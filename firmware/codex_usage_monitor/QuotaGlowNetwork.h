#pragma once

#include <Arduino.h>

using QuotaGlowMessageHandler = void (*)(String line);
using QuotaGlowDisplayHandler = void (*)(const String &line1, const String &line2);

void beginQuotaGlowNetwork(QuotaGlowMessageHandler messageHandler,
                           QuotaGlowDisplayHandler displayHandler);
void loopQuotaGlowNetwork();
