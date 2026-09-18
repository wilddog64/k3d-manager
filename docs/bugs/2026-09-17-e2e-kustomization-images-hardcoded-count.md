# `make test` red: `_e2e_kustomization_images` count gate hardcodes 3 images

**Filed:** 2026-09-17
**Status:** FIXED (this spec)
**Suite:** `scripts/tests/plugins/e2e_image_prune.bats`
**Case:** 525 of `make test` (`1..924`)

## Symptom

`make test` fails on exactly one case:

```
not ok 525 _e2e_kustomization_images pairs newName with newTag from the real substrate
#   `[ "$(printf '%s\n' "$output" | grep -c ':')" -eq 3 ]' failed
```

CI is green. `make test` is red. Both have been true simultaneously since v1.34.0.

## Root cause

The test asserts a **hardcoded** image count against the **real** substrate file:

```bash
run _e2e_kustomization_images "${SCRIPT_DIR}/etc/e2e/kustomization.yaml"
...
[ "$(printf '%s\n' "$output" | grep -c ':')" -eq 3 ]
```

`978ea60f` (v1.34.0) added a fourth app to `scripts/etc/e2e/kustomization.yaml`:

```yaml
- name: shopping-cart-payment
  newName: ghcr.io/wilddog64/shopping-cart-payment
  newTag: sha-a672ee42f79db703f632baca3b05bf4f2b4d8718
```

`_e2e_kustomization_images` correctly emits 4 lines. The gate still expects 3.

**The production code is correct. The test is stale.** This is the inverse of the
`cluster_down.bats` test-15 finding earlier the same day — that one looked stale and was
a real bug; this one looks like a bug and is genuinely a stale assertion. Each was
established by reading the code path, not by guessing from which side failed.

## Why CI never caught it

`.github/workflows/ci.yml` runs a hand-maintained `bats` file list. It includes seven
named files from `scripts/tests/plugins/` — and `e2e_image_prune.bats` is not one of them.
`make test` discovers `lib`/`core`/`plugins` at `-maxdepth 1`, so it runs the file CI
cannot see. Tracked separately in
`2026-09-17-ci-bats-list-drift-from-make-test.md` — that drift is the reason a red suite
stayed invisible, and it is a bigger problem than this one-line gate.

## Fix

`scripts/tests/plugins/e2e_image_prune.bats`, the `pairs newName with newTag from the
real substrate` case. Two changes:

1. Add the missing `shopping-cart-payment` membership assertion, matching the three
   siblings already asserted.
2. Replace the hardcoded count with one **derived from the substrate file**, so adding a
   fifth app cannot redden the suite again.

```bash
@test "_e2e_kustomization_images pairs newName with newTag from the real substrate" {
  run _e2e_kustomization_images "${SCRIPT_DIR}/etc/e2e/kustomization.yaml"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ghcr.io/wilddog64/shopping-cart-product-catalog:sha-"* ]]
  [[ "$output" == *"ghcr.io/wilddog64/shopping-cart-basket:sha-"* ]]
  [[ "$output" == *"ghcr.io/wilddog64/shopping-cart-order:sha-"* ]]
  [[ "$output" == *"ghcr.io/wilddog64/shopping-cart-payment:sha-"* ]]
  # Derived from the substrate, never hardcoded: adding an app to
  # kustomization.yaml must not redden this gate (it did, in v1.34.0). Every
  # override in the real substrate is complete, so one emitted line per
  # newName is the contract — a half-written override SHOULD fail here.
  local expected
  expected="$(grep -c '^[[:space:]]*newName:[[:space:]]' \
    "${SCRIPT_DIR}/etc/e2e/kustomization.yaml")"
  [ "${#lines[@]}" -eq "$expected" ]
  local line
  for line in "${lines[@]}"; do
    [[ "$line" == *:* ]]
  done
}
```

The per-line `*:*` loop preserves what the old `grep -c ':'` was really guarding — that no
bare, untagged placeholder leaks through — and states it per line instead of as an
aggregate count. It is the idiom the sibling `_e2e_substrate_images` case at line 91
already uses.

`newName` is the correct denominator, not `newTag`: the function keys off a pending
`newName` and the very next test (`skips an entry that has newTag but no newName`) pins
the tag-only case against its own fixture, so this case does not need to cover it.

## Requirements

- Do NOT change `scripts/plugins/e2e.sh` — `_e2e_kustomization_images` is correct.
- Do NOT change `scripts/etc/e2e/kustomization.yaml` — the fourth app is intended.
- Do NOT weaken to `-ge`. The gate must still fail on a leaked extra line.
- No whole-line `grep -F` of source text, no bare `!` in the BATS body.

## Verification gate

- `bats scripts/tests/plugins/e2e_image_prune.bats` — all cases green.
- `make test` — `1..924`, **zero** failures.

## Definition of Done

- [x] Test derives its count from the substrate.
- [x] `shopping-cart-payment` asserted.
- [x] `make test` fully green.
- [x] CHANGELOG `### Fixed` entry.
- [x] memory-bank open item cleared.

## What NOT to Do

- Do NOT "fix" the count by bumping `3` to `4`. That re-arms the exact trap for the fifth
  app and is why this gate broke silently in the first place.
- Do NOT add `e2e_image_prune.bats` to the CI list as the fix for the invisibility. The
  list itself is the defect; see the drift spec.
