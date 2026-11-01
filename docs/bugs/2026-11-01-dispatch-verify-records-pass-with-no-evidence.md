# Bug: `codex-dispatch verify` records a pass with no evidence, so "verified" on the dashboard can be a bare claim

**Status:** VERIFIED — 2026-11-01: fixed `6fe94bda` (Luna; Claude added cross-repo SHA resolution from `<run>/repo`); land TEST codex_dispatch.bats + agent_dispatch_dashboard.bats + test_dispatch_metrics.py passed; independent Acceptance-only suite (Sonnet verifier) 12/12 on `6fe94bda`, 11/12 red on pre-fix `90380e17` (M3 green on both, as expected); verify recorded with evidence sha256 `e6a2c500…`. E3 live (dashboard "Claimed, no evidence" panel) pending — needs `make platform-ops` on the M5
**Priority:** P1
**Severity:** high — the release gate trusts a `verified` column that nothing backs; the operator cannot tell a verified fix from one Claude said was verified. Second occurrence (operator, 2026-11-01: "this is the second time that this happened")
**Approval:** operator, 2026-11-01 ("we need to fix this problem otherwise, I have no idea if they have been verified or just you said so"); dispatch go: operator, 2026-11-01 ("go ahead to dispatch P1 bug to Luna")
**Filed:** 2026-11-01
**Detected by:** operator, k3dm-bugs dashboard review of PR #155
**Affected:** `bin/k3dm-codex-dispatch` (`_dispatch_verify`, ~line 334), `bin/k3dm-dispatch-metrics` (`_verification_metrics` ~line 899 and the other `verify` readers ~1147, ~1774) and the Agent Dispatch dashboard's verification panels
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

Spec correction (Claude, 2026-11-01, before dispatch): the k3dm-bugs dashboard's Verified and Live-verified columns
come from each bug doc's Status text via `bin/k3dm-vectordb-metrics`, not from the ledger, so they are out of scope.
The ledger `verify` events feed `bin/k3dm-dispatch-metrics` (delivered / awaiting / unknown, verified outputs per
quota point) and the Agent Dispatch dashboard. That is where "verified" must require evidence.

1. `verify --result pass` requires `--evidence FILE`. `--result fail` accepts it and does not require it. Refuse
   (non-zero exit, no ledger event, no copied file) when the file is missing, empty, or fails the format below.
2. Evidence file format: plain text. Header lines are `key: value`, one per line, at column 0, before a line that
   reads exactly `---`. After that line comes the verifier's raw captured output (free text, at least one line).
   Required keys:
   - `verifier:` name, same charset as `--verifier`; if `--verifier` is also given, the two must match
   - `tests_from: acceptance` (literal)
   - `fix_sha:` 7-40 hex, and it must resolve to a commit in the repo (`git cat-file -e "<sha>^{commit}"`)
   - `command:` non-empty; `rc: 0`
   - one or more `pre_fix_sha:` / `pre_fix_command:` / `pre_fix_rc:` triples, in that order, one triple per
     must_not; each `pre_fix_sha` resolves to a commit and each `pre_fix_rc` is a non-zero integer
3. On success, copy the file to `<run>/verify-evidence.<n>.log` (`<n>` = 1 + the count already there) and add
   `evidence_path` (relative to `K3DM_WORKTREE_ROOT`) and `evidence_sha256` (of the copy) to the `verify` event.
4. `bin/k3dm-dispatch-metrics`: a `pass` counts as verified (delivered, verified outputs) only when the event carries
   `evidence_sha256`. A `pass` without it is **claimed**: the task stays in awaiting, and a new
   `k3dm_dispatch_verification_claimed{window="..."}` gauge counts those tasks. Do not edit the ledger.
5. Agent Dispatch dashboard: add a "Claimed, no evidence" stat beside "Awaiting verification", with a description
   saying a claimed pass has no verifier output on file.
6. `docs/howto/codex-dispatch.md` "Independent verification and delivered cost": document `--evidence`, the format
   with an example file, and a verifier-prompt paragraph telling the verifier to write this file itself (its own
   captured output, not a summary by Claude).

## Files

| File | Change |
|---|---|
| `bin/k3dm-codex-dispatch` | `--evidence` parsing, validation, copy, event fields |
| `bin/k3dm-dispatch-metrics` | evidence-backed pass vs claimed; new gauge |
| `scripts/etc/argocd/platform-ops/grafana-dashboard-agent-dispatch.yaml` | "Claimed, no evidence" stat |
| `scripts/tests/bin/codex_dispatch.bats` | E1 |
| `scripts/tests/bin/test_dispatch_metrics.py` | E2 (offline half), plus any panel-count pins the new stat moves |
| `scripts/tests/plugins/agent_dispatch_dashboard.bats` | new stat present; existing layout checks still pass |
| `docs/howto/codex-dispatch.md` | step 6 |
| `CHANGELOG.md` | entry under v1.43.14 |

## What NOT to do

- Do not let Claude build the evidence file from a doc or memory. It must be the verifier's captured run output.
- Do not rewrite or delete the existing legacy events. They become "claimed".
- Do not touch `bin/k3dm-vectordb-metrics` or the k3dm-bugs dashboard.
- Tests use a scratch `K3DM_WORKTREE_ROOT` and a scratch git repo for the SHAs, and assert first that neither is the
  real one.

## Acceptance

```yaml
must:
  M1: verify --result pass --evidence F with every required field records a verify event with evidence_sha256 and evidence_path, and the copy exists under the run dir with that sha256 (paired positive control for N1)
  M2: dispatch metrics count a pass with evidence as delivered, and a legacy pass without evidence as claimed (k3dm_dispatch_verification_claimed) and not delivered
  M3: verify --result fail with no --evidence still records a fail event
must_not:
  N1: verify --result pass with no --evidence, an empty file, a file with no '---' separator, or a file missing any required key never writes a verify event or a copy, and exits non-zero
  N2: a pre_fix_rc of 0, or an rc other than 0, is refused
  N3: a fix_sha or pre_fix_sha that does not resolve to a commit is refused
evidence:
  E1:
    proves: [M1, M3, N1, N2, N3]
    kind: offline
    intent: You will see bats with a scratch K3DM_WORKTREE_ROOT and scratch git repo (asserted not the real ones) show verify refused for no, empty, unseparated, partial, rc-1, pre_fix_rc-0 and unknown-SHA evidence, with no event written (each red on the pre-fix dispatcher, which records them), and accepted with a complete file whose sha256 matches the copy under the run dir.
    what: bats scripts/tests/bin/codex_dispatch.bats
  E2:
    proves: [M2]
    kind: offline
    intent: You will see test_dispatch_metrics.py feed a ledger with one evidence-backed pass and one bare pass and get delivered 1, claimed 1 (red on the pre-fix metrics, which deliver both).
    what: python3 -m pytest scripts/tests/bin/test_dispatch_metrics.py
  E3:
    proves: [M2]
    kind: live
    intent: You will see the Agent Dispatch dashboard show the legacy passes under "Claimed, no evidence" and a newly verified fix under delivered.
    what: operator screenshot after platform-ops / the dashboard sync
interface:
  - bin/k3dm-codex-dispatch verify --slug S --result pass|fail [--evidence FILE] [--verifier NAME] [--tokens N]
  - ledger.jsonl and <version>/<slug>.run/ under K3DM_WORKTREE_ROOT
  - bin/k3dm-dispatch-metrics output (k3dm_dispatch_delivered, k3dm_dispatch_verification_claimed)
```
