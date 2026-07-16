<div align="center">
  <img src="docs/assets/logo.svg" width="112" alt="Twistaway logo" />

# 🏍️ Twistaway

**Privacy-first motorcycle routes built around the ride—not only the destination.**

[![CI](https://github.com/RadNotRed/twistaway/actions/workflows/ci.yml/badge.svg)](https://github.com/RadNotRed/twistaway/actions/workflows/ci.yml)
[![Build](https://github.com/RadNotRed/twistaway/actions/workflows/build.yml/badge.svg)](https://github.com/RadNotRed/twistaway/actions/workflows/build.yml)
[![Documentation](https://github.com/RadNotRed/twistaway/actions/workflows/docs.yml/badge.svg)](https://github.com/RadNotRed/twistaway/actions/workflows/docs.yml)
[![CodeQL](https://github.com/RadNotRed/twistaway/actions/workflows/codeql.yml/badge.svg)](https://github.com/RadNotRed/twistaway/actions/workflows/codeql.yml)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)

[Documentation](docs/index.md) · [Getting started](docs/getting-started.md) ·
[Changelog](CHANGELOG.md) · [Contributing](CONTRIBUTING.md) · [Security](SECURITY.md)
</div>

---

Twistaway is a cross-platform motorcycle route planner and navigation experience for
finding scenic roads, shaping custom rides, building loops, and keeping the map readable
while moving. The Flutter client is designed to degrade gracefully: external APIs and
integrations can enhance a ride, but they should never turn a temporary network failure
into a crashed navigation screen.

<!-- prettier-ignore -->
> [!WARNING]
> Twistaway is pre-release software. Do not use it as the sole source of navigation,
> road conditions, or safety information while riding.

## ✨ Highlights

|     | Capability                                                           |
| --- | -------------------------------------------------------------------- |
| 🗺️  | Full-screen map with a compact, expandable destination sheet         |
| 🧭  | Rider-follow navigation, device heading, and selectable rider icons  |
| 🛣️  | Scenic, twisty, backroad, draw, loop, and road-avoidance controls    |
| 🎵  | Spotify PKCE integration with navigation-friendly playback controls  |
| 🎨  | Map styles, map colors, voice, volume, privacy, and storage settings |
| 🔐  | Encrypted route/profile architecture and opaque API sessions         |
| 📴  | Local caching and provider fallbacks for intermittent connectivity   |
| 🐳  | One Docker Compose stack for a home server or Hetzner deployment     |

## 🚀 Quick start

### Requirements

- [Bun](https://bun.sh/) 1.3.14
- Node.js 25+
- [Flutter](https://flutter.dev/) 3.44.6
- Java 17 and Android SDK for Android
- Xcode and CocoaPods on macOS for iOS

```bash
git clone https://github.com/RadNotRed/twistaway.git
cd twistaway
bun install --frozen-lockfile
cd apps/mobile && flutter pub get && cd ../..
bun run dev:web
```

The Flutter development app opens at `http://127.0.0.1:8080`.

## 🧰 One command surface

Everything developers use regularly is routed through Bun from the repository root:

| Command                 | What it does                                       |
| ----------------------- | -------------------------------------------------- |
| `bun run dev:web`       | Run the Flutter app in a browser                   |
| `bun run dev:android`   | Start the configured emulator and run Flutter      |
| `bun run dev:api`       | Run the Express API with reload                    |
| `bun run dev:site`      | Run the Vite marketing/legal site                  |
| `bun run build`         | Build shared TypeScript, API, and website packages |
| `bun run build:android` | Create `artifacts/twistaway-release.apk`           |
| `bun run build:web`     | Create the Flutter bundle in `artifacts/web/`      |
| `bun run build:ios`     | Create an IPA on macOS                             |
| `bun run build:all`     | Build the workspace and all available app targets  |
| `bun run check`         | Format-check, build, and test the workspace        |
| `bun run check:flutter` | Format-check, analyze, and test Flutter            |
| `bun run check:all`     | Validate workspace, Flutter, docs, and Docker      |

See the complete [command reference](docs/development/commands.md).

## 🗂️ Repository layout

```text
twistaway/
├── apps/
│   ├── api/          # Express, SQLite, provider proxy, encrypted accounts
│   ├── mobile/       # Flutter app for Android, iOS, Windows, and web
│   └── web/          # Vite marketing and legal site
├── packages/shared/  # Shared TypeScript contracts
├── docs/             # MkDocs, architecture, deployment, and legal material
├── scripts/          # Bun-routed build, development, Docker, and emulator tools
├── compose.yaml      # Portable API and optional Cloudflare Tunnel stack
└── AGENTS.md         # Repository contract for AI coding agents
```

## 🐳 Home server or cloud deployment

The same Compose file works on a home server during development and on Hetzner when
Twistaway needs cloud uptime.

```bash
cp docker.env.example .env
openssl rand -hex 32
# Put the generated value and Cloudflare tunnel token in .env.
bun run docker:up:tunnel
```

Recommended hostnames:

- `https://twistaway.app` — product website or Flutter web app
- `https://api.twistaway.app` — Dockerized API
- `https://docs.twistaway.app` — MkDocs documentation

Read the full [Docker and Cloudflare guide](docs/docker-deployment.md) before exposing a
deployment.

## 📚 Documentation

The documentation site uses pinned MkDocs Material dependencies inside an isolated local
virtual environment:

```bash
bun run docs:install
bun run docs:serve
```

`bun run docs:build` uses strict mode, and GitHub Actions validates pull requests and
deploys documentation from `main` through GitHub Pages.

## 🔐 Privacy and security

- Spotify authentication uses Authorization Code with PKCE; no mobile client secret is
  embedded.
- Production API origins are explicit while native clients remain supported.
- Sensitive route/profile payloads follow the encrypted storage architecture.
- Map tiles load directly from their provider instead of consuming API bandwidth.
- `.env`, databases, tunnel tokens, signing material, and generated artifacts are
  excluded from source control.

Review the [security model](docs/architecture/security.md),
[privacy policy](docs/legal/privacy-policy.md), and
[security reporting policy](SECURITY.md).

## 🧪 Quality gates

GitHub Actions provide:

- 👷 Bun workspace build, formatting, and tests
- 📱 Flutter formatting, analysis, and tests
- 🐳 Production API image build and live health check
- 📦 Android, Flutter web, website, and API artifacts
- 📚 Strict MkDocs build and GitHub Pages deployment
- 🔎 CodeQL scanning
- 🤖 Grouped Dependabot updates with guarded automatic merging

Toolchains are pinned to reduce surprise breakage: Bun 1.3.14, Flutter 3.44.6, and
Java 17.

## 🤝 Contributing

Contributions are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md) and
[AGENTS.md](AGENTS.md), keep changes focused, add regression coverage, and use a leading
emoji with Conventional Commits:

```text
✨ feat(settings): add rider icon selection
🐛 fix(navigation): preserve map during destination search
📝 docs: explain Cloudflare deployment
```

## 💚 Credits

Twistaway is possible because of Flutter, Dart, Bun, Node.js, Express, SQLite, Vite,
Docker, MkDocs Material, OpenStreetMap contributors, OpenFreeMap, and the
OSRM/Valhalla/Photon ecosystems. Spotify playback uses Spotify APIs and official brand
assets under Spotify's applicable developer and branding terms.

See [Credits](docs/credits.md) for attribution and trademark notes. Twistaway is not
endorsed by Spotify, OpenStreetMap, Cloudflare, or the other listed providers.

## 📄 License

Twistaway is licensed under the [GNU General Public License v3.0 or later](LICENSE).
