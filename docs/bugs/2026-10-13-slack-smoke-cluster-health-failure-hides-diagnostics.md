# Bug: Slack make smoke reports cluster-health FAIL without actionable diagnostics

**Status:** OPEN
**Priority:** P2
**Filed:** 2026-10-13
**Detected by:** human
**Branch:** `k3d-manager-v1.43.5` (triage 2026-10-15, operator-approved placement)
**Component:** Slack /k3dm Make dispatch, `scripts/plugins/smoke.sh`, `bin/smoke-test-cluster-health`

## Observed behavior

A Slack-triggered `make smoke` invocation reported:

```text
check           tier      status
webhook         offline   PASS
cluster-health  cluster   FAIL
  log: /var/folders/xc/ye_fyZ14272dpg2z7yqvg5w0000gn/T//k3dm-smoke/20261013T220207Z-34177/cluster-health.log
smoke: 1 passed, 1 failed, 0 skipped
make: *** [smoke] Error 1
```

Slack marked the Make job failed (`rc 2`), but did not include **which individual cluster-health assertion failed**. The operator may have only Slack access and cannot reasonably inspect a local transient path on M4. The actual cluster health root cause is **unknown** from this screenshot; do not assume unhealthy pods or missing ArgoCD resources.

## Source inspection

- `scripts/plugins/smoke.sh` executes `bin/smoke-test-cluster-health` with stdout/stderr redirected into a per-run `cluster-health.log`. It prints the log **path** on failure but not the failing lines or a bounded extract.
- `bin/smoke-test-cluster-health` already emits `[FAIL]` diagnostic lines for missing `ghcr-pull-secret` in shopping-cart namespaces, Argo CD Applications not `Synced`, and fewer than five Running pods. That useful evidence is hidden from the Slack response.
- Cluster precheck only skips when the infra context /readyz is unreachable. Running the cluster health script doesn't prove the app context is correct or ready; the script may fall back to infra context if destination is absent locally.

## Expected behavior

For Slack-initiated `make smoke`, deliver an actionable, **safe, bounded** diagnosis directly in the job's thread:

- Failed tier/check and subcheck(s), with sanitized `[FAIL]` lines or equivalent structured summary.
- Cluster/context names where safe, failure counts, and exact next diagnostic action when available.
- A stable job ID and an accessible follow-up command or supported artifact lookup to retrieve the fuller evidence, rather than relying solely on an M4-local temporary path.
- Preserve the underlying log artifact with defined retention, without leaking tokens, Keychain values, Kubernetes Secrets, or other sensitive output. Truncate and redact; do not blindly post full logs.
- Distinguish `smoke_check_failed`, `environment_unavailable`, and `diagnostics_unavailable` rather than conflating them with the Make wrapper's rc.

## Acceptance / regression tests

- [ ] Stub cluster-health emitting multiple `[FAIL]` lines: Slack shows specific reasons with a bounded, redacted diagnostic excerpt.
- [ ] Mixed PASS/FAIL: only relevant failures highlighted, with count and check names.
- [ ] Missing/unreadable log: Slack reports diagnostics unavailable plus actionable job identifier, not a misleading generic path.
- [ ] Long/multiline output, ANSI/control characters, and secret-like content are sanitized and truncated deterministically.
- [ ] Successful smoke job retains concise normal output.
- [ ] Confirm Slack output and local artifact agree on check outcome/exit status.
- [ ] Verify no unrelated cluster, rollout, or app behavior is changed.

## Scope and relationship

This is **reporting/diagnostic visibility**, not a fix for the unknown cluster-health failure. The operator should be able to debug remotely without shell access. Implementation may reuse existing webhook job-tail / artifact reporting with limits and RBAC rather than inventing a new log access path.

**No executable code or cluster resources changed as part of filing.**

## Files

- `scripts/plugins/smoke.sh`
- `scripts/tests/plugins/smoke.bats`

## Verification gates

- `bats scripts/tests/plugins/smoke.bats`
- `shellcheck scripts/plugins/smoke.sh`

Keep diagnostic capture bounded and redacted. Do not change cluster-health assertions or runtime cluster behavior for this reporting fix.
