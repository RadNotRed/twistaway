# 🧱 Architecture overview

Twistaway is a monorepo with a Flutter client, an optional Express API, a Vite website,
and shared TypeScript contracts.

```text
Flutter app
├── map tiles ───────────────► tile provider
├── route/search fallback ───► supported public providers
├── production proxy ────────► Twistaway API
└── Spotify PKCE ────────────► Spotify

Twistaway API
├── provider request cache
├── routing/search proxy
├── encrypted user payloads
└── SQLite persistence
```

## Mobile-first behavior

The Flutter app owns navigation state, map presentation, rider heading, settings, local
caching, and graceful fallbacks. The API should improve reliability, privacy controls,
and provider flexibility without making the map unusable when the server is unavailable.

## API boundaries

The API serves small JSON requests and encrypted account data. Map tiles remain direct
between the client and tile provider to avoid unnecessary latency, bandwidth cost, and
licensing complexity.

## Persistence

SQLite is appropriate for a single early deployment. Before horizontally scaling the
API, move shared account/session state to a database designed for multiple writers and
move provider caching to a shared cache.
