#!/usr/bin/env bash
# allocate-port.sh — reserve the next free port for an AQNAS project.
#
# Usage: allocate-port.sh <project-name>
#
# Behavior:
#   - Refuses if <project-name> is already in the registry
#   - Refuses if no free port in 8010–8089
#   - Appends "<project-name> = <port>" to $AQNAS_STUDIO_ROOT/infrastructure/server/ports.conf
#     (default: ~/aqnas-studio/infrastructure/server/ports.conf)
#   - Prints the allocated port to stdout
#
# Registry path resolution (first match wins):
#   1. $AQNAS_PORT_REGISTRY (full path override)
#   2. $AQNAS_STUDIO_ROOT/infrastructure/server/ports.conf
#   3. $HOME/aqnas-studio/infrastructure/server/ports.conf
#
# If the real ports.conf doesn't exist but a .example template does, the
# script auto-copies the template before continuing. This handles the
# fresh-clone case where ports.conf is gitignored.
#
# Uses flock to serialize concurrent runs.

set -euo pipefail

PROJECT="${1:-}"
if [[ -z "$PROJECT" ]]; then
    echo "usage: $(basename "$0") <project-name>" >&2
    exit 64
fi

if ! [[ "$PROJECT" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
    echo "error: project name must be kebab-case (lowercase, hyphens, digits)" >&2
    exit 65
fi

REGISTRY="${AQNAS_PORT_REGISTRY:-${AQNAS_STUDIO_ROOT:-$HOME/aqnas-studio}/infrastructure/server/ports.conf}"
RANGE_START=8010
RANGE_END=8089

# Auto-copy from .example if real registry is missing (fresh-clone case)
if [[ ! -f "$REGISTRY" ]]; then
    EXAMPLE="${REGISTRY}.example"
    if [[ -f "$EXAMPLE" ]]; then
        cp "$EXAMPLE" "$REGISTRY"
        echo "info: created $REGISTRY from $(basename "$EXAMPLE")" >&2
    else
        echo "error: registry not found at $REGISTRY" >&2
        echo "       and no template at $EXAMPLE to bootstrap from" >&2
        exit 66
    fi
fi

# Acquire an exclusive lock on the registry file for the duration of this script
exec 9>"$REGISTRY.lock"
if ! flock -n 9; then
    echo "error: another allocation is in progress" >&2
    exit 75
fi

# Refuse if the project already has a port
if grep -qE "^${PROJECT}\s*=" "$REGISTRY"; then
    existing=$(grep -E "^${PROJECT}\s*=" "$REGISTRY" | head -n1)
    echo "error: ${PROJECT} already reserved: ${existing}" >&2
    exit 67
fi

# Collect already-used ports in the full 8000–8099 reserved range
# `grep -v '^\s*#'` strips comment lines first — without it, commented-out
# entries (like `# e.g. my-first-app = 8010` in the .example template)
# would be treated as already-used ports.
# `|| true` tolerates an empty registry — without it, `set -euo pipefail` aborts
# the script on the very first run when no ports are reserved yet.
used_ports=$(grep -v '^\s*#' "$REGISTRY" | grep -oE '=\s*8[0-9]{3}' | grep -oE '8[0-9]{3}' | sort -un || true)

# Find the first free port in the project sub-range
selected=""
for (( port=RANGE_START; port<=RANGE_END; port++ )); do
    if ! grep -qxF "$port" <<<"$used_ports"; then
        selected="$port"
        break
    fi
done

if [[ -z "$selected" ]]; then
    echo "error: no free port in ${RANGE_START}–${RANGE_END}" >&2
    exit 68
fi

# Append atomically
printf '%s = %d\n' "$PROJECT" "$selected" >> "$REGISTRY"

# Emit only the port on stdout for scripts that capture it
echo "$selected"
