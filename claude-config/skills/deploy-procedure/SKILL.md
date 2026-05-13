---
name: deploy-procedure
description: Defines the AQNAS deploy procedure for pushing a project to the Ubuntu 24.04 production host, covering the two deploy modes (bootstrap for a new project's first deploy; update for subsequent deploys), the GitHub Actions workflow that triggers on pushes to main (SSH as the `deploy` user, git pull, uv sync, systemctl restart, health check), the manual bootstrap steps that must run on the server once per project (create system user, create /opt/{project}/{project}/ for the repo plus data/ and .uv-cache/ siblings, install systemd unit, install Caddy config, reserve port, populate .env), zero-downtime considerations (uvicorn graceful reload, systemd restart vs reload), and rollback via `git reset --hard <prev>` + `systemctl restart`. Use when preparing a new project's first deploy, reviewing a deploy.yml workflow, debugging a failed deploy (health check failures, permission errors, Caddy reload failures), planning a rollback, or when the user asks about CI/CD, GitHub Actions, SSH deploy, zero-downtime, rollback, or health checks.
---

# deploy-procedure

Deploy to the Ubuntu 24.04 production host.

## Two modes

### Bootstrap — first deploy of a new project

Run once per project. Done on the server, automated by `bootstrap-project.sh`.

Prerequisites:
- `start-new-app` has scaffolded the repo locally and the operator pushed it to GitHub
- The server has been initialized via `init-server.sh` (one-time per server)
- Port is reserved in `infrastructure/server/ports.conf` (locally) — `bootstrap-project.sh` syncs this to the server's `/etc/caddy/ports.conf`

On the server:

```sh
ssh aqnas-prod
cd ~/aqnas-studio
git pull
sudo ./infrastructure/server/scripts/bootstrap-project.sh {project} {port} {project-domain}

# Example:
sudo ./infrastructure/server/scripts/bootstrap-project.sh hello-aqnas 8010 hello-aqnas.aqnas.xyz
```

The script executes a 13-step sequence:

1. Creates the system user `{project}`
2. Adds `deploy` to the `{project}` group
3. Creates `/opt/{project}/{{project},data,.uv-cache}/`
4. Sets ownership to `{project}:{project}` throughout
5. Sets group-write + setgid on the repo dir and `.uv-cache/`
6. Clones the repo as `deploy`, then chowns to the service user
7. Adds `git safe.directory` exception for `deploy` (CVE-2022-24765 mitigation)
8. Generates a stub `.env` (operator edits with real values)
9. Installs the systemd unit
10. Installs the Caddy config
11. Validates Caddy via `systemctl reload`
12. Adds the port to `/etc/caddy/ports.conf`
13. Runs first `uv sync` as deploy

After the script completes, the operator manually:
- Edits `/opt/{project}/.env` with real values
- Adds the DNS A record in Cloudflare
- Starts the service: `sudo systemctl start {project}`
- Verifies the public URL: `curl -fsSL https://{project-domain}/health`
- Triggers the first CI deploy by pushing a commit to `main`

The script refuses to run if the project user, dir, or port already exist — partial-state recovery is an explicit operator decision (see `scripts/README.md` for the cleanup commands).

For the script to work, the server must already have:
- `init-server.sh` completed (gives `deploy` the right sudoers permissions)
- `uv`, `git`, `caddy`, and `gitleaks` on PATH
- `deploy` user with SSH key registered on GitHub (account-level or per-repo)
- Caddy configured with `CLOUDFLARE_API_TOKEN` for DNS challenge

## Ownership model — why it's this way

The service user (`{project}`) is the owner of record for everything in `/opt/{project}/`. It runs the uvicorn process, owns `.env`, and is the primary write identity. The `deploy` user is a CI/CD actor only — it gets write access to `{project}/` (the repo) and `.uv-cache/` via **group membership**, not ownership.

| Path | Owner | Group | Mode | Why |
|---|---|---|---|---|
| `/opt/{project}/` | `{project}` | `{project}` | 755 | Service user is the root owner |
| `/opt/{project}/{project}/` | `{project}` | `{project}` | 2775 | The repo clone — group-writable (deploy can git pull) + setgid (new files inherit `{project}` group) |
| `/opt/{project}/data/` | `{project}` | `{project}` | 755 | Service user writes SQLite + uploads |
| `/opt/{project}/.uv-cache/` | `{project}` | `{project}` | 2775 | Group-writable + setgid (deploy writes during sync, service reads) |
| `/opt/{project}/.env` | `{project}` | `{project}` | 600 | Secrets — deploy cannot read |

After deploy runs `git pull` or `uv sync`, the touched files will be owned by `deploy:{project}` (owner changes to the runner, group inherits via setgid). That's acceptable — the service user has group read access either way. If you prefer strict service ownership at rest, chown back after each CI run; the extra step isn't necessary for correctness.

### Why the `git config safe.directory` step exists

When the service user owns `.git/` but `deploy` runs `git fetch` against it, git refuses with "fatal: detected dubious ownership in repository". This is git's CVE-2022-24765 mitigation — a defensive check, not a misconfiguration. The fix is `git config --global --add safe.directory /opt/{project}/{project}` for the `deploy` user, which `bootstrap-project.sh` runs as step 7.

### Why we don't use `caddy validate`

`bootstrap-project.sh` step 11 uses `systemctl reload caddy` instead of `caddy validate`. Reason: `caddy validate` from a plain shell can't see the systemd-injected env vars (like `CLOUDFLARE_API_TOKEN`), so it fails on TLS provisioning even when the running daemon is fine. `systemctl reload caddy` validates internally with the daemon's environment — same check, correct env.

### Update — subsequent deploys

Automated via GitHub Actions. Triggered on push to `main`. The workflow:

1. SSHes to the server as the `deploy` user
2. `cd /opt/{project}/{project} && git pull`
3. `UV_CACHE_DIR=/opt/{project}/.uv-cache /usr/local/bin/uv sync --frozen`
4. `sudo systemctl restart {project}` (the `deploy` user has sudoers entry for this one command, no password)
5. Polls `/health` until 200 OK or 30s timeout
6. Reports success or failure back to GitHub

On failure at step 5, the workflow doesn't auto-rollback — it fails loudly. Rollback is a deliberate decision (see below).

## GitHub Actions workflow

Canonical `.github/workflows/deploy.yml` lives in the `project-scaffold` skill's templates. The workflow uses repository secrets:

- `SSH_PRIVATE_KEY` — the `deploy` user's SSH key, added to the server's `/home/deploy/.ssh/authorized_keys`
- `SSH_HOST` — the server's public IP or hostname
- `SSH_USER` — always `deploy`

Never put these in `.env.example` or anywhere in the repo. Set them in GitHub's repo settings (Settings → Secrets and variables → Actions).

## Sudoers entry for `deploy`

Installed by `init-server.sh` to `/etc/sudoers.d/aqnas-studio-deploy` (mode 440):

```
deploy ALL=(root) NOPASSWD: /bin/systemctl restart *
deploy ALL=(root) NOPASSWD: /bin/systemctl reload caddy
deploy ALL=(root) NOPASSWD: /bin/systemctl status *
```

The wildcards cover all current and future projects without per-project entries. This is the smallest privilege set that lets the CI/CD flow work. Never grant `deploy` full sudo.

If you're setting up a server manually and need to install this without `init-server.sh`, use `sudo visudo -f /etc/sudoers.d/aqnas-studio-deploy` — visudo validates the syntax before saving, and a syntax error in `/etc/sudoers.d/*` can lock out sudo entirely.

## Zero-downtime considerations

`systemctl restart {project}` is **not** truly zero-downtime — there's a brief window (usually under a second) where the service is down. For AQNAS's current traffic, this is fine.

For actual zero-downtime, the paths are:
- Run two workers behind Caddy's load balancer, rolling-restart them
- Use `systemctl reload` if the service supports SIGHUP-reload (uvicorn supports `--reload`-style behavior via `--reload-dir`, but that's for dev, not prod; for prod graceful reload, use `uvicorn ... --lifespan on` and signal the service)

Don't invest in zero-downtime until traffic justifies it. The current `restart` approach is simple and correct.

## Health check

Every project must expose `GET /health` returning 200 OK. No auth. No database calls. Just `return "ok"`. The deploy workflow polls this; monitoring tools (future) will too.

More involved health checks (DB reachable, disk free, etc.) go at `/health/detailed` with auth. Keep `/health` dumb.

## Rollback

GitHub doesn't auto-rollback. When a deploy fails or production misbehaves:

```bash
# SSH to server as deploy user
ssh deploy@{server}
cd /opt/{project}/{project}

# Check current state
git log --oneline -5

# Roll back
git reset --hard <prev-commit-sha>
UV_CACHE_DIR=/opt/{project}/.uv-cache /usr/local/bin/uv sync --frozen
sudo systemctl restart {project}

# Verify
curl -sSf https://{project-domain}/health
```

Then push a revert commit on the local repo so GitHub matches:

```bash
# Local
git revert <bad-commit-sha>
git push origin main
```

This triggers a clean deploy of the reverted state and keeps history honest.

## What this skill never does

- Never runs deploys from Claude Code. Deploys are triggered by `git push`, not by slash commands.
- Never writes to `/opt/{project}/` directly from a dev machine. All changes go through git.
- Never modifies production `.env` via CI/CD. `.env` is set during bootstrap and edited on the server with `sudo -u {project} editor`.
- Never skips the health check in the deploy workflow. A deploy that lies about success is worse than a deploy that fails.

## Failure modes

- **Health check times out.** Service didn't start or isn't binding the port. `sudo journalctl -u {project} -n 100` on the server.
- **`git pull` fails in CI.** Conflict on the server (someone edited files manually). SSH in, resolve, or `git reset --hard origin/main` if the local state is disposable.
- **`uv sync` fails.** `pyproject.toml` change that needs a system dep, or `uv.lock` is out of date. Run locally first and commit the updated lock.
- **`systemctl restart` fails with permission error.** The `deploy` user's sudoers entry is missing or broken. Check `/etc/sudoers.d/aqnas-studio-deploy` (the file `init-server.sh` installs).
- **Caddy reload fails after a `.caddy` config change.** `systemctl reload caddy` validates the new config internally before applying it — if reload fails, the new config didn't pass validation. Check `journalctl -u caddy -n 30` for the specific error. Common cause: TLS DNS challenge failure (Cloudflare token missing or wrong permissions). The previous config keeps running, so existing sites stay up.
- **Deploy succeeds but the site returns 502.** Upstream service isn't listening. Check `systemctl status {project}` — service may be restart-looping.
- **Two deploys race.** GitHub Actions serializes per-workflow by default; don't change concurrency settings without a reason.
