# v0.5.5 — `_run_parallel`: run one command per item, N at a time, with per-item results

**Status:** OPEN — spec written 2026-11-09; dispatch after `lib-foundation-v0.5.5-install-promtool` lands (same files)
**Approval:** operator, 2026-11-09. This is Part A of k3d-manager `docs/plans/v1.44.0-parallel-offline-tests.md`
(operator exception: "I'd like it happen sooner than later"). Dispatch: Claude; not a hub or Hostinger change.
**Intent approved:** operator, 2026-11-09
**Branch:** `feat/run-parallel`
**Requested by:** k3d-manager `make test-all PARALLEL=1` (Part B of the plan above). The operator wants the runner in
lib-foundation so it works on macOS and Linux, including the Linux control node.

## Problem

k3d-manager's offline suite takes 1238 s serially on the M4. A hand-run of one job per file, four at a time, slowest
first, took 338 s (2026-11-09, `m4-air`). There is no library function for that, and base-OS tools must be used (no GNU
parallel).

## Fix spec

Add `_run_parallel` to `scripts/lib/system.sh`, after `_install_promtool`.

    _run_parallel [--jobs N] --out DIR [--order-by FILE] [--retry-failed] [--flaky-ok] -- CMD [ARG...]

- **Items:** NUL-separated on stdin. For each item it runs `CMD ARG... <item>`, the item as the last argument, never
  through `eval` or a shell string. An empty input returns 0 and prints `TOTAL 0s`.
- **Concurrency:** `xargs -0 -r -n 1 -P N`, the flags BSD and GNU xargs share. BSD xargs on `m4-air`, macOS 26.5.2,
  2026-11-09: `man xargs` lists `-P maxprocs` and `-r, --no-run-if-empty`. The per-item work runs in a small helper
  that xargs calls through `bash -c '…' _ "$item"`. The item is passed as a positional argument, never interpolated.
- **Jobs:** `--jobs N` (a positive integer, else return 2). Default: `sysctl -n hw.perflevel0.physicalcpu` when that
  succeeds (Apple Silicon performance cores), else `getconf _NPROCESSORS_ONLN`, else 1.
- **Per item, under `--out DIR`:** `<key>.log` (stdout and stderr), `<key>.rc`, `<key>.sec` (whole seconds). `<key>` is
  the item with every character outside `[A-Za-z0-9._-]` replaced by `_`. If two items map to the same key, append `-2`,
  `-3`, ….
- **Order:** with `--order-by FILE`, lines `<seconds> <item>` from a previous run. Items in the file start longest
  first. Items not in the file start before all known ones, in input order. Without it, input order.
- **Retry:** with `--retry-failed`, every failed item reruns once, alone, after the pool drains. Its first attempt's log
  is kept as `<key>.try1.log`. Pass on rerun → `FLAKY`; fail again → `FAIL`.
- **Summary on stdout,** after all items, sorted by item:
  `PASS <item> <s>s`, `FAIL <item> <s>s (rc N)` or `FLAKY <item> <s>s`, then `SLOWEST <item> <s>s` and `TOTAL <s>s`
  (wall time). The format follows `scripts/ci/fast_gate.sh:217` in k3d-manager. It also writes `<out>/times.txt`
  (`<seconds> <item>` per item), usable as the next `--order-by`.
- **Return:** 0 when every item is PASS, or PASS/FLAKY with `--flaky-ok`; otherwise 1. Bad usage returns 2. A failure
  never exits the caller's shell.

## Files

| File | Change |
|---|---|
| `scripts/lib/system.sh` | `_run_parallel` and its private helper |
| `scripts/tests/lib/run_parallel.bats` | tests below (new file) |
| `docs/api/functions.md` | one entry |
| `CHANGE.md` | entry under Unreleased |

## Rules

- Tests use tiny fake jobs written into `BATS_TEST_TMPDIR`: a script that sleeps for a given time, exits with a given rc,
  or fails on its first call and passes on its second (using a marker file). The fixture first asserts that the job
  script it runs is the one under `BATS_TEST_TMPDIR`.
- To check concurrency, jobs record start and end times and the test asserts that at most N overlap. To check order,
  `--jobs 1` with `--order-by`, and the test reads start order from the logs. Keep total test sleep under 10 s.
- Items containing spaces, quotes, `$(…)`, `;` and a leading `-` must run as literal arguments (shell-injection test).
- Run the tests with GNU xargs as well if it is present (`gxargs`); skip that one case with a named reason when it is
  absent. BSD xargs is the default on macOS.
- Run `make bats` and `make shellcheck-lib`. Leave the changes uncommitted; Claude reviews and commits.
- Do not change any other function.

## Acceptance

```yaml
must:
  - id: M1
    text: "Every item runs exactly once (twice only for a retried failure), with at most N running at the same time, and each item gets its .log, .rc and .sec."
  - id: M2
    text: "With --order-by, known items start longest first and unknown items start before them; times.txt from one run is accepted by the next."
  - id: M3
    text: "With --retry-failed, an item that fails and then passes is reported FLAKY by name, and the rc is 1 unless --flaky-ok is given (then 0)."
  - id: M4
    text: "The summary has one PASS/FAIL/FLAKY line per item, then SLOWEST and TOTAL lines in the stated format."
  - id: M5
    text: "Without --jobs, N comes from hw.perflevel0.physicalcpu when sysctl provides it, else getconf _NPROCESSORS_ONLN (paired positive control: a stubbed sysctl value is used)."
must_not:
  - id: N1
    text: "A failing item never yields rc 0 without --retry-failed and a passing rerun, at any job count or order."
  - id: N2
    text: "An item is never interpreted by a shell: items with spaces, quotes, $(…), ; or a leading - reach the command as one literal argument."
  - id: N3
    text: "Without --retry-failed, no item runs more than once."
  - id: N4
    text: "A failure or bad usage returns non-zero without exiting a calling shell running set -e in a subshell."
evidence:
  - {id: E1, proves: [M1, M2, M3, M4, M5, N1, N2, N3, N4], kind: offline, intent: "Tests with tiny fake jobs show every job runs once, N at a time, slowest first, a flaky job is named, odd file names stay literal, and a failure always means a red result. Each must_not is shown red by a mutant."}
  - {id: E2, proves: [M1], kind: live, intent: "Claude runs it on the M4 over k3d-manager's BATS files and compares the per-file results with a serial run at the same commit."}
interface:
  - "_run_parallel (source scripts/lib/system.sh) --jobs --out --order-by --retry-failed --flaky-ok -- CMD"
  - "env: PATH (sysctl, getconf, xargs stubs allowed)"
```

## Worker definition of done

- `make bats` and `make shellcheck-lib` pass; paste each command, rc and the proving lines.
- For each must_not, name the mutant and paste its red run.
- `git diff --stat` touches only the four files above.
- No `eval`, no GNU parallel, and no `sudo` in the diff.
