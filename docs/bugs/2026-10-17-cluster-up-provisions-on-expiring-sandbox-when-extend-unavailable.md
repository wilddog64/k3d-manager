# Bug: sandbox `make up` provisions on a sandbox about to expire when the extend fails

**Filed:** 2026-10-17 (Claude, during the operator's chained `make up` / `make down`, run started about 20:00 PDT)
**Status:** FIXED — 2026-10-17: `0ece6a8c` (Codex); Claude-verified (scope = spec, 3 files; `cluster_up.bats` 66/66; shellcheck 31 warnings before and after; all 6 new tests red against pre-fix 2c2dd4ba, including N1). Independent verifier (Sonnet, Acceptance-only, stubbed lib functions) PASSED: 19/19 post-fix incl. 59/60 floor boundaries, -1/empty TTL and both override directions; N1 red on pre-fix (7 pre-fix failures); re-run by Claude. Verifier notes: the N2 invalid-credentials case is only a source check; after a restart the TTL is not re-read (not required). Awaiting live E2
**Fix commit:** 0ece6a8c
**Priority:** P2 — the run can be cut off mid-provision when the sandbox expires; the workaround is to restart the sandbox by hand before `make up`
**Severity:** medium
**Approval:** approved — operator, 2026-10-17: "if you found any issue during run, feel free to debug and file bugs dispatch to codex, and rerun make up/down"
**Branch:** `k3d-manager-v1.43.4`
**Component:** `bin/cluster-up` Step 1 (k3s-aws TTL check, valid-credentials path)
**Related:** `docs/bugs/2026-05-19-acg-up-sandbox-ttl-check-before-provision.md` (added the TTL check and extend; did not cover an extend that cannot succeed); memory: an ACG sandbox lives 4h and can be extended once, to 8h

## Symptom

At the start of the run, Step 1 logged:

    INFO: [acg-up] Sandbox TTL: 38m remaining (< 120m threshold) — extending...
    INFO: Visible buttons at failure: ["Open navigation Menu","Open the search input","L","Learn More","Open Sandbox","15","Close","Delete Sandbox"]
    ERROR: Extend button not found or not visible after multiple attempts (including recovery)
    WARN: [acg-up] Sandbox extension failed — proceeding anyway

The k3s-aws provider's pre-flight extend failed the same way ("Pre-flight extend failed — proceeding").
Provisioning went ahead: CloudFormation stack, k3s, Cilium, ArgoCD, observability. Step 14b
finished at 20:37:32 PDT, about 5 minutes before the sandbox's shutdown time. A slower run would
have been cut off mid-provision.

## Root cause

The Extend button is missing because the sandbox's one extension was already used. That is
expected; no Playwright change can make it appear. In `bin/cluster-up` Step 1, a failed
`acg_extend_playwright` only warns, whatever the remaining TTL:

    acg_extend_playwright "${_acg_sandbox_ref}" || \
      _warn "[acg-up] Sandbox extension failed — proceeding anyway"

So when the extend fails and the remaining TTL is shorter than a provisioning run (about 35 minutes
here), `make up` builds a cluster that will die with the sandbox, or not finish.

## Fix (direction)

In that branch, when `acg_extend_playwright` fails, re-read the TTL with `acg_check_ttl`. If it is
below `ACG_MIN_PROVISION_MINUTES` (new, default `60`), log that the sandbox cannot be extended and
will expire before provisioning finishes, then call `acg_restart "${_acg_sandbox_ref}" aws` for a
fresh 4h sandbox and new credentials. If `acg_restart` fails, exit non-zero with `_err` (no
provisioning). If the TTL is at or above the floor, or can't be read (`-1` or empty), keep
today's warn-and-proceed. Don't change the path where the extend succeeds or isn't needed, or the
invalid-credentials path. The fix lives in `bin/cluster-up` only; `acg_restart` and
`acg_check_ttl` come from lib-foundation and are not changed.

Shape, so the logic can be tested the way `_acg_free_vault_local_port` is: move the TTL block in
Step 1 into `function _acg_ensure_sandbox_ttl()` in `bin/cluster-up` (takes the sandbox URL;
returns non-zero only when a needed restart fails). Step 1 calls it as
`_acg_ensure_sandbox_ttl "${_acg_sandbox_ref}" || exit 1` where the block was. Tests in
`scripts/tests/bin/cluster_up.bats` extract the function with
`sed -n '/^function _acg_ensure_sandbox_ttl()/,/^}$/p'` and stub the four lib functions.
Document both `ACG_MIN_REMAINING_MINUTES` (undocumented today) and `ACG_MIN_PROVISION_MINUTES` in
`docs/howto/acg.md` section "4. Extend Sandbox TTL": what `make up` does when the extend fails
(the sandbox gets one extension, to 8h).

## Acceptance

```yaml
must:
  - id: M1
    text: With valid credentials, TTL below ACG_MIN_REMAINING_MINUTES, a failed extend, and a re-read TTL below ACG_MIN_PROVISION_MINUTES (default 60), cluster-up Step 1 calls acg_restart once with the sandbox URL and provider aws, before any provisioning.
  - id: M2
    text: If that acg_restart fails, cluster-up exits non-zero and never reaches Step 2 (provisioning).
  - id: M3
    text: If the extend fails but the re-read TTL is at or above ACG_MIN_PROVISION_MINUTES, or cannot be read (-1 or empty), cluster-up warns and proceeds as before, with no acg_restart.
  - id: M4
    text: ACG_MIN_PROVISION_MINUTES overrides the 60-minute floor.
must_not:
  - id: N1
    text: cluster-up must not proceed to Step 2 on a sandbox whose extend failed and whose re-read TTL is below the floor without first restarting it (red on pre-fix, which warns and proceeds).
  - id: N2
    text: cluster-up must not call acg_restart when the extend succeeds, when the TTL is already at or above ACG_MIN_REMAINING_MINUTES, or on the invalid-credentials path.
evidence:
  - id: E1
    proves: [M1, M2, M3, M4, N1, N2]
    kind: offline
    text: BATS with acg_check_ttl, acg_extend_playwright, acg_restart and _acg_check_credentials stubbed (recording calls) and Step 2 stubbed to record that it ran; N1 red against pre-fix bin/cluster-up.
  - id: E2
    proves: [M1]
    kind: live
    text: Claude or the operator runs make up CLUSTER_PROVIDER=k3s-aws against a sandbox that was already extended once and has under 60 minutes left; the log shows the restart and provisioning starts on the new sandbox.
interface:
  - bin/cluster-up Step 1, k3s-aws branch, valid-credentials path
  - env ACG_MIN_REMAINING_MINUTES, ACG_MIN_PROVISION_MINUTES
  - functions acg_check_ttl, acg_extend_playwright, acg_restart, _acg_check_credentials (stub points)
```
