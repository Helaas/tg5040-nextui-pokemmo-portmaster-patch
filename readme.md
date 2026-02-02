# PokeMMO Patch for TrimUI Brick (tg5040)

A patch package that lets you run [PokeMMO](https://pokemmo.com) on the TrimUI Brick handheld via PortMaster.

## What it does

This `.pakz` installs a PortMaster-based launcher that downloads, patches, and runs the official PokeMMO client on your device. It handles:

- **Auto-patching** -- On each launch, the script extracts the PokeMMO client, identifies obfuscated class names, generates Java patches, and compiles them into a `loader.jar` that hooks into the game.
- **Credential storage** -- Enter your username and password once in `credentials.txt`; the patch injects auto-login so you don't need a keyboard at the login screen.
- **Controller support** -- Maps your gamepad to PokeMMO's controls via gptokeyb2 and a custom Jamepad bridge, with a bundled `controller.map` for the TrimUI Brick.
- **Display modes** -- A launch menu lets you pick between three UI layouts (see Menu Options below).
- **Runtime management** -- Automatically downloads required PortMaster runtimes (Weston, Mesa, Java 17) when you select "Update" from the menu.
- **Update & Restore** -- Menu options to re-download the latest PokeMMO client and to reset configuration or mods to defaults.

## Installation

1. Copy `pokemmo_patch.pakz` to the root of your SD card (`/mnt/SDCARD/`).
2. Reboot the device. NextUI will extract the patch automatically.
3. Launch **PokeMMO** from the Ports menu.
4. On first run, select **Update** to download the PokeMMO client and any missing runtimes (requires WiFi).
5. Edit `credentials.txt` at `.ports/pokemmo/credentials.txt` with your PokeMMO username and password for auto-login.

## Requirements

- TrimUI Brick (tg5040) running NextUI
- PortMaster installed
- WiFi connection for initial setup (client download and runtime fetching)
- A PokeMMO account ([pokemmo.com](https://pokemmo.com))

## Menu options

| Option | What it does |
|---|---|
| **PokeMMO** | Launch with desktop UI at 1x scale |
| **PokeMMO Android** | Launch with mobile UI at 1.8x scale |
| **PokeMMO Small** | Launch with desktop UI at 1.4x scale |
| **PokeMMO Update** | Download latest client + missing runtimes |
| **PokeMMO Restore** | Reset config and patches to defaults |
| **PokeMMO Restore Mods** | Reset only the mods folder to defaults |

## Controls

### Default Mode

| Button | Action |
|--------|--------|
| A | Confirm (A) |
| B | Cancel (B) |
| X | Bag |
| Y | Hotkey 1 |
| L1 | Right Click |
| R1 | Left Click |
| L2 | Hotkey 2 |
| R2 | Hotkey 3 |
| L3 (Extra1) | Hotkey 4 |
| R3 (Extra2) | Hotkey 5 |
| Start | Game Menu |
| D-Pad | Arrow Keys |
| Left Analog | Mouse Movement |
| Right Analog | Mouse Movement |

> **TrimUI Brick note:** On the Brick, the default mode starts with D-Pad mapped to mouse movement instead of arrow keys. Select+L2 toggles it to arrow keys.

### Select (Hold) + Button Combos

Hold **Select** and press a button to access these functions:

| Combo | Action |
|-------|--------|
| Select + B | Hotkey 6 |
| Select + A | Hotkey 7 |
| Select + X | Hotkey 8 |
| Select + R1 | Hotkey 9 |
| Select + R2 | Screenshot (F11) |
| Select + Y | Toggle Text Input Mode |
| Select + L2 | Toggle D-Pad Mouse Mode |

### D-Pad Mouse Mode

Activated via **Select + L2**. D-Pad controls the mouse cursor instead of arrow keys.

| Button | Action |
|--------|--------|
| L1 | Right Click |
| R1 | Left Click |
| D-Pad | Mouse Movement |
| Start | Game Menu |

All Select combos remain available (including Select+L2 to toggle back).

### Text Input Mode

Activated via **Select + Y**. Used for typing in chat and text fields.

| Button | Action |
|--------|--------|
| D-Pad Up/Down | Cycle through characters |
| D-Pad Left/Right | Move cursor |
| A | Add letter |
| B | Backspace |
| X | Space |
| Y | Toggle case (abc / ABC) |
| L1 | Right Click |
| R1 | Left Click |
| L2 | Switch charset (letters / numbers) |
| Right Analog | Mouse Movement |
| Start | Submit text and exit |
| Select + Y | Cancel text and exit |

## Building the pakz

Requires `make`, `rsync`, and `zip`.

```
cd pokemmo
make
```

This produces `pokemmo_patch.pakz` ready to copy to the SD card.

## Credits

- **Porter**: lowlevel.1989
- Built on [PortMaster](https://portmaster.games/)
- [PokeMMO](https://pokemmo.com) is a fan-made MMO by the PokeMMO team
