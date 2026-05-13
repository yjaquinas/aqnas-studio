# Claude Code Updates — {topic}

> **File 2 of 3** in `MEETING-{date}-{slug}/`
> Run before `3-BUILD-PLAN.md`. Updates `.claude/` only; no code changes here.
>
> ```
> /update-project-claude meetings/MEETING-{date}-{slug}/2-CLAUDE-UPDATES.md
> /exit
> claude --continue
> ```
>
> The `/exit` + `claude --continue` step is mandatory — the session must reload
> to pick up new/changed agents, commands, and skills before `/execute-plan` runs.

## CLAUDE.md changes

### Add

Under section `## {section}`:

```markdown
{new content}
```

### Change

Under section `## {section}`, replace:

> {existing content, quoted verbatim}

with:

> {new content}

### Remove

Under section `## {section}`, remove:

> {existing content, quoted verbatim}

If no changes, delete this section.

## Agents

### Create `agents/{agent-name}.md`

- **Role:** {one sentence}
- **Model:** sonnet / opus
- **Tools:** {comma-separated list, or omit to inherit}
- **Body outline:**
  - {key instruction 1}
  - {key instruction 2}
  - Relevant skills to read: {skill names}

### Update `agents/{agent-name}.md`

{what to change and why}

If no changes, delete this section.

## Skills

### Create `skills/{skill-name}/`

- **Description (what + when):** {full description for frontmatter}
- **user-invocable:** true / false
- **disable-model-invocation:** true / false
- **allowed-tools:** {space-separated list}
- **Body outline:**
  - {section 1}
  - {section 2}
- **Bundled files:** {templates/, scripts/, references/ — list or "none"}

### Update `skills/{skill-name}/`

{what to change and why}

If no changes, delete this section.

## Rules (project scope only)

### Create `rules/{rule-name}.md`

- **Paths:** {glob patterns, or "none — always loads"}
- **Content outline:**
  - {rule 1}
  - {rule 2}

If no changes, delete this section.
