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
- **neovim** — editor (minimal `init.lua` managed by bootstrap)

## Usage

Inside the container:

```bash
git clone https://github.com/<you>/dotfiles ~/.dotfiles
~/.dotfiles/bootstrap.sh
exec $SHELL -l
```

Re-running `bootstrap.sh` is safe — managed blocks are rewritten in place.

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
