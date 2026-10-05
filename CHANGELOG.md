# Changelog

All notable changes to QuotaGlow are documented here.

The project follows [Semantic Versioning](https://semver.org/).

## [1.4.0] - 2026-10-06

### Added

- DHT11 room temperature and humidity monitoring on GPIO 26, with a documented DHT22 configuration option.
- Touch-controlled OLED menu with persistent Companion, Codex Usage, Room Climate, and Auto Rotate modes.
- On-demand Wi-Fi pairing information without silently unpairing an existing module.
- Local-first companion moods that work without Codex usage data.
- Room climate setup guide and future-feature roadmap.
- LDR ambient sensing on ADC1 GPIO 34 with guided dark/bright calibration.
- Automatic OLED contrast, dark-room sleep, touch wake, and sudden-light companion reactions.
- Persistent Ambient Light home screen and auto-brightness menu setting.

### Changed

- Initial Wi-Fi and pairing notices now time out so they do not permanently replace the selected home screen.
- The legacy face-first preference is migrated automatically to the new saved home-mode setting.

USB, Wi-Fi, pairing, desktop-only, and legacy display protocols remain backward compatible.

## [1.3.0] - 2026-10-06

### Added

- Optional TTP223 touch sensor support on GPIO 27.
- Animated face-first desk companion with idle blinking and quota-aware moods.
- Tap-to-pet happy and excited reactions that work without usage data or Wi-Fi.
- Persistent touch-and-hold switching between companion and usage-dashboard modes.
- Desk companion wiring, controls, expressions, and troubleshooting documentation.

USB, Wi-Fi, pairing, desktop-only, and legacy display protocols remain backward compatible.

## [1.2.0] - 2026-10-04

### Added

- ESP32 captive-portal Wi-Fi provisioning, UDP discovery, pairing, and local HTTP API.
- Widget USB/Wi-Fi selection, manual-IP fallback, encrypted token storage, and bounded reconnection.
- Five-second BOOT-button reset for network and pairing data.
- Added single-instance protection, existing-window activation, and a verified force-stop launcher.

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

[1.3.0]: https://github.com/aadityasikder/quotaglow/compare/v1.2.0...v1.3.0
[1.4.0]: https://github.com/aadityasikder/quotaglow/compare/v1.3.0...v1.4.0
[1.2.0]: https://github.com/aadityasikder/quotaglow/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/aadityasikder/quotaglow/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/aadityasikder/quotaglow/releases/tag/v1.0.0
