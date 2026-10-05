# Room climate and OLED menu

QuotaGlow can read room temperature and humidity from a DHT11 or DHT22/AM2302-compatible sensor. This feature runs entirely on the ESP32 and does not require Codex, the desktop widget, USB data, or Wi-Fi. The reference firmware defaults to DHT11.

## Wiring

Disconnect the ESP32 from power before changing wires.

| DHT11 label | ESP32 label |
|---|---|
| `VCC` | `3V3` |
| `GND` | `GND` |
| `DATA` / `OUT` | `D26` / GPIO 26 |

Use 3.3V, not `VIN` or 5V. A bare four-pin sensor requires a 4.7–10 kΩ pull-up resistor from `DATA` to `3V3`. Most three-pin modules already contain the resistor.

For a DHT22, change this firmware line before uploading:

```cpp
constexpr uint8_t DHT_TYPE = DHT22;
```

Install **DHT sensor library by Adafruit** through Arduino IDE's Library Manager and accept its dependencies before compiling the firmware.

## Touch navigation

The same TTP223 on GPIO 27 controls the menu:

| Gesture | Result |
|---|---|
| Tap on the companion | Pet reaction |
| Hold for 1.2 seconds | Open the menu |
| Tap in the menu | Move to the next item |
| Hold in the menu | Select the current item |
| No input for 15 seconds | Close the menu |

The menu contains:

- **Companion:** keeps the local animated face visible.
- **Codex Usage:** keeps the existing usage dashboard visible.
- **Room Climate:** keeps temperature and humidity visible.
- **Ambient Light:** shows the calibrated light percentage and current light category.
- **Auto Rotate:** changes among available screens every eight seconds. It skips Usage without valid usage data and Climate without a valid sensor reading.
- **Auto Brightness:** enables or disables LDR-controlled OLED contrast.
- **Calibrate Light:** records dark and bright reference readings.
- **Wi-Fi Pairing:** shows the current pairing code and IP. If already paired, it shows that state without removing the saved token.
- **Back:** returns without changing the home mode.

The selected home mode is stored in ESP32 memory. Upgrading from v1.3 automatically converts the previous face-first or usage-first preference.

## Climate labels

| Reading | Label |
|---|---|
| Below 18°C | `COOL` |
| Above 28°C | `WARM` |
| Below 30% relative humidity | `DRY` |
| Above 70% relative humidity | `HUMID` |
| All other valid readings | `COMFY` |

These labels are informal desk-comfort hints, not health or safety measurements. The sensor is sampled every 2.5 seconds. A brief failed reading preserves the last value; three consecutive failures mark the sensor unavailable.

## Troubleshooting

**The Climate screen says `SENSOR UNAVAILABLE`:** wait at least eight seconds after startup, then check 3V3, GND, GPIO 26, the pull-up resistor, and that `DHT_TYPE` matches the physical sensor. Confirm that **DHT sensor library by Adafruit** is installed.

**Temperature or humidity jumps around:** shorten jumper wires, check the breadboard rows, keep the sensor away from the ESP32 voltage regulator, and avoid reading it directly in moving warm air.

**The menu does not open:** verify the TTP223 OUT wire is on GPIO 27. Hold continuously for at least 1.2 seconds.

**The old home screen changed after upgrading:** the firmware migrates `faceFirst=true` to Companion and `faceFirst=false` to Codex Usage. Select another mode through the menu to save it.
