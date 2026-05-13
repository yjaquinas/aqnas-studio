---
name: caddy-config
description: Defines Caddy v2 configuration conventions for AQNAS projects on Ubuntu 24.04 production hosts, covering per-project files under /etc/caddy/conf.d/, the global Caddyfile that imports them, Cloudflare DNS challenge for TLS via the caddy-dns/cloudflare plugin (CLOUDFLARE_API_TOKEN from the Caddy service environment), Cloudflare trusted_proxies ranges for correct client-IP forwarding, the canonical Content-Security-Policy and security header block (X-Content-Type-Options, X-Frame-Options, Referrer-Policy, Strict-Transport-Security, -Server), static file serving from /opt/{project}/{project}/app/static, reverse proxy to 127.0.0.1:{port} with X-Real-IP header, gzip encoding, and access logging with 50MiB rotation. Use when generating or reviewing a .caddy config, adding a new subdomain to the production server, debugging TLS handshake or DNS challenge failures, debugging CSP violations in the browser console, or when the user asks about Caddy, trusted_proxies, DNS challenge, CSP, Content-Security-Policy, reverse_proxy, or log rotation. Contains template.caddy ready for variable substitution.
---

# caddy-config

Caddy v2 configuration for AQNAS projects on Ubuntu 24.04 production hosts.

## File structure

```
/etc/caddy/
├── Caddyfile                # global — rarely touched
└── conf.d/
    ├── aqnas.caddy          # per-project
    ├── kumdo-exam.caddy
    └── {next-project}.caddy
```

Canonical copies tracked in `$AQNAS_STUDIO_ROOT/infrastructure/server/caddy/` (default `~/aqnas-studio/infrastructure/server/caddy/`). `.caddy` configs contain no secrets (the Cloudflare token is read from Caddy's environment, not the config) so they're safe to commit to the public studio repo.

## Global Caddyfile

Do not modify. It sets Cloudflare trusted_proxies and imports all per-project configs:

```caddy
{
    servers {
        trusted_proxies static 173.245.48.0/20 103.21.244.0/22 103.22.200.0/22 103.31.4.0/22 141.101.64.0/18 108.162.192.0/18 190.93.240.0/20 188.114.96.0/20 197.234.240.0/22 198.41.128.0/17 162.158.0.0/15 104.16.0.0/13 104.24.0.0/14 172.64.0.0/13 131.0.72.0/22
    }
}

import /etc/caddy/conf.d/*.caddy
```

The trusted_proxies list is Cloudflare's published IP ranges. When Cloudflare updates them (rare), update this list from https://www.cloudflare.com/ips/.

## Per-project template

See `${CLAUDE_SKILL_DIR}/template.caddy`. Substitute:

- `{project-domain}` — full domain (e.g. `kumdo-exam.aqnas.xyz`)
- `{project}` — kebab-case project name (matches systemd User, /opt/ path, port-registry entry)
- `{port}` — integer from port registry

## Block-by-block

### TLS via Cloudflare DNS challenge

```caddy
tls {
    dns cloudflare {env.CLOUDFLARE_API_TOKEN}
}
```

DNS challenge is used instead of HTTP challenge because the server may be behind Cloudflare proxying — HTTP-01 doesn't work reliably through the proxy. DNS-01 is more robust.

`CLOUDFLARE_API_TOKEN` is read from the environment. Caddy runs as a systemd service and gets the token from its own `EnvironmentFile` at `/etc/default/caddy` or similar — not from project env files. Set it once per server.

### Security headers

The canonical block — use exactly this unless a project has a justified reason to deviate:

```caddy
header {
    Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline' https://cdn.jsdelivr.net https://unpkg.com; style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; font-src 'self' https://fonts.gstatic.com; connect-src 'self'; object-src 'none'; base-uri 'self'; form-action 'self'"
    X-Content-Type-Options "nosniff"
    X-Frame-Options "DENY"
    Referrer-Policy "strict-origin-when-cross-origin"
    Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
    -Server
}
```

CSP rationale:
- `'unsafe-inline'` in script-src and style-src — required for Alpine.js inline `x-data` directives and Tailwind JIT inline styles. If a project drops Alpine + uses only HTMX, this can tighten.
- `cdn.jsdelivr.net` and `unpkg.com` — HTMX and Alpine loaded from CDN. If self-hosted, drop these.
- `fonts.googleapis.com` / `fonts.gstatic.com` — if not using Google Fonts, drop these.
- `connect-src 'self'` — XHR/fetch only to same origin, no third-party APIs from browser.
- `-Server` — strips Caddy's Server header to reduce fingerprinting.

### Static files

```caddy
handle /static/* {
    root * /opt/{project}/{project}/app
    file_server
}
```

The repo clone is at `/opt/{project}/{project}/`, and FastAPI serves static from `app/static/` within that. Caddy's `root` directive prefixes the path, so `/static/x.css` resolves to `/opt/{project}/{project}/app/static/x.css`. The repo subdirectory is named after the project (rather than a generic `app/`) so the project user owns a clearly-named tree at `/opt/{project}/`.

### Reverse proxy

```caddy
handle {
    reverse_proxy 127.0.0.1:{port} {
        header_up X-Real-IP {remote_host}
    }
}
```

`{remote_host}` is Caddy's placeholder for the connecting client's IP. Because we configured Cloudflare in `trusted_proxies`, Caddy correctly reads the `CF-Connecting-IP` header and exposes it as `{remote_host}`, so FastAPI sees the real user IP, not Cloudflare's IP.

### Gzip

```caddy
encode gzip
```

Caddy compresses text responses (HTML, CSS, JS, JSON) on the fly. Almost always worth it for HTMX partials.

### Logging

```caddy
log {
    output file /var/log/caddy/{project}-access.log {
        roll_size 50MiB
        roll_keep 5
        roll_keep_for 168h
    }
}
```

Keeps 5 × 50MiB rotations per project, up to 168 hours (7 days). Caddy handles rotation itself — no logrotate needed.

## Install sequence

```bash
# 1. Copy project config
sudo cp /opt/{project}/{project}/deploy/{project}.caddy /etc/caddy/conf.d/

# 2. Validate via reload (Caddy validates internally, with the daemon's environment)
sudo systemctl reload caddy

# 3. Verify
sudo systemctl status caddy
```

**Note on `caddy validate`:** the obvious-looking `sudo caddy validate --config /etc/caddy/Caddyfile` runs in *your* shell, not the systemd-managed Caddy environment. Configs that reference `{env.CLOUDFLARE_API_TOKEN}` will fail with "API token '' appears invalid" because the env var is set in the systemd drop-in, not your shell. `systemctl reload caddy` re-validates the config inside the daemon (with the right env), then atomically swaps to it on success. If validation fails, the old config keeps running — no downtime.

If you really need a standalone validator (e.g., pre-commit hook), source the env first:

```sh
sudo bash -c 'set -a; source /etc/systemd/system/caddy.service.d/override.conf 2>/dev/null; caddy validate --config /etc/caddy/Caddyfile'
```

A broken config is non-negotiable — never reload without confirming the validate (whether via `systemctl reload` or the env-sourced workaround) succeeds. A bad config takes down every site Caddy serves.

## Debugging

| Symptom | Likely cause |
|---|---|
| `ACME challenge failed` | `CLOUDFLARE_API_TOKEN` missing from Caddy's environment, or token lacks Zone:DNS:Edit permission. |
| `TLS handshake failed` | DNS not propagated yet. Check `dig {project-domain}` resolves to the production server's IP before expecting TLS to work. |
| `502 Bad Gateway` | The upstream FastAPI service isn't listening on `{port}`. Check `systemctl status {project}`. |
| `404` on /static/* | Path typo in `root` directive, or FastAPI's static files aren't at the expected path. |
| Console: "Refused to load script from..." | CSP violation. Either the script is loading from an undocumented source, or `cdn.jsdelivr.net` / `unpkg.com` isn't enough. |
| Client IPs show as Cloudflare IPs in logs | `trusted_proxies` missing in the global Caddyfile, or the Cloudflare ranges are out of date. |
| Caddy reload failed, site down | The new config was invalid. Revert via `git checkout` on the canonical copy, re-copy, reload. |

## Canonical copies

Same three-location discipline as `.service` files:

1. `~/{project}/deploy/{project}.caddy` — dev working copy
2. `$AQNAS_STUDIO_ROOT/infrastructure/server/caddy/conf.d/{project}.caddy` — studio canonical (tracked in git; no secrets)
3. `/etc/caddy/conf.d/{project}.caddy` — live on the production host

## What not to do

- Don't use HTTP-01 challenge behind Cloudflare proxy — fails unpredictably
- Don't hardcode the production host's IP anywhere in Caddy configs — DNS handles it
- Don't skip the validation step before reloading (whether via `systemctl reload caddy` or env-sourced `caddy validate`)
- Don't put secrets in the `.caddy` file — they'd end up in the public studio repo. Use `{env.VAR}` instead.
- Don't remove `-Server` without reason — stripping the Server header is one of the cheapest security wins
- Don't relax CSP globally to fix one violation; whitelist the specific source
