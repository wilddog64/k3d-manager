# Bug: the hub webhook's `python3` has no pytest, so `make test-python` fails on m5

**Status:** OPEN — capture
**Priority:** P2
**Introduced by:** unknown (likely the Homebrew Python upgrade to 3.15 on m5; pytest lived in an older site-packages)
**Should have been caught by:** live check
**Introducing change reviewed:** no
**Waiting on:** operator decision — since 2026-11-27
**Prior art:** exact-slug glob: none; `make find-similar-docs` not run
**Severity:** medium — every hub `test-python` / `test-pytest` / `test-all` run ends exit 2 even with enough time.
**Filed:** 2026-11-27, Claude, from the timed run for `2026-11-27-hub-make-test-all-exceeds-1800s-job-timeout.md`

## Evidence

- m5, 2026-11-27 19:35Z, webhook PATH: `make test-python` → `[make] no pytest found. Tried $PYTEST, pytest on PATH,
  python3 -m pytest, and $HOME/.pyenv/shims/python3 -m pytest.`
- `python3` resolves to `/opt/homebrew/opt/python@3.15/bin/python3.15`; `python3 -m pytest` → `No module named pytest`;
  no `~/.pyenv/shims/python3`.

## Notes for triage

Homebrew Python is externally managed (PEP 668), so `pip install --user` is refused by default. Options to prove first:
a dedicated hub venv that the Makefile's pytest lookup finds (for example via `PYTEST`), or `brew install pytest` if
the formula targets 3.15. A change to m5 is the operator's.
