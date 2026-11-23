# Bug: `make dr-drill` restore fails with an opaque `age: no identities found` when the login Keychain is locked

**Status:** LANDED — `77d5a836` on k3d-manager-v1.45.1 (2026-11-23), Sonnet acceptance verify pass; E6 live (operator, m2-air drill) pending; was: OPEN — spec rev 2
**Priority:** P2 (Claude's proposal; the drill cannot run from an SSH session, workaround: unlock the Keychain first)
**Introduced by:** edfc9a5c (v1.43.0, hub data restore)
**Should have been caught by:** offline test (empty identity from `_secret_load_data` is not rejected)
**Introducing change reviewed:** unknown
**Waiting on:** live check — since 2026-11-23
**Triage:** patch → v1.45.1 (operator, 2026-11-23: v1.45.1 = security and DR release)
**Branch:** k3d-manager-v1.45.1
**Intent approved:** operator, 2026-11-23
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

In the SSH session, before the drill: `security unlock-keychain ~/Library/Keychains/login.keycha## Fix (spec rev 2, Claude, 2026-11-23)

1. **New helper in `bin/dr-drill`, `_dr_drill_identity_ok`:** returns 0 when the identity the restore will use is
   readable and starts with `AGE-SECRET-KEY-1`, else 1. It prints nothing.
   - If `K3DM_HUB_DATA_AGE_IDENTITY` is already set, test that value (the restore never reads the Keychain then,
     `hub_data.sh:623-624`).
   - Otherwise read it with `_secret_load_data k3dm-hub-data-age identity age` into a `local`, tolerating its rc 1 on
     empty (`system.sh:619-621`; use `|| true`), test the prefix, then `unset` the local.
   - The read goes through `bash -c 'security …'` inside `_secret_load_data`, which resolves the drill's shim symlink on
     the exported PATH (`bin/dr-drill:47-51`) and is recorded against the `drill find k3dm-hub-data-age identity`
     allowlist row. Do not call `security` or the `security()` shell function (`bin/dr-drill:52`) directly.
2. **Call it through `_no_trace`** (`system.sh:2238`), so neither the assignment nor the `[[ … == AGE-SECRET-KEY-1* ]]`
   test is printed under `bash -x`.
3. **Placement:** in `_dr_drill_preflight`, right after `_dr_drill_install_credential_guard` (`bin/dr-drill:179`) and
   before `_dr_drill_latest_export` (`:180`, a git clone), so the refusal is immediate. On failure:
   `_dr_drill_refuse '[dr-drill] age identity unreadable (login Keychain locked over SSH?): run security unlock-keychain ~/Library/Keychains/login.keychain-db, then rerun'`.
   The value is never printed, logged or put in argv.
4. **Restore, `scripts/plugins/hub_data.sh` after `:630`:** if the identity is empty, print
   `ERROR: [hub-data] age identity is empty (locked Keychain?)` to stderr and `return 1`, without `_err`. The caller
   `_hub_data_copy_claim` (`:665`) already handles it with `|| return 1` (`:705`). This covers runs that bypass the drill
   preflight.
5. **Dropped from rev 1:** the check at `:1162`. `hub_data.sh:1170-1173` already rejects an identity that does not
   start with `AGE-SECRET-KEY-1` (return 1). Its only flaw, the "age identity loaded from the Keychain" line at `:1164`
   printed even when empty, is cosmetic and left alone.
6. **Known limit:** the prefix check rejects an item stored as a whole `age-keygen` file (leading `#` comment lines).
   That matches `:1170`.

## Root cause correction

`_secret_load_data` returns 1 (not an empty string with rc 0) when the read is empty (`system.sh:619-621`). `:630`
survives that only because errexit is suppressed by the caller's `||` at `:705`, so `identity` stays empty and reaches
`age`.

## External behaviour

`security find-generic-password -w` against a locked login Keychain over SSH: the item exists (metadata lookup rc 0)
and `show-keychain-info` says `User interaction is not allowed.` (m2-air, 2026-11-23, presence only, the OS's
`security`). That the `-w` read returns empty without hanging is inferred from the drill run (it reached `age` with an
empty identity), not from a direct capture. `age -i` with an empty identity fails with `no identities found` (seen in
the run).

## Contract readers

| Where | Reads | Change |
|---|---|---|
| `bin/dr-drill:163-182` `_dr_drill_preflight` | — | calls the new helper after `:179` |
| `bin/dr-drill:40-53` credential guard, `scripts/etc/dr/security-shim` | every `security` call | none; the read is recorded once more (`credentials_read` is de-duplicated with `unique`, `:58`) |
| `scripts/etc/dr/credential-allowlist.tsv:4` | `drill find k3dm-hub-data-age identity` | none |
| `scripts/etc/dr/credential-allowlist.tsv:15` | `restore-drill` row, used by `hub_data.sh:1162` | none |
| `bin/dr-drill:262` | runs restore as a child `scripts/k3d-manager hub_data_restore` (inherits the shim PATH) | none |
| `scripts/plugins/hub_data.sh:623-640` `_hub_data_restore_one` | env identity or Keychain | empty check after `:630` |
| `scripts/plugins/hub_data.sh:665,705` `_hub_data_copy_claim` | rc of the restore | none |
| `scripts/tests/bin/dr_drill.bats:68-84` `security` / `secret-tool` stubs | return `SHARDSENTINEL` for any other item | each gains a `*k3dm-hub-data-age*` case returning a fake `AGE-SECRET-KEY-1…` value |
| `scripts/tests/plugins/hub_data.bats:210,1394-1406,1586-1600` | identity stubs | unchanged; stay green |

## Acceptance

```yaml
must:
  M1: dr-drill refuses in Phase 1 (rc 2, before the export clone, no hub-up call) when the identity read is empty, with a message naming the locked Keychain and the unlock command
  M2: dr-drill continues to Phase 2 when the identity read returns an AGE-SECRET-KEY-1 value, or when K3DM_HUB_DATA_AGE_IDENTITY is already set to one (no Keychain read then)
  M3: the restore returns 1 with an ERROR line, without exiting the shell, when the identity is empty
must_not:
  N1: the identity value appears in stdout, stderr, the phase log, credentials.tsv or any argv, including under bash -x
  N2: an empty identity reaches age
  N3: an existing assertion in dr_drill.bats or hub_data.bats changes (setup stubs gain one case each)
evidence:
  - {id: E1, proves: [M1, N2], kind: offline, intent: "You will see a drill test where the fake Keychain returns nothing for the age key: the drill stops in Phase 1 with the unlock hint, before the export clone, and the fake hub-up was never called.", command: "bats scripts/tests/bin/dr_drill.bats", red: "today's tree: preflight passes and hub-up is logged"}
  - {id: E2, proves: [M2, N1], kind: offline, intent: "You will see the same test with a fake key, run once normally and once with bash -x: the drill goes on to Phase 2, and the key string appears nowhere in the captured output, logs or trace.", command: "same run; grep -r of the sentinel over the test root and the captured stderr finds only the stub's own file", red: "put the prefix test outside _no_trace: the trace run prints the sentinel"}
  - {id: E3, proves: [M2], kind: offline, intent: "You will see a drill test with the key already in K3DM_HUB_DATA_AGE_IDENTITY: preflight passes and the fake Keychain is never asked for it.", command: "same run; phase log has no security call for k3dm-hub-data-age", red: "always read the Keychain: the call appears"}
  - {id: E4, proves: [M3, N2], kind: offline, intent: "You will see a restore test with an empty identity return 1 with an ERROR line while the test shell keeps running, and the fake age never called.", command: "bats scripts/tests/plugins/hub_data.bats", red: "today's tree: fake age is called with an empty identity"}
  - {id: E5, proves: [N3], kind: offline, intent: "You will see both suites pass, with the diff of the .bats files showing only new tests and one added stub case each.", command: "same runs; git diff of the two .bats files", red: "n/a"}
  - {id: E6, proves: [M1], kind: live, intent: "You will see the operator run make dr-drill over SSH on m2-air with the Keychain locked and get the unlock hint within seconds instead of an age error after 17 minutes.", command: "make dr-drill (operator, m2-air SSH pane)", red: "n/a (live)"}
interface:
  - "bin/dr-drill: _dr_drill_identity_ok (new, no args, no output, rc 0/1)"
  - "hub_data.sh: _hub_data_restore_one signature unchanged"
```

## Files

| File | Change |
|---|---|
| `bin/dr-drill` | `_dr_drill_identity_ok`, called in `_dr_drill_preflight` |
| `scripts/plugins/hub_data.sh` | empty-identity check after `:630` |
| `scripts/tests/bin/dr_drill.bats` | stub cases; E1-E3 |
| `scripts/tests/plugins/hub_data.bats` | E4 |

## Routing

Luna, one task together with the V4 fix (both touch `hub_data.sh` and `hub_data.bats`).
