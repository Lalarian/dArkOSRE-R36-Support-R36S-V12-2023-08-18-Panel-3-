#!/bin/bash
# /usr/local/bin/r36_config.sh
# Early boot: detect hardware → select correct battery LED warning script → apply if needed
# Handles gamma setting every boot (persistent in config.ini, default from devices.ini)
# Writes current gamma to /dev/shm/CURRENT_GAMMA every boot (volatile runtime file)

set -euo pipefail

CONFIG_FILE="/etc/r36_config.ini"
DEVICES_FILE="/boot/dtb/r36_devices.ini"
SCRIPT_DIR="/usr/local/bin/batt_life_warning"
TARGET_LINK="/usr/local/bin/batt_life_warning.py"
LOG_FILE="/boot/darkosre_device.log"
GAMMA_BIN="/usr/local/bin/gamma"

# Logging helper - to file + kernel log for early visibility
log() {
    local msg="$(date '+%Y-%m-%d %H:%M:%S') [r36_config] $*"
    echo "$msg" >> "$LOG_FILE" 2>/dev/null || true
    echo "$msg" > /dev/kmsg 2>/dev/null || true
}

# Skip if forced, but always run hardware detection and gamma
log "Early boot LED variant + gamma config starting..."

# ────────────────────────────────────────────────
# Hardware detection (always run)
# ────────────────────────────────────────────────
HARDWARE_RAW=$(grep -i '^Hardware' /proc/cpuinfo | awk -F': ' '{print $2}' | head -n1 | sed 's/^[ \t]*//;s/[ \t]*$//')
[ -z "$HARDWARE_RAW" ] && HARDWARE_RAW="Unknown RK3326"
log "Hardware string: '$HARDWARE_RAW'"

HARDWARE_NORM=$(echo "$HARDWARE_RAW" | tr '[:upper:]' '[:lower:]' | sed 's/^[ \t]*//;s/[ \t]*$//')

# ────────────────────────────────────────────────
# Variant lookup function
# ────────────────────────────────────────────────
lookup_variant() {
    local orig="$1" norm="$2"
    local variant=""

    # Exact match
    while IFS= read -r line; do
        if [[ "$line" =~ ^\[([^]]+)\] ]]; then
            local sec="${BASH_REMATCH[1]}"
            local sec_norm=$(echo "$sec" | tr '[:upper:]' '[:lower:]' | sed 's/^[ \t]*//;s/[ \t]*$//')
            if [ "$sec_norm" = "$norm" ]; then
                variant=$(sed -n "/^\[$sec\]/,/^\[/ s/^variant[ \t]*=[ \t]*//p" "$DEVICES_FILE" | head -1 | xargs)
                [ -n "$variant" ] && echo "$variant" && return 0
            fi
        fi
    done < "$DEVICES_FILE"

    # Partial match
    while IFS= read -r line; do
        if [[ "$line" =~ ^\[([^]]+)\] ]]; then
            local sec="${BASH_REMATCH[1]}"
            local sec_norm=$(echo "$sec" | tr '[:upper:]' '[:lower:]' | sed 's/^[ \t]*//;s/[ \t]*$//')
            if echo "$norm" | grep -q "$sec_norm"; then
                variant=$(sed -n "/^\[$sec\]/,/^\[/ s/^variant[ \t]*=[ \t]*//p" "$DEVICES_FILE" | head -1 | xargs)
                [ -n "$variant" ] && echo "$variant" && return 0
            fi
        fi
    done < "$DEVICES_FILE"

    echo "unknown"
}

VARIANT=$(lookup_variant "$HARDWARE_RAW" "$HARDWARE_NORM")
log "Determined variant: $VARIANT"

# ────────────────────────────────────────────────
# LED handling - run on first boot or hardware change
# ────────────────────────────────────────────────
NEEDS_LED_UPDATE=0
if [ ! -f "$CONFIG_FILE" ]; then
    NEEDS_LED_UPDATE=1
    log "Config file missing (first boot) - performing full LED setup"
else
    CURRENT_HARDWARE=$(grep '^hardware[ \t]*=' "$CONFIG_FILE" | cut -d'=' -f2 | xargs || echo "")
    if [ "$CURRENT_HARDWARE" != "$HARDWARE_RAW" ]; then
        NEEDS_LED_UPDATE=1
        log "Hardware change detected: '$CURRENT_HARDWARE' → '$HARDWARE_RAW' - updating LED"
    else
        log "No hardware change - skipping LED update"
    fi
fi

if [ "$NEEDS_LED_UPDATE" = "1" ]; then
    # LED script selection
    case "$VARIANT" in
        r36s)     SELECTED="R36S_Green_30_Red.py" ;;
        soysauce) SELECTED="SoySauce_Blue_30_Pink_10_Red.py" ;;
        unknown)  SELECTED="Clone_PMIC_Controlled.py" ;;
        *)        SELECTED="Clone_Blue_30_Purple_10_Red.py" ;;
    esac

    SELECTED_PATH="$SCRIPT_DIR/$SELECTED"
    log "Selected LED script: $SELECTED"

    rm -f "$TARGET_LINK" 2>/dev/null || true
    if [ -f "$SELECTED_PATH" ]; then
        if cp "$SELECTED_PATH" "$TARGET_LINK" 2>>"$LOG_FILE"; then
            chmod +x "$TARGET_LINK" 2>>"$LOG_FILE" || log "chmod failed"
            log "Copied and made executable: $SELECTED"
        else
            log "ERROR: cp failed - source: $SELECTED_PATH"
        fi
    else
        log "CRITICAL: Source script missing: $SELECTED_PATH"
    fi

    # Robust config write with fallback
    log "Starting config write"
    TMP_CONFIG=$(mktemp /tmp/r36_config.XXXXXX 2>/dev/null) || log "mktemp failed - using fallback direct write"
    if [ -n "$TMP_CONFIG" ]; then
        # Heredoc to temp
        cat > "$TMP_CONFIG" <<EOF || { log "heredoc to temp failed"; rm -f "$TMP_CONFIG"; TMP_CONFIG=""; }
[Device]
hardware = $HARDWARE_RAW
variant = $VARIANT
config_version = 1.0
active_script = $SELECTED
EOF
        if [ -s "$TMP_CONFIG" ]; then
            mv "$TMP_CONFIG" "$CONFIG_FILE" && sync && log "Config written via temp: $CONFIG_FILE"
            chmod 666 "$CONFIG_FILE" 2>/dev/null || log "WARNING: Failed to set 666 perms on $CONFIG_FILE"
            log "Set permissions on $CONFIG_FILE to 666 (readable/writable by all)"
        else
            log "ERROR: Temp config empty - falling back"
            rm -f "$TMP_CONFIG"
            TMP_CONFIG=""
        fi
    fi

    # Fallback: direct echo if temp failed
    if [ -z "$TMP_CONFIG" ]; then
        log "Using fallback direct config write"
        > "$CONFIG_FILE"  # Truncate
        echo "[Device]" >> "$CONFIG_FILE" || log "echo failed for section"
        echo "hardware = $HARDWARE_RAW" >> "$CONFIG_FILE" || log "echo failed for hardware"
        echo "variant = $VARIANT" >> "$CONFIG_FILE" || log "echo failed for variant"
        echo "config_version = 1.0" >> "$CONFIG_FILE" || log "echo failed for version"
        echo "active_script = $SELECTED" >> "$CONFIG_FILE" || log "echo failed for script"
        sync
        if [ -s "$CONFIG_FILE" ]; then
            log "Fallback config written: $CONFIG_FILE"
            chmod 666 "$CONFIG_FILE" 2>/dev/null || log "WARNING: Failed to set 666 perms on $CONFIG_FILE"
            log "Set permissions on $CONFIG_FILE to 666 (readable/writable by all)"
        else
            log "CRITICAL: Even fallback config write failed"
        fi
    fi
fi

# ────────────────────────────────────────────────
# Gamma handling – runs EVERY boot
# ────────────────────────────────────────────────
GAMMA_VALUE=""
GAMMA_SOURCE=""

# 1. Check config.ini first (persistent override)
if [ -f "$CONFIG_FILE" ]; then
    GAMMA_VALUE=$(grep '^gamma[ \t]*=' "$CONFIG_FILE" | cut -d'=' -f2 | xargs || true)
    [ -n "$GAMMA_VALUE" ] && GAMMA_SOURCE="config.ini (persistent)"
fi

# 2. Fallback to devices.ini (variant default) if no value in config
if [ -z "$GAMMA_VALUE" ] && [ -f "$DEVICES_FILE" ]; then
    # Exact hardware section
    GAMMA_VALUE=$(sed -n "/^\[$HARDWARE_RAW\]/,/^\[/ s/^gamma[ \t]*=[ \t]*//p" "$DEVICES_FILE" | head -1 | xargs)
    [ -n "$GAMMA_VALUE" ] && GAMMA_SOURCE="devices.ini (exact match)"

    # Partial match if no exact
    if [ -z "$GAMMA_VALUE" ]; then
        GAMMA_VALUE=$(sed -n "/^\[.*$HARDWARE_NORM.*\]/,/^\[/ s/^gamma[ \t]*=[ \t]*//p" "$DEVICES_FILE" | head -1 | xargs)
        [ -n "$GAMMA_VALUE" ] && GAMMA_SOURCE="devices.ini (partial match)"
    fi
fi

# Apply gamma if we have a value and binary exists
if [ -n "$GAMMA_VALUE" ] && [ -x "$GAMMA_BIN" ]; then
    log "Applying gamma $GAMMA_VALUE (from $GAMMA_SOURCE)"
    if "$GAMMA_BIN" -s "$GAMMA_VALUE" 2>>"$LOG_FILE"; then
        log "Gamma applied successfully: $GAMMA_VALUE"
    else
        log "ERROR: gamma command failed (value=$GAMMA_VALUE)"
    fi

    # Save/update gamma in config.ini for persistence (if not already there)
    if [ -f "$CONFIG_FILE" ]; then
        if grep -q '^gamma[ \t]*=' "$CONFIG_FILE"; then
            sed -i "s/^gamma[ \t]*=.*/gamma = $GAMMA_VALUE/" "$CONFIG_FILE" || log "sed replace failed"
        else
            echo "gamma = $GAMMA_VALUE" >> "$CONFIG_FILE" || log "append gamma failed"
            log "Gamma appended to config.ini"
        fi
        sync
        log "Gamma persisted to $CONFIG_FILE"
    fi
else
    log "No gamma value defined or gamma binary not found → skipping"
fi

# Write current gamma to /dev/shm/CURRENT_GAMMA (volatile runtime) every boot
if [ -n "$GAMMA_VALUE" ]; then
    echo "$GAMMA_VALUE" > /dev/shm/CURRENT_GAMMA
    chmod 666 /dev/shm/CURRENT_GAMMA 2>/dev/null || log "WARNING: Failed to set 666 perms on /dev/shm/CURRENT_GAMMA"
    log "Wrote gamma $GAMMA_VALUE to /dev/shm/CURRENT_GAMMA (perms 666)"
fi

log "Early LED + gamma config complete."
exit 0