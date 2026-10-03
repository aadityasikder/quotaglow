# Setup Guide

This guide takes the project from assembled hardware to live Codex usage on the OLED.

## Hardware

- ESP32 development board
- 0.96-inch 128×64 I²C OLED, compatible with SSD1306
- Four jumper wires
- USB data cable
- Windows computer with Codex installed and signed in

## Wiring

Disconnect USB before changing any wires.

| OLED label | ESP32 label |
|---|---|
| GND | GND |
| VCC | 3V3 |
| SCL | D22 / GPIO 22 |
| SDA | D21 / GPIO 21 |

Use the labels printed on the modules. The physical order of OLED pins can vary. Connect VCC to `3V3`, not `VIN`.

## Arduino libraries

Install these libraries through **Arduino IDE → Tools → Manage Libraries**:

1. **Adafruit GFX Library** by Adafruit
2. **Adafruit SSD1306** by Adafruit

When Arduino IDE offers to install dependencies, choose **Install All**.

## Upload the firmware

1. Open `firmware/codex_usage_monitor/codex_usage_monitor.ino`.
2. Select your ESP32 board and its COM port.
3. Upload the sketch.
4. The OLED should show `WAITING FOR PC`.

For diagnostics, open Serial Monitor at 115200 baud. A working display reports `OLED detected at 0x3C` or `OLED detected at 0x3D`.

## Configure the Windows helper

1. Find the ESP32 port under **Arduino IDE → Tools → Port**.
2. Open `start_monitor.cmd` in Notepad.
3. Set `COM_PORT` to that port, for example:

   ```bat
   set "COM_PORT=COM6"
   ```

4. Close Serial Monitor before starting the helper. Only one application can normally use the port at a time.

## Test with demo data

1. Set `DEMO_MODE=1` in `start_monitor.cmd`.
2. Double-click `start_monitor.cmd`.
3. Confirm that the OLED displays the 0%, 50%, and 100% examples.
4. Press a key after the successful demo message.

## Start live monitoring

### Recommended: floating widget

1. Double-click `start_quotaglow.cmd`.
2. Wait for the first desktop reading.
3. To use the OLED, select its COM port and choose **Connect Module**.
4. Optionally enable **Start with Windows**.

The widget works without the ESP32 and refreshes every 60 seconds.

### Legacy command-window monitor

1. Set `DEMO_MODE=0`.
2. Confirm Codex is installed and signed in.
3. Double-click `start_monitor.cmd`.
4. Leave the helper window open.

The helper automatically locates the Codex desktop executable. It reads usage once per minute and sends only percentages, window labels, reset countdowns, and the allowed/blocked state over USB.

Stop the monitor by pressing **Ctrl+C** in the helper window.
