# Desk companion guide

The optional TTP223 touch sensor turns the ESP32 OLED into a small QuotaGlow companion. The companion runs entirely on the ESP32; it does not change Wi-Fi, USB, pairing, or the desktop widget.

Touch reactions do not require Wi-Fi, USB data, or a running desktop widget. The normal face is local-first: missing Codex data no longer makes it look confused. When a DHT22 is connected, room comfort can influence its idle expression.

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
| Hold for at least 1.2 seconds | Open the OLED menu. In the menu, hold again to select. |
| Tap while the menu is open | Move to the next menu item. |

The menu provides Companion, Codex Usage, Room Climate, Auto Rotate, Wi-Fi Pairing, and Back. The selected display mode is stored in ESP32 memory and remains after a restart. The OLED remains dark while monitoring is paused or receives `POWER|OFF`.

## Expressions

| Condition | Expression |
|---|---|
| Comfortable room reading | Relaxed and happy |
| Warm, cool, dry, or humid room | Concerned, with a room-status label |
| DHT22 absent or not ready | Friendly neutral face |
| Tap or repeated taps | Happy or excited reaction |

Wi-Fi setup, pairing codes, and connection messages appear temporarily. A long hold can still open the menu, and the selected home screen returns afterward.

## Troubleshooting

**Touch does nothing:** confirm `OUT` is connected to GPIO 27 and the module is powered from 3V3 and GND.

**Touch is always active or erratic:** shorten jumper wires, confirm the breadboard rows are not bridged, and keep the sensor away from loose powered wires or metal surfaces.

**Touch behavior is reversed:** the firmware expects the usual active-high TTP223 output. If your unusual module reports LOW when touched, change the `digitalRead(TOUCH_PIN) == HIGH` comparison in the firmware.

**A tap opens or selects unexpectedly:** hold gestures start after 1.2 seconds. Release sooner for a pet reaction or menu movement.
