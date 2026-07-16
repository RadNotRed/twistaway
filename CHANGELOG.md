# Changelog

All notable Twistaway changes will be documented here. The project follows
[Semantic Versioning](https://semver.org/) once versioned releases begin.

## Unreleased

### Added

- Full-screen, map-first Flutter planner with expandable destination controls
- Rider-follow navigation and configurable rider icons
- Spotify Authorization Code with PKCE integration and playback controls
- On-device route/search fallback caching
- Rebranded Android, iOS, Windows, web, API, and package identities
- Portable Docker API and optional Cloudflare Tunnel deployment
- Unified Bun development/build/check command surface
- MkDocs Material documentation and GitHub Pages workflow
- AI agent, contribution, security, issue, and pull-request guidance

### Changed

- Replaced the MotoPlanner identity with Twistaway and `com.twistaway.app`
- Reorganized GitHub Actions around pinned CI, builds, docs, CodeQL, and dependency
  automation
- Made Flutter artifacts use `https://api.twistaway.app` by default

### Fixed

- Bottom-sheet swipe and dynamic-height behavior
- Destination keyboard map flashes
- Full-screen menu scrolling being intercepted by map gestures
- Flutter web package/entrypoint errors after the application rename
- Map attribution overlap and compact-sheet spacing
