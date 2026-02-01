#!/bin/bash

CURRENT_DIR=$(pwd)

sudo tar -xvf /roms/ports/update-01242026.tar.gz -C / --no-same-owner > /dev/tty1 2>&1
sudo chown ark:ark /etc/emulationstation/es_systems.cfg
sudo chmod 755 /etc/emulationstation/es_systems.cfg
sudo chown ark:ark /opt/system/ZRam\ Manager.sh
sudo chmod 755 /opt/system/ZRam\ Manager.sh
sudo chown ark:ark /opt/system/Advanced/Switch\ to\ SD2\ for\ Roms.sh
sudo chmod 755 /opt/system/Advanced/Switch\ to\ SD2\ for\ Roms.sh
sudo chown root:root /usr/local/bin/Switch\ to\ SD2\ for\ Roms.sh
sudo chmod 777 /usr/local/bin/Switch\ to\ SD2\ for\ Roms.sh
sudo rm /boot/rk3326-rg351mp-linux.dtb
if [ -f "/opt/system/Advanced/Switch to Main SD for Roms.sh" ]; then
   sudo rm "/opt/system/Advanced/Switch to SD2 for Roms.sh" > /dev/tty1 2>&1
fi
  
rm -rf $CURRENT_DIR/update-01242026.tar.gz > /dev/tty1 2>&1
rm -rf $CURRENT_DIR/Update-01242026.sh > /dev/tty1 2>&1
sleep 5
sudo reboot > /dev/tty1 2>&1

