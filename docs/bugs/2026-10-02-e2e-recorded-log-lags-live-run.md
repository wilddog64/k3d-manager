# Bug: the `make e2e` recorded log lags far behind a live run

**Status:** OPEN
**Branch:** `k3d-manager-v1.40.0`
**File:** `Makefile` (`define _e2e_recorded`)
**Tests:** `scripts/tests/bin/makefile_e2e_recorded.bats`
**Introduced by:** `937c4bfe fix(e2e): persist full make output for interactive runs`

## Symptom

During the 2026-10-02 `make e2e` run that started at 17:26:38Z,
`~/.k3dm/e2e/make-e2e-20261002T172638Z.log` stayed at 2,699 bytes, last written at 10:28 local.
In the same minutes the operator's `| tee /tmp/e2e.log` copy had already reached the rabbitmq
rollout. So a watcher that tails the recorded log, which was the reason for recording it, sees
almost nothing until the run exits.

## Root cause

Neither branch of the macro asks `script(1)` to flush:

- **macOS (BSD) `script`:** flushes on a timer (`-t`, default 30s) and holds onto output in
  between. `-F` means "Immediately flush output after each write".
- **Linux (util-linux) `script`:** buffers its output unless `-f` / `--flush` is given.

## Fix

Old:
```make
if [ "$$(uname -s)" = Darwin ]; then script -q "$${_log}" $(2); else script -q -e -c "$(2)" "$${_log}"; fi
```
New:
```make
if [ "$$(uname -s)" = Darwin ]; then script -q -F "$${_log}" $(2); else script -q -f -e -c "$(2)" "$${_log}"; fi
```

## Test (append to `scripts/tests/bin/makefile_e2e_recorded.bats`)

`make -n` prints the whole `if` line, so both branches can be checked on either OS:

```bash
@test "e2e recording flushes on every write on both platforms" {
  run make --no-print-directory -C "${REPO_ROOT}" -n e2e
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"script -q -F "* ]]
  [[ "${output}" == *"script -q -f -e -c "* ]]
}
```

**Mutation check (must report):** drop `-F` → the test goes red. Restore it, then drop `-f` → the
test goes red. Restore both and run the whole file green. The existing exit-status test (`exit 7`)
must stay green, because it actually runs the Darwin or Linux branch.

## Rules

- `bats scripts/tests/bin/makefile_e2e_recorded.bats`: all green; paste the summary.
- Change only the one macro line. Leave the log path, `umask 077` and the target bodies as they are.

## Definition of Done

- [ ] Fix applied exactly as written
- [ ] Test added and green; mutation results reported
- [ ] Status line set to `FIXED (<short sha>)`
- [ ] Commit message: `fix(e2e): flush the recorded make log on every write`
- [ ] Pushed to `origin/k3d-manager-v1.40.0`; report `git rev-parse origin/k3d-manager-v1.40.0`

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify files other than `Makefile`, the bats file above, and this doc
- Do NOT commit to `main`
- Do NOT run `make e2e`: a live run is in progress on the operator's cluster
