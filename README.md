# dotfiles

Personal dev environment for Debian-based containers (e.g. `node:*-slim`).
Installs everything under `$HOME` via [mise](https://mise.jdx.dev/) — no root needed.

## Tools

- **lazygit**, **delta** — git TUI / diff viewer
- **yazi** — file manager
- **fzf**, **ripgrep**, **fd** — fuzzy find / grep / find
- **bat**, **eza** — `cat` / `ls` replacements
- **zoxide** — smarter `cd`
- **gh** — GitHub CLI
- **neovim** — editor (minimal `init.lua` managed by bootstrap, optional LSP via `--lsp`)

## Usage

Inside the container:

```bash
git clone https://github.com/<you>/dotfiles ~/.dotfiles
~/.dotfiles/bootstrap.sh                  # no LSP
~/.dotfiles/bootstrap.sh --lsp go,ts      # gopls + ts_ls
~/.dotfiles/bootstrap.sh --lsp all        # gopls + pyright + ts_ls
exec $SHELL -l
```

`--lsp` accepts a comma-separated subset of `go`, `python`, `ts` (or `all`).
LSP is wired via Neovim 0.11+ native `vim.lsp.config` — no plugin manager.
`pyright` and `typescript-language-server` are installed via `npm:` and
assume `node` is on `PATH` (true for `node:*-slim` and similar bases).

Re-running `bootstrap.sh` is safe — managed blocks are rewritten in place.
Switching `--lsp` between runs prunes the unused servers via `mise prune`.

## Requirements

- Debian/Ubuntu-based image
- `bash`, `curl`, `git`
- Write access to `$HOME`

## Notes

Set `GITHUB_TOKEN` before running to avoid GitHub API rate limits (60 req/hr unauthenticated). A token with no scopes is sufficient for fetching public release binaries.

```bash
export GITHUB_TOKEN=ghp_***
~/.dotfiles/bootstrap.sh
```
