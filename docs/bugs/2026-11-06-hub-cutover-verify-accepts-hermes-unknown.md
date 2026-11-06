# Bug: hub-cutover verify passes when Hermes and the webhook check could not look

**Status:** OPEN — observed 2026-11-06 on the M5, in the operator's `make hub-cutover-forwards` run
**Priority:** P2
**Approval:** operator, 2026-11-06: "dispatch them in a batch base on dependencies or priority"
**Branch:** `k3d-manager-v1.43.14`
**Related:** `docs/bugs/2026-11-06-hub-cutover-leaves-hermes-argocd-token-dead.md`; `docs/bugs/2026-11-06-hub-cutover-verify-fails-forever-after-old-cluster-is-stopped.md`

## Symptom

The run printed all of these and still ended `hub-cutover: verification passed`:

- `"classification": "keychain_interaction_required"` and `HTTP health was not tested` from the webhook check.
- `"evidence": "cluster status source unavailable"`, `"status": "unknown"` from `bin/k3dm-hermes status`.
- `Operator check: confirm a Hermes message arrives in Slack.` No message arrived, and none could be expected: nothing sends one, and Hermes posts only on an event (0 events in 1,352 cycles since 2026-10-31).

The same session showed Hermes blind to ArgoCD and to alert delivery, so the gate passed over a monitor that could not see.

## Cause

`verify_cutover` in `bin/hub-cutover` runs `bin/k3dm-hermes status || return 1`, which tests only the exit code. `unknown` exits 0. The Slack line is printed text with no check behind it.

## Files

- `bin/hub-cutover`
- `scripts/tests/bin/hub_cutover.bats`

## Fix direction

Parse the status and fail on `unknown`, naming the reason. Report a webhook check that did not run as not verified, with the unlock step, rather than as a pass. Replace the Slack line with either a real test post or a statement that delivery was not tested.

## Captured contract (Claude, 2026-11-06)

`bin/k3dm-hermes status` reports one sensor, `status_checks`, and exits 0 when it is `unknown`. Captured from `m5-air.local`, 2026-11-06T15:50:35Z, over SSH with a locked Keychain:

    {"data": {"checks": [], "counts": {}, "failed_ids": [], "warned_ids": []}, "evidence": "cluster status source unavailable", "sampled_at": "2026-11-06T15:50:35Z", "sensor": "status_checks", "status": "unknown"}

Parse `status` and `evidence` with `jq`. This check covers only this one record: `alert_delivery` and `argocd` are not in this output, so the known `alert_delivery` `unknown` does not block it. `degraded` and `failed` are not in this bug's scope.

Dispatch order: land this first. `2026-11-06-hub-cutover-leaves-hermes-argocd-token-dead` edits the same function afterwards.

## Acceptance

```yaml
must:
  - id: M1
    text: "Verification fails and prints the evidence when Hermes status is unknown."
  - id: M2
    text: "Verification passes this check when Hermes status is healthy."
  - id: M3
    text: "When the webhook check reports keychain_interaction_required, the output says HTTP health was not verified and gives the unlock command."
must_not:
  - id: N1
    text: "The output does not claim Slack delivery was checked unless a post was made and accepted (paired with M2)."
evidence:
  - {id: E1, proves: [M1, M2, M3, N1], kind: offline, text: "BATS with stubs whose output is captured from the 2026-11-06 M5 run; M1 red on the pre-fix commit; N1 red by a mutant."}
  - {id: E2, proves: [M2], kind: live, text: "make hub-cutover-verify on the M5 from an unlocked shell, after the token is re-minted."}
interface:
  - "bin/hub-cutover --verify"
  - "env: HOME, HUB_OLD_HOST, HUB_CUTOVER_STATE_DIR, PATH (stubs)"
```
