#include "QuotaGlowNetwork.h"

#include <DNSServer.h>
#include <ESPmDNS.h>
#include <Preferences.h>
#include <WebServer.h>
#include <WiFi.h>
#include <WiFiUdp.h>

namespace {
constexpr uint16_t HTTP_PORT = 80;
constexpr uint16_t DISCOVERY_PORT = 4210;
constexpr int BOOT_BUTTON_PIN = 0;
constexpr unsigned long WIFI_CONNECT_TIMEOUT_MS = 30000UL;
constexpr unsigned long WIFI_RETRY_MS = 10000UL;
constexpr unsigned long PAIR_CODE_LIFETIME_MS = 600000UL;
constexpr unsigned long PAIR_ATTEMPT_WINDOW_MS = 60000UL;
constexpr int MAX_PAIR_ATTEMPTS_PER_WINDOW = 5;
constexpr char DISCOVERY_REQUEST[] = "QUOTAGLOW_DISCOVER_V1";
constexpr char FIRMWARE_VERSION[] = "1.3.0";

Preferences preferences;
WebServer webServer(HTTP_PORT);
DNSServer dnsServer;
WiFiUDP discoveryUdp;
QuotaGlowMessageHandler onMessage = nullptr;
QuotaGlowDisplayHandler onDisplay = nullptr;

String deviceId;
String deviceName;
String pairingCode;
String deviceToken;
String savedSsid;
String savedPassword;
bool setupMode = false;
bool webServerStarted = false;
bool discoveryStarted = false;
unsigned long pairingCodeExpiresAt = 0;
unsigned long lastWifiAttemptAt = 0;
unsigned long disconnectedSince = 0;
unsigned long pairAttemptWindowStartedAt = 0;
int pairAttemptsInWindow = 0;
unsigned long bootPressedAt = 0;

String jsonEscape(const String &value) {
  String escaped;
  escaped.reserve(value.length() + 8);
  for (unsigned int i = 0; i < value.length(); i++) {
    char c = value[i];
    if (c == '\\' || c == '"') escaped += '\\';
    if (c == '\n') escaped += "\\n";
    else if (c != '\r') escaped += c;
  }
  return escaped;
}

String randomHexToken() {
  String token;
  token.reserve(64);
  char part[9];
  for (int i = 0; i < 8; i++) {
    snprintf(part, sizeof(part), "%08lx", static_cast<unsigned long>(esp_random()));
    token += part;
  }
  return token;
}

void createPairingCode() {
  pairingCode = String(100000 + (esp_random() % 900000));
  pairingCodeExpiresAt = millis() + PAIR_CODE_LIFETIME_MS;
  pairAttemptWindowStartedAt = millis();
  pairAttemptsInWindow = 0;
  if (onDisplay != nullptr && WiFi.status() == WL_CONNECTED) {
    onDisplay("Pair: " + pairingCode, WiFi.localIP().toString());
  }
  Serial.print("Wi-Fi pairing code: ");
  Serial.println(pairingCode);
}

bool pairingCodeExpired() {
  return static_cast<long>(millis() - pairingCodeExpiresAt) >= 0;
}

bool pairingRateLimited() {
  if (millis() - pairAttemptWindowStartedAt >= PAIR_ATTEMPT_WINDOW_MS) {
    pairAttemptWindowStartedAt = millis();
    pairAttemptsInWindow = 0;
  }
  pairAttemptsInWindow++;
  return pairAttemptsInWindow > MAX_PAIR_ATTEMPTS_PER_WINDOW;
}

bool isAuthorized() {
  if (deviceToken.length() != 64) return false;
  String authorization = webServer.header("Authorization");
  return authorization == "Bearer " + deviceToken;
}

void sendJson(int status, const String &json) {
  webServer.send(status, "application/json", json);
}

String infoJson() {
  String ip = setupMode ? WiFi.softAPIP().toString() : WiFi.localIP().toString();
  return "{\"deviceId\":\"" + jsonEscape(deviceId) +
         "\",\"name\":\"" + jsonEscape(deviceName) +
         "\",\"ip\":\"" + ip +
         "\",\"port\":" + String(HTTP_PORT) +
         ",\"firmwareVersion\":\"" + FIRMWARE_VERSION +
         "\",\"paired\":" + (deviceToken.length() == 64 ? "true" : "false") + "}";
}

void handleInfo() {
  sendJson(200, infoJson());
}

void handlePair() {
  if (deviceToken.length() == 64) {
    sendJson(409, "{\"error\":\"already_paired\"}");
    return;
  }
  if (pairingRateLimited()) {
    sendJson(429, "{\"error\":\"too_many_attempts\"}");
    return;
  }
  if (pairingCodeExpired()) createPairingCode();
  String submittedCode = webServer.arg("plain");
  submittedCode.trim();
  if (submittedCode != pairingCode) {
    sendJson(403, "{\"error\":\"invalid_code\"}");
    return;
  }

  deviceToken = randomHexToken();
  preferences.putString("token", deviceToken);
  pairingCode = "";
  sendJson(200, "{\"deviceId\":\"" + jsonEscape(deviceId) +
                    "\",\"token\":\"" + deviceToken + "\"}");
  if (onDisplay != nullptr) onDisplay("Wi-Fi paired", WiFi.localIP().toString());
  Serial.println("Wi-Fi module paired");
}

void handleMessage() {
  if (!isAuthorized()) {
    sendJson(401, "{\"error\":\"unauthorized\"}");
    return;
  }
  String line = webServer.arg("plain");
  line.trim();
  if (line.length() == 0 || line.length() > 160 || line.indexOf('\n') >= 0 || line.indexOf('\r') >= 0) {
    sendJson(400, "{\"error\":\"invalid_message\"}");
    return;
  }
  if (onMessage != nullptr) onMessage(line);
  sendJson(200, "{\"ok\":true}");
}

void handleUnpair() {
  if (!isAuthorized()) {
    sendJson(401, "{\"error\":\"unauthorized\"}");
    return;
  }
  deviceToken = "";
  preferences.remove("token");
  sendJson(200, "{\"ok\":true}");
  createPairingCode();
}

void clearNetworkSettings() {
  preferences.clear();
  savedSsid = "";
  savedPassword = "";
  deviceToken = "";
}

void handleWifiReset() {
  if (!isAuthorized()) {
    sendJson(401, "{\"error\":\"unauthorized\"}");
    return;
  }
  sendJson(200, "{\"ok\":true,\"restarting\":true}");
  delay(250);
  clearNetworkSettings();
  ESP.restart();
}

String setupPage() {
  return F("<!doctype html><html><head><meta name='viewport' content='width=device-width,initial-scale=1'>"
           "<title>QuotaGlow Setup</title><style>body{font-family:Arial;background:#12151e;color:#fff;"
           "max-width:420px;margin:40px auto;padding:24px}input,button{width:100%;box-sizing:border-box;"
           "padding:12px;margin:8px 0;border-radius:8px;border:1px solid #3b4150}button{background:#625bff;"
           "color:#fff;font-weight:bold}</style></head><body><h1>QuotaGlow Wi-Fi Setup</h1>"
           "<p>Enter a trusted 2.4 GHz Wi-Fi network. Credentials stay on this ESP32.</p>"
           "<form method='post' action='/save'><label>Wi-Fi name</label><input name='ssid' maxlength='32' required>"
           "<label>Password</label><input name='password' type='password' maxlength='64'>"
           "<button type='submit'>Save and connect</button></form></body></html>");
}

void handleSetupRoot() {
  if (!setupMode) {
    webServer.send(404, "text/plain", "Setup mode is not active.");
    return;
  }
  webServer.send(200, "text/html", setupPage());
}

void handleSetupSave() {
  if (!setupMode) {
    webServer.send(403, "text/plain", "Setup mode is not active.");
    return;
  }
  String ssid = webServer.arg("ssid");
  String password = webServer.arg("password");
  ssid.trim();
  if (ssid.length() == 0 || ssid.length() > 32 || password.length() > 64) {
    webServer.send(400, "text/plain", "Invalid Wi-Fi settings.");
    return;
  }
  preferences.putString("ssid", ssid);
  preferences.putString("password", password);
  webServer.send(200, "text/html", "<h2>Saved. QuotaGlow is restarting...</h2>");
  delay(500);
  ESP.restart();
}

void configureWebRoutes() {
  const char *headers[] = {"Authorization"};
  webServer.collectHeaders(headers, 1);
  webServer.on("/api/v1/info", HTTP_GET, handleInfo);
  webServer.on("/api/v1/pair", HTTP_POST, handlePair);
  webServer.on("/api/v1/message", HTTP_POST, handleMessage);
  webServer.on("/api/v1/unpair", HTTP_POST, handleUnpair);
  webServer.on("/api/v1/wifi/reset", HTTP_POST, handleWifiReset);
  webServer.on("/", HTTP_GET, handleSetupRoot);
  webServer.on("/save", HTTP_POST, handleSetupSave);
  webServer.onNotFound([]() {
    if (setupMode) webServer.sendHeader("Location", "http://192.168.4.1/", true);
    webServer.send(setupMode ? 302 : 404, "text/plain", setupMode ? "" : "Not found");
  });
}

void startWebServer() {
  if (webServerStarted) return;
  configureWebRoutes();
  webServer.begin();
  webServerStarted = true;
}

void startSetupMode() {
  setupMode = true;
  discoveryStarted = false;
  WiFi.disconnect(true);
  delay(100);
  WiFi.mode(WIFI_AP);
  String setupName = "QuotaGlow-Setup-" + deviceId.substring(deviceId.length() - 4);
  WiFi.softAP(setupName.c_str());
  dnsServer.start(53, "*", WiFi.softAPIP());
  startWebServer();
  if (onDisplay != nullptr) onDisplay(setupName, "Open 192.168.4.1");
  Serial.print("Setup network: ");
  Serial.println(setupName);
}

void startDiscovery() {
  if (!discoveryStarted) {
    discoveryUdp.begin(DISCOVERY_PORT);
    discoveryStarted = true;
  }
}

void onWifiConnected() {
  setupMode = false;
  disconnectedSince = 0;
  startWebServer();
  startDiscovery();
  String hostName = "quotaglow-" + deviceId.substring(deviceId.length() - 6);
  MDNS.begin(hostName.c_str());
  MDNS.addService("http", "tcp", HTTP_PORT);
  if (deviceToken.length() != 64) createPairingCode();
  else if (onDisplay != nullptr) onDisplay("Wi-Fi ready", WiFi.localIP().toString());
  Serial.print("Wi-Fi connected: ");
  Serial.println(WiFi.localIP());
}

bool connectSavedWifi() {
  if (savedSsid.length() == 0) return false;
  WiFi.mode(WIFI_STA);
  WiFi.begin(savedSsid.c_str(), savedPassword.c_str());
  unsigned long startedAt = millis();
  if (onDisplay != nullptr) onDisplay("Connecting Wi-Fi", savedSsid);
  while (WiFi.status() != WL_CONNECTED && millis() - startedAt < WIFI_CONNECT_TIMEOUT_MS) {
    delay(100);
  }
  if (WiFi.status() == WL_CONNECTED) {
    onWifiConnected();
    return true;
  }
  return false;
}

void handleDiscovery() {
  if (!discoveryStarted || WiFi.status() != WL_CONNECTED) return;
  int packetSize = discoveryUdp.parsePacket();
  if (packetSize <= 0 || packetSize > 64) return;
  char buffer[65];
  int length = discoveryUdp.read(buffer, sizeof(buffer) - 1);
  if (length <= 0) return;
  buffer[length] = '\0';
  String request(buffer);
  request.trim();
  if (request != DISCOVERY_REQUEST) return;
  String response = infoJson();
  discoveryUdp.beginPacket(discoveryUdp.remoteIP(), discoveryUdp.remotePort());
  discoveryUdp.print(response);
  discoveryUdp.endPacket();
}

void handleBootReset() {
  bool pressed = digitalRead(BOOT_BUTTON_PIN) == LOW;
  if (pressed && bootPressedAt == 0) bootPressedAt = millis();
  if (!pressed) bootPressedAt = 0;
  if (pressed && bootPressedAt != 0 && millis() - bootPressedAt >= 5000UL) {
    if (onDisplay != nullptr) onDisplay("Resetting Wi-Fi", "Please wait");
    clearNetworkSettings();
    delay(300);
    ESP.restart();
  }
}
}  // namespace

void beginQuotaGlowNetwork(QuotaGlowMessageHandler messageHandler,
                           QuotaGlowDisplayHandler displayHandler) {
  onMessage = messageHandler;
  onDisplay = displayHandler;
  pinMode(BOOT_BUTTON_PIN, INPUT_PULLUP);
  preferences.begin("quotaglow", false);

  uint64_t chipId = ESP.getEfuseMac();
  char idBuffer[13];
  snprintf(idBuffer, sizeof(idBuffer), "%012llx", static_cast<unsigned long long>(chipId));
  deviceId = String(idBuffer);
  deviceName = "QuotaGlow-" + deviceId.substring(deviceId.length() - 4);
  savedSsid = preferences.getString("ssid", "");
  savedPassword = preferences.getString("password", "");
  deviceToken = preferences.getString("token", "");

  if (!connectSavedWifi()) startSetupMode();
}

void loopQuotaGlowNetwork() {
  handleBootReset();
  if (setupMode) {
    dnsServer.processNextRequest();
    webServer.handleClient();
    return;
  }

  if (WiFi.status() == WL_CONNECTED) {
    if (disconnectedSince != 0) onWifiConnected();
    webServer.handleClient();
    handleDiscovery();
    if (deviceToken.length() != 64 && pairingCodeExpired()) createPairingCode();
    return;
  }

  if (disconnectedSince == 0) disconnectedSince = millis();
  if (millis() - lastWifiAttemptAt >= WIFI_RETRY_MS) {
    lastWifiAttemptAt = millis();
    WiFi.disconnect();
    WiFi.begin(savedSsid.c_str(), savedPassword.c_str());
  }
  if (millis() - disconnectedSince >= WIFI_CONNECT_TIMEOUT_MS) startSetupMode();
}
