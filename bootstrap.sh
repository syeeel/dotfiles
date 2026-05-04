#!/usr/bin/env bash
# Personal dev environment setup for Debian-based containers.
# Idempotent: re-running rewrites managed blocks to current spec.
# Requires: bash, curl. No root/sudo needed.

set -euo pipefail

log()  { printf '\033[1;34m[bootstrap]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[bootstrap]\033[0m %s\n' "$*" >&2; }

MISE_BIN="$HOME/.local/bin/mise"
MISE_SHIMS="$HOME/.local/share/mise/shims"

export PATH="$HOME/.local/bin:$MISE_SHIMS:$PATH"

# --- 1. mise (tool version manager) ---
if [ ! -x "$MISE_BIN" ]; then
  log "Installing mise..."
  curl -fsSL https://mise.run | sh
fi

eval "$("$MISE_BIN" activate bash --shims)"

# --- 2. Declare tools (config.toml is owned by this script) ---
log "Writing ~/.config/mise/config.toml..."
mkdir -p "$HOME/.config/mise"
cat > "$HOME/.config/mise/config.toml" <<'EOF'
# Managed by dotfiles/bootstrap.sh — edits here will be overwritten.
[tools]
lazygit = "latest"
ripgrep = "latest"
fzf     = "latest"
fd      = "latest"
bat     = "latest"
eza     = "latest"
zoxide  = "latest"
gh      = "latest"
# musl variants: statically linked, work on older GLIBC (Debian bookworm etc.)
"github:sxyazi/yazi"      = { version = "latest", exe = "yazi",  matching = "musl" }
"github:dandavison/delta" = { version = "latest", exe = "delta", matching = "musl" }
EOF

log "Installing tools per config.toml..."
if [ -z "${GITHUB_TOKEN:-}" ]; then
  warn "GITHUB_TOKEN not set — GitHub API limit is 60/hr unauthenticated."
  warn "If install fails (e.g. delta), set GITHUB_TOKEN and re-run."
fi
mise install -y
mise prune -y || true   # remove tools no longer in config (e.g. old go)
mise reshim

# --- 3. Shell integration (managed blocks, replaced on every run) ---
detect_rc() {
  case "${SHELL:-}" in
    *zsh) echo "$HOME/.zshrc" ;;
    *)    echo "$HOME/.bashrc" ;;
  esac
}

SHELL_NAME="$(basename "${SHELL:-bash}")"
SHELL_RC="$(detect_rc)"
touch "$SHELL_RC"

# Remove any prior block delimited by start/end markers, then append fresh block.
write_block() {
  local marker_start="$1" marker_end="$2" block="$3"
  if grep -qF "$marker_start" "$SHELL_RC"; then
    awk -v s="$marker_start" -v e="$marker_end" '
      index($0, s) { skip=1 }
      !skip        { print }
      index($0, e) { skip=0; next }
    ' "$SHELL_RC" > "$SHELL_RC.tmp" && mv "$SHELL_RC.tmp" "$SHELL_RC"
  fi
  printf '\n%s\n' "$block" >> "$SHELL_RC"
}

log "Updating $SHELL_RC..."

write_block "# >>> mise" "# <<< mise" "$(cat <<EOF
# >>> mise (managed by dotfiles bootstrap)
export PATH="\$HOME/.local/bin:\$HOME/.local/share/mise/shims:\$PATH"
if command -v mise >/dev/null 2>&1; then
  eval "\$(mise activate ${SHELL_NAME})"
fi
# <<< mise
EOF
)"

write_block "# >>> fzf" "# <<< fzf" "$(cat <<EOF
# >>> fzf key bindings (managed by dotfiles bootstrap)
if command -v fzf >/dev/null 2>&1; then
  if [ -n "\${ZSH_VERSION:-}" ]; then
    source <(fzf --zsh) 2>/dev/null || true
  else
    eval "\$(fzf --bash)" 2>/dev/null || true
  fi
fi
# <<< fzf
EOF
)"

write_block "# >>> zoxide" "# <<< zoxide" "$(cat <<EOF
# >>> zoxide (managed by dotfiles bootstrap)
if command -v zoxide >/dev/null 2>&1; then
  eval "\$(zoxide init ${SHELL_NAME})"
fi
# <<< zoxide
EOF
)"

# --- 4. Verify ---
log "Installed:"
mise ls

log "Sanity check (PATH resolution):"
ok=1
for entry in \
  "lazygit:lazygit" "ripgrep:rg" "fzf:fzf" "fd:fd" "yazi:yazi" \
  "bat:bat" "eza:eza" "zoxide:zoxide" "gh:gh" "delta:delta"; do
  name="${entry%%:*}"; bin="${entry##*:}"
  if path="$(command -v "$bin" 2>/dev/null)"; then
    printf '  ok   %-8s -> %s\n' "$bin" "$path"
  else
    warn "  MISS %-8s (%s) not found" "$bin" "$name"
    ok=0
  fi
done

cat <<EOF

[bootstrap] Done.
[bootstrap] To use the tools in your CURRENT shell, run:
[bootstrap]   exec \$SHELL -l
EOF

[ "$ok" = 1 ]
