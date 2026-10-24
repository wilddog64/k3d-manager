# Bug: CI `lint` fails on the `install-sudoers.sh --dry-run` syntax check after `ubuntu-latest` moved to Ubuntu 26.04

**Status:** FIXED — pending the v1.43.5 PR CI run
**Priority:** P1 — every PR's `lint` job fails, so no release can pass the CI gate
**Severity:** high
**Release:** v1.43.5 (bug; exempt from the plan cap)
**Filed:** 2026-10-24, by Claude, from PR #148 CI run 40119398036
**Approval:** fix under the operator's 2026-10-24 instruction to open the v1.43.5 PR; CI-only change
**Component:** `.github/workflows/ci.yml` (`lint` job), `scripts/tests/bin/install_sudoers.bats`
**Related:** `docs/bugs/v1.6.0-bugfix-stale-sudoers-install-path.md`

## Symptom

`not ok 356 install-sudoers.sh --dry-run validates sudoers syntax` (`[ "$status" -eq 0 ]` failed).
`bin/install-sudoers.sh` and its test are unchanged since `main`, whose CI last passed on 2026-10-19.
The failing run used runner image `20261021.618`, which is Ubuntu 26.04.

## Root cause

Ubuntu 26.04 ships `sudo-rs` as its only sudo. Its `visudo` (`/usr/lib/cargo/bin/visudo`) rejects
wildcards in command arguments:

    syntax error: wildcards are not allowed in command arguments
    %admin  ALL=(root) NOPASSWD: /bin/chmod [0-9][0-9][0-9] /usr/local/bin/*

The rules are installed on macOS, which runs classic sudo, where this line is valid. The classic
`sudo-ws` package can't be installed on 26.04. Reproduced in `ubuntu:26.04` (rc 1). The same script
passes in `ubuntu:24.04` (`Syntax OK`, rc 0).

## Fix

Pin the `lint` job to `runs-on: ubuntu-24.04`, which still ships classic sudo, so the check keeps
validating against the sudo that installs these rules. Don't change the rules or skip the check.
Revisit before GitHub retires the 24.04 image.

## Acceptance

```yaml
must:
  - id: M1
    text: The lint job runs on a runner whose visudo is classic sudo, and test 356 passes.
must_not:
  - id: N1
    text: The sudoers syntax check must not be skipped or loosened to pass (the test file is unchanged).
evidence:
  - id: E1
    kind: offline
    proves: [M1]
    text: ubuntu:26.04 container fails the dry-run (rc 1, wildcard error); ubuntu:24.04 passes (rc 0).
  - id: E2
    kind: live
    proves: [M1, N1]
    text: The PR #148 lint job on ubuntu-24.04 passes with test 356 ok.
interface:
  - .github/workflows/ci.yml lint job
  - bin/install-sudoers.sh --dry-run
```
