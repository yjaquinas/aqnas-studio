---
name: commit-git
description: Reviews staged and unstaged changes, runs gitleaks explicitly to scan for secrets before committing (defense in depth alongside the pre-commit hook), groups related changes into logical commits, and generates one-line conventional commit messages (with optional parenthetical reference). Refuses to commit if secrets are detected, if forbidden files are staged (.env, SSH keys, .key, .pem, credentials.json, or files containing production server IPs), or with --no-verify.
disable-model-invocation: true
argument-hint: [optional-message-hint]
allowed-tools: Bash(git:*), Bash(gitleaks:*), Read, Grep
---

# /commit-git

Stage-review, secret-scan, and commit.

## Invocation

`/commit-git` — no arguments needed. An optional message hint after the command is treated as a nudge, not a verbatim message (e.g., `/commit-git fix auth` → message generated with "fix auth" as theme).

`$ARGUMENTS` if present is a hint.

## Step 1 — Survey state

```bash
git status --short
git diff --stat
git diff --stat --staged
```

Report what's staged, unstaged, and untracked. If nothing to commit, abort.

## Step 2 — Stage review

If there are unstaged changes, ask the CEO which to include. Options:
- Stage all (`git add -A`)
- Stage modified only (`git add -u`)
- Stage specific files (CEO names them)
- Leave as-is (commit only what's already staged)

## Step 3 — Secret scan (MANDATORY — NEVER SKIP)

Run **two** scans. This is defense in depth with the pre-commit hook, which will run the same scan again at commit time.

### Scan 3a — gitleaks on staged diff

```bash
gitleaks protect --staged --no-banner --redact
```

If gitleaks reports findings → **abort immediately**. Display the redacted findings and tell the CEO:

```
GITLEAKS FOUND {N} SECRET(S). COMMIT ABORTED.

Review the findings above, remove the secret(s), and re-stage.
If the match is a false positive, add an entry to .gitleaks.toml
in the repo root and retry.
```

Do not proceed. Do not offer to bypass.

### Scan 3b — Forbidden filename check

Regardless of gitleaks, reject these file patterns in the staged set:

- `.env` (not `.env.example` or `.env.test`)
- `*.key`, `*.pem`, `*.pfx`, `*.p12`
- `id_rsa`, `id_ed25519`, `*_rsa`, `*_ed25519`
- `credentials.json`, `service-account*.json`
- Any file containing the production server's literal IP (grep the staged diff)

If any match → abort with the filename(s) and reason. Do not commit.

## Step 4 — Group and message

Examine the staged diff. Decide whether this is one commit or several:

- **One commit** — all changes serve one purpose (one feature, one fix, one refactor)
- **Several commits** — changes touch unrelated concerns (fix + new feature, or refactor + bug fix). Offer to split.

For each commit, generate a **conventional commit** message — one line subject only:

```
<type>(<scope>): <short subject>
```

Types: `feat`, `fix`, `refactor`, `docs`, `style`, `test`, `chore`, `build`, `ci`, `perf`.

Scope examples: `auth`, `web`, `mobile`, `deploy`, `infra`, `brand`.

Subject rules:
- Imperative mood ("add", not "added" or "adds")
- Under 72 characters (one line, no body)
- No trailing period
- Lowercase start (except proper nouns)

If the CEO gave a hint in `$ARGUMENTS`, incorporate it.

**Optional short description:** If context warrants (e.g., references a meeting or external ticket), append a brief parenthetical note on the same line, keeping total under 100 characters:

```
feat(auth): add email/password login (refs MEETING-2026-04-16-user-auth)
```

Prefer one-liners. Only add a parenthetical when it clarifies provenance or dependency.

## Step 5 — Confirm

Show the CEO:

```
STAGED FILES ({N}):
  M  app/routes/auth.py
  A  tests/test_auth.py
  M  CLAUDE.md

MESSAGE:

feat(auth): add email/password login with session cookies (refs MEETING-2026-04-16-user-auth)

Commit? (y / edit / abort)
```

Options:
- `y` — proceed
- `edit` — open the message for CEO edit (use `git commit -e` workflow)
- `abort` — no commit, no side effects

## Step 6 — Commit

```bash
git commit -m "..."
```

**Never** `--no-verify`. The pre-commit hook should run gitleaks a second time. If the hook fails, the commit is correctly blocked — investigate, don't bypass.

**Never** `--amend` unless the CEO explicitly asks. Amending rewrites history and surprises collaborators (even solo CEOs using multiple machines).

## Step 7 — Report

```
════════════════════════════════════════════════════════════
COMMIT COMPLETE
════════════════════════════════════════════════════════════

COMMIT:   {hash-short}  {subject}
BRANCH:   {branch}
FILES:    {N} changed
SECRETS:  none detected (2 scans passed)

NEXT:
  git push origin {branch}   (when ready)
════════════════════════════════════════════════════════════
```

Do not push automatically. Push is a separate decision — the CEO may want to review locally first, or the branch may not be ready.

## Hard rules

- Never commit with `--no-verify`
- Never commit `.env`, `.key`, `.pem`, `id_rsa`, `credentials.json`
- Never commit the production server's IP address (it belongs in `~/.ssh/config` or `.env`, never in the repo)
- Never force-push anywhere
- Never commit directly to `main` on projects that have a release workflow — use a branch and PR, unless the CEO explicitly confirms main is the working branch
- Never rewrite shared history (`rebase -i` on already-pushed commits) without CEO confirmation

## Failure modes

- **Gitleaks not installed.** Report: "gitleaks is required but missing. Install via `brew install gitleaks` (Mac) or the official release binary on Linux." Abort.
- **Pre-commit hook missing.** Warn but proceed — the explicit scan in Step 3 is the primary safety net. Flag for the CEO to reinstall the hook afterward.
- **Gitleaks false positive.** Guide the CEO to create/edit `.gitleaks.toml` with a targeted allowlist entry. Don't teach bypass patterns like `--no-verify`.
- **Huge diff.** If the staged diff is over 1000 lines, offer to split into smaller logical commits before proceeding.
