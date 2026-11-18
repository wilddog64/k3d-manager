# CI red on the release branch: password_bundle.bats needs age-keygen, the CI runner has none

**Status:** OPEN — filed 2026-11-18 (Claude, found while capturing check-runs for plan 1)
**Priority:** P1 — every CI run on `k3d-manager-v1.45.0` since `d14b5d9e` fails, so the release PR merge gate cannot pass and any new regression is hidden behind the same red
**Introduced by:** `ddd9329e` (v1.45.0 plan 2, password travel bundle)
**Should have been caught by:** deploy step (the land gate ran BATS on the M4, which has `age`; nothing checked that CI installs it)
**Introducing change reviewed:** unknown
**Waiting on:** fix running — since 2026-11-18 (Luna)
**Prior art:** `docs/bugs/2026-10-31-ci-reds-reproducible-locally-no-fast-gate.md` (exact-slug review) — read, different root cause (script syntax); `make find-similar-docs` not run
**Filed:** 2026-11-18

## Symptom (Claude, read-only, 2026-11-18)

- CI runs on `k3d-manager-v1.45.0`: last success `16476831` (03:38Z); every completed run from `d14b5d9e` (03:48Z) to
  `d3fd0a22` (15:23Z) failed, 11 runs. Each fails in shard `test (2)` only.
- Run 44335042126 (`d3fd0a22`): `scripts/tests/plugins/password_bundle.bats: line 10: age-keygen: command not found`,
  then `not ok 1`..`not ok 8` (all 8 tests, in `setup`). Same 8 lines in the `d14b5d9e` run.
- `.github/actions/setup/action.yml` installs `shellcheck python3-pip`, bats 1.11.0 and yamllint; no `age`.
- Jobs run on `ubuntu-24.04` (`.github/workflows/ci.yml:47,105,163`; runner image 20261111.127.1).

## Proof of external behaviour (Claude, M4, 2026-11-18T15:47Z, Docker 29.10.0, image `ubuntu:24.04` linux/amd64)

`apt-get install -y age` installs `age 1.1.1-1ubuntu0.24.04.3`, providing `/usr/bin/age` and `/usr/bin/age-keygen`;
`age-keygen | tail -1 | age-keygen -y` prints an `age1...` recipient, which is what `password_bundle.bats:9-10` runs.

## Fix

Add `age` to the apt install line in `.github/actions/setup/action.yml`. Do not skip the tests when `age` is missing:
a skip would turn a missing tool into a silent pass.

## Files

- `.github/actions/setup/action.yml`
- `scripts/tests/lib/ci_setup_installs_test_tools.bats` (new)

## Acceptance

```yaml
must:
  - id: M1
    text: the CI setup action installs the apt package age, so password_bundle.bats runs all 8 tests on the CI runner
must_not:
  - id: N1
    text: the CI setup action omits age while a BATS suite calls age or age-keygen — red today
  - id: N2
    text: password_bundle.bats skips or passes vacuously when age is absent
evidence:
  - id: E1
    proves: [M1, N1]
    kind: offline
    command: bats scripts/tests/lib/ci_setup_installs_test_tools.bats
    intent: "The test fails if any BATS test needs age but CI does not install it, so this kind of red cannot come back quietly."
  - id: E2
    proves: [M1, N2]
    kind: live
    what: "Claude, after the fix is pushed: the CI run on the release branch head is green, and the test (2) log shows ok 1..ok 8 for password_bundle.bats (no skip)."
    intent: "Release-branch CI is green again, and the travel-bundle tests really run there."
interface:
  - ".github/actions/setup/action.yml apt install line"
```

### Test requirements

- The new BATS test parses the apt install line in `.github/actions/setup/action.yml` (the `apt-get install -y` line in
  the "Install apt packages" step) and asserts `age` is one of its words (whole word, so `page` or `age-plugin` do not count).
- It also asserts that `scripts/tests` really contains a call to `age-keygen`, so it fails if the grep target moves.
- Positive control in the same file: a fixture copy of `action.yml` without `age` makes the check fail.
- Red today: run it against the unfixed `action.yml` and paste the failing line.

**Intent approved:** operator, 2026-11-18
**Intent approval note:** "go ahead for P1 and dispatch to Luna", after Claude listed E1/E2 as written
