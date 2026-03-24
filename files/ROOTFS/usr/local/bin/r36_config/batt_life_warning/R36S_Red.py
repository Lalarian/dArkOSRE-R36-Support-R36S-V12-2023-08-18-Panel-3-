#!/usr/bin/env python3
"""
R36S - Always force RED LED on during discharge (all %)
Only for genuine units where GPIO 77 works reliably.
Minimal version - assumes pin is already exportable.
"""

import time

CAPACITY_PATH = "/sys/class/power_supply/battery/capacity"
STATUS_PATH   = "/sys/class/power_supply/battery/status"
LED_VAL = "/sys/class/gpio/gpio77/value"

def set_led(on: bool):
    try:
        with open(LED_VAL, "w") as f:
            f.write("1" if on else "0")
    except:
        pass  # silent fail - will retry next loop

# Assume pin is already exported & set to out (done by service start script or dtb hack)

while True:
    try:
        cap = int(open(CAPACITY_PATH).read().strip())
        status = open(STATUS_PATH).read().strip()
    except:
        time.sleep(10)
        continue

    if status in ["Charging", "Full"]:
        set_led(False)          # let PMIC/hardware handle charging light
    else:
        set_led(True)           # force red on, always, during use

    time.sleep(5)