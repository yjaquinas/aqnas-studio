# Build Plan — {topic}

> **File 3 of 3** in `MEETING-{date}-{slug}/`
> Prerequisites:
> - `2-CLAUDE-UPDATES.md` applied via `/update-project-claude`
> - Session reloaded (`/exit` → `claude --continue`)
> - Blockers in `1-MANUAL-TASKS.md` resolved
>
> ```
> /execute-plan meetings/MEETING-{date}-{slug}/3-BUILD-PLAN.md
> ```

## Objective

{What we're building and why. 2–4 sentences. Include the user-facing outcome, not just the technical change.}

## Success criteria

- [ ] {observable, testable outcome 1}
- [ ] {observable, testable outcome 2}
- [ ] {observable, testable outcome 3}

## Tasks

### Task 1: {name}

- **Agents:** {comma-separated list of TF agents}
- **Depends on:** none
- **Description:** {what to build, 2–4 sentences}
- **Acceptance criteria:**
  - [ ] {specific, testable}
  - [ ] {specific, testable}
- **Files to touch:** {paths or "TBD by agent"}
- **Tests:** {what must pass}

### Task 2: {name}

- **Agents:** {list}
- **Depends on:** Task 1
- **Description:** {what to build}
- **Acceptance criteria:**
  - [ ] {criterion}
- **Files to touch:** {paths}
- **Tests:** {what must pass}

{Repeat for each task. Keep tasks small enough to verify independently.}

## Out of scope

- {explicit non-goal 1}
- {explicit non-goal 2}

Listing non-goals is deliberate — it prevents scope creep during execution.

## Deploy note

- [ ] Does this task require a production deploy? {yes/no}
- [ ] Does this task require a systemd service change? {yes/no}
- [ ] Does this task require a Caddy config change? {yes/no}
- [ ] Does this task require a new port allocation? {yes/no}

If any yes: coordinate with devops-engineer; reference the relevant skill (`systemd-service`, `caddy-config`, `port-registry`, `deploy-procedure`).
