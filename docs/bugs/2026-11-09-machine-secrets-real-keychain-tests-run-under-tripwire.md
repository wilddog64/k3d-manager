# Bug: machine-secrets real-Keychain tests run inside the tripwire, where they can never pass

**Status:** OPEN — child C4 of `docs/bugs/2026-11-09-offline-test-all-red-on-m4-four-root-causes.md`; spec written
**Priority:** P2
**Waiting on:** dispatch — since 2026-11-09
**Introduced by:** `bd68d6ff` (v1.43.12, 2026-10-31), which added both real-Keychain cases to a file that
`make test-bin` runs under `scripts/tests/tripwire.sh`
**Should have been caught by:** review
**Prior art:** none above threshold — exact-slug glob empty; `make find-similar-docs` not run to a result (vector
store unreachable from the M4, 2026-11-09)
**Severity:** medium — one case is permanently red under `make test-bin`; the other passes by skipping, so the real
round trip is never exercised by any gate
**Approval:** operator, 2026-11-09 (parent bug: one P2 parent with a child per root cause)
**Intent approved:** operator, 2026-11-09 ("C4 is approved"); dispatch go not yet given
**Filed:** 2026-11-09
**Detected by:** Claude, 2026-11-09, serial `make test-bin` baseline on the M4
**Release:** v1.43.16 (bug-only)
**Branch:** filed on `k3d-manager-v1.43.15`; fix goes on `k3d-manager-v1.43.16`

## Symptom

`make test-bin` on the M4, captured 2026-11-09:

- `scripts/tests/bin/machine_secrets.bats` "real throwaway keychain round trip is macOS only" (line 375) **fails** at
  line 378: `[ "$(command -v security)" = /usr/bin/security ]`. Under the tripwire, `security` resolves to the
  tripwire shim.
- "M6: stream unlock round trip uses throwaway keychains on macOS" (line 414) **passes by skipping**. The tripwire
  blocks `security create-keychain -p fixture-pass …/stream-source.keychain-db` with 97, the case hits its own
  `skip 'throwaway Keychain creation unavailable in this environment'`, and the blocked non-read call then fails
  the file.

So under the gate that runs these tests, one case can never pass and the other never tests anything.

## Root cause

Both cases deliberately use the real `/usr/bin/security` on throwaway keychains in `BATS_TEST_TMPDIR`, to prove the
encrypted export/import round trip against the real tool's encoding. That intent is sound: the hex `-X` and
multi-line values are exactly where stubs have lied before. But `make test-bin` runs every file in `scripts/tests/bin`
inside the tripwire, which exists to stop real `security` calls. The two goals cannot both hold in one suite.

A second hazard: `security create-keychain` adds the new keychain to the user's keychain search list. The cases
delete their keychains only on the success path (lines 410–411, 431–432). A failure in between leaves a search-list
entry pointing at a deleted temp file. The M4's list is clean today (`security list-keychains -d user` shows only
`login.keychain-db`, 2026-11-09).

## Fix

1. Move both cases unchanged in intent into a new file `scripts/tests/host/machine_secrets_real_keychain.bats`.
   `scripts/tests/host/` is a new directory for tests that must use a real host tool, and is not under any tripwire
   target. Delete them from `machine_secrets.bats`.
2. In the new file:
   - `setup` records `security list-keychains -d user`.
   - `teardown` deletes both throwaway keychains whatever the outcome, restores the recorded search list
     (`security list-keychains -d user -s …`), and fails if the list afterwards differs from the record.
   - Line 378's assertion stays, so the test refuses to run against anything but the real tool. Drop the `skip`
     fallback: on macOS, a failed `create-keychain` is a failure, not a skip.
   - Non-macOS keeps `require_macos`.
3. New Makefile target `test-host` runs `bats scripts/tests/host` on macOS, with no tripwire. It is not part of
   `test`, `test-bin`, `test-python` or `test-all`. Its help line says it touches the real Keychain tool and the
   user's search list, and restores the list.
4. No change to `bin/k3dm-machine-secrets`.

The two cases leave `make test-bin`, by design, not as a retirement: they move to `make test-host`. The parent's N1
case count for `test-bin` drops by exactly 2 for this reason.

## Contract readers

- `Makefile` gains `test-host`. `grep -n "test-host" Makefile` on 2026-11-09 finds no existing target of that name.
- `scripts/tests/bin/test_test_tripwire.py:40` asserts that the existing suite recipes go through the tripwire. It
  does not change: `test-host` is deliberately not in its list. Add an assertion that `test-host` is *not* wrapped,
  so the exception is explicit.
- No other reader of `scripts/tests/host/`: new path.

## Acceptance

```yaml
must:
  - id: M1
    text: make test-bin no longer contains either real-Keychain case, and machine_secrets.bats has zero failures and
      zero tripwire-blocked security calls.
  - id: M2
    text: make test-host on macOS runs both cases against /usr/bin/security and both pass, with no skip.
  - id: M3
    text: after make test-host, the user keychain search list is identical to before, including when a case fails
      partway.
must_not:
  - id: N1
    text: neither case is weakened; every assertion in the original two cases is still present in the moved file.
  - id: N2
    text: a case in the moved file must not pass when create-keychain fails (no skip fallback on macOS).
  - id: N3
    text: make test-host must not leave a keychain file or a search-list entry behind after any outcome.
evidence:
  - id: E1
    proves: M1
    kind: offline
    intent: make test-bin's machine-secrets file goes from 1 failure plus a blocked keychain call to zero of each.
  - id: E2
    proves: M2, N1
    kind: live
    intent: Claude runs make test-host on the M4 and both round trips pass against the real keychain tool, with a
      side-by-side list showing every original assertion survived the move.
  - id: E3
    proves: M3, N3
    kind: live
    intent: Claude records your keychain search list, runs make test-host once normally and once with a case forced
      to fail midway, and shows the list identical and no throwaway keychain left each time.
  - id: E4
    proves: N2
    kind: offline
    intent: With a create-keychain that fails, the moved case reports a failure, where before it reported a skip.
interface:
  - make test-host
  - make test-bin
  - scripts/tests/host/machine_secrets_real_keychain.bats
  - scripts/tests/bin/machine_secrets.bats
  - scripts/tests/bin/test_test_tripwire.py
```

E4 uses a `security` shim in `BATS_TEST_TMPDIR` whose `create-keychain` exits 1, as the tripwire's 97 does. The shim
asserts that it is the one resolved before the case runs. E2 and E3 are live, because they touch the real Keychain
tool: Claude runs them, never the worker or Gemini. The worker runs E1 and E4 only.

## Worker definition of done

- E1 and E4 run and pass. Paste each command, rc and the proving line.
- A diff of the two original cases against the moved file shows every assertion kept (for E2).
- The worker never runs `make test-host` or any real `security create-keychain`. Those are live, for Claude.
- `git diff --stat` touches only `machine_secrets.bats`, the new host file, `Makefile` and `test_test_tripwire.py`.
