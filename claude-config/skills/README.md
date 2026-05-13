# Skills — C-level

Top-level `skills/` is flat by design: Claude Code's skill discovery only scans
the top level of this directory for `SKILL.md` files. Subdirectories don't work
as namespaces (see issues #10238, #16438, #18192, #20805, #28266 in the
upstream repo).

This README is the categorization layer — the filesystem is flat, but the
skills split into two kinds by purpose.

## Commands (user-invocable)

These appear in the `/` picker. Each is a slash command.

| Command | Purpose |
|---|---|
| `/run-meeting` | Multi-agent deliberation producing a `MEETING-*/` directory with numbered outputs. Supports `mode-auto-on` flag for delegated deliberation. |
| `/update-project-claude` | Apply a meeting's `2-CLAUDE-UPDATES.md` to a project's `.claude/` directory. |
| `/execute-plan` | Spawn Task Force agents to build tasks defined in a meeting's `3-BUILD-PLAN.md`. |
| `/start-new-app` | Scaffold a new project repo from a meeting directory (structure, git init with gitleaks hook, port reservation, initial `.claude/` seed). |
| `/commit-git` | Review staged changes, run gitleaks explicitly for secret scanning, commit with a conventional message. |
| `/analyze-webpage` | Fetch and analyze a URL for design tokens, layout, copy voice, and tech stack. The only auto-invocable command (loads on URL mentions in conversation). |

## Knowledge (background)

These don't appear in the `/` picker — they carry `disable-model-invocation` or
are simply background references. Claude loads them automatically when their
descriptions match the current task.

| Skill | Covers |
|---|---|
| `systemd-service` | Per-project `.service` file conventions: isolation, uv ExecStart, hardening, `.uv-cache` layout. |
| `caddy-config` | Per-project `.caddy` conventions: Cloudflare DNS challenge TLS, security headers, reverse proxy, logging. |
| `project-scaffold` | Canonical AQNAS project directory layout and "where does X go?" cheat sheet. |
| `hyperview-patterns` | HXML/Hyperview for the mobile stack — screen structure, behaviors, styling, `/m/` routes. |
| `sqlite-conventions` | SQLite setup: WAL, foreign keys, raw SQL (no ORM), migration pattern, schema conventions. |
| `deploy-procedure` | Production deploy flow: bootstrap (one-shot), GitHub Actions CI/CD, rollback, ownership model. |
| `port-registry` | Port allocation 8000–8099; conflict detection; sync between studio repo and server `ports.conf`. |
