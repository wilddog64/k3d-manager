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
