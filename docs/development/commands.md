# 🧰 Command reference

All supported development entry points are routed through Bun from the repository root.

## Development

| Command                      | Purpose                                                  |
| ---------------------------- | -------------------------------------------------------- |
| `bun run dev:web`            | Launch the Flutter app on a local web server and open it |
| `bun run dev:mobile`         | Launch Flutter and select an attached device             |
| `bun run dev:android`        | Start the configured emulator and launch Flutter         |
| `bun run dev:android:device` | Launch Flutter on an authorized USB Android device       |
| `bun run dev:api`            | Run the Express API with file watching                   |
| `bun run dev:site`           | Run the Vite marketing/legal site                        |

## Builds

| Command                       | Output                                           |
| ----------------------------- | ------------------------------------------------ |
| `bun run build`               | TypeScript shared package, API, and Vite site    |
| `bun run build:android`       | `artifacts/twistaway-release.apk`                |
| `bun run build:android:debug` | `artifacts/twistaway-debug.apk`                  |
| `bun run build:web`           | `artifacts/web/` Flutter bundle                  |
| `bun run build:ios`           | `artifacts/twistaway-release.ipa` on macOS       |
| `bun run build:all`           | Workspace plus every supported platform artifact |

Set `TWISTAWAY_API_BASE_URL` to override the API embedded in Flutter artifacts:

```bash
TWISTAWAY_API_BASE_URL=https://staging-api.twistaway.app bun run build:web
```

## Quality

| Command                 | Checks                                                   |
| ----------------------- | -------------------------------------------------------- |
| `bun run format`        | Prettier plus Dart formatting                            |
| `bun run format:check`  | Formatting without writing                               |
| `bun run check`         | Formatting, TypeScript builds, and workspace tests       |
| `bun run check:flutter` | Dart format, analysis, and Flutter tests                 |
| `bun run check:all`     | Workspace, Flutter, docs, and Docker validation          |
| `bun run clean`         | Remove generated artifacts and build output              |
| `bun run clean:all`     | Also remove dependency, Flutter, Gradle, and docs caches |

## Documentation and deployment

| Command                    | Purpose                                      |
| -------------------------- | -------------------------------------------- |
| `bun run docs:install`     | Install pinned MkDocs dependencies           |
| `bun run docs:serve`       | Preview documentation locally                |
| `bun run docs:build`       | Strict documentation build                   |
| `bun run docker:check`     | Validate Compose and build the API image     |
| `bun run docker:up`        | Start the API locally                        |
| `bun run docker:up:tunnel` | Start the API and Cloudflare Tunnel          |
| `bun run docker:logs`      | Follow API container logs                    |
| `bun run docker:down`      | Stop the Compose stack without deleting data |
