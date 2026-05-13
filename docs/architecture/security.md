# Security Architecture

MotoPlanner separates authentication from private data encryption.

## Passwords

- Store account passwords with Argon2id only.
- Use per-password salts encoded in the Argon2 PHC string.
- Do not reuse the password hash as an encryption key.
- Tune Argon2id memory and time cost during deployment benchmarking.

## Private Data

Routes, home address, ride logs, and account-associated network logs are treated as sensitive.

The app derives a local vault key:

1. Argon2id over the user's password and per-user KDF salt.
2. HKDF-SHA256 over the Argon2 output, app/install secret, and a purpose string.
3. AES-256-GCM for each payload with a unique nonce and authenticated metadata.

The backend stores encrypted payload envelopes and operational metadata required to serve the account. Plain usernames and emails are allowed by the product requirements.

## Backend Logs

Anonymous operational logs should be minimized and rotated. Authenticated user audit logs should be encrypted before storage. If the server must generate a user-associated log value such as an observed IP address, the client should establish a short-lived audit encryption session after login so the server can encrypt that event without storing the user's raw password.

## Offline Mode

The mobile app should use SQLCipher-backed SQLite locally. The local database password should be derived from the vault key and protected by the OS secure storage where possible. Offline route packs should be encrypted with the same vault hierarchy.
