# Slack job lookup intermittent usage — verification record

**Date:** 2026-10-21  
**Branch:** `k3d-manager-v1.43.5`  
**Task:** `slack-job-lookup-intermittent-usage`  
**Change:** `7e176833`

## What was tested

- `pytest -q scripts/tests/bin/test_webhook_thread_dispatch.py`
- Python AST parse of `bin/k3dm-webhook`
- `git diff --check`
- `_agent_audit` and `_agent_lint`
- `make check-doc-links`
- Dispatcher landing gate with the same focused tests and checks

## Actual output

Pytest:

```text
....................................                                     [100%]
=============================== warnings summary ===============================
../../../../../../.pyenv/versions/3.13.6/lib/python3.13/site-packages/_pytest/cacheprovider.py:469
  PytestCacheWarning: cache could not write path /Users/cliang/.local/share/k3d-manager/worktrees/v1.43.5/slack-job-lookup-intermittent-usage/.pytest_cache/v/cache/nodeids: [Errno 1] Operation not permitted: '/Users/cliang/.local/share/k3d-manager/worktrees/v1.43.5/slack-job-lookup-intermittent-usage/.pytest_cache/v/cache/nodeids'

-- Docs: https://docs.pytest.org/en/stable/how-to/capture-warnings.html
36 passed, 1 warning in 0.38s
```

Documentation links:

```text
check-doc-links: 2300 file(s) OK
```

The combined AST/audit/lint/diff/doc-link command exited 1 only when the final
`py_compile` step attempted to write bytecode into the isolated task worktree:

```text
[Errno 1] Operation not permitted: 'bin/__pycache__/k3dm-webhookcpython-315.pyc.4305325104'
```

AST parsing had already succeeded, and the dispatcher landing gate reran AST
parsing successfully. The dispatcher reported:

```text
out-of-scope: docs/bugs/2026-10-21-slack-find-similar-docs-job-logs-rejected.md
scope: out-of-scope (allowed)
tests: passed
landed: slack-job-lookup-intermittent-usage
push: git push origin k3d-manager-v1.43.5
```

## Findings and limitation

The new tests exercise `/slack/events` through thread lookup and the guarded
handler for exact IDs against both `find-similar-docs` and `test-all`; both return
the requested job output. Invalid/missing arguments now produce a redacted,
reason-coded warning. This demonstrates expected behavior in the current source,
but does not identify the historical payload/runtime condition responsible for
the Slack usage responses. The currently loaded webhook revision was not
confirmed and no deployment or restart was performed.

## Follow-up

Keep the canonical bug OPEN. After the updated webhook is active, the operator
should try exact `logs <job-id>` and `status <job-id>` in a job thread. If either
returns usage, correlate it with the redacted warning in the webhook log. Do not
claim LIVE-VERIFIED until exact-ID behavior is confirmed on the active process.
