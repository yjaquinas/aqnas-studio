#!/usr/bin/env bash
# init-server.sh — initialize a server for AQNAS project hosting.
#
# Run once per server. Idempotent — safe to re-run.
#
# What it does:
#   1. Verifies prerequisites (uv, gitleaks, caddy, git)
#   2. Verifies the deploy user exists with expected setup
#   3. Installs /etc/sudoers.d/aqnas-studio-deploy with the wildcard pattern
#      (passwordless sudo for deploy on systemctl restart/reload/status)
#   4. Confirms Caddy's Cloudflare token is configured (for DNS challenge)
#   5. Creates /etc/caddy/ports.conf (server-side port registry)
#
# What it does NOT do:
#   - Install caddy/uv/gitleaks (operator responsibility — version-pinning matters)
#   - Create the deploy user (assumes existing setup)
#   - Configure SSH keys for deploy (assumes existing setup)
#
# Usage:
#   sudo ./init-server.sh [--dry-run]
#
# Run from the studio repo's root, e.g.:
#   sudo ./infrastructure/server/scripts/init-server.sh

set -euo pipefail

# ---- output helpers ----
c_reset=$'\033[0m'; c_bold=$'\033[1m'
c_green=$'\033[32m'; c_yellow=$'\033[33m'; c_red=$'\033[31m'; c_cyan=$'\033[36m'

ok()    { printf '  %s✓%s %s\n'  "$c_green"  "$c_reset" "$1"; }
warn()  { printf '  %s⚠%s %s\n'  "$c_yellow" "$c_reset" "$1"; }
fail()  { printf '  %s✗%s %s\n'  "$c_red"    "$c_reset" "$1"; }
info()  { printf '  %s→%s %s\n'  "$c_cyan"   "$c_reset" "$1"; }
step()  { printf '\n%s%s%s\n'    "$c_bold"   "$1"      "$c_reset"; }
die()   { fail "$1"; exit 1; }

# ---- args ----
DRY_RUN=0
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=1 ;;
        --help|-h)
            sed -n '2,/^$/p' "$0" | sed 's/^# \?//'
            exit 0
            ;;
        *) die "Unknown argument: $arg (see --help)" ;;
    esac
done

# ---- run-as-root check ----
if [[ $EUID -ne 0 ]]; then
    die "This script must run as root (use sudo)"
fi

# ---- helper: run-or-print ----
run() {
    if [[ $DRY_RUN -eq 1 ]]; then
        printf '    %s[dry-run]%s %s\n' "$c_yellow" "$c_reset" "$*"
    else
        eval "$@"
    fi
}

# ============================================================
step "1. Checking prerequisites..."
# ============================================================

declare -A required_tools=(
    [git]="apt install git"
    [uv]="curl -LsSf https://astral.sh/uv/install.sh | sh, then move to /usr/local/bin/"
    [caddy]="see https://caddyserver.com/docs/install"
    [gitleaks]="apt install gitleaks (Ubuntu 24.04+) or download from https://github.com/gitleaks/gitleaks/releases"
)

missing=0
for tool in "${!required_tools[@]}"; do
    if command -v "$tool" >/dev/null 2>&1; then
        ok "$tool: $(command -v "$tool")"
    else
        fail "$tool: not installed (${required_tools[$tool]})"
        missing=$((missing + 1))
    fi
done

if [[ $missing -gt 0 ]]; then
    die "$missing required tool(s) missing — install and re-run"
fi

# uv-specific path check (the systemd template hardcodes /usr/local/bin/uv)
if [[ "$(command -v uv)" != "/usr/local/bin/uv" ]]; then
    warn "uv is at $(command -v uv), but systemd template expects /usr/local/bin/uv"
    warn "Either symlink it or update the template ExecStart in systemd-service skill"
fi

# ============================================================
step "2. Verifying deploy user..."
# ============================================================

if ! id deploy >/dev/null 2>&1; then
    fail "User 'deploy' does not exist."
    info "Create with:"
    info "  sudo adduser deploy"
    info "  sudo -u deploy mkdir -p /home/deploy/.ssh && sudo -u deploy chmod 700 /home/deploy/.ssh"
    info "  sudo -u deploy ssh-keygen -t ed25519 -C deploy@\$(hostname)"
    info "  Add deploy's public key to GitHub (account-level or per-repo deploy keys)"
    die "Aborting — deploy user is required"
fi

deploy_groups=$(id -nG deploy)
ok "deploy user exists, groups: $deploy_groups"

# Sanity: deploy should NOT be in sudo (group-level sudo is too broad)
if id -nG deploy | tr ' ' '\n' | grep -qx sudo; then
    warn "deploy is in the 'sudo' group — this is broader than the studio convention"
    warn "Convention: deploy gets specific NOPASSWD entries, not blanket sudo access"
fi

# Sanity: deploy should have an SSH key
if [[ ! -f /home/deploy/.ssh/id_ed25519 && ! -f /home/deploy/.ssh/id_rsa ]]; then
    warn "deploy has no SSH key at ~/.ssh/id_ed25519 or ~/.ssh/id_rsa"
    warn "deploy needs a key to git-pull from GitHub during deploys"
fi

# ============================================================
step "3. Installing aqnas-studio-deploy sudoers file..."
# ============================================================

SUDOERS_FILE="/etc/sudoers.d/aqnas-studio-deploy"

if [[ -f "$SUDOERS_FILE" ]]; then
    ok "$SUDOERS_FILE already exists — checking content"
    if grep -q "Managed by aqnas-studio" "$SUDOERS_FILE"; then
        ok "Marker found — file appears to be ours"
    else
        warn "File exists but doesn't have the aqnas-studio marker comment"
        warn "Leaving alone. Inspect manually: cat $SUDOERS_FILE"
    fi
else
    info "Creating $SUDOERS_FILE"

    # Write to a tmp file and validate before installing
    TMP_FILE=$(mktemp)
    cat > "$TMP_FILE" <<'EOF'
# Managed by aqnas-studio.
# Grants the deploy user passwordless sudo for systemctl operations needed by CI/CD.
# Wildcards cover all current and future projects without per-project entries.

deploy ALL=(root) NOPASSWD: /bin/systemctl restart *
deploy ALL=(root) NOPASSWD: /bin/systemctl reload caddy
deploy ALL=(root) NOPASSWD: /bin/systemctl status *
EOF

    # Validate via visudo before moving into place — bad sudoers can lock out sudo
    if [[ $DRY_RUN -eq 1 ]]; then
        info "[dry-run] Would install sudoers file with content:"
        sed 's/^/      /' "$TMP_FILE"
    else
        if ! visudo -c -f "$TMP_FILE" >/dev/null 2>&1; then
            rm "$TMP_FILE"
            die "Sudoers syntax check failed — refusing to install"
        fi
        install -m 0440 "$TMP_FILE" "$SUDOERS_FILE"
        rm "$TMP_FILE"
        ok "Installed $SUDOERS_FILE (mode 0440)"
    fi
fi

# Verify it works (skip in dry-run)
if [[ $DRY_RUN -eq 0 ]]; then
    if sudo -u deploy sudo -n -l 2>/dev/null | grep -q "/bin/systemctl restart \*"; then
        ok "deploy can run 'sudo /bin/systemctl restart *' without password"
    else
        warn "deploy doesn't have the expected systemctl permission — check sudoers files manually:"
        warn "  sudo -u deploy sudo -n -l | grep systemctl"
    fi
fi

# ============================================================
step "4. Verifying Caddy Cloudflare token..."
# ============================================================

if systemctl show caddy -p Environment 2>/dev/null | grep -q "CLOUDFLARE_API_TOKEN="; then
    # Don't print the value — never echo secrets
    ok "Caddy has CLOUDFLARE_API_TOKEN configured"
else
    warn "Caddy doesn't have CLOUDFLARE_API_TOKEN in its environment"
    warn "TLS DNS challenge will fail without it"
    info "Configure with:"
    info "  sudo mkdir -p /etc/systemd/system/caddy.service.d"
    info "  sudo nano /etc/systemd/system/caddy.service.d/override.conf"
    info "  Content:"
    info "    [Service]"
    info "    Environment=\"CLOUDFLARE_API_TOKEN=<your-token>\""
    info "  sudo systemctl daemon-reload && sudo systemctl restart caddy"
fi

# ============================================================
step "5. Creating /etc/caddy/ports.conf (server-side port registry)..."
# ============================================================

CADDY_PORTS_CONF="/etc/caddy/ports.conf"

if [[ -f "$CADDY_PORTS_CONF" ]]; then
    ok "$CADDY_PORTS_CONF already exists"
else
    info "Creating $CADDY_PORTS_CONF"

    if [[ $DRY_RUN -eq 1 ]]; then
        info "[dry-run] Would create with header comment + empty body"
    else
        cat > "$CADDY_PORTS_CONF" <<'EOF'
# AQNAS port registry (server-side mirror of $AQNAS_STUDIO_ROOT/infrastructure/server/ports.conf)
#
# Format: {project} = {port}
# Range: 8000–8099
# Sub-ranges: 8000–8009 (studio), 8010–8089 (projects), 8090–8099 (scratch)
#
# Updated by bootstrap-project.sh during each project's first bootstrap.

EOF
        chmod 644 "$CADDY_PORTS_CONF"
        ok "Created $CADDY_PORTS_CONF (header only — bootstrap-project.sh appends entries)"
    fi
fi

# ============================================================
step "Summary"
# ============================================================

if [[ $DRY_RUN -eq 1 ]]; then
    printf '\n%s[DRY-RUN COMPLETE]%s — no changes made.\n' "$c_yellow" "$c_reset"
    printf 'Re-run without --dry-run to apply.\n\n'
else
    printf '\n%s%sServer initialization complete.%s\n' "$c_bold" "$c_green" "$c_reset"
    printf '\nNext: run bootstrap-project.sh once per project.\n'
    printf '  sudo ./bootstrap-project.sh {project-name} {port} {project-domain}\n\n'
    printf 'See infrastructure/server/scripts/README.md for details.\n\n'
fi
