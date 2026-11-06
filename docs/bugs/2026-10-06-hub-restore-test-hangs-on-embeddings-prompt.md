# `make test-all` hangs in `hub-restore` Grafana retry test

Status: FIXED
Severity: Medium
Area: Test isolation / non-interactive execution

## Evidence

An interactive `make test-all` run stopped after:

```text
ok 151 hub-restore rejects the wrong Kubernetes context before any make step
ok 152 hub-restore happy path runs independent steps and prints nine-row summary
```

The running process tree showed the next test had been executing for more than
36 minutes:

```text
40353 ... bats-exec-file ... hub_restore.bats ...
40674 ... bats-exec-test ... test_hub-2drestore_retries_Grafana_health_until_the_port-2dforward_is_ready 153 5 1
40702 ... bash bin/hub-restore
```

The active test is:

```text
@test "hub-restore retries Grafana health until the port-forward is ready" {
  export GRAFANA_MODE=flaky
  run bin/hub-restore
```

Its setup leaves the embeddings key absent (`EMBEDDINGS_LENGTH` is unset). Because
the test is running from a TTY, `bin/hub-restore` treats stdin as interactive and
waits for the missing-key prompt before reaching Step 9, where the Grafana retry
assertion is located. The captured BATS output file remained empty while the
process held `/dev/ttys007` as stdin.

## Root cause

The test intends to exercise Grafana retry behavior but does not make the
embeddings-key path non-interactive. `run bin/hub-restore` therefore inherits the
operator's tmux TTY and can block forever waiting for input. This makes the full
suite hang instead of failing with a bounded assertion.

## Recommended fix

Tests that are unrelated to interactive key entry now run `bin/hub-restore` with
stdin redirected from `/dev/null`. This keeps the production prompt behavior intact
while preventing an inherited tmux/Terminal TTY from blocking the suite. The focused
Grafana retry test completes under a TTY and verifies its three health probes.

## Follow-up

The adjacent Grafana failure test and the other non-interactive restore cases now use
the same helper. Interactive prompt tests retain their explicit stdin fixtures.

## Recurrence 2026-11-05: two `_run_with_tty` preflight tests fail when stdin is inherited

- **Seen:** the D3 Part B land gate (`land-test.2.log`), tests "rejects an unreadable Keychain before any make step" (line 224) and "rejects the wrong Kubernetes context before any make step" (line 234), both `[ "${status}" -eq 2 ]`. The same two reds were seen once on 2026-10-30 (memory-bank progress, `hub-cutover` entry) and written off as not reproduced.
- **Deterministic, not a flake:** on unchanged `k3d-manager-v1.43.14` (`3d369254`), `bats -f '…' scripts/tests/bin/hub_restore.bats` fails both tests 3/3 when stdin is inherited from Claude's Bash tool, and passes both with `</dev/null`. Not caused by Part B.
- **Cause (likely):** the earlier fix gave the hub-restore tests `/dev/null` stdin through a helper, but these two run through `_run_with_tty` (`script -q …`), which forwards the caller's stdin into the pty. Not yet traced inside `bin/hub-restore`.
- **Workaround used:** the Part B land ran its `--test` chain with `</dev/null`; 400/400 passed.
- **Fix (not done):** have `_run_with_tty` feed `script` from `/dev/null` (or a closed pipe), so a test's result never depends on the caller's stdin. Add a test that runs the two cases with stdin inherited.
