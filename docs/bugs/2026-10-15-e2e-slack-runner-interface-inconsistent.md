# P3 — Slack E2E command interface is inconsistent across execution environments

**Filed:** 2026-10-15
**Branch:** `k3d-manager-v1.43.5` (triage 2026-10-15, operator-approved placement)
**Priority:** P3 — operator-facing command contract / interface consistency
**Status:** FIXED (offline) — `87313693` 2026-10-23; E3 live pending (operator runs `k3dm e2e-remote RUNNER=aws`)
**Approval:** operator explicitly requested appropriate bug filing on 2026-10-15; split approved 2026-10-23 (operator: "yes, please split the way you suggested")
**Release:** v1.43.5 (bug; exempt from the plan cap)
**Component:** `scripts/plugins/e2e_remote.sh`, `scripts/lib/webhook/make_targets.py`

## Operator observation

During an active AWS ACG sandbox session, Slack command `k3dm e2e-remote RUNNER=acg` was rejected:

```
ERROR: [e2e-remote] runner 'acg' not in allowlist (m2)
make: *** [e2e-remote] Error 1
```

The operator reasonably expected a single Slack-accessible E2E command with runner selection (`m2`, `m4`, `aws`). From the Slack user's perspective **all executions happen remotely**, including those running on the webhook host/m4. The current distinction between `e2e-remote` and `e2e-sandbox` exposes implementation topology rather than operator intent.

Separately, `e2e-sandbox` attempted to install Argo CD over an existing AWS provisioned cluster and failed on CRD Helm ownership; this separate P2 issue remains tracked in `docs/bugs/2026-10-15-e2e-sandbox-argocd-crd-helm-ownership-conflict.md`.

## Confirmed current implementation

- `scripts/plugins/e2e_remote.sh` defaults `E2E_RUNNER_ALLOWLIST` to `m2`; the `e2e_runner_dispatch` implementation uses m2-specific SSH, paths, kubeconfig, locking, and result collection. Simply extending the allowlist to `aws` or `m4` **would not** implement those adapters.
- `scripts/plugins/e2e.sh` implements a separate `e2e-sandbox` flow targeting `ubuntu-k3s`, with its own setup and reporting paths.
- Both are exposed as operator-visible Make/Slack targets, forcing the operator to know internal transport details.

This is classified as a **P3 interface/design bug (enhancement-scale remediation)**, not a claim that the deliberately restricted m2 runner is itself malfunctioning.

## Split (2026-10-23)

Priority measures urgency, not size. `k3dm e2e-sandbox` already runs the ACG E2E, so this stays P3. What
hurt the operator was the error: `runner 'acg' not in allowlist (m2)` says nothing about which command
to use instead. This bug fixes only that. The unified `e2e-remote RUNNER=m2|m4|aws` command is
enhancement-scale and now lives in
[`v1.46.1-e2e-unified-runner-command`](../plans/v1.46.1-e2e-unified-runner-command.md).

## Fix

- **F1. A redirecting error.** In `scripts/plugins/e2e_remote.sh`, add `_e2e_runner_denied_message
  <runner>`, which prints one line, and use it at all four `not in allowlist` sites (lines ~427, ~910,
  ~965, ~1012), so the four stay identical:
  - `aws`, `acg` or `sandbox`: `[e2e-remote] runner '<r>' is not an e2e-remote runner; for Tier 2 E2E on
    the ACG sandbox use 'e2e-sandbox' (Slack: k3dm e2e-sandbox)`
  - `m4`, `local` or `hub`: `[e2e-remote] runner '<r>' is not an e2e-remote runner; for Tier 1 E2E on
    this host use 'e2e' (Slack: k3dm e2e)`
  - anything else: the current text, `[e2e-remote] runner '<r>' not in allowlist (<allowlist>)`.

  Matching is exact and case-sensitive. A name that is also in `E2E_RUNNER_ALLOWLIST` is allowed as
  before; the redirect applies only to a denied runner. The exit status and the `_err` path do not
  change.
- **F2. Help text.** In `scripts/lib/webhook/make_targets.py`, change the summaries so `k3dm help`
  says which command fits which environment:
  - `e2e-remote`: `Tier 1 e2e on a remote runner (RUNNER=m2); ACG sandbox: e2e-sandbox; this host: e2e`
  - `e2e`: `Tier 1 e2e in a disposable vCluster on this host`

  Change no role, parameter, timeout or confirm flag.
- **F3. Docs.** `docs/howto/slack-slash-commands.md`: one short "Which E2E command?" table (e2e /
  e2e-remote / e2e-sandbox: where it runs, tier, example), beside the target table at line ~385.
- **F4.** `CHANGELOG.md` `[Unreleased]` → `### Fixed`.

## Files

| File | Change |
|---|---|
| `scripts/plugins/e2e_remote.sh` | F1 |
| `scripts/lib/webhook/make_targets.py` | F2 |
| `scripts/tests/plugins/e2e_remote.bats` | F1 tests |
| `scripts/tests/bin/webhook_make_targets.py` | F2 tests (update any pinned summary) |
| `docs/howto/slack-slash-commands.md` | F3 |
| `CHANGELOG.md` | F4 |

## Acceptance

```yaml
must:
  - id: M1
    text: e2e_runner_dispatch with runner aws, acg or sandbox (not in E2E_RUNNER_ALLOWLIST) fails and its error names e2e-sandbox.
  - id: M2
    text: e2e_runner_dispatch with runner m4, local or hub (not in E2E_RUNNER_ALLOWLIST) fails and its error names e2e.
  - id: M3
    text: Any other denied runner keeps the current "not in allowlist (<allowlist>)" error.
  - id: M4
    text: Every entry point that checks the allowlist prints the same message for the same runner.
  - id: M5
    text: The e2e-remote help summary names e2e-sandbox and e2e; roles, parameters, timeouts and confirm flags of every target are unchanged.
  - id: M6
    text: docs/howto/slack-slash-commands.md has a table that says which E2E command runs where.
must_not:
  - id: N1
    text: A denied runner must not start any work - no SSH, lock, kubectl or make call (stubs record none).
  - id: N2
    text: An allowlisted runner (m2, or aws when E2E_RUNNER_ALLOWLIST includes it) must not get the redirect message or be refused.
  - id: N3
    text: The pre-fix error for RUNNER=aws ("not in allowlist (m2)") must fail M1 (test red on the pre-fix e2e_remote.sh).
  - id: N4
    text: No test reaches a live runner, cluster, sandbox, Slack or webhook.
evidence:
  - id: E1
    kind: offline
    proves: [M1, M2, M3, M4, N1, N2, N3, N4]
    text: bats scripts/tests/plugins/e2e_remote.bats green; the new tests red on the pre-fix e2e_remote.sh.
  - id: E2
    kind: offline
    proves: [M5]
    text: pytest scripts/tests/bin/webhook_make_targets.py green, with a test that compares every target's non-summary fields to the pre-fix values.
  - id: E3
    kind: live
    proves: [M1, M5]
    text: The operator runs "k3dm e2e-remote RUNNER=aws" and "k3dm help" in Slack after the webhook restart; the reply names e2e-sandbox, and no E2E job starts.
interface:
  - e2e_runner_dispatch <runner> [digest] (scripts/plugins/e2e_remote.sh) and the other allowlist-checking public functions in that file
  - E2E_RUNNER_ALLOWLIST
  - MAKE_TARGETS summaries in scripts/lib/webhook/make_targets.py (k3dm help)
```

## Definition of Done

- [ ] F1–F4 on `k3d-manager-v1.43.5`; only the Files above change.
- [ ] N3 shown red on the pre-fix file.
- [ ] Commit: `fix(e2e): point a denied e2e-remote runner at the right E2E command`

## What NOT to Do

- Do NOT add `aws` or `m4` to `E2E_RUNNER_ALLOWLIST`, and do not add any runner adapter; that is the
  v1.46.1 plan.
- Do NOT touch `scripts/plugins/e2e.sh`, the sandbox, or `e2e-sandbox` behaviour.
- Do NOT create a PR, commit to `main`, or use `--no-verify`.
