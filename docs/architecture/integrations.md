# Integrations

Last updated: May 12, 2026

Twistaway depends on external data for navigation handoff, routing context, traffic, and
weather. Integrations should minimize sensitive location sharing, protect API
credentials, and degrade cleanly for offline mobile use.

## Integration Principles

- Send the minimum route, location, and account data needed for each request.
- Do not send passwords, password hashes, encryption keys, app secrets, or plaintext
  sensitive logs to third-party providers.
- Avoid persistent third-party identifiers unless required by the provider contract.
- Cache only what provider terms allow, and attach expiration metadata to cached
  weather, traffic, and routing responses.
- Treat third-party data as advisory. Weather, traffic, closures, and suggested routes
  may be stale or wrong.
- Make offline behavior explicit: cached data should show its age and should not pretend
  to be live.

## Waze Integration

Waze should be treated primarily as a navigation handoff and traffic-context
integration.

Expected uses:

- Open a selected destination or route segment in Waze when the user chooses external
  navigation.
- Use traffic context only when provider terms and available APIs allow it.
- Preserve Twistaway route preferences locally even when Waze recalculates navigation
  externally.

Data handling:

- Handoff may expose destination coordinates, current location, and route context to
  Waze.
- Avoid sending Twistaway account identifiers.
- Do not include encrypted ride logs, home address labels, private notes, or motorcycle
  preference profiles in handoff URLs.

Failure and fallback:

- If Waze is unavailable, show a clear fallback to in-app route preview or another
  supported navigation target.
- If Waze recalculates the route, treat the Waze route as external guidance rather than
  a synchronized Twistaway route.

## wzsabre Integration

wzsabre is expected to support routing-related functionality or route data processing.
Because the exact deployment model may vary, keep the integration behind an internal
adapter boundary.

Adapter responsibilities:

- Convert Twistaway route preferences into provider-specific request parameters.
- Normalize returned route geometry, metadata, warnings, and errors.
- Preserve enough detail to explain why a route was selected without storing unnecessary
  provider payloads.
- Separate provider errors from application validation errors.

Motorcycle-specific inputs may include:

- Avoid highways, tolls, ferries, unpaved roads, or seasonal roads.
- Prefer scenic, twisty, lower-traffic, or fuel-aware routing where supported.
- Respect maximum daily distance, stop cadence, and offline map availability where
  supported by product logic.

Data handling:

- Send only route coordinates, constraints, and preferences needed for route generation.
- Do not send user password material, encryption keys, home address labels, private
  notes, or account email.
- Store sensitive returned route details encrypted when they become saved routes or ride
  logs.

Failure and fallback:

- If wzsabre is unavailable, retain draft route inputs locally and allow retry.
- If route generation partially succeeds, preserve warnings and degraded assumptions.
- If offline, use cached route plans and clearly mark weather and traffic as stale or
  unavailable.

## Weather Integration

Weather data should help riders assess risk along a route and at planned stops. It
should not be presented as a guarantee of safe riding conditions.

Expected uses:

- Forecasts for origin, destination, waypoints, and route corridor.
- Time-aware conditions for planned departure, arrival, and stop windows.
- Alerts or risk flags for rain, snow, ice, wind, lightning, low visibility, extreme
  heat, and extreme cold.

Data handling:

- Weather requests may include coordinates and planned travel times.
- Cache responses with provider-compliant expiration.
- Avoid attaching account identifiers to weather requests.
- Do not store precise route-weather histories in plaintext if they reveal sensitive
  travel patterns.

Failure and fallback:

- If live weather is unavailable, show cached forecast age or "weather unavailable."
- If offline, use only cached weather and make staleness visible.
- If provider data conflicts, prefer transparent uncertainty over overconfident
  recommendations.

## Traffic Integration

Traffic data may come from Waze-related flows, routing providers, or another traffic
data source.

Expected uses:

- Estimate delay and congestion along planned routes.
- Warn about closures or severe slowdowns when supported.
- Inform route comparison without overriding explicit motorcycle preferences unless the
  user chooses a faster route.

Data handling:

- Traffic requests may include route geometry, origin, destination, departure time, and
  current location.
- Cache traffic briefly because traffic data becomes stale quickly.
- Do not store provider traffic traces as long-term ride history unless encrypted and
  user-visible.

## Offline Mobile Behavior

Offline support should be designed as a first-class mode, not only an error state.

When offline, the app should:

- Continue showing saved routes, encrypted logs after unlock, and cached map or route
  data.
- Allow edits to route drafts and preferences in local SQLite.
- Queue syncable changes with conflict metadata.
- Clearly label weather, traffic, and provider route data as cached or unavailable.
- Avoid silently dropping user edits when reconnecting.

## Server and Client Boundary

Use server-side proxying when integration credentials must be protected, provider terms
require server mediation, or response normalization benefits all clients.

Use direct client handoff when the user intentionally opens another app, such as Waze
navigation. Direct handoff should be explicit because it may disclose coordinates to the
receiving app.

Sensitive saved routes, logs, and home address fields should remain encrypted before
leaving the client when the feature promises client-side encryption. The server may
store encrypted blobs, sync metadata, account data, and provider cache entries, but it
should not need plaintext sensitive ride history for normal operation.

## Open Decisions

- Confirm the exact Waze integration surface: deep link only, traffic data, or both.
- Confirm wzsabre hosting model, API contract, rate limits, and licensing.
- Choose weather provider and document permitted caching duration.
- Define whether weather and traffic cache entries are per-user encrypted, shared server
  cache, or both.
- Define recovery behavior for password-derived encrypted data.
