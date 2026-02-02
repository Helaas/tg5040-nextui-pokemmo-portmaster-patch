#!/bin/sh
# Post-install script for PokeMMO pakz
# Runs as /mnt/SDCARD/post_install.sh after extraction, then gets deleted by the installer.
# Note: WiFi is not available at this point. Runtime downloads happen in the Update menu option.

# Ensure PortMaster's expected home directory exists (mod_TrimUI.txt needs it)
mkdir -p /mnt/SDCARD/Data/home
