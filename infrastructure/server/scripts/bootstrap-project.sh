#!/usr/bin/env bash
# bootstrap-project.sh — bootstrap a new AQNAS project on the production server.
#
# Run once per project. NOT idempotent on user/dir creation (refuses if project
# already exists, to avoid silent overwrites).
#
# What it does (the 13 steps from deploy-procedure):
#   1. Creates the system user {project}
#   2. Adds deploy to the {project} group
#   3. Creates /opt/{project}/{{project},data,.uv-cache}
#   4. Sets ownership to {project}:{project}
#   5. Sets group-write + setgid on shared dirs
#   6. Clones the repo as deploy, then chowns to service user
#   7. Adds git safe.directory exception for deploy (prevents "dubious ownership")
#   8. Generates a stub .env (operator edits with real values)
#   9. Installs systemd unit
#  10. Installs Caddy config
#  11. Validates Caddy via systemctl reload
#  12. Adds entry to /etc/caddy/ports.conf
#  13. Runs first uv sync as deploy
#
# What it does NOT do:
#   - Add the DNS A record in Cloudflare (manual step in the dashboard)
#   - Start the service (operator should verify .env is populated first)
#   - Trigger CI/CD (operator does that by pushing a commit)
#
# Usage:
#   sudo ./bootstrap-project.sh {project-name} {port} {project-domain} [--dry-run]
#
# Example:
#   sudo ./bootstrap-project.sh hello-aqnas 8010 hello-aqnas.aqnas.xyz
#
# Run from the studio repo's root:
#   cd ~/aqnas-studio
#   sudo ./infrastructure/server/scripts/bootstrap-project.sh ...

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
ARGS=()
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=1 ;;
        --help|-h)
            sed -n '2,/^$/p' "$0" | sed 's/^# \?//'
            exit 0
            ;;
        --*) die "Unknown flag: $arg (see --help)" ;;
        *) ARGS+=("$arg") ;;
    esac
done

if [[ ${#ARGS[@]} -ne 3 ]]; then
    die "Usage: $0 <project-name> <port> <project-domain> [--dry-run]"
fi

PROJECT="${ARGS[0]}"
PORT="${ARGS[1]}"
DOMAIN="${ARGS[2]}"

# ---- validate args ----
if ! [[ "$PROJECT" =~ ^[a-z][a-z0-9-]*$ ]]; then
    die "Project name must be kebab-case (lowercase letters, digits, hyphens; start with letter): got '$PROJECT'"
fi

if ! [[ "$PORT" =~ ^[0-9]+$ ]] || (( PORT < 8000 || PORT > 8099 )); then
    die "Port must be a number in 8000–8099: got '$PORT'"
fi

if ! [[ "$DOMAIN" =~ ^[a-z0-9.-]+\.[a-z]+$ ]]; then
    die "Domain must be a valid hostname (e.g. hello-aqnas.aqnas.xyz): got '$DOMAIN'"
fi

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

# ---- locate the studio repo root ----
# Script lives at infrastructure/server/scripts/bootstrap-project.sh; root is 3 levels up
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STUDIO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

if [[ ! -d "$STUDIO_ROOT/claude-config" ]]; then
    die "Could not find studio repo root. Expected at $STUDIO_ROOT, but no claude-config/ there."
fi

ok "Studio root: $STUDIO_ROOT"

# ---- move to a neutral working directory ----
# Everything below uses absolute paths (PROJECT_DIR, REPO_DIR) or BASH_SOURCE-
# derived paths, so cwd is irrelevant to this script's own logic. But the
# per-user subcommands we spawn (e.g. `sudo -u deploy git config ...`) inherit
# this cwd, and git runs repository discovery on startup. If we were launched
# from a dir those users can't traverse (e.g. /home/ubuntu/aqnas-studio, mode
# 750), git aborts with "failed to stat ...: Permission denied" before doing
# anything. Anchoring to / (world-traversable) makes the script runnable from
# any directory.
cd /

PROJECT_DIR="/opt/$PROJECT"
REPO_DIR="$PROJECT_DIR/$PROJECT"

# ============================================================
step "Bootstrap parameters"
# ============================================================
info "Project:       $PROJECT"
info "Port:          $PORT"
info "Domain:        $DOMAIN"
info "Project dir:   $PROJECT_DIR"
info "Repo dir:      $REPO_DIR"
info "Studio root:   $STUDIO_ROOT"
echo

# ============================================================
step "Pre-flight checks"
# ============================================================

# Refuse if project already exists — explicit, no surprises
if id "$PROJECT" >/dev/null 2>&1; then
    die "User '$PROJECT' already exists. Refusing to bootstrap (would overwrite)."
fi

if [[ -d "$PROJECT_DIR" ]]; then
    die "$PROJECT_DIR already exists. Refusing to bootstrap (would overwrite)."
fi

if grep -qE "^${PROJECT}\s*=" /etc/caddy/ports.conf 2>/dev/null; then
    die "$PROJECT is already in /etc/caddy/ports.conf. Refusing to bootstrap."
fi

if [[ ! -f /etc/sudoers.d/aqnas-studio-deploy ]]; then
    die "/etc/sudoers.d/aqnas-studio-deploy not found. Run init-server.sh first."
fi

ok "Project '$PROJECT' is new (no user, no dir, no port reservation)"

# ============================================================
step "1/13 Creating system user '$PROJECT'..."
# ============================================================
run "adduser --system --group --no-create-home --shell /usr/sbin/nologin '$PROJECT'"

# ============================================================
step "2/13 Adding deploy to '$PROJECT' group..."
# ============================================================
run "usermod -aG '$PROJECT' deploy"

# ============================================================
step "3/13 Creating project tree..."
# ============================================================
run "mkdir -p '$PROJECT_DIR'"
run "mkdir -p '$REPO_DIR' '$PROJECT_DIR/data' '$PROJECT_DIR/.uv-cache'"

# ============================================================
step "4/13 Setting ownership..."
# ============================================================
run "chown -R '$PROJECT':'$PROJECT' '$PROJECT_DIR'"

# ============================================================
step "5/13 Setting group-write + setgid on shared dirs..."
# ============================================================
run "chmod 2775 '$REPO_DIR'"
run "chmod 2775 '$PROJECT_DIR/.uv-cache'"

# ============================================================
step "6/13 Cloning repo as deploy..."
# ============================================================
# Clone as the deploy user (whose SSH key is already on GitHub from init-server.sh).
# The directory is owned by {project}:{project} (step 4) with setgid set (step 5),
# so cloned files end up owned by deploy:{project} — group inheritance via setgid.
# The service user has group read/execute access; deploy retains write. The eventual
# steady state after subsequent `git reset --hard` runs in deploy/run.sh matches
# this layout exactly (no ownership flip-flopping).

GITHUB_REPO="git@github.com:yjaquinas/$PROJECT.git"
info "Repo URL: $GITHUB_REPO"

if [[ $DRY_RUN -eq 0 ]]; then
    if ! sudo -u deploy git clone "$GITHUB_REPO" "$REPO_DIR" 2>&1; then
        fail "Clone failed. Common causes:"
        fail "  - Repo doesn't exist on GitHub (create it first at github.com/yjaquinas/$PROJECT)"
        fail "  - deploy user doesn't have access (register its public key)"
        die "Aborting"
    fi
else
    info "[dry-run] sudo -u deploy git clone $GITHUB_REPO $REPO_DIR"
fi

# ============================================================
step "7/13 Adding git safe.directory exceptions..."
# ============================================================
# Without this, git refuses to operate with "dubious ownership". The .git/
# directory ends up owned by deploy:{project} due to setgid, but neither deploy
# nor the service user is the strict owner of every file (CVE-2022-24765 check).
# Both need the exception:
#   - deploy: runs git fetch + reset --hard via deploy/run.sh on every deploy
#   - service user: any manual `sudo -u {project} git ...` operation needs it too
#
# Use --system (writes /etc/gitconfig) rather than per-user --global. The service
# user is created with --no-create-home, so its $HOME is /nonexistent and
# `git config --global` fails with "could not lock config file
# /nonexistent/.gitconfig". A single system-wide entry covers every user that
# touches this repo, with no dependency on per-user home directories. We're
# already running as root here (via sudo), so /etc/gitconfig is writable.
run "git config --system --add safe.directory '$REPO_DIR'"

# ============================================================
step "8/13 Generating stub .env..."
# ============================================================

if [[ $DRY_RUN -eq 0 ]]; then
    sudo -u "$PROJECT" tee "$PROJECT_DIR/.env" > /dev/null <<EOF
# $PROJECT — production environment
# Created by bootstrap-project.sh on $(date -u +%Y-%m-%dT%H:%M:%SZ)
#
# REQUIRED: review and fill in real values before starting the service.
# Mode 600 — only the service user can read this.

APP_ENV=production
LOG_LEVEL=INFO

# SECRET_KEY=  # generate: python -c "import secrets; print(secrets.token_urlsafe(32))"
# DATABASE_PATH=$PROJECT_DIR/data/app.db

# Add project-specific vars below this line
EOF
    chmod 600 "$PROJECT_DIR/.env"
    ok "Wrote stub .env (mode 600)"
    warn "REVIEW $PROJECT_DIR/.env BEFORE STARTING THE SERVICE"
else
    info "[dry-run] Would write stub .env to $PROJECT_DIR/.env (mode 600)"
fi

# ============================================================
step "9/13 Installing systemd unit..."
# ============================================================

SYSTEMD_SRC="$REPO_DIR/infra/$PROJECT.service"
SYSTEMD_DST="/etc/systemd/system/$PROJECT.service"

if [[ ! -f "$SYSTEMD_SRC" ]]; then
    die "Systemd unit not found at $SYSTEMD_SRC — was it generated by /start-new-app?"
fi

run "cp '$SYSTEMD_SRC' '$SYSTEMD_DST'"
run "systemctl daemon-reload"
run "systemctl enable '$PROJECT'"

# ============================================================
step "10/13 Installing Caddy config..."
# ============================================================

CADDY_SRC="$REPO_DIR/infra/$PROJECT.caddy"
CADDY_DST="/etc/caddy/conf.d/$PROJECT.caddy"

if [[ ! -f "$CADDY_SRC" ]]; then
    die "Caddy config not found at $CADDY_SRC — was it generated by /start-new-app?"
fi

run "cp '$CADDY_SRC' '$CADDY_DST'"

# ============================================================
step "11/13 Validating Caddy via reload..."
# ============================================================
# Note: don't use `caddy validate` from a plain shell — it can't see the
# systemd-injected env vars (like CLOUDFLARE_API_TOKEN). systemctl reload
# validates internally with the correct environment.
if [[ $DRY_RUN -eq 0 ]]; then
    if systemctl reload caddy 2>&1; then
        ok "Caddy reloaded (config validated)"
    else
        fail "Caddy reload failed — check journalctl -u caddy"
        warn "Existing sites may still be serving from previous config"
        die "Aborting bootstrap"
    fi
else
    info "[dry-run] systemctl reload caddy"
fi

# ============================================================
step "12/13 Adding port to /etc/caddy/ports.conf..."
# ============================================================
run "echo '$PROJECT = $PORT' >> /etc/caddy/ports.conf"

# ============================================================
step "13/13 Running first uv sync as deploy..."
# ============================================================
if [[ $DRY_RUN -eq 0 ]]; then
    if sudo -u deploy bash -c "cd '$REPO_DIR' && UV_CACHE_DIR='$PROJECT_DIR/.uv-cache' /usr/local/bin/uv sync --frozen" 2>&1; then
        ok "uv sync completed"
    else
        fail "uv sync failed — check pyproject.toml and uv.lock in the repo"
        warn "Bootstrap is otherwise complete; the service won't start until uv sync succeeds"
    fi
else
    info "[dry-run] sudo -u deploy bash -c 'cd $REPO_DIR && UV_CACHE_DIR=... uv sync --frozen'"
fi

# ============================================================
step "Summary"
# ============================================================

if [[ $DRY_RUN -eq 1 ]]; then
    printf '\n%s[DRY-RUN COMPLETE]%s — no changes made.\n' "$c_yellow" "$c_reset"
    printf 'Re-run without --dry-run to apply.\n\n'
    exit 0
fi

cat <<EOF

${c_bold}${c_green}═══════════════════════════════════════════════════════════════${c_reset}
${c_bold}BOOTSTRAP COMPLETE — $PROJECT${c_reset}
${c_bold}${c_green}═══════════════════════════════════════════════════════════════${c_reset}

  Project user:    $PROJECT (system, no login)
  Project dir:     $PROJECT_DIR
  Repo dir:        $REPO_DIR
  Port:            $PORT
  Domain:          $DOMAIN

${c_bold}DO THESE NEXT (manual):${c_reset}

  1. Edit $PROJECT_DIR/.env with real values (currently a stub).

  2. Add DNS A record in Cloudflare:
     - Type: A
     - Name: ${DOMAIN%%.aqnas.xyz}  (e.g. just the subdomain part)
     - IP: <this server's IP>
     - Proxy: on (orange cloud)

  3. Start the service:
       sudo systemctl start $PROJECT
       sudo systemctl status $PROJECT
       curl -sS http://127.0.0.1:$PORT/health

  4. Verify public URL (after DNS propagates, usually <60s):
       curl -sS https://$DOMAIN/health

  5. Trigger CI deploy by pushing a commit to main:
     - Watch GitHub Actions
     - Workflow should now succeed end-to-end

${c_bold}${c_green}═══════════════════════════════════════════════════════════════${c_reset}

EOF
