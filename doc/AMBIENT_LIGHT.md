# Ambient awareness and LDR setup

An LDR lets QuotaGlow adapt to the room instead of behaving like a fixed-brightness display. Ambient awareness runs locally on the ESP32 and does not require Wi-Fi, USB data, or the Windows widget.

## Wiring

Disconnect power before changing wires. Build this voltage divider with an LDR and a 10 kΩ resistor:

```text
3V3 ── LDR ──┬── GPIO 34
             │
          10 kΩ
             │
            GND
```

GPIO 34 is input-only and belongs to ADC1, so it remains available while ESP32 Wi-Fi is running. Use 3.3V only. The calibration supports the opposite LDR/resistor order too, but the midpoint must still connect to GPIO 34.

## Calibration

1. Hold the TTP223 for 1.2 seconds to open the menu.
2. Tap until **Calibrate Light** is selected, then hold.
3. Cover the LDR or make the room as dark as its normal nighttime condition, then hold to save.
4. Shine a bright room light or flashlight toward the LDR, then hold again.

The readings must differ by at least 200 ADC counts. Calibration values are saved in ESP32 NVS and remain after restart. A short tap cancels calibration.

## Behaviors

- **Automatic brightness:** OLED contrast moves gradually between a dim nighttime level and full daytime contrast.
- **Dark-room sleep:** after the calibrated category stays `DARK` for 30 seconds, the companion closes its eyes.
- **Touch wake:** touching the TTP223 wakes it for 30 seconds and temporarily raises very low contrast so the reaction remains visible; a normal tap still produces a pet reaction.
- **Sudden-light reaction:** an increase of at least 35 calibrated percentage points within roughly one second produces a surprised face. A ten-second cooldown prevents repeated reactions.
- **Ambient Light screen:** shows the calibrated percentage, `DARK`, `DIM`, `NORMAL`, or `BRIGHT`, a progress bar, and auto-brightness status.

The light percentage is a relative room-light indicator, not a calibrated lux measurement.

## Menu settings

**Ambient Light** saves the sensor dashboard as the home screen. **Auto Rotate** includes it with the other available screens. **Auto Brightness** toggles contrast control and saves the preference. Turning automatic brightness off restores the normal SSD1306 contrast.

## Troubleshooting

If the reading remains at one extreme, check that GPIO 34 is connected to the divider midpoint. If it moves in the wrong direction, recalibrate; both divider orientations are supported. If it jumps around, shorten wires and reseat the resistor and LDR.
