---
name: execute-plan
description: Orchestrates Task Force (project-scope) agents to execute the build tasks defined in a meeting's 3-BUILD-PLAN.md file, respecting task dependencies and running independent tasks in parallel where safe. Never modifies .claude/ — that is update-project-claude's job. Requires that 2-CLAUDE-UPDATES.md has already been applied and that any blockers in 1-MANUAL-TASKS.md are resolved.
disable-model-invocation: true
argument-hint: <path-to-3-BUILD-PLAN.md>
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Task
---

# /execute-plan

Read a `3-BUILD-PLAN.md` and orchestrate TF agents to build it.

## Invocation

`/execute-plan <path>` where `<path>` is the path to a `3-BUILD-PLAN.md` file.

`$ARGUMENTS` contains the path. If empty, abort.

## Preconditions

Before executing, verify each:

1. **Input file exists** and parses. Abort if not.
2. **Sibling `2-CLAUDE-UPDATES.md`** (same meeting directory) has been applied. Heuristic: check that all agents named in `## Tasks` exist in `.claude/agents/`. If any are missing, abort with: "Agents {list} are not loaded. Did you run /update-project-claude and restart?"
3. **Sibling `1-MANUAL-TASKS.md` blockers** are resolved. Read the Blockers section; prompt the CEO to confirm each blocker is done before proceeding. If the CEO says no to any, abort with the unresolved item.
4. **Clean git state** (or acknowledged dirty). Run `git status`; if dirty, ask the CEO whether to proceed or stash first.

## Step 1 — Parse the plan

Extract from `3-BUILD-PLAN.md`:
- Objective
- Success criteria
- Tasks with: name, agents, dependencies, description, acceptance criteria, files, tests
- Out of scope list
- Deploy notes

Build a DAG of tasks from their `Depends on:` fields.

## Step 2 — Plan execution order

- **Sequential chains** — Task B depends on Task A → B runs after A
- **Parallel opportunities** — Tasks with no shared file paths and no dependency → may run in parallel
- **Serial safety** — If two parallel-eligible tasks touch overlapping paths, serialize them

Report the planned order to the CEO before executing:

```
Execution plan:
  1. Task 1: {name} (agent: {agents})
  2. Task 2: {name} (agent: {agents}) — parallel with 3
  3. Task 3: {name} (agent: {agents}) — parallel with 2
  4. Task 4: {name} (agent: {agents}) — after 2 and 3

Proceed?
```

## Step 3 — Execute each task

For each task in order:

1. **Spawn the TF agent(s)** via the Task tool. Hand them:
   - Task name and description
   - Acceptance criteria
   - File paths to touch
   - Test commands that must pass
   - Relevant excerpt of the Objective from the plan (not the whole plan)
2. **Agent does the work** in its own context.
3. **Run tests** named in the task's Tests field. If no tests, run the project default (`uv run pytest` for Python projects).
4. **Verify acceptance criteria.** Each criterion must be objectively observable (file exists, test passes, endpoint returns N, etc.). Don't mark done on vibes.
5. **Report the task outcome** before moving on.

### Multi-agent tasks

When a task lists multiple agents (e.g., `web-ux-designer, web-developer`), run them in handoff order — designer first produces the spec, developer implements against it. Don't run them in parallel on the same task.

### Deploy-related tasks

If the task's Deploy note says systemd change, Caddy change, or port allocation:
- Read the relevant skill (`systemd-service`, `caddy-config`, `port-registry`, `deploy-procedure`) before spawning the devops-engineer
- Hand the skill content to the agent as part of the task brief

## Step 4 — Continuous verification

- After each task, run the project's fast test suite (typically `uv run pytest tests/unit/` or equivalent)
- After the last task, run the full suite including any Playwright tests
- If any test fails, stop. Report the failure. Ask the CEO whether to investigate, retry, or roll back.

## Step 5 — Final report

```
════════════════════════════════════════════════════════════
EXECUTE-PLAN COMPLETE — {plan path}
════════════════════════════════════════════════════════════

TASKS:           {done}/{total}
TESTS:           {passed}/{total}
SUCCESS CRITERIA:
  ✓ {criterion}
  ✓ {criterion}
  ✗ {criterion — why it failed}  (if any)

FILES TOUCHED:   {count} across {N} tasks

NEXT:
  /commit-git   (to stage, scan for secrets, and commit)

If any criterion failed, resolve before committing.
════════════════════════════════════════════════════════════
```

## What this skill never does

- Never modifies `.claude/`. If a task in the plan asks for `.claude/` changes, refuse that task and point to `/update-project-claude`.
- Never commits. `/commit-git` does that.
- Never deploys. Deploy is a manual decision per `deploy-procedure` skill.
- Never expands scope beyond the tasks listed. New work = new meeting.

## Failure modes

- **A TF agent goes off-script** (starts editing files not in the task). Stop the agent, report, and ask the CEO whether to restart the task with tighter constraints.
- **Test failure after a task.** Don't auto-fix. Report and ask. Silent auto-fixes mask bugs.
- **Circular dependency in the plan.** If parsing the DAG detects a cycle, abort and ask the CEO to fix the plan.
- **Agent doesn't exist.** Covered by preconditions, but if it somehow slips through, abort with the missing name.
