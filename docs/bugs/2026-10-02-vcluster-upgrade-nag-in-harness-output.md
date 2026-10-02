# Bug: every harness `vcluster` call prints "Run `vcluster upgrade`", which is the wrong action

**Filed:** 2026-10-02
**Status:** OPEN
**Branch:** `k3d-manager-v1.40.0`
**File:** `scripts/plugins/vcluster.sh`
**Tests:** `scripts/tests/plugins/vcluster.bats`
**Related:** `docs/plans/v1.41.1-vcluster-version-drift.md` (the deliberate way to bump the pin)

## Symptom

`make e2e` output repeats this on every vcluster command:

```
warn There is a newer version of vcluster: v0.37.2. Run `vcluster upgrade` to upgrade to the newest version.
```

The harness does not use the operator's Homebrew `vcluster`, which is already 0.37.2. It uses the copy
that `foundation_ensure_vcluster_cli` downloads and SHA-256 checks at
`~/.local/share/lib-foundation/vcluster/0.32.1/vcluster`. `VCLUSTER_VERSION` pins that binary and the
vCluster Helm chart (`--chart-version`) together. Running `vcluster upgrade` on it would replace a
checked binary with an unchecked one, and the CLI and chart would no longer match. So the warning is noise,
and it points to the wrong fix. The pin is bumped through the v1.41.1 plan.

## Root cause

vcluster checks GitHub for a newer release on each command. Its source
(`pkg/upgrade/upgrade.go`, v0.32.1) skips the check when `VCLUSTER_SKIP_VERSION_CHECK` is `"true"`:

```go
func PrintNewerVersionWarning() {
	if os.Getenv("VCLUSTER_SKIP_VERSION_CHECK") != "true" {
```

The plugin does not set it.

## Fix

In `scripts/plugins/vcluster.sh`, set the variable next to the other defaults and export it with them.
An operator who sets it themselves keeps their value.

Old:
```bash
VCLUSTER_LOCAL_PORT="${VCLUSTER_LOCAL_PORT:-11443}"
_VCLUSTER_BIN=""
```
New:
```bash
VCLUSTER_LOCAL_PORT="${VCLUSTER_LOCAL_PORT:-11443}"
VCLUSTER_SKIP_VERSION_CHECK="${VCLUSTER_SKIP_VERSION_CHECK:-true}"
_VCLUSTER_BIN=""
```

Old:
```bash
export VCLUSTER_LOCAL_PORT
```
New:
```bash
export VCLUSTER_LOCAL_PORT
export VCLUSTER_SKIP_VERSION_CHECK
```

## Test (in `scripts/tests/plugins/vcluster.bats`, after "VCLUSTER_LOCAL_PORT defaults to 11443")

```bash
@test "VCLUSTER_SKIP_VERSION_CHECK defaults to true and reaches the CLI environment" {
  [ "$VCLUSTER_SKIP_VERSION_CHECK" = "true" ]
  run bash -c 'printf "%s" "${VCLUSTER_SKIP_VERSION_CHECK:-unset}"'
  [ "$output" = "true" ]
}
```

The `bash -c` child shows the value is exported, which is what the vcluster child process sees.

**Mutation check (must report):** delete the `export VCLUSTER_SKIP_VERSION_CHECK` line, and the test must
go red on the child check. Restore it, and the whole file is green.

## Rules

- `bats scripts/tests/plugins/vcluster.bats`: all green; paste the summary.
- `shellcheck scripts/plugins/vcluster.sh`: no new warnings.
- Do not change `VCLUSTER_VERSION` or `.github/actions/vcluster-e2e-setup/action.yml`.

## Definition of Done

- [ ] Fix applied exactly as written
- [ ] Test added and green; mutation result reported
- [ ] Status line set to `FIXED (<short sha>)`
- [ ] Commit message: `fix(vcluster): skip the CLI upgrade nag for the pinned harness binary`
- [ ] Pushed to `origin/k3d-manager-v1.40.0`; report `git rev-parse origin/k3d-manager-v1.40.0`

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify files other than `vcluster.sh`, `vcluster.bats`, and this doc
- Do NOT run `vcluster upgrade` or bump the pin
- Do NOT run `make e2e`: a live run is in progress
- Do NOT commit to `main`
