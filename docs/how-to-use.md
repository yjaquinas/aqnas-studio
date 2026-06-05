# AQNAS Studio — How-To

Operational reference for the project lifecycle: daily development, deploy, debug, rollback, status queries, and converting existing projects to studio convention.

For your first project (zero to deployed), see [quickstart.md](quickstart.md).

For Claude-Code-inside-the-project workflows (the 4-step `meeting → update config → build → commit` loop and slash command reference), see the [studio README](../README.md).

## Contents

1. [Daily development on an existing project](#1-daily-development-on-an-existing-project)
2. [Convert an existing project to studio convention](#2-convert-an-existing-project-to-studio-convention)

---

## 1. Daily development on an existing project

```sh
# ─── DEV LOOP ──────────────────────────────────────────────────────
cd <project-dir>
git pull
uv sync                                    # if pyproject.toml changed
./run.sh                                   # local dev :8000 + Tailwind watcher

# Make changes, test locally
# Then either drive feature work through Claude Code:
claude
# Inside Claude Code:
/run-meeting <what you want to build>
/update-project-claude meetings/MEETING-*/2-CLAUDE-UPDATES.md
/exit                                      # restart so new agents/skills load
claude --continue
/execute-plan meetings/MEETING-*/3-BUILD-PLAN.md
/commit-git                                # safe, secret-scanned commit

# Or for small changes, just talk to Claude normally then:
/commit-git

git push origin main                       # triggers CI deploy
```

### Watch the deploy

```sh
# Either:
#   - GitHub → Actions tab (browser)
#   - ./scripts/studio-status   from the studio repo root (streams over SSH)
```

`studio-status` reports per project: systemd state + uptime, /health check, Caddy config drift between repo and live, last commit. Plus port-registry-vs-listener alignment.

### Debug a failed deploy

```sh
ssh aqnas-prod
sudo journalctl -u <project> -n 100             # app logs (last 100 lines)
sudo systemctl status <project>                 # service state
sudo tail -f /var/log/caddy/access.log          # request logs (path may vary by project)

# Common failure modes — see deploy-procedure SKILL for the full list:
#   - "dubious ownership" → safe.directory missing for deploy user
#   - "terminal required for password" → sudoers entry missing (run init-server.sh)
#   - Health check timeout → service didn't bind the port (check journalctl)
#   - Caddy reload fails → check journalctl -u caddy -n 30
```

### Rollback

```sh
# Normal path: revert locally, push
cd <project-dir>
git revert <bad-sha>
git push origin main                       # deploys the revert cleanly

# Emergency path: roll back on the server first (if production needs to recover fast)
ssh aqnas-prod
cd /opt/<project>/<project>
sg "<project>" -c "git fetch origin main && git reset --hard <prev-sha>"
UV_CACHE_DIR=/opt/<project>/.uv-cache /usr/local/bin/uv sync --frozen --no-dev
sudo systemctl restart <project>
curl -sSf https://<project-domain>/health  # verify

# Then push the revert locally so GitHub matches the server
git revert <bad-sha>
git push origin main
```

### Modify deploy or infra config

```sh
# Edit deploy/run.sh, infra/<project>.caddy, infra/<project>.service in repo
git add . && git commit -m "..." && git push origin main

# deploy/run.sh auto-syncs Caddy if infra/<project>.caddy changed
# (sudo cp + reload happens in step 4 of the deploy)

# systemd unit changes need a manual reload — rare but worth knowing:
ssh aqnas-prod "sudo systemctl daemon-reload && sudo systemctl restart <project>"
```

### Check the whole studio

```sh
cd ~/dev/aqnas-studio    # or wherever your studio repo lives
./scripts/studio-status
```

Surfaces all projects' state at once. Useful before a release, after server maintenance, or when something feels off.

### Key locations to remember

| Where                            | What                                                                        |
| -------------------------------- | --------------------------------------------------------------------------- |
| `deploy/run.sh`                  | Deploy entry point (called by GitHub Actions via SSH)                       |
| `infra/<project>.caddy`          | Caddy reverse-proxy config; deploy syncs to `/etc/caddy/conf.d/` if changed |
| `infra/<project>.service`        | systemd unit; installed during bootstrap                                    |
| `CLAUDE.md` (project root)       | Project-level Claude Code context                                           |
| `DEVELOPER_GUIDE.md`             | Human reference doc                                                         |
| `MANUAL-TASKS.md`                | One-time setup checklist (gitignored, per-operator)                         |
| `/opt/<project>/.env` (server)   | Secrets — edit with `sudo -u <project> nano`                                |
| `/opt/<project>/data/` (server)  | SQLite + uploads, gets backed up                                            |
| `/etc/caddy/ports.conf` (server) | Port registry — source of truth for `studio-status`                         |

---

## 2. Convert an existing project to studio convention

There's no `/convert-existing-app` command — the work is manual but mechanical. Two scenarios:

- **The project isn't on the server yet** — use Path A: scaffold-then-merge.
- **The project is already running on the server** (this is what was done for aqnas-xyz and kumdo-exam) — use Path B: in-place migration.

### Path A — Not yet deployed

Easiest: scaffold a reference, then port your app code into it.

```sh
# Scaffold a fresh project alongside your old one
mkdir -p ~/dev/<project>
cd ~/dev/<project>
claude
/start-new-app
# (Confirm domain etc. as prompted)

# Port your app code into the new tree
cp -r ~/old-location/<old-project>/app/* ~/dev/<project>/app/
cp ~/old-location/<old-project>/pyproject.toml ~/dev/<project>/      # if more advanced

# Verify locally
./run.sh

# Adapt scaffold defaults to your code (see table below)

# Follow MANUAL-TASKS.md for the rest (GitHub, bootstrap, DNS, first deploy)
```

Defaults to adapt:

| Convention        | Default                             | If yours differs                                                              |
| ----------------- | ----------------------------------- | ----------------------------------------------------------------------------- |
| Tailwind input    | `app/static/src/input.css`          | Edit `TAILWIND_INPUT` in both `deploy/run.sh` and `run.sh`, or move your file |
| Tailwind output   | `app/static/style.css`              | Same — `TAILWIND_OUTPUT`                                                      |
| Health endpoint   | `GET /health` returns 200           | **Required** — add it: `@app.get("/health"): return {"status": "ok"}`         |
| App factory       | `app.main:app`                      | Edit `run.sh` and `infra/<project>.service` if your import path differs       |
| Database location | `/opt/<project>/data/app.db` (prod) | Set `DATABASE_URL` in `.env`; default falls back to `./app.db` locally        |

### Path B — Already deployed (in-place migration)

This is what was done for aqnas-xyz and kumdo-exam during the May 2026 migration. Manual because each existing project has its own quirks. Rough sequence:

```sh
# ─── LOCAL: bring the repo into studio convention ──────────────────
cd <project-dir>

# 1. Reorganize files
mkdir -p deploy infra
git mv deploy.sh deploy/run.sh                      # if you had a deploy.sh
git mv <old-caddy-path> infra/<project>.caddy
git mv <old-systemd-path> infra/<project>.service

# 2. Rewrite deploy/run.sh to canonical pattern
#    Reference: claude-config/skills/project-scaffold/templates/deploy/run.sh
#    Substitute {project-name} and {port} placeholders for your values

# 3. Replace .github/workflows/deploy.yml with the canonical thin SSH shell
#    (the workflow's only step should be:
#     ssh deploy@$SSH_HOST "cd /opt/<project>/<project> && bash deploy/run.sh")

# 4. Update GitHub secrets if migrating from older names:
#    SERVER_HOST → SSH_HOST
#    DEPLOY_KEY → SSH_PRIVATE_KEY

# 5. Add /health endpoint to your app if missing

# 6. Verify locally
./run.sh
curl -sS http://127.0.0.1:8000/health    # expect: ok

# 7. Commit and push
git add . && git commit -m "chore: adopt studio convention" && git push

# ─── SERVER: reconcile state with new convention ───────────────────
ssh aqnas-prod

# 1. Ensure the on-server layout matches: /opt/<project>/<project>/ (repo subdir)
#    with /opt/<project>/{data,.uv-cache,.env} as siblings. Move/rename if needed.

# 2. Ensure the system user exists and deploy is in its group
sudo useradd --system --shell /usr/sbin/nologin \
    --home-dir /home/<project> --create-home <project>     # if not exists
sudo usermod -a -G <project> deploy

# 3. Set ownership + perms
sudo chown -R <project>:<project> /opt/<project>/
sudo chmod 2775 /opt/<project>/<project> /opt/<project>/.uv-cache

# 4. Add safe.directory entries for both users (CVE-2022-24765)
sudo -u deploy git config --global --add safe.directory /opt/<project>/<project>
sudo -u <project> git config --global --add safe.directory /opt/<project>/<project>

# 5. Pull the studio-converted repo into place and install configs
cd /opt/<project>/<project>
sg "<project>" -c "git fetch origin main && git reset --hard origin/main"
sudo cp infra/<project>.service /etc/systemd/system/<project>.service
sudo cp infra/<project>.caddy /etc/caddy/conf.d/<project>.caddy
sudo systemctl daemon-reload
sudo systemctl reload caddy
sudo systemctl restart <project>

# 6. Add to /etc/caddy/ports.conf if not there
echo "<project>=<port>" | sudo tee -a /etc/caddy/ports.conf

# 7. Verify from local
cd ~/dev/aqnas-studio
./scripts/studio-status     # this project should now show green
```

### Notes on migration

- The conversion is mostly **renames + path adjustments**. Logic doesn't change.
- The trickiest file is usually `infra/<project>.caddy` — security headers, CSP for your frontend, TLS DNS challenge config. Reference aqnas-xyz's `infra/aqnas-xyz.caddy` for a working example.
- Don't try to convert and deploy in the same commit. Verify locally first (`./run.sh`), then push, then reconcile the server.
- If something fails mid-convert, your old `deploy.sh` is still valid as a fallback while you migrate.
- Some projects may legitimately diverge from studio convention. kumdo-exam keeps its Caddy config as "live is source of truth" because Cloudflare IP ranges drift — see `docs/findings.md` Bug 22 for the precedent.

---

## See also

- [quickstart.md](quickstart.md) — Your first project, zero to deployed
- [README](../README.md) — Setup, the 4-step development loop, slash command reference
- [findings.md](findings.md) — Known issues, decisions, deferred work, divergences
- [`claude-config/skills/deploy-procedure/SKILL.md`](../claude-config/skills/deploy-procedure/SKILL.md) — Authoritative deploy model: `deploy/run.sh`, `infra/` split, ownership, sudoers, rollback
- [`claude-config/skills/project-scaffold/SKILL.md`](../claude-config/skills/project-scaffold/SKILL.md) — Canonical project layout
- [`claude-config/skills/start-new-app/SKILL.md`](../claude-config/skills/start-new-app/SKILL.md) — `/start-new-app` invocation, preflight checks, cwd cases
- [`infrastructure/server/scripts/README.md`](../infrastructure/server/scripts/README.md) — Server-side scripts (bootstrap-project, init-server, studio-status)
