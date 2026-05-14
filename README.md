# MotoPlanner

MotoPlanner is a privacy-first motorcycle route planner for Android, iPhone, and web testing. It is organized as a monorepo with a Flutter mobile app, a Node/Express API, a Vite website, and shared TypeScript contracts.

## What Is Included

- `apps/mobile`: Flutter app shell for phones first, with Material 3, route planning preferences, offline-first storage, voice guidance, encrypted local vault design, and map/routing services.
- `apps/api`: Node/Express API backed by SQLite-ready persistence patterns, Argon2id password hashing, opaque sessions, and encrypted payload storage.
- `apps/web`: Static product/legal website that can be hosted separately from the app.
- `packages/shared`: Shared route preference and encrypted payload contracts.
- `.github/workflows`: GitHub Actions for Node and Flutter validation.

## Requirements

- Git
- Node.js 25 or newer
- npm 11 or newer, normally bundled with Node.js 25
- Flutter stable with Dart 3.5 or newer
- Platform tooling for the mobile targets you want to run:
  - Android Studio, Android SDK, and an emulator or device for Android
  - Xcode and CocoaPods on macOS for iOS
  - Chrome or Edge for Flutter web

Check your local toolchain:

```bash
node --version
npm --version
flutter doctor
```

## Install

Install the Node workspace dependencies from the repository root:

```bash
npm install
```

Install the Flutter app dependencies:

```bash
cd apps/mobile
flutter pub get
```

## Development

Run the API from the repository root:

```bash
npm run dev:api
```

Run the website from the repository root:

```bash
npm run dev:web
```

Run the mobile app:

```bash
cd apps/mobile
flutter run
```

Run the mobile app in Chrome:

```bash
cd apps/mobile
flutter run -d chrome
```

## Build

Build the Node workspace:

```bash
npm run build
```

Build the Flutter web app:

```bash
cd apps/mobile
flutter build web
```

## Test And Quality Checks

Run Node workspace tests:

```bash
npm test
```

Run Flutter static analysis and tests:

```bash
cd apps/mobile
flutter analyze
flutter test
```

## Map Tiles

The mobile app uses [Protomaps](https://protomaps.com/) vector tiles from a self-hosted PMTiles file. The tile source is configured at build time using the `MOTOPLANNER_PMTILES_SOURCE` Dart define. When the define is empty or unset, the app falls back to OpenStreetMap raster tiles.

### Local Development

Download or extract a regional PMTiles file using the `pmtiles` CLI:

```bash
# Install the CLI
npm install -g pmtiles

# Extract the US Northeast for quick testing (~1-2 GB)
pmtiles extract https://data.source.coop/protomaps/openstreetmap/v4.pmtiles northeast.pmtiles --maxzoom=15 --bbox=-80.0,38.5,-71.0,42.5

# Extract the full world capped at zoom 14 (~40-60 GB)
pmtiles extract https://data.source.coop/protomaps/openstreetmap/v4.pmtiles world-z14.pmtiles --maxzoom=14
```

Run the app with a local file path:

```bash
cd apps/mobile
flutter run -d chrome --dart-define=MOTOPLANNER_PMTILES_SOURCE=C:/path/to/northeast.pmtiles
```

### Docker Hosting (Testing)

Serve the PMTiles file with nginx. Range request support is required and enabled by default in nginx.

```bash
docker run -d -p 8090:80 -v /path/to/tiles:/usr/share/nginx/html:ro nginx:alpine
```

Run the app pointing at the Docker host:

```bash
flutter run -d chrome --dart-define=MOTOPLANNER_PMTILES_SOURCE=http://localhost:8090/northeast.pmtiles
```

### Cloudflare R2 (Production)

Upload the PMTiles file to an R2 bucket. R2 supports HTTP range requests natively and has zero egress fees.

1. Create a bucket and enable public access or use a custom domain.
2. Upload the file: `pmtiles upload world-z14.pmtiles --bucket=your-r2-bucket`
3. Build the app with the R2 URL:

```bash
flutter build web --dart-define=MOTOPLANNER_PMTILES_SOURCE=https://tiles.yourdomain.com/world-z14.pmtiles
```

### Satellite Tiles

Satellite imagery uses Esri World Imagery raster tiles as a fallback since Protomaps does not include satellite data.

## GitHub Actions

The repository includes:

- `Node CI`: installs dependencies with `npm ci`, builds the Node workspace, and runs Node tests.
- `Flutter CI`: installs Flutter dependencies, runs `flutter analyze`, runs `flutter test`, and builds the Flutter web target.
- `CodeQL`: scans the JavaScript and TypeScript code for security issues on pushes, pull requests, and a weekly schedule.
- Dependabot configuration for weekly npm and Flutter dependency updates.

Both CI workflows run on pushes and pull requests targeting `main`.

## Security Model

Passwords are never stored directly. The API stores Argon2id password hashes with per-password salts encoded in the PHC string.

Sensitive app data is encrypted before persistence:

- routes
- home address
- IP and audit metadata tied to an authenticated account
- saved ride logs

The client derives a vault key from the user's password plus an app/install secret. The backend stores encrypted payload envelopes and does not need plaintext route or home address values.

## Integration Notes

Waze official integration is partner-gated and focused on app switching, ETA, and route handoff. WzSABRE/Waze incident access is treated as an optional provider adapter because Waze changes unofficial interfaces. Open-Meteo is the default weather provider because it has a public forecast API with no API key for non-commercial use.

## Repository Hygiene

Generated and local-only files should stay out of source control, including:

- `node_modules/`
- TypeScript `dist/` output
- Flutter `.dart_tool/` and `build/` output
- local `.env` files
- local SQLite/database files

## License

MotoPlanner is licensed under the GNU General Public License v3.0 or later. See [LICENSE](LICENSE).
