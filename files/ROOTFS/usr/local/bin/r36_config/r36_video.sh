#!/bin/bash
# /usr/local/bin/r36_config/r36_video.sh
# Wrapper for video profile application 

RESOLUTION="${1:-640x480}"
PYTHON_SCRIPT="/usr/local/bin/r36_config/r36_video.py"

if [ ! -x "$PYTHON_SCRIPT" ]; then
    echo "Error: Python script not found or not executable" >&2
    exit 1
fi

python3 "$PYTHON_SCRIPT" "$RESOLUTION" 2>> /boot/darkosre_device.log