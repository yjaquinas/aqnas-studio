---
name: start-new-app
description: Scaffolds a new AQNAS project into the current working directory. The user creates an empty directory, cd's into it, launches Claude Code, and runs /start-new-app — the skill populates the directory in place with the canonical project layout, allocates a port from the studio registry, runs uv sync, initializes git with a gitleaks pre-commit hook, and makes the initial commit. Defaults to scaffolding both web (HTMX) and mobile (Hyperview) layers; --no-web or --no-mobile prune accordingly. Refuses to scaffold into a populated cwd or a cwd nested in another git repo without explicit confirmation. Never modifies the .claude/ symlink, never deploys, never pushes to GitHub.
disable-model-invocation: true
argument-hint: [--no-web] [--no-mobile]
allowed-tools: Read, Write, Edit, Bash, Glob
---

# /start-new-app

Scaffold the current working directory into a new AQNAS project.

## Mental model

The user's intended flow:

```sh
mkdir ~/dev/my-project
cd ~/dev/my-project
claude
# inside Claude Code:
/start-new-app
```

The skill operates on `$(pwd)`. It does not create a new directory; the user already did that by `mkdir`-ing one. It does not move the user; they're already where the project should live.

## Invocation

- `/start-new-app` — scaffold the cwd with both web and mobile layers (default)
- `/start-new-app --no-mobile` — scaffold web-only
- `/start-new-app --no-web` — scaffold mobile-only (rare; mostly for back-end + mobile-client setups)
- `/start-new-app --no-web --no-mobile` — refuse with "you've opted out of both — there's nothing to scaffold"

## Step 0 — Preflight

Before writing anything to the cwd, verify all of these:

1. **`$AQNAS_STUDIO_ROOT` is set.** If not, abort with: "AQNAS_STUDIO_ROOT is not set. Run `~/aqnas-studio/setup.sh` (or the equivalent) and reload your shell, then retry."
2. **cwd state.** Categorize the cwd into one of five cases below; act per the case.
3. **Project name validity.** `basename $(pwd)` should be kebab-case (lowercase letters, digits, hyphens; must start with a letter; no `aqnas-` prefix). If not, prompt for a name; warn that the directory name and project name will differ.
4. **Tools.** `uv` and `git` must be on the PATH. `gitleaks` and `node`/`npx` are checked but their absence is non-fatal: a missing `gitleaks` means the pre-commit hook will warn at commit time instead of failing here; a missing `node`/`npx` means Step 6's `playwright-cli` skill install is skipped (noted in the final report) and the CEO can run it later.

## Step 1 — Categorize the cwd

| Case | Detection | Action |
|---|---|---|
| **1. Empty (or .git/ only)** | `find . -maxdepth 1 -mindepth 1 -not -name .git` returns nothing | Proceed normally. |
| **2. AQNAS in progress** | `pyproject.toml` or `app/main.py` exists | Ask: "Looks like an AQNAS project is already started here. Continue scaffold to fill in missing files, or abort?" |
| **3. Other-stack files** | `package.json`, `Cargo.toml`, `Gemfile`, etc. detected | Ask: "This directory contains files from another stack ({list}). Are you intentionally adding an AQNAS scaffold alongside? (y/N)" |
| **4. Unrelated files** | Any other non-empty content | Ask: "This directory contains files I don't recognize ({list of first 5}). Scaffold here anyway? (y/N)" |
| **5. Nested in a git repo** | `git rev-parse --show-superproject-working-tree` or walking up to find a parent `.git` succeeds, AND the cwd itself isn't the parent repo's root | Ask: "This directory is inside another git repo at {parent-repo-path}. AQNAS projects are typically standalone repos with their own git history. Continue and create a nested git repo? (y/N)" |

For cases 2–5, default to abort if the user doesn't explicitly confirm. Log the case in the final report.

Cases 5 and 2/3/4 can co-occur — handle each prompt in order.

## Step 2 — Determine project metadata

Three values to lock in:

- **Project name** — `basename $(pwd)`, validated as kebab-case. Used as: systemd User, port-registry key, `/opt/{name}/` path, and the repo subdir on the production server.
- **Display name** — title-cased project name by default (e.g. `aqnas-test` → `Aqnas Test`). User confirms or overrides.
- **Domain** — `{project-name}.aqnas.xyz` by default. User confirms or overrides; can be a top-level domain like `myproduct.com` for graduating projects.

Show all three to the user for confirmation before writing anything:

```
Project name:  {project-name}
Display name:  {Project Display Name}
Domain:        {project-domain}
Layout:        web {+ mobile if --no-mobile not passed}

Proceed? (y/N)
```

## Step 3 — Allocate port

```bash
"$AQNAS_STUDIO_ROOT/claude-config/skills/port-registry/scripts/allocate-port.sh" "{project-name}"
```

Capture stdout as `{port}`. The script handles atomic allocation via `flock` and refuses if the project name is already reserved. If it errors, abort the whole scaffold — port collisions are not recoverable in this flow.

## Step 4 — Generate the scaffold

Copy template files from two source locations and substitute the four variables (`{project-name}`, `{Project Display Name}`, `{project-domain}`, `{port}`) in each:

**From `$AQNAS_STUDIO_ROOT/claude-config/skills/project-scaffold/templates/`:**

Always copied (regardless of flags):
- `app/main.py` → `app/main.py`
- `pyproject.toml` → `pyproject.toml`
- `README.md` → `README.md`
- `CLAUDE.md` → `CLAUDE.md` (project-root level — distinct from `.claude/CLAUDE.md`)
- `DEVELOPER_GUIDE.md` → `DEVELOPER_GUIDE.md`
- `run.sh` → `run.sh` (top-level local-dev runner; `chmod +x` after copy)
- `deploy/run.sh` → `deploy/run.sh` (canonical deploy entry point; `chmod +x` after copy)
- `infra/.gitkeep` → `infra/.gitkeep` (placeholder so directory exists)
- `.github/workflows/deploy.yml` → `.github/workflows/deploy.yml`
- `.claude/CLAUDE.md` → `.claude/CLAUDE.md`
- `.claude/skills/README.md` → `.claude/skills/README.md`
- `.claude/rules/python-backend.md` → `.claude/rules/python-backend.md`
- `.claude/rules/tests.md` → `.claude/rules/tests.md`
- `.claude/rules/repo-wide.md` → `.claude/rules/repo-wide.md`

Copied unless `--no-web`:
- `.claude/rules/web-templates.md` → `.claude/rules/web-templates.md`

Copied unless `--no-mobile`:
- `.claude/rules/mobile-templates.md` → `.claude/rules/mobile-templates.md`

**From `$AQNAS_STUDIO_ROOT/claude-config/skills/start-new-app/templates/`:**

Always copied:
- `.env.example` → `.env.example`
- `.gitignore` → `.gitignore`
- `MANUAL-TASKS.md` → `MANUAL-TASKS.md` (with `{project-name}`, `{project-domain}`, `{port}`, `{pwd}` substituted)

**Generated from skill templates:**

- `infra/{project-name}.service` from `$AQNAS_STUDIO_ROOT/claude-config/skills/systemd-service/template.service`
- `infra/{project-name}.caddy` from `$AQNAS_STUDIO_ROOT/claude-config/skills/caddy-config/template.caddy`

The `infra/` directory holds declarative infrastructure config (systemd unit, Caddy config) plus any per-project operational scripts the project adds later (backup.sh, harden.sh, etc.). The `deploy/` directory holds only `run.sh` — the deploy entry point called by GitHub Actions. Server-side bootstrap (installing the systemd unit and Caddy config to `/etc/`) is handled by the studio-level `bootstrap-project.sh`, not per-project. The generated `MANUAL-TASKS.md` references that script.

**Skeleton directories created (with `__init__.py` or `.gitkeep` as appropriate):**

```
app/__init__.py
app/routes/__init__.py
app/routes/web.py                    # if web layer is on
app/routes/mobile.py                 # if mobile layer is on
app/models/__init__.py
app/models/db.py                     # SQLite setup stub
app/services/__init__.py
app/static/src/.gitkeep              # Tailwind v4 source dir (input.css added when Tailwind is used)
app/static/js/.gitkeep
app/static/img/.gitkeep
app/templates/web/base.html.jinja2   # if web layer is on
app/templates/web/index.html.jinja2  # if web layer is on
app/templates/mobile/index.hxml.jinja2  # if mobile layer is on
app/templates/components/.gitkeep    # always
mobile-client/                       # only if mobile layer is on, with package.json/app.json/App.tsx stubs
tests/__init__.py
tests/conftest.py
meetings/.gitkeep
.claude/agents/.gitkeep
.claude/skills/.gitkeep
```

(`deploy/run.sh` and `infra/.gitkeep` are copied from templates as listed above, so the `deploy/` and `infra/` directories will exist post-scaffold.)

## Step 5 — Initialize git

```bash
git init -q
git branch -m main
```

Install gitleaks pre-commit hook at `.git/hooks/pre-commit`:

```bash
#!/usr/bin/env bash
# aqnas:gitleaks
set -e
if ! command -v gitleaks >/dev/null 2>&1; then
    echo "WARN: gitleaks not installed — skipping secret scan."
    exit 0
fi
gitleaks protect --staged --no-banner --redact
```

`chmod +x` it.

## Step 6 — Install dependencies

```bash
UV_CACHE_DIR=./.uv-cache uv sync
```

This generates `uv.lock` and creates `.venv/`. Both are project-local; `.uv-cache/` mirrors the production layout where systemd sets `UV_CACHE_DIR=/opt/{project}/.uv-cache`.

**On failure:** report the failure with the captured stderr but **do not roll back the scaffold**. Partial state is recoverable; rolling back deleted files is risky. Continue to step 7. Mark `uv sync` status in the final report.

Also install the `playwright-cli` skill for E2E tests:

```bash
npx -y @playwright/cli@latest install --skills=claude
```

This writes `.claude/skills/playwright-cli/` (skill + references, ready to commit) and an empty `.playwright/` (session/snapshot data, gitignored). It reuses an installed system browser when one is found instead of downloading a bundled Chromium. Non-fatal on failure — note it in the final report and the CEO can rerun the command later.

## Step 7 — Initial commit

```bash
git add .
git commit -m "chore: scaffold {project-name}"
```

If the gitleaks pre-commit hook flags anything, abort — something is in the templates or substitutions that shouldn't be (likely a leaked secret). Investigate before retrying.

## Step 8 — Generate `MANUAL-TASKS.md` and emit summary

The console output gets skipped or scrolled past; a file in the repo gets read. Write the per-project setup checklist to the project root, then print a short summary pointing at it.

### Write the checklist

Copy `$AQNAS_STUDIO_ROOT/claude-config/skills/start-new-app/templates/MANUAL-TASKS.md` to `$(pwd)/MANUAL-TASKS.md`, substituting these variables in the same pass:

- `{project-name}` → kebab-case project identifier
- `{project-domain}` → e.g. `hello-aqnas.aqnas.xyz`
- `{port}` → allocated production port from registry
- `{pwd}` → absolute path of the project directory (where the skill ran)

The template already has all four placeholders. Use the same substitution pass as for the other scaffold files.

### Emit short console summary

```
══════════════════════════════════════════════════════════════
START-NEW-APP COMPLETE — {project-name}
══════════════════════════════════════════════════════════════

LOCATION:        {pwd}
PORT:            {port} (production binding — local dev uses any port)
DOMAIN:          {project-domain}
LAYOUT:          {web | mobile | web + mobile}
INITIAL COMMIT:  {hash}
UV SYNC:         {ok | failed: <stderr summary>}
PRE-COMMIT:      gitleaks hook installed

WARNINGS:
  - {if cwd was non-empty / nested in git repo, note it here}

→ Open MANUAL-TASKS.md for the full setup checklist:
  Local dev verification, GitHub repo + secrets, deploy key, server bootstrap, DNS, CI/CD.

══════════════════════════════════════════════════════════════
```

That's it. Five lines of metadata + one pointer line. No long "NEXT (locally) / NEXT (push) / NEXT (deploy)" walls of text — those live in the file.

### Why a file instead of the console

Console output gets lost. The file:
- Sits in the project root where the user is already working
- Has checkboxes — tracks progress as you complete steps
- Is gitignored (per `.gitignore` template) — operator-specific, not project content
- Won't be regenerated. If deleted, recreate from the deploy-procedure skill or by running `/start-new-app` against an empty test directory and copying that file over.

## What this skill never does

- Never modifies `~/.claude/` or any studio-scope file
- Never deploys to the production server
- Never pushes to GitHub or creates remote repos
- Never moves the user — operates on `$(pwd)` only
- Never overwrites existing files in cwd silently — non-empty cases require explicit confirmation
- Never bypasses gitleaks at commit time — `--no-verify` is forbidden

## Failure modes

- **`$AQNAS_STUDIO_ROOT` not set.** Abort cleanly with the setup pointer. Don't try to guess the path.
- **Project name invalid.** Prompt for a valid kebab-case name; if the user can't or won't provide one, abort.
- **Port allocation fails.** Either the project name collides with an existing reservation, or no free port in the 8010–8089 range. Abort and surface the underlying error.
- **`uv sync` fails.** Report the failure but leave the scaffold in place. The user can fix `pyproject.toml` and re-run `uv sync` manually.
- **Gitleaks flags the initial commit.** Should never happen with clean templates — investigate. Likely an env var or path that contains something gitleaks treats as sensitive.
- **Pre-existing `.claude/` directory in cwd.** Treated like any other unrelated content — ask before proceeding. Almost certainly the user has been experimenting; back up theirs before scaffolding the standard skeleton.
- **Templates moved or missing.** If `$AQNAS_STUDIO_ROOT/claude-config/skills/project-scaffold/templates/` doesn't have the expected files, abort and tell the user to check their studio repo state.
