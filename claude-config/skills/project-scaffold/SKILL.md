---
name: project-scaffold
description: Defines the canonical AQNAS project repository structure and the contents of each boilerplate file. The repo layout puts templates and static assets inside the app module (app/templates/web/ for HTMX, app/templates/mobile/ for Hyperview, app/templates/components/ for shared fragments, app/static/ for CSS/JS/images). Other top-level dirs are mobile-client/ (React Native/Expo thin shell, only with --mobile), tests/ (pytest), deploy/ (contains only run.sh — the deploy entry point called by GitHub Actions), infra/ ({project}.caddy + {project}.service + optional per-project operational scripts like backup.sh, harden.sh), meetings/ (project-scope, tracked in git), .github/workflows/deploy.yml (GitHub Actions deploy as thin SSH shell), .claude/ (agents, skills, rules, project-level CLAUDE.md). Root files: CLAUDE.md (project Claude Code context), DEVELOPER_GUIDE.md (human-readable reference), run.sh (local dev runner), .env.example, .gitignore, pyproject.toml, uv.lock, README.md. On the production host, the repo clones into /opt/{project}/{project}/ (project-named subdirectory of the project user's tree) with /opt/{project}/data/, /opt/{project}/.uv-cache/, and /opt/{project}/.env as siblings. Use when scaffolding a new project (referenced by start-new-app), adding a missing directory to an existing project, deciding where a new file should live, or when the user asks about project structure, directory layout, deploy/ vs infra/ split, what boilerplate to include, or "where does X go?". Contains templates/ with ready-to-copy files for main.py, pyproject.toml, deploy.yml, README.md, CLAUDE.md, DEVELOPER_GUIDE.md, run.sh, deploy/run.sh, plus the project-scope .claude/ skeleton.
---

# project-scaffold

Canonical AQNAS project layout.

## Full tree

```
{project}/
├── app/
│   ├── __init__.py
│   ├── main.py                  # FastAPI app + Jinja2 setup
│   ├── routes/
│   │   ├── __init__.py
│   │   ├── web.py               # HTMX routes (HTML)
│   │   ├── mobile.py            # Hyperview routes (HXML) — /m/ prefix  (--mobile)
│   │   └── api.py               # webhook/integrations (non-hypermedia)
│   ├── models/
│   │   ├── __init__.py
│   │   └── db.py                # SQLite connection + schema
│   ├── services/
│   │   └── __init__.py          # business logic — pure functions where possible
│   ├── static/
│   │   ├── src/
│   │   │   └── input.css        # Tailwind v4 source (style.css gitignored, built at runtime)
│   │   ├── js/
│   │   │   └── htmx.min.js      # or loaded from CDN per caddy-config CSP
│   │   └── img/
│   └── templates/
│       ├── web/                 # .html.jinja2  (HTMX)               (--web, default on)
│       │   ├── base.html.jinja2
│       │   └── index.html.jinja2
│       ├── mobile/              # .hxml.jinja2  (Hyperview)           (--mobile, default on)
│       │   └── index.hxml.jinja2
│       └── components/          # shared fragments
│           └── nav.html.jinja2
├── mobile-client/               # React Native + Expo thin shell      (--mobile)
│   ├── App.tsx
│   ├── package.json
│   └── app.json
├── tests/
│   ├── __init__.py
│   ├── conftest.py
│   ├── unit/
│   ├── integration/
│   └── e2e/                     # Playwright via MCP
├── deploy/
│   └── run.sh                   # deploy entry point — called by GitHub Actions
├── infra/
│   ├── {project}.caddy          # per-site Caddy config (installed to /etc/caddy/conf.d/)
│   ├── {project}.service        # systemd unit (installed to /etc/systemd/system/)
│   └── (optional: backup.sh, backup-cron, harden.sh, etc. — per-project ops scripts)
├── meetings/
│   └── .gitkeep                 # project meetings land here; tracked in git
├── .github/
│   └── workflows/
│       └── deploy.yml           # thin SSH shell — calls deploy/run.sh
├── .claude/
│   ├── CLAUDE.md                # project-level Claude Code rules (loaded by Claude Code automatically)
│   ├── agents/                  # populated as TF agents are defined
│   ├── skills/                  # populated as project-scope skills are defined
│   └── rules/                   # 5 path-scoped/repo-wide rule skeletons
├── CLAUDE.md                    # root-level — project Claude Code context (distinct from .claude/CLAUDE.md)
├── DEVELOPER_GUIDE.md           # human-readable developer reference
├── run.sh                       # local dev entry point (Tailwind watcher + uvicorn --reload)
├── .env.example
├── .gitignore
├── pyproject.toml
├── uv.lock                      # generated
└── README.md
```

## The `deploy/` vs `infra/` split

Two infrastructure-related directories with deliberate scope:

- **`deploy/`** — what's actively *run* during deploy. Currently just `run.sh`. The GitHub Actions workflow calls `bash deploy/run.sh`; nothing else goes here.
- **`infra/`** — declarative *configuration* that lives in `/etc/` on the server (systemd unit, Caddy config). Plus optional per-project operational scripts (backup, hardening, OrbStack staging) that belong with the project but aren't part of the deploy entry point.

This split keeps the deploy entry point unambiguous (one file, one purpose) while letting `infra/` accumulate project-specific operational scripts without polluting `deploy/`.

`bootstrap-project.sh` (in the studio repo) reads from `infra/` to install the systemd unit and Caddy config during first deploy. `deploy/run.sh` re-syncs the Caddy config on subsequent deploys when it changes.

## CLAUDE.md vs .claude/CLAUDE.md

Two distinct files with different purposes:

- **`CLAUDE.md`** (project root) — project context for Claude Code: what the project is, current state, deploy procedure, dev workflow, key constraints. Roughly equivalent to a project README but written for an AI collaborator. Loaded automatically when Claude Code runs from the project root.
- **`.claude/CLAUDE.md`** (under `.claude/`) — project-level Claude Code rules, typically more about *how* Claude Code should behave in this repo (path-scoped rules, agents, skills). Loaded by Claude Code's standard `.claude/` discovery.

Both files coexist. The root `CLAUDE.md` is the "describe the project" file; `.claude/CLAUDE.md` is the "configure Claude Code" file.

## Production layout

On the production host, the repo clones into a project-named subdirectory under the project user's tree:

```
/opt/{project}/                  # owned by the {project} system user
├── {project}/                   # the cloned repo (matches the local layout above)
│   ├── app/
│   ├── deploy/
│   ├── infra/
│   ├── pyproject.toml
│   └── ...
├── data/                        # SQLite, uploads — written by the service
├── .uv-cache/                   # uv cache (mode 2775, deploy can write)
└── .env                         # secrets (mode 600, service-user only)
```

The repo subdirectory is named after the project (rather than a generic `app/`) to make `/opt/{project}/{project}/` self-describing. `data/`, `.uv-cache/`, and `.env` are siblings of the repo because they're not part of the codebase — each has different ownership/access rules.

## Where things go

A cheat sheet for when the CEO or an agent asks "where does X live?":

| Thing | Location |
|---|---|
| New FastAPI route (HTML) | `app/routes/web.py` |
| New FastAPI route (HXML) | `app/routes/mobile.py` (must start with `/m/`) |
| New FastAPI route (webhook) | `app/routes/api.py` under `/webhook/` or `/integrations/` |
| SQLite schema change | `app/models/db.py` + a migration in `app/models/migrations/` |
| Business logic | `app/services/` — one module per concept |
| HTMX page template | `app/templates/web/{name}.html.jinja2` |
| HXML page template | `app/templates/mobile/{name}.hxml.jinja2` |
| Shared fragment | `app/templates/components/{name}.html.jinja2` (or `.hxml.jinja2`) |
| Tailwind input | `app/static/src/input.css` (output `app/static/style.css` is gitignored) |
| New static asset | `app/static/{js,img}/` |
| pytest test | `tests/{unit,integration,e2e}/test_{name}.py` |
| Playwright test | `tests/e2e/test_{name}.py` (runs via Playwright MCP) |
| New skill (project scope) | `.claude/skills/{name}/SKILL.md` |
| New rule (project scope) | `.claude/rules/{name}.md` with `paths:` frontmatter |
| Meeting output | `meetings/MEETING-YYYY-MM-DD-{slug}/` |
| Systemd unit | `infra/{project}.service` (dev); `/etc/systemd/system/` (prod) |
| Caddy config | `infra/{project}.caddy` (dev); `/etc/caddy/conf.d/` (prod) |
| Deploy script | `deploy/run.sh` (called by `.github/workflows/deploy.yml`) |
| Per-project ops script (backup, harden, etc.) | `infra/{name}.sh` |

## Template files

Ready to copy from `${CLAUDE_SKILL_DIR}/templates/`:

**Project root:**
- `app/main.py` — minimal FastAPI app with Jinja2 and HTMX wiring
- `pyproject.toml` — uv-managed, Python 3.12, FastAPI, uvicorn, Jinja2, SQLite, ruff
- `README.md` — project README with dev/deploy sections
- `CLAUDE.md` — project-level Claude Code context (root, distinct from `.claude/CLAUDE.md`)
- `DEVELOPER_GUIDE.md` — comprehensive human-developer reference (architecture, server users, deploy flow, monitoring, break-glass)
- `run.sh` — local dev entry point (Tailwind watcher + uvicorn --reload, auto-skips Tailwind if no input.css)
- `.github/workflows/deploy.yml` — thin SSH shell that calls `deploy/run.sh`

**`deploy/`:**
- `deploy/run.sh` — canonical 6-step deploy script (sg + git fetch/reset, uv sync, optional Tailwind build, conditional Caddy sync, systemctl restart, health check)

**`infra/`:**
- `.gitkeep` — placeholder so the directory exists; `{project}.caddy` and `{project}.service` are generated by `/start-new-app` from the `caddy-config` and `systemd-service` skill templates

**Project-scope Claude Code config:**
- `.claude/CLAUDE.md` — starter CLAUDE.md with stack notes, domain placeholder, agents/skills/rules pointers
- `.claude/skills/README.md` — project-scope skills index template (commands vs knowledge categorization)
- `.claude/rules/python-backend.md` — path-scoped to `app/**` and `tests/**`: uv-run invocation, import conventions, SQLite patterns, ruff
- `.claude/rules/web-templates.md` — path-scoped to `app/templates/web/**`, `app/templates/components/**`, `app/static/**`: HTMX-first, Tailwind v4, Alpine as fallback, accessibility baseline
- `.claude/rules/mobile-templates.md` — path-scoped to `app/templates/mobile/**`, `mobile-client/**`: Hyperview/HXML conventions, `/m/` routing, Content-Type requirements
- `.claude/rules/tests.md` — path-scoped to `tests/**`: layout, naming, pytest + Playwright MCP patterns
- `.claude/rules/repo-wide.md` — always-loaded (no `paths:`): secret hygiene, git hygiene, destructive-action caution

(`.env.example` and `.gitignore` live in the `start-new-app` skill's own templates — that's where they're used.)

## Variable substitutions in templates

`/start-new-app` substitutes these placeholders when copying templates:

| Placeholder | Replaced with |
|---|---|
| `{project-name}` | kebab-case project name |
| `{project-domain}` | full domain (e.g. `hello-aqnas.aqnas.xyz`) |
| `{port}` | allocated production port from `ports.conf` |
| `{pwd}` | absolute path of the project directory |

These appear in `CLAUDE.md`, `DEVELOPER_GUIDE.md`, `deploy/run.sh`, `infra/{project}.service`, `infra/{project}.caddy`, `MANUAL-TASKS.md`, and similar.

## Naming conventions

- Project name: kebab-case, 1–2 words. No `aqnas-` prefix. Matches: directory, systemd User, Caddy config, `/opt/{project}/` path, port registry key.
- Routes: lowercase kebab-case in URLs (`/user-profile`), snake_case in handler names (`def user_profile(...)`).
- Templates: match route slugs where possible (`/posts/{id}` → `app/templates/web/post_detail.html.jinja2`).
- DB tables: plural snake_case (`users`, `blog_posts`).
- Tests: mirror the module under test (`app/services/auth.py` → `tests/unit/test_auth.py`).

## Required directories

These must exist even when empty:

- `app/`, `app/routes/`, `app/models/`, `app/services/`, `app/static/`
- `app/templates/web/`, `app/templates/components/`
- `tests/`
- `deploy/` (contains `run.sh`)
- `infra/` (with `.gitkeep`; populated by `/start-new-app` with `.caddy` and `.service` files)
- `meetings/` (with `.gitkeep`)
- `.claude/` (full subtree)

## Optional directories

Create only when the project uses them:

- `app/templates/mobile/` — only if the project has a mobile client
- `mobile-client/` — only if the project has a mobile client
- `tests/e2e/` — when Playwright tests are added

## What not to do

- Don't add a `/api/` prefix. AQNAS is hypermedia-first; HTMX fragments share the same routes as full pages, differentiated by `HX-Request` header. `/api/` is reserved for `webhook/` and `integrations/` only.
- Don't put business logic in routes. Routes are thin — they validate inputs, call services, render templates.
- Don't put `{project}.caddy` or `{project}.service` in `deploy/`. They live in `infra/`. `deploy/` is only for `run.sh`.
- Don't vendor libraries you could install via uv. Trust `pyproject.toml` + `uv.lock`.
- Don't mix web and mobile templates in the same directory.
- Don't create a `config/` directory. Environment variables live in `.env`; constants live in `app/config.py` (a single module).
- Don't commit `uv.lock` from a different Python version. Match `pyproject.toml`'s `requires-python = ">=3.12"`.
- Don't commit `app/static/style.css` — it's a Tailwind build artifact, gitignored, built at runtime by `run.sh` (dev) and `deploy/run.sh` (prod).
