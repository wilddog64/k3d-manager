# Two pytest suites ran nowhere in CI

**Filed:** 2026-09-25
**Branch:** k3d-manager-v1.38.0
**Severity:** gate hole — a green CI proved less than it claimed

## Symptom

`scripts/tests/bin/cloud_bridge.py` held 20 pytest-style tests, including the four P6
drift guards and the six mutation tests that are the security argument for exposing
`make` targets through the cloud bridge. None of them executed in CI.

`scripts/tests/bin/test_webhook_pushgateway_provider.py` (5 tests) ran nowhere either.
That one is pre-existing and unrelated to v1.38.0.

## Root cause

CI runs `make test`, `make test-bin`, `make test-python-unit`, `make test-pytest`. The
two Python targets partition `scripts/tests/bin/*.py` by filename, and both files fell
through the gap:

- `test-python-unit` globs `*.py`, skips `test_*.py`, and runs the rest as `python3 <file>`.
  That works for the seven `webhook_*.py` suites because they are unittest-style and end in
  `unittest.main()`. `cloud_bridge.py` was pytest-style — bare `def test_` functions with no
  main hook — so `python3 scripts/tests/bin/cloud_bridge.py` defined 20 functions, called
  none, and exited 0. **The target passed vacuously.**
- `test-pytest` ran an explicit three-entry list (`scripts/tests/hermes`,
  `test_smoke_logins.py`, `test_check_doc_links.py`). Neither file was in it.

The suites only ever passed because the P6 handoff told Codex to run bare
`pytest scripts/tests/bin/cloud_bridge.py` by hand, and Claude verified the same way. Both
saw real green. No make target or CI job did.

The Makefile comment above `test-pytest` already read
`(scripts/tests/hermes + scripts/tests/bin/test_*.py)` — the recipe had drifted from its own
documented contract.

## Fix

1. `git mv scripts/tests/bin/cloud_bridge.py scripts/tests/bin/test_cloud_bridge.py` — the
   file now obeys the convention the Makefile already documented, and the rename alone moves
   it out of the vacuous `test-python-unit` glob.
2. `test-pytest` globs `scripts/tests/bin/test_*.py` instead of naming files. This fixes both
   orphans at once and means a future `test_*.py` is collected without a Makefile edit.
3. `test-python-unit` gained a guard: a file that defines `^def test_` but has no
   `unittest.main()` / `pytest.main(` hook fails the target with exit 2 and a message naming
   the rename. A pytest-style file can no longer pass by executing nothing.

## Verification

- `make test-pytest` — 213 passed, rc=0. `test_cloud_bridge.py` 23 and
  `test_webhook_pushgateway_provider.py` 5 are collected; both were previously absent.
- `make test-python-unit` — rc=0, seven unittest suites run as before.
- The guard was mutation-tested: a temporary `zz_guard_probe.py` containing a bare
  `def test_vacuous(): assert False` makes `test-python-unit` exit 2 with the new message.
  Before the fix that same file passed silently at rc=0. Probe removed.

## Process note

The lesson is not the glob. It is that "the agent ran the suite and pasted green output" and
"the suite runs in CI" are different claims, and the P6 handoff only ever demanded the first.
A gate that names a file by hand does not prove the file is wired into anything. Handoffs that
require a test run should require it **through the make target CI invokes**, not through a
direct `pytest <path>`.
