#!/usr/bin/env python3
"""
Genuine R36S - Always Red LED when discharging (all battery %)
GPIO 77 (GPIO2 PB5): 1 = red LED on
Aggressive reset to fight DTB/PMIC lock after reboot
"""

import os
import time

CAPACITY_PATH = "/sys/class/power_supply/battery/capacity"
STATUS_PATH   = "/sys/class/power_supply/battery/status"

LED_GPIO = 77
LED_DIR  = f"/sys/class/gpio/gpio{LED_GPIO}/direction"
LED_VAL  = f"/sys/class/gpio/gpio{LED_GPIO}/value"

def reset_pin():
    try:
        os.system(f"echo {LED_GPIO} > /sys/class/gpio/unexport 2>/dev/null")
        time.sleep(0.5)
        os.system(f"echo {LED_GPIO} > /sys/class/gpio/export")
        time.sleep(0.5)
        with open(LED_DIR, "w") as f:
            f.write("out")
        print("Pin reset successful")
        return True
    except Exception as e:
        print(f"Pin reset failed: {e}")
        return False

def set_led(on: bool):
    try:
        value = "1" if on else "0"
        with open(LED_VAL, "w") as f:
            f.write(value)
        print(f"Red LED set to {'ON' if on else 'OFF'}")
        return True
    except Exception as e:
        print(f"Set failed: {e}")
        reset_pin()           # Retry reset
        time.sleep(1)
        try:
            with open(LED_VAL, "w") as f:
                f.write(value)
            print("Retry succeeded")
            return True
        except:
            print("Retry also failed - DTB/PMIC lock likely")
            return False

def release_led():
    try:
        with open(LED_DIR, "w") as f:
            f.write("in")
        print("Released LED control to PMIC")
    except:
        pass

# ── Initial setup ─────────────────────────────────
reset_pin()
release_led()   # Start safe

prev_status = ""

while True:
    try:
        cap = int(open(CAPACITY_PATH).read().strip())
        status = open(STATUS_PATH).read().strip()
    except:
        release_led()
        time.sleep(10)
        continue

    # Only act when status changes
    if status == prev_status:
        time.sleep(5)
        continue

    prev_status = status

    if status in ["Charging", "Full"]:
        release_led()
        print(f"Charging/Full ({cap}%) → LED released to PMIC")
    else:
        # ALWAYS force red LED on when discharging - all percentages
        set_led(on=True)
        print(f"Discharging ({cap}%) → Red LED FORCED ON")

    time.sleep(5)