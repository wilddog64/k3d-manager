# Plan: `make test-all` on a dev machine publishes no suite metrics unless the Pushgateway URL is set (P2)

**Filed:** 2026-11-18
**Branch:** `k3d-manager-v1.45.0`
**Status:** PLANNED — ready for dispatch
**Covers:** `docs/bugs/2026-11-14-dev-machine-test-all-overwrites-nightly-suite-metrics.md` (operator decision 2026-11-14, option (a))
**Risk:** low-medium (offline-suite alerts read these series; a mistake silences the nightly. Mitigated by pinning the
nightly to today's default URL and by `OfflineSuiteStale`, which fires if the nightly stops publishing)
**Reviewed:** Claude only (P2, small; every reader below found by grep)
**Agent:** Flash (`agy`, `gemini-3.8-flash-medium`)

## Problem

`bin/k3dm-test-metrics` pushes to `K3DM_PUSHGATEWAY_URL`, falling back to `DEFAULT_PUSHGATEWAY_URL = "http://localhost:9091"`
(`bin/k3dm-test-metrics:17`, used at `:245`). `make test-all` calls it on every run (`Makefile:2175`). On the M4, 9091 is a
port-forward to the hostinger Pushgateway, so any `make test-all` there (a dev run, a dispatch worktree) replaces the
nightly suite's group: on 2026-11-14 a test fixture set a false `k3dm_test_last_success_timestamp_seconds` and a worktree
run cleared `OfflineSuiteFailing`.

## Before You Start

1. Read the bug doc above.
2. Read `bin/k3dm-test-metrics` in full, `bin/k3dm-webhook:1811-1827`, `scripts/etc/launchd/com.k3d-manager.test-metrics.plist.tmpl`,
   `scripts/tests/bin/test_k3dm_test_metrics.py` and `scripts/tests/bin/test_webhook_pushgateway_provider.py` in full.

## Fix

1. **`bin/k3dm-test-metrics` `main()` (`:270`):** after the existing `"[k3dm-test-metrics] N cases, M failed"` line (`:284`),
   if `os.environ.get("K3DM_PUSHGATEWAY_URL", "").strip()` is empty, print exactly
   `[k3dm-test-metrics] metrics not published (K3DM_PUSHGATEWAY_URL unset)` and return 0 without calling `push_metrics`
   (no network call of any kind). Otherwise behave exactly as today. Do not change `push_metrics`, `DEFAULT_PUSHGATEWAY_URL`,
   the payload, or the grouping URL.
2. **Nightly LaunchAgent template:** add `K3DM_PUSHGATEWAY_URL` = `http://localhost:9091` to `EnvironmentVariables` in
   `scripts/etc/launchd/com.k3d-manager.test-metrics.plist.tmpl`. That is today's default, so the nightly publishes to the
   same place as now.
3. **`bin/k3dm-webhook` `_publish_test_metrics` (`:1811`):** build the child env as `dict(os.environ)` and, when the
   module's `PUSHGATEWAY_URL` (from `webhook.config`, already `K3DM_PUSHGATEWAY_URL` or `http://localhost:9091`) is
   non-empty, set `env["K3DM_PUSHGATEWAY_URL"] = PUSHGATEWAY_URL`. Pass that env at `:1820`. At `:1822`, also treat
   `"metrics not published"` in `output` as not confirmed (same warning and Slack notice as `"metrics push skipped"`).

## Files

| File | Change |
|---|---|
| `bin/k3dm-test-metrics` | Fix 1 |
| `scripts/etc/launchd/com.k3d-manager.test-metrics.plist.tmpl` | Fix 2 |
| `bin/k3dm-webhook` | Fix 3 |
| `scripts/tests/bin/test_k3dm_test_metrics.py` | tests 1-4; the four existing `test_main_*` tests (`:107`, `:117`, `:329`, `:344`) set `K3DM_PUSHGATEWAY_URL` with `monkeypatch.setenv` so they keep testing publication |
| `scripts/tests/bin/test_webhook_pushgateway_provider.py` | tests 5-6 |

`Makefile` is **not** in scope (another dispatch holds it).

## Contract readers

`K3DM_PUSHGATEWAY_URL` — `grep -rn K3DM_PUSHGATEWAY_URL bin scripts Makefile`:
- `bin/k3dm-test-metrics:245` (reader) — **changes**: unset or blank now means "do not publish" in `main()`.
- `scripts/lib/webhook/config.py:36` (reader, default `http://localhost:9091`) — unchanged; the webhook's own
  `k3dm-webhook` job metrics (`bin/k3dm-webhook:1767-1786`) keep using it.
- Writers after the fix: the nightly plist template (new), `bin/k3dm-webhook` `_publish_test_metrics` (new, child env
  only), `scripts/tests/bin/makefile_test_all.bats:249` (test, sets `http://127.0.0.1:9`; unchanged).
- Other test readers (`scripts/tests/hermes/*`, `scripts/tests/lib/webhook.bats`, dashboard bats) — unchanged.

Callers of `bin/k3dm-test-metrics`: `Makefile:2175` (inherits the caller's env; unchanged), `bin/k3dm-webhook:1815` (Fix 3).

`k3dm_test_*` series readers — `scripts/etc/prometheus/rules-acg/k3dm-tests.yaml`, `scripts/etc/grafana/dashboards/k3dm-tests-configmap.yaml`,
`scripts/etc/helm/observability/kube-prometheus-stack-values.yaml` — unchanged: same names, labels and grouping.

Deploy reader: the installed `~/Library/LaunchAgents/com.k3d-manager.test-metrics.plist` on the hub is rendered by
`make install-test-metrics`. After promote, the hub must re-run `make install-test-metrics`, or the nightly stops
publishing (and `OfflineSuiteStale` fires). This is an operator deploy step, listed under E3.

## Tests (these names exactly)

In `scripts/tests/bin/test_k3dm_test_metrics.py`:

1. `test_main_without_pushgateway_url_publishes_nothing` — `monkeypatch.delenv("K3DM_PUSHGATEWAY_URL", raising=False)`, assert
   it is absent, replace `urllib.request.urlopen` (as imported by the module) and `push_metrics` with recorders; `main()` on a
   passing log returns 0, neither recorder is called, stdout contains `metrics not published (K3DM_PUSHGATEWAY_URL unset)`.
2. `test_main_with_blank_pushgateway_url_publishes_nothing` — same with `K3DM_PUSHGATEWAY_URL="  "`.
3. `test_main_with_explicit_pushgateway_url_publishes` (positive control) — `K3DM_PUSHGATEWAY_URL=http://127.0.0.1:9`, `push_metrics`
   recorder: called twice on a passing log (run group, then `-last-success`), and the message from test 1 is absent.
4. `test_nightly_plist_sets_pushgateway_url` — load the template with `plistlib` (after substituting the `{{…}}` placeholders
   with fixed strings); `EnvironmentVariables["K3DM_PUSHGATEWAY_URL"] == "http://localhost:9091"`.

In `scripts/tests/bin/test_webhook_pushgateway_provider.py` (reuse the `fake_spawn` pattern of
`test_publish_test_metrics_runs_repo_exporter_from_repo_root`, capturing `env`):

5. `test_publish_test_metrics_passes_pushgateway_url_explicitly` — `monkeypatch.delenv("K3DM_PUSHGATEWAY_URL", raising=False)`,
   `monkeypatch.setattr(WEBHOOK, "PUSHGATEWAY_URL", "http://pg.invalid:9091")`; the captured env has
   `K3DM_PUSHGATEWAY_URL == "http://pg.invalid:9091"`.
6. `test_publish_test_metrics_warns_when_metrics_not_published` — `fake_spawn` returns rc 0 and output
   `[k3dm-test-metrics] metrics not published (K3DM_PUSHGATEWAY_URL unset)`; exactly one notice is recorded and it contains
   `metrics publication was not confirmed`.

Pre-fix red: 1, 2, 4, 5, 6 fail on today's code; 3 passes (positive control). Mutations (each turns the named test red;
apply by hand, run, revert): remove the guard in `main()` (1, 2); drop `.strip()` (2); remove the plist key (4); stop setting
the child env (5); drop the `"metrics not published"` match (6).

## What NOT to Do

- Do not change `Makefile`, `push_metrics`, `DEFAULT_PUSHGATEWAY_URL`, `scripts/lib/webhook/config.py`, metric names,
  labels, grouping, rules or dashboards.
- Do not run `make install-test-metrics`, `make test-all` or `make test-metrics` against the real `~/Library/LaunchAgents`
  or any real Pushgateway. No network in tests.
- Do not touch `docs/`, `CHANGELOG.md` or `memory-bank/`. Do not commit, push or open a PR; Claude verifies and commits.
- Do not skip hooks. Do not modify files outside the Files table.

## Rules

LF only; keep indentation, quoting and naming; no unsolicited refactors. If the spec contradicts the code, stop and say so.

## Gates

`pytest scripts/tests/bin/test_k3dm_test_metrics.py scripts/tests/bin/test_webhook_pushgateway_provider.py`, then `make test-pytest`.

## Definition of Done

- [ ] Fix 1-3; `git status` shows only the five files.
- [ ] Pre-fix red for 1, 2, 4, 5, 6 and green for 3, recorded.
- [ ] Both gates green; mutation table recorded.
- [ ] Report: changed files, test output, mutation table. No commit.

## Acceptance

```yaml
interface:
  - "bin/k3dm-test-metrics LOG --target test-all ... (env K3DM_PUSHGATEWAY_URL decides whether it publishes)"
  - "scripts/etc/launchd/com.k3d-manager.test-metrics.plist.tmpl EnvironmentVariables.K3DM_PUSHGATEWAY_URL"
must:
  - id: M1
    text: with K3DM_PUSHGATEWAY_URL set, test-all metrics publish exactly as today (both groups on success)
  - id: M2
    text: the nightly LaunchAgent sets K3DM_PUSHGATEWAY_URL to http://localhost:9091, today's default
  - id: M3
    text: the webhook's test-all job passes its Pushgateway URL to the exporter explicitly, and an unpublished result raises its existing "not confirmed" notice
must_not:
  - id: N1
    text: with K3DM_PUSHGATEWAY_URL unset or blank, k3dm-test-metrics makes any network call or pushes any group — red today
  - id: N2
    text: the webhook's test-all job relies on an inherited K3DM_PUSHGATEWAY_URL, or reports success when nothing was published — red today
evidence:
  - id: E1
    proves: [M1, M2, M3, N1, N2]
    kind: offline
    command: pytest scripts/tests/bin/test_k3dm_test_metrics.py scripts/tests/bin/test_webhook_pushgateway_provider.py -k "pushgateway_url or not_published or nightly_plist"
    intent: "A make test-all on your laptop or in a dispatch worktree no longer overwrites the nightly test results in Grafana; it says 'metrics not published' instead. The nightly run and the webhook's test job still publish as before."
  - id: E2
    proves: [N1]
    kind: live
    what: "Claude: on the M4, make test-all prints 'metrics not published (K3DM_PUSHGATEWAY_URL unset)' and the hostinger Pushgateway k3dm-tests group timestamp does not move."
    intent: "On the M4, a test run leaves the nightly numbers in Grafana untouched."
  - id: E3
    proves: [M2]
    kind: live
    what: "Operator: after promote, make install-test-metrics on the hub; the next 04:30 nightly updates k3dm_test_last_run_timestamp (or the group's push time) and OfflineSuiteStale stays quiet."
    intent: "After you reinstall the nightly agent on the hub, the next nightly run still shows up in Grafana."
```

**Intent approved:** operator, 2026-11-18
**Approval words and scope:** 2026-11-14 decision "approve" (option (a): publish only when `K3DM_PUSHGATEWAY_URL` is set
explicitly; the nightly sets it); 2026-11-18 "can you write a spec for make test-all and then dispatch to Flash". Fix 3 (the
webhook passes its URL) keeps today's webhook behaviour under option (a); no new behaviour beyond the decision.
