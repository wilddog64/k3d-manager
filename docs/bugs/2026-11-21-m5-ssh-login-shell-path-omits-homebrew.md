# m5-air ssh login shell PATH omits /opt/homebrew/bin

**Status:** LIVE-VERIFIED — 2026-11-21: zshdotfiles#5 merged as ae8bd15 (supersedes #4/1c5cf9e) and fast-forwarded on m5-air; a fresh `zsh -lic` there has `HOMEBREW_PREFIX=/opt/homebrew`, gnubin on PATH and `brew`, `envsubst`, `gh`, `tmux` from `/opt/homebrew/bin`.
**Priority:** P3
**Verification type:** investigation
**Live investigation evidence:** 2026-11-21 · source claude-ssh-probe · reference docs/bugs/2026-11-21-m5-ssh-login-shell-path-omits-homebrew.md · env m5-air · scenario fresh-login-shell-after-zshdotfiles-ae8bd15 · proves m1
**Introduced by:** pre-existing
**Should have been caught by:** deploy step
**Introducing change reviewed:** no
**Prior art:** not run (find-similar-docs: vector store unavailable); exact-slug glob found none. Read, different scope: `docs/bugs/2026-09-27-launchd-path-omits-local-bin.md` (launchd agents, not shells), `docs/bugs/2026-10-09-launchd-agents-hardcode-homebrew-python3-hermes-down.md`.

## Symptom

On m5-air (the hub), 2026-11-21, the interactive zsh PATH printed `~/.local/share/k3d-manager/bin`, `~/.zplug/bin`,
`/opt/puppetlabs/puppet/bin`, `/usr/local/bin`, `~/bin`, `~/.local/bin`, `/usr/local/sbin`, `/usr/bin`, `/bin`, ... and no
`/opt/homebrew/bin`. Homebrew tools that operator make targets need (`gh`, `envsubst` from gettext, `/opt/homebrew/bin/tmux`)
were not found, so `make hub-deploy` failed (see `docs/bugs/2026-11-21-hub-deploy-no-tool-preflight-gh-envsubst.md`).

## Cause

`~/.zprofile` on m5 only sources OrbStack's init, and `~/.zshrc` (symlink to `~/.zsh/zshrc`, repo `zshdotfiles`) used
`$HOMEBREW_PREFIX` without ever putting `/opt/homebrew/bin` on PATH. The real Homebrew setup is in `~/.zshenv` (repo
`zshdotfiles/zshenv`), gated on `which brew`; a fresh ssh login starts with the bare system PATH, so that check failed and
the whole block (`brew shellenv`, gnubin, openssl, gnu-tar) was skipped.

## Fix

First attempt, `zshdotfiles` 1c5cf9e (PR #4): a `zshrc` block prepending `/opt/homebrew/bin:/opt/homebrew/sbin`. It found
`gh`/`envsubst` but left `HOMEBREW_PREFIX`, gnubin and the rest unset (operator: "seems to wipe out brew path").

Fix, `zshdotfiles` ae8bd15 (PR #5): `zshenv` falls back to `/opt/homebrew/bin/brew`, then `/usr/local/bin/brew`, when `brew`
is not on PATH, and runs `eval "$($BREW_CMD shellenv)"`; the #4 `zshrc` block is removed. Tested on m4 first with
`env -i ... PATH=/usr/bin:/bin zsh -lic`.

## Live check (m1)

2026-11-21, m5-air, after `git merge --ff-only origin/main` in `zshdotfiles` (HEAD ae8bd15): `zsh -lic` printed
`HOMEBREW_PREFIX=/opt/homebrew`, gnubin on PATH, `brew`/`envsubst`/`gh`/`tmux` from `/opt/homebrew/bin`, first PATH entry
`~/.local/share/k3d-manager/bin`. m1 = a new ssh login shell on the hub resolves
the Homebrew tools that operator make targets need.
