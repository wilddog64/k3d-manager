# Issue: _run_command Non-Interactive Sudo Failure after VM Restart

**Date:** 2026-03-19
**Status:** RESOLVED (2026-03-20)
**Component:** `scripts/lib/system.sh` (`_run_command`), `scripts/lib/providers/k3s.sh`

## Description

During the infrastructure restoration process on `m4-air` after a machine and Ubuntu VM restart, the `deploy_cluster` command failed on the remote Ubuntu host. The failure occurred at the first step requiring elevated privileges (`mkdir -p /etc/rancher/k3s`).

## Symptoms

- Running `./scripts/k3d-manager deploy_cluster --force-k3s automation` via SSH fails with:
  ```
  mkdir: cannot create directory ‘/etc/rancher/k3s’: Permission denied
  mkdir command failed (1): mkdir -p /etc/rancher/k3s 
  ERROR: failed to execute mkdir -p /etc/rancher/k3s: 1
  ```
- The script does not prompt for a `sudo` password even when run with `-t` (pseudo-terminal).

## Root Cause

The `_run_command` function in `scripts/lib/system.sh` defaults to using non-interactive sudo flags:
```bash
if (( interactive_sudo == 0 )); then
  sudo_flags=(-n)  # Non-interactive sudo
fi
```
When the Ubuntu VM is restarted, the `sudo` timestamp is cleared. Subsequent calls to `sudo -n` fail immediately because they require a password that cannot be provided in non-interactive mode.

## Workaround (Manual)

Warm up the `sudo` timestamp on the remote host before running the manager script:
```bash
ssh -t ubuntu "sudo true"
```
After this, `sudo -n` will succeed for the duration of the `sudo` timeout (typically 5-15 minutes).

## Permanent Fix (Implemented)

- Added `_run_command_has_tty` helper so `_run_command` can detect whether a TTY is present (overridable in tests).
- Updated all `--prefer-sudo`, `--require-sudo`, and `--probe` paths to attempt interactive sudo when `sudo -n` fails but a TTY exists, and to keep failing fast when no TTY is available.
- Added regression BATS coverage for the new fallback behavior and ensured `scripts/k3d-manager test run_command` exercises the new code paths.

These changes shipped on `k3d-manager-v0.9.4` via commit `fix(system): fall back to interactive sudo when sudo -n unavailable and TTY present`.
