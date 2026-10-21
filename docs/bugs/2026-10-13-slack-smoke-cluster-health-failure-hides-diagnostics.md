# Bug: Slack make smoke reports cluster-health FAIL without actionable diagnostics

**Status:** LIVE-VERIFIED — Slack job `a3d1097b` surfaced the bounded `[TARGET]` reason and both candidate contexts after the webhook restart; smoke correctly failed closed on ambiguous target selection
**Live evidence:** 2026-10-21 · run a3d1097b · env Slack/Make · scenario smoke-target-diagnostic-output · commit 36dfb1e2 · proves fix
**Fix commit:** `36dfb1e2`
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
- [ ] A target-selection failure beginning with `[TARGET]` includes its bounded diagnostic and the following candidate/context lines; it must not be reported as `diagnostics_unavailable`.
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

## Offline verification — 2026-10-20

- Landed on `k3d-manager-v1.43.5` as commit `30236df8`.
- `bats scripts/tests/plugins/smoke.bats`: 10/10 passed.
- `shellcheck scripts/plugins/smoke.sh`: clean (exit 0).
- `_agent_audit`: passed in the commit hook.
- At initial offline verification, no live Slack smoke command had been run.

## Live verification attempt — 2026-10-21

The operator's Slack `/make smoke` run returned `diagnostics_unavailable`. The retained
`cluster-health.log` shows that the health check failed before assertion checks because two
shopping-cart targets were found. The reporter only extracts `[FAIL]` lines, so it omitted the
actionable `[TARGET]` explanation. See `docs/issues/2026-10-21-slack-live-verification-results.md`.
This reopened the bug and led to the follow-up below; do not mark LIVE-VERIFIED until the operator
repeats the Slack check against the restarted webhook.

### Follow-up dispatch evidence

The exact retained log for Slack job `09e916e4` was:

```text
[TARGET] expected exactly one shopping-cart target, found 2
  ubuntu-hostinger-shopping-cart-basket -> ubuntu-hostinger
  ubuntu-k3s-shopping-cart-basket -> ubuntu-k3s
/Users/cliang/src/gitrepo/personal/k3d-manager/scripts/../bin/smoke-test-cluster-health command failed (2): /Users/cliang/src/gitrepo/personal/k3d-manager/scripts/../bin/smoke-test-cluster-health
ERROR: failed to execute /Users/cliang/src/gitrepo/personal/k3d-manager/scripts/../bin/smoke-test-cluster-health: 2
```

Follow-up implementation must report the `[TARGET]` reason and bounded candidate context as
actionable diagnostics, while preserving redaction and the five-line/240-character bounds. Keep
the fix in `scripts/plugins/smoke.sh` and `scripts/tests/plugins/smoke.bats`; do not modify
`bin/smoke-test-cluster-health` or cluster behavior.

### Follow-up offline verification — 2026-10-21

- Follow-up landed as `36dfb1e2`; it recognizes `[TARGET]` diagnostics and includes indented
  candidate/context lines, while retaining the existing sanitization and output bounds.
- `bats scripts/tests/plugins/smoke.bats`: 11/11 passed; `shellcheck scripts/plugins/smoke.sh`:
  clean; `_agent_audit` passed in the commit hook.
- Status is VERIFIED offline. Operator must restart the webhook and rerun `/make smoke` for
  live verification.

### Live verification — 2026-10-21

After the webhook restart, Slack job `a3d1097b` returned the target-selection diagnostic and
candidate details directly in the thread:

```text
make smoke queued — job a3d1097b
make smoke started by slack:wilddog64:U4C9LDQP2 — job a3d1097b
make smoke failed (rc 2) — job a3d1097b
./scripts/k3d-manager smoke_run
running under bash version 5.3.20(1)-release
check           tier      status
webhook         offline   PASS
cluster-health  cluster   FAIL
  log: /var/folders/xc/ye_fyZ14272dpg2z7yqvg5w0000gn/T//k3dm-smoke/20261021T011004Z-55192/cluster-health.log
  smoke_check_failed: 1 cluster-health failure(s)
  [TARGET] expected exactly one shopping-cart target, found 2
    ubuntu-hostinger-shopping-cart-basket -> ubuntu-hostinger
    ubuntu-k3s-shopping-cart-basket -> ubuntu-k3s
  Next: retrieve the full bounded job transcript with /k3dm logs <job-id>.
smoke: 1 passed, 1 failed, 0 skipped
make: *** [smoke] Error 1
```

The reporting fix is LIVE-VERIFIED: the Slack output contains the actionable bounded target
diagnostic and candidates. The smoke command's nonzero result is a separate, intentional
fail-closed response to two eligible targets; it is not evidence that the reporter regressed.
Slack currently does not allow passing `ARGOCD_APP_PREFIX`, so selection support is tracked in
`docs/bugs/2026-10-21-slack-smoke-target-override-not-allowlisted.md`.

Keep diagnostic capture bounded and redacted. Do not change cluster-health assertions or runtime cluster behavior for this reporting fix.
