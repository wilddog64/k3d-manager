# Bug: `make dr-drill` restore fails with an opaque `age: no identities found` when the login Keychain is locked

**Status:** OPEN — spec rev 1 (Fable review pending)
**Priority:** P2 (Claude's proposal; the drill cannot run from an SSH session, workaround: unlock the Keychain first)
**Introduced by:** edfc9a5c (v1.43.0, hub data restore)
**Should have been caught by:** offline test (empty identity from `_secret_load_data` is not rejected)
**Introducing change reviewed:** unknown
**Waiting on:** dispatch — since 2026-11-23 (Fable spec review)
**Triage:** patch → v1.45.1 (operator, 2026-11-23: v1.45.1 = security and DR release)
**Branch:** k3d-manager-v1.45.1
**Intent approved:** pending
**Prior art:** `docs/bugs/2026-11-14-acg-credentials-reports-empty-when-keychain-locked.md` (exact-slug glob + grep; vector store unavailable) — same class (locked Keychain read as empty), different component; closed there as P3, recurrence here in a release-gating path
**Detected by:** Claude, `make dr-drill` on m2-air sent by Claude to the operator's SSH pane (operator asked), 2026-11-23 ~05:00 PST

## Symptom

Phases 1–2 pass (with istioctl 1.31.4, see `2026-11-23-dr-drill-hub-up-istioctl-1-32-rejects-k3s-1-32.md`). Phase 3
restore clones the data repo, creates the PVCs, then:

    age: error: reading "/dev/fd/62": failed to read "/dev/fd/62": no identities found
    tar: short read
    make: *** [dr-drill] Error 1

after 17 minutes, rc=2.

## Root cause

`scripts/plugins/hub_data.sh:630` loads the identity with `_secret_load_data k3dm-hub-data-age identity age`. On macOS
that runs `security find-generic-password ... -w` under `|| true`
(`scripts/lib/foundation/scripts/lib/system.sh:614`). Over SSH the login Keychain is locked and needs UI; the read
returns empty, and lines 637/639 pass the empty string to `age -i <(...)`.

Evidence (read-only, m2-air, 2026-11-23, presence only): `security find-generic-password -s k3dm-hub-data-age`
rc=0 (item exists); `security show-keychain-info login.keychain-db` → `User interaction is not allowed.`

## Expected

- An empty identity fails before Phase 2 (preflight), with a message naming the locked Keychain and the unlock step,
  not 17 minutes later as an `age` parse error.
- Preflight checks the identity is readable (non-empty), without printing it.

## Workaround

In the SSH session, before the drill: `security unlock-keychain ~/Library/Keychains/login.keychain-db` (operator types
the password), then rerun.

## Fix (spec rev 1, Claude, 2026-11-23)

1. **Preflight, `bin/dr-drill` `_dr_drill_preflight`:** after `_dr_drill_install_credential_guard` (so the read goes
   through the security shim and is recorded against the `drill find k3dm-hub-data-age identity` allowlist row), read
   the identity once into a local variable, test only that it is non-empty and starts with `AGE-SECRET-KEY-1`, and
   discard it (`unset`). On failure call `_dr_drill_refuse` with: `[dr-drill] age identity unreadable (login Keychain
   locked over SSH?): run security unlock-keychain ~/Library/Keychains/login.keychain-db, then rerun`. Refusal happens
   before Phase 2, so no cluster is built. The value is never printed, logged, or put in argv.
2. **Restore, `scripts/plugins/hub_data.sh` after `:630`:** if the loaded identity is empty, print
   `ERROR: [hub-data] age identity is empty (locked Keychain?)` to stderr and `return 1`, without calling `_err`
   (which exits; see the V4 bug). This covers callers other than the drill (`hub_data_recover` rehearsals, `:1162`).
3. **`hub_data.sh:1162`:** the same empty check for `K3DM_HUB_DATA_AGE_IDENTITY_FROM_KEYCHAIN=1`.

## External behaviour

`security find-generic-password -w` against a locked login Keychain over SSH: item present (rc 0 for the metadata
lookup), value read prints nothing, and `show-keychain-info` says `User interaction is not allowed.` (m2-air,
2026-11-23, presence only, macOS `security` shipped with the OS). `_secret_load_data` turns that into an empty string
(`system.sh:614`, `|| true`). `age -i` given an empty identity file fails with `no identities found` (seen in the run).

## Contract readers

| Where | Reads | Change |
|---|---|---|
| `bin/dr-drill:163-182` `_dr_drill_preflight` | — | new identity check after the guard |
| `scripts/etc/dr/credential-allowlist.tsv:4` | `drill find k3dm-hub-data-age identity` | none (already allowed) |
| `scripts/etc/dr/security-shim` | records every `security` call | none; the preflight read appears once more in `credentials.tsv` |
| `scripts/plugins/hub_data.sh:624-640` restore | `K3DM_HUB_DATA_AGE_IDENTITY` or Keychain | empty check |
| `scripts/plugins/hub_data.sh:1156-1163` `hub_data_recover` | same | empty check |
| `scripts/tests/bin/dr_drill.bats`, `scripts/tests/plugins/hub_data.bats:210` | stub `_secret_load_data` / `security` | new cases |

## Acceptance

```yaml
must:
  M1: dr-drill refuses in Phase 1 (rc 2, no hub-up call, no cluster) when the identity read returns empty, with a message naming the locked Keychain and the unlock command
  M2: dr-drill continues to Phase 2 when the identity read returns an AGE-SECRET-KEY-1 value
  M3: the restore function returns 1 with an ERROR line, without exiting the shell, when the identity is empty
must_not:
  N1: the identity value appears in stdout, stderr, the phase log, credentials.tsv values or any argv
  N2: an empty identity reaches age (today it does, 17 minutes in)
  N3: existing dr_drill.bats and hub_data.bats tests change behaviour
evidence:
  - {id: E1, proves: [M1, N2], kind: offline, intent: "You will see a drill test where the fake Keychain returns nothing: the drill stops in Phase 1 with the unlock hint, and the fake hub-up was never called.", command: "bats scripts/tests/bin/dr_drill.bats", red: "today's tree: Phase 2 starts (hub-up logged), the test fails"}
  - {id: E2, proves: [M2, N1], kind: offline, intent: "You will see the same test with a fake key: the drill goes on to Phase 2, and the key string appears nowhere in the captured output or logs.", command: "same run, plus grep -r the sentinel over the test root returns only the stub's own file", red: "print the identity in the refuse message: the grep finds it"}
  - {id: E3, proves: [M3, N2], kind: offline, intent: "You will see a restore test with an empty identity return 1 with an ERROR line while the test shell keeps running, and the fake age never called.", command: "bats scripts/tests/plugins/hub_data.bats", red: "today's tree: fake age is called with an empty identity"}
  - {id: E4, proves: [N3], kind: offline, intent: "You will see both suites pass with no existing test edited.", command: "same runs; git diff shows only added tests", red: "n/a"}
  - {id: E5, proves: [M1], kind: live, intent: "You will see the operator run make dr-drill over SSH on m2-air with the Keychain locked and get the unlock hint within seconds instead of an age error after 17 minutes.", command: "make dr-drill (operator, m2-air SSH pane)", red: "n/a (live)"}
```

## Files

| File | Change |
|---|---|
| `bin/dr-drill` | identity presence check in `_dr_drill_preflight` |
| `scripts/plugins/hub_data.sh` | empty-identity checks at `:630` and `:1162` |
| `scripts/tests/bin/dr_drill.bats` | E1, E2 |
| `scripts/tests/plugins/hub_data.bats` | E3 |

## Routing

Luna, 2 logic files + 2 tests. Shares `hub_data.sh` with the V4 fix: dispatch after V4 lands, or as one task with it
(one per file rule).
