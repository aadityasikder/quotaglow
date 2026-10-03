# Troubleshooting

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
