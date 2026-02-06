# PokeMMO Patch for TrimUI Brick & Smart Pro

Yo dawg, I heard you like [PokeMMO](https://pokemmo.com) PortMaster patches.  
So I patched the patch with another patch, so you can patch your PokeMMO PortMaster patch while patching your PokeMMO PortMaster patch.  

Why? To run PokeMMO on the TrimUI Brick and TrimUI Smart Pro with [NextUI](https://nextui.loveretro.games/) ≥ 6.7!

## What it does

- Brings the original [PortMaster Port](https://github.com/lowlevel-1989/pokemmo-port) port by [lowlevel.1989](https://github.com/lowlevel-1989) to NextUI on the TrimUI Brick and TrimUI Smart Pro.
- Downloads and sets up the official PokeMMO client automatically
- Lets you log in without a keyboard by injecting the credentials from a configurable file
- Adds built-in controller support tuned for the Brick and Smart Pro
- Offers simple display/layout choices at launch
- Keeps everything up to date and easy to reset if something breaks
- Provides library overrides so the Port can actually run on these devices

## Requirements

- TrimUI Brick (tg3040) or Smart Pro (tg5040) running NextUI 6.7 or higher
- WiFi connection
- A PokeMMO account ([pokemmo.com](https://pokemmo.com))

## Installation
### Part 1: Install PortMaster and PokeMMO
1. Install PortMaster on your TrimUI Brick or Smart Pro via the Pak Store if you haven't already.
2. Open PortMaster from the Ports Menu.
    - Let it perform updates if required.
3. Navigate to the **All Ports** section.
4. Select PokeMMO and install it.
    - Let PortMaster do it's thing.
### Part 2: Configure credentials, place the roms and install patch
1. Turn off your device, remove the SD card and plug it into your computer.
2. Navigate to /mnt/SDCARD/Roms/Ports (PORTS)/.ports/pokemmo
    - Unhide hidden folders if you can't find the .ports folder.
3. Rename credentials.template.txt to credentials.txt.
    - Open credentials.txt and enter your PokeMMO username and password.
4. Copy the ROMs as described [here](https://github.com/lowlevel-1989/pokemmo-port?tab=readme-ov-file#3-add-required-and-optional-roms).
   - Adding the Black & White ROM didn't require me to edit the main.properties file. If it turns out to be required for the other ROMs, please do so after applying the patch as it wil overwrite main.properties again.
6. Copy [pokemmo_patch.pakz](https://github.com/Helaas/tg5040-nextui-pokemmo-portmaster-patch/releases) to the root of your SD card.
7. Reboot the device. NextUI will extract the patch automatically.
8. Launch **PokeMMO** from the Ports menu.

## Menu options

| Option | What it does |
|---|---|
| **PokeMMO** | Launch with desktop UI at 1x scale |
| **PokeMMO Android** | Launch with mobile UI at 1.8x scale |
| **PokeMMO Small** | Launch with desktop UI at 1.4x scale |
| **PokeMMO Update** | Download latest client + missing runtimes + apply credentials patch|
| **PokeMMO Restore** | Reset config and patches to defaults |
| **PokeMMO Restore Mods** | Reset only the mods folder to defaults |

## Controls

| Button | Action |
|--------|--------|
| Start | Menu Focus |
| R1 | Mouse Left |
| L1 | Mouse Right |
| A | A |
| B | B |
| X | Bag |
| Y | Hotkey 1 |
| L2 | Hotkey 2 |
| R2 | Hotkey 3 |
| F1 | Hotkey 4 (Brick only)|
| F2 | Hotkey 5 (Brick only)|
| Select + B | Hotkey 6 |
| Select + A | Hotkey 7 |
| Select + X | Hotkey 8 |
| Select + R1 | Hotkey 9 |
| Select + R2 | Screenshot |
| Select + L2 | Toggle D-Pad Mouse (Brick: this defaults to On) |
| Select + Y | Toggle Mode Text (On/Off) |
| Right thumbstick | Move mouse (Smart Pro only) |
| Power button | Exit game |

Note: Hotkeys are assigned by right-clicking on any item or element in the game and selecting register.
Note 2: The Brick's D-Pad defaults to mouse mode, but you can toggle it on/off with Select + L2 after logging in.

### Virtual Keyboard

| Button | Action |
|--------|--------|
| Select + Y | Mode Text (Off) |
| A | Add Character |
| B | Backspace |
| X | Space |
| Y | Toggle Case |
| Up | Prev Character |
| Down | Next Character |
| Select | Toggle Number/Letter |

## For DEVs: building the pakz

Requires `make`, `rsync`, and `zip`.

```
cd pokemmo
make
```

This produces [pokemmo/pokemmo_patch.pakz](pokemmo/pokemmo_patch.pakz) ready to copy to the SD card.

## Changes from the original port
Based on [lowlevel-1989/pokemmo-port](https://github.com/lowlevel-1989/pokemmo-port). This patch adds:
- **NextUI integration** -- Shared userdata/log paths, and a safe temp symlink to avoid spaces breaking westonwrap.
- **TrimUI input fixes** -- Injects udev rules and bind-mounts the udev runtime directory so libinput sees the gamepad correctly.
- **Boot splash progress** -- Uses the NextUI splash utility to display progress during launch.
- **Post-install cleanup** -- Removes duplicate Port entries created by the installer.
- **Native overrides** -- Provides bundled native libs and LWJGL overrides for compatibility via [pokemmo/staged/lib_override](pokemmo/staged/lib_override) and [pokemmo/staged/lwjgl_override](pokemmo/staged/lwjgl_override).
- **CredentialsAgent patch** -- Injects the CredentialsAgent hook from [pokemmo/staged/patch_template/CredentialsAgent.java](pokemmo/staged/patch_template/CredentialsAgent.java) to enable credentials-file login. This replaces the credentials.java & launcher.java class-replacement technique, which proved troublesome.
- **Bundled ripgrep** -- Provides a bundled version of [ripgrep](https://github.com/BurntSushi/ripgrep) for faster patching of the game files. Can patch the credentials agent class in under a minute instead of several minutes.

## Known Issues
- **Long first launch** -- The first launch of PokeMMO can take up to ~2 minutes before reaching the menu. This is expected behavior while PortMaster performs initial setup and only occurs on the first run.
- **3D rendering glitches** -- Minor 3D issues may appear, most notably on the login screen. In-game rendering is generally fine and this has no impact on gameplay. This is caused by missing or incomplete driver support.
- **Mouse cursor moves automatically (Smart Pro)** -- This is usually caused by uncalibrated analog sticks. Reboot the device **without the SD card**, then go to `Settings > System > Calibrate Joystick` and follow the on-screen prompts to rotate both sticks.
- **Can only move left and right** -- This happens when text mode is still enabled. Press **Select + Y** to exit text mode, then movement in all directions will work normally.

## Credits

- **Original porter**: lowlevel.1989
- Built on [PortMaster](https://portmaster.games/)
- [PokeMMO](https://pokemmo.com)

## Note
This patch is not affiliated with the PokeMMO team or lowlevel.1989. Do not contact them for support with this patch. For issues, please open an issue on this repository.
