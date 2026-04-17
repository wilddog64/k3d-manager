# m2-air GitHub Actions Runner Reports Wrong Architecture Label

**Date:** 2026-02-25
**Status:** Partially mitigated

## Description

The self-hosted GitHub Actions runner on `m2-air` (Apple Silicon, ARM64) registered
with the system label `X64` instead of `ARM64`. This happens when the runner agent is
installed or run under Rosetta 2 (x86 emulation) rather than natively as ARM64.

### Observed via API
```json
{
  "name": "m2-air",
  "os": "macOS",
  "labels": [
    { "name": "self-hosted", "type": "read-only" },
    { "name": "macOS",       "type": "read-only" },
    { "name": "X64",         "type": "read-only" }
  ]
}
```

## Impact

- CI workflow files that target `runs-on: [self-hosted, macOS, ARM64]` would not
  match this runner — jobs would queue indefinitely.
- Tools compiled for ARM64 (native Apple Silicon binaries) may behave unexpectedly
  if the runner is actually executing under Rosetta 2.

## Mitigation Applied (2026-02-25)

A custom `ARM64` label was added to the runner via the GitHub API:

```bash
gh api --method POST repos/wilddog64/k3d-manager/actions/runners/2/labels \
  --field 'labels[]=ARM64'
```

Runner now has both `X64` (system, read-only) and `ARM64` (custom). CI workflow files
can target `runs-on: [self-hosted, macOS, ARM64]` successfully.

## Permanent Fix

Re-register the runner natively on m2-air so the runner agent self-reports `ARM64`
as a read-only system label:

```bash
# On m2-air — remove existing runner first
cd ~/actions-runner
./config.sh remove --token <RUNNER_REMOVAL_TOKEN>

# Re-download and configure as native ARM64
# Get fresh token from: https://github.com/wilddog64/k3d-manager/settings/actions/runners/new
curl -o actions-runner-osx-arm64.tar.gz -L \
  https://github.com/actions/runner/releases/latest/download/actions-runner-osx-arm64.tar.gz
tar xzf actions-runner-osx-arm64.tar.gz
./config.sh --url https://github.com/wilddog64/k3d-manager --token <RUNNER_TOKEN>
./run.sh
```

After re-registration the system label will show `ARM64` and the custom label can be
removed.

## CI Workflow Target

Until the runner is re-registered, use:
```yaml
runs-on: [self-hosted, macOS, ARM64]
```
This matches on the custom `ARM64` label and works correctly with the mitigation in place.
