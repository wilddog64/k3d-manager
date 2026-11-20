# machine-setup: antigravity-cli cask refuses to install over an agy brew does not own

**Status:** OPEN
**Priority:** P3
**Introduced by:** 20c9bc74 (cask:antigravity-cli added to brew.hub.list / brew.worker.list)
**Should have been caught by:** live check
**Introducing change reviewed:** unknown
**Waiting on:** operator decision — since 2026-11-20
**Prior art:** docs/bugs/2026-10-31-machine-setup-installs-wrong-gemini-and-no-agy.md (exact topic, read) — read, different root cause; find-similar-docs not run

## Symptom

`make machine-setup ROLE=worker FROM=m5-air.local` on m4-air (operator, 2026-11-20) reports
`brew:antigravity-cli missing (see machine-setup.log)` and ends `Error 1`. The log
(`~/.local/state/k3d-manager/machine-setup.log`) shows:

`Error: antigravity-cli: It seems there is already a Command Wrapper at '/opt/homebrew/bin/agy'.`

`/opt/homebrew/bin/agy` is a working Mach-O binary, `agy --version` = `1.5.13`, the same version the cask ships, but
`brew info --cask antigravity-cli` says `Not installed`. So agy works and only Homebrew's record is missing; setup
cannot tell the two apart and fails.

## Fix options (operator decision)

- (a) One-off on the M4: `brew install --cask --force antigravity-cli` (replaces agy with the identical version and
  registers it). No code change.
- (b) In `bin/k3dm-machine-setup`, treat an existing executable `agy` that reports a version as satisfying
  `cask:antigravity-cli` (report `ok (unmanaged)`), instead of a failure.
