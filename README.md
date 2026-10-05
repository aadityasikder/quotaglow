# QuotaGlow

**A privacy-first ESP32 desk companion with room sensing, touch controls, and optional Codex usage.**

[![Release](https://img.shields.io/github/v/release/aadityasikder/quotaglow?display_name=tag)](https://github.com/aadityasikder/quotaglow/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-6f62ff.svg)](LICENSE)
[![Platform: Windows](https://img.shields.io/badge/platform-Windows-0078D4.svg)](#requirements)
[![Hardware: Optional](https://img.shields.io/badge/ESP32-optional-65d6ad.svg)](#optional-esp32-oled)

QuotaGlow is an expandable ESP32 desk companion. Its OLED can show an animated face, room temperature and humidity, and optional Codex usage data received from the Windows widget over USB or trusted local Wi-Fi.

## Features

- Live Codex usage percentages and reset countdowns
- Automatic refresh every 60 seconds
- Manual refresh and last-successful-refresh timestamp
- Full and compact draggable widget modes
- Optional start with Windows
- Optional ESP32 + SSD1306 OLED display
- Optional TTP223 touch sensor for an animated desk companion
- Optional DHT11 or DHT22 room temperature and humidity sensor
- Touch-controlled OLED menu with fixed and rotating display modes
- USB or wireless local-network module connection
- Browser-based Wi-Fi setup and six-digit pairing
- Module connect/disconnect and OLED sleep controls
- No API key copied into the project or firmware
- No Python, Node.js, npm, or installer required

## Choose your setup

| Setup | What you need | Recommended for |
|---|---|---|
| Desktop widget only | Windows and Codex desktop/CLI | Fastest setup; no electronics required |
| Desktop widget + OLED | Above, plus ESP32 and SSD1306 OLED | A USB or wireless desk monitor |
| Legacy command helper | Windows, Codex, and optional ESP32 | Diagnostics and protocol testing |

## Requirements

### Desktop widget

- Windows 10 or Windows 11
- Windows PowerShell 5.1
- Codex desktop app or Codex CLI, installed and signed in

### Optional ESP32 OLED

- ESP32 development board
- 0.96-inch 128×64 I²C OLED compatible with SSD1306
- Four jumper wires and a USB data cable
- Arduino IDE with ESP32 board support
- `Adafruit GFX Library` and `Adafruit SSD1306`
- `DHT sensor library` by Adafruit

## Quick start: desktop widget only

1. Download the latest release ZIP or clone the repository:

   ```powershell
   git clone https://github.com/aadityasikder/quotaglow.git
   cd quotaglow
   ```

2. Double-click `start_quotaglow.vbs`.
3. Wait a few seconds for the first Codex reading.
4. Drag the widget wherever you want it.
5. Use **-** for compact mode and **+** to expand it again.

The VBS launcher intentionally starts QuotaGlow without a PowerShell terminal window. The widget works even when no ESP32 is attached.

QuotaGlow allows only one widget instance. Opening `start_quotaglow.cmd` or `start_quotaglow.vbs` again brings the existing widget forward instead of creating another copy. To close all current or older stuck instances, double-click `stop_quotaglow.cmd`.

## Optional ESP32 OLED

### 1. Wire the display

Disconnect USB before changing wires.

| OLED label | ESP32 label |
|---|---|
| `GND` | `GND` |
| `VCC` | `3V3` |
| `SCL` | `D22` / GPIO 22 |
| `SDA` | `D21` / GPIO 21 |

Use the labels printed on your modules; OLED pin order varies. Connect `VCC` to `3V3`, not `VIN`.

### 2. Install Arduino libraries

In **Arduino IDE → Tools → Manage Libraries**, install:

- **Adafruit GFX Library** by Adafruit
- **Adafruit SSD1306** by Adafruit

Accept **Install All** if Arduino IDE offers required dependencies.

Also install **DHT sensor library by Adafruit** for room temperature and humidity support.

### 3. Upload the firmware

Open and upload:

```text
firmware/codex_usage_monitor/codex_usage_monitor.ino
```

The OLED should show the QuotaGlow startup screen followed by Wi-Fi information or the saved home mode. The firmware automatically detects addresses `0x3C` and `0x3D`.

### 4. Connect over USB

1. Close Arduino Serial Monitor so it releases the COM port.
2. Open QuotaGlow with `start_quotaglow.vbs`.
3. Select the ESP32 COM port.
4. Click **Connect Module**.

The OLED immediately receives the latest values and follows future refreshes. Disconnecting the module does not stop the desktop widget.

### Or connect over Wi-Fi

1. Join the ESP32's temporary `QuotaGlow-Setup-XXXX` network.
2. Open `http://192.168.4.1` and enter your trusted 2.4 GHz Wi-Fi details.
3. In the widget choose **Wi-Fi**, select **Rescan**, and choose the module. If discovery is blocked, enter the IP shown on the OLED.
4. Enter the six-digit OLED code and select **Pair**.

See the [Wi-Fi setup guide](doc/WIFI_SETUP.md) for complete instructions and safety notes.

### Add the desk companion touch sensor

QuotaGlow can show an animated face and react when you pet it. Connect a standard TTP223 capacitive touch module:

| TTP223 label | ESP32 label |
|---|---|
| `VCC` | `3V3` |
| `GND` | `GND` |
| `OUT` | `D27` / GPIO 27 |

Use `3V3`, never `VIN` or 5V. Tap the sensor to pet the companion. Hold it for about 1.2 seconds to open the OLED menu.

### Add the room climate sensor

The firmware defaults to the DHT11 used by the current reference build. Connect it as follows:

| DHT11 label | ESP32 label |
|---|---|
| `VCC` | `3V3` |
| `GND` | `GND` |
| `DATA` / `OUT` | `D26` / GPIO 26 |

A bare four-pin sensor needs a 4.7–10 kΩ pull-up resistor between `DATA` and `3V3`. Most three-pin modules already include one. Use 3.3V, not 5V. DHT22 owners can change `DHT_TYPE` from `DHT11` to `DHT22` before uploading.

Hold the touch sensor for 1.2 seconds to open the OLED menu. Tap to move and hold to select **Companion**, **Codex Usage**, **Room Climate**, **Auto Rotate**, or **Wi-Fi Pairing**. See the [room climate and OLED menu guide](doc/ROOM_CLIMATE.md).

## Widget controls

| Control | Behavior |
|---|---|
| **Refresh** | Requests a new reading immediately |
| **- / +** | Switches between full and compact mode |
| **USB / Wi-Fi** | Selects the module transport |
| **Rescan** | Refreshes COM ports or discovers Wi-Fi modules |
| **Pair / Forget** | Pairs with or removes a saved Wi-Fi module |
| **Connect Module** | Opens the selected ESP32 serial port |
| **Disconnect Module** | Stops OLED mirroring while desktop monitoring continues |
| **Pause Monitoring** | Stops polling, disconnects the module, and darkens the OLED |
| **Start with Windows** | Adds or removes a current-user startup entry |
| **X** | Closes QuotaGlow and darkens a connected OLED |

If the widget does not respond to **X**, run `stop_quotaglow.cmd`. It first requests a normal shutdown and then force-stops only processes whose command line is verified as the QuotaGlow widget.

Settings are saved in `%LOCALAPPDATA%\QuotaGlow\settings.json`. This file contains UI preferences only—not credentials or account IDs.

## Documentation

- [Complete setup guide](doc/SETUP.md)
- [Desktop widget guide](doc/DESKTOP_WIDGET.md)
- [Troubleshooting](doc/TROUBLESHOOTING.md)
- [Architecture and security model](doc/ARCHITECTURE.md)
- [USB serial protocol](doc/SERIAL_PROTOCOL.md)
- [Wi-Fi setup and pairing](doc/WIFI_SETUP.md)
- [Wi-Fi discovery and local API](doc/WIFI_API.md)
- [Desk companion guide](doc/DESK_COMPANION.md)
- [Room climate and OLED menu](doc/ROOM_CLIMATE.md)
- [Feature roadmap](doc/ROADMAP.md)
- [Contributing](CONTRIBUTING.md)
- [Security policy](SECURITY.md)
- [Changelog](CHANGELOG.md)

## Testing

Run the local regression checks from PowerShell:

```powershell
.\tests\Test-QuotaGlow.ps1
```

The checks validate PowerShell syntax, usage conversion, widget XAML, serial output, and legacy demo compatibility.

## Privacy and security

QuotaGlow uses the locally installed Codex app-server and your existing Codex sign-in. It does not place your password, access token, API key, or account ID in the repository, settings file, or ESP32 firmware. Only display-ready values are sent to the module. Wi-Fi uses authenticated HTTP rather than HTTPS, so use it only on a trusted private network.

The Codex rate-limit interface used by QuotaGlow is experimental and may require updates after a future Codex release.

## Current limitations

- The desktop widget currently supports Windows only.
- The computer must remain running for live updates.
- Wi-Fi is local-LAN only; there is no cloud relay or remote module access.
- The firmware targets 128×64 SSD1306-compatible I²C displays.

## Contributing

Issues and pull requests are welcome. Feature work targets `develop`; create a focused feature branch and see [CONTRIBUTING.md](CONTRIBUTING.md) before submitting changes.

## License

QuotaGlow is available under the [MIT License](LICENSE).
