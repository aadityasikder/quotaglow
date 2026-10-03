# Contributing to QuotaGlow

Thank you for helping improve QuotaGlow.

## Development workflow

1. Fork or clone the repository.
2. Check out `develop` and update it.
3. Create a focused branch such as `feature/widget-theme` or `fix/serial-reconnect`.
4. Make and test your changes.
5. Open a pull request into `develop`.

Release-ready changes are merged from `develop` into `main`. Do not target `main` directly for normal feature work.

## Local checks

Run from Windows PowerShell in the repository root:

```powershell
.\tests\Test-QuotaGlow.ps1
```

For firmware changes, also compile and upload the sketch with Arduino IDE and test against a physical SSD1306 display.

## Pull-request expectations

- Keep each pull request focused on one feature or fix.
- Explain user-visible behavior and testing performed.
- Preserve the existing serial protocol unless a versioned extension is necessary.
- Update README or `doc/` when behavior, setup, or interfaces change.
- Never commit credentials, Codex authentication files, account IDs, or local settings.
- Keep the widget usable without an ESP32 attached.

## Coding guidance

- Maintain Windows PowerShell 5.1 compatibility.
- Avoid adding runtime dependencies unless the benefit clearly justifies them.
- Keep Codex polling outside the WPF UI thread.
- Treat serial failures as module failures, not desktop-monitoring failures.
- Use ASCII text in PowerShell/WPF source where practical to avoid Windows PowerShell encoding problems.

## Reporting bugs

Include:

- Windows version
- Codex installation type
- Whether the desktop-only widget works
- ESP32 board and OLED model, if relevant
- Exact error text
- Steps needed to reproduce the issue

Remove account identifiers and credentials from logs or screenshots before posting.
