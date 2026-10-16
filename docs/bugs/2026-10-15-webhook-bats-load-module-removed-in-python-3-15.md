# Bug: webhook BATS tests fail on Python 3.15 — `SourceFileLoader.load_module()` was removed

**Filed:** 2026-10-15
**Branch:** `k3d-manager-v1.43.2`
**Status:** OPEN
**Priority:** P3 — test-only; it fails only where `python3` resolves to 3.15, and the operator's pyenv 3.13 still passes
**Approval:** explicit 2026-10-15 "go ahead" (operator, to "should I file the Python 3.15 `load_module` issue as a P3 bug?")
**Severity:** low — no runtime code is affected; the four tests go red as soon as the shell's `python3` is 3.15

## Symptom

`make test` at `0214f363`, run from a shell whose `python3` is Homebrew 3.15.0, ended 1594/1598 with:

```text
not ok 349 smoke test ESO wiring samples app and hub through helper
not ok 374 Slack cluster parser accepts tokens in any order and dry-run isolates execution
not ok 415 webhook role helpers preserve token admin and fail closed
not ok 416 webhook fix mode requires operator+ role, not question phrasing
```

Each failure is a bare `[ "$status" -eq 0 ]`, so BATS does not show the cause. Running one of the
inline snippets directly shows it:

```text
AttributeError: 'SourceFileLoader' object has no attribute 'load_module'. Did you mean '.exec_module' instead of '.load_module'?
```

The same commit passes all four tests under pyenv's 3.13.6, which the operator's tmux shell resolves
first: `make test-metrics` gave 3002 cases with 0 failed. Rerunning the two suites with
`PATH="$HOME/.pyenv/shims:$PATH"` gave 74/74.

## Root cause

`importlib.machinery.SourceFileLoader.load_module()` was deprecated since Python 3.4 and is removed
in 3.15. The tests load the extensionless `bin/k3dm-webhook` script that way, in five places:

- `scripts/tests/lib/webhook.bats:419`
- `scripts/tests/lib/webhook.bats:1004`
- `scripts/tests/lib/webhook.bats:1020`
- `scripts/tests/lib/webhook.bats:1021` (`scripts/lib/webhook/agent.py`)
- `scripts/tests/lib/webhook_hub_eso.bats:149`

Which interpreter runs depends on `PATH` order. This machine has `/opt/homebrew/bin/python3`
(3.15), `~/.pyenv/shims/python3` (3.13) and `/usr/bin/python3`. A pyenv upgrade, or any shell
that puts Homebrew first, turns these four tests red without any code change.

## Fix

Use the loader pattern the pytest suites already use (`scripts/tests/bin/webhook_agent.py:14`). An
explicit `SourceFileLoader` is needed because `bin/k3dm-webhook` has no `.py` extension:

```python
import importlib.util
from importlib.machinery import SourceFileLoader

def _load(name, path):
    spec = importlib.util.spec_from_file_location(name, path, loader=SourceFileLoader(name, path))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

webhook = _load("k3dm_webhook", os.environ["K3DM_WEBHOOK_PATH"])
```

Apply it at all five call sites. Leave the assertions unchanged.

## Files

- `scripts/tests/lib/webhook.bats`
- `scripts/tests/lib/webhook_hub_eso.bats`

## Definition of Done

- [ ] `grep -rn 'load_module()' scripts/tests` returns nothing.
- [ ] Both suites pass under 3.15:
      `PATH=/opt/homebrew/bin:$PATH scripts/tests/tripwire.sh bats scripts/tests/lib/webhook_hub_eso.bats scripts/tests/lib/webhook.bats`
- [ ] Both suites still pass under 3.13 (`PATH="$HOME/.pyenv/shims:$PATH"`).
- [ ] Commit message: `test(webhook): load bin/k3dm-webhook with exec_module for Python 3.15`
