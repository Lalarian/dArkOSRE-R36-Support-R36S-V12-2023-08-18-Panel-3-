#!/usr/bin/env python3
import os, time, datetime, subprocess, sys, glob

LOG_FILE = "/roms/r36_battery_cal.log"
VIDEO_PATH = "/usr/local/bin/r36_config/assets/Anira - Bad Apple.mp4"

def find_battery_path():
    for p in glob.glob("/sys/class/power_supply/*/"):
        if "bat" in p.lower():
            return p.rstrip("/")
    print("❌ No battery found in /sys/class/power_supply")
    sys.exit(1)

def read_sysfs(path):
    try:
        with open(path, "r") as f:
            return f.read().strip()
    except:
        return None

def is_fully_charged(bat_path):
    cap = read_sysfs(f"{bat_path}/capacity")
    status = read_sysfs(f"{bat_path}/status")
    voltage = read_sysfs(f"{bat_path}/voltage_now")
    if not cap or not voltage:
        return False
    cap = int(cap)
    volt = int(voltage) / 1_000_000.0
    if cap >= 98:
        return True
    if cap >= 95 and volt >= 4.00 and status in ("Full", "Not charging", "Charging"):
        return True
    return False

print("🔋 R36 Battery OCV Calibration – Discharge Test")
bat_path = find_battery_path()
print(f"   Battery path: {bat_path}")

if not is_fully_charged(bat_path):
    print("❌ Battery is NOT fully charged. Plug in charger and wait until 100%.")
    if "--force" not in sys.argv:
        sys.exit(1)
    print("   --force used → continuing anyway")

print("✅ Battery looks good – starting constant-load drain test")
print("🛑 Stopping EmulationStation now...")
subprocess.run(["sudo", "systemctl", "stop", "emulationstation"], check=True)

print("🎬 Launching video with sudo mediaplayer.sh...")
subprocess.Popen([
    "sudo", "/usr/local/bin/mediaplayer.sh",
    VIDEO_PATH
], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

print(f"📝 Logging every 5 seconds to {LOG_FILE} until device shuts down...")
with open(LOG_FILE, "w") as log:
    log.write("timestamp,capacity_percent,voltage_volts,status\n")
    while True:
        try:
            cap = int(read_sysfs(f"{bat_path}/capacity") or 0)
            volt_uv = int(read_sysfs(f"{bat_path}/voltage_now") or 0)
            status = read_sysfs(f"{bat_path}/status") or "unknown"
            volt_v = volt_uv / 1_000_000.0
            ts = datetime.datetime.now().isoformat()
            log.write(f"{ts},{cap},{volt_v},{status}\n")
            log.flush()
            print(f"{ts} | {cap:3}% | {volt_v:.3f} V | {status}")
            time.sleep(5)
        except Exception as e:
            print(f"Logging stopped: {e}")
            break
EOF
