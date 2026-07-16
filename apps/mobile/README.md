# 📱 Twistaway Flutter app

The primary Twistaway client targets Android, iOS, Windows, and web from one Flutter
project. Run supported commands from the **repository root** through Bun so local
development and CI use the same entry points.

## 🚀 Development

```bash
bun install --frozen-lockfile
cd apps/mobile && flutter pub get && cd ../..
bun run dev:web
```

Other targets:

```bash
bun run dev:mobile   # Select an attached Flutter device
bun run dev:android  # Start the configured emulator and launch the app
```

VS Code includes launch configurations for the configured Android emulator and the
currently selected device. JetBrains run configurations expose the same emulator/build
tooling.

## 📦 Builds

```bash
bun run build:android
bun run build:android:debug
bun run build:web
bun run build:ios
bun run build:all
```

Artifacts are copied to the repository-level `artifacts/` directory. iOS IPA builds
require macOS, Xcode, CocoaPods, and valid Apple signing.

Release-oriented builds default to `https://api.twistaway.app`. Override the embedded
API for staging:

```bash
TWISTAWAY_API_BASE_URL=https://staging-api.twistaway.app bun run build:web
```

## 🧪 Quality

```bash
bun run format:flutter
bun run analyze:flutter
bun run test:flutter
bun run check:flutter
```

UI changes should also be exercised in a browser or emulator. Widget tests do not fully
prove map gestures, bottom-sheet drag behavior, keyboard transitions, or safe-area
spacing.

## 🔑 Spotify configuration

Spotify uses Authorization Code with PKCE and the registered redirect URI:

```text
twistaway-login://spotify-callback
```

Provide the public Spotify client ID through the app's build configuration. Do not add a
Spotify client secret to Flutter, source control, or distributed artifacts.

## 🏷️ Application identity

- Display name: `Twistaway`
- Dart package: `twistaway_app`
- Android application ID: `com.twistaway.app`
- Production API: `https://api.twistaway.app`

See the root [README](../../README.md), [agent guide](../../AGENTS.md), and
[documentation](../../docs/index.md) for architecture and deployment details.
