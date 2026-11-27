# Bug: `make test-all` run by the hub webhook is killed at its 1800 s limit before finishing

**Status:** OPEN — rev 2 (2026-11-27): rewritten from Fable's REWRITE review and a timed run on m5; intents pending
**Priority:** P2
**Introduced by:** unknown (test-bin suite growth against fixed limits; last hub success 2026-11-14)
**Should have been caught by:** live check
**Introducing change reviewed:** unknown
**Waiting on:** operator decision — since 2026-11-27 (rev 2 intents), then dispatch to Flash
**Prior art:** exact-slug glob: none; `make find-similar-docs` unavailable on m4 (fell back to glob)
**Severity:** medium — every cloud `make-test-all` and `make-test-bin` request fails (exit 124); the k3dm Tests
dashboard is stale; v1.46.0 p3b's `--with-test-all` leg cannot pass.
**Filed:** 2026-11-27, Claude, from the v1.46.0 p2b live check (operator: "go ahead to file those two P2 bugs")
**Approval:** operator, 2026-11-27 ("go ahead to file those two P2 bugs and have Fable and Neon to review them. after that dispatch to Flash and Luna"); rev 2 scope: operator, 2026-11-27 ("can you check the test-all review spec then timed run on m5? after maybe you want to send me intents for approval then dispatch to Flash?")
**Component:** `scripts/lib/webhook/make_targets.py:33,37`; `Makefile` `test-all` recipe; `bin/k3dm-test-metrics`

## Evidence

- **Live, 2026-11-27, hub m5 on `deploy/hub` `54a13982`:** cloud request `make-test-all` → job `16aadbe5`, final
  `body.exit_code` 124, output tail `ok 757 E1 approval never pushes, …` then `make: *** [test-all] Terminated: 15`.
- **Timed run, m5, 2026-11-27 18:36–19:35Z (Claude, read-only scratch clone `/tmp/k3dm-timing` at `deploy/hub`
  `1c74deb3`, webhook PATH `/Users/cliang/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin`, over SSH):**

  | Stage | Wall time | TAP lines | Current cloud limit |
  |---|---|---|---|
  | `make test` | **517 s** | 2256 | 1200 s |
  | `make test-bin` | **2983 s** | 1555 | **300 s** (docs: "~1 min") |
  | `make test-python` | 40 s, exit 2: **no pytest** for the webhook's `python3` (Homebrew 3.15) | 0 | 900 s |

  The webhook's test 757 is test-bin's 757th test: 517 s + test-bin tests 1–757 ≈ 1720 s, which matches the 1800 s kill.
  So the hub is **not** slower under launchd than over SSH; the suite outgrew the limits. Fable's "hub-side slowness"
  hypothesis is ruled out for this run.
- **Where test-bin spends its time:** 52 tests take ≥ 10 s each (1039 s together). Tests 1401–1555 alone take 889 s;
  the slowest are web-console install/recovery tests (`[M2] journal survives crashes…` 126 s, `[M4] C7 discovers process
  configs…` 65 s).
- **pytest missing on the hub** is a separate root cause and is filed separately
  (`docs/bugs/2026-11-27-hub-webhook-python-has-no-pytest.md`); this spec does not fix it.
- Grafana: `k3dm_test_last_success_timestamp_seconds{instance="test-all-local-last-success"}` = 2026-11-14T00:11:50Z.

## Scope (rev 2)

Child **A (Flash)**, one dispatch:

1. **Stage durations as each stage finishes.** Every `[test-all] stage-complete <stage>` line in the `test-all` recipe
   (serial and `PARALLEL=1` paths) also carries `seconds=<n>`. A run killed mid-way still has lines for the stages that
   finished.
2. **New metric, not the existing one.** `bin/k3dm-test-metrics` parses `seconds=` and exports
   `k3dm_test_stage_duration_seconds{stage}`. `k3dm_test_suite_duration_seconds{suite=<file|pytest>}` is unchanged
   (Fable: reusing it mixes stage and file names on the existing panel). The partial-log publish fallback
   (`scripts/lib/webhook/lifecycle.py:223-229`) publishes the stage durations it finds.
3. **Limits from the measurement** (about 1.4× measured, rounded):
   - `test-bin`: 300 → **4200** s (measured 2983 s).
   - `test-all`: 1800 → **5400** s (517 + 2983 + about 450 s pytest from m4 ≈ 3950 s).
   - `test` stays 1200 s (measured 517 s).
4. **Consumers follow the limit.** `scripts/lib/acceptance/live.py:470` (submit timeout) and `:631` (`LiveLeg`
   deadline) become at least the job limit plus the bridge's poll slack; the bridge watch is derived from
   `MAKE_TARGETS` (`bin/k3dm-cloud-bridge:566-567`, expiry `timeout + 600` at `:710`) and only its pin changes.
5. **Docs say the truth:** test-bin "~50 min", test-all "about 70 minutes" and that it holds the single make slot.

Out of scope: making test-bin faster (ideas row: profile the web-console suites; `PARALLEL=1` needs GNU `parallel`,
absent on m5); pytest on the hub (separate bug).

## Files

- `Makefile` (`test-all` recipe: `stage-complete` lines only)
- `bin/k3dm-test-metrics`
- `scripts/lib/webhook/make_targets.py`
- `scripts/lib/webhook/lifecycle.py` (partial-log publish includes stage durations, only if it needs a change)
- `scripts/lib/acceptance/live.py`
- `scripts/etc/grafana/dashboards/k3dm-tests-configmap.yaml` (one panel for the new metric)
- `docs/guides/grafana-dashboards/k3dm-tests.md`, `docs/guides/operator-acceptance.md`, `docs/howto/cloud-session-requests.md`
- Tests: `scripts/tests/bin/test_k3dm_test_metrics.py`, `scripts/tests/bin/webhook_make_targets.py`,
  `scripts/tests/bin/test_cloud_bridge.py`, `scripts/tests/bin/makefile_test_all.bats`, the live.py test file

## Contract readers

- `MAKE_TARGETS["test-all"]["timeout"]` and `["test-bin"]["timeout"]`: `scripts/lib/webhook/lifecycle.py` (kill timer);
  `bin/k3dm-cloud-bridge:566-567,710` (watch, derived); pins `scripts/tests/bin/test_cloud_bridge.py:1503,1507`;
  `scripts/lib/acceptance/live.py:470,631`; `docs/howto/cloud-session-requests.md:83,87,112`;
  `docs/guides/operator-acceptance.md:50,152`.
- `[test-all] stage-complete` line: writer `Makefile:1884,2046,2058,2089` (and the other stages); reader
  `bin/k3dm-test-metrics:52` (regex must accept the new `seconds=` suffix and old lines without it).
- New metric `k3dm_test_stage_duration_seconds`: writer `bin/k3dm-test-metrics`; readers the k3dm Tests dashboard
  configmap and its guide. No alert rule reads either duration metric (grep of `scripts/etc/prometheus/` empty).

## Acceptance

```yaml
must:
  - id: T-M1
    text: "each stage-complete line in the test-all log carries seconds=<n>, written when that stage finishes"
  - id: T-M2
    text: "k3dm-test-metrics exports k3dm_test_stage_duration_seconds{stage} for every completed stage, including from a log cut off mid-run"
  - id: T-M3
    text: "the hub allows test-bin 4200 s and test-all 5400 s; the acceptance live leg waits at least as long as the job plus bridge slack"
must_not:
  - id: T-N1
    text: "a stage that finished is missing its duration because a later stage was killed"
    red_on_current: "red: today's recipe prints no durations and the push runs only at the end"
  - id: T-N2
    text: "the existing k3dm_test_suite_duration_seconds series change name, labels or values"
    red_on_current: "green on current; mutant 'emit stage durations into suite_duration' turns it red"
  - id: T-N3
    text: "the acceptance live leg gives up before the job's own limit"
    red_on_current: "red: live.py deadline is 1200 s, below the 1800 s job limit"
  - id: T-N4
    text: "an old stage-complete line without seconds= breaks the metrics parser"
    red_on_current: "green on current; mutant 'require seconds=' turns it red"
evidence:
  - id: T-E1
    proves: [T-M1, T-M2, T-M3, T-N1, T-N2, T-N3, T-N4]
    kind: offline
    command: "pytest on the touched Python tests and bats makefile_test_all.bats pass under PATH=/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin; on pre-fix code T-N1 and T-N3 fail; the T-N2 and T-N4 mutants fail"
    intent: "Each part of the test run reports how long it took, even when a later part is cut off, and the cloud limits match how long the suites really take."
  - id: T-E2
    proves: [T-M1, T-M2, T-M3]
    kind: live
    command: "after a hub promote, in an idle window: make-test-bin then make-test-all from a cloud request finish without exit 124 (a real test failure or the pytest bug is acceptable); the job log shows seconds= for each completed stage; Grafana shows k3dm_test_stage_duration_seconds for them"
    intent: "You can run the test suites from a cloud session again without them being killed, and the dashboard shows how long each part takes."
interface:
  - "MAKE_TARGETS['test-bin']['timeout'] = 4200; MAKE_TARGETS['test-all']['timeout'] = 5400"
  - "[test-all] stage-complete <stage> seconds=<n>"
  - "k3dm_test_stage_duration_seconds{stage}"
```
