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
