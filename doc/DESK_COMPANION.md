# Desk companion guide

The optional TTP223 touch sensor turns the ESP32 OLED into a small QuotaGlow companion. The companion runs entirely on the ESP32; it does not change Wi-Fi, USB, pairing, or the desktop widget.

Touch reactions do not require Wi-Fi, USB data, or a running desktop widget. Without a valid usage update, the companion normally looks confused, but taps still show its happy reaction before it returns to that no-data state.

## Wiring

| TTP223 label | ESP32 label |
|---|---|
| `VCC` | `3V3` |
| `GND` | `GND` |
| `OUT` | `D27` / GPIO 27 |

Use a standard active-high TTP223 module. Do not connect its `VCC` pin to 5V or `VIN`; the ESP32 GPIO pins are 3.3V-only.

## Controls

| Gesture | Behavior |
|---|---|
| Tap for 50–700 ms | Pet the companion; it reacts happily. Rapid taps make it excited. |
| Hold for at least 1.2 seconds | Toggle between face-first and usage-first display mode. |

The selected display mode is stored in ESP32 memory and remains after a restart. The OLED remains dark while monitoring is paused or receives `POWER|OFF`.

## Expressions

| Condition | Expression |
|---|---|
| More than 50% remains | Happy |
| 21–50% remains | Neutral |
| 1–20% remains | Worried |
| No ordinary usage remains | Exhausted |
| No data, stale data, or a Codex error | Confused |

Wi-Fi setup, pairing codes, and connection messages temporarily take priority over the face so setup information stays readable.

## Troubleshooting

**Touch does nothing:** confirm `OUT` is connected to GPIO 27 and the module is powered from 3V3 and GND.

**Touch is always active or erratic:** shorten jumper wires, confirm the breadboard rows are not bridged, and keep the sensor away from loose powered wires or metal surfaces.

**Touch behavior is reversed:** the firmware expects the usual active-high TTP223 output. If your unusual module reports LOW when touched, change the `digitalRead(TOUCH_PIN) == HIGH` comparison in the firmware.

**A tap toggles the display:** hold gestures start after 1.2 seconds. Release the sensor sooner for a pet reaction.
