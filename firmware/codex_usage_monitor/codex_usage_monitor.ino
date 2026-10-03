#include <Wire.h>
#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>
#include "QuotaGlowNetwork.h"

constexpr int SCREEN_WIDTH = 128;
constexpr int SCREEN_HEIGHT = 64;
constexpr int OLED_RESET = -1;
constexpr int SDA_PIN = 21;
constexpr int SCL_PIN = 22;
constexpr unsigned long STALE_AFTER_MS = 180000UL;
constexpr unsigned long RESET_PAGE_MS = 4000UL;

Adafruit_SSD1306 display(SCREEN_WIDTH, SCREEN_HEIGHT, &Wire, OLED_RESET);

bool displayReady = false;
bool displayPowered = true;
bool haveLimits = false;
bool usageAllowed = true;
int primaryRemaining = 0;
int secondaryRemaining = -1;
String primaryWindow = "-";
String secondaryWindow = "-";
String primaryReset = "--";
String secondaryReset = "--";
String statusMessage = "WAITING FOR PC";
String serialLine;
unsigned long lastValidUpdate = 0;
bool lastResetPage = false;

int clampPercent(int value) {
  if (value < 0) return 0;
  if (value > 100) return 100;
  return value;
}

bool isInteger(const String &value) {
  if (value.length() == 0) return false;
  int start = value[0] == '-' ? 1 : 0;
  if (start == 1 && value.length() == 1) return false;
  for (unsigned int i = start; i < value.length(); i++) {
    if (!isDigit(value[i])) return false;
  }
  return true;
}

int splitFields(const String &input, String fields[], int maximumFields) {
  int count = 0;
  int start = 0;
  for (unsigned int i = 0; i <= input.length() && count < maximumFields; i++) {
    if (i == input.length() || input[i] == '|') {
      fields[count++] = input.substring(start, i);
      start = i + 1;
    }
  }
  return count;
}

void drawProgressBar(int x, int y, int width, int height, int percent) {
  display.drawRect(x, y, width, height, SSD1306_WHITE);
  int innerWidth = width - 2;
  int filledWidth = (innerWidth * clampPercent(percent)) / 100;
  if (filledWidth > 0) {
    display.fillRect(x + 1, y + 1, filledWidth, height - 2, SSD1306_WHITE);
  }
}

void drawCenteredMessage(const String &line1, const String &line2 = "") {
  if (!displayReady || !displayPowered) return;
  display.clearDisplay();
  display.setTextColor(SSD1306_WHITE);
  display.setTextSize(1);
  display.setCursor(0, 17);
  display.println(line1);
  if (line2.length() > 0) {
    display.setCursor(0, 33);
    display.println(line2);
  }
  display.display();
}

void drawLimits() {
  if (!displayReady || !displayPowered) return;

  if (!haveLimits) {
    drawCenteredMessage(statusMessage);
    return;
  }

  if (!usageAllowed) {
    drawCenteredMessage("LIMIT REACHED", "Check Codex on PC");
    return;
  }

  bool stale = millis() - lastValidUpdate >= STALE_AFTER_MS;
  bool showSecondaryReset = secondaryRemaining >= 0 && ((millis() / RESET_PAGE_MS) % 2 == 1);

  display.clearDisplay();
  display.setTextColor(SSD1306_WHITE);
  display.setTextSize(1);
  display.setCursor(25, 0);
  display.print("CODEX USAGE");

  display.setCursor(0, 10);
  display.print(primaryWindow);
  display.setCursor(65, 10);
  display.print(primaryRemaining);
  display.print("% LEFT");
  drawProgressBar(0, 20, 128, 7, primaryRemaining);

  if (secondaryRemaining >= 0) {
    display.setCursor(0, 30);
    display.print(secondaryWindow);
    display.setCursor(65, 30);
    display.print(secondaryRemaining);
    display.print("% LEFT");
    drawProgressBar(0, 40, 128, 7, secondaryRemaining);
  } else {
    display.setCursor(0, 33);
    display.print("Second limit: N/A");
  }

  display.setCursor(0, 54);
  if (stale) {
    display.print("DATA STALE");
  } else {
    display.print("Reset: ");
    display.print(showSecondaryReset ? secondaryReset : primaryReset);
  }
  display.display();
}

void handleStatus(const String fields[], int count) {
  if (count != 2) return;
  if (fields[1] == "CODEX_ERROR") {
    statusMessage = "CODEX ERROR";
  } else if (fields[1] == "NO_LIMIT_DATA") {
    statusMessage = "NO LIMIT DATA";
  } else {
    return;
  }

  Serial.print("Status received: ");
  Serial.println(statusMessage);
  if (!haveLimits) drawLimits();
}

void handleLimits(const String fields[], int count) {
  if (count != 8 || !isInteger(fields[1]) || !isInteger(fields[4]) || !isInteger(fields[7])) {
    Serial.println("Ignored malformed LIMITS message");
    return;
  }

  int newPrimary = fields[1].toInt();
  int newSecondary = fields[4].toInt();
  int newAllowed = fields[7].toInt();
  if (newPrimary < 0 || newPrimary > 100 || newSecondary < -1 || newSecondary > 100 ||
      (newAllowed != 0 && newAllowed != 1) || fields[2].length() == 0 ||
      fields[3].length() == 0 || fields[5].length() == 0 || fields[6].length() == 0) {
    Serial.println("Ignored out-of-range LIMITS message");
    return;
  }

  primaryRemaining = clampPercent(newPrimary);
  secondaryRemaining = newSecondary < 0 ? -1 : clampPercent(newSecondary);
  primaryWindow = fields[2].substring(0, 8);
  primaryReset = fields[3].substring(0, 12);
  secondaryWindow = fields[5].substring(0, 8);
  secondaryReset = fields[6].substring(0, 12);
  usageAllowed = newAllowed == 1;
  haveLimits = true;
  lastValidUpdate = millis();
  statusMessage = "";

  Serial.println("Valid usage update received");
  drawLimits();
}

void handlePower(const String fields[], int count) {
  if (count != 2 || !displayReady) return;

  if (fields[1] == "OFF") {
    display.clearDisplay();
    display.display();
    display.ssd1306_command(SSD1306_DISPLAYOFF);
    displayPowered = false;
    Serial.println("OLED powered off by PC");
  } else if (fields[1] == "ON") {
    display.ssd1306_command(SSD1306_DISPLAYON);
    displayPowered = true;
    Serial.println("OLED powered on by PC");
    drawLimits();
  }
}

void handleSerialLine(String line) {
  line.trim();
  if (line.length() == 0) return;

  String fields[8];
  int count = splitFields(line, fields, 8);
  if (fields[0] == "LIMITS") {
    handleLimits(fields, count);
  } else if (fields[0] == "STATUS") {
    handleStatus(fields, count);
  } else if (fields[0] == "POWER") {
    handlePower(fields, count);
  } else {
    Serial.println("Ignored unknown serial message");
  }
}

void handleNetworkLine(String line) {
  handleSerialLine(line);
}

void showNetworkMessage(const String &line1, const String &line2) {
  drawCenteredMessage(line1, line2);
}

bool beginDisplay() {
  const uint8_t addresses[] = {0x3C, 0x3D};
  for (uint8_t address : addresses) {
    Wire.beginTransmission(address);
    if (Wire.endTransmission() == 0) {
      if (display.begin(SSD1306_SWITCHCAPVCC, address)) {
        Serial.print("OLED detected at 0x");
        Serial.println(address, HEX);
        return true;
      }
    }
  }
  return false;
}

void setup() {
  Serial.begin(115200);
  delay(300);
  Serial.println();
  Serial.println("Codex Usage Monitor starting");

  Wire.begin(SDA_PIN, SCL_PIN);
  displayReady = beginDisplay();
  if (!displayReady) {
    Serial.println("OLED not found at 0x3C or 0x3D");
  } else {
    display.clearDisplay();
    display.display();
    drawCenteredMessage("WAITING FOR PC", "USB 115200 baud");
  }
  Serial.println("Waiting for usage data from PC");
  beginQuotaGlowNetwork(handleNetworkLine, showNetworkMessage);
}

void loop() {
  loopQuotaGlowNetwork();
  while (Serial.available() > 0) {
    char incoming = static_cast<char>(Serial.read());
    if (incoming == '\n') {
      handleSerialLine(serialLine);
      serialLine = "";
    } else if (incoming != '\r') {
      if (serialLine.length() < 160) {
        serialLine += incoming;
      } else {
        serialLine = "";
        Serial.println("Discarded oversized serial message");
      }
    }
  }

  if (displayPowered && haveLimits && usageAllowed) {
    bool resetPage = secondaryRemaining >= 0 && ((millis() / RESET_PAGE_MS) % 2 == 1);
    static bool wasStale = false;
    bool stale = millis() - lastValidUpdate >= STALE_AFTER_MS;
    if (resetPage != lastResetPage || stale != wasStale) {
      lastResetPage = resetPage;
      wasStale = stale;
      drawLimits();
    }
  }

  delay(10);
}
