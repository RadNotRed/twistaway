# Twistaway agent guide

This file is the operating contract for AI coding agents working in this repository.
Read it before changing code, documentation, workflows, or build configuration.

## Mission

Twistaway is a privacy-first motorcycle route planner and navigation app. The primary
product is the Flutter application in `apps/mobile`. The Express API is an optional
production proxy and encrypted account store; navigation must keep working gracefully
when it or a third-party provider is unavailable.

## Repository map

| Path                | Purpose                                                         |
| ------------------- | --------------------------------------------------------------- |
| `apps/mobile`       | Flutter Android, iOS, Windows, and web application              |
| `apps/api`          | Express API, SQLite persistence, provider proxy, authentication |
| `apps/web`          | Vite marketing and legal site                                   |
| `packages/shared`   | Shared TypeScript contracts                                     |
| `docs`              | MkDocs content and detailed legal/architecture notes            |
| `scripts`           | Bun, Flutter, Docker, and emulator automation                   |
| `.github/workflows` | CI, builds, CodeQL, dependency automation, documentation        |

## Source of truth commands

Run commands from the repository root. Prefer these Bun scripts over handwritten tool
commands because local development and CI intentionally share them.

```bash
bun install --frozen-lockfile
bun run build
bun run test
bun run check
bun run check:flutter
bun run check:all
```

Platform commands:

```bash
bun run dev:web
bun run dev:api
bun run dev:site
bun run dev:android
bun run build:android
bun run build:web
bun run build:ios
bun run build:all
```

Deployment and documentation:

```bash
bun run docker:check
bun run docker:up
bun run docker:up:tunnel
bun run docs:build
bun run docs:serve
```

## Required validation

Choose the smallest relevant set while iterating, then run the full relevant gate before
committing:

- TypeScript/API/site changes: `bun run check`
- Flutter changes: `bun run check:flutter`
- Docker changes: `bun run docker:check` and a real `/health` request
- Documentation changes: `bun run docs:build`
- Workflow changes: parse YAML and run `actionlint`
- Cross-cutting/release work: `bun run check:all`

For visible Flutter behavior, also launch `bun run dev:web` or an Android emulator and
verify the rendered interaction. Builds and widget tests alone do not prove layout,
gestures, keyboard behavior, or map overlays are correct.

## Product invariants

- Keep the map mounted while opening destination search or the keyboard; avoid black
  flashes caused by rebuilding the map surface.
- The collapsed bottom sheet shows destination first. Starting location and advanced
  route controls belong in expanded/draw/loop states.
- Map gestures must not steal scrolling from full-screen menus or sheets.
- Navigation follows the rider, rotates the selected rider icon using device heading,
  keeps the rider low on screen, and reserves the top for maneuvers.
- Rider icon selection is persistent and applies during navigation.
- Spotify failures must never crash navigation. Surface recoverable errors through the
  existing self-clearing notification handler.
- OpenStreetMap/OpenFreeMap attribution must remain visible and legally compliant
  without covering controls.
- Map tiles load directly from their provider. Do not proxy bulk tile traffic through
  the Twistaway API.
- The mobile app must degrade to supported on-device/provider behavior when the optional
  API cannot be reached.

## Security and privacy invariants

- Never commit `.env`, Spotify access/refresh tokens, Cloudflare tunnel tokens, signing
  keys, passwords, database files, or production encryption secrets.
- Spotify uses Authorization Code with PKCE. A mobile client secret must not be embedded
  in the application.
- Keep `APP_ENCRYPTION_SECRET` stable per deployment and at least 32 random bytes.
  Rotating it requires an intentional migration plan.
- Persist only encrypted route/profile payloads where the architecture promises
  client-side secrecy.
- Keep production CORS origins explicit. Native requests without an Origin header remain
  supported.
- Treat proxy headers as trusted only when the API is behind the configured
  Cloudflare/reverse-proxy boundary.
- Do not log credentials, bearer tokens, private route payloads, or precise locations.

## Code conventions

- Dart: use `dart format`, satisfy `flutter analyze`, prefer small widgets and services,
  and add widget/unit coverage for regressions.
- TypeScript: strict mode stays enabled; validate external input with Zod; centralize
  configuration; preserve explicit error boundaries.
- Scripts: use portable Bun/JavaScript orchestration unless a platform tool genuinely
  requires shell. Put scripts in `scripts/`, not the repository root.
- Documentation: update README, MkDocs, and examples whenever commands, environment
  variables, domains, or deployment behavior change.
- Generated Flutter platform files should only change through deliberate plugin or
  identity updates.

## Environment and domains

- Public product domain: `https://twistaway.app`
- Production API: `https://api.twistaway.app`
- Future documentation domain: `https://docs.twistaway.app`
- Spotify redirect URI: `twistaway-login://spotify-callback`
- Android application ID: `com.twistaway.app`
- Flutter package: `twistaway_app`

Production Flutter artifacts receive the API URL through `TWISTAWAY_API_BASE_URL`. Local
Flutter development defaults to `http://localhost:4180` unless overridden.

## Git workflow

Preserve unrelated user changes. Do not reset, discard, or rewrite history without
explicit approval. Commits use Conventional Commits with a leading emoji:

```text
✨ feat(mobile): add rider icon selection
🐛 fix(navigation): keep map mounted during search
♻️ refactor(api): isolate provider caching
🧪 test(mobile): cover destination sheet gestures
📝 docs: document Cloudflare deployment
🔧 chore(tooling): standardize Bun commands
👷 ci: validate Docker image health
🔒 security(api): restrict production origins
```

Keep commits cohesive and independently reviewable. Never mix generated build output,
secrets, databases, or local IDE state into commits.

## Definition of done

A change is complete only when:

1. The requested behavior exists without weakening the invariants above.
2. Relevant tests and static checks pass.
3. User-visible behavior is exercised in a real runtime when feasible.
4. Failure paths are safe, logged appropriately, and non-crashing.
5. Documentation and environment examples match the implementation.
6. `git diff --check` passes and no secret/generated artifact is staged.
