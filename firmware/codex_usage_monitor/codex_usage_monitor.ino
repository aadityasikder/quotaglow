#include <Wire.h>
#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>
#include <DHT.h>
#include <Preferences.h>
#include "QuotaGlowNetwork.h"

constexpr int SCREEN_WIDTH = 128;
constexpr int SCREEN_HEIGHT = 64;
constexpr int OLED_RESET = -1;
constexpr int SDA_PIN = 21;
constexpr int SCL_PIN = 22;
constexpr int DHT_PIN = 26;
constexpr int TOUCH_PIN = 27;
constexpr int LDR_PIN = 34;
constexpr uint8_t DHT_TYPE = DHT11;
constexpr unsigned long STALE_AFTER_MS = 180000UL;
constexpr unsigned long RESET_PAGE_MS = 4000UL;
constexpr unsigned long TOUCH_DEBOUNCE_MS = 250UL;
constexpr unsigned long TAP_MIN_MS = 50UL;
constexpr unsigned long TAP_MAX_MS = 700UL;
constexpr unsigned long HOLD_MS = 1200UL;
constexpr unsigned long PET_REACTION_MS = 1500UL;
constexpr unsigned long PET_CHAIN_MS = 1500UL;
constexpr unsigned long NETWORK_MESSAGE_MS = 3500UL;
constexpr unsigned long NETWORK_LONG_MESSAGE_MS = 15000UL;
constexpr unsigned long MENU_TIMEOUT_MS = 15000UL;
constexpr unsigned long AUTO_ROTATE_MS = 8000UL;
constexpr unsigned long CLIMATE_READ_MS = 2500UL;
constexpr unsigned long LIGHT_SAMPLE_MS = 100UL;
constexpr unsigned long LIGHT_BASELINE_MS = 1000UL;
constexpr unsigned long LIGHT_SLEEP_DELAY_MS = 30000UL;
constexpr unsigned long TOUCH_WAKE_MS = 30000UL;
constexpr unsigned long SURPRISE_COOLDOWN_MS = 10000UL;
constexpr unsigned long CONTRAST_UPDATE_MS = 100UL;
constexpr unsigned long FRAME_INTERVAL_MS = 80UL;
constexpr uint8_t MAX_CLIMATE_FAILURES = 3;
constexpr int DEFAULT_DARK_ADC = 250;
constexpr int DEFAULT_BRIGHT_ADC = 3500;
constexpr int MIN_CALIBRATION_SPAN = 200;

Adafruit_SSD1306 display(SCREEN_WIDTH, SCREEN_HEIGHT, &Wire, OLED_RESET);
DHT climateSensor(DHT_PIN, DHT_TYPE);
Preferences companionPreferences;

enum HomeMode : uint8_t {
  HOME_COMPANION = 0,
  HOME_USAGE = 1,
  HOME_CLIMATE = 2,
  HOME_AUTO = 3,
  HOME_AMBIENT = 4
};
enum DisplayScreen : uint8_t {
  SCREEN_COMPANION = 0,
  SCREEN_USAGE = 1,
  SCREEN_CLIMATE = 2,
  SCREEN_AMBIENT = 3
};
enum CompanionMood { MOOD_HAPPY, MOOD_NEUTRAL, MOOD_WORRIED, MOOD_SLEEPY };
enum PetReaction { REACTION_NONE, REACTION_HAPPY, REACTION_EXCITED, REACTION_SURPRISED };
enum AmbientLevel { AMBIENT_DARK, AMBIENT_DIM, AMBIENT_NORMAL, AMBIENT_BRIGHT };
enum LightCalibrationStage { CALIBRATION_NONE, CALIBRATION_DARK, CALIBRATION_BRIGHT };

constexpr uint8_t MENU_ITEM_COUNT = 9;
const char *const MENU_ITEMS[MENU_ITEM_COUNT] = {
    "Companion", "Codex Usage", "Room Climate", "Ambient Light", "Auto Rotate",
    "Auto Brightness", "Calibrate Light", "Wi-Fi Pairing", "Back"};

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

HomeMode homeMode = HOME_COMPANION;
DisplayScreen autoScreen = SCREEN_COMPANION;
bool menuActive = false;
uint8_t menuIndex = 0;
unsigned long menuLastInputAt = 0;
unsigned long lastAutoRotateAt = 0;

bool touchWasDown = false;
bool touchIgnored = false;
bool holdHandled = false;
unsigned long touchStartedAt = 0;
unsigned long ignoreTouchUntil = 0;
PetReaction activeReaction = REACTION_NONE;
unsigned long reactionUntil = 0;
unsigned long lastPetAt = 0;
uint8_t petChainCount = 0;

bool haveClimate = false;
float temperatureC = 0.0f;
float humidityPercent = 0.0f;
uint8_t climateFailureCount = 0;
unsigned long lastClimateReadAt = 0;

bool haveLightReading = false;
bool autoBrightnessEnabled = true;
float filteredLightRaw = 0.0f;
int ambientPercent = 50;
int lightDarkAdc = DEFAULT_DARK_ADC;
int lightBrightAdc = DEFAULT_BRIGHT_ADC;
int lightBaselinePercent = 50;
uint8_t currentContrast = 0xCF;
AmbientLevel ambientLevel = AMBIENT_NORMAL;
LightCalibrationStage calibrationStage = CALIBRATION_NONE;
int pendingDarkAdc = DEFAULT_DARK_ADC;
unsigned long lastLightSampleAt = 0;
unsigned long lastLightBaselineAt = 0;
unsigned long lastContrastUpdateAt = 0;
unsigned long darknessStartedAt = 0;
unsigned long touchWakeUntil = 0;
unsigned long surpriseCooldownUntil = 0;

unsigned long lastFrameAt = 0;
unsigned long networkMessageUntil = 0;
String networkLine1;
String networkLine2;
bool networkMessageActive = false;

void drawLimits();
void drawClimate();
void drawAmbientLight();
void renderDisplay();
void triggerSurprisedReaction();

int clampPercent(int value) {
  if (value < 0) return 0;
  if (value > 100) return 100;
  return value;
}

bool isInteger(const String &value) {
  if (value.length() == 0) return false;
  int start = value[0] == '-' ? 1 : 0;
  if (start == 1 && value.length() == 1) return false;
  for (unsigned int i = start; i < value.length(); i++) if (!isDigit(value[i])) return false;
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
  int filledWidth = ((width - 2) * clampPercent(percent)) / 100;
  if (filledWidth > 0) display.fillRect(x + 1, y + 1, filledWidth, height - 2, SSD1306_WHITE);
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

String climateLabel() {
  if (!haveClimate) return "UNAVAILABLE";
  if (temperatureC < 18.0f) return "COOL";
  if (temperatureC > 28.0f) return "WARM";
  if (humidityPercent < 30.0f) return "DRY";
  if (humidityPercent > 70.0f) return "HUMID";
  return "COMFY";
}

const char *ambientLevelLabel() {
  switch (ambientLevel) {
    case AMBIENT_DARK: return "DARK";
    case AMBIENT_DIM: return "DIM";
    case AMBIENT_BRIGHT: return "BRIGHT";
    default: return "NORMAL";
  }
}

int lightPercentFromRaw(float rawValue) {
  long span = static_cast<long>(lightBrightAdc) - lightDarkAdc;
  if (abs(span) < MIN_CALIBRATION_SPAN) return 50;
  long scaled = (static_cast<long>(rawValue) - lightDarkAdc) * 100L / span;
  if (scaled < 0) return 0;
  if (scaled > 100) return 100;
  return static_cast<int>(scaled);
}

void updateAmbientLevel() {
  switch (ambientLevel) {
    case AMBIENT_DARK:
      if (ambientPercent > 15) ambientLevel = AMBIENT_DIM;
      break;
    case AMBIENT_DIM:
      if (ambientPercent < 8) ambientLevel = AMBIENT_DARK;
      else if (ambientPercent > 35) ambientLevel = AMBIENT_NORMAL;
      break;
    case AMBIENT_NORMAL:
      if (ambientPercent < 25) ambientLevel = AMBIENT_DIM;
      else if (ambientPercent > 80) ambientLevel = AMBIENT_BRIGHT;
      break;
    case AMBIENT_BRIGHT:
      if (ambientPercent < 70) ambientLevel = AMBIENT_NORMAL;
      break;
  }
}

bool touchWakeActive() {
  unsigned long now = millis();
  return static_cast<long>(now - touchWakeUntil) < 0;
}

bool ambientSleeping() {
  if (!haveLightReading || ambientLevel != AMBIENT_DARK || darknessStartedAt == 0) return false;
  return !touchWakeActive() && millis() - darknessStartedAt >= LIGHT_SLEEP_DELAY_MS;
}

void applyAutomaticContrast() {
  if (!autoBrightnessEnabled || !displayReady || !displayPowered) return;
  unsigned long now = millis();
  if (now - lastContrastUpdateAt < CONTRAST_UPDATE_MS) return;
  lastContrastUpdateAt = now;

  uint8_t target = static_cast<uint8_t>(map(ambientPercent, 0, 100, 8, 255));
  if (touchWakeActive() && target < 48) target = 48;
  if (currentContrast < target) {
    int next = currentContrast + 6;
    currentContrast = static_cast<uint8_t>(next > target ? target : next);
  } else if (currentContrast > target) {
    int next = currentContrast - 6;
    currentContrast = static_cast<uint8_t>(next < target ? target : next);
  } else return;
  display.ssd1306_command(SSD1306_SETCONTRAST);
  display.ssd1306_command(currentContrast);
}

void updateAmbientLight() {
  unsigned long now = millis();
  if (now - lastLightSampleAt < LIGHT_SAMPLE_MS) return;
  lastLightSampleAt = now;

  int raw = analogRead(LDR_PIN);
  if (!haveLightReading) {
    filteredLightRaw = raw;
    haveLightReading = true;
    ambientPercent = lightPercentFromRaw(filteredLightRaw);
    lightBaselinePercent = ambientPercent;
    lastLightBaselineAt = now;
  } else {
    filteredLightRaw = filteredLightRaw * 0.85f + raw * 0.15f;
    ambientPercent = lightPercentFromRaw(filteredLightRaw);
  }

  updateAmbientLevel();
  if (ambientLevel == AMBIENT_DARK) {
    if (darknessStartedAt == 0) darknessStartedAt = now;
  } else darknessStartedAt = 0;

  if (now - lastLightBaselineAt >= LIGHT_BASELINE_MS) {
    int increase = ambientPercent - lightBaselinePercent;
    if (increase >= 35 && static_cast<long>(now - surpriseCooldownUntil) >= 0 &&
        calibrationStage == CALIBRATION_NONE) {
      triggerSurprisedReaction();
      surpriseCooldownUntil = now + SURPRISE_COOLDOWN_MS;
    }
    lightBaselinePercent = ambientPercent;
    lastLightBaselineAt = now;
  }
  applyAutomaticContrast();
}

CompanionMood currentMood() {
  if (ambientSleeping()) return MOOD_SLEEPY;
  if (!haveClimate) return MOOD_NEUTRAL;
  return climateLabel() == "COMFY" ? MOOD_HAPPY : MOOD_WORRIED;
}

bool shouldBlink() {
  unsigned long phase = millis() % 4800UL;
  return phase >= 4200UL && phase < 4360UL;
}

void drawEye(int x, int y, bool blink, bool worried) {
  if (blink) display.drawLine(x - 7, y, x + 7, y, SSD1306_WHITE);
  else if (worried) {
    display.drawLine(x - 7, y - 3, x + 7, y + 2, SSD1306_WHITE);
    display.fillCircle(x, y + 5, 4, SSD1306_WHITE);
  } else display.fillRoundRect(x - 5, y - 7, 10, 15, 5, SSD1306_WHITE);
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

  if (reaction == REACTION_SURPRISED) {
    display.drawCircle(39, 31, 8, SSD1306_WHITE);
    display.drawCircle(89, 31, 8, SSD1306_WHITE);
    display.fillCircle(39, 31, 3, SSD1306_WHITE);
    display.fillCircle(89, 31, 3, SSD1306_WHITE);
    display.drawCircle(64, 47, 6, SSD1306_WHITE);
    display.setCursor(37, 56);
    display.print("so bright!");
  } else if (reaction == REACTION_EXCITED) {
    drawEye(39, 31, false, false);
    drawEye(89, 31, false, false);
    display.drawLine(52, 43, 58, 51, SSD1306_WHITE);
    display.drawLine(58, 51, 64, 43, SSD1306_WHITE);
    display.drawLine(64, 43, 70, 51, SSD1306_WHITE);
    display.drawLine(70, 51, 76, 43, SSD1306_WHITE);
    display.setCursor(42, 55);
    display.print("so happy!");
  } else if (reaction == REACTION_HAPPY) {
    drawEye(39, 31, false, false);
    drawEye(89, 31, false, false);
    display.drawLine(52, 43, 58, 49, SSD1306_WHITE);
    display.drawLine(58, 49, 70, 49, SSD1306_WHITE);
    display.drawLine(70, 49, 76, 43, SSD1306_WHITE);
    display.setCursor(43, 55);
    display.print("thanks!");
  } else if (mood == MOOD_SLEEPY) {
    display.drawLine(31, 31, 46, 31, SSD1306_WHITE);
    display.drawLine(82, 31, 97, 31, SSD1306_WHITE);
    display.drawLine(56, 47, 72, 47, SSD1306_WHITE);
    display.setCursor(34, 55);
    display.print("sleepy night");
  } else {
    drawEye(39, 31, blink, worried);
    drawEye(89, 31, blink, worried);
    if (mood == MOOD_HAPPY) {
      display.drawLine(52, 43, 58, 49, SSD1306_WHITE);
      display.drawLine(58, 49, 70, 49, SSD1306_WHITE);
      display.drawLine(70, 49, 76, 43, SSD1306_WHITE);
      display.setCursor(34, 55);
      display.print("feeling cozy");
    } else if (mood == MOOD_WORRIED) {
      display.drawLine(52, 50, 64, 43, SSD1306_WHITE);
      display.drawLine(64, 43, 76, 50, SSD1306_WHITE);
      display.setCursor(31, 55);
      display.print("room: ");
      display.print(climateLabel());
    } else {
      display.drawLine(53, 47, 75, 47, SSD1306_WHITE);
      display.setCursor(39, 55);
      display.print("tap to pet");
    }
  }
  display.display();
}

void drawMenu() {
  display.clearDisplay();
  display.setTextColor(SSD1306_WHITE);
  display.setTextSize(1);
  display.setCursor(48, 1);
  display.print("MENU");
  display.drawLine(0, 12, 127, 12, SSD1306_WHITE);
  display.setCursor(8, 24);
  display.print(">");
  display.setCursor(20, 24);
  if (menuIndex == 5) display.print(autoBrightnessEnabled ? "Auto Bright: ON" : "Auto Bright: OFF");
  else display.print(MENU_ITEMS[menuIndex]);
  display.setCursor(50, 39);
  display.print(menuIndex + 1);
  display.print("/");
  display.print(MENU_ITEM_COUNT);
  display.setCursor(2, 54);
  display.print("Tap next Hold select");
  display.display();
}

void drawLightCalibration() {
  display.clearDisplay();
  display.setTextColor(SSD1306_WHITE);
  display.setTextSize(1);
  display.setCursor(20, 1);
  display.print("LIGHT CALIBRATE");
  display.drawLine(0, 12, 127, 12, SSD1306_WHITE);
  display.setCursor(13, 20);
  display.print(calibrationStage == CALIBRATION_DARK ? "Cover the sensor" : "Shine bright light");
  display.setCursor(30, 34);
  display.print("Reading: ");
  display.print(static_cast<int>(filteredLightRaw));
  display.setCursor(12, 48);
  display.print("Hold to save");
  display.setCursor(15, 56);
  display.print("Tap to cancel");
  display.display();
}

DisplayScreen visibleScreen() {
  if (homeMode == HOME_USAGE) return SCREEN_USAGE;
  if (homeMode == HOME_CLIMATE) return SCREEN_CLIMATE;
  if (homeMode == HOME_AMBIENT) return SCREEN_AMBIENT;
  if (homeMode == HOME_AUTO) return autoScreen;
  return SCREEN_COMPANION;
}

void updateAutoRotation() {
  if (homeMode != HOME_AUTO || menuActive || activeReaction != REACTION_NONE) return;
  unsigned long now = millis();
  if (now - lastAutoRotateAt < AUTO_ROTATE_MS) return;
  lastAutoRotateAt = now;
  for (uint8_t offset = 1; offset <= 4; offset++) {
    DisplayScreen candidate = static_cast<DisplayScreen>((static_cast<uint8_t>(autoScreen) + offset) % 4);
    if (candidate == SCREEN_COMPANION || (candidate == SCREEN_USAGE && haveLimits) ||
        (candidate == SCREEN_CLIMATE && haveClimate) ||
        (candidate == SCREEN_AMBIENT && haveLightReading)) {
      autoScreen = candidate;
      break;
    }
  }
}

void renderDisplay() {
  if (!displayReady || !displayPowered) return;
  unsigned long now = millis();
  if (calibrationStage != CALIBRATION_NONE) {
    drawLightCalibration();
    return;
  }
  if (menuActive) {
    drawMenu();
    return;
  }
  if (networkMessageActive) {
    if (now < networkMessageUntil) {
      drawCenteredMessage(networkLine1, networkLine2);
      return;
    }
    networkMessageActive = false;
  }
  if (activeReaction != REACTION_NONE && now < reactionUntil) {
    drawCompanionFace(currentMood(), activeReaction);
    return;
  }
  activeReaction = REACTION_NONE;
  if (visibleScreen() == SCREEN_USAGE) drawLimits();
  else if (visibleScreen() == SCREEN_CLIMATE) drawClimate();
  else if (visibleScreen() == SCREEN_AMBIENT) drawAmbientLight();
  else drawCompanionFace(currentMood());
}

void triggerPetReaction() {
  unsigned long now = millis();
  if (now - lastPetAt <= PET_CHAIN_MS) {
    if (petChainCount < 3) petChainCount++;
  } else petChainCount = 1;
  lastPetAt = now;
  activeReaction = petChainCount >= 2 ? REACTION_EXCITED : REACTION_HAPPY;
  reactionUntil = now + PET_REACTION_MS;
  lastAutoRotateAt = now;
  Serial.println(activeReaction == REACTION_EXCITED ? "Companion excited" : "Companion petted");
}

void triggerSurprisedReaction() {
  if (!displayPowered || menuActive || calibrationStage != CALIBRATION_NONE) return;
  unsigned long now = millis();
  activeReaction = REACTION_SURPRISED;
  reactionUntil = now + PET_REACTION_MS;
  lastAutoRotateAt = now;
  Serial.println("Companion noticed sudden bright light");
}

void saveHomeMode(HomeMode selectedMode) {
  homeMode = selectedMode;
  companionPreferences.putUChar("homeMode", static_cast<uint8_t>(homeMode));
  autoScreen = SCREEN_COMPANION;
  lastAutoRotateAt = millis();
  activeReaction = REACTION_NONE;
}

void openMenu() {
  menuActive = true;
  menuIndex = 0;
  menuLastInputAt = millis();
  activeReaction = REACTION_NONE;
  Serial.println("Display menu opened");
}

void closeMenu() {
  menuActive = false;
  Serial.println("Display menu closed");
}

void setAutoBrightness(bool enabled) {
  autoBrightnessEnabled = enabled;
  companionPreferences.putBool("autoBright", autoBrightnessEnabled);
  if (!autoBrightnessEnabled && displayReady && displayPowered) {
    currentContrast = 0xCF;
    display.ssd1306_command(SSD1306_SETCONTRAST);
    display.ssd1306_command(currentContrast);
  } else applyAutomaticContrast();
}

void startLightCalibration() {
  menuActive = false;
  calibrationStage = CALIBRATION_DARK;
  Serial.println("Light calibration: cover the LDR and hold touch");
}

void saveLightCalibrationStep() {
  int reading = static_cast<int>(filteredLightRaw);
  if (calibrationStage == CALIBRATION_DARK) {
    pendingDarkAdc = reading;
    calibrationStage = CALIBRATION_BRIGHT;
    Serial.println("Light calibration: shine a bright light and hold touch");
    return;
  }

  if (calibrationStage == CALIBRATION_BRIGHT) {
    if (abs(reading - pendingDarkAdc) < MIN_CALIBRATION_SPAN) {
      calibrationStage = CALIBRATION_NONE;
      showNetworkMessage("CALIBRATION FAILED", "Use more light range");
      Serial.println("Light calibration failed: readings are too close");
      return;
    }
    lightDarkAdc = pendingDarkAdc;
    lightBrightAdc = reading;
    companionPreferences.putUShort("lightDark", static_cast<uint16_t>(lightDarkAdc));
    companionPreferences.putUShort("lightBright", static_cast<uint16_t>(lightBrightAdc));
    ambientPercent = lightPercentFromRaw(filteredLightRaw);
    calibrationStage = CALIBRATION_NONE;
    showNetworkMessage("LIGHT CALIBRATED", "Auto brightness ready");
    Serial.println("Light calibration saved");
  }
}

void cancelLightCalibration() {
  calibrationStage = CALIBRATION_NONE;
  showNetworkMessage("CALIBRATION", "Cancelled");
  Serial.println("Light calibration cancelled");
}

void selectMenuItem() {
  menuLastInputAt = millis();
  if (menuIndex <= 2) {
    saveHomeMode(static_cast<HomeMode>(menuIndex));
    closeMenu();
  } else if (menuIndex == 3) {
    saveHomeMode(HOME_AMBIENT);
    closeMenu();
  } else if (menuIndex == 4) {
    saveHomeMode(HOME_AUTO);
    closeMenu();
  } else if (menuIndex == 5) {
    setAutoBrightness(!autoBrightnessEnabled);
    menuLastInputAt = millis();
  } else if (menuIndex == 6) {
    startLightCalibration();
  } else if (menuIndex == 7) {
    closeMenu();
    showQuotaGlowPairingInfo();
  } else closeMenu();
}

void handleShortTap() {
  if (calibrationStage != CALIBRATION_NONE) cancelLightCalibration();
  else if (menuActive) {
    menuIndex = (menuIndex + 1) % MENU_ITEM_COUNT;
    menuLastInputAt = millis();
  } else if (visibleScreen() == SCREEN_COMPANION) triggerPetReaction();
}

void updateTouch() {
  if (!displayPowered) {
    touchWasDown = false;
    return;
  }
  unsigned long now = millis();
  bool down = digitalRead(TOUCH_PIN) == HIGH;
  if (down && !touchWasDown) {
    touchWasDown = true;
    touchStartedAt = now;
    touchWakeUntil = now + TOUCH_WAKE_MS;
    touchIgnored = now < ignoreTouchUntil;
    holdHandled = false;
  }
  if (down && touchWasDown && !touchIgnored && !holdHandled && now - touchStartedAt >= HOLD_MS) {
    holdHandled = true;
    ignoreTouchUntil = now + TOUCH_DEBOUNCE_MS;
    if (calibrationStage != CALIBRATION_NONE) saveLightCalibrationStep();
    else if (menuActive) selectMenuItem();
    else openMenu();
  }
  if (!down && touchWasDown) {
    unsigned long duration = now - touchStartedAt;
    if (!touchIgnored && !holdHandled && duration >= TAP_MIN_MS && duration <= TAP_MAX_MS) {
      handleShortTap();
      ignoreTouchUntil = now + TOUCH_DEBOUNCE_MS;
    }
    touchWasDown = false;
  }
}

void updateClimate() {
  unsigned long now = millis();
  if (now - lastClimateReadAt < CLIMATE_READ_MS) return;
  lastClimateReadAt = now;
  float newHumidity = climateSensor.readHumidity();
  float newTemperature = climateSensor.readTemperature();
  if (isnan(newHumidity) || isnan(newTemperature) || newHumidity < 0.0f ||
      newHumidity > 100.0f || newTemperature < -40.0f || newTemperature > 80.0f) {
    if (climateFailureCount < MAX_CLIMATE_FAILURES) climateFailureCount++;
    if (climateFailureCount >= MAX_CLIMATE_FAILURES) haveClimate = false;
    Serial.println("DHT sensor reading failed");
    return;
  }
  humidityPercent = newHumidity;
  temperatureC = newTemperature;
  climateFailureCount = 0;
  haveClimate = true;
}

void drawClimate() {
  if (!displayReady || !displayPowered) return;
  if (!haveClimate) {
    drawCenteredMessage("SENSOR UNAVAILABLE", "Check DATA GPIO26");
    return;
  }
  display.clearDisplay();
  display.setTextColor(SSD1306_WHITE);
  display.setTextSize(1);
  display.setCursor(28, 0);
  display.print("ROOM CLIMATE");
  display.drawLine(0, 10, 127, 10, SSD1306_WHITE);
  display.setTextSize(2);
  display.setCursor(21, 16);
  display.print(temperatureC, 1);
  display.print(" C");
  display.setTextSize(1);
  display.setCursor(25, 39);
  display.print("Humidity ");
  display.print(humidityPercent, 0);
  display.print("%");
  String label = climateLabel();
  display.setCursor(64 - static_cast<int>(label.length() * 3), 54);
  display.print(label);
  display.display();
}

void drawAmbientLight() {
  if (!displayReady || !displayPowered) return;
  if (!haveLightReading) {
    drawCenteredMessage("LIGHT SENSOR", "Waiting for reading");
    return;
  }

  display.clearDisplay();
  display.setTextColor(SSD1306_WHITE);
  display.setTextSize(1);
  display.setCursor(22, 0);
  display.print("AMBIENT LIGHT");
  display.drawLine(0, 10, 127, 10, SSD1306_WHITE);
  display.setTextSize(2);
  display.setCursor(38, 15);
  display.print(ambientPercent);
  display.print("%");
  display.setTextSize(1);
  int labelLength = strlen(ambientLevelLabel());
  display.setCursor(64 - labelLength * 3, 34);
  display.print(ambientLevelLabel());
  drawProgressBar(8, 44, 112, 7, ambientPercent);
  display.setCursor(35, 55);
  display.print(autoBrightnessEnabled ? "AUTO: ON" : "AUTO: OFF");
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
  if (stale) display.print("DATA STALE");
  else {
    display.print("Reset: ");
    display.print(showSecondaryReset ? secondaryReset : primaryReset);
  }
  display.display();
}

void handleStatus(const String fields[], int count) {
  if (count != 2) return;
  if (fields[1] == "CODEX_ERROR") statusMessage = "CODEX ERROR";
  else if (fields[1] == "NO_LIMIT_DATA") statusMessage = "NO LIMIT DATA";
  else return;
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
    menuActive = false;
    activeReaction = REACTION_NONE;
    display.clearDisplay();
    display.display();
    display.ssd1306_command(SSD1306_DISPLAYOFF);
    displayPowered = false;
    Serial.println("OLED powered off by PC");
  } else if (fields[1] == "ON") {
    display.ssd1306_command(SSD1306_DISPLAYON);
    displayPowered = true;
    ignoreTouchUntil = millis() + TOUCH_DEBOUNCE_MS;
    lastContrastUpdateAt = 0;
    Serial.println("OLED powered on by PC");
    renderDisplay();
  }
}

void handleSerialLine(String line) {
  line.trim();
  if (line.length() == 0) return;
  String fields[8];
  int count = splitFields(line, fields, 8);
  if (fields[0] == "LIMITS") handleLimits(fields, count);
  else if (fields[0] == "STATUS") handleStatus(fields, count);
  else if (fields[0] == "POWER") handlePower(fields, count);
  else Serial.println("Ignored unknown serial message");
}

void handleNetworkLine(String line) {
  handleSerialLine(line);
}

void showNetworkMessage(const String &line1, const String &line2) {
  networkLine1 = line1;
  networkLine2 = line2;
  networkMessageActive = true;
  bool longMessage = line1.startsWith("QuotaGlow-Setup-") || line1.startsWith("Pair:") ||
                     line1 == "ALREADY PAIRED";
  networkMessageUntil = millis() + (longMessage ? NETWORK_LONG_MESSAGE_MS : NETWORK_MESSAGE_MS);
  renderDisplay();
}

bool beginDisplay() {
  const uint8_t addresses[] = {0x3C, 0x3D};
  for (uint8_t address : addresses) {
    Wire.beginTransmission(address);
    if (Wire.endTransmission() == 0 && display.begin(SSD1306_SWITCHCAPVCC, address)) {
      Serial.print("OLED detected at 0x");
      Serial.println(address, HEX);
      return true;
    }
  }
  return false;
}

HomeMode loadHomeMode() {
  if (companionPreferences.isKey("homeMode")) {
    uint8_t storedMode = companionPreferences.getUChar("homeMode", HOME_COMPANION);
    if (storedMode <= HOME_AMBIENT) return static_cast<HomeMode>(storedMode);
  }
  bool oldFaceFirst = companionPreferences.getBool("faceFirst", true);
  HomeMode migratedMode = oldFaceFirst ? HOME_COMPANION : HOME_USAGE;
  companionPreferences.putUChar("homeMode", static_cast<uint8_t>(migratedMode));
  Serial.println("Migrated legacy display preference");
  return migratedMode;
}

void setup() {
  Serial.begin(115200);
  delay(300);
  Serial.println();
  Serial.println("QuotaGlow desk companion starting");
  pinMode(TOUCH_PIN, INPUT);
  pinMode(LDR_PIN, INPUT);
  analogReadResolution(12);
  analogSetPinAttenuation(LDR_PIN, ADC_11db);
  companionPreferences.begin("companion", false);
  homeMode = loadHomeMode();
  autoBrightnessEnabled = companionPreferences.getBool("autoBright", true);
  lightDarkAdc = companionPreferences.getUShort("lightDark", DEFAULT_DARK_ADC);
  lightBrightAdc = companionPreferences.getUShort("lightBright", DEFAULT_BRIGHT_ADC);
  if (abs(lightBrightAdc - lightDarkAdc) < MIN_CALIBRATION_SPAN) {
    lightDarkAdc = DEFAULT_DARK_ADC;
    lightBrightAdc = DEFAULT_BRIGHT_ADC;
  }
  climateSensor.begin();
  lastClimateReadAt = millis();
  Wire.begin(SDA_PIN, SCL_PIN);
  displayReady = beginDisplay();
  if (!displayReady) Serial.println("OLED not found at 0x3C or 0x3D");
  else drawCenteredMessage("QUOTAGLOW", "Starting companion");
  beginQuotaGlowNetwork(handleNetworkLine, showNetworkMessage);
}

void loop() {
  loopQuotaGlowNetwork();
  updateClimate();
  updateAmbientLight();
  updateTouch();
  if (menuActive && millis() - menuLastInputAt >= MENU_TIMEOUT_MS) closeMenu();
  updateAutoRotation();
  while (Serial.available() > 0) {
    char incoming = static_cast<char>(Serial.read());
    if (incoming == '\n') {
      handleSerialLine(serialLine);
      serialLine = "";
    } else if (incoming != '\r') {
      if (serialLine.length() < 160) serialLine += incoming;
      else {
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
