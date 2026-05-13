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
