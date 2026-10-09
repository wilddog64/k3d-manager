# PR #138 review findings (v1.42.0)

**Date:** 2026-10-09
**PR:** #138 — v1.42.0 release
**Reviewers:** Copilot (0 findings), CI `lint` job (pyflakes F821), CodeQL (1 alert)

Copilot's overview reported **0 open findings**. It noted that a large release diff is mostly a
docs status sweep, and that the security-sensitive paths deserve human sign-off. The two real
defects came from CI and CodeQL.

## 1. `bin/k3dm-webhook:1572` — `REPO_ROOT` undefined (pyflakes F821)

`_publish_test_metrics` built the exporter path as `REPO_ROOT / "bin" / "k3dm-test-metrics"` and
ran it with `cwd=REPO_ROOT`, but `bin/k3dm-webhook` never imports `REPO_ROOT`. The
`webhook.config.REPO_ROOT` is also a `str`, so importing it would have raised `TypeError` on `/`.

**Impact:** silent. `webhook/lifecycle.py` wraps the call in `try/except Exception` and logs
only `type(exc).__name__`. A webhook `test-all` run whose output lacked the `metrics pushed`
line therefore never published its fallback metrics. The only trace was a `NameError` warning
in the webhook log.

**Fix:**

```python
# before
    command = [
        sys.executable, str(REPO_ROOT / "bin" / "k3dm-test-metrics"), str(log_path),
    ...
        command, cwd=REPO_ROOT, env=dict(os.environ), timeout=60,
# after
    repo_root = Path(__file__).resolve().parent.parent
    command = [
        sys.executable, str(repo_root / "bin" / "k3dm-test-metrics"), str(log_path),
    ...
        command, cwd=repo_root, env=dict(os.environ), timeout=60,
```

This matches how the webhook already locates `cleanup-stale-sandbox` and `k3dm-ask-bash`.

**Test:** `test_publish_test_metrics_runs_repo_exporter_from_repo_root` in
`scripts/tests/bin/test_webhook_pushgateway_provider.py`. It fails with `NameError` on the old
code and passes on the fix (`pytest scripts/tests/bin`: 536 passed, 1 skipped).

**Root cause:** commit `9c987697` added the publisher with stubbed helpers in
`webhook_lifecycle.py`. No test ever called the real function, and the broad `except` turned a
crash into a warning. `make test-all` does not run the Python lint, so only CI's `lint` job
caught it.

**Process note:** when a helper is injected through `_helpers` and is stubbed in lifecycle
tests, the real helper still needs one direct test.

## 2. `scripts/tests/bin/test_k3dm_test_metrics.py:162` — CodeQL inefficient regex

`r'="((?:\\.|[^"])*)"'` is ambiguous, because `[^"]` also matches `\`. A string like `="\!\!\!…`
can backtrack exponentially. The fix is `r'="((?:\\.|[^"\\])*)"'`, which gives the same matches
for well-formed escaped labels. `test_k3dm_test_metrics.py`: 24 passed with it.

**Status: not committed by Claude.** The regex lives inside an `assert` line. `_agent_audit`
counts an edited assertion as removed, and only the operator may override that with
`--no-verify`. The input is a fixed test payload, so the alert has no runtime exposure. The
operator can either commit the one-line change with `--no-verify`, or dismiss the alert as
"used in tests".
