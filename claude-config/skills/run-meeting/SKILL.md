---
name: run-meeting
description: Orchestrates multi-agent deliberation meetings for the AQNAS studio and produces a MEETING-YYYY-MM-DD-{slug}/ directory with up to three structured output files (1-MANUAL-TASKS.md, 2-CLAUDE-UPDATES.md, 3-BUILD-PLAN.md) plus an end-of-meeting CEO briefing. Supports a `mode-auto-on` flag for delegated deliberation where agents iterate up to 4 rounds without pausing for the CEO.
disable-model-invocation: true
argument-hint: [mode-auto-on] <topic>
allowed-tools: Read, Write, Bash, Task, Glob, Grep
---

# /run-meeting

Orchestrate C-level agent deliberation and produce structured outputs.

## Invocation

- `/run-meeting <topic>` — **default mode**, CEO-driven. Agents present positions each round, then pause for CEO input.
- `/run-meeting mode-auto-on <topic>` — **delegation mode**. Agents deliberate up to 4 rounds on their own, only interrupting the CEO for true preference decisions (e.g., "do you prefer A's approach or B's?").

`$ARGUMENTS` contains the full argument string. If the first token is exactly `mode-auto-on`, strip it and treat the rest as the topic; otherwise the whole string is the topic. The flag is deliberately unusual (`mode-auto-on` rather than just `auto`) so a topic that happens to start with the word "auto" (e.g., "auto-complete feature") doesn't accidentally trigger delegation mode.

## Step 0 — Preflight

1. **Confirm session state.** Regular mode, not plan mode (plan mode conflicts with deliberation). If in plan mode, ask the CEO to exit before proceeding.
2. **Confirm /effort high** is set. If unclear, ask.
3. **Detect meeting location:**
   - If `$(pwd)/.claude/CLAUDE.md` exists → `MEETING_DIR={cwd}/meetings/`
   - Else → `MEETING_DIR="${AQNAS_STUDIO_ROOT:-$HOME/aqnas-studio}/meetings/"`
4. **Generate directory name:** `MEETING-$(date +%Y-%m-%d)-<slug>` where `<slug>` is a 2–4 word kebab-case distillation of the topic.
5. **Create the meeting directory immediately.** The directory is always created; output files are only created if they accrue content.

## Step 1 — Agent selection

Not every meeting needs every agent. Cost matters ($5–20/meeting × 4 rounds of Opus). Pick only agents with skin in the game:

| Signal in the topic | Agents to include |
|---|---|
| Product decisions, user research, growth, positioning | product-strategist |
| System design, database schema, feasibility, stack choice | technical-architect |
| Infrastructure, deploy, server, cost, hosting, Caddy, systemd | devops-engineer |
| UX, visual direction, brand identity, copy voice | design-lead |
| Privacy, licensing, compliance, secrets, auth | security-legal |

For simple topics, 2–3 agents is correct. For full product meetings, use all 5. `agent-architect` is a utility — only include when the meeting explicitly involves writing or revising project-scope agents, commands, or skills.

Before spawning, announce the roster to the CEO: "Convening this meeting: {list}. Proceed?"

## Step 2 — Deliberation

### Default mode (CEO-driven)

Each round:
1. Each agent presents position (short — 3–5 bullets per agent, not essays).
2. **Pause.** Summarize disagreement and ask CEO: clarify intent, run another round, or finalize.
3. CEO response drives the next round.

Max rounds: 4. If consensus hasn't emerged by round 4, write a CEO-decision block into the meeting outputs flagging the unresolved question.

### Auto mode (`mode-auto-on`)

Agents iterate 1–4 rounds without pausing. Only interrupt the CEO when:
- An agent explicitly flags a preference question ("this is a taste call")
- Two agents disagree on a security or cost matter that has no defensible default
- Scope creep emerges that changes the meeting's subject

Otherwise, converge silently and produce outputs at the end.

### How agents talk to each other

Subagents don't share context with each other automatically. When spawning round N, hand each agent:
- The topic
- Their prior position (if round > 1)
- Other agents' positions from round N-1
- Any CEO input since last round

Keep hand-offs compact — agents don't need transcripts, just the load-bearing points.

## Step 3 — Generate outputs

Three possible output files. **Only create a file if it has content.** The directory always exists; empty files don't.

- `1-MANUAL-TASKS.md` — work the CEO must do themselves (provision GitHub secrets, purchase domains, manual DNS, sign contracts). If none, skip.
- `2-CLAUDE-UPDATES.md` — changes to the project's `.claude/` config (CLAUDE.md edits, new/updated agents, new/updated skills, new/updated rules). If none, skip.
- `3-BUILD-PLAN.md` — code work TF agents will execute via `/execute-plan`. If the meeting is pure strategy with no build work, skip.

Templates live in `${CLAUDE_SKILL_DIR}/templates/`:
- `${CLAUDE_SKILL_DIR}/templates/1-MANUAL-TASKS.md`
- `${CLAUDE_SKILL_DIR}/templates/2-CLAUDE-UPDATES.md`
- `${CLAUDE_SKILL_DIR}/templates/3-BUILD-PLAN.md`

Copy the relevant templates into the meeting directory, fill them in, then delete unused sections.

### Filling guidelines

- **1-MANUAL-TASKS.md blockers.** If a manual task blocks a build task, say so explicitly: "Task 4 in 3-BUILD-PLAN.md is blocked until GitHub Secret STRIPE_API_KEY is set."
- **2-CLAUDE-UPDATES.md specificity.** Never say "update CLAUDE.md to be clearer." Name the section, quote the before, write the after.
- **3-BUILD-PLAN.md dependencies.** Every task names the TF agent(s) responsible, acceptance criteria, and dependencies on other tasks. No acceptance criteria = task is underspecified.

## Step 4 — CEO briefing

End every run-meeting invocation with a briefing. Format:

```
════════════════════════════════════════════════════════════
MEETING COMPLETE — MEETING-{date}-{slug}/
════════════════════════════════════════════════════════════

OUTPUTS:
  1. 1-MANUAL-TASKS.md    → {N} tasks for you (start now)
  2. 2-CLAUDE-UPDATES.md  → {summary}
  3. 3-BUILD-PLAN.md      → {N} build tasks

EXECUTION ORDER:
  □ Start 1-MANUAL-TASKS.md items immediately
  □ /update-project-claude meetings/MEETING-*/2-CLAUDE-UPDATES.md
  □ /exit  →  claude --continue
  □ /execute-plan meetings/MEETING-*/3-BUILD-PLAN.md
  □ /commit-git

BLOCKERS:
  - {manual task} blocks {build task} (if applicable)

TOKENS USED: ~{estimate} across {N} rounds
════════════════════════════════════════════════════════════
```

Omit rows for files that weren't created.

## Git behavior

- **Project meetings** (written to `{project}/meetings/`) — tracked in git. Don't `git add` here; let the CEO decide when to commit.
- **Studio meetings** (written to `$AQNAS_STUDIO_ROOT/meetings/`; default `~/aqnas-studio/meetings/`) — gitignored. Never committed. Still on disk for backup.

## What this skill never does

- Never modifies `.claude/` directly. `/update-project-claude` does that.
- Never writes code. `/execute-plan` does that.
- Never commits to git. `/commit-git` does that.
- Never bypasses CEO on cost, scope, or security decisions.

## Failure modes to watch

- **Agent consensus on a bad idea.** Agents can agree and still be wrong. If all 5 agree and something feels off, flag it in the CEO briefing rather than treating consensus as correctness.
- **Scope creep.** If deliberation drifts from the stated topic, stop the round and ask the CEO whether to re-scope or return.
- **Analysis paralysis.** 4 rounds is a ceiling, not a target. If round 2 converges, stop at round 2.
