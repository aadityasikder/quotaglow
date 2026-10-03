# USB Serial Protocol

## Transport

- Baud rate: 115200
- Data bits: 8
- Parity: none
- Stop bits: 1
- Encoding: ASCII-compatible text
- Framing: one message per line, terminated by `\n`
- Field separator: `|`

The protocol intentionally contains no credentials or account identifiers.

## Usage update

Example:

```text
LIMITS|35|5h|2h18m|58|7d|3d04h|1
```

| Position | Field | Example | Meaning |
|---:|---|---|---|
| 1 | Message type | `LIMITS` | Identifies a usage update |
| 2 | Primary remaining | `35` | Percentage from 0 through 100 |
| 3 | Primary window | `5h` | Compact duration label |
| 4 | Primary reset | `2h18m` | Countdown until reset |
| 5 | Secondary remaining | `58` | Percentage from 0 through 100; `-1` means absent |
| 6 | Secondary window | `7d` | Compact duration label or `-` |
| 7 | Secondary reset | `3d04h` | Countdown or `--` |
| 8 | Usage allowed | `1` | `1` for allowed, `0` for explicitly blocked |

The ESP32 rejects messages with a wrong field count, invalid numbers, percentages outside the accepted ranges, or empty required fields.

## Status messages

```text
STATUS|CODEX_ERROR
STATUS|NO_LIMIT_DATA
```

- `CODEX_ERROR` means the helper could not read usage from Codex.
- `NO_LIMIT_DATA` means Codex responded but provided no primary usage window.

If valid values were previously received, transient status messages do not erase them. After three minutes without another valid `LIMITS` message, the display shows `DATA STALE`.

## OLED power messages

```text
POWER|OFF
POWER|ON
```

- `POWER|OFF` clears the framebuffer and places the OLED controller in display-off mode. The ESP32 remains powered by USB.
- `POWER|ON` wakes the OLED and redraws the most recently received values.

Older `LIMITS` and `STATUS` messages are unchanged.

## Demo sequence

Demo mode sends:

```text
LIMITS|0|5h|2h18m|100|7d|3d04h|1
LIMITS|50|5h|2h17m|50|7d|3d04h|1
LIMITS|100|5h|2h16m|0|7d|3d04h|1
```

There is a five-second delay between samples during the normal demo.

## Compatibility guidance

Future firmware and helper versions should preserve the eight-field `LIMITS` message for backward compatibility. A new message type is preferable to silently changing the meaning or order of existing fields.
