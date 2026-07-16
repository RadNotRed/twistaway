# Docker deployment

The same Compose stack runs on a home server or a Hetzner VM. The API listens on the
host's loopback interface by default, stores SQLite data in a named volume, and can be
published through an optional Cloudflare Tunnel container.

## Domain layout

Use these hostnames so the website and API can evolve independently:

- `twistaway.app`: public website or Flutter web application
- `www.twistaway.app`: redirect to `twistaway.app`
- `api.twistaway.app`: Dockerized API in this stack

The mobile app should eventually use `https://api.twistaway.app` as its production API
base URL. GitHub artifacts and the repository build scripts now embed that URL
automatically. Override it for a staging server by setting the `TWISTAWAY_API_BASE_URL`
environment variable before building. Do not expose SQLite, Docker, or the host's
management interface through Cloudflare.

## Start the API locally

From the repository root:

```bash
cp docker.env.example .env
openssl rand -hex 32
```

Put the generated value in `.env` as `APP_ENCRYPTION_SECRET`, then run:

```bash
docker compose up -d --build api
docker compose ps
curl http://127.0.0.1:4180/health
```

The expected health response is:

```json
{ "ok": true, "service": "twistaway-api" }
```

View logs or stop the stack with:

```bash
docker compose logs -f api
docker compose down
```

`docker compose down` preserves the `twistaway-data` volume. Do not add `-v` unless you
intentionally want to delete the database.

## Publish through Cloudflare

1. Add `twistaway.app` to Cloudflare and point the domain's nameservers to Cloudflare.
2. In Cloudflare Zero Trust, create a remotely managed tunnel named `twistaway-api`.
3. Add a public hostname:
   - Hostname: `api.twistaway.app`
   - Service type: `HTTP`
   - Service URL: `http://api:4180`
4. Copy the tunnel token into `.env` as `CLOUDFLARE_TUNNEL_TOKEN`.
5. Start the API and tunnel profile:

```bash
docker compose --profile tunnel up -d --build
curl https://api.twistaway.app/health
```

Cloudflare Tunnel connects outward from the server, so no router port-forward or public
inbound firewall rule is required. Keep the API port bound to `127.0.0.1`; the
`cloudflared` container reaches `api:4180` over the Compose network.

## Update or move servers

Pull the new code and rebuild in place:

```bash
docker compose --profile tunnel pull cloudflared
docker compose --profile tunnel up -d --build
docker image prune -f
```

The Compose file uses the same named volume on a home server and Hetzner. To migrate,
stop writes, back up the volume, restore it on the new host, copy the `.env` file
securely, and start the stack. Cloudflare can keep the public hostname unchanged while
its tunnel token moves to the new server.

## Back up SQLite

For a simple cold backup, briefly stop the API, archive the volume, and restart:

```bash
docker compose stop api
docker run --rm \
  -v twistaway-data:/source:ro \
  -v "$PWD/backups:/backup" \
  alpine:3.22 \
  tar czf "/backup/twistaway-$(date +%Y%m%d-%H%M%S).tar.gz" -C /source .
docker compose start api
```

Store backups on another machine or provider and periodically test a restore. For
frequent backups without downtime, add a SQLite-aware tool such as Litestream rather
than copying a live database and WAL files independently.

## Production checklist

- Keep `.env` readable only by the deployment account and never commit it.
- Keep the host OS, Docker Engine, and `cloudflared` image updated.
- Enable rate limiting and security rules in Cloudflare.
- Use a UPS and off-site backups when hosting at home.
- Monitor `/health`, disk space, memory, and tunnel availability externally.
- Keep map tiles direct from the provider instead of proxying them through the API.
