# Architecture

In v1.2 the widget sends display lines through a background transport worker. It owns either USB serial or the authenticated Wi-Fi client, while Codex polling continues independently. The ESP32 processes both transports through the same parser.

Wi-Fi credentials live only in ESP32 NVS. The device token is stored in ESP32 NVS and encrypted with Windows current-user DPAPI in desktop settings. Discovery exposes only non-sensitive metadata.

The desk companion is firmware-local. GPIO 27 receives TTP223 touch input, GPIO 26 reads the configured DHT11 or DHT22 sensor, and ADC1 GPIO 34 samples the LDR divider. The `companion` NVS namespace stores the home mode, auto-brightness preference, and light calibration. Existing `faceFirst` values are migrated once. These local features do not add a transport message or desktop setting.

## Overview

The Windows monitor is optional. Local touch and climate features continue running directly on the ESP32:

```text
Codex account
     │
     ▼
Local Codex app-server
     │ JSON messages over standard input/output
     ▼
QuotaGlow PowerShell core ─────► Floating WPF desktop widget
     │ optional display messages over USB or trusted Wi-Fi
     ▼
ESP32 firmware ◄──────── TTP223 touch (GPIO 27)
     ▲
     └────────────────── DHT climate sensor (GPIO 26)
     └────────────────── LDR divider (ADC1 GPIO 34)
     │ I²C
     ▼
SSD1306 OLED and local menu
```

The desktop widget works independently of the ESP32, and the companion and climate screens work independently of Windows. The Windows core is required only for Codex usage because the ESP32 does not authenticate with OpenAI and does not hold account credentials.

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
- Samples the configured DHT sensor every 2.5 seconds and preserves readings through brief failures.
- Runs a touch-controlled menu and persists the selected home mode.
- Rotates only among currently available screens when Auto Rotate is selected.
- Smooths LDR samples, applies category hysteresis, and gradually adjusts SSD1306 contrast.
- Detects sustained darkness, touch wakeups, and sudden bright-light changes locally.

Display priority is: powered-off state, light calibration, user-opened menu, temporary network notice, companion reaction, and the selected home screen. This lets a user open the menu even while Wi-Fi setup information is visible.

## Security boundary

Credentials remain inside the existing Codex installation. The project does not read, save, print, or send access tokens, passwords, API keys, or account IDs. The ESP32 receives only display-ready usage information.

Keep that boundary intact when extending the project. Do not copy Codex authentication files into this repository or firmware.

## Known constraints

- Windows is required by the current PowerShell launcher.
- The computer and widget/helper must remain running.
- Module communication supports USB or authenticated HTTP on a trusted local Wi-Fi network.
- The OLED layout targets 128×64 SSD1306-compatible displays.
- The local Codex rate-limit operation is experimental.
