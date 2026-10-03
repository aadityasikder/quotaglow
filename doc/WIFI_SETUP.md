# Wi-Fi setup and pairing

QuotaGlow v1.2 can update the OLED through a trusted local 2.4 GHz Wi-Fi network. USB serial remains available, and a phone charger or power bank can power the ESP32 for wireless placement.

## First-time setup

1. Upload the v1.2 firmware and restart the ESP32.
2. Join `QuotaGlow-Setup-XXXX` from a phone or computer.
3. If the setup page does not open, browse to `http://192.168.4.1`.
4. Enter your 2.4 GHz Wi-Fi name and password. They stay in ESP32 NVS and are never sent to Windows.
5. Wait for the OLED to show an IP address and six-digit pairing code.
6. Open QuotaGlow, choose **Wi-Fi**, and select **Rescan**.
7. Select the module. If discovery fails, type the OLED's IP address into the address field.
8. Enter the OLED code and select **Pair**.

The code expires after ten minutes, and repeated incorrect attempts are rate-limited. Restart the ESP32 for a fresh code.

## Normal use

QuotaGlow remembers one module and reconnects after launch. Retry delays increase to approximately 5, 15, 30, then 60 seconds. Desktop usage monitoring continues while the module is offline. **Forget** removes the saved Windows token and unpairs the module.

## Reset the module

Hold the ESP32 **BOOT** button for five seconds. The OLED confirms the reset, Wi-Fi and pairing data are erased, and setup mode restarts. Firmware is not erased.

## Safety

The API uses authenticated HTTP, not HTTPS. A person controlling the network could observe traffic. Use Wi-Fi mode only on a trusted private network—never public, guest, school, hotel, or café Wi-Fi. No Codex credentials or account identifiers are sent to the ESP32.

## Existing USB users

Upload the new firmware and continue selecting **USB** in the widget. Existing wiring, demo mode, and serial messages remain compatible. Wi-Fi setup is optional.
