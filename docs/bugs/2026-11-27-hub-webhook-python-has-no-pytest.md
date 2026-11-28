# Bug: the hub webhook's `python3` has no pytest, so `make test-python` fails on m5

**Status:** LANDED — `60e15c51` + `27d32d14`, 2026-11-27 (Flash; Claude added broken-venv rebuild, made fast-gate Y-N1 observable, fixed a PATH leak in two tests); offline Y-E1 PASS, live Y-E2 owed
**Priority:** P2
**Introduced by:** unknown (likely the Homebrew Python upgrade to 3.15 on m5; pytest lived in an older site-packages)
**Should have been caught by:** live check
**Introducing change reviewed:** no
**Waiting on:** live check — since 2026-11-27 (promote, then operator runs `make install-pytest-venv` on m5)
**Prior art:** exact-slug glob: none; `make find-similar-docs` unavailable on m4 (no k3d-k3d-cluster context) — not run
**Severity:** medium — every hub `test-python` / `test-pytest` / `test-all` run ends exit 2 even with enough time.
**Filed:** 2026-11-27, Claude, from the timed run for `2026-11-27-hub-make-test-all-exceeds-1800s-job-timeout.md`
**Approval:** operator, 2026-11-27 ("I think you can do 1, 2, 4, and 5!" — item 1: pytest on the hub)
**Intent approved:** operator, 2026-11-27
**Intent approval words:** "intents approved" (Y-E1, Y-E2 as written in rev 1)
**Component:** `Makefile` pytest lookups; `scripts/ci/fast_gate.sh` pytest lookup

## Evidence

- m5, 2026-11-27 19:35Z, webhook PATH: `make test-python` → `[make] no pytest found. Tried $PYTEST, pytest on PATH,
  python3 -m pytest, and $HOME/.pyenv/shims/python3 -m pytest.`
- `python3` resolves to `/opt/homebrew/opt/python@3.15/bin/python3.15`; `python3 -m pytest` → `No module named pytest`;
  `python3.14` the same; neither has `yaml`; no `~/.pyenv/shims/python3`.
- Test imports outside the standard library are only `pytest` and `yaml` (grep of `scripts/tests/bin/*.py`,
  `scripts/lib/**/*.py`, 2026-11-27); the plain `python3` unit scripts import neither.
- **Proof of the fix (Claude, m5, 2026-11-27, read-only scratch):** `python3.15 -m venv /tmp/k3dm-venv-probe` then
  `pip install pytest==9.1.1 PyYAML==6.0.3` succeeded (PEP 668 does not apply inside a venv). In the scratch clone at
  `deploy/hub` `1c74deb3`, webhook PATH, `PYTEST="/tmp/k3dm-venv-probe/bin/python -m pytest" make test-pytest`:
  **3002 passed, 1 failed, 2 skipped in 399 s**. The failure (`test_r9_requires_stale_values_branch_and_pins_deploy_hub`,
  `refused: deploy-ref-unknown`) is the scratch clone lacking a `deploy/hub` ref, not the venv.
- Homebrew's `pytest` formula alone does not fix it: it installs into its own isolated venv without PyYAML.

## Fix

1. **`make install-pytest-venv`** creates `$(HOME)/.local/share/k3d-manager/pytest-venv` with the Homebrew `python3`
   (`python3 -m venv`), installs exactly `pytest==9.1.1` and `PyYAML==6.0.3`, and prints the venv's `pytest --version`.
   Re-running it is idempotent (reuses the venv, reinstalls the pins). It never uses `sudo` or `pip --user` and never
   touches the system Python.
2. **One more fallback in every pytest lookup**, after the pyenv shim and before "no pytest found":
   `$HOME/.local/share/k3d-manager/pytest-venv/bin/python -m pytest` when that file is executable and
   `-m pytest --version` succeeds. `$PYTEST` and the existing order stay first. Sites: `Makefile:1628`
   (`check-release-milestones`), `:1712` (`test-pytest`), `:1985` (`test-all` parallel), `:2230` (`test-all` serial),
   `scripts/ci/fast_gate.sh:39`. The "no pytest found" messages name `make install-pytest-venv`.
3. **Manifest:** `scripts/etc/machine/not-installed.list` gets `install-pytest-venv|operator-run on the hub: …` so
   the machine-setup disjointness test stays green.
4. **Docs:** `docs/howto/webhook-operations.md` (hub prerequisites: run `make install-pytest-venv` once per hub, and
   after a Homebrew Python minor upgrade).

Out of scope: installing it on m5 (operator runs `make install-pytest-venv` after the promote); machine-setup
automation.

## Files

- `Makefile`
- `scripts/ci/fast_gate.sh`
- `scripts/etc/machine/not-installed.list`
- `docs/howto/webhook-operations.md`
- `scripts/tests/bin/makefile_test_all.bats`
- `scripts/tests/lib/fast_gate.bats`
- `scripts/tests/bin/makefile_install_pytest_venv.bats` (new)

## Contract readers

- Venv path `$HOME/.local/share/k3d-manager/pytest-venv`: writer `make install-pytest-venv` (new); readers the five
  lookup sites above. No other file names it (grep `pytest-venv`, 2026-11-27: none).
- `PYTEST` env: readers the same five sites; unchanged and still first.
- `not-installed.list`: reader `scripts/tests/bin/machine_setup.bats:260` (disjointness) and `bin/k3dm-machine-setup`.

## Acceptance

```yaml
must:
  - id: Y-M1
    text: "with no PYTEST, no pytest on PATH, python3 lacking pytest and no pyenv shim, every lookup uses $HOME/.local/share/k3d-manager/pytest-venv/bin/python -m pytest when it works"
  - id: Y-M2
    text: "make install-pytest-venv creates the venv with exactly pytest==9.1.1 and PyYAML==6.0.3, idempotently, without sudo or pip --user"
  - id: Y-M3
    text: "with neither available, the error names make install-pytest-venv and the exit code is unchanged (2; fast gate still prints SKIP)"
must_not:
  - id: Y-N1
    text: "the venv is used when PYTEST or an earlier lookup already works"
    red_on_current: "green on current (no venv branch); mutant 'venv checked first' turns it red"
  - id: Y-N2
    text: "a lookup site still reports no pytest while a working venv exists"
    red_on_current: "red: no site checks the venv path today"
  - id: Y-N3
    text: "the install target reaches the network, sudo or the real HOME in tests"
    red_on_current: "green on current (target absent); test runs the target with a fake HOME and a stub python3 that records its argv, and asserts no sudo/--user"
evidence:
  - id: Y-E1
    proves: [Y-M1, Y-M2, Y-M3, Y-N1, Y-N2, Y-N3]
    kind: offline
    command: "bats makefile_test_all.bats, fast_gate.bats and makefile_install_pytest_venv.bats pass under PATH=/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin with fake HOME and stub interpreters; Y-N2 red on pre-fix code; Y-N1 mutant red; machine_setup.bats disjointness green"
    intent: "The test commands find pytest in a small dedicated environment on the hub, and installing that environment is one command that touches nothing else."
  - id: Y-E2
    proves: [Y-M1, Y-M2]
    kind: live
    command: "after a hub promote: operator runs make install-pytest-venv on m5; Claude (read-only) confirms the venv's pytest --version, then a cloud make-test-pytest finishes without 'no pytest found'"
    intent: "Running the Python tests from a cloud session works on the hub again."
interface:
  - "make install-pytest-venv"
  - "$HOME/.local/share/k3d-manager/pytest-venv/bin/python -m pytest (fallback after the pyenv shim)"
```

## Live check — 2026-11-27 (Claude, read-only plus one cloud request)

- Promote `15660f42` (operator), then `make install-pytest-venv` on m5 (operator). Venv: pytest 9.1.1, PyYAML 6.0.3,
  Python 3.15.2.
- `make-test-pytest` through the webhook (request `20261127T235409Z-make-test-pytest`, job `46243ccb`): pytest
  resolved from the venv and ran — **3005 passed**, 2 skipped, **2 failed** (Y-E2: the "no pytest found" stop is gone).
- The 2 failures are a test-isolation defect exposed now that the hub runs pytest at all:
  `test_release_milestones_drift.py` sets `HOME` to `tmp_path`, so the nested `make check-release-milestones` cannot
  reach `$HOME/.local/share/k3d-manager/pytest-venv`; m4 passed only because pyenv/Homebrew python3 carry pytest.
  Reproduced on m4 with a `python3` stand-in lacking pytest (2 failed), fixed by passing
  `PYTEST="<sys.executable> -m pytest"` into the fixture env (3 passed under both PATHs; `make lint-python` clean).
- Remaining: promote the test fix, rerun `make-test-pytest` (expect 0 failed), then the overnight `make-test-all`.
