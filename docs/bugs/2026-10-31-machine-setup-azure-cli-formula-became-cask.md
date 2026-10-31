# Bug: machine setup reports azure-cli missing on the M5, because Homebrew installed it as a cask

**Status:** FIXED (`9766a7b6`, Codex; Claude review, independent verifier, live E2 2026-10-31)
**Priority:** P3
**Approval:** operator, 2026-10-31 ("go ahead")
**Filed:** 2026-10-31
**Detected by:** the operator's `make machine-setup ROLE=hub` on the M5 (exit 1); diagnosed by Claude
**Affected:** `bin/k3dm-machine-setup` (brew package loop, line ~178); `scripts/etc/machine/brew.hub.list`, `brew.worker.list`
**Branch:** `k3d-manager-v1.43.13`

## Observed failure

`bin/k3dm-machine-setup --role hub --check` on the M5 (interactive login shell, 2026-10-31) reports
`brew:azure-cli missing`, and every setup run fails on it. azure-cli is installed and works there:
`brew info azure-cli` shows `Installed (on request)` at `/opt/homebrew/Caskroom/azure-cli/2.91.0`, and
`/opt/homebrew/bin/az` links into that Caskroom. `machine-setup.log` shows each run's `brew install azure-cli`
answering `Warning: Not upgrading azure-cli, the latest version is already installed`.

On the M4 the same package is still a formula: `brew list --formula --versions azure-cli` prints `azure-cli 2.90.0`.

## Root cause

The manifests list `azure-cli` as a formula (no `cask:` prefix). Homebrew now ships azure-cli as a cask, so a fresh
install (the M5, 2026-10-30) gets the cask. The check runs `brew list --formula azure-cli`, which fails for a cask.
`brew install azure-cli` resolves to the installed cask and succeeds without changing anything, so setup cannot
repair it and fails on every run. A Mac installed earlier (the M4) keeps the formula, so changing the manifest to
`cask:azure-cli` alone would make the M4 fail instead.

## Fix

For a manifest entry with no `cask:`/`formula:` prefix, count the package as present when either
`brew list --formula NAME` or `brew list --cask NAME` succeeds. Keep an explicit prefix strict. Check the other
manifest entries the same way on the M4 and M5 (`brew list --cask` vs the lists) and note any other package in
the same state.

## Files

- `bin/k3dm-machine-setup`
- `scripts/tests/bin/machine_setup.bats`
- `CHANGELOG.md`

## What NOT to do

- Do not uninstall or migrate azure-cli on either Mac.
- Do not loosen `cask:` or `formula:` entries.

## Acceptance

```yaml
must:
  M1: an unprefixed manifest entry installed only as a cask reports `brew:<name> ok` in check and setup mode
  M2: an unprefixed entry installed only as a formula still reports ok
must_not:
  N1: an unprefixed entry installed as neither still fails check mode
  N2: a `formula:`-prefixed entry installed only as a cask still fails
evidence:
  E1:
    proves: [M1, M2, N1, N2]
    kind: offline
    intent: >-
      You will see a brew stub (output captured from the M5 and M4, 2026-10-31) answering list --cask for one
      name and list --formula for another, and check mode passing both while a third, absent name fails. It
      failed if it passes against today's script.
    what: bats scripts/tests/bin/machine_setup.bats
  E2:
    proves: [M1, M2]
    kind: live
    intent: >-
      You will see `bin/k3dm-machine-setup --role hub --check` on the M5 and the M4 report `brew:azure-cli ok`.
      It failed if either reports it missing.
    what: Claude runs both from an interactive login shell
interface:
  - bin/k3dm-machine-setup --role hub|worker|console --check
  - scripts/etc/machine/brew.<role>.list
```

## Verification (Claude, 2026-10-31)

- E1: Codex's two BATS tests, mutation-checked on a scratch copy. The accept-either test fails on the pre-fix script;
  the strict-prefix test fails when the `"$raw" != *:*` guard is removed. An independent verifier, given only the
  Acceptance block, wrote 9 tests: its M1 tests fail on pre-fix and all 9 pass on the fix. N1/N2 cannot go red on the
  pre-fix script (it was already strict); they are regression guards.
- E2: `bin/k3dm-machine-setup --role hub --check` from `HEAD` reports `brew:azure-cli ok` on the M4 (formula) and the
  M5 (cask; 86/86 `brew:` lines ok). Both exit 1 only on other lines (heartbeat agent by design; M4 python-tools,
  state-direnvrc, one https remote).
- Brew exit codes behind the stubs, captured 2026-10-31: M5 `brew list --formula azure-cli` 1, `--cask` 0; M4 0 and 1.
- No other unprefixed manifest entry is a cask on the M4 (Codex) or the M5 (all 86 ok).
- Found on the way, not part of this fix: the M5's interactive login shell had no Homebrew on PATH at E2 time (the M4's
  does; same `/etc/paths.d/homebrew`), so the E2 run on the M5 put brew on PATH with `brew shellenv`. `my_func.zsh:25`
  also fails `zsh -n` on both Macs, and `--check-shell` does not match `parse error` or `unmatched`.
