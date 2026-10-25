# Bug: Agent Dispatch run evidence shows a file name you cannot open

**Status:** LIVE-VERIFIED 2026-10-25 — offline E1 green (pytest 100/100, BATS 19/19, ruff clean, validate-manifests 83/83; 7 pytest + 1 BATS red on the pre-fix files); live E2 from operator screenshot 253
**Live evidence:** 2026-10-25 · run hub-grafana-agent-dispatch-per-run-screenshot · env hub/k3d-k3d-cluster · scenario agent-dispatch/per-run-result-log-columns · commit 884062ef · proves E2
**Fix commit:** `b63fe8da`
**Live note:** operator screenshot 253 at Window v1.43.7: Result shows parsed results (`101 passed`, `82/82 ok`, `19/19 ok; 99 passed`), Log shows `~/.local/share/k3d-m…` paths with no username, Tokens fits the panel; the running task's row reads `unknown`/`none` as specified. The cell-inspect click was not shown; the click-through is replaced by the Loki link in `docs/bugs/2026-10-25-dispatch-run-log-not-viewable-from-grafana.md`. The fix is `b63fe8da` plus widths `3041183d` and home-free paths `884062ef`.
**Review note:** Claude raised the `evidence_path` cap to 512 characters (real run paths are ~145, so the 120 cap in F1 cut them mid-name) and matched the Log override on the renamed field `Log`, as every other dashboard override does; added a long-path test.
**Priority:** P3
**Severity:** low — the column names its evidence but gives no result and no way to reach the file
**Release:** v1.43.7 (bug; does not count toward the five-plan cap)
**Filed:** 2026-10-25, by Claude, from the operator's review of panel 47 (screenshot 249)
**Approval:** explicit 2026-10-25 ("do what you recommend. I just don't want to have file presented but can't drill down to it"). Not critical (metrics script and one dashboard ConfigMap).
**Component:** `bin/k3dm-dispatch-metrics` (run outcome rows, `k3dm_dispatch_task_run_outcome`), `scripts/etc/argocd/platform-ops/grafana-dashboard-agent-dispatch.yaml` (panel 47)
**Related:** `docs/bugs/2026-10-24-agent-dispatch-run-evidence-table-unreadable.md`

## Problem

Panel 47 (Per run) has an **evidence** column that reads `land-test.log` on every accepted row. The
file is `~/.local/share/k3d-manager/worktrees/<version>/<slug>.run/land-test.log` on the operator's
Mac. The cell gives neither the test result nor the path, and a browser cannot open a local file
from Grafana, so the operator sees a file name with nothing behind it.

A clickable link would need an HTTP server on the Mac serving run logs. That is new exposure for
logs that can hold command output, so it is out of scope.

## Fix

### F1. Export the result and the path

In `bin/k3dm-dispatch-metrics`, add two labels to every `k3dm_dispatch_task_run_outcome` series:

- `evidence_summary`: for `land-test.log`, a result parsed from the log:
  - TAP (bats): count lines starting `ok ` and `not ok ` across the whole log → `<ok>/<ok+not_ok> ok`;
  - otherwise the last pytest summary line matching `^\d+ (passed|failed)` → that count text up to
    ` in ` (e.g. `89 passed`, `2 failed, 87 passed`);
  - both present: join with `; ` (bats first);
  - log missing or unparseable: `unknown`.
  For `codex_exit.exit` use `exit <code>`; for `land_refused.tests`, `abandon.event` and `none`, use
  the existing evidence value.
- `evidence_path`: the absolute path of the file the row's evidence comes from: `land-test.log` for
  `accepted` and `land_refused.tests`, `codex.log` for `codex_exit.exit`; empty otherwise. Use the run
  directory the script already reads; do not hard-code a home directory.

Sanitise both like other label values (no `"`, `\`, newlines; at most 120 characters). Keep the
existing `evidence` label unchanged.

### F2. Panel 47

- The **evidence** column shows `evidence_summary` (header **Result**).
- A new **Log** column shows `evidence_path` with cell inspect enabled
  (`"inspect": true` in the field's `custom` config), so clicking the cell shows the full path to copy.
  Keep it narrow (`width` ≤ 160); the cell may truncate.
- No data link to a `file://` URL.

### F3. Docs

`docs/guides/grafana-dashboards.md`, Agent Dispatch Per run: what Result means and how to open the
log (click the Log cell, copy the path, `less <path>`).

## Tests

In `scripts/tests/bin/test_dispatch_metrics.py`:

1. An accepted run whose `land-test.log` has `ok 1`, `ok 2`, `not ok 3` → `evidence_summary="2/3 ok"`.
2. A pytest-only log ending `89 passed in 1.41s` → `89 passed`.
3. A log with both → `"<tap>; <pytest>"`.
4. Missing log → `unknown`, and the script still exits 0.
5. A `codex_exit.exit` row → `evidence_summary="exit <code>"`, `evidence_path` ends `codex.log`.
6. `evidence_path` for an accepted row is absolute and ends `/<slug>.run/land-test.log`.
7. A log line with `"` or a newline in a test name does not break the exposition format.

In `scripts/tests/plugins/agent_dispatch_dashboard.bats`:

8. Panel 47 shows `evidence_summary` as **Result**, has a **Log** column from `evidence_path` with
   `inspect: true`, and has no `file://` link.

## Files

- `bin/k3dm-dispatch-metrics`
- `scripts/etc/argocd/platform-ops/grafana-dashboard-agent-dispatch.yaml`
- `scripts/tests/bin/test_dispatch_metrics.py`
- `scripts/tests/plugins/agent_dispatch_dashboard.bats`
- `docs/guides/grafana-dashboards.md`
- `CHANGELOG.md`

## Acceptance

```yaml
must:
  - id: M1
    text: Every run outcome series carries evidence_summary with the parsed test result (TAP ok/total, pytest summary, exit code) or unknown.
  - id: M2
    text: Every run outcome series carries evidence_path, the absolute path of its evidence file, or empty when there is none.
  - id: M3
    text: Panel 47 shows the result in a Result column and the path in a Log column whose cell can be inspected to copy the full value.
  - id: M4
    text: The guide says how to open a run's log.
must_not:
  - id: N1
    text: No file:// link or HTTP server for run logs.
  - id: N2
    text: A missing or malformed log must not stop the metrics run or emit an invalid exposition line.
  - id: N3
    text: The existing evidence label value and the outcome classification must not change.
  - id: N4
    text: Tests never push to the real Pushgateway.
evidence:
  - id: E1
    kind: offline
    proves: [M1, M2, M3, M4, N1, N2, N3, N4]
    text: K3DM_DISPATCH_PUSHGATEWAY_URL=http://127.0.0.1:9 pytest scripts/tests/bin/test_dispatch_metrics.py and bats scripts/tests/plugins/agent_dispatch_dashboard.bats green; tests 1, 5, 6 and 8 red on a temp copy of the pre-fix files; ruff 0.15.8 clean; make validate-manifests passes.
  - id: E2
    kind: live
    proves: [M1, M2, M3]
    text: After the next metrics push and dashboard sync, the operator's screenshot of panel 47 at Window v1.43.7 shows results such as 99 passed, and clicking a Log cell shows a path that opens with less.
interface:
  - bin/k3dm-dispatch-metrics --dry-run
  - k3dm_dispatch_task_run_outcome{version,slug,run,outcome,evidence,evidence_summary,evidence_path}
  - Grafana /d/k3dm-agent-dispatch panel 47
```

## Definition of Done

- [ ] F1–F3 and a CHANGELOG `[Unreleased]` `### Fixed` entry; only the Files above change.
- [ ] E1 green; paste the summaries.
- [ ] Tests 1, 5, 6 and 8 shown red on a temp copy of the pre-fix files.
- [ ] Commit: `fix(dispatch): show each run's test result and log path in Per run`

## What NOT to Do

- Do NOT create a PR, commit to `main`, or skip hooks (`--no-verify`).
- Do NOT add a `file://` link, a web server, or any copy of log contents to metrics.
- Do NOT push to the real Pushgateway; tests use `K3DM_DISPATCH_PUSHGATEWAY_URL=http://127.0.0.1:9`.
- Do NOT change or remove existing tests or assertions, except where this spec changes the behaviour.
- Do NOT modify files outside the Files list.
