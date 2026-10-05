# Architecture

In v1.2 the widget sends display lines through a background transport worker. It owns either USB serial or the authenticated Wi-Fi client, while Codex polling continues independently. The ESP32 processes both transports through the same parser.

Wi-Fi credentials live only in ESP32 NVS. The device token is stored in ESP32 NVS and encrypted with Windows current-user DPAPI in desktop settings. Discovery exposes only non-sensitive metadata.

The desk companion is firmware-local. GPIO 27 receives TTP223 touch input, while a separate `companion` NVS namespace stores the selected face-first or usage-first display mode. It consumes the existing parsed quota state and does not add a transport message or desktop setting.

## Overview

The monitor has a reusable core and two user interfaces:

```text
Codex account
     │
     ▼
Local Codex app-server
     │ JSON messages over standard input/output
     ▼
QuotaGlow PowerShell core
     ├──────────────► Floating WPF desktop widget
     │ compact text messages over USB serial
     ▼
ESP32 firmware
     │ I²C
     ▼
SSD1306 OLED
```

The desktop widget works independently of the ESP32. The Windows core is required because the ESP32 does not authenticate with OpenAI and does not hold account credentials.

## Desktop widget

`desktop-widget/QuotaGlow.ps1` is a borderless, always-on-top WPF interface. A background PowerShell runspace owns Codex polling so app-server startup and network delays cannot block the UI thread. Thread-safe queues carry refresh, pause, resume, and stop commands and return snapshots or errors.

The UI thread owns the optional serial port. Successful snapshots update the widget first and are then mirrored to the module. A module failure therefore cannot interrupt desktop usage monitoring.

## Windows helper

`pc-helper/QuotaGlow.Core.psm1` performs the following work for both interfaces:

1. Opens the configured ESP32 COM port at 115200 baud.
2. Locates `codex.exe` through the normal command path or the Codex desktop installation.
3. Starts `codex app-server` locally.
4. Completes the app-server initialization handshake with experimental API support enabled.
5. Calls the read-only `account/rateLimits/read` operation.
6. Prefers the `codex` entry in `rateLimitsByLimitId` and falls back to `rateLimits`.
7. Converts used percentages into remaining percentages.
8. Converts window durations and reset timestamps into compact display text.
9. Sends one update to the ESP32 every 60 seconds.

`pc-helper/codex_usage_helper.ps1` remains as a console and demo interface for diagnostics.

The helper never requests a model response and never uses reset credits. The rate-limit read is experimental and may need adjustment after a future Codex update.

## ESP32 firmware

The firmware:

- Starts I²C on GPIO 21 and GPIO 22.
- Detects the OLED at address `0x3C` or `0x3D`.
- Receives newline-terminated USB serial messages.
- Supports OLED wake and sleep commands from the widget.
- Validates field count, numeric ranges, and message length.
- Displays the two usage windows and progress bars.
- Alternates their reset countdowns every four seconds.
- Keeps the last valid data during short communication failures.
- Marks data stale after three minutes without a valid update.

## Security boundary

Credentials remain inside the existing Codex installation. The project does not read, save, print, or send access tokens, passwords, API keys, or account IDs. The ESP32 receives only display-ready usage information.

Keep that boundary intact when extending the project. Do not copy Codex authentication files into this repository or firmware.

## Known constraints

- Windows is required by the current PowerShell launcher.
- The computer and widget/helper must remain running.
- Communication uses USB rather than Wi-Fi.
- The OLED layout targets 128×64 SSD1306-compatible displays.
- The local Codex rate-limit operation is experimental.
