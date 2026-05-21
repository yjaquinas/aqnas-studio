# {project-name} — Claude instructions

## What this project is

{One or two sentences describing what this project does and why it exists.
Replace this paragraph when scaffolding.}

Stack: FastAPI + uv + Uvicorn. Optional Tailwind CSS v4 + Alpine.js + HTMX
(web), Hyperview/HXML (mobile), SQLite.
Hosting: Ubuntu 24.04 (production via Caddy + systemd).
Studio context: see `~/.claude/CLAUDE.md` for studio-wide conventions and brand.

## Current state

- Live at: https://{project-domain}
- Local dev: `./run.sh` (port 8000)
- Repo: github.com/yjaquinas/{project-name}
- Production path: `/opt/{project-name}/{project-name}/` on `aqnas-prod`
- Production port: {port}

## Site structure

{If this is a website, describe the public-facing structure: pages, sections,
key flows. If not a website (API-only, mobile-only), remove this section.}

## Key constraints

{Project-specific non-negotiables — brand assets that can't be modified,
naming conventions that are externally committed, integrations that are
load-bearing. The place to bake in "do not change without explicit decision."}

- {placeholder}
- {placeholder}

## Deployment

Push to `main` triggers `.github/workflows/deploy.yml`, which SSHes into
the production host and runs `deploy/run.sh` in this repo. See the studio's
`deploy-procedure` skill for the full model.

`deploy/run.sh` handles: git sync (`sg + fetch + reset --hard`),
`uv sync --frozen --no-dev`, optional Tailwind build, conditional Caddy
config sync from `infra/{project-name}.caddy`, `systemctl restart`, and
health check via `GET /health`.

GitHub secrets:
- `SSH_HOST` — production host IP or DNS
- `SSH_PRIVATE_KEY` — deploy user's SSH private key

## Development workflow

Local: `./run.sh` (starts uvicorn with `--reload` and, if applicable,
the Tailwind watcher). URL: http://127.0.0.1:8000.

For per-project Claude Code rules and skills, see `.claude/` in this repo
(loaded automatically when Claude Code runs from the project root).

## Reference docs

- `DEVELOPER_GUIDE.md` — full developer reference (architecture, server users,
  deploy flow, database schema, monitoring, break-glass)
- `~/.claude/CLAUDE.md` — studio-wide context, brand, default tech stack
- `~/.claude/skills/` — studio skills (deploy-procedure, port-registry,
  systemd-service, caddy-config, secret-hygiene, etc.)
