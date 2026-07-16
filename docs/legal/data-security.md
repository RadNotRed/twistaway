# Data Security Notes

Last updated: May 12, 2026

These notes summarize the intended security posture for Twistaway. They are not a
substitute for a threat model, penetration test, or legal review.

## Security Goals

Twistaway should protect sensitive rider data while preserving useful route planning,
weather, traffic, sync, and offline mobile behavior.

High-sensitivity data includes:

- Home address.
- Saved routes and ride logs.
- Precise location history.
- Private notes attached to routes.
- Authentication credentials and password-derived encryption material.

Moderate-sensitivity data includes:

- Motorcycle routing preferences.
- Saved places that are not home address.
- Offline cache metadata.
- Weather and traffic queries tied to routes.

## Accounts and Passwords

Passwords must never be stored in plaintext. Password storage should use Argon2id with
parameters reviewed for the deployment environment and revisited as hardware changes.

Recommended implementation expectations:

- Unique salt per password.
- Server-side rate limiting for authentication attempts.
- Secure session cookies or tokens with expiration and revocation.
- Reauthentication for sensitive actions, such as account deletion or encryption
  recovery changes.
- No password logging in application, analytics, crash reports, or request traces.

## Client-Side Encryption

Sensitive route and log data should be encrypted on the client before being written to
SQLite or uploaded during sync. The product requirement calls for encryption based on an
application secret plus the user's password.

Recommended constraints:

- Derive encryption keys with a memory-hard password-based key derivation function,
  separate from the password hash used for authentication.
- Use authenticated encryption, such as XChaCha20-Poly1305 or AES-256-GCM.
- Use unique nonces for each encrypted record.
- Keep encryption domains separate for home address, route logs, saved routes, and
  diagnostic payloads.
- Never send plaintext sensitive route data to the server when encrypted sync is
  expected.
- Treat password reset as a potential data loss event unless a reviewed recovery-key
  design exists.

The application secret should not be treated as the sole protection for user data. If it
ships with a client app, assume it can eventually be extracted and design the
password-derived component accordingly.

## SQLite and Local Device Storage

SQLite should store sensitive fields encrypted at the application layer. Full-database
encryption may be added, but it should not replace field or record encryption for
syncable sensitive data.

Local storage expectations:

- Store tokens in platform secure storage where available.
- Avoid writing plaintext sensitive data to temporary files, logs, crash dumps, or
  search indexes.
- Expire or allow deletion of weather, traffic, and routing caches.
- Mark sensitive local files for exclusion from cloud backup where appropriate and
  legally permissible.
- Support explicit deletion of offline routes, logs, home address, and caches.

## Logs and Diagnostics

Diagnostics are useful, but route data can reveal habits, home, work, and travel
patterns. Logging should default to data minimization.

Logs should avoid:

- Full coordinates unless required and explicitly protected.
- Home address and saved place labels.
- Passwords, tokens, password hashes, salts, encryption keys, or key derivation inputs.
- Full third-party request URLs if they include route coordinates or API keys.

When sensitive diagnostic payloads are necessary, encrypt them before persistence or
transmission.

## Third-Party Requests

Weather, traffic, routing, Waze handoff, and wzsabre-related integrations should receive
only the data required for the requested feature.

Recommended practices:

- Strip account identifiers from provider requests unless strictly required.
- Use backend proxying when API keys or provider terms require server-side protection.
- Use client-side handoff only when the destination app or provider requires direct
  interaction.
- Cache provider responses only within provider terms and with clear expiration.
- Document which providers receive precise coordinates.

## Operational Checklist

Before launch:

- Complete a threat model for account compromise, stolen device, malicious server
  operator, leaked app secret, and third-party provider exposure.
- Review Argon2id parameters on target server hardware.
- Review encryption key derivation, nonce generation, and recovery behavior.
- Add automated tests for encryption round trip, wrong-password failure, and migration
  behavior.
- Add redaction tests for logs and crash reports.
- Define data deletion behavior for local, synced, cached, and backup data.
