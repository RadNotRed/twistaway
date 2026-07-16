# Security policy

## Reporting a vulnerability

Please use GitHub's private vulnerability reporting feature for the
`RadNotRed/twistaway` repository. Do not disclose exploitable details in a public issue.

Include affected versions or commits, reproduction steps, impact, and any suggested
mitigation. Avoid including real credentials, precise user locations, or production
database contents.

## Supported code

Twistaway is pre-release software. Security fixes target the current `main` branch until
versioned releases and a formal support window are established.

## Secrets

The project never needs production secrets committed to source control. Use local `.env`
files, protected GitHub Actions secrets, Android/iOS signing stores, and
Cloudflare-managed tunnel tokens.
