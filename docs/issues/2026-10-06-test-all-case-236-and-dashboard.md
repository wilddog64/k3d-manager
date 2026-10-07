# Live `make test-all` failure and dashboard evidence

## Test result

The tmux pane showed cases 149 through 235 passing after the prompt-hang fix. Case
236 failed, and the suite completed all 328 cases:

```text
ok 235 e2e passes DIGEST through to the vcluster harness
not ok 236 recorded output preserves exit status and is mode 600
# (in test file scripts/tests/bin/makefile_e2e_recorded.bats, line 43)
#   `[ "${status}" -eq 2 ]' failed
...
ok 328 a curl timeout reports its exit code instead of a doubled 000000
[k3dm-test-metrics] 1707 cases, 1 failed
[k3dm-test-metrics] metrics pushed: test-all/local
[test-all] metrics log: /tmp/k3dm-test-all-1791341010.log
make: *** [test-all] Error 2
```

The focused test output was:

```text
make: `probe' is up to date.
```

This proves the test fixture extractor stopped at an earlier `endef` and did not
include `_e2e_recorded`.

## Dashboard result

The local Pushgateway health endpoint returned `OK`, and its metrics endpoint
contained:

```text
k3dm_test_cases_total{instance="test-all-local",job="k3dm-tests",target="test-all"} 1707
k3dm_test_exit_code{instance="test-all-local",job="k3dm-tests",target="test-all"} 2
k3dm_test_run_duration_seconds{instance="test-all-local",job="k3dm-tests",target="test-all"} 466
k3dm_test_suite_cases{instance="test-all-local",job="k3dm-tests",result="not_ok",suite="bats"} 1
```

The dashboard screenshot still showed `No data` in every panel. The active local
port 9091 forward targets `ubuntu-hostinger`, while the dashboard source uses the
ACG datasource UID `P5A1115AEDF367D43`. The dashboard and publisher are therefore
likely pointed at different Prometheus instances; the deployed Grafana API required
authentication, so this topology needs live confirmation after the config fix.
