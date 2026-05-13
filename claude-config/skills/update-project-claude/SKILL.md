---
name: update-project-claude
description: Applies CLAUDE.md, agents, skills, and rules changes from a meeting's 2-CLAUDE-UPDATES.md file to the current project's .claude/ directory. Writes only to .claude/ — never touches application code, templates, or data files. After running, requires /exit and claude --continue so the session reloads with the new configuration before /execute-plan runs.
disable-model-invocation: true
argument-hint: <path-to-2-CLAUDE-UPDATES.md>
allowed-tools: Read, Write, Edit, Glob, Grep, Bash
---

# /update-project-claude

Read a `2-CLAUDE-UPDATES.md` file and apply its changes to `.claude/`.

## Invocation

`/update-project-claude <path>` where `<path>` is a path (absolute or relative) to a `2-CLAUDE-UPDATES.md` file from a meeting directory.

`$ARGUMENTS` contains the path. If empty, abort with: "Provide the path to the 2-CLAUDE-UPDATES.md file."

## Scope

This skill writes only to `.claude/` directories. It **never**:
- Modifies `app/`, `templates/`, `tests/`, `mobile-client/`, `deploy/`, or any application code
- Commits to git (that's `/commit-git`)
- Executes build tasks (that's `/execute-plan`)
- Writes to `meetings/`
- Writes to `infrastructure/` (that's `start-new-app` or direct edit)

If the update file asks for any of the above, refuse that specific section and report it in the summary.

## Target directory

Detect scope:

- If `$(pwd)/.claude/CLAUDE.md` exists → target is `$(pwd)/.claude/` (project scope)
- Else if in `$AQNAS_STUDIO_ROOT` (or `~/aqnas-studio/` if unset) → target is `$AQNAS_STUDIO_ROOT/claude-config/` (studio/C-level scope, via symlink to `~/.claude/`)
- Else abort with: "Not inside a project or the studio repo. cd to the target and retry."

## Step 1 — Parse the update file

Read `2-CLAUDE-UPDATES.md`. Expected sections:

- `## CLAUDE.md changes` — Add / Change / Remove blocks
- `## Agents` — Create / Update blocks
- `## Skills` — Create / Update blocks
- `## Rules (project scope only)` — Create / Update blocks (project scope only; reject at studio scope)

Missing sections are fine; ignore them.

## Step 2 — Apply CLAUDE.md changes

Never overwrite CLAUDE.md wholesale. For each block:

- **Add** — append new content under the named section, preserving existing content
- **Change** — locate the exact quoted existing content and replace it with the new content
- **Remove** — locate the exact quoted existing content and delete it

If the "before" text can't be found verbatim, stop and report: "Couldn't locate the existing text for {section}. Skipping; apply manually."

After edits, verify CLAUDE.md is under 200 lines. If it exceeds 200, flag it and suggest moving content to `rules/` or a new skill.

## Step 3 — Create/update agents

For each agent in the update file:

1. Validate required frontmatter: `name`, `description`
2. `name` must equal the filename stem (hyphens only)
3. `description` must be third person, include what + when
4. Enforce **100-line cap on the agent body** (frontmatter + content). If the spec's body would exceed 100 lines, trim or flag.
5. Model defaults: C-level = `opus`, TF = `sonnet`, unless spec overrides
6. Write to `agents/{name}.md`

At C-level scope, valid agents are the 5 meeting agents + `agent-architect` only. Reject creation of arbitrary new C-level agents without CEO confirmation.

## Step 4 — Create/update skills

For each skill:

1. Create directory `skills/{name}/` if missing
2. Write `skills/{name}/SKILL.md` with valid frontmatter:
   - `name` (max 64 chars, lowercase + numbers + hyphens)
   - `description` (third person, what + when, trigger terms included)
   - Optional: `user-invocable`, `disable-model-invocation`, `allowed-tools`, `model`, `argument-hint`
3. If spec lists bundled files (`templates/`, `scripts/`, `references/`), create those subdirectories and files
4. SKILL.md body target: under 500 lines, ideally 200–300. If it's growing, push detail into `references/`.

At project scope: user-invocable skills (commands) may have side effects, so enforce `disable-model-invocation: true` for anything that writes, deploys, commits, or scaffolds.

## Step 5 — Create/update rules (project scope only)

If the update file has a `## Rules` section and scope is studio/C-level → **reject** the section with: "Rules are project-scope only per AQNAS conventions. Skipping."

Otherwise:

1. Create `rules/` if missing
2. For each rule, validate `paths:` frontmatter uses valid glob patterns (or omit `paths:` for always-loaded)
3. Write to `rules/{name}.md`

## Step 6 — Validate

After all writes:

1. Run a sanity pass on every touched file — YAML frontmatter parses, no trailing `---`, no empty required fields
2. Check for accidental secrets in any new content (email addresses, tokens, IPs). Flag, don't write.
3. List every file created or changed

## Step 7 — Report and prompt restart

Output a summary:

```
════════════════════════════════════════════════════════════
UPDATE-PROJECT-CLAUDE COMPLETE
════════════════════════════════════════════════════════════

CLAUDE.md:   {added: N, changed: N, removed: N}
Agents:      {created: N, updated: N}
Skills:      {created: N, updated: N}
Rules:       {created: N, updated: N}

SKIPPED:
  - {item, reason}  (if applicable)

NEXT:
  /exit
  claude --continue
  /execute-plan {plan path}   (if 3-BUILD-PLAN.md exists)

The session must restart so new/changed agents, skills, and
rules are loaded before /execute-plan runs.
════════════════════════════════════════════════════════════
```

## Failure modes

- **Missing input file.** Abort with clear path and no writes.
- **Malformed update file.** Apply the sections you can parse; report the ones you couldn't.
- **Frontmatter conflicts.** If creating a skill whose name collides with an existing skill, ask before overwriting.
- **Line-cap violations.** Don't silently truncate; flag and let the CEO decide.
- **Public repo secret leak.** If studio scope and the content contains IPs, tokens, or keys — refuse the write entirely and report.
