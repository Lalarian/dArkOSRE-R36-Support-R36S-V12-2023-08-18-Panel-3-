#!/usr/bin/env python3
import os
import re
import subprocess
import sys
import glob
import shutil
from datetime import datetime

LOG_FILE = "/roms/r36_battery_cal.log"
BACKUP_DIR = "/boot/dtb/backups"

# === EDIT THESE FOR YOUR EXACT DEVICE ===
DTB_LINUX = "/boot/dtbs/rockchip/rk3326-r36s-linux.dtb"
DTB_UBOOT = "/boot/*-uboot.dtb"          # glob pattern

os.makedirs(BACKUP_DIR, exist_ok=True)

def log(msg):
    print(f"[{datetime.now().strftime('%H:%M:%S')}] {msg}")

def parse_log():
    if not os.path.exists(LOG_FILE):
        log(f"❌ Calibration log not found: {LOG_FILE}")
        sys.exit(1)

    lines = [line.strip().split(",") for line in open(LOG_FILE) if line.strip() and not line.startswith("timestamp")]
    if len(lines) < 10:
        log("❌ Log file too short for calibration")
        sys.exit(1)

    data = []
    for ts, cap, volt, status in lines:
        try:
            t = datetime.fromisoformat(ts)
            data.append((t, float(volt)))
        except:
            continue

    if len(data) < 10:
        log("❌ Not enough valid data points")
        sys.exit(1)

    start_t = data[0][0]
    total_seconds = (data[-1][0] - start_t).total_seconds()

    points = []
    for i in range(21):                     # 0% to 100% in 5% steps
        target_pct = i * 5
        target_sec = total_seconds * (100 - target_pct) / 100.0

        for j in range(len(data)-1):
            t1, v1 = data[j]
            t2, v2 = data[j+1]
            s1 = (t1 - start_t).total_seconds()
            s2 = (t2 - start_t).total_seconds()
            if s1 <= target_sec <= s2:
                frac = (target_sec - s1) / (s2 - s1)
                v = v1 + frac * (v2 - v1)
                points.append(int(v * 1_000_000))   # microvolts for DTB
                break

    log(f"✅ Generated 21-point linear OCV table from {len(data)} log points")
    return points

def decompile_dtb(dtb_path, dts_path):
    log(f"Decompiling {dtb_path}")
    subprocess.run(["dtc", "-I", "dtb", "-O", "dts", "-o", dts_path, dtb_path], check=True)

def recompile_dtb(dts_path, dtb_path):
    log(f"Recompiling {dtb_path}")
    subprocess.run(["dtc", "-I", "dts", "-O", "dtb", "-o", dtb_path, dts_path], check=True)

def patch_ocv_table(dts_path, new_ocv_values):
    with open(dts_path, "r") as f:
        dts = f.read()

    values_str = " ".join(f"0x{v:08x}" for v in new_ocv_values)
    pattern = r'(ocv_table|ocv-capacity-table-0)\s*=\s*<[^>]+>;'
    replacement = f'\\1 = <{values_str}>;'

    dts_new = re.sub(pattern, replacement, dts, flags=re.IGNORECASE)

    if dts_new == dts:
        log("⚠️ Could not find ocv_table in DTB – check node name")
        return False

    with open(dts_path, "w") as f:
        f.write(dts_new)

    log(f"✅ Patched OCV table with {len(new_ocv_values)} values")
    return True

def process_dtb(dtb_glob, label):
    files = glob.glob(dtb_glob)
    if not files:
        log(f"⚠️ No {label} DTB found for pattern: {dtb_glob}")
        return

    for dtb_path in files:
        log(f"🔧 Processing {label}: {dtb_path}")
        backup = f"{BACKUP_DIR}/{os.path.basename(dtb_path)}.{datetime.now():%Y%m%d-%H%M%S}"
        shutil.copy2(dtb_path, backup)

        dts = dtb_path + ".dts"
        decompile_dtb(dtb_path, dts)

        if patch_ocv_table(dts, parse_log()):
            recompile_dtb(dts, dtb_path)
            log(f"✅ {label} DTB successfully updated")
        else:
            log(f"❌ Failed to patch {label} DTB")

        if os.path.exists(dts):
            os.unlink(dts)

# ========================= MAIN =========================
if __name__ == "__main__":
    print("🔋 R36 Battery OCV Calibration Tool")
    print("====================================")

    new_table = parse_log()
    print(f"Generated linear OCV table with {len(new_table)} points")

    process_dtb(DTB_LINUX, "Linux kernel")
    process_dtb(DTB_UBOOT, "U-Boot")

    print("\n🎉 Done! All DTBs updated.")
    print(f"Original DTBs backed up to: {BACKUP_DIR}")
    print("Reboot the device for the new battery curve to take effect.")
