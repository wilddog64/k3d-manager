# Bug: `make refresh` never installs a missing system LaunchDaemon unless sudo is already cached

**Filed:** 2026-10-03, Claude
**Branch:** `k3d-manager-v1.41.0`
**Status:** OPEN — spec below, for Codex
**Severity:** medium. The public shop (`frontend.3ai-talk.org`) stays at 502 after a "successful" refresh.
**Related:** `v1.6.1-bugfix-system-daemon-plists-not-reinstalled-by-acg-refresh.md`, which introduced
the installer

## Observed (2026-10-03)

1. `make up` was run through Claude Code `!`. It logged `no sudo in headless context — skipping
   keycloak-browser-http LaunchDaemon install`, and the same for `frontend-browser-http`.
2. The operator then ran `make refresh CLUSTER_PROVIDER=k3s-aws` in Terminal.app. It completed and
   never asked for a password.
3. `/Library/LaunchDaemons` still contains only `com.k3d-manager.loopback-alias.plist`. Nothing listens
   on `127.0.0.2:80`, and `bin/public-endpoint-probe` reports `frontend.3ai-talk.org 0/5 [502…]`.

## Root cause

`bin/cluster-refresh` `_system_daemon_install_if_missing` copies the plist with
`_run_command --prefer-sudo --quiet --soft -- cp ...`. In `system.sh`, `--prefer-sudo` resolves only
to `sudo -n` (non-interactive). With no cached sudo timestamp, it falls back to a plain `cp` into
`/Library/LaunchDaemons`. That fails, and `--soft` + `--quiet` turn the failure into one `_warn`.
`_launchd_ensure` then has no plist to bootstrap.

The restart path in the same file (`_launchd_restart`) already uses `--interactive-sudo`. Only the
install path is non-interactive.

## Fix

1. `bin/cluster-refresh` `_system_daemon_install_if_missing`: `--prefer-sudo` → `--interactive-sudo`
   on the `cp`. Keep `--soft`, so a declined prompt still lets the refresh finish. `cluster-refresh`
   is an operator-run command in a real terminal, so a prompt is expected.
2. When stdin is not a TTY (`[[ -t 0 ]]` false, for example a Slack `/cluster-refresh` job), keep
   `--prefer-sudo`, and make the `_warn` name the missing plist and the exact recovery command:
   `sudo -v && make refresh CLUSTER_PROVIDER=<provider>`.

**Gates (offline; stubs only):**
- BATS: with a `_run_command` stub that records its flags, a TTY run passes `--interactive-sudo`, and a
  non-TTY run passes `--prefer-sudo` and prints the recovery command.
- Mutation: reverting the TTY branch turns the test red.
- shellcheck is clean, and `git diff --stat` touches only `bin/cluster-refresh` and its BATS file.

## Workaround

```bash
sudo -v && make refresh CLUSTER_PROVIDER=k3s-aws
```

macOS sudo timestamps are per terminal, so a `sudo -v` in the same Terminal.app window lets the
`sudo -n` probe succeed.
