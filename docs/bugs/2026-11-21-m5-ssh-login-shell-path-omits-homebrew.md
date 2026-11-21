# m5-air ssh login shell PATH omits /opt/homebrew/bin

**Status:** OPEN — captured 2026-11-21; dotfiles fix in review (wilddog64/zshdotfiles#4).
**Priority:** P3
**Introduced by:** pre-existing
**Should have been caught by:** deploy step
**Introducing change reviewed:** no
**Waiting on:** operator decision — since 2026-11-21
**Prior art:** not run (find-similar-docs: vector store unavailable); exact-slug glob found none. Read, different scope: `docs/bugs/2026-09-27-launchd-path-omits-local-bin.md` (launchd agents, not shells), `docs/bugs/2026-10-09-launchd-agents-hardcode-homebrew-python3-hermes-down.md`.

## Symptom

On m5-air (the hub), 2026-11-21, the interactive zsh PATH printed `~/.local/share/k3d-manager/bin`, `~/.zplug/bin`,
`/opt/puppetlabs/puppet/bin`, `/usr/local/bin`, `~/bin`, `~/.local/bin`, `/usr/local/sbin`, `/usr/bin`, `/bin`, ... and no
`/opt/homebrew/bin`. Homebrew tools that operator make targets need (`gh`, `envsubst` from gettext, `/opt/homebrew/bin/tmux`)
were not found, so `make hub-deploy` failed (see `docs/bugs/2026-11-21-hub-deploy-no-tool-preflight-gh-envsubst.md`).

## Cause

`~/.zprofile` on m5 only sources OrbStack's init, and `~/.zshrc` (symlink to `~/.zsh/zshrc`, repo `zshdotfiles`) used
`$HOMEBREW_PREFIX` without ever putting `/opt/homebrew/bin` on PATH. Nothing ran `brew shellenv`.

## Fix

`zshdotfiles` commit 36bddaa (PR #4): guarded, idempotent `export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:$PATH"`,
inserted before the pyenv block and the k3d-manager bin export so those stay first. After merge: `git pull --ff-only` in
`~/src/gitrepo/personal/zshdotfiles` on m5, open a new shell, `command -v envsubst gh` -> `/opt/homebrew/bin/...`.
