# QuotaGlow

**A privacy-first desktop widget and optional ESP32 OLED display for Codex usage limits.**

[![Release](https://img.shields.io/github/v/release/aadityasikder/quotaglow?display_name=tag)](https://github.com/aadityasikder/quotaglow/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-6f62ff.svg)](LICENSE)
[![Platform: Windows](https://img.shields.io/badge/platform-Windows-0078D4.svg)](#requirements)
[![Hardware: Optional](https://img.shields.io/badge/ESP32-optional-65d6ad.svg)](#optional-esp32-oled)

QuotaGlow shows your Codex 5-hour and weekly usage windows, reset countdowns, and last refresh time in a small always-on-top Windows widget. It works without hardware. If you have an ESP32 and a 0.96-inch OLED, QuotaGlow can mirror the same information to a physical desk display over USB.

## Features

- Live Codex usage percentages and reset countdowns
- Automatic refresh every 60 seconds
- Manual refresh and last-successful-refresh timestamp
- Full and compact draggable widget modes
- Optional start with Windows
- Optional ESP32 + SSD1306 OLED display
- Module connect/disconnect and OLED sleep controls
- No API key copied into the project or firmware
- No Python, Node.js, npm, or installer required

## Choose your setup

| Setup | What you need | Recommended for |
|---|---|---|
| Desktop widget only | Windows and Codex desktop/CLI | Fastest setup; no electronics required |
| Desktop widget + OLED | Above, plus ESP32 and SSD1306 OLED | A physical always-visible desk monitor |
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

### 3. Upload the firmware

Open and upload:

```text
firmware/codex_usage_monitor/codex_usage_monitor.ino
```

The OLED should show `WAITING FOR PC`. The firmware automatically detects addresses `0x3C` and `0x3D`.

### 4. Connect from QuotaGlow

1. Close Arduino Serial Monitor so it releases the COM port.
2. Open QuotaGlow with `start_quotaglow.vbs`.
3. Select the ESP32 COM port.
4. Click **Connect Module**.

The OLED immediately receives the latest values and follows future refreshes. Disconnecting the module does not stop the desktop widget.

## Widget controls

| Control | Behavior |
|---|---|
| **Refresh** | Requests a new reading immediately |
| **- / +** | Switches between full and compact mode |
| **Scan** | Refreshes the COM-port list |
| **Connect Module** | Opens the selected ESP32 serial port |
| **Disconnect Module** | Stops OLED mirroring while desktop monitoring continues |
| **Pause Monitoring** | Stops polling, disconnects the module, and darkens the OLED |
| **Start with Windows** | Adds or removes a current-user startup entry |
| **X** | Closes QuotaGlow and darkens a connected OLED |

Settings are saved in `%LOCALAPPDATA%\QuotaGlow\settings.json`. This file contains UI preferences only—not credentials or account IDs.

## Documentation

- [Complete setup guide](doc/SETUP.md)
- [Desktop widget guide](doc/DESKTOP_WIDGET.md)
- [Troubleshooting](doc/TROUBLESHOOTING.md)
- [Architecture and security model](doc/ARCHITECTURE.md)
- [USB serial protocol](doc/SERIAL_PROTOCOL.md)
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

QuotaGlow uses the locally installed Codex app-server and your existing Codex sign-in. It does not place your password, access token, API key, or account ID in the repository, settings file, or ESP32 firmware. Only display-ready percentages, duration labels, reset countdowns, and allowed/blocked state are sent over USB.

The Codex rate-limit interface used by QuotaGlow is experimental and may require updates after a future Codex release.

## Current limitations

- The desktop widget currently supports Windows only.
- The computer must remain running for live updates.
- ESP32 communication currently uses USB serial, not Wi-Fi.
- The firmware targets 128×64 SSD1306-compatible I²C displays.

## Contributing

Issues and pull requests are welcome. Feature work targets `develop`; create a focused feature branch and see [CONTRIBUTING.md](CONTRIBUTING.md) before submitting changes.

## License

QuotaGlow is available under the [MIT License](LICENSE).
