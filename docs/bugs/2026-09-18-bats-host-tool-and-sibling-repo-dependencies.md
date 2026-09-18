# Two BATS suites depend on the author's workstation, not the repo

**Filed:** 2026-09-18
**Status:** OPEN
**Branch:** `k3d-manager-v1.35.0`
**Component:** `scripts/tests/plugins/argocd_reclaim_release_ownership.bats`,
`scripts/tests/plugins/keycloak.bats`
**Severity:** medium — red CI on the v1.35.0 release PR (#128)
**Surfaced by:** `6064796c` (CI now uses the Makefile's full discovery instead of a
hand-maintained file list). Both suites were **dark in CI** before that commit, so neither
failure is a regression — they are pre-existing defects becoming visible for the first time.

## Problem

Both tests pass on the maintainer's macOS workstation and fail on the Linux CI runner, because
each depends on something that exists only on that workstation.

### 1. `argocd_reclaim_release_ownership.bats` calls `rg`

```
not ok 500 argocd reclaim ownership: confirm patches, removes tracking, and deletes only serviceaccounts
# (in test file scripts/tests/plugins/argocd_reclaim_release_ownership.bats, line 63)
#   `configmap_patch="$(rg 'patch configmap argocd-cm' "${BATS_TEST_TMPDIR}/calls")"' failed with status 127
# rg: command not found
```

Seven call sites use `rg` (lines 53, 63, 64, 68, 69, 70, 83). `rg` (ripgrep) is installed on the
maintainer's machine — where `grep` is in fact *aliased* to `rg` — but it is not a dependency of
this repo and is not present on `ubuntu-latest`. A test suite may only use tools the repo
actually requires.

Note the exit status: `127` (command not found). At line 53 and line 70 the call is wrapped in
`run` and the assertion is `[ "$status" -ne 0 ]`, so **those two assertions pass for the wrong
reason** — a missing binary satisfies "this pattern must not match". They assert nothing on CI.
That is the more dangerous half of this defect: it is not merely red, it is silently vacuous.

### 2. `keycloak.bats` copies a file from a sibling repository

```
not ok 728 _keycloak_reconcile_realm_client updates argocd redirect URIs
# (in test file scripts/tests/plugins/keycloak.bats, line 45)
#   `cp "${BATS_TEST_DIRNAME}/../../../../shopping-carts/shopping-cart-infra/identity/keycloak/realm-shopping-cart.json" "$realm_json"' failed
# cp: cannot stat '.../shopping-carts/shopping-cart-infra/identity/keycloak/realm-shopping-cart.json': No such file or directory
```

The test reaches four levels up and out of the repository into a **separate checkout**
(`shopping-carts/shopping-cart-infra`). CI clones only `k3d-manager`, so the fixture is absent.

The correct idiom already exists in this tree — `scripts/tests/plugins/shopping_cart.bats:86`
guards the same sibling-repo path:

```bash
if [[ -d "${repo_root}/../shopping-carts/shopping-cart-infra/argocd/applications" ]]; then
```

So `keycloak.bats` is the outlier, not the precedent.

## Fix

### 1. `rg` → `grep`

Replace all seven `rg` call sites with `grep`. Line 53's pattern uses ERE alternation
(`' (patch|label|delete) '`) and therefore needs `grep -Eq`; the rest are plain BRE-safe patterns
and take `grep -q`. Use `--` before the pattern where a leading `-` is possible.

Do **not** add ripgrep as a CI dependency. The point is that a test must not require a tool the
product does not require.

### 2. Skip the keycloak case when its sibling fixture is absent

Guard the `cp` and `skip` with a message naming what is missing, matching the
`shopping_cart.bats:86` convention. Resolve the path from the repo root rather than by counting
`../` from `BATS_TEST_DIRNAME`.

Do **not** vendor a copy of `realm-shopping-cart.json` into this repo: it is owned by
`shopping-cart-infra`, and a vendored copy would drift silently and start asserting against a
realm definition that no longer matches the one actually deployed.

## Rules

- Double-quote every expansion.
- No bare `!` in BATS; no whole-line `grep -F` of a source line.
- Minimal patch — do not restructure either suite or touch unrelated cases.
- Do NOT edit `scripts/lib/foundation/` or `scripts/lib/acg/`.
- Do NOT add a CI dependency to satisfy a test.
- Do NOT mark either case `skip` unconditionally, delete it, or remove it from discovery.

## Definition of Done

- [ ] No `rg` anywhere under `scripts/tests/`: `command grep -rn '\brg\b' scripts/tests/` → 0
- [ ] The two `run`-wrapped negative assertions (old lines 53, 70) still assert a real
      non-match, not a missing binary — confirm the pattern genuinely does not appear
- [ ] `keycloak.bats` skips with a clear reason when the sibling fixture is absent, and still
      runs the real assertions when it is present
- [ ] `make test` green, UNPIPED, and report the real numbers:
      `make test > /tmp/mt.log 2>&1; echo "EXIT=$?"`, `grep -c '^ok '`, `grep -n '^not ok'`
- [ ] Green **without** the sibling repo reachable — prove the skip path works, e.g. run the
      keycloak suite with the sibling checkout temporarily unreadable or from a clean clone
- [ ] `make test-bin` green (108 cases)
- [ ] CI green on PR #128 — this is the gate that matters; local green is what hid the bug
- [ ] CHANGELOG `### Fixed` entry under `[1.35.0]`
- [ ] `memory-bank/activeContext.md` and `memory-bank/progress.md` updated with the SHA

## What NOT to Do

- Do NOT install ripgrep in CI.
- Do NOT vendor `realm-shopping-cart.json` into this repo.
- Do NOT revert `6064796c` to re-hide the suites.
- Do NOT create a PR, merge, commit to `main`, force-push, or use `--no-verify`.
- Do NOT touch a live cluster, `kubectl`, helm, docker, launchd, Keychain or Vault.
