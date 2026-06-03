# Findings

Dated notes on bugs, decisions, and operational lessons learned while running `aqnas-studio`.

## How to use this file

Entries are dated and brief — just enough context that future-you can recover what was learned and why. No fixed template.

When something deferred gets fixed: update the dates line if it's quick (`→ resolved YYYY-MM-DD`), or just leave it; `git log` is the system of record. The artifact in the codebase is what matters.

For active deferred work, a separate `TODO.md` or GitHub issues is lighter than searching this log.

---

### Bug 1 — `allocate-port.sh` aborts on empty registry

*2026-04-28 → resolved 2026-04-29*

With `set -euo pipefail`, `grep` exits 1 when there are no matches in a fresh `ports.conf`, failing the whole pipeline before any allocation. Fixed in `allocate-port.sh:57` by adding `|| true` to tolerate the empty case. (See also Bug 14 — same pipeline needed a second fix to ignore commented entries.)

---

### Bug 2 — `/start-new-app` report's local-dev port hint was misleading

*2026-04-28 → resolved 2026-04-29*

Console report told users to run `uvicorn` locally with `--port {port}`, where `{port}` is the production port from the registry. That conflates the prod binding with local-dev (which is just `127.0.0.1:8000`). Fixed by hardcoding `--port 8000` in the local-dev hint and adding an explanatory note. Later folded into the `MANUAL-TASKS.md` rewrite (Bug 4).

---

### Bug 3 — README's `~/dev/{project}/` example might look prescriptive

*2026-04-28 — no action*

The README's example path is illustrative, not mandatory. New users might follow it literally without realizing `/start-new-app` works in whatever cwd. Current behavior is correct (path-flexibility is a feature); the friction is purely cosmetic. Logged for awareness.

---

### Bug 4 — `/start-new-app` console mixed prerequisites with workflow next-steps

*2026-04-30 → resolved 2026-05-07 (cleanup chunk 4)*

Console blended pre-conditions (deploy key registration, secrets) with workflow actions and future work, all under generic "NEXT" headings. Caused first-time users to miss critical GitHub Actions secret setup. Fixed by emitting a structured `MANUAL-TASKS.md` (251 lines, gitignored, sections for local dev / GitHub / first push / server bootstrap / verification); console output became a 3-5 line pointer at the file.

---

### Bug 5 — Production server IP convenience

*2026-04-30 → resolved 2026-05-12 (cleanup chunk 6)*

Initially considered: gitleaks IP-pattern detection to catch the production IP in commits. Decided against — too tedious, and the regex itself would expose the IP. Better approach: teach users to set up an SSH alias once (`aqnas-prod` — vendor-agnostic, scales to multiple environments). Added a "Configure SSH access" step to the studio README; removed vendor-specific naming from skill bodies.

---

### Bug 6 — Diagnostic-sharing workflow needed guardrails against secret leakage

*2026-04-30 → resolved 2026-05-13 (cleanup chunk 7)*

Realized when a `journalctl -u caddy` paste included `CLOUDFLARE_API_TOKEN=...` in plaintext. Token was rotated. Created `claude-config/skills/secret-hygiene/SKILL.md` (121 lines): what never to share, commands that commonly leak secrets in their default output, redaction patterns, a "share logs safely" procedure, and an emergency rotation playbook. Studio CLAUDE.md got one bullet pointing at the new skill.

---

### Bug 7 — `caddy validate` can't see the running daemon's environment

*2026-04-30 → resolved 2026-05-06 (cleanup chunk 3)*

Skill said "always `caddy validate` before reloading." But on configs referencing `{env.CLOUDFLARE_API_TOKEN}`, validate runs in the user's shell env (no token) — fails with "API token '' appears invalid" even when the daemon is fine. Fixed by replacing validate guidance with `systemctl reload caddy` (which validates internally with the daemon's environment, then atomically swaps on success). Cost an hour during hello-aqnas Phase 3.

---

### Bug 8 — `curl -I` returns 405 because FastAPI doesn't auto-implement HEAD

*2026-04-30 → resolved 2026-05-06 (cleanup chunk 3)*

`curl -I` issues HEAD; FastAPI/Starlette doesn't auto-implement HEAD for GET routes — returns 405 with helpful `allow: GET` header but looks like a server problem. Audit of `claude-config/` and `infrastructure/` found zero `curl -I` usages — never made it into templates. No edits required.

---

### Bug 9 — Studio repo was leaking operational state

*2026-04-30 → resolved 2026-05-07 (cleanup chunk 5)*

`infrastructure/server/ports.conf` documented real production deployments (which projects, which ports). The aggregate of public skills + workflow templates + real ports.conf disclosed more than necessary for a public repo. Fixed by gitignoring the real file, shipping `ports.conf.example` with commented illustrative entries; `allocate-port.sh` and `setup.sh` auto-copy the template on first run if the real file doesn't exist.

---

### Bug 10 — Existing aqnas project diverged from studio conventions

*2026-04-30 → resolved 2026-05-15 (separate aqnas-xyz migration session)*

The original `aqnas` project predated studio conventions: wrong repo path (`/opt/aqnas/app/`), wrong ownership model (deploy owned everything), legacy port (8000), legacy secret names (`SERVER_HOST`/`DEPLOY_KEY`), bespoke `deploy.sh`. Reconciled during the May 2026 aqnas-xyz/kumdo-exam migration: renamed to `aqnas-xyz`, moved to `/opt/aqnas-xyz/aqnas-xyz/`, ownership flipped, ports moved to 8011/8012. Follow-up cleanup tracked as Bugs 16-20.

---

### Bug 11 — Bootstrap procedure missing `git config safe.directory`

*2026-05-04 → resolved 2026-05-05 (cleanup chunk 2)*

Git refuses to operate when `.git/`'s owner doesn't match the running user (CVE-2022-24765). With the studio's ownership model (service user owns repo, deploy has group-write), every first CI run fails with "dubious ownership" until safe.directory is set. Fixed in `bootstrap-project.sh` step 7. Later extended (May 20) to set safe.directory for *both* deploy AND service user.

---

### Bug 12 — Bootstrap procedure missing sudoers for deploy

*2026-05-04 → resolved 2026-05-05 (cleanup chunk 2)*

CI's `sudo /bin/systemctl restart $PROJECT` prompted for a password — workflow failed with "a terminal is required to read the password." Fixed in `init-server.sh` (installs `/etc/sudoers.d/aqnas-studio-deploy` with systemctl wildcards). Later extended (chunk D, May 20) to include a `cp` wildcard for Caddy auto-sync from `infra/`.

---

### Bug 13 — `deploy-procedure` didn't account for project-specific deploy logic

*2026-05-04 → resolved 2026-05-20 (migration follow-up chunks A-D)*

The inline `.github/workflows/deploy.yml` was correct for hello-aqnas but couldn't handle real projects with asset builds, conditional Caddy syncs, or robust health checks. Resolved by adopting the `deploy/run.sh` pattern: workflow is a thin SSH shell calling `bash deploy/run.sh`; the script lives per-project and contains all deploy logic (sg + fetch + reset --hard, uv sync --no-dev, Tailwind, Caddy sync, restart, health check). Documented in `deploy-procedure/SKILL.md`; canonical template in `project-scaffold`.

---

### Bug 14 — `allocate-port.sh` regex matched commented-out entries

*2026-05-07 → resolved 2026-05-07 (cleanup chunk 5 smoke test)*

Surfaced by the chunk 5 smoke test against `ports.conf.example` (with `# my-first-app = 8010` illustrative entries). The "used ports" regex matched comments, so a fresh registry would consider 8010 and 8011 "used" and skip to 8012. Fixed by adding `grep -v '^\s*#'` as the first filter.

---

### Bug 15 — Studio repo accidentally captures Claude Code runtime state

*2026-05-13 → resolved 2026-05-13 (immediate fix during Phase 6 init push)*

The `~/.claude/ → claude-config/` symlink design meant `git add .` would stage Claude Code runtime state alongside methodology: `.credentials.json` (live auth token), `history.jsonl` (chat history), `projects/*.jsonl` (484KB of conversation logs), `file-history/`, `backups/`. Caught pre-push by `git status` audit. Fixed by adding 12 entries to root `.gitignore` covering all runtime-state paths plus 3 defensive entries for unknown future state. **Anyone forking this studio needs the same gitignore; the symlink-runtime-state gap is structural.**

---

### Bug 16 — aqnas-xyz docs referenced pre-migration paths

*2026-05-20 → resolved 2026-05-28*

Project's own `CLAUDE.md` and `DEVELOPER_GUIDE.md` referenced stale paths: `deploy.sh`, `/opt/aqnas/app/`, `SERVER_HOST`/`DEPLOY_KEY`. Documentation drift only — production state was correct, CI/CD reads YAML not Markdown. Fixed by surgical edits replacing all stale references; canonical post-migration paths throughout both files.

---

### Bug 17 — kumdo-exam Caddyfile not named per studio convention

*2026-05-20 — deferred*

`infra/Caddyfile` should be `infra/kumdo-exam.caddy` (matches `infra/{project}.service` naming). No current impact — kumdo-exam's `deploy/run.sh` has no Caddy sync step. Becomes blocking the moment that step is added: the sudoers `cp` wildcard `/opt/*/?*/infra/*.caddy` won't match `Caddyfile`.

---

### Bug 18 — Legacy `deploy.sh` still in kumdo-exam's tree

*2026-05-20 — deferred*

`deploy.sh` at kumdo-exam's repo root was replaced by `deploy/run.sh` during migration. aqnas-xyz's was removed; kumdo-exam's was left. Just `git rm deploy.sh` — single-commit chore.

---

### Bug 19 — aqnas-xyz's `deploy/run.sh` used old `git pull` pattern

*2026-05-20 → resolved 2026-05-27*

Script used `git pull origin main` and `uv sync --frozen` instead of canonical `sg + git fetch + reset --hard` and `--no-dev`. Worked normally but would hang on any server-side divergence. Fixed by replacing with the canonical template from `project-scaffold/templates/deploy/run.sh`, substituting `aqnas-xyz` and port `8011`. Workflow also updated to drop the redundant `git pull` (run.sh handles its own sync).

---

### Bug 20 — Top-level `run.sh` divergence between projects

*2026-05-20 → resolved 2026-05-28 (for aqnas-xyz)*

aqnas-xyz and kumdo-exam top-level `run.sh` files diverged from the canonical template — aqnas-xyz exports a dev `ADMIN_PASSWORD` default and always runs Tailwind; kumdo-exam has port-kill insurance and binds 0.0.0.0. Originally logged as "no action required" — project-specific dev runners may legitimately diverge. Resolved for aqnas-xyz anyway: adopted canonical structure (`set -euo pipefail`, input.css guard, variables) while preserving the load-bearing ADMIN_PASSWORD line. kumdo-exam left as-is.

---

### Bug 21 — Server-side aqnas-studio clone creates soft drift risk

*2026-05-20 — partial resolution; broader pattern deferred*

The `~/aqnas-studio/` clone on production exists only for `bootstrap-project.sh`. Outside that, it tempts operators to "just edit on the server" — soft drift risk. Mitigated for `studio-status` by adding a local wrapper at `scripts/studio-status` that streams the script over SSH via `bash -s`; the server doesn't need a copy. The same pattern could extend to `bootstrap-project.sh` and `init-server.sh`, then remove the server-side clone entirely. Open concerns: interactive prompts under `bash -s`, sibling-file references, recovery scenarios when SSH is broken. Worth a focused session.
