# Findings

Living log of bugs and improvements found while operating `aqnas-studio`. Each entry is dated. Severity guides cleanup priority.

When something gets fixed, append a `### Resolution` block to the entry with date, what changed, and how it was verified — don't delete entries. The history of "what was broken and how we fixed it" is more useful than a clean slate.

---

## Bug 1 — `allocate-port.sh` aborts when the port registry is empty

**Found:** 2026-04-28
**Severity:** Blocks first use on every fresh install
**Where:** `claude-config/skills/port-registry/scripts/allocate-port.sh:57`

```sh
used_ports=$(grep -oE '=\s*8[0-9]{3}' "$REGISTRY" | grep -oE '8[0-9]{3}' | sort -un)
```

With `set -euo pipefail` (line 20) and `pipefail` in effect, if the first `grep` finds no matches it exits 1 and the whole pipeline fails. The very first time the script runs against a fresh `ports.conf` (no project entries), it aborts before allocating anything.

**Repro:** From a fresh `ports.conf`, run `allocate-port.sh hello-aqnas`. Script exits 1 silently due to `set -e`.

**Fix:** tolerate the empty case.

```sh
used_ports=$(grep -oE '=\s*8[0-9]{3}' "$REGISTRY" | grep -oE '8[0-9]{3}' | sort -un || true)
```

**Workaround used during Phase 1 testing:** added `hello-aqnas = 8010` to `ports.conf` manually.

### Resolution

**Date:** 2026-04-29
**Change:** Patched `allocate-port.sh` line 57 with `|| true`. Added inline comment explaining why so future readers don't think it's a typo.
**Verified:** Wipe-and-rescaffold on 2026-04-29 — empty registry no longer aborts; `/start-new-app` ran cleanly to completion. Smoke-tested the empty-input case in isolation: pipeline returns empty string instead of erroring.

---

## Bug 2 — `/start-new-app` final report's "NEXT (locally)" hint is misleading

**Found:** 2026-04-28
**Severity:** Cosmetic / educational. No functional impact, but creates a false coupling in the user's mental model.
**Where:** `claude-config/skills/start-new-app/SKILL.md` Step 8 (Report)

The report told users to run `uvicorn` locally with `--port {port}`, where `{port}` is the *production* port reserved in `ports.conf` for the systemd unit and Caddy reverse proxy. There is no reason for local dev to use it — local dev binds to a port on `127.0.0.1` that has no relationship to the registry. Suggesting `{port}` here implies the registry is load-bearing for dev, which it isn't.

**Fix:** decouple the local-dev port from `{port}`; mirror the project's `README.md` template which already hardcodes `--port 8000`.

### Resolution

**Date:** 2026-04-29
**Change:** Patched `start-new-app/SKILL.md` Step 8 to use `--port 8000` for the local-dev hint, plus added an explanatory paragraph distinguishing local-dev port from the production registry binding. Folded into the larger Step 8 rewrite in cleanup chunk 4 (see Bug 4 resolution).
**Verified:** Wipe-and-rescaffold on 2026-04-29 — final report showed `--port 8000` and the parenthetical explanation about prod/dev port distinction. After chunk 4, the same content lives in `MANUAL-TASKS.md` instead of the console output.

---

## Bug 3 — Project location is suggested by README but not enforced by `/start-new-app`

**Found:** 2026-04-28
**Severity:** Documentation discoverability only. Current behavior is correct (path-flexibility is a feature, not a bug); the friction is purely "did the user notice the README's example."
**Where:** README "Start a brand-new project" section vs `/start-new-app` skill behavior.

The README example uses `~/dev/{project}/`, but the skill operates on whatever cwd it's run from. New users might not realize the README's path is illustrative — they may follow it literally without understanding the underlying flexibility.

**Suggested fix:** none. The current behavior is right. Optional enhancement: add a clarifying note in the skill's report — "scaffolded into {pwd} (your current directory)."

**Status:** No action planned. Logged for awareness.

---

## Bug 4 — `/start-new-app` console report doesn't separate manual prerequisites from forward-looking next steps

**Found:** 2026-04-30
**Severity:** UX / documentation. Affects every first-time scaffolding. First-time users hit GitHub Actions failures because deploy-key registration was buried in the console output and easy to miss.
**Where:** `claude-config/skills/start-new-app/SKILL.md` Step 8 (Report).

The console report mixed three different kinds of next-steps under "NEXT" headings:

1. Things to do **before** the project will work in CI/CD (deploy key, secrets — pre-conditions)
2. Things to do **next** in the workflow (run locally, push to GitHub — actions)
3. Things to do **eventually** (deploy to production — future)

These are three different categories with different urgencies. They were all under "NEXT" headings, and the console output gets skipped or scrolled past. Real-world consequence during hello-aqnas testing: the deploy SSH key wasn't registered on the new GitHub repo, and CI failed on its first run.

**Fix:** the skill writes a `MANUAL-TASKS.md` file to the project root and the console report becomes a 3–5 line summary pointing at the file.

**Design decisions:**
- Filename: `MANUAL-TASKS.md` (matches `/run-meeting`'s `1-MANUAL-TASKS.md` naming pattern)
- Gitignore: yes — `MANUAL-TASKS.md` added to the project `.gitignore` template
- Regenerable: no. Keep `/start-new-app` as a one-shot scaffold

### Resolution

**Date:** 2026-05-07 (cleanup chunk 4)
**Change:**
- Created `claude-config/skills/start-new-app/templates/MANUAL-TASKS.md` — 251-line structured checklist with sections for Local dev / GitHub setup / First push / Production server bootstrap / CI/CD verification, plus a "When things go wrong" section.
- Added `MANUAL-TASKS.md` to `claude-config/skills/start-new-app/templates/.gitignore`.
- Rewrote `start-new-app/SKILL.md` Step 8 (formerly "Report") as "Generate `MANUAL-TASKS.md` and emit summary" — short console output points at the file.
- Updated Step 4 to include `MANUAL-TASKS.md` in the always-copied template list and removed the stale `deploy/bootstrap.sh` reference (server-side bootstrap now lives in `infrastructure/server/scripts/`, not per-project).
**Verified:** Spot-checked the rendered file against the skill body — variable substitutions (`{project-name}`, `{project-domain}`, `{port}`, `{pwd}`) line up with what Step 4's substitution pass produces. Not end-to-end tested with `/start-new-app` since hello-aqnas was scaffolded under the old behavior — the next new project will exercise the path.

---

## Bug 5 — Production server IP convenience (set up SSH alias instead of leak detection)

**Found:** 2026-04-30
**Severity:** UX / documentation. Removes the constant friction of typing IPs.
**Where:** Studio README.

Initially considered: add gitleaks IP-pattern detection to catch the production IP in commits. Decided against — too tedious, and putting the IP in a detection rule's regex would itself expose the IP in the public repo.

**Better approach:** teach users to set up `~/.ssh/config` with an alias once. Then every command refers to the alias, never the IP.

**Decisions:**
- Alias name: `aqnas-prod` — vendor-agnostic, scales to multiple environments (could add `aqnas-staging`, `aqnas-dev` later), unambiguous vs the `aqnas` project / user / studio names
- Migration: Option B — if user already has an alias to the same server, add `aqnas-prod` alongside on the same `Host` line. No forced break of existing muscle memory.
- README mentions this generically (no naming `oracle` specifically) — keeps the docs vendor-agnostic

### Resolution

**Date:** 2026-05-12 (cleanup chunk 6)
**Change:**
- Added a new "Step 6 — Configure SSH access to the production server" section to README.md, walking through `~/.ssh/config` setup with `aqnas-prod` alias, generic "if you already have an alias" note, explanation that the alias only works on the dev machine (GitHub Actions still uses the raw IP/DNS via the `SSH_HOST` secret).
- Added one Troubleshooting entry for the "Could not resolve hostname" failure mode.
- Removed vendor-specific naming from `claude-config/skills/systemd-service/SKILL.md` ("cloud VMs like Oracle/AWS/GCP" → "any cloud VM").
- Note: earlier chunks (2, 4) already used `aqnas-prod` throughout `deploy-procedure/SKILL.md`, `infrastructure/server/scripts/README.md`, and the `MANUAL-TASKS.md` template — no rework needed.
**Verified:** Grep-audit confirmed zero remaining "oracle" references in skill bodies (only in this findings doc as historical context, which is intentional).

---

## Bug 6 — Diagnostic-sharing workflow needs guardrails against secret leakage

**Found:** 2026-04-30
**Severity:** High — single mistake can leak production credentials. Realized when the user pasted full `journalctl -u caddy` output that included `CLOUDFLARE_API_TOKEN=...` in plaintext during debugging. Token was rotated immediately.
**Where:** Studio CLAUDE.md, possibly a new skill.

`commit-git` skill protects against secrets in commits. There is no equivalent guidance for sharing logs/diagnostics with Claude or in support contexts. The pattern of "paste the full output of {diagnostic command}" is common but risky when the output includes env vars, config files, or process listings.

**Design decision:** option (c) — short line in CLAUDE.md creating awareness + dedicated skill with the full content.

### Resolution

**Date:** 2026-05-13 (cleanup chunk 7)
**Change:**
- Added one bullet to the existing "Secret hygiene" section in `claude-config/CLAUDE.md` pointing at the new skill.
- Created `claude-config/skills/secret-hygiene/SKILL.md` (121 lines) covering: what never to share regardless of context (private keys, API tokens with format-recognition patterns, OAuth tokens, basic-auth, DB URLs with credentials, server IPs, `.env` contents), a table of commands that commonly leak secrets in their default output (`journalctl --environ`, `systemctl show`, `env`, etc.), redaction patterns using `grep -v` and `sed`, a 6-step "share logs safely" procedure, and an emergency rotation playbook for when a secret leaks.
- Skill body uses `<YOUR_PRODUCTION_IP>` as placeholder in sed examples (consistent with the public/private discipline from Bug 9). Grep-audit during chunk 8 verified no literal production IP anywhere in the studio repo.
**Verified:** Skill frontmatter description includes trigger keywords (debugging, sharing diagnostics, journalctl, env) so Claude auto-loads it in contexts where it's needed.

---

## Bug 7 — `caddy validate` from a plain shell can't see the running service's environment

**Found:** 2026-04-30
**Severity:** Low — once you know, you know. Cost an hour of debugging during hello-aqnas Phase 3 V1.
**Where:** `claude-config/skills/caddy-config/SKILL.md`.

The skill said "always `caddy validate` before reloading." Correct guidance in spirit, but the literal command fails on configs that reference `{env.CLOUDFLARE_API_TOKEN}` because the validate process runs in the user's shell environment, not the systemd-managed service environment.

**Repro:** `sudo caddy validate --config /etc/caddy/Caddyfile` returns "API token '' appears invalid" even though the running Caddy daemon has the token from its drop-in.

### Resolution

**Date:** 2026-05-06 (cleanup chunk 3)
**Change:**
- Rewrote the "Install sequence" section in `caddy-config/SKILL.md`: replaced `caddy validate` with `systemctl reload caddy` (which validates internally with the daemon's environment, then atomically swaps to the new config on success).
- Added an explanatory paragraph about the env-inheritance gotcha and provided an env-sourced workaround for users who genuinely need standalone validation (e.g., pre-commit hooks).
- Updated `deploy-procedure/SKILL.md` debugging section: the "Caddy reload fails" entry now correctly explains that `systemctl reload caddy` does internal validation, and points users at `journalctl -u caddy` for failure details.
**Verified:** `bootstrap-project.sh` (chunk 2) uses `systemctl reload caddy` as step 11; the script passed end-to-end on hello-aqnas's Phase 3 deployment.

---

## Bug 8 — `curl -I` against AQNAS apps returns 405 because FastAPI doesn't auto-implement HEAD

**Found:** 2026-04-30
**Severity:** Low — diagnostic-only. Misleading output during health-checking.
**Where:** Originally flagged as affecting `caddy-config/SKILL.md`, `deploy-procedure/SKILL.md`, and `start-new-app/SKILL.md`.

FastAPI/Starlette doesn't auto-implement HEAD for GET-defined routes unless explicitly added. `curl -I` issues HEAD, gets 405 with a helpful `allow: GET` header, but looks like a server problem at first glance.

### Resolution

**Date:** 2026-05-06 (cleanup chunk 3)
**Change:** Audited the codebase for HEAD-style diagnostic examples (`curl -I`, `curl -fI`, `curl -sI`, `wget --spider`). **Zero matches.** All existing diagnostic examples already use `curl -sSf` or plain `curl` (GET by default). No edits required.
**Verified:** `grep -rn "curl -I\|wget --spider"` across `claude-config/` and `infrastructure/` returned empty. Likely was either fixed during earlier cleanup or never made it into the templates.

---

## Bug 9 — Privacy boundary for studio repo's operational state (cluster)

**Found:** 2026-04-30
**Severity:** Medium — the studio works without these changes, but going public exposes operational state that doesn't need to be public.
**Where:** Multiple files affected.

The studio repo is intended to be public, but `infrastructure/server/ports.conf` documents real production deployments (which projects, which ports). The aggregate effect of public skill docs + workflow templates + ports.conf is more disclosure of operational state than necessary.

**Decision:** Option B — gitignore the real file, ship a `.example` template. Matches `.env` / `.env.example` discipline, minimal change, reversible.

### Resolution

**Date:** 2026-05-07 (cleanup chunk 5)
**Change:**
- Renamed existing `infrastructure/server/ports.conf` (which had real entries) into a fresh `infrastructure/server/ports.conf.example` template — public, format documentation with commented-out illustrative entries marked `# e.g.`, no real allocations.
- Created a new gitignored `infrastructure/server/ports.conf` with the actual entries (`aqnas = 8000`, `kumdo-exam = 8001`, `hello-aqnas = 8010`).
- Added `infrastructure/server/ports.conf` to root `.gitignore` with explanatory comment.
- Updated `allocate-port.sh` to auto-copy from `.example` if real file is missing (fresh-clone case), logging the copy to stderr.
- Updated `setup.sh` with a new step (between gitleaks hook install and tool checks) that auto-copies `.example` → real on first run if real doesn't exist.
- Rewrote the "Canonical copies" section in `port-registry/SKILL.md` to document the three-way split: `.example` (public), `ports.conf` (private), `/etc/caddy/ports.conf` (server).
**Verified:** Smoke-tested `allocate-port.sh` against a fresh tmpdir with only `.example`: script auto-copied template, allocated 8010 for first project, 8011 for second, refused duplicate. Three smoke tests all passed.

---

## Bug 10 — Existing aqnas project diverges from current studio conventions

**Found:** 2026-04-30
**Severity:** Medium — current setup works (aqnas.xyz is live and serving), but diverges from the convention hello-aqnas establishes. Needs reconciliation during Phase 7 (port migration to 8010+) where we'll be touching the deploy config anyway.
**Where:** Oracle production server, `aqnas` service.

Discovered while bootstrapping hello-aqnas. The aqnas project predates several studio conventions and has accumulated drift. Current state on Oracle:

| Aspect | aqnas (current) | Studio convention (hello-aqnas) |
|---|---|---|
| Service user | `aqnas:aqnas` ✓ | `{project}:{project}` ✓ |
| Repo location | `/opt/aqnas/app/` | `/opt/{project}/{project}/` |
| Repo ownership | `deploy:deploy` (deploy fully owns it) | `{project}:{project}` with deploy in the group |
| `deploy` in `aqnas` group | No | deploy in `{project}` group |
| Deploy mechanism | `appleboy/ssh-action` + custom `deploy.sh` script | `webfactory/ssh-agent` + inline workflow |
| GitHub secrets | `SERVER_HOST`, `DEPLOY_KEY` | `SSH_HOST`, `SSH_PRIVATE_KEY` |
| Extra dirs | `backups/`, `.oci/` (manual additions) | None — `data/` only |
| Port | 8000 (legacy) | 8010+ (registry convention) |

**Reconciliation needed during Phase 7:**

1. Rename `/opt/aqnas/app/` → `/opt/aqnas/aqnas/`
2. Add `deploy` to `aqnas` group: `sudo usermod -aG aqnas deploy`
3. Chown the repo from `deploy:deploy` → `aqnas:aqnas` with mode 2775
4. Migrate `deploy.sh` logic into the standard inline workflow (or keep `deploy.sh` if it does AQNAS-specific orchestration the standard pattern doesn't cover — investigate)
5. Update GitHub secrets: rename `SERVER_HOST` → `SSH_HOST`, `DEPLOY_KEY` → `SSH_PRIVATE_KEY` (or keep the old names and note them as legacy)
6. Update workflow file to use `webfactory/ssh-agent` + inline commands
7. Update systemd unit and Caddy config to bind 8010 instead of 8000
8. Decide what to do with `backups/` and `.oci/` — keep, move to `data/`, or formalize as conventions in `project-scaffold`

**Pre-flight check before Phase 7:** read `deploy.sh` to understand what it does. May be doing legitimate work (e.g., backup before deploy, OCI-specific calls) that hello-aqnas's pattern doesn't include. If so, that's a gap in the studio convention, not a flaw in aqnas — possibly worth folding back into `deploy-procedure`.

**Status:** Deferred to Phase 7. Phase 3 (hello-aqnas) didn't depend on aqnas being consistent.

---

## Bug 11 — Bootstrap procedure missing `git config safe.directory` for deploy user

**Found:** 2026-05-04
**Severity:** Blocks CI/CD on every fresh project bootstrap. Each new project hits this on its first CI run after Phase 3 bootstrap.
**Where:** `claude-config/skills/deploy-procedure/SKILL.md`, bootstrap sequence.

When the studio's ownership model is followed (service user owns the repo, deploy has group-write access), git refuses to operate when run as deploy because the `.git/` directory's owner doesn't match the running user. Error:

```
fatal: detected dubious ownership in repository at '/opt/{project}/{project}'
To add an exception for this directory, call:
    git config --global --add safe.directory /opt/{project}/{project}
```

This is git's intentional safety check (introduced for CVE-2022-24765), not a misconfiguration on our part. But the bootstrap procedure doesn't account for it, so every project's first CI run fails until manually patched.

### Resolution

**Date:** 2026-05-04 (manual workaround on Oracle) + 2026-05-05 (cleanup chunk 2 permanent fix)
**Change:**
- Initial workaround during hello-aqnas Phase 3: ran `sudo -u deploy git config --global --add safe.directory /opt/hello-aqnas/hello-aqnas` manually. GitHub Actions deploy succeeded on retry.
- Permanent fix in cleanup chunk 2: `bootstrap-project.sh` step 7 runs `sudo -u deploy git config --global --add safe.directory $REPO_DIR` automatically with a code comment explaining the CVE-2022-24765 context. `deploy-procedure/SKILL.md` was refactored to point at the script as the canonical procedure, and the skill body has a "Why the `git config safe.directory` step exists" subsection explaining the rationale.
**Verified:** Manual workaround unblocked CI on hello-aqnas. The scripted version is bash-syntax-validated but hasn't been run end-to-end yet — first opportunity is the next new project after init push.

---

## Bug 12 — Bootstrap procedure missing sudoers entry for deploy user

**Found:** 2026-05-04
**Severity:** Blocks CI/CD `systemctl restart` step on every fresh project bootstrap.
**Where:** `claude-config/skills/deploy-procedure/SKILL.md`, bootstrap sequence.

CI workflow's deploy step ends with `sudo /bin/systemctl restart $PROJECT`. Without a passwordless sudoers entry for the `deploy` user covering this command, sudo prompts for a password — CI is non-interactive, so the workflow fails with:

```
sudo: a terminal is required to read the password
```

The `deploy-procedure` skill body's "Sudoers entry for deploy" section already documented the right pattern as reference material, but didn't list it as a numbered bootstrap step. Result: every fresh project bootstrap hit this on first CI run.

### Resolution

**Date:** 2026-05-04 (manual workaround on Oracle) + 2026-05-05 (cleanup chunk 2 permanent fix)
**Change:**
- Initial workaround during hello-aqnas Phase 3: created `/etc/sudoers.d/aqnas-studio-deploy` manually via `sudo visudo -f` with the three-line wildcard pattern (`/bin/systemctl restart *`, `/bin/systemctl reload caddy`, `/bin/systemctl status *`).
- Permanent fix in cleanup chunk 2: `init-server.sh` installs the file automatically as part of the one-time-per-server setup. Validates syntax via `visudo -c -f` against a tempfile before installing to the final location (refuses to install on syntax errors — protects against locking out sudo). Updated `deploy-procedure/SKILL.md` "Sudoers entry for deploy" section to point at `init-server.sh` and use the new `aqnas-studio-deploy` filename.
**Verified:** `sudo -u deploy sudo -n /bin/systemctl restart hello-aqnas` returned silently (no password prompt). GitHub Actions deploy completed end-to-end on retry.

**Related discovery — accumulated drift on existing Oracle install (deferred to Phase 7):**

Three pre-existing per-project sudoers files were found during diagnosis (`deploy`, `deploy-aqnas`, `deploy-kumdo-exam`), each with project-specific entries. Notable issues:

- `deploy-kumdo-exam` contains `(kumdo-exam) NOPASSWD: ALL` — over-permissive; should be tightened to only the operations CI actually needs.
- `deploy-aqnas` references `/usr/local/bin/aqnas-deploy-caddy` — a bespoke script not part of studio convention. Investigate whether still used.
- Path mismatch: existing files use `/usr/bin/systemctl`; studio convention uses `/bin/systemctl`. Both work on Ubuntu 24.04 (usr-merge), but they're not equivalent in sudoers — sudoers does literal path matching. Standardize on `/bin/systemctl` during Phase 7 cleanup.

---

## Bug 13 — Studio's `deploy-procedure` doesn't account for project-specific deploy logic

**Found:** 2026-05-04
**Severity:** Low. The current pattern works for hello-aqnas (a minimal test); won't work cleanly for projects with build steps, asset compilation, or auto-syncing infra configs.
**Where:** `claude-config/skills/deploy-procedure/SKILL.md`.

The existing aqnas `deploy.sh` script handles things the studio convention's inline workflow doesn't:

1. **Asset build step** — compiles Tailwind CSS during deploy, with auto-install fallback for the standalone CLI
2. **Conditional Caddy config sync** — diffs `infra/aqnas.caddy` against `/etc/caddy/conf.d/aqnas.caddy`, copies and reloads if changed (instead of requiring manual server-side updates)
3. **Robust health check** — retries with backoff, logs systemctl status on failure for diagnostics

The studio's current `.github/workflows/deploy.yml` template does an inline `git pull + uv sync + systemctl restart + curl /health` flow that's correct for trivial projects but doesn't generalize.

**Fix (deferred to Phase 7 or later):** consider whether `deploy-procedure` should:

- Recommend a `deploy/run.sh` script in the project repo that the workflow calls (so each project can override deploy behavior without changing the workflow)
- Or keep the inline pattern and document escape hatches (when to use a custom script)
- Or split the pattern: minimal projects use inline, complex projects use a script

The aqnas `deploy.sh` is a good reference for what a real project might need.

**Status:** Deferred.

---

## Bug 14 — `allocate-port.sh` regex matched commented-out registry entries

**Found:** 2026-05-07 (during cleanup chunk 5 smoke test)
**Severity:** Latent until commented entries appeared in registry files. Would have caused incorrect port allocations from the next new project onward.
**Where:** `claude-config/skills/port-registry/scripts/allocate-port.sh` line 57.

The "used ports" detection used `grep -oE '=\s*8[0-9]{3}'` against the full registry file. This regex matches both real entries and commented-out entries:

```sh
$ echo "# my-first-app = 8010" | grep -oE '=\s*8[0-9]{3}'
= 8010
```

With the new `ports.conf.example` template introduced by chunk 5 (which has `# e.g. my-first-app = 8010` illustrative entries), `allocate-port.sh` against a freshly-copied registry would consider 8010 and 8011 "used" and skip to 8012.

Surfaced by the chunk 5 smoke test against a tmpdir — caught before shipping.

### Resolution

**Date:** 2026-05-07 (cleanup chunk 5)
**Change:** Added `grep -v '^\s*#'` as the first filter in the pipeline, stripping comment lines before the port-number extraction. Inline comment explains both `grep -v '^\s*#'` and `|| true` (from Bug 1's fix) so future readers see the reasoning for both.

```sh
used_ports=$(grep -v '^\s*#' "$REGISTRY" | grep -oE '=\s*8[0-9]{3}' | grep -oE '8[0-9]{3}' | sort -un || true)
```

**Verified:** Re-ran the chunk 5 smoke test — fresh registry from `.example` allocated 8010 for first project (correct, ignoring commented `# my-first-app = 8010`), 8011 for second project, refused duplicate. Three smoke tests passed.
