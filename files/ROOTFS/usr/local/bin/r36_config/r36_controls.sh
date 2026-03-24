#!/bin/bash
SCHEME="${1:-default}"
PYTHON_SCRIPT="/usr/local/bin/r36_config/r36_controls.py"

if [ ! -x "$PYTHON_SCRIPT" ]; then
    echo "Error: Python script not found or not executable" >&2
    exit 1
fi

python3 "$PYTHON_SCRIPT" "$SCHEME" 2>> /boot/darkosre_device.log