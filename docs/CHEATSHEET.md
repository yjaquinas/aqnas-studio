# AQNAS Studio — Cheat Sheet

Quick reference for the three project lifecycle workflows.

This doc complements the [studio README](../README.md), which covers Claude-Code-inside-the-project workflows (slash commands, meetings, the 4-step development loop). This doc covers what surrounds that: scaffolding, server bootstrap, deploy, status queries, and converting existing projects to studio convention.

## Contents

1. [Start a new project](#1-start-a-new-project)
2. [Continue developing an existing project](#2-continue-developing-an-existing-project)
3. [Convert an existing project to AQNAS Studio convention](#3-convert-an-existing-project-to-aqnas-studio-convention)

---

## 1. Start a new project

```sh
# ─── LOCAL ─────────────────────────────────────────────────────────
# In your terminal, anywhere
/start-new-app <project-name> <project-domain> [--no-web | --no-mobile]
#   e.g. /start-new-app hello-aqnas hello-aqnas.aqnas.xyz --no-mobile

# What this does (automatically):
#   - Allocates a port via aqnas-studio/infrastructure/server/ports.conf
#   - Creates ~/projects/<project>/ with full scaffold (app/, deploy/run.sh,
#     infra/{project}.caddy + .service, CLAUDE.md, DEVELOPER_GUIDE.md, run.sh,
#     .github/workflows/deploy.yml, .claude/, etc.)
#   - Substitutes {project-name}, {project-domain}, {port}, {pwd} everywhere
#   - Generates MANUAL-TASKS.md with the remaining steps

# Verify locally
cd ~/projects/<project>
./run.sh                                    # uvicorn :8000 + Tailwind watcher
curl -sS http://127.0.0.1:8000/health       # expect: ok

# ─── GITHUB ────────────────────────────────────────────────────────
# Create the repo (empty, private) at github.com/yjaquinas/<project>

git init && git add . && git commit -m "chore: scaffold"
git remote add origin git@github.com:yjaquinas/<project>.git
git push -u origin main

# Add repo secrets at github.com/yjaquinas/<project>/settings/secrets/actions:
#   SSH_HOST          (Oracle IP)
#   SSH_PRIVATE_KEY   (paste deploy user's id_ed25519 contents)

# ─── SERVER (one-time per project) ─────────────────────────────────
ssh aqnas-prod
cd ~/aqnas-studio && git pull
sudo ./infrastructure/server/scripts/bootstrap-project.sh <project> <port> <project-domain>
#   e.g. sudo ./.../bootstrap-project.sh hello-aqnas 8010 hello-aqnas.aqnas.xyz

# 13-step bootstrap runs. When it finishes, the script prints "DO THESE NEXT":
sudo -u <project> editor /opt/<project>/.env       # populate secrets
# Add DNS A record at Cloudflare → <project-domain> → Oracle IP
sudo systemctl start <project>
curl -fsSL https://<project-domain>/health         # expect: ok

# ─── FIRST CI DEPLOY ───────────────────────────────────────────────
# From local
git commit --allow-empty -m "ci: first deploy" && git push
# Watch the Actions tab on GitHub
```

---

## 2. Continue developing an existing project

```sh
# ─── LOCAL DEV LOOP ────────────────────────────────────────────────
cd ~/projects/<project>
git pull
uv sync                                    # if pyproject.toml changed
./run.sh                                   # local dev server :8000

# Make changes. Test locally.
git add . && git commit -m "feat: ..."
git push origin main                       # auto-triggers deploy

# ─── WATCH THE DEPLOY ──────────────────────────────────────────────
# Either:
#   GitHub → Actions tab
#   ./scripts/studio-status                # see all projects' state at a glance

# ─── DEBUG A FAILED DEPLOY ─────────────────────────────────────────
ssh aqnas-prod
sudo journalctl -u <project> -n 100        # app logs
sudo systemctl status <project>            # service state
tail -f /var/log/caddy/<project>-access.log  # request logs

# ─── ROLLBACK ──────────────────────────────────────────────────────
# Locally
git revert <bad-sha>
git push origin main                       # deploys the revert cleanly

# Or surgically on server (emergency only)
ssh aqnas-prod
cd /opt/<project>/<project>
sg "<project>" -c "git fetch origin main && git reset --hard <prev-sha>"
sudo systemctl restart <project>

# ─── CHECK THE WHOLE STUDIO ────────────────────────────────────────
./scripts/studio-status                    # from local studio root
# Surfaces: which services up, /health status, Caddy config drift,
# port listener alignment, last commit per project

# ─── MODIFY DEPLOY/INFRA ───────────────────────────────────────────
# Edit deploy/run.sh, infra/<project>.caddy, infra/<project>.service in repo
# Push → deploy/run.sh auto-syncs Caddy if config changed (sudo cp + reload)
# Systemd unit changes need a manual reload (rare):
ssh aqnas-prod "sudo systemctl daemon-reload && sudo systemctl restart <project>"
```

**Key locations to remember:**

| Where | What |
|---|---|
| `deploy/run.sh` | The deploy script (the only thing in `deploy/`) |
| `infra/<project>.caddy` | Caddy reverse proxy config |
| `infra/<project>.service` | systemd unit |
| `CLAUDE.md` (root) | Project context for Claude Code |
| `DEVELOPER_GUIDE.md` | Human reference doc |
| `/opt/<project>/.env` (server) | Secrets — edit with `sudo -u <project> editor` |
| `/opt/<project>/data/` (server) | SQLite + uploads, gets backed up |

---

## 3. Convert an existing project to AQNAS Studio convention

There's no `/convert-to-aqnas-studio` command — the work is manual but mechanical and well-defined. The roadmap below assumes a vanilla FastAPI + uv project; adjust for your reality.

### Step 1 — scaffold a sibling project, then merge

```sh
# Easiest path: scaffold a reference, then port your app code into it.
cd ~/projects
/start-new-app <project-name> <project-domain>
# Now you have ~/projects/<project>/ — the canonical scaffold

# Copy your existing app code into the new tree
cp -r ~/projects/<old-project>/app/* ~/projects/<project>/app/
cp ~/projects/<old-project>/pyproject.toml ~/projects/<project>/  # if more advanced

# Verify locally before going further
cd ~/projects/<project>
./run.sh
```

### Step 2 — adapt the scaffold's defaults to your code

| Convention | Default | If yours differs |
|---|---|---|
| Tailwind input path | `app/static/src/input.css` | Edit `deploy/run.sh` + `run.sh` `TAILWIND_INPUT` var, or move your file |
| Tailwind output path | `app/static/style.css` | Same |
| Health endpoint | `/health` returning 200 | Add the route if missing (`@app.get("/health"): return {"status": "ok"}`) |
| App factory | `app.main:app` | Edit `run.sh` and `infra/<project>.service` if your import path differs |
| Database location | `/opt/<project>/data/app.db` (prod) | Set `DATABASE_URL` in `.env`; default falls back to `./app.db` locally |

### Step 3 — replace project-specific files with templated versions

Fill in the placeholders in:
- `CLAUDE.md` (root) — describe what your project does, key constraints
- `DEVELOPER_GUIDE.md` — architecture diagram, server users (uses studio defaults), routes table, schema
- `infra/<project>.caddy` — security headers, CSP, your domain
- `infra/<project>.service` — systemd unit (defaults are usually fine; verify `WorkingDirectory`, `ExecStart`)

### Step 4 — wire up CI/CD

```sh
# Repo on GitHub:
#   1. Settings → Secrets → Actions
#   2. Add SSH_HOST and SSH_PRIVATE_KEY (deploy user's private key)
#   3. The workflow .github/workflows/deploy.yml is already in place
```

### Step 5 — server-side bootstrap

Only if the project isn't already on the server. If it is already running (migrating an existing deployment), skip `bootstrap-project.sh` and follow Step 5b instead.

**Step 5a — fresh project not yet on server:**

```sh
ssh aqnas-prod
cd ~/aqnas-studio && git pull
sudo ./infrastructure/server/scripts/bootstrap-project.sh <project> <port> <project-domain>
# Follow MANUAL-TASKS (edit .env, add DNS, start service)
```

**Step 5b — project already running on server, just adopting studio convention:**

This is essentially what was done for aqnas-xyz and kumdo-exam. Manual steps because each existing project has its own quirks. Rough sequence:

```sh
# On the server
ssh aqnas-prod
cd /opt/<old-project>/

# 1. Ensure directory layout matches: /opt/<project>/<project>/ for repo,
#    /opt/<project>/{data,.uv-cache,.env} as siblings. Move/rename if needed.

# 2. Ensure user exists: <project> system user, deploy in its group
id <project> || sudo useradd --system --shell /usr/sbin/nologin \
    --home-dir /home/<project> --create-home <project>
sudo usermod -a -G <project> deploy

# 3. Ensure ownership + perms
sudo chown -R <project>:<project> /opt/<project>/
sudo chmod 2775 /opt/<project>/<project> /opt/<project>/.uv-cache

# 4. Add both safe.directory entries (CVE-2022-24765)
sudo -u deploy git config --global --add safe.directory /opt/<project>/<project>
sudo -u <project> git config --global --add safe.directory /opt/<project>/<project>

# 5. Move systemd unit and Caddy config into the new infra/ layout.
#    Push the studio-converted repo first, then on the server:
cd /opt/<project>/<project>
sg "<project>" -c "git fetch origin main && git reset --hard origin/main"
sudo cp infra/<project>.service /etc/systemd/system/<project>.service
sudo cp infra/<project>.caddy /etc/caddy/conf.d/<project>.caddy
sudo systemctl daemon-reload
sudo systemctl reload caddy
sudo systemctl restart <project>

# 6. Add to port registry if not there
echo "<project>=<port>" | sudo tee -a /etc/caddy/ports.conf

# 7. Verify (from local)
./scripts/studio-status                    # should show this project green
```

### Step 6 — first CI deploy of the converted project

```sh
git commit --allow-empty -m "ci: studio convention" && git push
# If anything fails, ./scripts/studio-status surfaces what's drifting
```

### Notes on the migration path

- The full conversion is mostly **renames + path adjustments**. Logic doesn't change.
- The hardest part is usually `infra/<project>.caddy` — security headers, CSP for your specific frontend, TLS DNS challenge config. Reference aqnas-xyz's `infra/aqnas-xyz.caddy` for a working example.
- Don't try to convert and deploy in the same commit. Get the convention right locally first (verify with `./run.sh`), then push, then bootstrap on the server.
- If something fails mid-convert, the project's previous `deploy.sh` is still a valid fallback while you migrate — they're not mutually exclusive.

---

## See also

- [README](../README.md) — Claude Code workflows, slash commands, the 4-step development loop
- [findings.md](findings.md) — Known issues, bugs, deferred work
- [`claude-config/skills/deploy-procedure/SKILL.md`](../claude-config/skills/deploy-procedure/SKILL.md) — Canonical deploy model: `deploy/run.sh`, `infra/` split, ownership, sudoers, rollback
- [`claude-config/skills/project-scaffold/SKILL.md`](../claude-config/skills/project-scaffold/SKILL.md) — Canonical project layout
- [`infrastructure/server/scripts/README.md`](../infrastructure/server/scripts/README.md) — Server-side scripts (bootstrap-project, init-server, studio-status)
