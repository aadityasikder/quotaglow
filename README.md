# ESP32 Codex Usage Monitor

This project displays your remaining Codex usage limits and reset countdowns on a 0.96-inch OLED. A Windows helper reads the limits from your existing Codex login and sends only display values to the ESP32 over USB.

Your password, access token, and account ID are never sent to the ESP32 or saved in this project.

## Documentation

- [Floating desktop widget](doc/DESKTOP_WIDGET.md)
- [Complete setup guide](doc/SETUP.md)
- [Architecture and security model](doc/ARCHITECTURE.md)
- [USB serial protocol](doc/SERIAL_PROTOCOL.md)
- [Troubleshooting guide](doc/TROUBLESHOOTING.md)

## Floating desktop widget

Double-click `start_quotaglow.vbs` to open the always-on-top Windows widget without a terminal window. It displays live Codex usage without requiring the ESP32, refreshes every 60 seconds, supports manual refresh, and shows the last successful refresh time.

Use the minus button to collapse QuotaGlow into a rounded usage-only bar. The compact mode and screen position are remembered.

The ESP32 is optional. Select its COM port and click **Connect Module** to mirror the widget values to the OLED. See the [widget guide](doc/DESKTOP_WIDGET.md) for every control and startup behavior.

## Project contents

```text
codex_usage_monitor/
├── firmware/
│   └── codex_usage_monitor/
│       └── codex_usage_monitor.ino
├── pc-helper/
│   └── codex_usage_helper.ps1
├── start_monitor.cmd
└── README.md
```

## Wiring

Disconnect the ESP32 from USB before changing wires.

| OLED pin | ESP32 pin |
|---|---|
| GND | GND |
| VCC | 3V3 |
| SDA | GPIO 21 |
| SCL | GPIO 22 |

Follow the labels printed on your OLED. Do not assume that every module has its pins in the same physical order.

## Required Arduino libraries

The firmware uses:

- Adafruit GFX Library
- Adafruit SSD1306

Install them from **Arduino IDE → Tools → Manage Libraries** if they are not already installed.

## Step 1: Upload the firmware

1. Open `firmware\codex_usage_monitor\codex_usage_monitor.ino` in Arduino IDE.
2. Connect the ESP32 and select its normal board and port settings.
3. Upload the sketch.
4. The OLED should say `WAITING FOR PC`.

The firmware automatically checks the common OLED addresses `0x3C` and `0x3D`. If the display stays blank, open Serial Monitor at **115200 baud**. It will report whether an OLED was detected.

## Step 2: Find and configure the COM port

1. In Arduino IDE, open **Tools → Port**.
2. Note the ESP32 port, for example `COM5`.
3. Open `start_monitor.cmd` in Notepad.
4. Change this line to match your port:

```bat
set "COM_PORT=COM5"
```

5. Save the file.

Only one program can normally use the port at a time. Close Arduino Serial Monitor before starting the helper.

## Step 3: Run the display demo first

The demo verifies the OLED and USB communication without reading your Codex account.

1. Open `start_monitor.cmd` in Notepad.
2. Change `set "DEMO_MODE=0"` to `set "DEMO_MODE=1"`.
3. Save and double-click `start_monitor.cmd`.
4. The display will cycle through 0%, 50%, and 100% examples.
5. After all three samples are sent, the helper pauses and waits for you to press a key. This is normal; demo mode is a short test rather than a continuously running monitor.

If the demo works, return `DEMO_MODE` to `0` for live usage.

## Step 4: Run the live monitor

1. Confirm Codex is installed and signed in on this computer.
2. Confirm `DEMO_MODE=0` in `start_monitor.cmd`.
3. Close Arduino Serial Monitor.
4. Double-click `start_monitor.cmd`.
5. Leave the helper window open.

The first update may take several seconds. After that, the helper refreshes the values every 60 seconds.

This command-window workflow remains available for diagnostics and backward compatibility. For normal use, prefer `start_quotaglow.vbs`.

The OLED shows:

- Remaining percentage for the primary usage window.
- Remaining percentage for the secondary usage window, when available.
- Progress bars representing usage remaining.
- Alternating reset countdowns.
- `DATA STALE` if no valid update arrives for three minutes.
- `LIMIT REACHED` if Codex explicitly reports that ordinary usage is unavailable.

Press **Ctrl+C** in the helper window to stop it.

## Troubleshooting

### Port was not found

Check **Arduino IDE → Tools → Port** again and update `COM_PORT` in `start_monitor.cmd`.

### Access to the port is denied

Close Arduino Serial Monitor and any other program using the ESP32 port, then restart the helper.

### OLED remains blank

- Check GND, 3V3, SDA/GPIO 21, and SCL/GPIO 22.
- Follow the labels on the OLED rather than relying on physical pin order.
- Open Serial Monitor at 115200 baud and look for the OLED detection message.

### The OLED says CODEX ERROR

- Confirm the Codex desktop app or CLI is installed and signed in.
- Restart `start_monitor.cmd`.
- A future Codex update may change the experimental local usage interface and require an update to the helper.

The helper first checks the normal command path, then automatically searches the Codex desktop app installation under your Windows local application-data folder. You do not need to add Codex to `PATH` manually.

### The OLED says NO LIMIT DATA

Codex responded but did not provide a primary usage window. Check the usage display in Codex and restart the helper.

### The OLED says DATA STALE

The previous valid data is still displayed, but no new update arrived for three minutes. Check that the helper window is still running and that the USB cable remains connected.

## Serial protocol

Normal update:

```text
LIMITS|35|5h|2h18m|58|7d|3d04h|1
```

The fields are primary remaining percentage, primary window, primary reset, secondary remaining percentage, secondary window, secondary reset, and whether normal usage is allowed. A secondary percentage of `-1` means that no secondary window is available.

Status messages:

```text
STATUS|CODEX_ERROR
STATUS|NO_LIMIT_DATA
```

Serial settings are 115200 baud, 8 data bits, no parity, and one stop bit.

## Optional command-line checks

These checks do not require the ESP32 to be connected. Run them from PowerShell inside the project folder.

Test fake data conversion:

```powershell
.\pc-helper\codex_usage_helper.ps1 -Demo -DryRun -Once
```

Read live Codex limits once and print the serial message:

```powershell
.\pc-helper\codex_usage_helper.ps1 -DryRun -Once
```

The local Codex usage operation is experimental. If a later Codex version changes it, the PowerShell helper may need to be updated.
