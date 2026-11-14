# `ACG_CREDENTIALS` reports `empty` when the login Keychain is locked

**Status:** OPEN — captured, not triaged
**Priority:** P3
**Waiting on:** operator decision — since 2026-11-14
**Introduced by:** unknown
**Should have been caught by:** spec
**Severity:** low — misleading diagnosis only; the login fails either way, but the operator is pointed at the item
contents instead of the locked Keychain
**Approval:** none yet (captured per "capture first, triage later", 2026-11-11)
**Prior art:** `docs/bugs/2026-11-08-find-similar-docs-rc36-hint-skips-locked-keychain.md` (found by grep, not scored) —
read, same class (a locked Keychain is reported as something else), different code path. `find-similar-docs` not run:
the store needs kube context `k3d-k3d-cluster`, absent on this host.
**Filed:** 2026-11-14
**Detected by:** Claude, 2026-11-14 ACG login session (operator not at the M4)
**Affected:** lib-foundation `scripts/lib/acg/cdp.sh` (`_cdp_ensure_acg_session`, lines 199-200),
`scripts/lib/acg/acg_session_check.js` (`_credentialState`) — fix upstream, then subtree-pull
**Branch:** `k3d-manager-v1.44.0`

## Symptom

With the login Keychain locked, the session check prints `ACG_CREDENTIALS: username=empty password=empty`. The
item holds both values; nothing is empty.

## Cause (from source, not yet reproduced live)

`_cdp_ensure_acg_session` reads both fields with
`_acg_user="$(_secret_load_data k3dm-acg-pluralsight username 2>/dev/null || true)"` (same for `password`). A locked
Keychain makes `security` fail. The error is discarded and the variable is set to `""`, so `_credentialState`
classifies `''` as `empty`. The states `locked` and `unreadable` cannot appear in the report.

## Fix direction (for triage)

Keep the loader's exit status and tell the JS about it (for example `ACG_CREDENTIALS_LOAD=locked|unreadable|ok`), so
the report shows `locked` and `K3DM_ACG_REQUIRE_CREDENTIALS=1` fails fast with a Keychain hint. The related ideas row
"ACG login without operator at the M4" (locked-Keychain fail-fast) is ranked at grooming 2026-11-15.
