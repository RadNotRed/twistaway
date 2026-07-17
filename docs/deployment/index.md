# 🚢 Deployment

Twistaway separates static clients from the optional API:

- `twistaway.app`: product website or Flutter web bundle
- `api.twistaway.app`: Express API
- `docs.twistaway.app`: project documentation

For development and an early beta, the API can run on a home server behind Cloudflare
Tunnel. The same Compose stack moves to Hetzner or another Docker host without changing
the public API hostname.

Start with [Docker and Cloudflare](docker.md), then review the
[hosting tradeoffs](hosting.md).
