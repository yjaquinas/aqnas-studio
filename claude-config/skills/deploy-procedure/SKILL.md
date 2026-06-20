---
name: deploy-procedure
description: Defines the AQNAS deploy procedure for the Ubuntu 24.04 production host, covering the two deploy modes (bootstrap for a new project's first deploy via bootstrap-project.sh; update for subsequent deploys via deploy/run.sh in the project repo), the project layout convention (deploy/run.sh as the deploy entry point, infra/{project}.service and infra/{project}.caddy as declarative infrastructure config), the GitHub Actions workflow as a thin SSH shell that just calls deploy/run.sh, the canonical deploy/run.sh shape (sg + git fetch + git reset --hard for sync, uv sync, optional Tailwind build, conditional Caddy config sync, systemctl restart, health check), the ownership model where the service user owns the repo and deploy gets write access via group membership, the git safe.directory exceptions needed for both deploy and service users, the sudoers entries needed (systemctl wildcards plus a cp wildcard for Caddy syncs), and rollback via git fetch + reset --hard <prev>. Use when preparing a new project's first deploy, reviewing a deploy.yml workflow or deploy/run.sh script, debugging a failed deploy (health check failures, dubious-ownership errors, sudoers permission errors, Caddy reload failures), planning a rollback, or when the user asks about CI/CD, GitHub Actions, SSH deploy, deploy/run.sh, the deploy vs infra directory split, zero-downtime, rollback, health checks, or sg group activation.
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
4. Sets ownership to `{project}:{project}` throughout (before clone, so the directory itself is service-user-owned)
5. Sets group-write + setgid on the repo dir and `.uv-cache/`
6. Clones the repo as `deploy` (whose SSH key is on GitHub). The directory's setgid + group-writable bits mean cloned files end up `deploy:{project}` — the service user has read/execute via group; deploy retains write for future `git reset --hard`.
7. Adds `git safe.directory` exceptions for both `deploy` and `{project}` users (CVE-2022-24765 mitigation)
8. Generates a stub `.env` (operator edits with real values)
9. Installs the systemd unit from `infra/{project}.service`
10. Installs the Caddy config from `infra/{project}.caddy`
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

### Update — subsequent deploys

Subsequent deploys go through `deploy/run.sh` — a per-project script the GitHub Actions workflow calls. The workflow is thin; the script is where the logic lives.

Workflow shape (canonical, in `.github/workflows/deploy.yml`):

```yaml
- name: Deploy
  run: |
    ssh deploy@$SSH_HOST "cd /opt/{project}/{project} && bash deploy/run.sh"
```

That's it. SSH in, cd, call the script. Everything else is in `deploy/run.sh`.

What `deploy/run.sh` does (the canonical template lives in `project-scaffold`):

1. **Sync to remote main**: `sg "{project}" -c "git fetch origin main && git reset --hard origin/main"`
2. **Sync dependencies**: `uv sync --frozen --no-dev`
3. **Build assets** (if Tailwind is used): auto-install standalone CLI if missing, then build CSS
4. **Sync Caddy config** (if `infra/{project}.caddy` changed): `sudo cp infra/{project}.caddy /etc/caddy/conf.d/` + `sudo systemctl reload caddy`
5. **Restart the application service**: `sudo systemctl restart {project}`
6. **Health check**: poll `http://127.0.0.1:{port}/health` with 5 retries × 2s

If health check fails, the workflow fails loudly. Rollback is a deliberate decision (see below).

#### Why `git fetch && git reset --hard` instead of `git pull`

`git pull` does fetch + merge. If the server's state diverged from `origin/main` for any reason — manual experiment, partial deploy, accidental commit — `git pull` errors with merge conflicts and the deploy hangs.

`git fetch && git reset --hard origin/main` always succeeds because it discards any server-side state and replaces it with whatever `origin/main` is. The server is treated as cache, not source. This is the right model: source of truth lives in GitHub; the server is reproducible from it.

#### Why `sg "{project}"` wraps the git command

Deploy is in the `{project}` group via secondary membership, but its primary group is `deploy`. When git creates files inside `.git/objects/`, the directory's setgid bit usually ensures group inheritance — but git's internal file creation occasionally bypasses that, and files end up `deploy:deploy`. The service user (which is `{project}:{project}`) can't then read them.

`sg "{project}" -c "..."` runs the wrapped command with `{project}` as the effective primary group, so git's writes land as `deploy:{project}` consistently. Belt-and-suspenders with the setgid bit. Cheap defensive layering for a footgun that's hard to debug when it bites.

## Project layout — `deploy/` vs `infra/`

Each project's repo has two infrastructure-related directories:

```
{project}/
├── deploy/
│   └── run.sh                  ← the only file in deploy/
├── infra/
│   ├── {project}.caddy         ← Caddy reverse-proxy config
│   └── {project}.service       ← systemd unit
└── (project-specific operational scripts also live in infra/, optional)
```

The split is by intent:

- `deploy/` — what's actively _run_ during deploy. Currently just `run.sh`. The CI workflow calls this; nothing else goes here.
- `infra/` — declarative _configuration_ that lives in `/etc/` on the server (systemd unit, Caddy config). Plus optional per-project operational scripts (backup, hardening, OrbStack staging, etc.) that belong with the project but aren't part of the deploy entry point.

`bootstrap-project.sh` reads from `infra/` to install the systemd unit and Caddy config. `deploy/run.sh` reads from `infra/{project}.caddy` to optionally re-sync Caddy on each deploy when it changes.

## Ownership model — why it's this way

The service user (`{project}`) is the owner of record for everything in `/opt/{project}/`. It runs the uvicorn process, owns `.env`, and is the primary write identity. The `deploy` user is a CI/CD actor only — it gets write access to `{project}/` (the repo) and `.uv-cache/` via **group membership**, not ownership.

| Path                        | Owner       | Group       | Mode | Why                                                                                                     |
| --------------------------- | ----------- | ----------- | ---- | ------------------------------------------------------------------------------------------------------- |
| `/opt/{project}/`           | `{project}` | `{project}` | 755  | Service user is the root owner                                                                          |
| `/opt/{project}/{project}/` | `{project}` | `{project}` | 2775 | The repo clone — group-writable (deploy can git operate) + setgid (new files inherit `{project}` group) |
| `/opt/{project}/data/`      | `{project}` | `{project}` | 755  | Service user writes SQLite + uploads                                                                    |
| `/opt/{project}/.uv-cache/` | `{project}` | `{project}` | 2775 | Group-writable + setgid (deploy writes during sync, service reads)                                      |
| `/opt/{project}/.env`       | `{project}` | `{project}` | 600  | Secrets — deploy cannot read                                                                            |

After deploy runs git or uv sync, the touched files will be owned by `deploy:{project}` (owner is the runner, group inherits via setgid + `sg`). That's acceptable — the service user has group read access either way.

### Why the `git config safe.directory` step exists

When the user running git isn't the owner of the repo's `.git/` directory, git refuses with "fatal: detected dubious ownership in repository". This is git's CVE-2022-24765 mitigation — a defensive check, not a misconfiguration.

In our layout, `.git/` is owned by `deploy` (the user that cloned), so `deploy` running git operations is fine without the exception. But two scenarios need it:

1. **The service user running git manually** (e.g., `sudo -u {project} git status` during debugging) — service user isn't the owner of `.git/`, so the check fires.
2. **Defensive coverage for future ownership changes** — if anyone later chowns the repo to the service user (e.g., a manual operator action), deploy's CI runs would start failing.

Both users get the exception for robustness:

```bash
sudo -u deploy git config --global --add safe.directory /opt/{project}/{project}
sudo -u {project} git config --global --add safe.directory /opt/{project}/{project}
```

`bootstrap-project.sh` runs both in step 7. Without them, manual or post-rechown git operations fail with the dubious-ownership error.

### Why we don't use `caddy validate`

`bootstrap-project.sh` step 11 uses `systemctl reload caddy` instead of `caddy validate`. Reason: `caddy validate` from a plain shell can't see the systemd-injected env vars (like `CLOUDFLARE_API_TOKEN`), so it fails on TLS provisioning even when the running daemon is fine. `systemctl reload caddy` validates internally with the daemon's environment — same check, correct env.

## GitHub Actions workflow

Canonical `.github/workflows/deploy.yml` lives in the `project-scaffold` skill's templates. Triggered on push to `main`. Uses repository secrets:

- `SSH_PRIVATE_KEY` — the `deploy` user's SSH key, added to the server's `/home/deploy/.ssh/authorized_keys`
- `SSH_HOST` — the server's public IP or hostname

The workflow's only deploy step is `ssh deploy@$SSH_HOST "cd /opt/{project}/{project} && bash deploy/run.sh"`. All deploy logic lives in `deploy/run.sh`, which is in the project's repo and editable per project.

Never put SSH keys in `.env.example` or anywhere in the repo. Set them in GitHub's repo settings (Settings → Secrets and variables → Actions).

## Sudoers entries for `deploy`

Installed by `init-server.sh` to `/etc/sudoers.d/aqnas-studio-deploy` (mode 440):

```
deploy ALL=(root) NOPASSWD: /bin/systemctl restart *
deploy ALL=(root) NOPASSWD: /bin/systemctl reload caddy
deploy ALL=(root) NOPASSWD: /bin/systemctl status *
deploy ALL=(root) NOPASSWD: /bin/cp /opt/*/?*/infra/*.caddy /etc/caddy/conf.d/*.caddy
```

The wildcards cover all current and future projects without per-project entries:

- First three lines: systemctl restart/reload/status for any service
- Fourth line: cp any project's `infra/{project}.caddy` to `/etc/caddy/conf.d/{project}.caddy`. The path glob `/opt/*/?*/infra/*.caddy` matches `/opt/{project}/{project}/infra/{project}.caddy` for arbitrary project names. The `?*` after the second `/` ensures the project name isn't empty (a literal `*` alone would match `/opt//foo` which we don't want)

This is the smallest privilege set that lets the CI/CD flow work. Never grant `deploy` full sudo.

If you have older per-project `cp` entries (e.g. `deploy ALL=(root) NOPASSWD: /bin/cp /opt/aqnas-xyz/aqnas-xyz/infra/aqnas-xyz.caddy /etc/caddy/conf.d/aqnas-xyz.caddy`), the wildcard supersedes them. Safe to remove them after the wildcard is installed.

If you're setting up a server manually and need to install this without `init-server.sh`, use `sudo visudo -f /etc/sudoers.d/aqnas-studio-deploy` — visudo validates the syntax before saving, and a syntax error in `/etc/sudoers.d/*` can lock out sudo entirely.

## Zero-downtime considerations

`systemctl restart {project}` is **not** truly zero-downtime — there's a brief window (usually under a second) where the service is down. For AQNAS's current traffic, this is fine.

For actual zero-downtime, the paths are:

- Run two workers behind Caddy's load balancer, rolling-restart them
- Use `systemctl reload` if the service supports SIGHUP-reload

Don't invest in zero-downtime until traffic justifies it. The current `restart` approach is simple and correct.

## Health check

Every project must expose `GET /health` returning 200 OK. No auth. No database calls. Just `return "ok"`. The deploy script polls this; monitoring tools (future) will too.

More involved health checks (DB reachable, disk free, etc.) go at `/health/detailed` with auth. Keep `/health` dumb.

## Rollback

GitHub doesn't auto-rollback. When a deploy fails or production misbehaves:

```bash
# SSH to server as deploy user
ssh deploy@{server}
cd /opt/{project}/{project}

# Check current state
git log --oneline -5

# Roll back (use sg for consistent group ownership, same pattern as deploy/run.sh)
sg "{project}" -c "git fetch origin main && git reset --hard <prev-commit-sha>"
UV_CACHE_DIR=/opt/{project}/.uv-cache /usr/local/bin/uv sync --frozen --no-dev
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
- Never skips the health check in `deploy/run.sh`. A deploy that lies about success is worse than a deploy that fails.

## Failure modes

- **Health check times out.** Service didn't start or isn't binding the port. `sudo journalctl -u {project} -n 100` on the server.
- **`git fetch` or `git reset --hard` fails in CI with "dubious ownership".** Missing safe.directory exception for deploy. Fix with `sudo -u deploy git config --global --add safe.directory /opt/{project}/{project}`. `bootstrap-project.sh` does this in step 7; if you bootstrapped manually or with an older version of the script, run it now.
- **`uv sync` fails.** `pyproject.toml` change that needs a system dep, or `uv.lock` is out of date. Run locally first and commit the updated lock.
- **Build step fails with `EACCES: permission denied` on a gitignored output file.** Common with Tailwind's `app/static/style.css` or other build artifacts. The file persists from a previous deploy (gitignored, so `git reset --hard` doesn't touch it) and was created with mode 644 by a different owner or umask, so the current `deploy` user can't overwrite it even though it's in the project group. Immediate fix: `ssh aqnas-prod "sudo rm -f /opt/{project}/{project}/<path-to-stale-file>"` and retry the deploy. Permanent fix: ensure `umask 002` is set near the top of `deploy/run.sh` (the canonical `project-scaffold` template includes it) so files created during deploys are group-writable (664) instead of owner-only (644).
- **`systemctl restart` fails with "password required" in CI.** The `deploy` user's sudoers entry is missing. Check `/etc/sudoers.d/aqnas-studio-deploy` (the file `init-server.sh` installs).
- **Caddy `cp` step in `deploy/run.sh` fails with permission error.** The sudoers `cp` wildcard isn't installed or your project's path doesn't match. The wildcard pattern is `/opt/*/?*/infra/*.caddy /etc/caddy/conf.d/*.caddy` — verify your project's path matches. Older per-project `cp` entries also work but the wildcard is preferred.
- **Caddy reload fails after a `.caddy` config change.** `systemctl reload caddy` validates the new config internally before applying it — if reload fails, the new config didn't pass validation. Check `journalctl -u caddy -n 30` for the specific error. Common cause: TLS DNS challenge failure (Cloudflare token missing or wrong permissions). The previous config keeps running, so existing sites stay up.
- **Deploy succeeds but the site returns 502.** Upstream service isn't listening. Check `systemctl status {project}` — service may be restart-looping.
- **Two deploys race.** GitHub Actions serializes per-workflow by default; don't change concurrency settings without a reason.
