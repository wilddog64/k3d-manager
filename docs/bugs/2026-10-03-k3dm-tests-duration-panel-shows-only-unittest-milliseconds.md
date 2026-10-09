# Bug: k3dm Tests duration panel shows only unittest milliseconds; the ~15-minute run reports 0

**Filed:** 2026-10-03
**Status:** FIXED in `3a254484` (#133): the run duration is measured and pushed as `k3dm_test_run_duration_seconds{target}`
**Branch:** `k3d-manager-v1.41.0`
**Severity:** Medium — the dashboard misstates how long the offline suite takes; no test result is wrong.

## Symptom

On the `k3dm-tests` Grafana dashboard, the **Suite duration over time** panel plots values between 0 and 4 ms:
- The `webhook_*.py` series show 1–4 ms.
- The `bats` and `pytest` series sit at 0.

In reality, `make test-all` takes about 15 minutes. **Cases by suite** says "No data" on a clean run, which reads like a broken panel.

## Root cause

`bin/k3dm-test-metrics`:
- **Line 144** pushes `k3dm_test_run_duration_seconds 0` as a literal. The `test-metrics` Makefile recipe never measures the run.
- **Line 134** emits `parsed["durations"].get(suite, 0)`, so a suite with no known duration publishes a fake `0`.
- **Only two sources of per-suite duration are parsed:**
  - unittest's `Ran N tests in X s` line, which is the real time for those small files (milliseconds);
  - a `# duration:` marker that no harness prints.
- **The pytest summary's `in X.XXs` is never read.**
- BATS prints no per-file time at all.

`docs/guides/grafana-dashboards.md` already records this as "Suite duration is not wired yet".

"Cases by suite" filters to `not_ok > 0` by design, so an empty panel is the healthy state. Only its title misleads.

## Relationship to v1.42.0

`docs/plans/v1.42.0-daily-offline-and-e2e-verification.md` §3 ("Measure the actual time") covers this offline duration repair as part of the daily scheduler. This bug pulls **only the offline-suite duration piece** forward to v1.41.0. The daily envelope and the E2E runtimes stay in v1.42.0. Change 6 records that in the plan.

## Spec (for Codex)

### Before You Start

- Repo: `~/src/gitrepo/personal/k3d-manager`.
- Branch: **`k3d-manager-v1.41.0`**. Run `git pull origin k3d-manager-v1.41.0` first.
- Read these files in full before editing:
  - `bin/k3dm-test-metrics`
  - `scripts/tests/bin/test_k3dm_test_metrics.py`
  - `scripts/etc/grafana/dashboards/k3dm-tests-configmap.yaml`
  - the `test-metrics:` recipe in `Makefile`
  - `docs/guides/grafana-dashboards.md` lines 293–316

### Change 1 — `Makefile`, `test-metrics:` recipe

OLD:
```make
test-metrics:
	@set -o pipefail; \
	_log="$${TMPDIR:-/tmp}/k3dm-test-all-$$(date -u +%s).log"; \
	$(MAKE) test-all >"$${_log}" 2>&1; _rc=$$?; \
	./bin/k3dm-test-metrics "$${_log}" --target test-all --exit-code "$${_rc}"; \
```
NEW:
```make
test-metrics:
	@set -o pipefail; \
	_log="$${TMPDIR:-/tmp}/k3dm-test-all-$$(date -u +%s).log"; \
	_start=$$(date -u +%s); \
	$(MAKE) test-all >"$${_log}" 2>&1; _rc=$$?; \
	_dur=$$(( $$(date -u +%s) - _start )); \
	./bin/k3dm-test-metrics "$${_log}" --target test-all --exit-code "$${_rc}" --run-duration "$${_dur}"; \
```
Leave the remaining two lines of the recipe (`echo "[test-metrics] log: ..."` and `exit 0`) unchanged.

### Change 2 — `bin/k3dm-test-metrics`

**2a.** In `parse_log`, replace the pytest summary block.

OLD:
```python
        pytest_passed = re.search(r"(\d+)\s+passed\b", line)
        pytest_failed = re.search(r"(\d+)\s+failed\b", line)
        if pytest_passed or pytest_failed:
            passed = int(pytest_passed.group(1)) if pytest_passed else 0
            bad = int(pytest_failed.group(1)) if pytest_failed else 0
            suites["pytest"]["ok"] += passed
            suites["pytest"]["not_ok"] += bad
            total += passed + bad
            failed += bad
            last_step = "test-pytest"
```
NEW:
```python
        pytest_passed = re.search(r"(\d+)\s+passed\b", line)
        pytest_failed = re.search(r"(\d+)\s+failed\b", line)
        if pytest_passed or pytest_failed:
            passed = int(pytest_passed.group(1)) if pytest_passed else 0
            bad = int(pytest_failed.group(1)) if pytest_failed else 0
            suites["pytest"]["ok"] += passed
            suites["pytest"]["not_ok"] += bad
            total += passed + bad
            failed += bad
            pytest_time = re.search(r"\bin\s+([0-9.]+)s\b", line)
            if pytest_time:
                durations["pytest"] = float(pytest_time.group(1))
            last_step = "test-pytest"
```

**2b.** Change the `build_payload` signature.

OLD:
```python
def build_payload(parsed, target, exit_code, now=None):
```
NEW:
```python
def build_payload(parsed, target, exit_code, now=None, run_duration=None):
```

**2c.** Emit per-suite durations only for suites that reported one.

OLD:
```python
    for suite in sorted(parsed["suites"]):
        lines.append(f'k3dm_test_suite_duration_seconds{{suite="{suite}"}} {parsed["durations"].get(suite, 0)}')
```
NEW:
```python
    for suite in sorted(parsed["durations"]):
        lines.append(f'k3dm_test_suite_duration_seconds{{suite="{suite}"}} {parsed["durations"][suite]}')
```

**2d.** Replace the hard-coded run duration. The run-duration lines move out of the `lines += [...]` list; the `last_timestamp` lines stay where they are.

OLD:
```python
        f'k3dm_test_cases_failed{{target="{target}"}} {parsed["failed"]}',
        "# HELP k3dm_test_run_duration_seconds Wall-clock duration of the whole run",
        "# TYPE k3dm_test_run_duration_seconds gauge",
        "k3dm_test_run_duration_seconds 0",
        "# HELP k3dm_test_last_timestamp_seconds Unix timestamp of the last completed run",
        "# TYPE k3dm_test_last_timestamp_seconds gauge",
        f"k3dm_test_last_timestamp_seconds {now}",
    ]
```
NEW:
```python
        f'k3dm_test_cases_failed{{target="{target}"}} {parsed["failed"]}',
        "# HELP k3dm_test_last_timestamp_seconds Unix timestamp of the last completed run",
        "# TYPE k3dm_test_last_timestamp_seconds gauge",
        f"k3dm_test_last_timestamp_seconds {now}",
    ]
    if run_duration is not None:
        lines += [
            "# HELP k3dm_test_run_duration_seconds Wall-clock duration of the whole run",
            "# TYPE k3dm_test_run_duration_seconds gauge",
            f'k3dm_test_run_duration_seconds{{target="{target}"}} {run_duration}',
        ]
```

**2e.** In `main`, add the argument and pass it through.

OLD:
```python
    parser.add_argument("--exit-code", type=int, default=0)
    args = parser.parse_args(argv)
    parsed = parse_log(Path(args.log_path).read_text())
    print(f"[k3dm-test-metrics] {parsed['total']} cases, {parsed['failed']} failed")
    push_metrics(build_payload(parsed, args.target, args.exit_code), args.target, args.origin)
```
NEW:
```python
    parser.add_argument("--exit-code", type=int, default=0)
    parser.add_argument("--run-duration", type=int, default=None)
    args = parser.parse_args(argv)
    parsed = parse_log(Path(args.log_path).read_text())
    print(f"[k3dm-test-metrics] {parsed['total']} cases, {parsed['failed']} failed")
    push_metrics(
        build_payload(parsed, args.target, args.exit_code, run_duration=args.run_duration),
        args.target, args.origin,
    )
```

### Change 3 — `scripts/tests/bin/test_k3dm_test_metrics.py`

Append these tests at the end of the file:

```python
def test_pytest_summary_duration_is_parsed():
    parsed = METRICS.parse_log(fixture_text())
    assert parsed["durations"]["pytest"] == 4.0


def test_suite_without_a_reported_duration_is_omitted_not_zero():
    parsed = METRICS.parse_log("# file: clean.bats\n1..1\nok 1 works\n")
    payload = METRICS.build_payload(parsed, "test-all", 0, now=123)
    assert 'k3dm_test_suite_duration_seconds{suite="clean.bats"}' not in payload


def test_run_duration_is_published_when_measured():
    parsed = METRICS.parse_log(fixture_text())
    payload = METRICS.build_payload(parsed, "test-all", 0, now=123, run_duration=917)
    assert 'k3dm_test_run_duration_seconds{target="test-all"} 917' in payload
    assert "k3dm_test_run_duration_seconds 0" not in payload


def test_run_duration_is_omitted_when_not_measured():
    parsed = METRICS.parse_log(fixture_text())
    payload = METRICS.build_payload(parsed, "test-all", 0, now=123)
    assert "k3dm_test_run_duration_seconds" not in payload


def test_main_forwards_run_duration(monkeypatch, tmp_path):
    log = tmp_path / "run.log"
    log.write_text("# file: clean.bats\n1..1\nok 1 works\n")
    pushed = []
    monkeypatch.setattr(METRICS, "push_metrics", lambda payload, *args, **kwargs: pushed.append(payload))
    METRICS.main([str(log), "--target", "test-all", "--run-duration", "42"])
    assert 'k3dm_test_run_duration_seconds{target="test-all"} 42' in pushed[0]
```

### Change 4 — `scripts/etc/grafana/dashboards/k3dm-tests-configmap.yaml`

**4a.** Panel id 4.

OLD:
```json
          "title": "Cases by suite",
          "gridPos": { "x": 8, "y": 5, "w": 16, "h": 5 },
```
NEW:
```json
          "title": "Failing cases by suite",
          "description": "Lists only suites with at least one failed case. Empty on a clean run.",
          "gridPos": { "x": 8, "y": 5, "w": 16, "h": 5 },
```

**4b.** Panel id 5.

OLD:
```json
          "title": "Suite duration over time",
          "gridPos": { "x": 0, "y": 10, "w": 24, "h": 8 },
          "fieldConfig": { "defaults": { "unit": "s", "custom": { "lineWidth": 2, "fillOpacity": 10 } } },
          "targets": [{ "datasource": { "type": "prometheus", "uid": "P5A1115AEDF367D43" }, "expr": "k3dm_test_suite_duration_seconds", "legendFormat": "{{suite}}" }]
```
NEW:
```json
          "title": "Run duration over time",
          "description": "Whole run is the wall-clock time of make test-all. Per-suite lines appear only for suites whose runner reports its own time (pytest and the unittest files); BATS reports none.",
          "gridPos": { "x": 0, "y": 10, "w": 24, "h": 8 },
          "fieldConfig": { "defaults": { "unit": "s", "custom": { "lineWidth": 2, "fillOpacity": 10 } } },
          "targets": [
            { "datasource": { "type": "prometheus", "uid": "P5A1115AEDF367D43" }, "expr": "k3dm_test_run_duration_seconds", "legendFormat": "whole run ({{target}})" },
            { "datasource": { "type": "prometheus", "uid": "P5A1115AEDF367D43" }, "expr": "k3dm_test_suite_duration_seconds", "legendFormat": "{{suite}}" }
          ]
```

### Change 5 — `docs/guides/grafana-dashboards.md`

**5a.** In the k3dm Tests panel table, change two rows.

OLD:
```
| Cases by suite | `k3dm_test_suite_cases{result="not_ok"} > 0` |
| Suite duration over time | `k3dm_test_suite_duration_seconds` |
```
NEW:
```
| Failing cases by suite | `k3dm_test_suite_cases{result="not_ok"} > 0` (empty on a clean run) |
| Run duration over time | `k3dm_test_run_duration_seconds`, `k3dm_test_suite_duration_seconds` |
```

**5b.** Replace the "Suite duration is not wired yet" paragraph.

OLD: the four-line paragraph that begins with `**Suite duration is not wired yet.**` and ends with `not a broken push.`

NEW:
```
**Duration.** `make test-metrics` times the whole `make test-all` run and pushes it as
`k3dm_test_run_duration_seconds{target="test-all"}`. Per-suite duration is published only for
suites whose runner prints its own time: pytest's `in X.XXs` summary and unittest's
`Ran N tests in X s`. BATS prints no per-file time, so BATS suites have no duration series
rather than a fake `0`. A run pushed by an older exporter still shows the old `0`/millisecond
values until the next `make test-metrics`.
```

### Change 6 — `docs/plans/v1.42.0-daily-offline-and-e2e-verification.md`

At the end of section `### 3. Measure the actual time` (after the paragraph ending `stale data must be displayed as stale.`), append one paragraph:

```
**Offline part delivered early (v1.41.0).** The offline-suite run duration and the
"publish missing rather than 0" rule shipped as a bug fix:
`docs/bugs/2026-10-03-k3dm-tests-duration-panel-shows-only-unittest-milliseconds.md`.
The daily envelope and the two E2E runtimes remain in scope here.
```

### Change 7 — `CHANGELOG.md`

`## [Unreleased]` is currently empty. Add a `### Fixed` heading directly under it, followed by a blank line and then this single bullet:

```
- **k3dm Tests dashboard duration is now real.** `make test-metrics` now times the whole `make test-all` run and passes `--run-duration` to `bin/k3dm-test-metrics`. Before, the exporter pushed `k3dm_test_run_duration_seconds` as a literal `0` and published `0` for every suite with no parsed time, so the panel showed only the unittest files' millisecond timings against a roughly 15-minute run. The exporter now also reads pytest's summary time and omits suites with no reported duration. The panel is renamed "Run duration over time" and shows the whole run, and "Cases by suite" is renamed "Failing cases by suite", because an empty panel there is the healthy state.
```

### Gates (run them and paste the output)

1. `python3 -m pytest scripts/tests/bin/test_k3dm_test_metrics.py -q`: everything passes, including the five new tests.
2. **Mutation.** Temporarily change `run_duration` back to the hard-coded `"k3dm_test_run_duration_seconds 0"` behaviour, i.e. revert 2d in a scratch edit. Confirm that `test_run_duration_is_published_when_measured` and `test_main_forwards_run_duration` turn red. Restore the file, show that `git diff bin/k3dm-test-metrics` matches only the spec, then rerun gate 1 and confirm it is green.
3. `python3 -c 'import json,yaml,sys; d=yaml.safe_load(open("scripts/etc/grafana/dashboards/k3dm-tests-configmap.yaml")); [json.loads(v) for v in d["data"].values()]; print("dashboard json ok")'` prints `dashboard json ok`.
4. `bats scripts/tests/plugins/grafana_dashboard_appsets.bats scripts/tests/plugins/hub_pushgateway.bats`: all pass.
5. `make -n test-metrics | grep -c -- '--run-duration'` prints `1`.
6. `grep -c 'k3dm_test_run_duration_seconds 0' bin/k3dm-test-metrics` prints `0`. It exits 1 on zero matches; that is expected.
7. `shellcheck` is not applicable; no shell files change.

### Definition of Done

- [ ] Changes 1–7 applied exactly. No other files touched.
- [ ] One commit, with exactly this message:
  ```
  fix(test-metrics): publish the real run duration instead of zeros

  Co-Authored-By: Codex <noreply@openai.com>
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  ```
- [ ] Pushed to `origin/k3d-manager-v1.41.0`. Report `git rev-parse origin/k3d-manager-v1.41.0`.
- [ ] Report the commit SHA and the output of gates 1–6.

### What NOT to Do

- Do NOT create a PR or merge anything.
- Do NOT commit to `main` or skip hooks (`--no-verify`).
- Do NOT modify files outside the seven listed above. Do NOT touch `memory-bank/`, because Claude records the result.
- Do NOT add a daily scheduler, launchd plist or E2E duration. Those belong to v1.42.0.
- Do NOT run `make test-metrics` or push to a Pushgateway.
