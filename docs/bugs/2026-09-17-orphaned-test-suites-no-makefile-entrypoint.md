# Bug — test suites with no Makefile entrypoint run in neither `make test` nor CI

**Date:** 2026-09-17
**Branch:** `k3d-manager-v1.35.0`
**Severity:** High (silent loss of test coverage; agents have no deterministic way to run these suites)
**Related:** `docs/bugs/2026-09-17-webhook-register-secret-coverage-audit.md`
(its new `webhook_redaction.py` lands in one of the orphaned directories)

---

## Problem

`make test` delegates to `./scripts/k3d-manager test all`. That dispatcher builds its
suite list from exactly three directories, at `-maxdepth 1`
(`scripts/k3d-manager`, the `test()` function):

```bash
local -a search_dirs=("${tests_root}/lib" "${tests_root}/core" "${tests_root}/plugins")
```

CI (`.github/workflows/ci.yml`) runs a *different*, hand-maintained list:

```yaml
bats \
  scripts/tests/lib \
  scripts/tests/etc \
  scripts/tests/plugins/trivy_operator_observability.bats \
  … six more named plugin files …
```

Neither path covers everything, and the two disagree. Verified inventory:

| Suite | `make test` | CI | Count |
|-------|-------------|----|-------|
| `scripts/tests/lib` | ✅ | ✅ | — |
| `scripts/tests/core` | ✅ | ❌ | — |
| `scripts/tests/plugins` | ✅ (all) | ⚠️ (7 named files only) | — |
| `scripts/tests/etc` | ❌ | ✅ | — |
| **`scripts/tests/bin`** | ❌ | ❌ | **20 `.bats` + 4 `.py`** |
| **`scripts/tests/hermes`** | ❌ | ❌ | **9 pytest files (~106 tests)** |
| **`scripts/tests/*.bats`** (top level) | ❌ | ❌ | **3 files** |

`grep -rn "tests/bin" .github/workflows/ scripts/ Makefile` returns nothing.
No Python test in this repo is executed by any automated path — there is no
`pytest`, `python`, `requirements.txt`, `pyproject.toml` or `pytest.ini` reference
anywhere in CI or the Makefile.

The practical consequence, and the reason this is filed: **an agent handed a task in
these areas has no deterministic command to run.** The `_register_secret` spec had to
name raw `python3 <path>` invocations because no target existed. That is guesswork
encoded into a spec, and it does not survive a file rename.

---

## Naming convention (establish and document)

Two runners are needed because the files use two frameworks. The existing files
already follow a consistent split — make it explicit rather than inventing a new one:

- **`test_*.py`** → pytest (uses fixtures / `import pytest`):
  `scripts/tests/hermes/test_*.py`, `scripts/tests/bin/test_smoke_logins.py`
- **`*.py` not matching `test_*`** → stdlib `unittest`, runnable standalone via
  `python3 <file>` (each ends with `unittest.main()`):
  `webhook_request_hardening.py`, `webhook_make_targets.py`, `webhook_redaction.py`

Do **not** rename any existing file to unify these. A rename breaks every doc and
spec that names the current paths, for no functional gain.

---

## Fix — Part 1: Makefile targets (this commit)

Add these targets. Place them immediately after the existing `test:` target
(around line 679), keeping the `## ` doc-comment style used throughout the file.

```makefile
## Run the BATS suites under scripts/tests/bin (not covered by `make test`)
test-bin:
	@set -euo pipefail; \
	 command -v bats >/dev/null 2>&1 || { \
	   echo "[make] bats not found — install with: brew install bats-core" >&2; exit 2; }; \
	 bats scripts/tests/bin

## Run the stdlib-unittest Python suites (scripts/tests/bin/*.py, excluding test_*.py)
test-python-unit:
	@set -euo pipefail; \
	 found=0; \
	 for f in scripts/tests/bin/*.py; do \
	   case "$$(basename "$$f")" in test_*) continue;; esac; \
	   found=1; \
	   echo "[make] python3 $$f"; \
	   python3 "$$f"; \
	 done; \
	 if [ "$$found" -eq 0 ]; then echo "[make] no unittest suites found" >&2; exit 2; fi

## Run the pytest suites (scripts/tests/hermes + scripts/tests/bin/test_*.py)
test-pytest:
	@set -euo pipefail; \
	 python3 -m pytest --version >/dev/null 2>&1 || { \
	   echo "[make] pytest not installed for $$(python3 --version 2>&1)." >&2; \
	   echo "[make] install with: python3 -m pip install --user pytest" >&2; \
	   exit 2; }; \
	 python3 -m pytest scripts/tests/hermes scripts/tests/bin/test_smoke_logins.py

## Run every Python suite (unittest + pytest)
test-python: test-python-unit test-pytest

## Run every offline suite: BATS (dispatcher) + BATS bin + Python
test-all: test test-bin test-python
```

Add `test-bin test-python-unit test-pytest test-python test-all` to the `.PHONY`
line at line 16.

Add to the `help:` target, immediately after the existing
`make test          Run all BATS test suites` line:

```makefile
	@echo "    make test-all      Run every offline suite (BATS dispatcher + bin BATS + Python)"
	@echo "    make test-bin      Run the BATS suites under scripts/tests/bin"
	@echo "    make test-python   Run every Python suite (unittest + pytest)"
```

### Requirements on the guards

- A missing `bats` or `pytest` must **fail loudly with exit 2 and an install hint**.
  It must never be silently skipped or swallowed into a green result — a test runner
  that passes because it ran nothing is worse than no runner at all.
- `test-python-unit` must not hardcode the three current filenames. The glob is the
  point: a new `webhook_*.py` suite must be picked up with no Makefile edit.
- Every recipe uses `set -euo pipefail` and double-quotes each expansion.
- Remember Make needs `$$` for shell variables.

---

## Fix — Part 2: CI wiring (separate commit, CONDITIONAL)

**Do not write this commit until Part 1 is green locally and you have pasted the
output.** These suites have never run in CI. Some may fail. That is the expected
outcome of switching on coverage that was dark, and it must be reported, not hidden.

Run `make test-bin` and `make test-python-unit` locally first.

- **If everything passes:** add a CI step to `.github/workflows/ci.yml`, in the `lint`
  job, immediately after the existing `Run unit BATS (lib + etc + trivy plugin)` step:

  ```yaml
      - name: Run bin BATS + Python unit suites
        shell: bash
        run: |
          set -euo pipefail
          make test-bin
          make test-python-unit
  ```

  Do **not** add `test-pytest` to CI in this commit. pytest is not installed on this
  machine (`python3 -m pytest --version` → `No module named pytest`, Python 3.14.7), so
  the hermes suites cannot be verified locally before wiring, and wiring an unverified
  ~106-test suite into CI is how you get a red main. Wiring pytest is a follow-up that
  needs its own dependency-install step.

- **If anything fails:** stop. Do not fix the failing tests, do not delete them, and do
  not add the CI step. Report each failure with its verbatim output. Those failures are
  a separate finding and need a decision before anyone touches them — a test that has
  been dark for months may be asserting something the code intentionally stopped doing.

---

## Before You Start

1. Read `memory-bank/activeContext.md` and `memory-bank/progress.md`.
2. `git pull origin k3d-manager-v1.35.0`
3. Read `Makefile` lines 1–20 (header + `.PHONY`), 676–684 (the `test:` target), and
   705–722 (the `help:` target) before editing.
4. Read `.github/workflows/ci.yml` lines 55–95 (the lint job's test steps).
5. Read `scripts/k3d-manager` lines 436–442 to confirm the `search_dirs` list quoted
   above still reads as documented.

Branch (all work): `k3d-manager-v1.35.0`

---

## Definition of Done

- [ ] Five targets added to the Makefile exactly as specified.
- [ ] `.PHONY` updated; `help:` updated with the three new lines.
- [ ] `make help` runs and shows the new entries — paste the relevant output.
- [ ] `make test-bin` run — paste the FULL verbatim output, pass or fail.
- [ ] `make test-python-unit` run — paste the FULL verbatim output, pass or fail.
- [ ] `make test-pytest` run — paste its output; a clean exit-2 "pytest not installed"
      message is the expected and correct result on this machine.
- [ ] `make test` still works unchanged — paste the tail of its output.
- [ ] Part 2 CI step added **only if** `test-bin` and `test-python-unit` both passed.
      State explicitly in your report which branch of that condition you took and why.
- [ ] CHANGELOG `[Unreleased]` → `### Added` entry describing the new targets, and
      naming the coverage gap they close.
- [ ] Commit message for Part 1, verbatim:
      `build(make): add deterministic entrypoints for bin BATS and Python test suites`
- [ ] Commit message for Part 2 (only if written), verbatim:
      `ci: run bin BATS and Python unit suites in the lint job`
- [ ] Append these trailers to every commit message:
      `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`
      `Claude-Session: https://claude.ai/code/session_01B9RRyT5eU8S76oXYMrLZN8`
- [ ] `git push origin k3d-manager-v1.35.0`, then `git rev-parse origin/k3d-manager-v1.35.0`
      must equal your final commit. Do NOT report done before showing that output.
- [ ] `memory-bank/activeContext.md` and `memory-bank/progress.md` updated with the SHAs.

---

## Rules

- `set -euo pipefail` in every recipe; double-quote every expansion; `$$` for shell vars.
- Minimal patch. Do not reformat the Makefile, do not reorder targets, do not touch any
  target other than `test:`'s neighbours, `.PHONY` and `help:`.
- Do NOT touch `scripts/lib/foundation/` or `scripts/lib/acg/`.

## What NOT to Do

- Do NOT create a pull request. Do NOT merge. Do NOT commit to `main`. Do NOT force-push.
- Do NOT skip pre-commit hooks (`--no-verify`).
- Do NOT modify `scripts/k3d-manager`'s `search_dirs`. Changing the dispatcher's suite
  discovery alters what `make test` means for every existing caller and CI; the Makefile
  layer is the right seam for this fix. If you believe the dispatcher is the better fix,
  say so in your report — do not implement it.
- Do NOT edit, fix, skip, `@skip`, delete or rename any existing test to make a suite pass.
- Do NOT rename any test file to unify the pytest/unittest naming split.
- Do NOT add `test-pytest` to CI.
- Do NOT add a `requirements.txt`, `pyproject.toml` or `pytest.ini`.
- Do NOT modify files outside: `Makefile`, `.github/workflows/ci.yml` (Part 2 only),
  `CHANGELOG.md`, `memory-bank/activeContext.md`, `memory-bank/progress.md`.
