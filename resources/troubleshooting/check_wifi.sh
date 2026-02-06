#!/bin/bash

# WiFi Debug and Fix Script for RK3326 R36S Clone on dArkOS (Enhanced v2)
# Additions: Check module file existence, SDIO vendor/device ID detection,
# try alternative modules (brcmfmac, rtl8xxxu), tool install suggestions,
# deeper SDIO analysis.

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
LOGFILE="${SCRIPT_DIR}/wifi_debug_fix.log"
DTB_DUMP="${SCRIPT_DIR}/dtb_decompiled.dts"

echo "Starting enhanced WiFi system analysis and fix attempt (v2)..." | tee $LOGFILE
echo "Timestamp: $(date)" >> $LOGFILE
echo "User: $(whoami)" >> $LOGFILE
echo "Hostname: $(hostname)" >> $LOGFILE

echo "\n=== System Overview ===" >> $LOGFILE
uname -a >> $LOGFILE 2>&1
cat /etc/os-release >> $LOGFILE 2>&1 || echo "No /etc/os-release found" >> $LOGFILE

echo "\n=== Kernel Command Line (for DTB/overlay info) ===" >> $LOGFILE
cat /proc/cmdline >> $LOGFILE 2>&1

echo "\n=== Loaded Modules (lsmod | grep wifi/wlan/wireless/sdio/mmc/rtl/rockchip) ===" >> $LOGFILE
lsmod | grep -iE 'wifi|wlan|wireless|rtl|rockchip|brcm|ath|cfg80211|mac80211|sdio|mmc|ieee80211|rfkill' >> $LOGFILE 2>&1 || echo "No matching modules found" >> $LOGFILE

echo "\n=== Module File Existence Check (/lib/modules/$(uname -r)/) ===" >> $LOGFILE
KERNEL_DIR="/lib/modules/$(uname -r)"
find "$KERNEL_DIR" -name "*wifi*.ko*" -or -name "*80211*.ko*" -or -name "*rtl*.ko*" -or -name "*brcm*.ko*" -or -name "*ath*.ko*" 2>/dev/null >> $LOGFILE || echo "No WiFi-related module files found" >> $LOGFILE

echo "\n=== Full dmesg Output (kernel logs) ===" >> $LOGFILE
dmesg >> $LOGFILE 2>&1

echo "\n=== Filtered dmesg for WiFi-Related Messages (Deeper Grep) ===" >> $LOGFILE
dmesg | grep -iE 'wifi|wlan|wireless|rtl|rockchip|brcm|ath|cfg80211|mac80211|sdio|mmc|ieee80211|rfkill|firmware|error|fail|net|interface|phy|regulatory|country|antenna' >> $LOGFILE 2>&1 || echo "No WiFi-related dmesg entries" >> $LOGFILE

echo "\n=== SDIO Device ID Detection (if present) ===" >> $LOGFILE
if [ -d /sys/bus/sdio/devices ]; then
    for dev in /sys/bus/sdio/devices/*; do
        if [ -f "$dev/vendor" ] && [ -f "$dev/device" ]; then
            echo "SDIO Device: $(cat "$dev/vendor"):$(cat "$dev/device") at $dev" >> $LOGFILE
        fi
    done
else
    echo "No SDIO devices directory" >> $LOGFILE
fi

echo "\n=== Network Interfaces (ip link show) ===" >> $LOGFILE
ip link show >> $LOGFILE 2>&1 || echo "ip not found" >> $LOGFILE

echo "\n=== Wireless Interfaces (iwconfig) ===" >> $LOGFILE
if command -v iwconfig >/dev/null 2>&1; then
    iwconfig >> $LOGFILE 2>&1 || echo "iwconfig failed" >> $LOGFILE
else
    echo "iwconfig not available; install wireless-tools if needed" >> $LOGFILE
fi

echo "\n=== Wireless Status (/proc/net/wireless) ===" >> $LOGFILE
cat /proc/net/wireless >> $LOGFILE 2>&1 || echo "No /proc/net/wireless found" >> $LOGFILE

echo "\n=== RFKill Status (rfkill list) ===" >> $LOGFILE
if command -v rfkill >/dev/null 2>&1; then
    rfkill list >> $LOGFILE 2>&1 || echo "rfkill failed" >> $LOGFILE
else
    echo "rfkill not available" >> $LOGFILE
fi

echo "\n=== I2C/SDIO/MMC Devices (potential WiFi peripherals) ===" >> $LOGFILE
if command -v i2cdetect >/dev/null 2>&1; then
    for bus in $(ls /dev/i2c-* 2>/dev/null | sed 's/\/dev\/i2c-//'); do
        echo "I2C Bus $bus:" >> $LOGFILE
        i2cdetect -y $bus >> $LOGFILE 2>&1
    done
else
    echo "i2cdetect not available; install i2c-tools if needed" >> $LOGFILE
fi
ls -l /sys/class/mmc_host/* >> $LOGFILE 2>&1 || echo "No MMC hosts found" >> $LOGFILE
ls -l /sys/bus/sdio/devices/* >> $LOGFILE 2>&1 || echo "No SDIO devices found" >> $LOGFILE

echo "\n=== Firmware Directory Listing (/lib/firmware and subfolders - Recursive) ===" >> $LOGFILE
ls -R /lib/firmware >> $LOGFILE 2>&1 || echo "No /lib/firmware directory found" >> $LOGFILE

echo "\n=== Filtered Firmware for WiFi (grep in /lib/firmware) ===" >> $LOGFILE
find /lib/firmware -type f | grep -iE 'wifi|wlan|rtl|brcm|ath|rockchip|fw_|bin' >> $LOGFILE 2>&1 || echo "No WiFi-related firmware found" >> $LOGFILE

echo "\n=== DTB/Overlay Files in /boot/ ===" >> $LOGFILE
ls -l /boot/dt* /boot/overlay* /boot/*.dtb 2>/dev/null >> $LOGFILE || echo "No DTB/overlay files found in /boot/" >> $LOGFILE

echo "\n=== Current DTB Info (Deeper Analysis - Prioritizing Kernel DTB) ===" >> $LOGFILE
if [ -f /proc/device-tree/model ]; then
    echo "Device Tree Model: $(cat /proc/device-tree/model)" >> $LOGFILE
    find /proc/device-tree/ -name '*wifi*' -or -name '*wlan*' -or -name '*wireless*' -or -name '*rtl*' -or -name '*brcm*' -or -name '*sdio*' -or -name '*mmc*' -or -name '*pwrseq*' -or -name '*regulatory*' >> $LOGFILE 2>&1
    echo "\nDumping deeper /proc/device-tree WiFi nodes:" >> $LOGFILE
    for node in $(find /proc/device-tree/ -name '*wifi*' -or -name '*wlan*' -or -name '*wireless*' -or -name '*rtl*' -or -name '*brcm*' -or -name '*sdio*' -or -name '*mmc*' -or -name '*pwrseq*' -or -name '*regulatory*'); do
        if [ -d "$node" ]; then
            echo "Node: $node" >> $LOGFILE
            ls -l "$node" >> $LOGFILE
            for prop in $(ls "$node"); do
                if [ -f "$node/$prop" ]; then
                    echo "  Prop $prop: $(cat "$node/$prop" 2>/dev/null || echo 'binary')" >> $LOGFILE
                fi
            done
        fi
    done
fi
if command -v dtc >/dev/null 2>&1 && ls /boot/*.dtb >/dev/null 2>&1; then
    # Prioritize kernel DTB like rk3326-g80ca-linux.dtb over uboot ones
    DTB_FILE=$(ls /boot/rk3326-*.dtb 2>/dev/null | head -1)
    if [ -z "$DTB_FILE" ]; then
        DTB_FILE=$(ls /boot/*.dtb | grep -iv 'uboot' | head -1)  # Fallback, exclude uboot if possible
    fi
    if [ -z "$DTB_FILE" ]; then
        DTB_FILE=$(ls /boot/*.dtb | head -1)  # Ultimate fallback
    fi
    echo "Selected DTB for decomp: $DTB_FILE (prioritized kernel over uboot)" >> $LOGFILE
    echo "Decompiling $DTB_FILE fully to $DTB_DUMP for analysis..." >> $LOGFILE
    dtc -I dtb -O dts "$DTB_FILE" > "$DTB_DUMP" 2>> $LOGFILE
    if [ -f "$DTB_DUMP" ]; then
        echo "Full DTB decomp saved to $DTB_DUMP. Key WiFi excerpts:" >> $LOGFILE
        grep -iE 'wifi|wlan|wireless|rtl|brcm|ath|sdio|mmc|pwrseq|regulatory|compatible|phandle|interrupt|clock|reset|power|antenna' "$DTB_DUMP" >> $LOGFILE || echo "No WiFi-related DTB nodes found" >> $LOGFILE
    else
        echo "Failed to decompile DTB" >> $LOGFILE
    fi
else
    echo "dtc not available or no DTB file found; install device-tree-compiler if needed" >> $LOGFILE
fi

echo "\n=== WiFi Configuration Files ===" >> $LOGFILE
cat /etc/wpa_supplicant.conf >> $LOGFILE 2>&1 || echo "No /etc/wpa_supplicant.conf" >> $LOGFILE
cat /etc/NetworkManager/NetworkManager.conf >> $LOGFILE 2>&1 || echo "No NetworkManager.conf" >> $LOGFILE

# Suggest tool installs if missing
if ! command -v iwconfig >/dev/null; then echo "Suggestion: Install wireless-tools (sudo apt install wireless-tools)" >> $LOGFILE; fi
if ! command -v rfkill >/dev/null; then echo "Suggestion: Install rfkill (sudo apt install rfkill)" >> $LOGFILE; fi
if ! command -v iw >/dev/null; then echo "Suggestion: Install iw (sudo apt install iw)" >> $LOGFILE; fi
if ! command -v wpa_supplicant >/dev/null; then echo "Suggestion: Install wpasupplicant (sudo apt install wpasupplicant)" >> $LOGFILE; fi

echo "\n=== Attempting Fixes for WiFi (Expanded Modules) ===" >> $LOGFILE

if command -v rfkill >/dev/null 2>&1; then
    echo "Unblocking all RFKill..." >> $LOGFILE
    rfkill unblock all >> $LOGFILE 2>&1
fi

# Expanded module list
WIFI_MODULES="rtl8723bs rkwifi cfg80211 mac80211 brcmfmac rtl8xxxu ath9k"  # Added alternatives
for mod in $WIFI_MODULES; do
    if lsmod | grep -q $mod; then
        echo "Reloading module $mod..." >> $LOGFILE
        modprobe -r $mod >> $LOGFILE 2>&1
        modprobe $mod >> $LOGFILE 2>&1
    else
        echo "Loading module $mod if available..." >> $LOGFILE
        modprobe $mod >> $LOGFILE 2>&1 || echo "Module $mod not found or failed to load" >> $LOGFILE
    fi
done

# Bring up interface (existing, but add check for any 'wl*' or 'wlp*' variants)
WLAN_IF=$(ip link show | grep -oP '(wlan|wl|wlp)\S+' | head -1 || echo "wlan0")
if [ ! -z "$WLAN_IF" ]; then
    echo "Bringing up $WLAN_IF..." >> $LOGFILE
    ip link set $WLAN_IF up >> $LOGFILE 2>&1
else
    echo "No wlan/wl interface found" >> $LOGFILE
fi

echo "\n=== Loaded Modules After Fixes ===" >> $LOGFILE
lsmod | grep -iE 'wifi|wlan|wireless|rtl|rockchip|brcm|ath|cfg80211|mac80211|sdio|mmc|ieee80211|rfkill' >> $LOGFILE 2>&1

echo "\n=== Network Interfaces After Fixes ===" >> $LOGFILE
ip link show >> $LOGFILE 2>&1

# Test WiFi Scan
if [ ! -z "$WLAN_IF" ] && command -v iw >/dev/null 2>&1; then
    echo "Attempting WiFi scan on $WLAN_IF..." >> $LOGFILE
    iw dev $WLAN_IF scan | head -n 50 >> $LOGFILE 2>&1 || echo "WiFi scan failed; check if interface is up or regulatory domain set" >> $LOGFILE
else
    echo "iw not available or no wlan interface; install iw if needed" >> $LOGFILE
fi

# Test Connectivity (ping google.com)
echo "Testing connectivity (ping google.com -c 4)..." >> $LOGFILE
ping -c 4 google.com >> $LOGFILE 2>&1 || echo "Ping failed; WiFi may not be connected" >> $LOGFILE

echo "\n=== Journalctl WiFi Logs (if systemd) ===" >> $LOGFILE
if command -v journalctl >/dev/null 2>&1; then
    journalctl | grep -iE 'wifi|wlan|wireless|rtl|cfg80211|mac80211|sdio|mmc|net|interface|phy' | tail -n 100 >> $LOGFILE 2>&1
else
    echo "journalctl not available" >> $LOGFILE
fi

echo "\nEnhanced analysis and fix attempt complete. Log saved to $LOGFILE" | tee -a $LOGFILE
echo "DTB full decomp at $DTB_DUMP - Check for missing WiFi nodes (e.g., no 'wifi' or 'sdio' compatible)." >> $LOGFILE
echo "If WiFi still doesn't work:" >> $LOGFILE
echo "- Reboot and test connectivity." >> $LOGFILE
echo "- DTB mismatch likely: Try R36S-specific DTBs from https://github.com/AeolusUX/R36S-DTB or ArkOS repos." >> $LOGFILE
echo "- Ensure firmware in /lib/firmware (e.g., rtl_bt/rtl8723bs_fw.bin for RTL8723BS)." >> $LOGFILE
echo "- Manually: modprobe rtl8723bs; ip link set wlan0 up; iw wlan0 scan" >> $LOGFILE
echo "- If errors in dmesg (e.g., firmware load fail), check /lib/firmware paths or patch DTB for pwrseq/compatibles." >> $LOGFILE
echo "- If SDIO ID is 0x024c:0xb723, confirm RTL8723BS and compile driver if modules missing." >> $LOGFILE