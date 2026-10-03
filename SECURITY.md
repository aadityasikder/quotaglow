# Security Policy

## Supported versions

Security fixes are applied to the latest released version of QuotaGlow.

## Reporting a vulnerability

Please do not publish credentials, tokens, account identifiers, or an exploitable vulnerability in a public issue. Contact the repository owner privately through their GitHub profile and include only the minimum information needed to reproduce the problem.

## Security model

QuotaGlow relies on the user's existing local Codex installation and sign-in. The project is designed so that:

- Credentials remain inside Codex.
- The settings file stores only UI and COM-port preferences.
- USB messages contain display-ready usage values, not authentication data.
- The ESP32 never authenticates directly with OpenAI.
- The usage operation is read-only.

Do not modify QuotaGlow to copy Codex credential files into the repository, settings folder, firmware, or serial messages.
