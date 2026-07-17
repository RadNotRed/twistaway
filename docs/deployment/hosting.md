# API hosting

Twistaway's API is a small Express service, but it uses native Argon2 password hashing
and a persistent SQLite database. That makes a small VM or container host a better
immediate fit than an edge-function platform.

## Recommended starting point

Use a Hetzner CX23 in a European region with Ubuntu LTS, Docker, and a small daily
database backup. It gives the current API a normal filesystem and enough memory for
Bun/Node, Argon2, SQLite, request caching, and a reverse proxy. EU CX servers include
substantially more transfer than typical serverless plans, which keeps map-search and
routing proxy traffic predictable.

As of July 2026, the CX23 is listed at €5.49 or $6.49 per month before tax and optional
IPv4, with 20 TB of included EU transfer. Verify the current total before ordering
because region, currency, tax, and IP choices affect it. See Hetzner's
[current price adjustment table](https://docs.hetzner.com/general/infrastructure-and-availability/price-adjustment/)
and [cloud traffic details](https://www.hetzner.com/cloud/).

Suggested layout:

1. Run the compiled API behind Caddy or nginx with automatic HTTPS.
2. Store `twistaway.sqlite` on the VM's persistent disk, outside the deployed
   application directory.
3. Set a strong `APP_ENCRYPTION_SECRET`, `DB_PATH`, `PORT`, and production CORS origins
   through environment variables.
4. Back up the database daily to a second provider or encrypted object storage.
5. Put Cloudflare's free DNS/proxy in front for TLS edge termination, basic DDoS
   protection, and caching of responses that are actually safe to share.
6. Keep map tiles direct from the tile provider. Do not proxy tile traffic through the
   Twistaway API unless licensing or authentication requires it.

The repository's [Docker deployment](docker.md) implements this layout and can run
unchanged on a home server first, then move to Hetzner while keeping `api.twistaway.app`
stable through Cloudflare Tunnel.

## Alternatives

| Provider                                                                          | Best for                                                                                 | Tradeoff                                                                                                        |
| --------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------- |
| Hetzner Cloud                                                                     | Lowest predictable bandwidth cost; CX23 is €5.49/$6.49 before tax with 20 TB EU transfer | You manage updates, backups, firewall rules, and uptime                                                         |
| [Fly.io](https://fly.io/docs/about/pricing/)                                      | A small container close to users; 512 MB shared CPU starts around $3.32/month            | Persistent volumes and outbound transfer are separate costs                                                     |
| [Railway](https://railway.com/pricing)                                            | Easiest deployment from GitHub; Hobby has a $5 minimum including $5 usage                | Service egress is $0.05/GB and sustained compute can exceed the included credit                                 |
| [Cloudflare Workers](https://developers.cloudflare.com/workers/platform/pricing/) | Free tier includes 100,000 requests/day                                                  | The current Express, native Argon2, and SQLite design requires a rewrite to Workers plus D1 or another database |

## Scaling path

Start with one API instance and SQLite while usage is small. Before adding a second
instance, move account/session data to a managed database and move shared provider
caching to Redis or another distributed cache. At that point the API containers can
remain stateless and scale horizontally.

The public Photon and OSRM endpoints are appropriate for development, not a capacity
plan. Production should use hosted providers with suitable terms or self-host
routing/geocoding services. Self-hosting full-planet routing and geocoding requires far
more memory and storage than the application API itself, so those services should be
evaluated separately rather than installed on the small starter VM.
