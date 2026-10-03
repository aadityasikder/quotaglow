# Changelog

All notable changes to QuotaGlow are documented here.

The project follows [Semantic Versioning](https://semver.org/).

## [1.2.0] - Pending hardware validation

### Added

- ESP32 captive-portal Wi-Fi provisioning, UDP discovery, pairing, and local HTTP API.
- Widget USB/Wi-Fi selection, manual-IP fallback, encrypted token storage, and bounded reconnection.
- Five-second BOOT-button reset for network and pairing data.

USB, desktop-only, and demo modes remain backward compatible. Bluetooth LE is deferred.

## [1.1.0] - 2026-10-03

### Added

- Always-on-top Windows desktop widget that works without ESP32 hardware.
- Live 5-hour and weekly usage cards with reset countdowns.
- Automatic 60-second refresh, manual refresh, and last-refresh time.
- Compact rounded usage-only mode with remembered position and view state.
- Optional ESP32 connection from a COM-port dropdown.
- OLED wake and sleep commands.
- Start-with-Windows option.
- Silent VBS launcher with no attached terminal window.
- Reusable PowerShell core module and automated regression checks.
- Public setup, widget, architecture, protocol, security, and troubleshooting documentation.

### Changed

- ESP32 hardware is now optional rather than required.
- The legacy console helper now shares the same core logic as the widget.
- Public branding and documentation now use the QuotaGlow project name.

## [1.0.0] - 2026-10-03

### Added

- Initial ESP32 and SSD1306 OLED usage monitor.
- Windows PowerShell helper using the local Codex app-server.
- Five-hour and weekly remaining percentages and reset countdowns.
- Demo mode, stale-data handling, and USB serial protocol.

[1.1.0]: https://github.com/aadityasikder/quotaglow/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/aadityasikder/quotaglow/releases/tag/v1.0.0
