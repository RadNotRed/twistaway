# 🚀 Getting started

## Requirements

- Git
- Bun 1.3.14
- Node.js 25 or newer
- Flutter 3.44.6 with Dart
- Java 17 and Android SDK for Android builds
- Xcode and CocoaPods on macOS for iOS builds
- Python 3.8 or newer for MkDocs
- Docker Engine with Compose for API containers

Check the main toolchains:

```bash
bun --version
node --version
flutter doctor -v
docker compose version
```

## Install

```bash
git clone https://github.com/RadNotRed/twistaway.git
cd twistaway
bun install --frozen-lockfile
cd apps/mobile
flutter pub get
cd ../..
```

## Run the products

=== "Flutter web"

    ```bash
    bun run dev:web
    ```

=== "Android"

    ```bash
    bun run dev:android
    ```

=== "API"

    ```bash
    bun run dev:api
    ```

=== "Marketing site"

    ```bash
    bun run dev:site
    ```

## Spotify development

Spotify uses Authorization Code with PKCE and the redirect URI
`twistaway-login://spotify-callback`. Provide the public client ID through the
documented Flutter build configuration. Never embed a Spotify client secret in the
mobile application.

## Next steps

- Learn the [Bun command surface](development/commands.md).
- Review the [architecture](architecture/overview.md).
- Start a local API with [Docker](deployment/docker.md).
