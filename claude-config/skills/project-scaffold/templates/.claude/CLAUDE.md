# {Project Display Name}

{One-line description — what this project does, for whom.}

Part of the [AQNAS](https://aqnas.xyz) studio. Studio-scope conventions live in `~/.claude/`, which is symlinked to the `claude-config/` folder inside the studio repo (at `$AQNAS_STUDIO_ROOT/claude-config/`, default `~/aqnas-studio/claude-config/`). This file and the files in `.claude/` are project-scope — they override or extend the studio defaults for this project specifically.

## Stack

Inherits the AQNAS defaults from studio-scope: Python 3.12 + uv, FastAPI, HTMX v2 (web), Hyperview/HXML (mobile), SQLite, Tailwind v4, Caddy, systemd. See `~/.claude/CLAUDE.md` for the full list and reasoning.

Project-specific deviations:

_(List any stack choices that differ from studio defaults. If none, delete this section.)_

## Domain

_(2–4 sentences on the problem this project solves and the user it serves. This is the grounding context for every agent, every meeting, every piece of work.)_

## Agents

Twelve Task Force agents live in `.claude/agents/` — they do the building work (as opposed to the C-level agents at studio scope, who deliberate).

_(List the project's TF agent roster here as it's populated — which agents are active, what each owns.)_

## Skills

Seven project-scope skills live in `.claude/skills/`. Two are commands (`fix-issue`, `refactor`); five are knowledge skills encoding project-specific conventions (color system, typography, component patterns, data model, copy patterns).

See `.claude/skills/README.md` for the full index once populated.

## Rules

Path-scoped and repo-wide rules live in `.claude/rules/`:

- `python-backend.md` — Python conventions (loads when editing `app/**`)
- `web-templates.md` — HTMX + Tailwind conventions (loads when editing `templates/web/**`)
- `mobile-templates.md` — Hyperview conventions (loads when editing `templates/mobile/**`)
- `tests.md` — pytest + Playwright conventions (loads when editing `tests/**`)
- `repo-wide.md` — always-loaded: secret hygiene, git hygiene, destructive-action caution

## Deploy

- **Domain:** {project-domain}
- **Port:** {port}
- **Production path:** `/opt/{project}/`

See `deploy/` for this project's systemd unit, Caddy config, and bootstrap script. See the `deploy-procedure` skill at studio scope for the full flow.

## Meeting history

Past decisions live in `meetings/`. Each `MEETING-YYYY-MM-DD-{slug}/` captures the deliberation that produced whatever change followed.
