# Bug: `make dr-drill` restore fails with an opaque `age: no identities found` when the login Keychain is locked

**Status:** OPEN — captured 2026-11-23 by Claude from the m2-air drill run
**Priority:** P2 (Claude's proposal; the drill cannot run from an SSH session, workaround: unlock the Keychain first)
**Introduced by:** edfc9a5c (v1.43.0, hub data restore)
**Should have been caught by:** offline test (empty identity from `_secret_load_data` is not rejected)
**Introducing change reviewed:** unknown
**Waiting on:** operator decision — since 2026-11-23
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
