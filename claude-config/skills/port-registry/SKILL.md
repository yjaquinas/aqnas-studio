---
name: port-registry
description: Defines the AQNAS port allocation scheme for FastAPI projects running behind Caddy on the production host, covering the reserved range (8000–8099), the two canonical copies of the registry (`$AQNAS_STUDIO_ROOT/infrastructure/server/ports.conf` in the studio repo (default `$AQNAS_STUDIO_ROOT/infrastructure/server/ports.conf`) and `/etc/caddy/ports.conf` on the server), the simple key = value line format (`{project} = {port}`), the first-available allocation rule, reserved entries for well-known internal services (8000–8009 for studio infra, 8010–8089 for projects, 8090–8099 for temporary/scratch), and the rule that reserved ports never conflict with listening sockets (each project's uvicorn binds to 127.0.0.1:{port}, Caddy is the only public listener on 80/443). Use when allocating a port for a new project (usually invoked by start-new-app), debugging a port collision, auditing what's running on the host, syncing the studio registry to the production host, or when the user asks about ports, port allocation, 8000-series, port conflicts, or ports.conf. Contains scripts/allocate-port.sh to find the next available port and append it atomically.
---

# port-registry

Port allocation for AQNAS projects.

## The range: 8000–8099

Every project's uvicorn binds to `127.0.0.1:{port}` on a port in this range. Caddy is the only public listener (80/443); it reverse-proxies `{project-domain}` to the right loopback port.

Sub-ranges:

| Range | Purpose |
|---|---|
| `8000–8009` | Studio infrastructure (reserved for future — monitoring, log shipper, etc.) |
| `8010–8089` | Normal projects — allocate here by default |
| `8090–8099` | Temporary or scratch projects — not expected to persist |

100 ports is more than a one-person studio will ever use; if we hit the ceiling, something's wrong with the project-count, not with the scheme.

## Canonical copies

The registry exists in three places with a deliberate public/private split:

1. **`$AQNAS_STUDIO_ROOT/infrastructure/server/ports.conf.example`** — public template. Tracked in git, ships in the studio repo. Has format documentation and commented-out illustrative entries (marked `# e.g.`). No real allocations.

2. **`$AQNAS_STUDIO_ROOT/infrastructure/server/ports.conf`** — your real allocations. **Gitignored.** Source of truth for `allocate-port.sh`. Contains the actual port→project mapping for your deployments. On a fresh clone, `setup.sh` (or `allocate-port.sh` itself) auto-creates this from `.example` if it doesn't exist.

3. **`/etc/caddy/ports.conf`** — server-side mirror. Created by `init-server.sh`. Updated by `bootstrap-project.sh` during each project's first bootstrap.

The studio repo is public; specific port allocations are operational state that doesn't need to be public — hence the split. The discipline matches `.env` / `.env.example`: the template documents the format, the real file holds your data, only the template is committed.

Format is plain text:

```
# Studio infrastructure (reserved)
# (none yet)

# Projects
aqnas-xyz = 8010
kumdo-exam = 8011

# Scratch (8090–8099)
# (none)
```

Comments start with `#`. Blank lines allowed. One `key = value` per line. Keys are kebab-case project names; values are integers.

## Allocation rule

**First available integer in the target sub-range, scanning ascending.**

For a normal project:
1. Read `$AQNAS_STUDIO_ROOT/infrastructure/server/ports.conf`
2. Parse all `key = value` entries
3. Find the lowest integer in `8010–8089` not already allocated
4. Append the new line: `{project} = {port}`
5. Commit to git with message `chore(ports): reserve {port} for {project}`

Never reuse a port from a retired project for at least 90 days — stale DNS, cached Caddy state, or half-forgotten references can route to the wrong service.

## Script

`${CLAUDE_SKILL_DIR}/scripts/allocate-port.sh` — finds and reserves the next port atomically.

Usage:

```bash
allocate-port.sh {project-name}
```

Behavior:
- Refuses if `{project-name}` is already in the registry
- Refuses if no free port in `8010–8089`
- Appends the entry to `$AQNAS_STUDIO_ROOT/infrastructure/server/ports.conf`
- Prints the allocated port to stdout

The script uses `flock` on the file to prevent race conditions if two `/start-new-app` runs happen simultaneously (unlikely but cheap to defend against).

## Conflict checks

Before deploy, a project should verify its reserved port matches what systemd and Caddy expect:

- `deploy/{project}.service` — `--port {port}` in ExecStart
- `deploy/{project}.caddy` — `reverse_proxy 127.0.0.1:{port}`
- `infrastructure/server/ports.conf` — `{project} = {port}`

All three must agree. A mismatch = 502 at runtime. `bootstrap.sh` should validate this before starting the service.

## Listening vs reserved

"Reserved in `ports.conf`" and "something is listening on the port" are different things. Check both:

```bash
# What's reserved
cat /etc/caddy/ports.conf

# What's actually listening
sudo ss -tlnp | grep -E ':8[0-9]{3}'
```

If a port is reserved but nothing listens on it, the service is stopped or crashed. If something listens on an unreserved port, someone skipped the registry — audit.

## What not to do

- Don't pick a port manually without updating `ports.conf`. The registry is the source of truth; off-book allocations lead to collisions.
- Don't reuse a retired project's port for at least 90 days.
- Don't allocate outside `8000–8099`. Other ranges are used by system services or future infra; stay in the reservation.
- Don't bind uvicorn to `0.0.0.0:{port}` — the port is loopback-only. Public access is Caddy's job.
- Don't commit ports with secrets in comments. `ports.conf` is plain text in a public repo.
- Don't edit `/etc/caddy/ports.conf` on the server directly without syncing back to `$AQNAS_STUDIO_ROOT/infrastructure/server/ports.conf`. The studio repo is source of truth; server copies are derivatives.

## Failure modes

- **Allocation script finds no free port.** The `8010–8089` range is full (highly unlikely). Audit retired projects; reclaim ports unused for 90+ days.
- **502 from Caddy after deploy.** Port mismatch between `.caddy` and `.service`. Grep both files for the port and align.
- **Two services both listening on the same port.** Shouldn't happen if the registry is respected. If it does, the second service fails to start with `address already in use`. Check `ss -tlnp` to see which process holds it; stop the rogue one.
- **`ports.conf` edited on server but not in repo.** Next deploy of the studio repo will overwrite the server's edits. Always edit in repo first, push, then sync.
