#!/usr/bin/env bash

# NextUI init
# Resolve paths relative to this script
PAK_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PAK_NAME=$(basename -- "$0")
PAK_NAME=${PAK_NAME%.*}

# Shared userdata home for this pak (fallback to $HOME/.userdata if not provided)
SHARED_USERDATA_ROOT=${SHARED_USERDATA_PATH:-"$HOME/.userdata"}
export HOME="$SHARED_USERDATA_ROOT/$PAK_NAME"
mkdir -p "$HOME"

# Resolve logging location (fallback to shared userdata logs directory)
LOG_ROOT=${LOGS_PATH:-"$SHARED_USERDATA_ROOT/logs"}
mkdir -p "$LOG_ROOT"

GAMEDIR="$PAK_DIR/.ports/pokemmo"

# Avoid spaces in paths for westonwrap's unquoted eval/cd usage
ORIG_GAMEDIR="$GAMEDIR"
SAFE_GAMEDIR="/tmp/pokemmo"
if [ ! -L "$SAFE_GAMEDIR" ] || [ "$(readlink "$SAFE_GAMEDIR" 2>/dev/null)" != "$ORIG_GAMEDIR" ]; then
  rm -rf "$SAFE_GAMEDIR"
  ln -s "$ORIG_GAMEDIR" "$SAFE_GAMEDIR" 2>/dev/null || true
fi
if [ -L "$SAFE_GAMEDIR" ]; then
  GAMEDIR="$SAFE_GAMEDIR"
fi

# Setup logging - write early debug info directly to log file
LOGFILE="$LOG_ROOT/$PAK_NAME.txt"
echo "========================================" > "$LOGFILE"
echo "PokeMMO Launch - $(date)" >> "$LOGFILE"
echo "========================================" >> "$LOGFILE"
echo "PAK_DIR: $PAK_DIR" >> "$LOGFILE"
echo "GAMEDIR: $GAMEDIR" >> "$LOGFILE"
echo "PWD: $(pwd)" >> "$LOGFILE"
echo "========================================" >> "$LOGFILE"

# PortMaster preamble
XDG_DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}
if [ -n "$EMU_DIR" ] && [ -f "$EMU_DIR/control.txt" ]; then
  controlfolder="$EMU_DIR"
elif [ -d "/opt/system/Tools/PortMaster/" ]; then
  controlfolder="/opt/system/Tools/PortMaster"
elif [ -d "/opt/tools/PortMaster/" ]; then
  controlfolder="/opt/tools/PortMaster"
elif [ -d "$XDG_DATA_HOME/PortMaster/" ]; then
  controlfolder="$XDG_DATA_HOME/PortMaster"
else
  controlfolder="/roms/ports/PortMaster"
fi

source $controlfolder/control.txt

# We source custom mod files from the portmaster folder example mod_jelos.txt which containts pipewire fixes
[ -f "${controlfolder}/mod_${CFW_NAME}.txt" ] && source "${controlfolder}/mod_${CFW_NAME}.txt"

# Add PortMaster bin directory to PATH (provides python3, 7zzs, etc.)
PM_BIN_DIR="$controlfolder/../bin"
if [ -d "$PM_BIN_DIR" ]; then
  export PATH="$PM_BIN_DIR:$PATH"
fi

get_controls

java_runtime="zulu17.48.15-ca-jdk17.0.10-linux"
weston_runtime="weston_pkg_0.2"
mesa_runtime="mesa_pkg_0.1"

if [[ -z "$GPTOKEYB2" ]]; then
  pm_message "This port requires the latest PortMaster to run, please go to https://portmaster.games/ for more info."
  sleep 5
  exit 1
fi

echo "$GAMEDIR"
> "$GAMEDIR/log.txt" && exec > >(tee -a "$GAMEDIR/log.txt" "$LOGFILE") 2>&1

cd "$GAMEDIR"

echo RELEASE
cat "$GAMEDIR/RELEASE"

#echo Dump CFW info
#$controlfolder/device_info.txt 2> /dev/null

echo ls -l "${GAMEDIR}"
ls -l "${GAMEDIR}"

# Check if we need to use westonpack. If we have mainline OpenGL, we don't need to use it.
if glxinfo | grep -q "OpenGL version string"; then
    westonpack=0
else
    westonpack=1
fi

# Ensure /run/udev has the actual udev database (TrimUI keeps it at /tmp/run/udev).
# Use bind-mount instead of replacing the directory so nothing is written to /run.
if [ -d /tmp/run/udev/data ] && [ ! -d /run/udev/data ]; then
  if [ -L /run/udev ]; then
    # Already a symlink (previous run or system) — works as-is
    :
  elif [ -d /run/udev ]; then
    $ESUDO mount --bind /tmp/run/udev /run/udev
  fi
fi

# Ensure input devices are tagged for Weston/libinput (TrimUI udev lacks input_id helper).
# Rules are written under /tmp; the bind-mount (or existing symlink) makes them
# visible at /run/udev/rules.d/ where udevadm expects them.
mkdir -p /tmp/run/udev/rules.d
echo 'SUBSYSTEM=="input", KERNEL=="event*", TAG+="seat", ENV{ID_SEAT}="seat0", ENV{ID_INPUT}="1", ENV{ID_INPUT_KEYBOARD}="1", ENV{ID_INPUT_JOYSTICK}="1", ENV{ID_INPUT_MOUSE}="1"' > /tmp/run/udev/rules.d/99-seat-input.rules
udevadm control --reload-rules || true
udevadm trigger --subsystem-match=input --action=add
udevadm settle

# On normal exit: remove the rule and re-trigger so the power button works again
# (hard crashes / power loss are already covered since /run is tmpfs)
cleanup_udev() {
  rm -f /tmp/run/udev/rules.d/99-seat-input.rules
  udevadm control --reload-rules 2>/dev/null || true
  udevadm trigger --subsystem-match=input --action=add 2>/dev/null || true
  # Remove udev and suspend bind-mounts if still in place
  umount /run/udev 2>/dev/null || true
  umount /mnt/SDCARD/.system/tg5040/bin/suspend 2>/dev/null || true
  rm -f /tmp/pokemmo_real_suspend /tmp/pokemmo_suspend_wrapper
}
trap cleanup_udev EXIT

# ---- NextUI splash progress via show2.elf ----
SHOW2_BIN="${SYSTEM_PATH:-/mnt/SDCARD/.system/tg5040}/bin/show2.elf"
SHOW2_FIFO="/tmp/show2.fifo"
SHOW2_LOGO="${SDCARD_PATH:-/mnt/SDCARD}/.system/res/logo.png"
SHOW2_PID=""
SPLASH_WATCHDOG_PID=""
SPLASH_TAILER_PID=""

splash_send() { [ -p "$SHOW2_FIFO" ] && echo "$1" > "$SHOW2_FIFO"; }

start_splash() {
  # Kill any lingering show2 from a previous run
  pkill -f show2.elf 2>/dev/null || true
  rm -f "$SHOW2_FIFO"
  sleep 0.1

  if [ ! -x "$SHOW2_BIN" ]; then
    echo "show2.elf not found, skipping splash"
    return
  fi

  LD_LIBRARY_PATH="/usr/trimui/lib:${LD_LIBRARY_PATH}" \
    "$SHOW2_BIN" --mode=daemon \
    --image="$SHOW2_LOGO" \
    --bgcolor=0x000000 \
    --fontcolor=0xFFFFFF \
    --text="Launching PokeMMO..." \
    --logoheight=128 \
    --progressy=90 &
  SHOW2_PID=$!

  # Wait for FIFO to appear
  local _n=0
  while [ ! -p "$SHOW2_FIFO" ] && [ $_n -lt 40 ]; do
    sleep 0.05
    _n=$((_n + 1))
  done

  splash_send "PROGRESS:-1"
  splash_send "TEXT:Starting..."

  # Watchdog: hard timeout after 120s
  (
    sleep 120
    echo "PROGRESS:100" > "$SHOW2_FIFO" 2>/dev/null || true
    echo "TEXT:Launch timed out" > "$SHOW2_FIFO" 2>/dev/null || true
    sleep 0.5
    echo "QUIT" > "$SHOW2_FIFO" 2>/dev/null || true
  ) &
  SPLASH_WATCHDOG_PID=$!

  # Background log tailer
  (
    # Wait for game log to appear
    while [ ! -f "$GAMEDIR/log.txt" ]; do
      kill -0 "$SPLASH_WATCHDOG_PID" 2>/dev/null || exit 0
      sleep 0.2
    done

    last_pct=-1
    tail -n 0 -F "$GAMEDIR/log.txt" 2>/dev/null | while IFS= read -r line; do
      kill -0 "$SPLASH_WATCHDOG_PID" 2>/dev/null || break
      case "$line" in
        *"Starting Weston"*)
          [ $last_pct -lt 5 ] && { splash_send "PROGRESS:5"; splash_send "TEXT:Starting display server..."; last_pct=5; } ;;
        *"Running your command"*)
          [ $last_pct -lt 10 ] && { splash_send "PROGRESS:10"; splash_send "TEXT:Launching client..."; last_pct=40; } ;;
        *"Initialized logger"*)
          [ $last_pct -lt 20 ] && { splash_send "PROGRESS:50"; splash_send "TEXT:Initializing..."; last_pct=80; } ;;
        *"Starting PokeMMO Client"*)
          [ $last_pct -lt 90 ] && { splash_send "PROGRESS:90"; splash_send "TEXT:Starting PokeMMO..."; last_pct=90; } ;;
        *"Initializing cursor"*)
          # Xwayland is taking over the display — kill show2 to avoid framebuffer fighting
          splash_send "QUIT"
          kill "$SHOW2_PID" 2>/dev/null || true
          break ;;
      esac
    done
  ) &
  SPLASH_TAILER_PID=$!
}

stop_splash() {
  kill "$SPLASH_TAILER_PID" 2>/dev/null || true
  kill "$SPLASH_WATCHDOG_PID" 2>/dev/null || true
  splash_send "QUIT" 2>/dev/null || true
  sleep 0.2
  kill "$SHOW2_PID" 2>/dev/null || true
  rm -f "$SHOW2_FIFO"
}

if [ "$westonpack" -eq 1 ]; then

# Mount Weston runtime
weston_dir=/tmp/weston
$ESUDO mkdir -p "${weston_dir}"
if [ ! -f "$controlfolder/libs/${weston_runtime}.squashfs" ]; then
  if [ ! -f "$controlfolder/harbourmaster" ]; then
    pm_message "This port requires the latest PortMaster to run, please go to https://portmaster.games/ for more info."
    sleep 5
    exit 1
  fi
  $ESUDO $controlfolder/harbourmaster --quiet --no-check runtime_check "${weston_runtime}.squashfs"
fi
if [[ "$PM_CAN_MOUNT" != "N" ]]; then
    $ESUDO umount "${weston_dir}"
fi
$ESUDO mount -t squashfs -o loop "$controlfolder/libs/${weston_runtime}.squashfs" "${weston_dir}"
echo ls -l ${weston_dir}
ls -l ${weston_dir}

# Patch westonwrap (copy out of squashfs) to avoid gptokeyb kill-signal behavior
WESTONWRAP="/tmp/westonwrap_pokemmo.sh"
if [ -f "$weston_dir/westonwrap.sh" ]; then
  cp "$weston_dir/westonwrap.sh" "$WESTONWRAP"
  # Fix shebang: /bin/bash may not exist; use env lookup instead
  sed -i '1s|^#!/bin/bash|#!/usr/bin/env bash|' "$WESTONWRAP"
  # Ensure the wrapper still points to the mounted runtime
  sed -i 's|^export weston_dir=.*|export weston_dir="/tmp/weston"|' "$WESTONWRAP"
  awk '
    BEGIN { skip=0 }
    /^check_gptokeyb\\(\\)/ { print "check_gptokeyb(){ :; }"; skip=1; next }
    skip && /^}/ { skip=0; next }
    skip { next }
    { gsub(/gptokeyb_used=1/, "gptokeyb_used=0"); print }
  ' "$WESTONWRAP" > /tmp/westonwrap_pokemmo.tmp && mv -f /tmp/westonwrap_pokemmo.tmp "$WESTONWRAP"
  chmod +x "$WESTONWRAP"
fi

# Mount Mesa runtime
mesa_dir=/tmp/mesa
$ESUDO mkdir -p "${mesa_dir}"
if [ ! -f "$controlfolder/libs/${mesa_runtime}.squashfs" ]; then
  if [ ! -f "$controlfolder/harbourmaster" ]; then
    pm_message "This port requires the latest PortMaster to run, please go to https://portmaster.games/ for more info."
    sleep 5
    exit 1
  fi
  $ESUDO $controlfolder/harbourmaster --quiet --no-check runtime_check "${mesa_runtime}.squashfs"
fi
if [[ "$PM_CAN_MOUNT" != "N" ]]; then
    $ESUDO umount "${mesa_dir}"
fi
$ESUDO mount -t squashfs -o loop "$controlfolder/libs/${mesa_runtime}.squashfs" "${mesa_dir}"
echo ls -l ${mesa_dir}
ls -l ${mesa_dir}

# Provide EGL/GLES for Xwayland. Prefer bundled overrides, fall back to Mesa runtime.
mesa_lib_src="/tmp/mesa/lib/aarch64-linux-gnu"
mesa_lib_dst="/tmp/pokemmo_libs"
override_lib_src="$GAMEDIR/lib_override"
mkdir -p "$mesa_lib_dst"
if [ -d "$override_lib_src" ]; then
  cp -f "$override_lib_src"/* "$mesa_lib_dst"/ 2>/dev/null || true
fi
if [ -d "$mesa_lib_src" ]; then
  if [ ! -f "$mesa_lib_dst/libEGL.so.1" ] && [ -f "$mesa_lib_src/libEGL_mesa.so.0.0.0" ]; then
    cp -f "$mesa_lib_src/libEGL_mesa.so.0.0.0" "$mesa_lib_dst/libEGL.so.1"
  fi
  if [ ! -f "$mesa_lib_dst/libGLESv2.so.2" ] && [ -f "$mesa_lib_src/libGLESv2.so.2.0.0" ]; then
    cp -f "$mesa_lib_src/libGLESv2.so.2.0.0" "$mesa_lib_dst/libGLESv2.so.2"
  fi
fi
export LD_LIBRARY_PATH="$mesa_lib_dst:$LD_LIBRARY_PATH"

# LWJGL native overrides (custom build)
LWJGL_OVERRIDE_DIR="$GAMEDIR/lwjgl_override"
LWJGL_TMP_DIR="/tmp/pokemmo_lwjgl"
if [ -d "$LWJGL_OVERRIDE_DIR" ]; then
  rm -rf "$LWJGL_TMP_DIR"
  mkdir -p "$LWJGL_TMP_DIR"
  cp -f "$LWJGL_OVERRIDE_DIR"/*.so "$LWJGL_TMP_DIR"/ 2>/dev/null || true
  export LD_LIBRARY_PATH="$LWJGL_TMP_DIR:$LD_LIBRARY_PATH"
fi

fi

# Mount Java runtime
export JAVA_HOME="/tmp/javaruntime/"
$ESUDO mkdir -p "${JAVA_HOME}"
if [ ! -f "$controlfolder/libs/${java_runtime}.squashfs" ]; then
  if [ ! -f "$controlfolder/harbourmaster" ]; then
    pm_message "This port requires the latest PortMaster to run, please go to https://portmaster.games/ for more info."
    sleep 5
    exit 1
  fi
  $ESUDO $controlfolder/harbourmaster --quiet --no-check runtime_check "${java_runtime}.squashfs"
fi
if [[ "$PM_CAN_MOUNT" != "N" ]]; then
    $ESUDO umount "${JAVA_HOME}"
fi
$ESUDO mount -t squashfs -o loop "$controlfolder/libs/${java_runtime}.squashfs" "${JAVA_HOME}"
export PATH="$JAVA_HOME/bin:$PATH"

echo ls -l ${JAVA_HOME}
ls -l ${JAVA_HOME}


# Ensure Python 3 is available (prefer bundled PortMaster python3 on PATH)
if command -v python3 >/dev/null 2>&1; then
  echo "Python3 found: $(command -v python3) ($(python3 --version))"
elif command -v python >/dev/null 2>&1 && (( $(python -c 'import sys; print(sys.version_info[0])') >= 3 )); then
  echo "Python found: $(command -v python) ($(python --version))"
else
  echo "ERROR: No Python 3 interpreter found on PATH"
  echo "PATH=$PATH"
fi

if [ ! -f "credentials.txt" ]; then
  mv credentials.template.txt credentials.txt
fi

# Fixed: Home screen freezing
rm pokemmo_crash_*.log
rm hs_err_pid*

export SDL_GAMECONTROLLERCONFIG="$sdl_controllerconfig"

$ESUDO chmod +x "$GAMEDIR/controller_info.$DEVICE_ARCH"
$ESUDO chmod +x "$GAMEDIR/menu/launch_menu.$DEVICE_ARCH"

echo INFO CONTROLLER
"$GAMEDIR/controller_info.$DEVICE_ARCH"
echo $SDL_GAMECONTROLLERCONFIG

if [[ -n "$ESUDO" ]]; then
    ESUDO="$ESUDO LD_LIBRARY_PATH=$controlfolder"
fi

# MENU
$GPTOKEYB2 "launch_menu" -c "./menu/controls.ini" &
"$GAMEDIR/menu/launch_menu.$DEVICE_ARCH" "$GAMEDIR/menu/menu.items" "$GAMEDIR/menu/FiraCode-Regular.ttf"

# Capture the exit code
selection=$?

if [ -f "$GAMEDIR/controller.map" ]; then
    echo load controller.map
    export SDL_GAMECONTROLLERCONFIG="$(cat "$GAMEDIR/controller.map")"
    echo $SDL_GAMECONTROLLERCONFIG
fi

env_vars=""
LAUNCH_GAME=0

# Check what was selected
case $selection in
    0)
        pm_finish

        if [[ "$PM_CAN_MOUNT" != "N" ]]; then
          if [ "$westonpack" -eq 1 ]; then
            $ESUDO umount "${weston_dir}"
            $ESUDO umount "${mesa_dir}"
          fi
          $ESUDO umount "${JAVA_HOME}"
        fi

        exit 2
        ;;
    1)
        echo "[MENU] ERROR"
        pm_finish

        if [[ "$PM_CAN_MOUNT" != "N" ]]; then
          if [ "$westonpack" -eq 1 ]; then
            $ESUDO umount "${weston_dir}"
            $ESUDO umount "${mesa_dir}"
          fi
          $ESUDO umount "${JAVA_HOME}"
        fi

        exit 1
        ;;
    2)
        echo "[MENU] PokeMMO"
        LAUNCH_GAME=1
        cat data/mods/console_mod/dync/theme.xml > data/mods/console_mod/console/theme.xml

        client_ui_theme=$(grep -E '^client.ui.theme=' config/main.properties | cut -d'=' -f2)

        sed -i 's/^client\.gui\.scale\.guiscale=.*/client.gui.scale.guiscale=1.0/' config/main.properties
        sed -i 's/^client\.gui\.hud\.hotkeybar\.y=.*/client.gui.hud.hotkeybar.y=0/' config/main.properties
        sed -i 's/^client\.ui\.theme\.mobile=.*/client.ui.theme\.mobile=false/' config/main.properties

        sed -i 's/is_mobile="true"/is_mobile="false"/' data/mods/console_mod/info.xml
        ;;
    3)
        echo "[MENU] PokeMMO Android"
        LAUNCH_GAME=1
        cat data/mods/console_mod/dync/theme.android.xml > data/mods/console_mod/console/theme.xml

        client_ui_theme=$(grep -E '^client.ui.theme=' config/main.properties | cut -d'=' -f2)

        sed -i 's/^client\.gui\.scale\.guiscale=.*/client.gui.scale.guiscale=1.8/' config/main.properties
        sed -i 's/^client\.gui\.scale\.hidpifont=.*/client.gui.scale.hidpifont=true/' config/main.properties
        sed -i 's/^client\.ui\.theme\.mobile=.*/client.ui.theme\.mobile=true/' config/main.properties

        sed -i 's/is_mobile="false"/is_mobile="true"/' data/mods/console_mod/info.xml
        ;;
    4)
        echo "[MENU] PokeMMO Small"
        LAUNCH_GAME=1
        cat data/mods/console_mod/dync/theme.small.xml > data/mods/console_mod/console/theme.xml

        client_ui_theme=$(grep -E '^client.ui.theme=' config/main.properties | cut -d'=' -f2)

        sed -i 's/^client\.gui\.scale\.guiscale=.*/client.gui.scale.guiscale=1.4/' config/main.properties
        sed -i 's/^client\.gui\.hud\.hotkeybar\.y=.*/client.gui.hud.hotkeybar.y=0/' config/main.properties
        sed -i 's/^client\.ui\.theme\.mobile=.*/client.ui.theme\.mobile=false/' config/main.properties

        sed -i 's/is_mobile="true"/is_mobile="false"/' data/mods/console_mod/info.xml
        ;;
    5)
        echo "[MENU] PokeMMO Update"
        rm -rf /tmp/launch_menu.trace

        # Launch progress display, then kill gptokeyb to prevent input interference
        "$GAMEDIR/menu/launch_menu.$DEVICE_ARCH" "$GAMEDIR/menu/menu.items" "$GAMEDIR/menu/FiraCode-Regular.ttf" --trace &
        sleep 0.3
        pkill -9 gptokeyb2 2>/dev/null || true

        # Download missing PortMaster runtimes (WiFi is available at this point)
        if [ -f "$controlfolder/harbourmaster" ]; then
          for _rt in "$weston_runtime" "$mesa_runtime" "$java_runtime"; do
            if [ ! -f "$controlfolder/libs/${_rt}.squashfs" ]; then
              echo "Downloading runtime: ${_rt}..." > /tmp/launch_menu.trace
              "$controlfolder/harbourmaster" --quiet --no-check runtime_check "${_rt}.squashfs" || true
            fi
          done
        fi

        if [ ! -f "main.properties" ]; then
          cp config/main.properties main.properties
        fi
        echo "Downloading update..." > /tmp/launch_menu.trace
        curl -L https://pokemmo.com/download_file/1/ -o _pokemmo.zip 2>> /tmp/launch_menu.trace
        if [ ! -f "patch.zip" ]; then
          cp patch_applied.zip patch.zip
        fi
        echo "Extracting update..." >> /tmp/launch_menu.trace
        unzip -o _pokemmo.zip >> /tmp/launch_menu.trace 2>&1
        rm _pokemmo.zip
        rm -f PokeMMO.sh

        echo "Generating PATCHES" >> /tmp/launch_menu.trace
        sleep 1
        echo __END__ >> /tmp/launch_menu.trace
        ;;
    6)
        echo "[MENU] PokeMMO Restore"
        cp patch_applied.zip patch.zip
        rm -rf config/main.properties main.properties
        "$GAMEDIR/menu/launch_menu.$DEVICE_ARCH" "$GAMEDIR/menu/menu.items" "$GAMEDIR/menu/FiraCode-Regular.ttf" --show "PokeMMO Restored"
        pm_finish

        if [[ "$PM_CAN_MOUNT" != "N" ]]; then
          if [ "$westonpack" -eq 1 ]; then
            $ESUDO umount "${weston_dir}"
            $ESUDO umount "${mesa_dir}"
          fi
          $ESUDO umount "${JAVA_HOME}"
        fi

        exit 0
        ;;
    7)
        echo "[MENU] PokeMMO Restore Mods"
        rm -rf data/mods/
        cp patch_applied.zip patch.zip
        "$GAMEDIR/menu/launch_menu.$DEVICE_ARCH" "$GAMEDIR/menu/menu.items" "$GAMEDIR/menu/FiraCode-Regular.ttf" --show "Restored Mods"
        pm_finish

        if [[ "$PM_CAN_MOUNT" != "N" ]]; then
          if [ "$westonpack" -eq 1 ]; then
            $ESUDO umount "${weston_dir}"
            $ESUDO umount "${mesa_dir}"
          fi
          $ESUDO umount "${JAVA_HOME}"
        fi

        exit 0
        ;;
    *)
        echo "[MENU] Unknown option: $selection"
        LAUNCH_GAME=1
        cat data/mods/console_mod/dync/theme.xml > data/mods/console_mod/console/theme.xml

        client_ui_theme=$(grep -E '^client.ui.theme=' config/main.properties | cut -d'=' -f2)

        sed -i 's/^client\.gui\.scale\.guiscale=.*/client.gui.scale.guiscale=1.0/' config/main.properties
        sed -i 's/^client\.gui\.scale\.hidpifont=.*/client.gui.scale.hidpifont=true/' config/main.properties
        sed -i 's/^client\.gui\.hud\.hotkeybar\.y=.*/client.gui.hud.hotkeybar.y=0/' config/main.properties
        sed -i 's/^client\.ui\.theme\.mobile=.*/client.ui.theme\.mobile=false/' config/main.properties

        sed -i 's/is_mobile="true"/is_mobile="false"/' data/mods/console_mod/info.xml
        ;;
esac

echo KILL launch_menu
echo "ps -eo user,pid,args | grep '[g]ptokeyb2' | grep 'launch_menu'"
echo $(ps -eo user,pid,args | grep '[g]ptokeyb2' | grep 'launch_menu')
__pids=$(ps -eo user,pid,args | grep '[g]ptokeyb2' | grep 'launch_menu' | awk '{print $2}')
echo [$__pids]

if [ -n "$__pids" ]; then
  echo "KILL: $__pids"
  $ESUDO kill $__pids
fi

echo ESUDO=$ESUDO
echo env_vars=$env_vars

# Start NextUI splash progress for game launches
if [ "$LAUNCH_GAME" -eq 1 ]; then
  start_splash
fi

if [ -f "patch.zip" ]; then
  rm -rf /tmp/launch_menu.trace
  EXTRACT_DIR="/tmp/pokemmo_extract"
  rm -rf f com "$EXTRACT_DIR" _mods f.jar loader.jar /tmp/pokemmo_jars "$GAMEDIR/jars" src/auto
  if [ ! -f "main.properties" ]; then
    cp config/main.properties main.properties
  fi
  if [ ! -f "theme.xml" ]; then
    cp data/mods/console_mod/console/theme.xml theme.xml
  fi
  cp -rf data/mods _mods

  # Launch progress display, then kill gptokeyb to prevent input interference
  "$GAMEDIR/menu/launch_menu.$DEVICE_ARCH" "$GAMEDIR/menu/menu.items" "$GAMEDIR/menu/FiraCode-Regular.ttf" --trace &
  sleep 0.3
  pkill -9 gptokeyb2 2>/dev/null || true

  echo "Extracting patch.zip..." > /tmp/launch_menu.trace
  unzip -o patch.zip >> /tmp/launch_menu.trace 2>&1
  echo "Extracting classes from PokeMMO.exe..." >> /tmp/launch_menu.trace
  # Use 7z with -tzip to handle Launch4j EXE format (auto-detects ZIP offset)
  # -aoa: overwrite all existing files without prompt
  "$controlfolder/../bin/7zzs.aarch64" x -tzip -y -aoa -o"$EXTRACT_DIR" PokeMMO.exe "f/*" "com/badlogic/gdx/controllers/desktop/*" >> /tmp/launch_menu.trace 2>&1
  mv patch.zip patch_applied.zip
  mv main.properties config/main.properties
  mv theme.xml data/mods/console_mod/console/theme.xml
  cp -rf _mods/* data/mods
  rm -rf _mods
  for file in "$EXTRACT_DIR"/f/*.class; do
    echo "[CHECKING] $file" >> /tmp/launch_menu.trace
    if grep -q -a "client.ui.login.username" "$file"; then
      echo "[MATCH] $file" >> /tmp/launch_menu.trace
      class_name="${file%.class}"
      class_name="${class_name#"$EXTRACT_DIR"/}"
      class_name="${class_name//\//.}"
      break
    fi
  done
  # Build JARs on tmpfs to avoid exFAT case-insensitivity issues
  JAR_DIR="/tmp/pokemmo_jars"
  rm -rf "$JAR_DIR"
  mkdir -p "$JAR_DIR"

  echo "Generating f.jar" >> /tmp/launch_menu.trace
  rm -rf credentials.javap.txt jamepad.javap.txt
  echo "class_name $class_name" >> /tmp/launch_menu.trace
  javap -v -classpath "$EXTRACT_DIR" "$class_name" > credentials.javap.txt
  javap -v -classpath "$EXTRACT_DIR" com.badlogic.gdx.controllers.desktop.JamepadControllerManager > jamepad.javap.txt
  echo jar cf "$JAR_DIR/f.jar" -C "$EXTRACT_DIR" f >> /tmp/launch_menu.trace
  jar cf "$JAR_DIR/f.jar" -C "$EXTRACT_DIR" f
  echo "Generating loader.jar" >> /tmp/launch_menu.trace
  if command -v python &>/dev/null; then
    PYTHON_CMD=python
  elif command -v python3 &>/dev/null; then
    PYTHON_CMD=python3
  else
    echo "Error: Neither 'python' nor 'python3' command found." >&2
    exit 1
  fi
  echo "Found Python interpreter: $PYTHON_CMD"
  echo "Using interpreter: $PYTHON_CMD" >> /tmp/launch_menu.trace
  $PYTHON_CMD --version >> /tmp/launch_menu.trace
  mkdir -p src/auto
  $PYTHON_CMD parse_javap.py >> /tmp/launch_menu.trace 2>&1
  if [ $? -ne 0 ]; then
    echo "ERROR: parse_javap.py failed!" >> /tmp/launch_menu.trace
    echo "ERROR: parse_javap.py failed!" >&2
  fi
  # Verify credential class was generated
  CRED_CLASS=$(find src/auto/f -name "*.java" -type f | head -n 1)
  if [ -z "$CRED_CLASS" ]; then
    echo "ERROR: Credential class was not generated in src/auto/f/" >> /tmp/launch_menu.trace
    echo "ERROR: Credential class was not generated in src/auto/f/" >&2
  else
    echo "Generated credential class: $CRED_CLASS" >> /tmp/launch_menu.trace
  fi
  mkdir -p out
  # Use find to get all Java files recursively from src/auto (includes src/auto/f credential class)
  AUTO_JAVA_FILES=$(find src/auto -name "*.java" 2>/dev/null | tr '\n' ' ')
  echo "Auto-generated Java files: $AUTO_JAVA_FILES" >> /tmp/launch_menu.trace
  echo javac -d out/ -cp "$JAR_DIR/f.jar:libs/*" src/*.java $AUTO_JAVA_FILES >> /tmp/launch_menu.trace
  javac -d out/ -cp "$JAR_DIR/f.jar:libs/*" src/*.java $AUTO_JAVA_FILES 2>> /tmp/launch_menu.trace
  if [ $? -ne 0 ]; then
    echo "ERROR: javac compilation failed!" >> /tmp/launch_menu.trace
    echo "ERROR: javac compilation failed!" >&2
  fi
  cp -rf src/com/* out/com
  echo "Contents of out/ after compilation:" >> /tmp/launch_menu.trace
  ls -R out >> /tmp/launch_menu.trace 2>&1
  # Verify the credential class was compiled
  CRED_CLASS_COUNT=$(find out/f -name "*.class" -type f 2>/dev/null | wc -l)
  if [ "$CRED_CLASS_COUNT" -eq 0 ]; then
    echo "ERROR: Credential class was not compiled in out/f/" >> /tmp/launch_menu.trace
    echo "ERROR: Credential class was not compiled in out/f/" >&2
  else
    echo "Compiled $CRED_CLASS_COUNT credential class(es) in out/f/" >> /tmp/launch_menu.trace
  fi
  ls -R src
  echo jar cf "$JAR_DIR/loader.jar" -C "$GAMEDIR/out" f -C "$GAMEDIR/out" org -C "$GAMEDIR/out" com >> /tmp/launch_menu.trace
  jar cf "$JAR_DIR/loader.jar" -C "$GAMEDIR/out" f -C "$GAMEDIR/out" org -C "$GAMEDIR/out" com
  # Verify the JAR contains the credential class
  echo "Verifying loader.jar contents:" >> /tmp/launch_menu.trace
  unzip -l "$JAR_DIR/loader.jar" | grep "f/" >> /tmp/launch_menu.trace 2>&1
  rm -rf out
  # Persist JARs to SD card so they survive reboot without re-patching
  mkdir -p "$GAMEDIR/jars"
  cp "$JAR_DIR/f.jar" "$GAMEDIR/jars/f.jar"
  cp "$JAR_DIR/loader.jar" "$GAMEDIR/jars/loader.jar"
  sleep 1
  echo __END__ >> /tmp/launch_menu.trace
fi

JAR_DIR="/tmp/pokemmo_jars"
# After reboot the tmpfs JARs are gone; restore from persistent storage
if [ ! -f "$JAR_DIR/loader.jar" ] && [ -f "$GAMEDIR/jars/loader.jar" ]; then
  echo "Restoring JARs from persistent storage..."
  mkdir -p "$JAR_DIR"
  cp "$GAMEDIR/jars/f.jar" "$JAR_DIR/f.jar"
  cp "$GAMEDIR/jars/loader.jar" "$JAR_DIR/loader.jar"
fi

# Fallback: no JARs anywhere but patch was applied — re-patch once to populate persistent storage
if [ ! -f "$JAR_DIR/loader.jar" ] && [ -f "patch_applied.zip" ] && [ ! -f "patch.zip" ]; then
  echo "No cached JARs found; re-patching once to build persistent cache..."
  cp patch_applied.zip patch.zip
  exec "$0" "$@"
fi

if [ ! -f "$JAR_DIR/loader.jar" ]; then
  "$GAMEDIR/menu/launch_menu.$DEVICE_ARCH" "$GAMEDIR/menu/menu.items" "$GAMEDIR/menu/FiraCode-Regular.ttf" --show "ERROR: loader.jar"
  sleep 10
  pm_finish

  if [[ "$PM_CAN_MOUNT" != "N" ]]; then
    if [ "$westonpack" -eq 1 ]; then
      $ESUDO umount "${weston_dir}"
      $ESUDO umount "${mesa_dir}"
    fi
    $ESUDO umount "${JAVA_HOME}"
  fi

  exit 1
fi

# DEBUG INFO
echo look loader
unzip -l "$JAR_DIR/loader.jar"

if [ "$DEVICE_NAME" = "TRIMUI-SMART-PRO" ]; then
  DISPLAY_WIDTH=1280
  DISPLAY_HEIGHT=720
fi

# FIX GPTOKEYB2, --preserve-env=SDL_GAMECONTROLLERCONFIG
if [ -n "$ESUDO" ]; then
  ESUDO="${ESUDO},SDL_GAMECONTROLLERCONFIG"
fi
GPTOKEYB2=$(echo "$GPTOKEYB2" | sed 's/--preserve-env=SDL_GAMECONTROLLERCONFIG_FILE,/&SDL_GAMECONTROLLERCONFIG,/')

COMMAND="$WESTONWRAP headless noop kiosk crusty_glx_gl4es"
# Note: libs/* uses Java's classpath wildcard syntax (NOT shell glob)
PATCH="$JAR_DIR/loader.jar:$JAR_DIR/f.jar:libs/*:PokeMMO.exe"

JAVA_OPTS="-Xms128M -Xmx384M -Dorg.lwjgl.util.Debug=true -Dfile.encoding=UTF-8"
if [ -d "/tmp/pokemmo_lwjgl" ]; then
  JAVA_OPTS="$JAVA_OPTS -Dorg.lwjgl.librarypath=/tmp/pokemmo_lwjgl"
fi

# Create fontconfig pointing to game fonts so Java can find them
# (device /usr/share/fonts is empty, causing "Fontconfig head is null")
FONT_DIR="$GAMEDIR/data/themes/default/res/fonts"
if [ -d "$FONT_DIR" ]; then
  cat > /tmp/pokemmo_fonts.conf <<FCEOF
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>
  <dir>$FONT_DIR</dir>
  <dir>/usr/share/fonts</dir>
  <cachedir>/tmp/fontconfig-cache</cachedir>
</fontconfig>
FCEOF
  mkdir -p /tmp/fontconfig-cache
  export FONTCONFIG_FILE=/tmp/pokemmo_fonts.conf
  echo "Fontconfig: $FONTCONFIG_FILE -> $FONT_DIR"
fi
ENV_VARS="PATH=$PATH JAVA_HOME=$JAVA_HOME XDG_SESSION_TYPE=x11 GAMEDIR=$GAMEDIR"
CLASS_PATH="-cp $PATCH com.pokeemu.client.Client"

echo "PokeMMO        $(cat RELEASE)"
echo "controlfolder  $controlfolder"
echo "theme          $client_ui_theme"

echo "WESTOMPACK  $westonpack"
echo "ESUDO       $ESUDO"
echo "COMMAND     $COMMAND"
echo "PATCH       $PATCH"
echo "GPTOKEYB2   $GPTOKEYB2"
echo "JAVA_OPTS   $JAVA_OPTS"
echo "ENV_VARS    $ENV_VARS"
echo "CLASS_PATH  $CLASS_PATH"

# Verify JAR files exist and contain expected classes
echo "Checking JAR files..."
if [ -f "$JAR_DIR/loader.jar" ]; then
  echo "loader.jar exists, checking for credential class:"
  unzip -l "$JAR_DIR/loader.jar" | grep "f/" | head -5 || echo "WARNING: No classes in f/ package found in loader.jar!"
else
  echo "ERROR: $JAR_DIR/loader.jar does not exist!"
fi

if [ "$westonpack" -eq 1 ]; then 
  # Ensure Weston runtime dir is secure to avoid startup warnings
  mkdir -p /tmp/weston_runtime
  chown 0:0 /tmp/weston_runtime 2>/dev/null || true
  chmod 700 /tmp/weston_runtime
  export XDG_RUNTIME_DIR=/tmp/weston_runtime

  # Weston-specific environment (avoid inline assignments with spaces)
  export GAMEDIR="$GAMEDIR"
  export XDG_DATA_HOME="$GAMEDIR"
  export WAYLAND_DISPLAY=
  export LANG=en_US.UTF-8
  export LC_ALL=en_US.UTF-8
  export XCOMPOSEFILE=/tmp/xcompose
  if [ ! -f "$XCOMPOSEFILE" ]; then
    echo "# minimal compose" > "$XCOMPOSEFILE"
  fi
  cd "$GAMEDIR"
  POWER_FLAG="/tmp/pokemmo_power_kill"
  POWER_APP_PID="/tmp/pokemmo_app.pid"
  POWER_GPTOKEYB_PID="/tmp/pokemmo_gptokeyb.pid"
  SUSPEND_BIN="/mnt/SDCARD/.system/tg5040/bin/suspend"
  SUSPEND_COPY="/tmp/pokemmo_real_suspend"
  SUSPEND_WRAPPER="/tmp/pokemmo_suspend_wrapper"

  # Intercept suspend via bind-mount so the power button kills the game
  # instead of sleeping. No files in .system/ are modified on disk;
  # a reboot clears the mount automatically if cleanup doesn't run.
  $ESUDO umount "$SUSPEND_BIN" 2>/dev/null || true
  cp "$SUSPEND_BIN" "$SUSPEND_COPY"
  chmod +x "$SUSPEND_COPY"
  cat > "$SUSPEND_WRAPPER" <<'EOS'
#!/bin/sh
FLAG="/tmp/pokemmo_power_kill"
APP_PID_FILE="/tmp/pokemmo_app.pid"
GPTOKEYB_PID_FILE="/tmp/pokemmo_gptokeyb.pid"

if [ -f "$FLAG" ]; then
  if [ -f "$GPTOKEYB_PID_FILE" ]; then
    pid=$(cat "$GPTOKEYB_PID_FILE" 2>/dev/null)
    [ -n "$pid" ] && kill "$pid" 2>/dev/null || true
  fi
  if [ -f "$APP_PID_FILE" ]; then
    pid=$(cat "$APP_PID_FILE" 2>/dev/null)
    [ -n "$pid" ] && kill "$pid" 2>/dev/null || true
  fi
  exit 0
fi

exec /tmp/pokemmo_real_suspend "$@"
EOS
  chmod +x "$SUSPEND_WRAPPER"
  $ESUDO mount --bind "$SUSPEND_WRAPPER" "$SUSPEND_BIN"

  RUN_SCRIPT="/tmp/pokemmo_run.sh"
  cat > "$RUN_SCRIPT" <<EOF
#!/bin/sh
cd "$GAMEDIR"
env -u WAYLAND_DISPLAY DISPLAY=:0 java $JAVA_OPTS $CLASS_PATH &
app_pid=\$!
echo "\$app_pid" > "$POWER_APP_PID"
sleep 0.5
wait \$app_pid
EOF
  chmod +x "$RUN_SCRIPT"

  # Start gptokeyb2 before Weston so the virtual devices exist at compositor startup
  SDL_GAMECONTROLLERCONFIG_FILE="controller.map"
  if [ ! -f "$GAMEDIR/controller.map" ]; then
    cat > "$GAMEDIR/controller.map" <<'CTRLMAP'
0300a3845e0400008e02000014010000,Xbox 360 Controller,a:b1,b:b0,x:b3,y:b2,back:b6,guide:b8,start:b7,leftshoulder:b4,rightshoulder:b5,lefttrigger:a2,righttrigger:a5,leftstick:b9,rightstick:b10,dpup:h0.1,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,leftx:a0,lefty:a1,rightx:a3,righty:a4,platform:Linux
1900d3cd010000000100000000010000,TrimUI Brick Controller,a:b1,b:b0,x:b3,y:b2,back:b8,guide:b10,start:b9,leftshoulder:b4,rightshoulder:b5,lefttrigger:b6,righttrigger:b7,dpup:h0.1,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,leftx:a0,lefty:a1,rightx:a3,righty:a4,platform:Linux
CTRLMAP
  fi
  # On Brick, swap dpad default to mouse movement; select+L2 toggles to arrow keys
  CONTROLS_INI="$GAMEDIR/controls.ini"
  if [ "$DEVICE" = "brick" ]; then
    CONTROLS_INI="/tmp/pokemmo_controls.ini"
    sed -e '/^\[controls\]$/,/^\[/ s/^dpad         = arrow_keys/dpad         = mouse_movement/' \
        -e '/^\[controls:dpad_mouse\]$/,/^\[/ s/^dpad  = mouse_movement/dpad  = arrow_keys/' \
        "$GAMEDIR/controls.ini" > "$CONTROLS_INI"
  fi
  LD_LIBRARY_PATH="/usr/trimui/lib:${LD_LIBRARY_PATH}" \
    SDL_GAMECONTROLLERCONFIG_FILE="$SDL_GAMECONTROLLERCONFIG_FILE" \
    DISPLAY=:0 \
    $GPTOKEYB2 java -c "$CONTROLS_INI" > /tmp/gptokeyb2.log 2>&1 &
  GPTOKEYB2_PID=$!
  echo "$GPTOKEYB2_PID" > "$POWER_GPTOKEYB_PID"
  touch "$POWER_FLAG"

  $ESUDO env CRUSTY_SHOW_CURSOR=1 WESTON_HEADLESS_WIDTH="$DISPLAY_WIDTH" WESTON_HEADLESS_HEIGHT="$DISPLAY_HEIGHT" \
    "$WESTONWRAP" headless noop kiosk crusty_glx_gl4es sh "$RUN_SCRIPT"

  # Cleanup gptokeyb2 if it's still running
  if [ -n "$GPTOKEYB2_PID" ]; then
    kill "$GPTOKEYB2_PID" 2>/dev/null || true
  fi
  rm -f "$POWER_FLAG" "$POWER_APP_PID" "$POWER_GPTOKEYB_PID"
  $ESUDO umount "$SUSPEND_BIN" 2>/dev/null || true
  rm -f "$SUSPEND_COPY" "$SUSPEND_WRAPPER"

  # Clean up Weston environment
  $ESUDO "$WESTONWRAP" cleanup
  cd "$ORIG_GAMEDIR"
else
  # Non-Weston environment with cursor fix
  ENV_NON_WESTON="$ENV_VARS CRUSTY_SHOW_CURSOR=1"
  
  env $ENV_NON_WESTON java $JAVA_OPTS $CLASS_PATH
fi

# Stop splash progress after game exits
stop_splash

if [[ "$PM_CAN_MOUNT" != "N" ]]; then
  if [ "$westonpack" -eq 1 ]; then
    $ESUDO umount "${weston_dir}"
    $ESUDO umount "${mesa_dir}"
  fi
  $ESUDO umount "${JAVA_HOME}"
fi

# Cleanup any running gptokeyb instances, and any platform specific stuff.
pm_finish
