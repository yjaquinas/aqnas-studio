# infrastructure/server/

Canonical copies of the production host's operational files. Provider-agnostic
by design: the configs here work on any Ubuntu 24.04 server (Oracle Cloud, AWS
EC2, GCP Compute, bare metal, or a Raspberry Pi).

## Layout

```
server/
├── caddy/
│   ├── Caddyfile                # global config, rarely changed
│   └── conf.d/                  # one file per project
│       ├── aqnas-xyz.caddy
│       ├── kumdo-exam.caddy
│       └── ...
├── systemd/                     # one .service per project
│   ├── aqnas-xyz.service
│   ├── kumdo-exam.service
│   └── ...
├── scripts/                     # ops scripts (sync, backup, cert rotation, etc.)
└── ports.conf                   # port registry — source of truth
```

## Rules

1. **This directory is the source of truth.** Server copies at `/etc/caddy/`
   and `/etc/systemd/system/` are derivatives. Edit here first, then sync.
2. **No secrets in these files, ever.** This repo is public. `.caddy` configs
   read tokens from Caddy's environment; `.service` units load secrets via
   `EnvironmentFile=/opt/{project}/.env` which is not in this repo.
3. **Per-project canonical copy path:** `infrastructure/server/caddy/conf.d/{project}.caddy`
   and `infrastructure/server/systemd/{project}.service`. Each is also tracked
   in the project's own `{project}/deploy/` directory — the project repo is the
   dev working copy; this tree is the studio-wide canonical copy.

## Related skills

- `caddy-config` — Caddy conventions and template
- `systemd-service` — systemd conventions and template
- `port-registry` — port allocation rules and scripts
- `deploy-procedure` — how the contents of this tree get applied to the server
