# Bug: `codex-dispatch verify` records a pass with no evidence, so "verified" on the dashboard can be a bare claim

**Status:** OPEN
**Priority:** P1
**Severity:** high — the release gate trusts a `verified` column that nothing backs; the operator cannot tell a verified fix from one Claude said was verified. Second occurrence (operator, 2026-11-01: "this is the second time that this happened")
**Approval:** operator, 2026-11-01 ("we need to fix this problem otherwise, I have no idea if they have been verified or just you said so")
**Filed:** 2026-11-01
**Detected by:** operator, k3dm-bugs dashboard review of PR #155
**Affected:** `bin/k3dm-codex-dispatch` (`_dispatch_verify`, ~line 330), `bin/k3dm-dispatch-metrics` and the k3dm-bugs dashboard's verified column
**Branch:** `k3d-manager-v1.43.14`

## Observed failure

On 2026-11-01 the dashboard showed three v1.43.13 fixes as "not yet" verified: P1 pre-push gate, P2 hub migration Slack
config, and P2 `machine_setup.bats` TTY hang. Each doc's Status says "independent verifier PASS", but the ledger had no
`verify` event. Claude ran `verify --result pass --verifier claude` for all three, using only that doc text. Nothing was
re-run, and no verifier output exists on disk: each `.run/` directory holds land logs only. The operator challenged
this, and Claude removed the three events (ledger lines 1555-1557, backup in the session scratchpad).

The other 38 `verify` events in the ledger have the same flaw. A verifier subagent's report reaches only the Claude
session transcript, and the event stores just `result` and `verifier`.

## Root cause

`verify` accepts `--result pass` with no proof. It does not require the verifier's test command, rc, output, or the
red-on-pre-fix run, and it stores nothing in the run directory. The dashboard shows the event as fact.

## Fix

- `verify` requires `--evidence FILE`. It refuses a missing or empty file, or one without these fields:
  - `command:` and `rc:` for the green run on the fix commit, with that commit's SHA
  - `pre_fix_command:`, `pre_fix_rc:` (non-zero) and the pre-fix SHA, for each must_not
  - `verifier:` and `tests_from: acceptance` (the verifier wrote its tests from the Acceptance block)
- It copies the file to `<run>/verify-evidence.<n>.log` and records its sha256 and path in the `verify` event.
- The dashboard counts a fix as verified only when the event has evidence. A legacy `verify` event with no evidence
  shows as "claimed", not "verified".
- The verifier subagent prompt template writes this file itself, so its own output is the evidence, not Claude's
  summary of it.

## What NOT to do

- Do not let Claude build the evidence file from a doc or memory. It must be the verifier's captured run output.
- Do not rewrite or delete the existing 38 legacy events. Mark them "claimed" on the dashboard.

## Acceptance

```yaml
must:
  M1: verify --result pass --evidence F with every required field records an event with evidence_sha256 and evidence_path, and the file exists under the run dir (paired positive control for N1)
  M2: the dashboard query counts a verify event with evidence as verified and a legacy event without evidence as claimed
must_not:
  N1: verify --result pass with no --evidence, an empty file, or a file missing a required field never writes a verify event, and exits non-zero
  N2: a pre_fix_rc of 0 is refused (a must_not that never went red proves nothing)
evidence:
  E1:
    proves: [M1, N1, N2]
    kind: offline
    intent: You will see bats with a scratch K3DM_WORKTREE_ROOT (asserted not the real one) show verify refused with no, empty, partial or pre_fix_rc 0 evidence, writing no event (red on the pre-fix dispatcher, which records them), and accepted with a complete file whose sha256 matches the copy under the run dir.
    what: bats scripts/tests/bin/codex_dispatch.bats
  E2:
    proves: [M2]
    kind: live
    intent: You will see the k3dm-bugs dashboard show a newly verified fix as verified and a legacy one as claimed.
    what: operator screenshot after the dashboard syncs
interface:
  - bin/k3dm-codex-dispatch verify --slug S --result pass|fail --evidence FILE [--verifier NAME]
  - ledger.jsonl under K3DM_WORKTREE_ROOT
```
