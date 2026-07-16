# Privacy Policy

Last updated: May 12, 2026

Twistaway helps riders plan motorcycle routes using route preferences, weather, traffic,
saved places, offline access, and optional account features. This policy explains what
data the service collects, how it is protected, and the choices available to users.

This draft is provided for product planning and should be reviewed by counsel before
public launch.

## Information We Collect

We collect information needed to operate the service:

- Account information, such as email address, display name, password credentials, and
  authentication metadata.
- Route planning information, such as start and end points, waypoints, route
  preferences, avoidance settings, motorcycle-specific riding preferences, saved routes,
  trip notes, and home address if provided.
- Location and device information, such as approximate or precise location when
  permission is granted, device type, app version, network status, and offline map/cache
  state.
- Usage and diagnostics information, such as feature usage, error reports, performance
  logs, sync status, and crash diagnostics.
- Weather and traffic request information needed to retrieve forecasts, road conditions,
  route context, and estimated travel conditions.

We do not intentionally collect payment information in the current product requirements.
If paid features are added later, payment details should be handled by a payment
processor and covered in an updated policy.

## Passwords and Security

User passwords are hashed with Argon2id before storage. We do not store plaintext
passwords.

Sensitive route and log data is designed to be encrypted on the client before storage or
sync. Sensitive data may include saved routes, ride logs, home address, and similar
location history. The encryption design uses an application secret together with the
user's password-derived material so that protected data is not stored in plaintext in
SQLite or remote sync storage.

Because password-derived encryption depends on the user's password, a password reset may
make some encrypted local or synced data unrecoverable unless the product provides a
separate recovery mechanism. Users should understand that strong privacy protections can
limit account recovery options.

## SQLite, Local Storage, and Offline Use

Twistaway uses SQLite and local device storage to support offline mobile use. Depending
on user settings and device permissions, the app may store:

- Offline route plans, cached map or navigation data, and route preferences.
- Weather, traffic, and routing responses needed for recently viewed or saved trips.
- Encrypted ride logs, saved routes, and home address.
- Sync metadata used to reconcile local and remote changes.

Users are responsible for protecting their device with an operating system passcode,
biometric unlock, disk encryption, and current security updates.

## How We Use Information

We use information to:

- Create and manage accounts.
- Plan, save, sync, and display motorcycle routes.
- Apply riding preferences, such as road type preferences, avoidance rules, scenic or
  twisty-road options, fuel and stop planning, and offline availability.
- Provide weather, traffic, routing, and safety-relevant route context.
- Improve reliability, diagnose crashes, detect abuse, and secure the service.
- Communicate service updates, security notices, and account-related messages.

We do not sell personal information. If analytics are used, they should be configured to
minimize collection of precise location, route history, and other sensitive riding data.

## Third-Party Services

Twistaway may integrate with routing, weather, traffic, navigation, and music services,
including Waze-related navigation handoff, wzsabre routing data or tooling, weather
providers, and Spotify. When the app requests information from these services, the
request may include route coordinates, approximate location, destination, timing, device
or app metadata, Spotify playback state, and other information needed to return useful
results.

Third-party services process data under their own terms and privacy policies. Twistaway
should avoid sending user account identifiers to third-party providers unless required,
and should prefer short-lived request data over persistent identifiers.

## Sharing and Disclosure

We may disclose information:

- To service providers that host, operate, secure, or support the product.
- To comply with law, legal process, or enforceable government requests.
- To protect users, the public, Twistaway, or others from security threats, fraud, or
  harm.
- In connection with a merger, acquisition, financing, or sale of assets, subject to
  appropriate protections.
- With user direction or consent, such as opening a route in another navigation app.

## Retention

We retain account data while the account is active or as needed to provide the service.
Local offline data remains on the user's device until deleted by the user, removed by
app settings, or cleared during uninstall depending on platform behavior.

Encrypted routes, logs, and home address data should be deleted when the user deletes
the corresponding item or closes the account, subject to backups, legal retention, abuse
prevention, and technical limits.

## User Choices

Users may be able to:

- Update account details.
- Delete saved routes, logs, home address, and cached offline data.
- Disable precise location permissions through operating system settings.
- Change route preferences and weather or traffic options.
- Request account deletion.

Some features may not work without location access, route coordinates, weather requests,
traffic data, or local offline storage.

## Children's Privacy

Twistaway is not intended for children under 13. We do not knowingly collect personal
information from children under 13.

## Changes

We may update this policy as the product changes. Material changes should be
communicated through the app, website, or account email when appropriate.

## Contact

Privacy questions and deletion requests should be sent to the contact address designated
by the Twistaway project before launch.
