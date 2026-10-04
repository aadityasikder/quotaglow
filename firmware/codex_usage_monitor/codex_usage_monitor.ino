#include <Wire.h>
#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>
#include <Preferences.h>
#include "QuotaGlowNetwork.h"

constexpr int SCREEN_WIDTH = 128;
constexpr int SCREEN_HEIGHT = 64;
constexpr int OLED_RESET = -1;
constexpr int SDA_PIN = 21;
constexpr int SCL_PIN = 22;
constexpr int TOUCH_PIN = 27;
constexpr unsigned long STALE_AFTER_MS = 180000UL;
constexpr unsigned long RESET_PAGE_MS = 4000UL;
constexpr unsigned long TOUCH_DEBOUNCE_MS = 250UL;
constexpr unsigned long TAP_MIN_MS = 50UL;
constexpr unsigned long TAP_MAX_MS = 700UL;
constexpr unsigned long HOLD_MS = 1200UL;
constexpr unsigned long PET_REACTION_MS = 1500UL;
constexpr unsigned long PET_CHAIN_MS = 1500UL;
constexpr unsigned long NETWORK_MESSAGE_MS = 3500UL;
constexpr unsigned long FRAME_INTERVAL_MS = 80UL;

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
Preferences companionPreferences;
bool companionFaceFirst = true;
bool touchWasDown = false;
bool touchIgnored = false;
bool holdHandled = false;
unsigned long touchStartedAt = 0;
unsigned long ignoreTouchUntil = 0;
unsigned long reactionUntil = 0;
unsigned long lastPetAt = 0;
unsigned long lastFrameAt = 0;
unsigned long networkMessageUntil = 0;
uint8_t petChainCount = 0;
String networkLine1;
String networkLine2;
bool networkMessageActive = false;

enum CompanionMood { MOOD_HAPPY, MOOD_NEUTRAL, MOOD_WORRIED, MOOD_EXHAUSTED, MOOD_CONFUSED };
enum PetReaction { REACTION_NONE, REACTION_HAPPY, REACTION_EXCITED };
PetReaction activeReaction = REACTION_NONE;

void drawLimits();

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

CompanionMood currentMood() {
  if (!haveLimits || statusMessage.length() > 0 || millis() - lastValidUpdate >= STALE_AFTER_MS) {
    return MOOD_CONFUSED;
  }
  if (!usageAllowed || primaryRemaining <= 0) return MOOD_EXHAUSTED;
  if (primaryRemaining <= 20) return MOOD_WORRIED;
  if (primaryRemaining <= 50) return MOOD_NEUTRAL;
  return MOOD_HAPPY;
}

bool shouldBlink() {
  unsigned long phase = millis() % 4800UL;
  return phase >= 4200UL && phase < 4360UL;
}

void drawEye(int x, int y, bool blink, bool worried) {
  if (blink) {
    display.drawLine(x - 7, y, x + 7, y, SSD1306_WHITE);
  } else if (worried) {
    display.drawLine(x - 7, y - 3, x + 7, y + 2, SSD1306_WHITE);
    display.fillCircle(x, y + 5, 4, SSD1306_WHITE);
  } else {
    display.fillRoundRect(x - 5, y - 7, 10, 15, 5, SSD1306_WHITE);
  }
}

void drawCompanionFace(CompanionMood mood, PetReaction reaction = REACTION_NONE) {
  if (!displayReady || !displayPowered) return;

  bool blink = shouldBlink() && reaction == REACTION_NONE;
  bool worried = mood == MOOD_WORRIED;
  display.clearDisplay();
  display.setTextColor(SSD1306_WHITE);
  display.setTextSize(1);
  display.setCursor(31, 2);
  display.print("QUOTAGLOW");

  if (mood == MOOD_CONFUSED) {
    display.drawCircle(39, 31, 8, SSD1306_WHITE);
    display.fillCircle(39, 31, 2, SSD1306_WHITE);
    display.drawLine(79, 24, 90, 24, SSD1306_WHITE);
    display.setCursor(83, 35);
    display.print("?");
    display.drawLine(53, 49, 64, 45, SSD1306_WHITE);
    display.drawLine(64, 45, 75, 49, SSD1306_WHITE);
    display.setCursor(16, 55);
    display.print("waiting for data");
  } else if (mood == MOOD_EXHAUSTED) {
    display.drawLine(31, 30, 46, 30, SSD1306_WHITE);
    display.drawLine(82, 30, 97, 30, SSD1306_WHITE);
    display.drawLine(53, 47, 75, 47, SSD1306_WHITE);
    display.setCursor(30, 55);
    display.print("time to recharge");
  } else {
    drawEye(39, 31, blink, worried);
    drawEye(89, 31, blink, worried);
    if (reaction == REACTION_EXCITED) {
      display.drawLine(52, 43, 58, 51, SSD1306_WHITE);
      display.drawLine(58, 51, 64, 43, SSD1306_WHITE);
      display.drawLine(64, 43, 70, 51, SSD1306_WHITE);
      display.drawLine(70, 51, 76, 43, SSD1306_WHITE);
      display.setCursor(42, 55);
      display.print("so happy!");
    } else if (reaction == REACTION_HAPPY || mood == MOOD_HAPPY) {
      display.drawLine(52, 43, 58, 49, SSD1306_WHITE);
      display.drawLine(58, 49, 70, 49, SSD1306_WHITE);
      display.drawLine(70, 49, 76, 43, SSD1306_WHITE);
      display.setCursor(43, 55);
      display.print(reaction == REACTION_HAPPY ? "thanks!" : "all good");
    } else if (mood == MOOD_WORRIED) {
      display.drawLine(52, 50, 64, 43, SSD1306_WHITE);
      display.drawLine(64, 43, 76, 50, SSD1306_WHITE);
      display.setCursor(14, 55);
      display.print("quota running low");
    } else {
      display.drawLine(53, 47, 75, 47, SSD1306_WHITE);
      display.setCursor(39, 55);
      display.print("tap to pet");
    }
  }
  display.display();
}

void renderDisplay() {
  if (!displayReady || !displayPowered) return;
  unsigned long now = millis();
  if (networkMessageActive) {
    if (networkMessageUntil == 0 || now < networkMessageUntil) {
      drawCenteredMessage(networkLine1, networkLine2);
      return;
    }
    networkMessageActive = false;
  }
  if (activeReaction != REACTION_NONE && now < reactionUntil) {
    drawCompanionFace(currentMood(), activeReaction);
  } else {
    activeReaction = REACTION_NONE;
    if (companionFaceFirst) drawCompanionFace(currentMood());
    else drawLimits();
  }
}

void triggerPetReaction() {
  unsigned long now = millis();
  if (now - lastPetAt <= PET_CHAIN_MS) {
    if (petChainCount < 3) petChainCount++;
  } else {
    petChainCount = 1;
  }
  lastPetAt = now;
  activeReaction = petChainCount >= 2 ? REACTION_EXCITED : REACTION_HAPPY;
  reactionUntil = now + PET_REACTION_MS;
  Serial.println(activeReaction == REACTION_EXCITED ? "Companion excited" : "Companion petted");
}

void toggleCompanionMode() {
  companionFaceFirst = !companionFaceFirst;
  companionPreferences.putBool("faceFirst", companionFaceFirst);
  activeReaction = REACTION_NONE;
  Serial.println(companionFaceFirst ? "Companion face mode" : "Usage dashboard mode");
}

void updateTouch() {
  unsigned long now = millis();
  bool down = digitalRead(TOUCH_PIN) == HIGH;
  if (down && !touchWasDown) {
    touchWasDown = true;
    touchStartedAt = now;
    touchIgnored = now < ignoreTouchUntil;
    holdHandled = false;
  }
  if (down && touchWasDown && !touchIgnored && !holdHandled && now - touchStartedAt >= HOLD_MS) {
    holdHandled = true;
    ignoreTouchUntil = now + TOUCH_DEBOUNCE_MS;
    toggleCompanionMode();
  }
  if (!down && touchWasDown) {
    unsigned long duration = now - touchStartedAt;
    if (!touchIgnored && !holdHandled && duration >= TAP_MIN_MS && duration <= TAP_MAX_MS) {
      triggerPetReaction();
      ignoreTouchUntil = now + TOUCH_DEBOUNCE_MS;
    }
    touchWasDown = false;
  }
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
  renderDisplay();
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
  renderDisplay();
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
    renderDisplay();
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
  networkLine1 = line1;
  networkLine2 = line2;
  networkMessageActive = true;
  networkMessageUntil = (line1.startsWith("QuotaGlow-Setup-") || line1.startsWith("Pair:"))
                            ? 0
                            : millis() + NETWORK_MESSAGE_MS;
  renderDisplay();
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

  pinMode(TOUCH_PIN, INPUT);
  companionPreferences.begin("companion", false);
  companionFaceFirst = companionPreferences.getBool("faceFirst", true);

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
  updateTouch();
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

  if (millis() - lastFrameAt >= FRAME_INTERVAL_MS) {
    lastFrameAt = millis();
    renderDisplay();
  }

  delay(10);
}
