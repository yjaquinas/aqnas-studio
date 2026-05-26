# infrastructure/server/scripts/

Server-side automation for AQNAS project hosting. Run on the production server, not on dev machines.

## Three scripts, three layers

These scripts split server work into three layers by frequency:

### Layer 2 — `init-server.sh` (once per server)

Run once when provisioning a new server. Sets up the server's foundation:

- Verifies prerequisites are installed (`uv`, `gitleaks`, `caddy`, `git`)
- Verifies the `deploy` user exists with sane configuration
- Installs `/etc/sudoers.d/aqnas-studio-deploy` (passwordless sudo for `deploy` on `systemctl restart/reload/status`)
- Confirms Caddy's Cloudflare API token is configured (for TLS DNS challenge)
- Creates `/etc/caddy/ports.conf` (server-side port registry)

Idempotent — safe to re-run. Won't recreate or modify existing setup.

```sh
sudo ./infrastructure/server/scripts/init-server.sh
sudo ./infrastructure/server/scripts/init-server.sh --dry-run   # preview only
```

### Layer 1 — `bootstrap-project.sh` (once per project)

Run once when adding a new project to an already-initialized server. Creates the project's full server-side footprint.

NOT idempotent — refuses if the project already exists. This is deliberate; bootstrapping over an existing project would silently overwrite state.

```sh
sudo ./infrastructure/server/scripts/bootstrap-project.sh <project-name> <port> <project-domain>
sudo ./infrastructure/server/scripts/bootstrap-project.sh hello-aqnas 8010 hello-aqnas.aqnas.xyz
sudo ./infrastructure/server/scripts/bootstrap-project.sh hello-aqnas 8010 hello-aqnas.aqnas.xyz --dry-run
```

What it does (the 13 steps from `deploy-procedure`):

1. Creates the system user `{project}`
2. Adds `deploy` to the `{project}` group
3. Creates `/opt/{project}/{{project},data,.uv-cache}`
4. Sets ownership to `{project}:{project}` throughout
5. Sets group-write + setgid on shared directories
6. Clones the repo as `deploy`, then chowns to the service user
7. Adds `git safe.directory` exception for deploy (prevents "dubious ownership")
8. Generates a stub `.env` (operator edits with real values before starting)
9. Installs the systemd unit
10. Installs the Caddy config
11. Validates Caddy via `systemctl reload`
12. Adds the port to `/etc/caddy/ports.conf`
13. Runs first `uv sync` as deploy

What the script does NOT do:

- Add the DNS A record in Cloudflare (manual step in the dashboard)
- Start the service (operator should verify `.env` is populated first)
- Trigger CI/CD (operator pushes a commit to do that)

### Layer 0 — `studio-status` (any time, read-only, run from local)

A one-shot status query for all projects on the server. Reports per-project: systemd state + uptime, `/health` endpoint result, Caddy config drift between repo's `infra/` and `/etc/caddy/conf.d/`, last git commit. Also reports overall Caddy daemon status and port-registry-vs-listener alignment.

Read-only — no state modified. Run from your **local machine** via the wrapper at `scripts/studio-status`. The wrapper streams the server-side script over SSH and executes it remotely:

```sh
cd ~/aqnas-studio
./scripts/studio-status
```

The server doesn't need a copy of aqnas-studio for this. The canonical script lives at `infrastructure/server/scripts/studio-status` in this repo; the wrapper streams it each invocation. No server-side `git pull` step, no drift risk from a server-side clone (see Bug 21 in `docs/findings.md` for context).

Suggested alias in your **local** shell rc:

```sh
alias studio-status='~/aqnas-studio/scripts/studio-status'
```

Exit code is always 0 — `studio-status` is observational, not a CI gate. Grep the output for `⚠` or `✗` to detect issues programmatically:

```sh
studio-status | grep -E '(⚠|✗)' && echo "issues found" || echo "all green"
```

The server-side script honors `FORCE_COLOR=1` so colors survive the SSH pipe (the wrapper sets this automatically).

## Typical first-deploy workflow

Initial setup of a new server:

```sh
ssh aqnas-prod
git clone git@github.com:yjaquinas/aqnas-studio.git ~/aqnas-studio
cd ~/aqnas-studio
sudo ./infrastructure/server/scripts/init-server.sh
```

Adding a project to that server:

```sh
ssh aqnas-prod
cd ~/aqnas-studio
git pull   # ensure scripts are current
sudo ./infrastructure/server/scripts/bootstrap-project.sh hello-aqnas 8010 hello-aqnas.aqnas.xyz
```

After bootstrap, the script prints a "DO THESE NEXT (manual)" section covering: editing `.env`, adding DNS, starting the service, verifying public URL, and triggering the first CI deploy.

## Recovering from a failed bootstrap

If `bootstrap-project.sh` fails partway through, the project is in a partial state. The script refuses to re-run because the user/dir already exist. To clean up before retrying:

```sh
# Stop and disable any partially-installed service
sudo systemctl stop {project} 2>/dev/null
sudo systemctl disable {project} 2>/dev/null

# Remove systemd unit
sudo rm /etc/systemd/system/{project}.service
sudo systemctl daemon-reload

# Remove Caddy config and reload
sudo rm /etc/caddy/conf.d/{project}.caddy
sudo systemctl reload caddy

# Remove port registry entry
sudo sed -i "/^{project} = /d" /etc/caddy/ports.conf

# Remove the project tree
sudo rm -rf /opt/{project}

# Remove the system user
sudo deluser {project}

# Now safe to re-run bootstrap-project.sh
```

## Why these scripts and not just `deploy-procedure/SKILL.md`?

The skill body documents the *what* and *why* — what each step does, why we own things this way, what the failure modes are. That's reference material for understanding.

The scripts encode the *how* — the exact sequence of commands, with validation, error handling, and dry-run support. That's automation for repetition.

You read the skill once to understand the model. You run the scripts every time you provision a server or add a project. Both are sources of truth for their own concerns.

If the skill says one thing and the script does another, the script is wrong (or the skill is out of date). They should agree.

## See also

- `claude-config/skills/deploy-procedure/SKILL.md` — the canonical reference for the deploy model and ownership conventions
- `claude-config/skills/systemd-service/SKILL.md` — systemd unit conventions
- `claude-config/skills/caddy-config/SKILL.md` — Caddy config conventions
- `claude-config/skills/port-registry/SKILL.md` — port allocation conventions
