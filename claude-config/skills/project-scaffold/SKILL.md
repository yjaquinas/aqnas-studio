---
name: project-scaffold
description: Defines the canonical AQNAS project repository structure and the contents of each boilerplate file. The repo layout puts templates and static assets inside the app module (app/templates/web/ for HTMX, app/templates/mobile/ for Hyperview, app/templates/components/ for shared fragments, app/static/ for CSS/JS/images). Other top-level dirs are mobile-client/ (React Native/Expo thin shell, only with --mobile), tests/ (pytest), deploy/ (.caddy, .service, bootstrap.sh), meetings/ (project-scope, tracked in git), .github/workflows/deploy.yml (GitHub Actions deploy), .claude/ (agents, skills, rules, CLAUDE.md). Root files: .env.example, .gitignore, pyproject.toml, uv.lock, README.md. On the production host, the repo clones into /opt/{project}/{project}/ (project-named subdirectory of the project user's tree) with /opt/{project}/data/, /opt/{project}/.uv-cache/, and /opt/{project}/.env as siblings. Use when scaffolding a new project (referenced by start-new-app), adding a missing directory to an existing project, deciding where a new file should live, or when the user asks about project structure, directory layout, what boilerplate to include, or "where does X go?". Contains templates/ with ready-to-copy files for main.py, pyproject.toml, deploy.yml, README.md, plus the project-scope .claude/ skeleton.
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
│   │   ├── css/
│   │   │   └── app.css          # Tailwind v4 entry
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
│   ├── {project}.caddy          # canonical — also in studio infrastructure/
│   ├── {project}.service
│   └── bootstrap.sh             # server-side: create user, dirs, install service
├── meetings/
│   └── .gitkeep                 # project meetings land here; tracked in git
├── .github/
│   └── workflows/
│       └── deploy.yml
├── .claude/
│   ├── CLAUDE.md
│   ├── agents/                  # populated as TF agents are defined
│   ├── skills/                  # populated as project-scope skills are defined
│   └── rules/                   # 5 path-scoped/repo-wide rule skeletons
├── .env.example
├── .gitignore
├── pyproject.toml
├── uv.lock                      # generated
└── README.md
```

## Production layout

On the production host, the repo clones into a project-named subdirectory under the project user's tree:

```
/opt/{project}/                  # owned by the {project} system user
├── {project}/                   # the cloned repo (matches the local layout above)
│   ├── app/
│   ├── deploy/
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
| New static asset | `app/static/{css,js,img}/` |
| pytest test | `tests/{unit,integration,e2e}/test_{name}.py` |
| Playwright test | `tests/e2e/test_{name}.py` (runs via Playwright MCP) |
| New skill (project scope) | `.claude/skills/{name}/SKILL.md` |
| New rule (project scope) | `.claude/rules/{name}.md` with `paths:` frontmatter |
| Meeting output | `meetings/MEETING-YYYY-MM-DD-{slug}/` |
| Systemd unit | `deploy/{project}.service` (dev); `/etc/systemd/system/` (prod) |
| Caddy config | `deploy/{project}.caddy` (dev); `/etc/caddy/conf.d/` (prod) |

## Template files

Ready to copy from `${CLAUDE_SKILL_DIR}/templates/`:

**Project root:**
- `app/main.py` — minimal FastAPI app with Jinja2 and HTMX wiring
- `pyproject.toml` — uv-managed, Python 3.12, FastAPI, uvicorn, Jinja2, SQLite, ruff
- `README.md` — project README with dev/deploy sections
- `.github/workflows/deploy.yml` — GitHub Actions to SSH to the production server and deploy

**Project-scope Claude Code config:**
- `.claude/CLAUDE.md` — starter CLAUDE.md with stack notes, domain placeholder, agents/skills/rules pointers
- `.claude/skills/README.md` — project-scope skills index template (commands vs knowledge categorization)
- `.claude/rules/python-backend.md` — path-scoped to `app/**` and `tests/**`: uv-run invocation, import conventions, SQLite patterns, ruff
- `.claude/rules/web-templates.md` — path-scoped to `app/templates/web/**`, `app/templates/components/**`, `app/static/**`: HTMX-first, Tailwind v4, Alpine as fallback, accessibility baseline
- `.claude/rules/mobile-templates.md` — path-scoped to `app/templates/mobile/**`, `mobile-client/**`: Hyperview/HXML conventions, `/m/` routing, Content-Type requirements
- `.claude/rules/tests.md` — path-scoped to `tests/**`: layout, naming, pytest + Playwright MCP patterns
- `.claude/rules/repo-wide.md` — always-loaded (no `paths:`): secret hygiene, git hygiene, destructive-action caution

(`.env.example` and `.gitignore` live in the `start-new-app` skill's own templates — that's where they're used.)

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
- `deploy/`
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
- Don't vendor libraries you could install via uv. Trust `pyproject.toml` + `uv.lock`.
- Don't mix web and mobile templates in the same directory.
- Don't create a `config/` directory. Environment variables live in `.env`; constants live in `app/config.py` (a single module).
- Don't commit `uv.lock` from a different Python version. Match `pyproject.toml`'s `requires-python = ">=3.12"`.
