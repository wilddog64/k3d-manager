# Copilot PR #156 review findings and related CI reds

Date: 2026-11-07. PR: wilddog64/k3d-manager#156 (branch `k3d-manager-v1.43.14`).

## Finding 1 - tunnel port cast can crash the status run

- **Comment:** 4502776202, `scripts/lib/webhook/status.py:37` (`_tunnel_port_for_context`).
- **Flagged:** `int(os.environ.get(...))` raises `ValueError` on an empty or non-numeric `TUNNEL_SANDBOX_LOCAL_PORT` / `TUNNEL_LOCAL_PORT`, crashing the whole status run.
- **Before:** `return int(os.environ.get("TUNNEL_SANDBOX_LOCAL_PORT", "16443"))` (and `TUNNEL_LOCAL_PORT`, `6443`).
- **After:** the value is parsed in a `try`; `ValueError` or a port outside 1..65535 returns the default (16443 for `ubuntu-k3s`, 6443 otherwise).
- **Root cause:** environment input was cast without validation; a misconfigured env var is an operator error that should degrade to defaults, not abort a diagnostics path.
- **Tests:** `test_tunnel_port_for_context_falls_back_on_invalid_values` in `scripts/tests/bin/webhook_status.py` covers empty, `abc`, `0`, `70000`, `-1`, `12.5` for both contexts, plus a valid override. Red on the pre-fix code (12 failures), green after.
- **Process note:** env-derived numbers in the webhook are validated at the point of use; the sibling `webhook._tunnel_port_for_provider` in `bin/k3dm-webhook` is a separate copy and was not part of this finding.

## Finding 2 - hardcoded Homebrew bash in a bats helper

- **Comment:** 4502776242, `scripts/tests/plugins/argocd_browser_listener_defaults.bats:28`.
- **Flagged:** the helper ran `/opt/homebrew/bin/bash -c`, which does not exist on the Linux CI runner (subshell exited 127).
- **Before:** `/opt/homebrew/bin/bash -c '...'`
- **After (be035329):** `shell_bin=/opt/homebrew/bin/bash; [ -x "${shell_bin}" ] || shell_bin="$(command -v bash)"; "${shell_bin}" -c '...'`
- **Root cause:** the test was written and run only on macOS and assumed a Homebrew path.
- **Process note:** tests must not assume macOS-only tools or paths; CI runs on Linux.

## Related CI reds fixed in 1f2381c2

Three suites under `scripts/tests/bin/` assumed macOS or developer-machine tools:

- `rg` (ripgrep) not installed on the runner (`browser_user_listeners.bats`, `hub_cutover.bats`).
- BSD `stat -f` syntax, which GNU `stat` rejects (`hub_cutover.bats`, `browser_user_listeners.bats`).
- `plutil` absent on Linux, so the dependent tests now skip (`install_browser_relays.bats`).

Root cause and process note are the same as Finding 2: portable tools (`grep`, a `stat` fallback) or an explicit skip when a macOS-only tool is missing.

## CI red 3 — pytest hidden by the drift fixture's scratch HOME

`scripts/tests/bin/test_release_milestones_drift.py` (`_fixture_repo`, changed on this branch in `11982d31`) runs a
nested `python3 -m pytest` and the pre-commit hook with `HOME` set to `tmp_path`. CI installs pytest with
`pip install --user`, under the real `~/.local`; Python derives the user site from `HOME`, so the child processes
reported `No module named pytest` and two tests failed. macOS and a system-wide pytest hide this.

Fix: the fixture passes `PYTHONUSERBASE` (the parent's value, or `site.getuserbase()`) to the child. Reproduced in
`ubuntu:24.04` as a non-root user with `pip install --user pytest==9.1.1`: pre-fix 2 failed (rc 1), fixed 3 passed (rc 0).

Process note: a test that swaps `HOME` and starts another Python must carry the user site with it.

## CI red 4 — `codex_dispatch.bats` S1 advisory-gates test raced the worker (run 42396866390)

- **Failure:** `not ok 237 codex dispatch S1 open advisory gates do not block resume, land, or a new task`; `git -C "$K3DM_WORKTREE_ROOT/v9.9.9/$slug" commit` failed at line 384.
- **Root cause:** `s1_start_finished` returned as soon as `$run/exit` existed. The dispatcher writes the exit marker *before* its bookkeeping (`_dispatch_codex_exit` runs `git add -A`, `write-tree`, `reset` in the worktree). The test's own `git add`/`commit` then raced that bookkeeping for the worktree index — losing on a slower CI runner.
- **Fix:** the helper now also waits until the worker PID from `$run/pid` has exited.
- **Proof:** mutation — a `sleep 1` injected between `write-tree` and `reset` made the old helper fail (`[ "$open_rc" -eq 0 ]`) and the new helper pass; dispatcher restored and `cmp`-checked. Full suite 105/105 locally.
- **Process note:** a test that waits on a "done" marker must check the marker is written last; here it is deliberately written first (so a bookkeeping failure cannot hide the exit), so "done" means the process is gone.

## CI red 5 — Ruff (pyflakes) on branch-added test files (run 42399587467)

- **Failure:** `make lint-python` found 4 errors: F841 unused `path` (`test_check_bug_status.py:138`), F401 unused `import time` (`test_hermes_checkout_lag.py:6`), F841 unused `as scratch` twice (`webhook_status.py:118`, `:214`).
- **Why it surfaced late:** every earlier run failed at a test step, so step 12 (Lint Python) was skipped; this was the first run to reach it. Ruff is also not installed on the dev Mac, so the gate never ran locally.
- **Fix:** dropped the unused names; behaviour unchanged. Verified with pinned `ruff==0.15.8` in a scratch venv ("All checks passed!"); affected pytest 37 passed, `webhook_status.py` 13 OK; `make validate-manifests` (step 13) 85/85 valid.
