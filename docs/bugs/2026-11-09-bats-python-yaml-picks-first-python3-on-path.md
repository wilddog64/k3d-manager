# Bug: BATS tests that parse YAML use the first python3 on PATH, which may lack PyYAML

**Status:** OPEN — child C1 of `docs/bugs/2026-11-09-offline-test-all-red-on-m4-four-root-causes.md`; spec written
**Priority:** P2
**Waiting on:** dispatch — since 2026-11-09
**Introduced by:** pre-existing (each file has called bare `python3` since it was written; it surfaced when the
personal envrc's `layout python3` put a venv without PyYAML first on PATH)
**Should have been caught by:** review
**Prior art:** none above threshold — exact-slug glob empty; `make find-similar-docs` not run to a result (vector
store unreachable from the M4, 2026-11-09)
**Severity:** medium — 27 of the 35 offline failures on the M4; one more assertion (`argocd.bats:389`) silently does
not run on such a host
**Approval:** operator, 2026-11-09 (parent bug: one P2 parent with a child per root cause)
**Intent approved:** operator, 2026-11-09 ("your C1 is approved"); dispatch go not yet given
**Filed:** 2026-11-09
**Detected by:** Claude, 2026-11-09, serial `make test` baseline on the M4
**Release:** v1.43.16 (bug-only)
**Branch:** filed on `k3d-manager-v1.43.15`; fix goes on `k3d-manager-v1.43.16`

## Symptom

On the M4, from the operator's shell under `~/src/gitrepo/personal`, `make test` fails 27 cases in six files with
`ModuleNotFoundError: No module named 'yaml'` (captured 2026-11-09):

| File | Failing cases |
|---|---|
| `scripts/tests/plugins/e2e_observability.bats` | 16 |
| `scripts/tests/plugins/vectordb_rules.bats` | 5 |
| `scripts/tests/plugins/dr_alert_rules.bats` | 2 |
| `scripts/tests/plugins/hub_pushgateway.bats` | 2 |
| `scripts/tests/lib/ci_workflow_no_stage2.bats` | 1 |
| `scripts/tests/plugins/argocd_app_cluster_generator.bats` | 1 |

With `/opt/homebrew/bin` first on PATH (Python 3.15.2, PyYAML present) all six pass.

A seventh file hides the same problem: `scripts/tests/plugins/argocd.bats:389` wraps its YAML check in
`if … python3 -c 'import yaml'; then`, so on this host that check never runs and the case passes anyway.

## Root cause

The personal envrc (`~/src/gitrepo/personal/.envrc`) runs `layout python3`, which puts a direnv venv
(`~/.cache/direnv/layouts/…/python-3.13/bin`) first on PATH. That venv has no PyYAML. The tests call bare
`python3 -` / `python3 -c` and take whatever is first. CI is green because `.github/workflows/ci.yml:30` installs
`PyYAML==6.0.2` into the python it puts on PATH.

Installing PyYAML into the venv would fix the M4 alone. It would break again on the next machine, venv rebuild or
envrc change, and the parent's N2 rules it out.

## Fix

1. New sourced helper `scripts/tests/python_yaml.bash` defines `k3dm_python_yaml`. It prints the path of the
   first interpreter that can `import yaml`, trying in order: `$K3DM_TEST_PYTHON3` (if set), `python3` on PATH,
   `/opt/homebrew/bin/python3`, `/usr/local/bin/python3`, `/usr/bin/python3`. If none can, it prints
   `no python3 with PyYAML found (tried: …); set K3DM_TEST_PYTHON3` to stderr and returns non-zero. Never `skip`.
2. The six files and `argocd.bats` source it in `setup` (or `setup_file`) and use the resolved interpreter wherever
   they now call `python3` for YAML work. When resolution fails, the case **fails** with that message.
3. `argocd.bats:389`: drop the `if … import yaml` guard, so the YAML check always runs, through the helper.
4. No change to production code, the Makefile, CI, or any python environment.

Out of scope: `scripts/tests/lib/fast_gate.bats` (stubs `python3` itself, line 43); python test files (`test_*.py`),
which run under whatever runs pytest; `scripts/tests/bin/alert_delivery_status_python.bats`, which passes on the M4
today (listed for the verifier to confirm, not changed).

## Contract readers

New env var `K3DM_TEST_PYTHON3`, read only by the new helper. `grep -rn K3DM_TEST_PYTHON3` on 2026-11-09 finds no
existing reader. `K3DM_PYTHON3_PATH` (`Makefile:34`, launch agent templates) is a different contract and is not
read or changed.

## Acceptance

```yaml
must:
  - id: M1
    text: the six files pass under make test when the first python3 on PATH has no PyYAML and another listed
      interpreter has it.
  - id: M2
    text: when no candidate interpreter can import yaml, each affected case fails (not skips) with a message naming
      K3DM_TEST_PYTHON3.
  - id: M3
    text: K3DM_TEST_PYTHON3, when set to an interpreter with PyYAML, is used ahead of python3 on PATH.
  - id: M4
    text: the YAML check in argocd.bats (formerly behind the import guard at line 389) runs on every host.
must_not:
  - id: N1
    text: no case in the seven files is deleted, skipped or weakened; the number of cases per file does not drop.
  - id: N2
    text: no package is installed into any python environment, and no python environment is created, by the fix or
      its tests.
  - id: N3
    text: an affected case must not pass when no interpreter has PyYAML (no silent skip, no vacuous pass).
evidence:
  - id: E1
    proves: M1
    kind: offline
    intent: With a python that lacks PyYAML first on PATH, as on your M4, the six files go from red to green.
  - id: E2
    proves: M2, N3
    kind: offline
    intent: With no python that has PyYAML anywhere in the candidate list, the cases fail with a clear message
      instead of passing or skipping. Before the fix, argocd.bats passes in this setup, which is the red result.
  - id: E3
    proves: M3
    kind: offline
    intent: Setting K3DM_TEST_PYTHON3 makes the tests use that interpreter even when another python comes first.
  - id: E4
    proves: N1
    kind: offline
    intent: Case counts per file are the same before and after.
  - id: E5
    proves: M1
    kind: live
    intent: Claude runs make test on the M4 from your normal shell, with direnv active, and it shows zero yaml failures.
interface:
  - scripts/tests/python_yaml.bash (k3dm_python_yaml)
  - K3DM_TEST_PYTHON3
  - make test
  - the seven bats files named above
```

Test fixtures for E1–E3 build fake interpreters in `BATS_TEST_TMPDIR`. One is a `python3` shim that exits 1 on
`import yaml`, imitating the direnv venv. The real venv behaviour was captured on `m4-air`, 2026-11-09: `python3 -c
'import yaml'` gives `ModuleNotFoundError: No module named 'yaml'`. Each fixture first asserts that the interpreter
it resolved is the fake one, not a real system python. The `/opt/homebrew` and `/usr` fallbacks must be overridable
for the "none has PyYAML" case. The helper reads the candidate list from `K3DM_TEST_PYTHON3_CANDIDATES` when set,
test-only.

## Worker definition of done

- E1–E4 run and pass. Paste each command, rc and the proving line.
- E2's red run against pre-fix `argocd.bats` is shown.
- `git diff --stat` touches only the seven bats files and the new helper, plus new tests.
- No `pip`, `uv` or `venv` command appears in the diff or the run log.
