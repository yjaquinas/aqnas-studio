# AQNAS — studio config

One-person software studio orchestrating Claude Code agents to ship SaaS products and take on selective consulting work.

## Operating principle

Every decision evaluates against one-person scale. Features, tools, dependencies, and services earn their place by not adding ongoing operational or cognitive burden. When the answer is "we'll just maintain it," the answer is "we won't build it."

## How work flows

There are two main entry points: starting a brand-new project, and iterating on an existing one.

### Starting a brand-new project

```
mkdir ~/dev/my-project && cd ~/dev/my-project
claude
  ↓
/start-new-app [--no-web] [--no-mobile]
  → scaffolds cwd in place
  → reserves a port in $AQNAS_STUDIO_ROOT/infrastructure/server/ports.conf
  → git init + gitleaks pre-commit hook
  → uv sync, initial commit
  ↓
(see "Adding work to an existing project" below for what comes next)
```

### Adding work to an existing project

```
cd ~/dev/my-project
claude
  ↓
/run-meeting <topic>
  → MEETING-YYYY-MM-DD-{slug}/ with up to 3 files
  │   ├── 1-MANUAL-TASKS.md       (the CEO does these manually, in parallel)
  │   ├── 2-CLAUDE-UPDATES.md     (feeds the next step)
  │   └── 3-BUILD-PLAN.md         (feeds the step after)
  ↓
/update-project-claude {path to 2-CLAUDE-UPDATES.md}
  → applies agent/skill/rule changes into the current project's .claude/
  ↓
/exit  →  claude --continue
  → session reloads so new config is picked up before the build runs
  ↓
/execute-plan {path to 3-BUILD-PLAN.md}
  → Task Force agents build, tests gate each task
  ↓
/commit-git
  → gitleaks scan (explicit, plus the pre-commit hook as defense in depth)
  → conventional commit message
```

Not every meeting produces all three files — only what the meeting's output actually warrants. For small changes that don't need a meeting, just talk to Claude normally and `/commit-git` when done.

Supports `/run-meeting mode-auto-on <topic>` for delegated deliberation — agents iterate up to 4 rounds on their own, pausing only for genuine CEO preference calls.

## The six C-level agents

Convened by `/run-meeting` based on topic relevance — not every meeting needs all six:

- **product-strategist** — user/market lens; pushes back on feature creep
- **technical-architect** — schemas, boundaries, feasibility
- **devops-engineer** — deploy, infra, cost, reliability
- **design-lead** — IA, components, accessibility
- **security-legal** — privacy, auth, licensing
- **agent-architect** — utility; only for writing or revising `.claude/` config

Each agent lives in `agents/` and has a ≤100-line system prompt. **Subagents do not inherit this CLAUDE.md**, so each agent carries the studio context it specifically needs.

## Default tech stack

Applies to all AQNAS projects unless a project explicitly overrides:

- **Python 3.12**, `uv` for dependency management
- **FastAPI** + uvicorn (2 workers on the 2-CPU production host — tune per host)
- **Jinja2** templates
- **HTMX v2** for web; **Hyperview/HXML** for mobile (server-driven UI)
- **Tailwind v4**; Alpine.js only as a deliberate fallback
- **SQLite** with WAL mode, raw SQL (no ORM)
- **Caddy v2** with Cloudflare DNS challenge for TLS
- **systemd** on Ubuntu 24.04
- **GitHub Actions** for CI/CD (SSH deploy, uv sync, restart, health check)
- **ruff** for lint + format

Details live in skills under `skills/`. See `skills/README.md` for the commands-vs-knowledge index.

## Infrastructure

Production host configs (per-project `.caddy`, `.service`, shared `ports.conf`, scripts) live in `$AQNAS_STUDIO_ROOT/infrastructure/server/` (default: `~/aqnas-studio/infrastructure/server/`). That directory is the source of truth; server copies at `/etc/caddy/` and `/etc/systemd/system/` are derivatives — edit here first, sync to the host.

**Path convention:** Every skill that references the studio repo uses `$AQNAS_STUDIO_ROOT` with `~/aqnas-studio` as the fallback default. Users who clone elsewhere set `AQNAS_STUDIO_ROOT` via `setup.sh` or manually in their shell rc.

Provider-agnostic — the same configs work on Oracle Cloud, AWS, GCP, bare metal, or a Raspberry Pi. Ports allocate from `8000–8099` via `skills/port-registry/scripts/allocate-port.sh`.

## Ownership model on the production host

- **Service user** (`{project}`, created `--system`) owns `/opt/{project}/` at rest and runs the uvicorn process.
- **Deploy user** is the CI/CD actor only — member of each project's group for write access (git pull, uv sync), not an owner.
- `.env` is mode 600 owned by the service user. The deploy user cannot read secrets.
- `.uv-cache/` is project-local at `/opt/{project}/.uv-cache/`, mode 2775 setgid — deploy writes during sync, service reads via `uv run`.

## Meeting outputs

- **Studio-scope meetings** land in `$AQNAS_STUDIO_ROOT/meetings/` (default `~/aqnas-studio/meetings/`) and are **gitignored** (studio strategy stays private).
- **Project-scope meetings** land in `{project}/meetings/` and are **committed** with the project repo (the project's own history).

## Brand voice is project-scope, not studio-scope

AQNAS-the-studio is brand-agnostic by design. Each project under the studio defines its own brand voice, palette, typography, and copy conventions in its own `.claude/skills/`. Do not apply the `aqnas.xyz`-the-homepage brand voice to other projects — they have their own.

## Secret hygiene

- gitleaks runs as a pre-commit hook in every project AND explicitly inside `/commit-git`
- `.env` is always `chmod 600`, owned by the service user, never in any repo
- The production host IP never appears in any repo
- Cloudflare and GitHub tokens are set once per environment (Caddy's systemd `EnvironmentFile` for DNS challenge; GitHub repo secrets for Actions)
- **Before sharing logs or diagnostic output** (with Claude, in chat, in screenshots, in support tickets): redact secrets, tokens, and IPs first. See the `secret-hygiene` skill for redaction patterns and the emergency procedure if a secret leaks.

## Pointers

- `skills/README.md` — skills index (commands vs knowledge)
- `agents/` — the six C-level agents
- `$AQNAS_STUDIO_ROOT/infrastructure/server/` — production host configs
- `$AQNAS_STUDIO_ROOT/infrastructure/server/ports.conf` — port registry
- `$AQNAS_STUDIO_ROOT/README.md` — setup and multi-machine sync
