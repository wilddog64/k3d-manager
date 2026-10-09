# Live issue: `make test-all` stopped at `hub-restore` case 152

## Attempted

Inspected the attached tmux test pane and process tree without stopping the run.
The pane output ended after test 152:

```text
1..328
...
ok 149 hub-restore rejects a non-TTY before any make step
ok 150 hub-restore rejects an unreadable Keychain before any make step
ok 151 hub-restore rejects the wrong Kubernetes context before any make step
ok 152 hub-restore happy path runs independent steps and prints nine-row summary
```

The next BATS process was still active after approximately 36 minutes:

```text
40674 ... test_hub-2drestore_retries_Grafana_health_until_the_port-2dforward_is_ready 153 5 1
40701 ... test_hub-2drestore_retries_Grafana_health_until_the_port-2dforward_is_ready 153 5 1
40702 ... bash bin/hub-restore
```

The child process had `/dev/ttys007` as stdin and an empty BATS output file. The
test source is:

```text
@test "hub-restore retries Grafana health until the port-forward is ready" {
  export GRAFANA_MODE=flaky
  run bin/hub-restore
```

## Result

The test is blocked before the Grafana assertion because the missing embeddings key
causes `bin/hub-restore` to wait for its interactive API-key prompt. This is tracked
in `docs/bugs/2026-10-06-hub-restore-test-hangs-on-embeddings-prompt.md`.

The fix adds a `_run_noninteractive_restore` helper that redirects stdin from
`/dev/null` for tests unrelated to prompt behavior. The focused suite now passes
14/14 both normally and under a real TTY.

## Recommended follow-up

The remaining verification is a full `make test-all` run by the operator.
