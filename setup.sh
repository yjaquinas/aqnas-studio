#!/usr/bin/env bash
# aqnas-studio setup script.
#
# What it does (all idempotent — safe to re-run):
#   1. Verifies we're inside an aqnas-studio clone
#   2. Symlinks ~/.claude/ -> {this repo}/claude-config/
#      (if ~/.claude already exists, moves it to ~/.claude.backup-YYYYMMDD-HHMMSS)
#   3. Writes AQNAS_STUDIO_ROOT to your shell rc file (with markers so it can be updated in place)
#   4. Installs a gitleaks pre-commit hook in this repo
#   5. Initializes ports.conf from ports.conf.example if missing
#   6. Checks that required tools are installed
#
# Usage:
#   ./setup.sh

set -euo pipefail

# Resolve the studio root as the absolute path of this script's directory
STUDIO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# -------- output helpers --------
c_reset=$'\033[0m'
c_bold=$'\033[1m'
c_green=$'\033[32m'
c_yellow=$'\033[33m'
c_red=$'\033[31m'
c_cyan=$'\033[36m'

ok()    { printf '  %s✓%s %s\n' "$c_green" "$c_reset" "$1"; }
warn()  { printf '  %s⚠%s %s\n' "$c_yellow" "$c_reset" "$1"; }
fail()  { printf '  %s✗%s %s\n' "$c_red" "$c_reset" "$1"; }
info()  { printf '  %s→%s %s\n' "$c_cyan" "$c_reset" "$1"; }
step()  { printf '\n%s%s%s\n' "$c_bold" "$1" "$c_reset"; }

prompt_yes_no() {
    local msg="$1" answer
    read -rp "  $msg [y/N] " answer
    [[ "$answer" =~ ^[Yy]$ ]]
}

# -------- step 0: sanity check --------
step "Checking repository..."

if [[ ! -d "$STUDIO_ROOT/claude-config" ]]; then
    fail "claude-config/ not found at $STUDIO_ROOT"
    fail "This script must run from inside the aqnas-studio repo."
    exit 1
fi

if [[ ! -d "$STUDIO_ROOT/.git" ]]; then
    warn "No .git directory — this doesn't look like a git clone."
    warn "Continuing anyway, but pre-commit hook install will be skipped."
fi

ok "Repo location: $STUDIO_ROOT"

# -------- step 1: symlink ~/.claude --------
step "Linking ~/.claude to claude-config/..."

CLAUDE_LINK="$HOME/.claude"
TARGET="$STUDIO_ROOT/claude-config"

if [[ -L "$CLAUDE_LINK" ]]; then
    # Already a symlink — check if it points where we expect
    current_target="$(readlink "$CLAUDE_LINK")"
    if [[ "$current_target" == "$TARGET" ]]; then
        ok "Symlink already in place (points to $current_target)"
    else
        warn "~/.claude is a symlink pointing to $current_target"
        warn "Expected: $TARGET"
        if prompt_yes_no "Replace it?"; then
            backup="$HOME/.claude.backup-$(date +%Y%m%d-%H%M%S)"
            mv "$CLAUDE_LINK" "$backup"
            ln -s "$TARGET" "$CLAUDE_LINK"
            ok "Moved old symlink to $backup"
            ok "New symlink: ~/.claude → $TARGET"
        else
            info "Skipped — leaving existing symlink in place"
        fi
    fi
elif [[ -e "$CLAUDE_LINK" ]]; then
    # Real directory or file — back it up, never delete
    backup="$HOME/.claude.backup-$(date +%Y%m%d-%H%M%S)"
    warn "~/.claude exists as a real directory/file"
    info "Will move it to: $backup"
    if prompt_yes_no "Proceed?"; then
        mv "$CLAUDE_LINK" "$backup"
        ok "Moved existing ~/.claude to $backup"
        ln -s "$TARGET" "$CLAUDE_LINK"
        ok "Symlink: ~/.claude → $TARGET"
        info "If you had MCP settings, restore them from $backup"
    else
        info "Skipped — ~/.claude not modified"
    fi
else
    # Doesn't exist — just create the symlink
    ln -s "$TARGET" "$CLAUDE_LINK"
    ok "Symlink: ~/.claude → $TARGET"
fi

# -------- step 2: set AQNAS_STUDIO_ROOT --------
step "Setting AQNAS_STUDIO_ROOT..."

# Detect shell and pick the right rc file
shell_name="$(basename "${SHELL:-/bin/sh}")"
rc_file=""
rc_syntax="export"   # default POSIX-style

case "$shell_name" in
    zsh)
        rc_file="$HOME/.zshrc"
        ;;
    bash)
        # macOS Terminal runs bash as a login shell by default → .bash_profile
        # Linux interactive bash reads .bashrc. Prefer .bashrc if it exists, else .bash_profile.
        if [[ -f "$HOME/.bashrc" ]]; then
            rc_file="$HOME/.bashrc"
        elif [[ -f "$HOME/.bash_profile" ]]; then
            rc_file="$HOME/.bash_profile"
        else
            rc_file="$HOME/.bashrc"  # will be created
        fi
        ;;
    fish)
        rc_file="$HOME/.config/fish/config.fish"
        rc_syntax="set -gx"
        mkdir -p "$(dirname "$rc_file")"
        ;;
    *)
        warn "Shell '$shell_name' not recognized."
        warn "Add this line to your shell's rc file manually:"
        printf '\n      export AQNAS_STUDIO_ROOT="%s"\n\n' "$STUDIO_ROOT"
        rc_file=""
        ;;
esac

if [[ -n "$rc_file" ]]; then
    # Write between markers so we can update in place on re-runs
    marker_start="# >>> aqnas-studio >>>"
    marker_end="# <<< aqnas-studio <<<"

    if [[ "$rc_syntax" == "set -gx" ]]; then
        block="${marker_start}
set -gx AQNAS_STUDIO_ROOT \"${STUDIO_ROOT}\"
${marker_end}"
    else
        block="${marker_start}
export AQNAS_STUDIO_ROOT=\"${STUDIO_ROOT}\"
${marker_end}"
    fi

    if [[ -f "$rc_file" ]] && grep -q "^${marker_start}$" "$rc_file"; then
        # Block exists — update in place
        # Use a portable sed: copy to tmp, replace block, move back
        tmp="$(mktemp)"
        awk -v start="$marker_start" -v end="$marker_end" -v new="$block" '
            BEGIN { in_block = 0; printed = 0 }
            $0 == start { in_block = 1; print new; printed = 1; next }
            in_block && $0 == end { in_block = 0; next }
            in_block { next }
            { print }
        ' "$rc_file" > "$tmp"
        mv "$tmp" "$rc_file"
        ok "Updated AQNAS_STUDIO_ROOT in $rc_file"
    else
        # Append new block
        {
            printf '\n%s\n' "$block"
        } >> "$rc_file"
        ok "Added AQNAS_STUDIO_ROOT to $rc_file"
    fi
fi

# -------- step 3: gitleaks pre-commit hook --------
step "Installing gitleaks pre-commit hook..."

if [[ -d "$STUDIO_ROOT/.git" ]]; then
    hook_file="$STUDIO_ROOT/.git/hooks/pre-commit"
    hook_marker="# aqnas-studio:gitleaks"

    if [[ -f "$hook_file" ]] && grep -q "$hook_marker" "$hook_file"; then
        ok "Pre-commit hook already installed"
    elif [[ -f "$hook_file" ]]; then
        warn "A different pre-commit hook exists at $hook_file"
        warn "Leaving it alone. To enable gitleaks scanning, add this line to it:"
        printf '\n      gitleaks protect --staged --no-banner --redact  # aqnas-studio:gitleaks\n\n'
    else
        cat > "$hook_file" <<'EOF'
#!/usr/bin/env bash
# aqnas-studio:gitleaks
# Scan staged changes for secrets before every commit.
set -e
if ! command -v gitleaks >/dev/null 2>&1; then
    echo "WARN: gitleaks not installed — skipping secret scan."
    echo "      Install: brew install gitleaks (macOS) or sudo apt install gitleaks (Ubuntu)"
    exit 0
fi
gitleaks protect --staged --no-banner --redact
EOF
        chmod +x "$hook_file"
        ok "Installed pre-commit hook at $hook_file"
    fi
else
    warn "Not a git repo — skipping pre-commit hook install"
fi

# -------- step 4: ports.conf bootstrap --------
step "Initializing port registry..."

PORTS_REAL="$STUDIO_ROOT/infrastructure/server/ports.conf"
PORTS_EXAMPLE="$STUDIO_ROOT/infrastructure/server/ports.conf.example"

if [[ -f "$PORTS_REAL" ]]; then
    ok "ports.conf already exists — leaving alone"
elif [[ -f "$PORTS_EXAMPLE" ]]; then
    cp "$PORTS_EXAMPLE" "$PORTS_REAL"
    ok "Created ports.conf from ports.conf.example"
    info "Edit $PORTS_REAL to add your real port allocations"
else
    warn "Neither ports.conf nor ports.conf.example found at $STUDIO_ROOT/infrastructure/server/"
    warn "allocate-port.sh will create one when it first runs, but you can also create one manually"
fi

# -------- step 5: tool checks --------
step "Checking required tools..."

check_tool() {
    local tool="$1" install_hint="$2"
    if command -v "$tool" >/dev/null 2>&1; then
        ok "$tool installed"
    else
        warn "$tool NOT installed — $install_hint"
    fi
}

check_tool git      "likely already installed; if not: brew install git (macOS) or sudo apt install git (Ubuntu)"
check_tool uv       "install: curl -LsSf https://astral.sh/uv/install.sh | sh"
check_tool claude   "install: https://docs.claude.com/en/docs/claude-code"
check_tool gitleaks "install: brew install gitleaks (macOS) or sudo apt install gitleaks (Ubuntu)"

# -------- summary --------
printf '\n%s══════════════════════════════════════════════%s\n' "$c_bold" "$c_reset"
printf '%saqnas-studio setup complete%s\n' "$c_bold" "$c_reset"
printf '%s══════════════════════════════════════════════%s\n' "$c_bold" "$c_reset"

printf '\nStudio root: %s\n' "$STUDIO_ROOT"

printf '\nFor THIS shell session, run:\n\n'
printf '    export AQNAS_STUDIO_ROOT="%s"\n\n' "$STUDIO_ROOT"
printf 'New terminals will pick it up automatically from your rc file.\n'

printf '\nNext steps:\n'
printf '  1. Start Claude Code:  claude\n'
printf '  2. Type /  and confirm studio commands appear\n'
printf '     (/run-meeting, /start-new-app, /commit-git, ...)\n\n'
