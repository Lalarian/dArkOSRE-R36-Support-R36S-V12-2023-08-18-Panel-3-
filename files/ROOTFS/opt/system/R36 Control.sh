#!/bin/bash
# Copyright (c) 2026 - Adapted for R36 Control
#
# Adapted from Wifi.sh by: southoz <retrooz@users.x.com>
# For customizing devices based on the hardware
# Full ALSA audio controls + control scheme selection added

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

# Audio defaults
CUR_ALSA_PATH=$(sudo grep '^alsa_path =' "$CONFIG_FILE" 2>/dev/null | awk -F' = ' '{print $2}' | tr -d '[:space:]' || echo "SPK_HP")
CUR_ALSA_VOLUME=$(sudo grep '^alsa_volume =' "$CONFIG_FILE" 2>/dev/null | awk -F' = ' '{print $2}' | tr -d '[:space:]' || echo "")

# Control scheme
CUR_CONTROL_SCHEME=$(sudo grep '^control_scheme =' "$CONFIG_FILE" 2>/dev/null | awk -F' = ' '{print $2}' | tr -d '[:space:]' || echo "default")

ExitMenu() {
  printf "\033c" > /dev/tty1
  pgrep -f gptokeyb | sudo xargs kill -9 2>/dev/null
  sudo setfont /usr/share/consolefonts/Lat7-Terminus20x10.psf.gz
  exit 0
}

SelectScript() {
  dialog --infobox "\nScanning scripts for $VARIANT ..." 5 $width > /dev/tty1
  sleep 1

  SCRIPT_DIR="/usr/local/bin/r36_config/batt_life_warning"
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

AudioMenu() {
  audio_options=(
    1 "Select ALSA Playback Path (SPK_HP / SPK)"
    2 "Manage Boot Volume (set / clear)"
    3 "Back"
  )

  while true; do
    current_vol_display="${CUR_ALSA_VOLUME:-Manual}"
    [ -n "$CUR_ALSA_VOLUME" ] && current_vol_display="${current_vol_display}%"

    achoice=$(dialog --backtitle "R36 Control Centre: $HARDWARE_MODEL" \
      --title "Audio Controls" \
      --no-collapse --clear --cancel-label "Back" \
      --menu "Current path: $CUR_ALSA_PATH\nCurrent boot volume: $current_vol_display" \
      $height $width 10 "${audio_options[@]}" 2>&1 >/dev/tty1)

    [[ $? -ne 0 ]] && MainMenu

    case $achoice in
      1) SelectALSAPath ;;
      2) SetBootVolume ;;
      3) MainMenu ;;
    esac
  done
}

SelectALSAPath() {
  declare -a path_options=(
    "SPK_HP" "Speaker + Headphone jack detection"
    "SPK"    "Speaker only"
  )

  choice=$(dialog --backtitle "Current: $CUR_ALSA_PATH" \
    --title "Select ALSA Playback Path" \
    --no-collapse --clear --cancel-label "Back" \
    --menu "SPK_HP = full jack sensing\nSPK = speaker only" \
    12 $width 8 "${path_options[@]}" 2>&1 >/dev/tty1)

  [[ $? -ne 0 ]] && AudioMenu

  dialog --infobox "Applying $choice ..." 5 $width

  if sudo grep -q '^alsa_path =' "$CONFIG_FILE"; then
    sudo sed -i "s/^alsa_path =.*/alsa_path = $choice/" "$CONFIG_FILE"
  else
    echo "alsa_path = $choice" | sudo tee -a "$CONFIG_FILE" >/dev/null
  fi

  sudo amixer -c 0 cset iface=MIXER,name='Playback Path' "$choice" >/dev/null 2>&1

  sudo systemctl stop ogage.service 2>/dev/null
  if [ "$choice" = "SPK" ]; then
    sudo cp /usr/local/bin/r36_config/ogage/ogage.SPK /usr/local/bin/ogage
  else
    sudo cp /usr/local/bin/r36_config/ogage/ogage.SPK_HP /usr/local/bin/ogage
  fi
  sudo chmod +x /usr/local/bin/ogage
  sudo systemctl start ogage.service

  sudo sync
  CUR_ALSA_PATH="$choice"

  dialog --msgbox "ALSA path set to $choice\nogage updated & service restarted" 8 $width
  AudioMenu
}

SetBootVolume() {
  current_vol_display="${CUR_ALSA_VOLUME:-Manual}"
  [ -n "$CUR_ALSA_VOLUME" ] && current_vol_display="${current_vol_display}%"

  declare -a vol_options=()
  vol_options+=("Clear" "Disable persistent boot volume (use normal volume controls)")
  for i in {10..100..5}; do
    vol_options+=("$i%" "$i%")
  done

  choice=$(dialog --backtitle "Current: $current_vol_display" \
    --title "Manage Boot Volume" \
    --no-collapse --clear --cancel-label "Back" \
    --menu "Choose a persistent boot volume or CLEAR to let normal volume controls take over" \
    22 $width 20 "${vol_options[@]}" 2>&1 >/dev/tty1)

  [[ $? -ne 0 ]] && AudioMenu

  if [ "$choice" = "Clear" ]; then
    dialog --infobox "Clearing alsa_volume from config..." 5 $width
    sudo sed -i '/^alsa_volume[ \t]*=/d' "$CONFIG_FILE" 2>/dev/null || true
    sudo sync
    CUR_ALSA_VOLUME=""
    dialog --msgbox "Boot volume enforcement CLEARED.\n\nr36_config.sh will no longer override volume on boot.\nUse normal volume controls." 10 $width
    AudioMenu
    return
  fi

  vol_num="${choice%\%}"
  dialog --infobox "Setting boot volume to $choice ..." 5 $width

  if sudo grep -q '^alsa_volume =' "$CONFIG_FILE"; then
    sudo sed -i "s/^alsa_volume =.*/alsa_volume = $vol_num/" "$CONFIG_FILE"
  else
    echo "alsa_volume = $vol_num" | sudo tee -a "$CONFIG_FILE" >/dev/null
  fi
  sudo sync

  sudo amixer -c 0 -M sset 'Playback' "$choice" >/dev/null 2>&1

  CUR_ALSA_VOLUME="$vol_num"

  dialog --msgbox "Boot volume set to $choice%\n(Will be applied every boot)" 8 $width
  AudioMenu
}

SelectControlScheme() {
  dialog --infobox "\nSelecting control scheme for your device..." 5 $width

  declare -a ctrl_options=(
    "default"      "Default R36 Controls (Function Button → emulators menu)"
    "no_function"  "No Function Button (R36H style)"
  )

  choice=$(dialog --backtitle "Current: $CUR_CONTROL_SCHEME" \
    --title "Select Control Scheme" \
    --no-collapse --clear --cancel-label "Back" \
    --menu "R36H devices must use 'no_function'" \
    12 $width 8 "${ctrl_options[@]}" 2>&1 >/dev/tty1)

  [[ $? -ne 0 ]] && UtilitiesMenu

  dialog --infobox "Applying $choice ..." 5 $width

  # Run the script cleanly to get real exit status (no redirection here)
  sudo /usr/local/bin/r36_config/r36_controls.sh "$choice"
  status=$?

  # Log output in a separate invocation that we don't care if it fails
  sudo /usr/local/bin/r36_config/r36_controls.sh "$choice" >> /boot/darkosre_device.log 2>&1 || true

  # Add explicit menu-level logging for visibility
  log_msg="$(date '+%Y-%m-%d %H:%M:%S') [R36 Control] Applied control scheme: $choice (status $status)"
  echo "$log_msg" >> /boot/darkosre_device.log 2>/dev/null || true

  if [ $status -eq 0 ]; then
    msg="Successfully applied $choice"
  else
    msg="Warning: r36_controls.sh exited with status $status (but script ran)"
  fi

  if sudo grep -q '^control_scheme =' "$CONFIG_FILE"; then
    sudo sed -i "s/^control_scheme =.*/control_scheme = $choice/" "$CONFIG_FILE"
  else
    echo "control_scheme = $choice" | sudo tee -a "$CONFIG_FILE" >/dev/null
  fi
  sudo sync

  CUR_CONTROL_SCHEME="$choice"

  dialog --msgbox "$msg\n\nControl scheme set to $choice\n(Reboot recommended for full effect)" 10 $width
  UtilitiesMenu
}

UtilitiesMenu() {
  utils_options=(
    1 "View Current Config"
    2 "Delete Current Config (reboot to apply)"
    3 "Select Control Scheme"
    4 "Back"
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
          CUR_GAMMA="1.0"
          CUR_SCRIPT="None"
          CUR_ALSA_PATH="SPK_HP"
          CUR_ALSA_VOLUME=""
          CUR_CONTROL_SCHEME="default"
          MainMenu
        fi
        ;;
      3) SelectControlScheme ;;
      4) MainMenu ;;
    esac
  done
}

MainMenu() {
  mainoptions=(
    1 "Select Battery LED Warning Type"
    2 "Adjust Gamma Correction"
    3 "Audio Controls"
    4 "Utilities"
    5 "Exit"
  )

  while true; do
    vol_display="${CUR_ALSA_VOLUME:-Manual}"
    [ -n "$CUR_ALSA_VOLUME" ] && vol_display="${vol_display}%"

    choice=$(dialog --backtitle "R36 Control Centre: $HARDWARE_MODEL" \
      --title "Main Menu" \
      --no-collapse --clear --cancel-label "Select + Start to Exit" \
      --menu "Current gamma: $CUR_GAMMA\nLED script: $CUR_SCRIPT\nALSA path: $CUR_ALSA_PATH\nBoot volume: $vol_display\nControl scheme: $CUR_CONTROL_SCHEME" \
      $height $width 15 "${mainoptions[@]}" 2>&1 >/dev/tty1)

    [[ $? -ne 0 ]] && exit 1

    case $choice in
      1) SelectScript ;;
      2) AdjustGamma ;;
      3) AudioMenu ;;
      4) UtilitiesMenu ;;
      5) ExitMenu ;;
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