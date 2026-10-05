# Troubleshooting

## Ambient Light always reads 0% or 100%

Confirm the divider midpoint—not 3V3 or GND—is connected to GPIO 34. Use a 10 kΩ fixed resistor and never connect the ADC pin to 5V. Open **Calibrate Light**, cover the LDR and hold, then shine a bright light and hold again. Calibration fails when the two readings differ by fewer than 200 ADC counts.

## OLED brightness flickers or changes in the wrong direction

Run **Calibrate Light** again under realistic dark and bright conditions. The firmware supports either divider orientation, averages samples, and uses hysteresis. Loose breadboard wires can still produce unstable ADC readings.

## Companion does not sleep in darkness

The calibrated light category must remain `DARK` for 30 seconds. Touching the sensor wakes the face for another 30 seconds. Check the Ambient Light screen to see the current category.

## DHT sensor shows `SENSOR UNAVAILABLE`

Install **DHT sensor library by Adafruit** and accept its dependencies. Wire `VCC` to `3V3`, `GND` to `GND`, and `DATA` or `OUT` to GPIO 26. A bare four-pin sensor also needs a 4.7–10 kΩ pull-up resistor between DATA and 3V3. The firmware defaults to DHT11; change `DHT_TYPE` to `DHT22` when using a DHT22 or AM2302. Wait at least eight seconds after boot because three failed samples are required before the unavailable state is final.

If Serial Monitor repeatedly prints `DHT sensor reading failed`, shorten the wires, confirm the configured sensor type matches the hardware, and check that DATA is not connected to GPIO 27—the touch sensor uses GPIO 27.

## OLED menu does not open

Hold the TTP223 continuously for at least 1.2 seconds. A short tap pets the companion or advances an already-open menu. Confirm TTP223 OUT is connected to GPIO 27 and that the display has not been turned off with `POWER|OFF`.

## TTP223 touch sensor does not react

Wire `VCC` to `3V3`, `GND` to `GND`, and `OUT` to GPIO 27. Do not use 5V or VIN. See [DESK_COMPANION.md](DESK_COMPANION.md) for gesture and wiring troubleshooting.

## Multiple widgets are already open

Double-click `stop_quotaglow.cmd`. It closes responsive widgets normally, then force-stops remaining processes only when their command line identifies the QuotaGlow widget. Start QuotaGlow again afterward. New versions prevent a second instance and bring the existing widget forward instead.

## Wi-Fi setup network does not appear

Hold **BOOT** for five seconds to clear network data. Confirm v1.2 firmware is uploaded, then restart the ESP32.

## Captive portal does not open

Stay connected to `QuotaGlow-Setup-XXXX` despite any no-internet warning, then open `http://192.168.4.1` manually.

## Rescan finds no module

Confirm both devices are on the same private network and Windows Firewall permits local UDP. Enter the IP shown on the OLED if discovery is blocked.

## Pairing fails

Use the current OLED code. Codes expire after ten minutes and repeated failures are rate-limited. Restart the module for a new code.

## Wi-Fi details changed

Hold **BOOT** for five seconds and provision again. USB remains usable during Wi-Fi problems.

## OLED is completely blank

1. Disconnect USB.
2. Check the connections by their printed labels:
   - OLED GND → ESP32 GND
   - OLED VCC → ESP32 3V3
   - OLED SCL → ESP32 D22
   - OLED SDA → ESP32 D21
3. Reconnect USB and open Serial Monitor at 115200 baud.

Expected output:

```text
OLED detected at 0x3C
```

or:

```text
OLED detected at 0x3D
```

If the firmware reports that neither address was found, recheck power and swap SCL/SDA only if their labels were previously misread.

## `Adafruit_GFX.h: No such file or directory`

Install **Adafruit GFX Library by Adafruit** through Arduino IDE's Library Manager. Also install **Adafruit SSD1306 by Adafruit** and accept all dependencies.

## `DHT.h: No such file or directory`

Install **DHT sensor library by Adafruit** through Arduino IDE's Library Manager and choose **Install All** when prompted.

## Display remains on `WAITING FOR PC`

- Confirm `COM_PORT` in `start_monitor.cmd` matches Arduino IDE.
- Close Arduino Serial Monitor.
- Confirm the USB cable supports data.
- Run with `DEMO_MODE=1` first.
- In the desktop widget, select the correct COM port and click **Connect Module**.

## Widget does not open

- Run `start_quotaglow.vbs` again and wait several seconds.
- Confirm Windows PowerShell is enabled.
- From PowerShell, run `desktop-widget\QuotaGlow.ps1` without the hidden launcher to see an error message.

## A PowerShell terminal appears with the widget

Launch with `start_quotaglow.vbs`, not the `.ps1` file. The VBS launcher starts the widget invisibly. The `.ps1` file should only be run directly when troubleshooting.

## Widget shows a Codex error

- Confirm Codex desktop is installed and signed in.
- Click **Refresh**.
- Close and reopen the widget if the local service remains unavailable.

The last successful values remain visible during a temporary error and become stale after three minutes.

## Widget is outside the visible screen

Close the widget and delete `%LOCALAPPDATA%\QuotaGlow\settings.json`. It will reopen centered.

## Start with Windows does not work

Toggle **Start with Windows** off and on again. The setting uses the current-user Run registry entry and does not require administrator access. Moving the repository afterward requires toggling the setting again so the saved path is updated.

## COM port not found

Reconnect the ESP32, check **Arduino IDE → Tools → Port**, and update `COM_PORT`.

## Access to the COM port is denied

Another application has the port open. Close Serial Monitor, serial plotters, and other helper windows, then retry.

## `codex` is not recognized

The current helper automatically checks both the command path and the Codex desktop installation under Windows local application data. Pull the latest project version if an older helper still reports this error.

## OLED shows `CODEX ERROR`

- Confirm Codex desktop is installed and signed in.
- Restart the helper.
- Update Codex if the installation is incomplete.
- If the error starts after a Codex update, the experimental app-server interface may have changed.

## OLED shows `NO LIMIT DATA`

Codex responded without a primary usage window. Check the usage display in Codex and restart the helper.

## OLED shows `DATA STALE`

No valid usage update arrived for three minutes. The last valid percentages remain visible. Check the helper window and USB connection.

## Diagnostic commands

Run these from PowerShell in the repository root.

Test message generation without an ESP32:

```powershell
.\pc-helper\codex_usage_helper.ps1 -Demo -DryRun -Once
```

Read live limits once without opening a COM port:

```powershell
.\pc-helper\codex_usage_helper.ps1 -DryRun -Once
```

The dry-run output begins with `SERIAL>` and shows exactly what would be sent to the ESP32.
