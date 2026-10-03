# Wi-Fi discovery and local API

The v1 local interface uses HTTP port 80 and UDP discovery port 4210.

## Discovery

Broadcast `QUOTAGLOW_DISCOVER_V1` to UDP port 4210. Replies are JSON containing only `deviceId`, `name`, `ip`, `port`, `firmwareVersion`, and `paired`.

## Endpoints

| Method | Path | Authentication | Body |
|---|---|---|---|
| GET | `/api/v1/info` | None | None |
| POST | `/api/v1/pair` | Pairing code | Six ASCII digits as `text/plain` |
| POST | `/api/v1/message` | Bearer token | One protocol line as `text/plain` |
| POST | `/api/v1/unpair` | Bearer token | Empty |
| POST | `/api/v1/wifi/reset` | Bearer token | Empty |

Protected requests use `Authorization: Bearer <device-token>`. Pairing returns a random 256-bit token once. Windows encrypts it with current-user DPAPI before saving it under `%LOCALAPPDATA%\QuotaGlow`.

`/api/v1/message` accepts `LIMITS`, `STATUS`, `POWER|ON`, and `POWER|OFF`. Newlines, messages over 160 characters, malformed requests, and invalid authorization are rejected.

This interface is local-LAN only. It has no cloud relay, HTTPS, OTA update, or remote-internet support.
