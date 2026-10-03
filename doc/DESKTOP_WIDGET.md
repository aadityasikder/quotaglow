# Floating Desktop Widget

The module selector supports **USB** and **Wi-Fi**. Wi-Fi mode provides discovery, manual IP entry, six-digit pairing, forgetting a device, and automatic reconnection. Module work runs in the background, so an offline ESP32 does not freeze or stop Codex refreshes.

QuotaGlow includes a compact Windows widget that works with or without the ESP32 module. It reads Codex usage every 60 seconds and stays above normal windows.

## Start the widget

Double-click:

```text
start_quotaglow.vbs
```

The VBS launcher starts PowerShell invisibly, so no terminal window remains beside the widget. `start_quotaglow.cmd` remains as a compatibility launcher and immediately hands off to the silent VBS launcher.

Only one QuotaGlow widget can run per Windows user. Launching it again activates the existing window. `stop_quotaglow.cmd` requests a clean shutdown and then closes any verified older or unresponsive QuotaGlow instances.

The first reading can take several seconds while the local Codex service starts.

## Controls

- **Refresh** requests a new reading immediately. Repeated clicks do not create overlapping requests.
- **-** collapses the full card into a short rounded usage bar.
- **+** restores the full controls from compact mode.
- **COM port** selects the optional ESP32 module.
- **Rescan** updates the list of available COM ports.
- **Connect Module** opens the selected port and sends the latest values to the OLED.
- **Disconnect Module** closes only the module connection; desktop monitoring continues.
- **Pause Monitoring** stops Codex polling, sends `POWER|OFF` to a connected OLED, and disconnects the module.
- **Resume Monitoring** restarts desktop polling. Reconnect the module manually when wanted.
- **Start with Windows** adds or removes a current-user startup entry. Administrator access is not required.
- **×** closes QuotaGlow, stops its local Codex service, and darkens a connected OLED.

Compact mode shows only the connection indicator and the 5-hour and 7-day remaining percentages. Monitoring and optional OLED updates continue normally while compact.

Drag the title area—or the empty portion of the compact bar—to move the widget. Its position and compact/expanded state are restored on the next launch. If a saved position is no longer visible after monitor changes, QuotaGlow opens in the center of the primary screen.

## Status colors

- Green: live data is available.
- Amber: starting, refreshing, or stale.
- Red: Codex or module error.
- Gray: monitoring is paused.

The status text distinguishes desktop-only mode from an attached module. The last successful refresh time remains visible when a later request fails.

## Optional ESP32 module

The widget does not require the ESP32. To attach it:

1. Upload the latest firmware containing `POWER|ON` and `POWER|OFF` support.
2. Connect the ESP32 by USB.
3. Close Arduino Serial Monitor.
4. Choose its COM port.
5. Select **Connect Module**.

The widget immediately sends its latest reading and mirrors each later refresh. A serial failure disconnects the module without stopping desktop monitoring.

## Local settings

Non-sensitive settings are stored at:

```text
%LOCALAPPDATA%\QuotaGlow\settings.json
```

The file contains only the selected COM port, widget position, compact/expanded state, and startup preference. It contains no OpenAI credentials, account IDs, or usage history.

Delete this file while QuotaGlow is closed to restore defaults.
