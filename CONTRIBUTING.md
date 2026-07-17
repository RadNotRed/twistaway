# Contributing to Twistaway

Thanks for helping improve Twistaway. Changes should preserve rider safety, privacy,
graceful offline behavior, and a distraction-resistant interface.

## Setup

```bash
git clone https://github.com/RadNotRed/twistaway.git
cd twistaway
bun install --frozen-lockfile
cd apps/mobile && flutter pub get && cd ../..
```

See the [getting started guide](docs/getting-started.md) for platform tooling.

## Development

Use the root Bun scripts:

```bash
bun run dev:web       # Flutter app in a browser
bun run dev:api       # Express API with reload
bun run dev:site      # Marketing/legal website
bun run dev:android   # Emulator plus Flutter app
bun run dev:android:device  # Connected USB Android device plus Flutter logs
```

## Quality checks

```bash
bun run check
bun run check:flutter
bun run docs:build
bun run docker:check
```

Add regression coverage for fixes. For UI changes, verify the real rendered app in
addition to widget tests.

## Commits and pull requests

Use a leading emoji plus Conventional Commits:

```text
✨ feat(settings): add rider icon picker
🐛 fix(sheet): restore swipe expansion
📝 docs: explain home server deployment
```

Keep pull requests focused, describe how the change was tested, and include screenshots
or recordings for visible interface changes.

## Security

Do not open public issues containing vulnerabilities, tokens, private locations, or user
data. Follow [SECURITY.md](SECURITY.md) for private reporting.
