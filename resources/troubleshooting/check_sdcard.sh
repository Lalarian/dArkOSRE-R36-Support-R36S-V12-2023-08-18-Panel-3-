#!/bin/bash

# SD Card and Mounted Filesystems Debug Script for RK3326 R36S Clone on dArkOS
# This script collects detailed information about mounted filesystems and inserted SD cards.
# It targets problems like the second SD card not being detected when inserted.
# Outputs to BOTH screen (/dev/tty1) and log file using tee.
# Logs to sd_card_debug.log in script dir (handles symlinks).
# Run from EmulationStation; no fixes or speed tests on raw devices – only safe checks.

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
LOGFILE="${SCRIPT_DIR}/sd_card_debug.log"

# Function to log to both screen and file with tee
log() {
    echo -e "$@" | tee -a "$LOGFILE" /dev/tty1
}

# Function to run commands and tee output to log and screen
run_cmd() {
    "$@" 2>&1 | tee -a "$LOGFILE" /dev/tty1
}

log "Starting mounted filesystems and SD card analysis..."
log "Timestamp: $(date)"
log "User: $(whoami)"
log "Hostname: $(hostname)"
run_cmd cat /proc/cpuinfo | grep -i 'model name\|hardware'

log "\n=== System Overview ==="
run_cmd uname -a
run_cmd cat /etc/os-release || log "No /etc/os-release found"

log "\n=== Kernel Command Line (for DTB/overlay info) ==="
run_cmd cat /proc/cmdline

log "\n=== Loaded Modules (lsmod | grep mmc/sd/storage) ==="
run_cmd lsmod | grep -iE 'mmc|sd|storage|disk|block|dwmmc|rockchip' || log "No matching modules found"

log "\n=== Full dmesg Output (kernel logs) ==="
run_cmd dmesg

log "\n=== Mounted Filesystems (mount) ==="
run_cmd mount || log "mount command failed"

log "\n=== Disk Usage (df -h) ==="
run_cmd df -h || log "df command failed"

log "\n=== Block Devices (lsblk -f) ==="
run_cmd lsblk -f || log "lsblk not found"

log "\n=== Disk UUIDs (blkid) ==="
sudo blkid | tee -a "$LOGFILE" /dev/tty1 2>&1 || log "blkid not found or sudo failed"

log "\n=== fstab Contents (/etc/fstab) ==="
run_cmd cat /etc/fstab || log "No /etc/fstab found"

log "\n=== SD Card Devices (/sys/block/mmc*) ==="
run_cmd ls -l /sys/block/mmc* || log "No SD card devices found in /sys/block"
for dev in /sys/block/mmc*; do
    if [ -d "$dev" ]; then
        log "SD Device: $dev"
        cat "$dev/device/name" "$dev/device/type" "$dev/device/vendor" "$dev/size" "$dev/removable" 2>&1 | tee -a "$LOGFILE" /dev/tty1
        log ""
    fi
done

log "\n=== Filesystem Check (quick dry run with fsck -n) ==="
for dev in $(lsblk -o NAME,MOUNTPOINT -n | awk '{if ($2 == "") print "/dev/" $1}'); do
    if [ -b "$dev" ]; then
        log "Quick checking $dev for errors (dry run, no fixes)..."
        sudo fsck -n "$dev" | tee -a "$LOGFILE" /dev/tty1 2>&1 || log "fsck failed for $dev (may be mounted or not a filesystem)"
        log ""
    fi
done

log "\n=== SD Card Speed Tests (read/write on mounted FS only) ==="
for sd in $(lsblk -o NAME,TYPE -n | grep -i 'mmc.*disk' | awk '{print $1}'); do
    PART=$(lsblk -o NAME,MOUNTPOINT -n | grep "^${sd}p.* /" | awk '{print $2}' | head -1)
    if [ -n "$PART" ] && [ -d "$PART" ]; then
        log "Speed testing SD $sd on mounted partition $PART (safe temp file test)..."
        TEST_FILE="$PART/tmp_speed_test.dat"
        log "Write test:"
        dd if=/dev/zero of="$TEST_FILE" bs=1M count=100 conv=fdatasync 2>&1 | tee -a "$LOGFILE" /dev/tty1
        log "Read test:"
        dd if="$TEST_FILE" of=/dev/null bs=1M count=100 2>&1 | tee -a "$LOGFILE" /dev/tty1
        rm -f "$TEST_FILE" >> "$LOGFILE" 2>&1
        log ""
    else
        log "No mounted partition for $sd; skipping speed test"
    fi
done

log "\n=== DTB Storage/SD-Related Info ==="
if [ -f /proc/device-tree/model ]; then
    log "Device Tree Model: $(cat /proc/device-tree/model)"
    find /proc/device-tree/ -name '*mmc*' -or -name '*sd*' -or -name '*storage*' -or -name '*disk*' -or -name '*dwmmc*' 2>&1 | tee -a "$LOGFILE" /dev/tty1
    for node in $(find /proc/device-tree/ -name '*mmc*' -or -name '*sd*' -or -name '*storage*' -or -name '*disk*' -or -name '*dwmmc*'); do
        if [ -d "$node" ]; then
            log "Node: $node"
            ls -l "$node" | tee -a "$LOGFILE" /dev/tty1
            for prop in $(ls "$node"); do
                if [ -f "$node/$prop" ]; then
                    log "  Prop $prop: $(cat "$node/$prop" 2>/dev/null || echo 'binary')"
                fi
            done
        fi
    done
fi
if command -v dtc >/dev/null 2>&1 && ls /boot/*.dtb >/dev/null 2>&1; then
    DTB_FILE=$(ls /boot/*.dtb | head -1)
    log "Decompiling $DTB_FILE for storage/SD nodes:"
    dtc -I dtb -O dts "$DTB_FILE" 2>/dev/null | grep -iE 'mmc|sd|storage|disk|dwmmc|regulator|power|domain|vcc|supply' | tee -a "$LOGFILE" /dev/tty1 || log "No storage/SD-related DTB nodes found"
else
    log "dtc not available or no DTB file found; install device-tree-compiler if needed"
fi