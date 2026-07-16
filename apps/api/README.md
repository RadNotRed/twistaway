# Twistaway API

The API is an optional account store and routing/geocoding proxy. The mobile app must
continue to use supported on-device or provider behavior when this service is down.

## Production security

Production startup fails unless `APP_ENCRYPTION_SECRET` is at least 32 bytes and
`CORS_ORIGINS` contains explicit browser origins. Native app requests do not send an
`Origin` header and remain supported. A distributed mobile binary cannot safely keep a
shared secret, so a static "app-only" API key is intentionally not used: it can be
extracted and would provide false assurance. If stronger client verification becomes
necessary, add platform attestation (Apple App Attest and Google Play Integrity) at the
edge without replacing normal account authentication or rate limits.

Run the service behind HTTPS and set `TRUST_PROXY=true` only when the immediate reverse
proxy is trusted and overwrites forwarded headers. The process applies security headers,
strict JSON limits, request IDs, short server timeouts, generic authentication failures,
encrypted audit payloads, and hashed bearer tokens.

## Performance and protection controls

The defaults are suitable for one small API instance:

| Variable                      | Default  | Purpose                                   |
| ----------------------------- | -------- | ----------------------------------------- |
| `API_BODY_LIMIT_BYTES`        | 524288   | Maximum JSON request body                 |
| `RATE_LIMIT_GLOBAL_MAX`       | 300/min  | Per-IP process-wide token bucket          |
| `RATE_LIMIT_AUTH_MAX`         | 10/15m   | Per-IP and per-identifier auth protection |
| `RATE_LIMIT_INTEGRATIONS_MAX` | 90/min   | Per-IP provider proxy protection          |
| `SESSION_CACHE_TTL_MS`        | 30000    | Short-lived authenticated-session cache   |
| `SEARCH_CACHE_ENTRIES`        | 512      | In-memory geocoder LRU capacity           |
| `SEARCH_CACHE_TTL_MS`         | 300000   | Geocoder cache lifetime                   |
| `SEARCH_CACHE_MAX_BYTES`      | 16777216 | Geocoder cache memory budget              |
| `ROUTE_CACHE_ENTRIES`         | 256      | In-memory route LRU capacity              |
| `ROUTE_CACHE_TTL_MS`          | 600000   | Route cache lifetime                      |
| `ROUTE_CACHE_MAX_BYTES`       | 67108864 | Route cache memory budget                 |
| `UPSTREAM_TIMEOUT_MS`         | 8000     | Maximum provider request time             |
| `UPSTREAM_CONCURRENCY`        | 32       | Maximum active provider operations        |
| `UPSTREAM_QUEUE_SIZE`         | 64       | Maximum queued provider operations        |
| `AUDIT_RETENTION_DAYS`        | 90       | Encrypted audit-log retention period      |

Identical in-flight provider requests are coalesced. Search and route responses use
private browser caching, ETags, and Brotli or gzip for payloads over 1 KiB. Provider
responses are size-bounded, SQLite uses WAL and supporting indexes, and expired sessions
and old encrypted audit logs are removed periodically.

`GET /routes` returns at most 100 routes by default. Use `limit` (1-200) and `offset` to
page through larger collections; the response includes `pagination.hasMore`.

These rate limits and caches are deliberately in-process. Before running more than one
API replica, move them to a shared service such as Redis and move account data off the
single SQLite writer. Keep a reverse-proxy or Cloudflare limit in front as the first
layer against volumetric abuse.

## Validation

From the repository root:

```bash
bun run build:shared
bun run build:api
bun run test:api
bun run check
```
