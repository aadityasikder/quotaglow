# Complete Setup Guide

QuotaGlow supports desktop-only use, USB serial, local Wi-Fi, and independent ESP32 companion features. For wireless provisioning and pairing, follow [WIFI_SETUP.md](WIFI_SETUP.md) after uploading the firmware.

This guide starts with the desktop widget because it is the fastest way to verify that QuotaGlow can read Codex usage. The ESP32 and OLED are optional and can be added afterward.

Optional TTP223 and DHT11/DHT22 sensors add touch navigation, companion reactions, and room climate readings. See [DESK_COMPANION.md](DESK_COMPANION.md) and [ROOM_CLIMATE.md](ROOM_CLIMATE.md) after confirming the OLED works.

## Part 1: Desktop widget

### Requirements

- Windows 10 or Windows 11
- Windows PowerShell 5.1, included with Windows
- Codex desktop app or Codex CLI
- An active Codex sign-in

### Download QuotaGlow

Choose one method.

#### Release ZIP

1. Open the [QuotaGlow releases page](https://github.com/aadityasikder/quotaglow/releases).
2. Download the source ZIP for the latest version.
3. Extract the complete folder to a permanent location.

Do not run the launcher from inside the ZIP. If you move the project after enabling Windows startup, turn the startup checkbox off and on again to save the new path.

#### Git

```powershell
git clone https://github.com/aadityasikder/quotaglow.git
cd quotaglow
```

### Start the widget

1. Confirm Codex is installed and signed in.
2. Double-click `start_quotaglow.vbs`.
3. Wait several seconds for the first reading.

Success looks like:

- A small QuotaGlow card appears without a terminal window.
- The status becomes green.
- The 5-hour and 7-day remaining percentages appear.
- The last-refreshed time updates.

Use **Refresh** to request a new reading. Use **-** to collapse the widget and **+** to expand it. Drag either view to position it.

If this stage fails, stop and use [Troubleshooting](TROUBLESHOOTING.md) before adding hardware.

## Part 2: Optional ESP32 OLED

### Hardware

- ESP32 development board
- 0.96-inch 128×64 I²C OLED compatible with SSD1306
- Four jumper wires
- USB data cable
- Arduino IDE with ESP32 board support

### Wire the OLED

Disconnect the ESP32 from USB before changing wires.

| OLED label | ESP32 label |
|---|---|
| `GND` | `GND` |
| `VCC` | `3V3` |
| `SCL` | `D22` / GPIO 22 |
| `SDA` | `D21` / GPIO 21 |

Important:

- Follow the labels printed on the OLED; modules use different physical pin orders.
- Connect `VCC` to `3V3`, not `VIN`.
- `SCL` and `SDA` must not be swapped.

### Install Arduino libraries

In **Arduino IDE → Tools → Manage Libraries**, install:

1. **Adafruit GFX Library** by Adafruit
2. **Adafruit SSD1306** by Adafruit
3. **DHT sensor library** by Adafruit

Choose **Install All** if Arduino IDE asks about dependencies, including Adafruit Unified Sensor.

### Upload the firmware

1. Open `firmware/codex_usage_monitor/codex_usage_monitor.ino`.
2. Select your ESP32 board.
3. Select its COM port under **Tools → Port**.
4. Upload the sketch.

Success starts with the QuotaGlow startup screen. Wi-Fi setup information may appear temporarily, after which the saved home mode is restored.

### Add the room sensor

Disconnect USB before changing wires, then connect the default DHT11 module:

| DHT11 label | ESP32 label |
|---|---|
| `VCC` | `3V3` |
| `GND` | `GND` |
| `DATA` / `OUT` | `D26` / GPIO 26 |

For a bare four-pin sensor, place a 4.7–10 kΩ resistor between `DATA` and `3V3`. Three-pin modules commonly include this resistor. The first reading may take several seconds after startup. To use a DHT22, change `DHT_TYPE` in the sketch from `DHT11` to `DHT22`.

Hold the TTP223 for 1.2 seconds to open the display menu, tap to move, and hold to select. Full controls and climate-status meanings are in [ROOM_CLIMATE.md](ROOM_CLIMATE.md).

For diagnostics, open Serial Monitor at **115200 baud**. A detected display reports:

```text
OLED detected at 0x3C
```

or:

```text
OLED detected at 0x3D
```

Close Serial Monitor before continuing; it otherwise keeps the COM port busy.

### Connect the module

1. Open QuotaGlow.
2. Choose the ESP32 port from the COM-port list.
3. If it is missing, click **Scan**.
4. Click **Connect Module**.

The OLED should immediately display the same limits as the desktop widget. QuotaGlow continues working if the module is later disconnected.

## Part 3: Optional hardware demo

Use the legacy helper to verify serial communication without reading Codex:

1. Open `start_monitor.cmd` in Notepad.
2. Set `COM_PORT` to the ESP32 port.
3. Set `DEMO_MODE=1`.
4. Save and double-click `start_monitor.cmd`.

The OLED cycles through 0%, 50%, and 100% examples. Return `DEMO_MODE` to `0` afterward.

## Start with Windows

Enable **Start with Windows** inside the expanded widget. QuotaGlow creates a current-user startup entry; administrator access is not required.

To disable automatic launch, clear the same checkbox.

## Updating QuotaGlow

If installed with Git:

```powershell
git switch main
git pull
```

If installed from a ZIP, download and extract the new release. Preserve no credentials—QuotaGlow stores only non-sensitive UI settings separately in `%LOCALAPPDATA%\QuotaGlow`.

After an update that changes firmware behavior, upload the latest `.ino` file again.
