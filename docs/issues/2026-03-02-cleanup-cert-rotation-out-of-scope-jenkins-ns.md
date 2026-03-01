# P1: `_cleanup_cert_rotation_test` Uses Out-of-Scope `jenkins_ns`

**Date:** 2026-03-02
**Reported:** Codex bot review comment on PR #8
**Status:** FIXED — `_cleanup_cert_rotation_test` now reads `${JENKINS_NAMESPACE:-cicd}` directly
**Severity:** P1
**Type:** Bug — unbound variable under `set -u`, cleanup silently fails

---

## What Was Reported

The Codex bot flagged that `_cleanup_cert_rotation_test()` dereferences `${jenkins_ns}`,
but `jenkins_ns` is declared as `local` inside the calling function `test_cert_rotation`.
When the EXIT trap fires, `jenkins_ns` is out of scope and unbound under `set -u`,
causing cleanup to error rather than delete the test job.

---

## Root Cause

**File:** `scripts/lib/test.sh`

```bash
# Line 829 — trap set BEFORE jenkins_ns is defined
trap '_cleanup_cert_rotation_test' EXIT TERM

# Line 832 — local variable, not accessible from called functions
local jenkins_ns="${JENKINS_NAMESPACE:-cicd}"
```

```bash
# Line 1060-1064 — cleanup function references out-of-scope local
function _cleanup_cert_rotation_test() {
  _kubectl delete job test-cert-rotation -n "${jenkins_ns}" 2>/dev/null || true
  _info "Certificate rotation test cleanup complete"
}
```

In bash, `local` variables are scoped to the function they are declared in and
its children on the call stack. `_cleanup_cert_rotation_test` is a separate
global function invoked by the EXIT trap — not a child call of `test_cert_rotation`.
When the trap fires, `jenkins_ns` is unset, and `set -u` (active in this repo's
scripts via `set -euo pipefail`) causes an `unbound variable` error.

The effect: the test job `test-cert-rotation` is never cleaned up when `test_cert_rotation`
exits abnormally, leaving a stale job in the cluster.

---

## Fix

In `_cleanup_cert_rotation_test`, replace `"${jenkins_ns}"` with
`"${JENKINS_NAMESPACE:-cicd}"` — the same expression used to define `jenkins_ns`
in the calling function.

**Exact change in `scripts/lib/test.sh` line 1062:**

```bash
# Before:
  _kubectl delete job test-cert-rotation -n "${jenkins_ns}" 2>/dev/null || true

# After:
  _kubectl delete job test-cert-rotation -n "${JENKINS_NAMESPACE:-cicd}" 2>/dev/null || true
```

No other changes needed.

---

## Resolution & Verification (2026-03-02)

- Patched `scripts/lib/test.sh` so the cleanup trap always references
  `${JENKINS_NAMESPACE:-cicd}`, eliminating the out-of-scope variable and keeping
  behavior consistent with the main function.
- Re-sourced `_cleanup_cert_rotation_test` indirectly by running
  `PATH="/opt/homebrew/bin:$PATH" bats scripts/tests/plugins/eso.bats` for sanity;
  no Jenkins-specific automated test exists for this helper.

---

## Risk Assessment

| Factor | Assessment |
|---|---|
| Correctness | Cleanup silently fails under `set -u` — stale jobs left in cluster |
| Scope | Only `test_cert_rotation` / `_cleanup_cert_rotation_test` |
| Fix risk | Minimal — one-line change, same expression already used in calling function |
| Severity | P1 — causes resource leak on test failure |
