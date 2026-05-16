#!/usr/bin/env bash
# Personal dev environment setup for Debian-based containers.
# Idempotent: re-running rewrites managed blocks to current spec.
# Requires: bash, curl. No root/sudo needed.

set -euo pipefail

log()  { printf '\033[1;34m[bootstrap]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[bootstrap]\033[0m %s\n' "$*" >&2; }

usage() {
  cat <<'USAGE'
Usage: bootstrap.sh [--lsp <langs>]

Options:
  --lsp <langs>   Comma-separated LSP servers to install via mise.
                  Choices: go, python, ts, all
                  Examples: --lsp go,ts
                            --lsp all

LSP is set up using Neovim 0.11+ native vim.lsp.config (no plugin manager).
USAGE
}

LSP_LANGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --lsp)     shift; IFS=',' read -ra LSP_LANGS <<< "${1:-}"; shift ;;
    --lsp=*)   IFS=',' read -ra LSP_LANGS <<< "${1#--lsp=}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *)         warn "Unknown argument: $1"; usage; exit 1 ;;
  esac
done

# Expand 'all' and validate. Length-gated for portability across bash
# versions that fault on empty-array expansion under `set -u`.
if (( ${#LSP_LANGS[@]} > 0 )); then
  for l in "${LSP_LANGS[@]}"; do
    if [[ "$l" == "all" ]]; then
      LSP_LANGS=(go python ts)
      break
    fi
  done
  for l in "${LSP_LANGS[@]}"; do
    case "$l" in
      go|python|ts) ;;
      *) warn "Unknown LSP lang: $l (valid: go, python, ts, all)"; exit 1 ;;
    esac
  done
fi

has_lsp() {
  local target=$1 l
  (( ${#LSP_LANGS[@]} == 0 )) && return 1
  for l in "${LSP_LANGS[@]}"; do
    [[ "$l" == "$target" ]] && return 0
  done
  return 1
}

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
{
  cat <<'EOF'
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
neovim  = "latest"
# musl variants: statically linked, work on older GLIBC (Debian bookworm etc.)
# - asset_pattern: explicit format suffix to exclude .deb (which also contains "musl")
# - version_prefix = "": delta tags are bare "0.19.2", not "v0.19.2"
"github:sxyazi/yazi"      = { version = "latest", exe = "yazi",  asset_pattern = "*linux-musl.zip" }
"github:dandavison/delta" = { version = "latest", exe = "delta", asset_pattern = "*linux-musl.tar.gz", version_prefix = "" }
EOF

  # LSP servers (opt-in via --lsp). pyright/ts_ls assume node is on PATH (e.g. node:*-slim base).
  if has_lsp go; then
    cat <<'EOF'
go                            = "latest"
"go:golang.org/x/tools/gopls" = "latest"
EOF
  fi
  if has_lsp python; then
    cat <<'EOF'
"npm:pyright" = "latest"
EOF
  fi
  if has_lsp ts; then
    cat <<'EOF'
"npm:typescript"                 = "latest"
"npm:typescript-language-server" = "latest"
EOF
  fi
} > "$HOME/.config/mise/config.toml"

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

write_block "# >>> editor" "# <<< editor" "$(cat <<EOF
# >>> editor (managed by dotfiles bootstrap)
if command -v nvim >/dev/null 2>&1; then
  export EDITOR=nvim
  export VISUAL=nvim
fi
# <<< editor
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

# --- 4. Neovim config (init.lua is owned by this script) ---
log "Writing ~/.config/nvim/init.lua..."
mkdir -p "$HOME/.config/nvim"
{
  cat <<'EOF'
-- Managed by dotfiles/bootstrap.sh — edits here will be overwritten.

-- 表示
vim.opt.number = true          -- 行番号
vim.opt.cursorline = true      -- カーソル行をハイライト
vim.opt.termguicolors = true   -- 24bit カラー
vim.opt.signcolumn = 'yes'     -- 左端の余白を常に確保

-- 検索
vim.opt.ignorecase = true
vim.opt.smartcase = true

-- 操作
vim.opt.mouse = 'a'
vim.opt.clipboard = 'unnamedplus'  -- OSC52 経由でホストのクリップボードへ

-- インデント
vim.opt.expandtab = true
vim.opt.shiftwidth = 2
vim.opt.tabstop = 2
EOF

  if [[ ${#LSP_LANGS[@]} -gt 0 ]]; then
    cat <<'EOF'

-- LSP (Neovim 0.11+ ネイティブ API、プラグイン無し)
EOF
    if has_lsp go; then
      cat <<'EOF'
vim.lsp.config('gopls', {
  cmd = { 'gopls' },
  filetypes = { 'go', 'gomod', 'gowork', 'gotmpl' },
  root_markers = { 'go.work', 'go.mod', '.git' },
})
vim.lsp.enable('gopls')
EOF
    fi
    if has_lsp python; then
      cat <<'EOF'
vim.lsp.config('pyright', {
  cmd = { 'pyright-langserver', '--stdio' },
  filetypes = { 'python' },
  root_markers = { 'pyproject.toml', 'setup.py', 'setup.cfg', 'requirements.txt', '.git' },
})
vim.lsp.enable('pyright')
EOF
    fi
    if has_lsp ts; then
      cat <<'EOF'
vim.lsp.config('ts_ls', {
  cmd = { 'typescript-language-server', '--stdio' },
  filetypes = { 'typescript', 'typescriptreact', 'javascript', 'javascriptreact' },
  root_markers = { 'tsconfig.json', 'package.json', 'jsconfig.json', '.git' },
})
vim.lsp.enable('ts_ls')
EOF
    fi
    cat <<'EOF'

vim.api.nvim_create_autocmd('LspAttach', {
  callback = function(ev)
    local buf = ev.buf
    local map = function(k, fn) vim.keymap.set('n', k, fn, { buffer = buf }) end
    map('gd', vim.lsp.buf.definition)
    map('K',  vim.lsp.buf.hover)
    map('gr', vim.lsp.buf.references)
    map('gi', vim.lsp.buf.implementation)
    map('<leader>rn', vim.lsp.buf.rename)
    map('<leader>ca', vim.lsp.buf.code_action)
    if vim.lsp.completion and vim.lsp.completion.enable then
      vim.lsp.completion.enable(true, ev.data.client_id, buf, { autotrigger = true })
    end
  end,
})
EOF
  fi
} > "$HOME/.config/nvim/init.lua"

# --- 5. Yazi config (yazi.toml is owned by this script) ---
log "Writing ~/.config/yazi/yazi.toml..."
mkdir -p "$HOME/.config/yazi"
cat > "$HOME/.config/yazi/yazi.toml" <<'EOF'
# Managed by dotfiles/bootstrap.sh — edits here will be overwritten.
[mgr]
ratio = [1, 2, 6]
show_hidden = true

[opener]
edit = [
  { run = 'nvim --clean "$@"', block = true, for = "unix" },
]

[open]
rules = [
  { mime = "text/*", use = "edit" },
  { name = "*", use = "edit" },
]
EOF

# --- 6. Verify ---
log "Installed:"
mise ls

log "Sanity check (PATH resolution):"
ok=1
checks=(
  "lazygit:lazygit" "ripgrep:rg" "fzf:fzf" "fd:fd" "yazi:yazi"
  "bat:bat" "eza:eza" "zoxide:zoxide" "gh:gh" "delta:delta" "neovim:nvim"
)
has_lsp go     && checks+=("gopls:gopls")
has_lsp python && checks+=("pyright:pyright-langserver")
has_lsp ts     && checks+=("ts_ls:typescript-language-server")

for entry in "${checks[@]}"; do
  name="${entry%%:*}"; bin="${entry##*:}"
  if path="$(command -v "$bin" 2>/dev/null)"; then
    printf '  ok   %-22s -> %s\n' "$bin" "$path"
  else
    warn "  MISS %-22s (%s) not found" "$bin" "$name"
    ok=0
  fi
done

cat <<EOF

[bootstrap] Done.
[bootstrap] To use the tools in your CURRENT shell, run:
[bootstrap]   exec \$SHELL -l
EOF

[ "$ok" = 1 ]
