# Bug: E2E Verification tables show run dates in UTC, and Failure groups leads with the date and status

**Status:** OPEN — filed 2026-11-09
**Priority:** P3
**Waiting on:** operator decision — since 2026-11-09 (intent approval)
**Introduced by:** pre-existing (`e2e_utc` and the run-date-first column order came in with the run-status columns;
see CHANGELOG `fixed: passed <date>`)
**Should have been caught by:** none (presentation preference, not a regression)
**Prior art:** `make find-similar-docs` unavailable (vector store unreachable from the M4: `context "k3d-k3d-cluster"
does not exist`, 2026-11-09); exact-slug glob: none
**Severity:** cosmetic — the operator reads Pacific time and has to convert each run date and "fixed: passed" time.
**Approval:** operator, 2026-11-09: "can we change UTC to local time, and column order: Run ID -> Runner -> Run Date ->
Tier -> Target -> Service Failure Kind -> Status Now"
**Filed:** 2026-11-09
**Detected by:** operator, 2026-11-09, E2E Verification "Failure groups" screenshot
**Branch:** `k3d-manager-v1.43.15`
**Release:** P3 batch

## Symptom

E2E Verification dashboard, Failure groups (panel id 6): columns are Run date (UTC), Status now, Run ID, Runner, Tier,
Target, Service, Failure kind. Dates read `2026-11-07 21:25 UTC`; Status now reads `fixed: passed 2026-11-07 21:30 UTC`.
Recent runs (id 5) and Failure details (id 7) show the same UTC strings.

## Root cause

The dates are text, not time fields. `scripts/etc/argocd/platform-ops/vulnerability-inventory-exporter.yaml:146-147`
`e2e_utc()` formats `time.gmtime(seconds)` as `"%Y-%m-%d %H:%M UTC"`; it fills the `run_date` label (lines 573, 581,
594) and the time inside `run_status` (line 157). Grafana shows the dashboard time zone only for time fields, so it
cannot convert a string label. The column order is the `organize` transform's `indexByName` in
`scripts/etc/argocd/platform-ops/grafana-dashboard-e2e.yaml` (Failure groups: `run_date` 0, `run_status` 1).

## Fix

1. Exporter: format with `time.localtime(seconds)` and `"%Y-%m-%d %H:%M %Z"` (rename the helper, e.g. `e2e_time`).
   The Deployment's `exporter` container gets `env: [{ name: TZ, value: "PST8PDT,M3.2.0,M11.1.0" }]`. Empty for
   `seconds <= 0` as today.
2. Dashboard, all three tables: header `Run date (UTC)` becomes `Run date`.
3. Dashboard, Failure groups (id 6) `indexByName`: `run_id` 0, `runner` 1, `run_date` 2, `tier` 3, `target` 4,
   `exported_service` 5, `kind` 6, `run_status` 7. Recent runs and Failure details keep their order.

**External behaviour proof (CLAUDE.md, 2026-11-07):** the exporter image is `python:3.12-alpine` (line 632), which has
no tz database; a POSIX TZ rule needs none. Claude, M4, 2026-11-09, `docker run --rm -e TZ='PST8PDT,M3.2.0,M11.1.0'
python:3.12-alpine` (`python@sha256:e064671ca452259bab50e8e2c7bd896e39e9a343bb06ca25234adf6fe18d0fc7`, Python
3.12.16): `time.localtime(1794086678)` → `2026-11-07 13:24 PST`; `time.localtime(1783000000)` → `2026-07-02 06:46 PDT`.
The only other time call in the exporter (line 123, `datetime.fromisoformat(...).timestamp()` on an explicit offset)
is unaffected by `TZ`.

## Files

| File | Change |
|---|---|
| `scripts/etc/argocd/platform-ops/vulnerability-inventory-exporter.yaml` | local-time helper; `TZ` env on the container |
| `scripts/etc/argocd/platform-ops/grafana-dashboard-e2e.yaml` | header rename (3 tables); Failure groups column order |
| `scripts/tests/plugins/e2e_observability.bats` | update lines 270, 284, 290, 471, 481, 483, 489 (they pin `e2e_utc`, `UTC` strings and `run_date` 0 / `run_status` 1) |

## Contract readers

| Reader | Changes? |
|---|---|
| `grafana-dashboard-e2e.yaml` panels 5, 6, 7 (`run_date`, `run_status` labels) | Yes: header and order only; same label names |
| `scripts/tests/plugins/e2e_observability.bats` | Yes: assertions follow the new format and order |
| `grafana-dashboard-e2e.yaml:294,660,702,745` (count/sum over the info metrics) | No: they do not read `run_date` or `run_status` |
| `scripts/lib/hermes/sensors.py:752` (`" UTC"` suffix) | No: parses GitHub token expiry, not e2e labels |

Found by `git grep -n "run_date\|run_status\|e2e_utc\| UTC\""` outside `docs/`, 2026-11-09.

## Acceptance

```yaml
must:
  - id: M1
    text: "E2E run dates and 'fixed: passed' times show Pacific local time with a PST or PDT suffix."
  - id: M2
    text: "Failure groups columns read Run ID, Runner, Run date, Tier, Target, Service, Failure kind, Status now, in that order."
must_not:
  - id: N1
    text: "No E2E table shows a time with a UTC suffix or a 'Run date (UTC)' header."
evidence:
  - {id: E1, proves: [M1, N1], kind: offline, intent: "With TZ set as the Deployment sets it, the exporter's time helper turns a November epoch into PST and a July epoch into PDT, and a 'fixed: passed' status carries the same local time; the test fails on today's UTC code."}
  - {id: E2, proves: [M2, N1], kind: offline, intent: "The dashboard JSON orders Failure groups as you listed and no table header says UTC; a test fails if the order or the header goes back."}
  - {id: E3, proves: [M1, M2], kind: live, intent: "After the fix lands and is promoted, you open E2E Verification and see Failure groups in your order with times like 2026-11-07 13:25 PST."}
interface:
  - "scripts/etc/argocd/platform-ops/vulnerability-inventory-exporter.yaml (exporter.py source under data; Deployment env)"
  - "scripts/etc/argocd/platform-ops/grafana-dashboard-e2e.yaml (dashboard JSON under data)"
```

## Worker definition of done

- Mutants shown red: (a) restore `time.gmtime` / `UTC`, (b) drop the `TZ` env from the Deployment, (c) swap `run_id`
  and `runner` in `indexByName`. Paste each red run.
- Tests set `TZ` explicitly and call `time.tzset()`; never depend on the host's zone.
- Run `bats scripts/tests/plugins/e2e_observability.bats` and `make validate-manifests`; paste command, rc and proving
  lines. Leave changes uncommitted; Claude reviews and lands. No kubectl, nothing against the hub.
