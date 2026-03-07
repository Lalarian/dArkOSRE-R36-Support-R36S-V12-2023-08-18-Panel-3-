#!/bin/bash

# Copyright (c) 2026 - Adapted for R36 Control
#
# Adapted from Wifi.sh by: southoz <retrooz@users.x.com>
# For customizing devices based on the hardware

sudo chmod 666 /dev/tty1
reset

# hide cursor
printf "\e[?25l" > /dev/tty1
dialog --clear

height="15"
width="55"

sudo setfont /usr/share/consolefonts/Lat7-TerminusBold22x11.psf.gz

pgrep -f gptokeyb | sudo xargs kill -9 2>/dev/null
printf "\033c" > /dev/tty1
printf "Starting R36 Control Centre. Please wait..." > /dev/tty1

old_ifs="$IFS"

# Hardware model
HARDWARE_MODEL=$(cat /proc/cpuinfo | grep -i '^hardware' | awk -F ': ' '{print $2}' | head -n 1)
[ -z "$HARDWARE_MODEL" ] && HARDWARE_MODEL="Unknown RK3326"

# Config file
CONFIG_FILE="/etc/r36_config.ini"

# Read current config values with proper defaults
VARIANT=$(sudo grep '^variant =' "$CONFIG_FILE" 2>/dev/null | awk -F' = ' '{print $2}' | tr -d '[:space:]' || echo "unknown")
CUR_SCRIPT=$(sudo grep '^active_script =' "$CONFIG_FILE" 2>/dev/null | awk -F' = ' '{print $2}' | tr -d '[:space:]' || echo "None")

# Gamma: default to 1.0 if missing or empty
CUR_GAMMA_RAW=$(sudo grep '^gamma =' "$CONFIG_FILE" 2>/dev/null | awk -F' = ' '{print $2}' | tr -d '[:space:]')
[ -z "$CUR_GAMMA_RAW" ] && CUR_GAMMA="1.0" || CUR_GAMMA="$CUR_GAMMA_RAW"

ExitMenu() {
  printf "\033c" > /dev/tty1
  pgrep -f gptokeyb | sudo xargs kill -9 2>/dev/null
  sudo setfont /usr/share/consolefonts/Lat7-Terminus20x10.psf.gz
  exit 0
}

SelectScript() {
  dialog --infobox "\nScanning scripts for $VARIANT ..." 5 $width > /dev/tty1
  sleep 1

  SCRIPT_DIR="/usr/local/bin/batt_life_warning"
  [ ! -d "$SCRIPT_DIR" ] && { dialog --msgbox "Directory $SCRIPT_DIR not found!" 6 $width; MainMenu; }

  case "$VARIANT" in
    clone)     PREFIX="Clone_" ;;
    soysauce)  PREFIX="SoySauce_" ;;
    r36s)      PREFIX="R36S_" ;;
    *)         PREFIX="" ;;
  esac

  mapfile -t scripts < <(ls -1 "$SCRIPT_DIR" 2>/dev/null | grep "^$PREFIX")

  if [ ${#scripts[@]} -eq 0 ]; then
    dialog --msgbox "No matching scripts found for $VARIANT" 6 $width
    MainMenu
  fi

  declare -a soptions=()
  for s in "${scripts[@]}"; do
    soptions+=("$s" ".")
  done

  while true; do
    choice=$(dialog --backtitle "Current: $CUR_SCRIPT" \
      --title "Select Battery LED Warning Type" \
      --no-collapse --clear --cancel-label "Back" \
      --menu "" $height $width 15 "${soptions[@]}" 2>&1 >/dev/tty1)

    [[ $? -ne 0 ]] && MainMenu

    dialog --infobox "Applying $choice ..." 5 $width

    sudo systemctl stop batt_led.service 2>/dev/null
    sleep 1
    sudo rm -f /usr/local/bin/batt_life_warning.py
    sudo cp "$SCRIPT_DIR/$choice" /usr/local/bin/batt_life_warning.py
    sudo chmod +x /usr/local/bin/batt_life_warning.py
    sudo systemctl start batt_led.service
    sleep 1

    if systemctl is-active --quiet batt_led.service; then
      msg="Successfully applied $choice"
      if sudo grep -q '^active_script =' "$CONFIG_FILE"; then
        sudo sed -i "s/^active_script =.*/active_script = $choice/" "$CONFIG_FILE"
      else
        echo "active_script = $choice" | sudo tee -a "$CONFIG_FILE" >/dev/null
      fi
      CUR_SCRIPT="$choice"
    else
      msg="Warning: batt_led.service failed to start"
    fi

    sudo sync
    dialog --infobox "$msg" 6 $width
    sleep 2
    MainMenu
  done
}

AdjustGamma() {
  dialog --infobox "Current gamma: $CUR_GAMMA\n\nChanges apply after reboot.\n\nUse R3 + D-Pad Left/Right for live preview." 8 $width
  sleep 2

  declare -a gamma_options=()
  for i in {4..18}; do
    int_part=$((i / 10))
    dec_part=$((i % 10))
    val="${int_part}.${dec_part}"
    gamma_options+=("$val" "$val")
  done

  choice=$(dialog --backtitle "Current gamma: $CUR_GAMMA" \
    --title "Select Gamma Value (0.4 – 1.8)" \
    --no-collapse --clear --cancel-label "Back" \
    --menu "Higher = brighter / washed out\nLower = darker / more contrast" \
    18 $width 12 "${gamma_options[@]}" 2>&1 >/dev/tty1)

  [[ $? -ne 0 ]] && MainMenu

  dialog --infobox "Setting gamma = $choice\n(Applies on next boot)" 6 $width

  if sudo grep -q '^gamma =' "$CONFIG_FILE"; then
    sudo sed -i "s/^gamma =.*/gamma = $choice/" "$CONFIG_FILE"
  else
    echo "gamma = $choice" | sudo tee -a "$CONFIG_FILE" >/dev/null
  fi
  sudo sync

  CUR_GAMMA="$choice"

  dialog --msgbox "Gamma updated to $choice\n\nReboot to apply permanently.\nLive test: hold R3 + D-Pad Left/Right" 10 $width
  MainMenu
}

UtilitiesMenu() {
  utils_options=(
    1 "View Current Config"
    2 "Delete Current Config (reboot to apply)"
    3 "Back"
  )

  while true; do
    uchoice=$(dialog --backtitle "R36 Control Centre: $HARDWARE_MODEL" \
      --title "Utilities" \
      --no-collapse --clear --cancel-label "Back" \
      --menu "" $height $width 10 "${utils_options[@]}" 2>&1 >/dev/tty1)

    [[ $? -ne 0 ]] && MainMenu

    case $uchoice in
      1)
        if [ -f "$CONFIG_FILE" ]; then
          content=$(sudo cat "$CONFIG_FILE")
          dialog --title "Current r36_config.ini" --msgbox "$content" 20 70
        else
          dialog --msgbox "No config file found." 6 $width
        fi
        ;;
      2)
        if dialog --title "Confirm Delete" --yesno "Delete /etc/r36_config.ini?\n\nIt will be regenerated with defaults on next boot." 10 $width; then
          sudo rm -f "$CONFIG_FILE"
          sudo sync
          dialog --msgbox "Config file deleted.\n\nDefaults will be restored on reboot." 7 $width
          # Refresh displayed values
          CUR_GAMMA="1.0"
          CUR_SCRIPT="None"
          MainMenu
        fi
        ;;
      3) MainMenu ;;
    esac
  done
}

MainMenu() {
  mainoptions=(
    1 "Select Battery LED Warning Type"
    2 "Adjust Gamma Correction"
    3 "Utilities"
    4 "Exit"
  )

  while true; do
    choice=$(dialog --backtitle "R36 Control Centre: $HARDWARE_MODEL" \
      --title "Main Menu" \
      --no-collapse --clear --cancel-label "Select + Start to Exit" \
      --menu "Current gamma: $CUR_GAMMA\nLED script: $CUR_SCRIPT" \
      $height $width 15 "${mainoptions[@]}" 2>&1 >/dev/tty1)

    [[ $? -ne 0 ]] && exit 1

    case $choice in
      1) SelectScript ;;
      2) AdjustGamma ;;
      3) UtilitiesMenu ;;
      4) ExitMenu ;;
    esac
  done
}

# Joystick setup
sudo chmod 666 /dev/uinput
export SDL_GAMECONTROLLERCONFIG_FILE="/opt/inttools/gamecontrollerdb.txt"
pgrep -f gptokeyb | sudo xargs kill -9 2>/dev/null
/opt/inttools/gptokeyb -1 "batt_led_control.sh" -c "/opt/inttools/keys.gptk" >/dev/null 2>&1 &

printf "\033c" > /dev/tty1
dialog --clear
trap ExitMenu EXIT
MainMenu