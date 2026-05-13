---
name: systemd-service
description: Defines systemd service conventions for AQNAS projects on Ubuntu 24.04 production hosts, covering per-project user isolation (one system user per project for blast-radius containment; the service user owns /opt/{project} and the deploy user has group-level write access for CI/CD only), uv run ExecStart patterns, EnvironmentFile loading from /opt/{project}/.env (chmod 600, service-user-only), filesystem hardening directives (ProtectSystem=strict, ProtectHome=yes, PrivateTmp=yes, NoNewPrivileges=yes, ReadWritePaths covering /opt/{project}/data and /opt/{project}/.uv-cache, ReadOnlyPaths=/opt/{project}), restart policy (on-failure, 3s delay), and the project-local uv cache at /opt/{project}/.uv-cache (owned {project}:{project}, mode 2775 for group write + setgid) that matches the dev-side ./.uv-cache pattern. Use when generating or reviewing a .service file, deploying a new project, adding or changing systemd hardening, debugging why a service won't start (permission issues, path typos, EnvironmentFile failures, uv cache failures), or when the user asks about systemd, ExecStart, User/Group isolation, ProtectSystem, ReadWritePaths, UV_CACHE_DIR, or service restart behavior. Contains template.service ready for variable substitution: {Project Display Name}, {project}, {project-domain}, {port}.
---

# systemd-service

Service-file conventions for AQNAS projects on Ubuntu 24.04 production hosts.

## Design principle

One system user per project. Not a shared `www-data` or similar. The blast radius of any compromise is bounded by the single project's `/opt/{project}/` tree, and systemd hardening locks that tree further.

This is why AQNAS uses per-project users even though it's a one-person studio — if one FastAPI app has an RCE, it doesn't compromise the others.

## Template

See `${CLAUDE_SKILL_DIR}/template.service` for the canonical unit file. Substitute:

- `{Project Display Name}` — human-readable, used in `Description=`
- `{project}` — kebab-case project name, used as User/Group and in paths
- `{project-domain}` — e.g. `kumdo-exam.aqnas.xyz`, used only in `Description=`
- `{port}` — integer from the port registry (see `port-registry` skill)

## Variable rationale

| Directive | Value | Why |
|---|---|---|
| `User`, `Group` | `{project}` | Per-project isolation |
| `WorkingDirectory` | `/opt/{project}/{project}` | Repo clone lives here |
| `EnvironmentFile` | `/opt/{project}/.env` | Secrets, `chmod 600`, owned by `{project}` |
| `Environment=UV_CACHE_DIR` | `/opt/{project}/.uv-cache` | Project-local uv cache, owned by `{project}:{project}` with mode 2775 (group write + setgid). The deploy user is in the `{project}` group, so CI/CD can write the cache during `uv sync`; the service user owns it and reads via `uv run`. Cache lives as a sibling of the repo clone (alongside `data/` and `.env`). |
| `ExecStart` | `/usr/local/bin/uv run uvicorn app.main:app --host 127.0.0.1 --port {port} --workers 2` | Caddy handles TLS; uvicorn binds loopback only. `--workers 2` is the default; tune to match the host's CPU count (2 workers for the current 2-CPU production host). |
| `Restart` | `on-failure` | Crash → restart. Manual `systemctl stop` → stay stopped. |
| `RestartSec` | `3` | Short enough to recover fast, long enough to avoid restart loops |

## Hardening rationale

| Directive | Effect |
|---|---|
| `ProtectSystem=strict` | Entire filesystem read-only except explicitly opened paths |
| `ProtectHome=yes` | `/home`, `/root`, `/run/user` invisible to the service |
| `PrivateTmp=yes` | Service gets its own `/tmp`, isolated from other services |
| `NoNewPrivileges=yes` | No `setuid`, no privilege escalation via `exec` |
| `ReadWritePaths=/opt/{project}/data /opt/{project}/.uv-cache` | SQLite DB and uploads live in `data/`; uv stores downloaded wheels in `.uv-cache/`. Both must be writable by the service user. |
| `ReadOnlyPaths=/opt/{project}` | Makes the `/opt/{project}` tree read-only by default — pair with the CI/CD deploy flow that writes as the `deploy` user. `ReadWritePaths` above carves out the two exceptions. |

`LimitNOFILE=65536` — file descriptor limit. FastAPI with many connections can exhaust the default 1024.

## Install sequence

```bash
# 1. Copy from repo to systemd
sudo cp /opt/{project}/{project}/deploy/{project}.service /etc/systemd/system/

# 2. Reload systemd to pick up the new file
sudo systemctl daemon-reload

# 3. Enable for auto-start on boot
sudo systemctl enable {project}

# 4. Start now
sudo systemctl start {project}

# 5. Verify
sudo systemctl status {project}
sudo journalctl -u {project} -f
```

## Debugging

| Symptom | Likely cause |
|---|---|
| `status=203/EXEC` | `ExecStart` path wrong, or the `uv` binary is missing at `/usr/local/bin/uv`. Verify with `which uv`. |
| `status=217/USER` | `{project}` user doesn't exist. Run `adduser {project} --system` first (typically done by `bootstrap.sh`). |
| `Failed to read environment file` | `.env` missing or unreadable. Check `ls -la /opt/{project}/.env` — should be owned by `{project}:{project}` and `-rw-------`. |
| Service runs, port not reachable | Caddy config missing or wrong port. Check `caddy-config` skill and the server's `/etc/caddy/ports.conf`. |
| Can't write to data dir | `ReadWritePaths` misspelled, or the data dir doesn't exist. `mkdir -p /opt/{project}/data && chown {project}:{project} /opt/{project}/data`. |
| uv sync fails during deploy | `/opt/{project}/.uv-cache/` missing, or deploy user lacks group write. Verify: `ls -la /opt/{project}/` — cache dir should be `{project}:{project}`, mode 2775. Also verify deploy is in the `{project}` group: `id deploy`. If missing, re-run: `sudo usermod -aG {project} deploy && sudo chmod 2775 /opt/{project}/.uv-cache`. |

## Canonical copies

Every `.service` file lives in **three** places:

1. `~/{project}/deploy/{project}.service` — dev working copy (tracked in project git)
2. `$AQNAS_STUDIO_ROOT/infrastructure/server/systemd/{project}.service` — studio-wide canonical copy, tracked in the public `aqnas-studio` repo (the pattern works for any Ubuntu 24.04 host — any cloud VM, bare metal, or even a Raspberry Pi; `.service` files never contain secrets, so they're safe to commit)
3. `/etc/systemd/system/{project}.service` — live on the production host

When changing: edit (1), sync to (2) via `$AQNAS_STUDIO_ROOT/infrastructure/server/scripts/`, deploy to (3) via the install sequence above.

## What not to do

- Don't use `Type=forking` — uvicorn is `Type=exec`
- Don't bind uvicorn to `0.0.0.0` — Caddy is the only public-facing listener; uvicorn is loopback-only
- Don't put secrets directly in `Environment=` lines (they're visible in `systemctl show`); use `EnvironmentFile=` with chmod 600
- Don't skip `NoNewPrivileges=yes` — it's cheap and closes a class of exploits
- Don't raise `--workers` above 2× CPU count without load-testing; more workers ≠ more throughput when CPU-bound
