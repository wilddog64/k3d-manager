# Full test-all acceptance: 2026-10-28

Status: PASS — operator-run full suite and fresh published telemetry verified.

Operator ran the coordinator-provided native-promtool PATH command in M4's
SSH pane (%10 on M2 tmux):

```bash
PATH="/private/tmp/k3dm-prometheus-review/prometheus-3.2.1.darwin-arm64:$PATH" make test-all
```

Log `/tmp/k3dm-test-all-1793225872.log`, duration 1450 seconds, completed all
three stages. [Full verbatim BATS/unittest/pytest output](../assets/2026-10-28-test-all-1793225872.txt).
Main BATS: 1913 cases, 17 skips, no failures. Bin BATS: 623 cases, no skips or
failures. Pytest: 1661 passed, 2 skipped. Aggregator includes unittest cases:
4312 cases total, zero failed, exit code0, complete1. No passing claim for
skipped tests. The eight read-only security/kubectl attempts were blocked by
the unchanged tripwire; none reached real binaries. No Docker/OrbStack attempt
reported. Report-mode hermetic sentinel violation is intentional.

This is one complete run, not combined stage results. Repaired guard/E2E,
recovery/cleanup/OrbStack fixture and Python semantic checks all passed in it.

## Actual completion and publisher output

```text
[test-all] stage-complete test
[test-all] stage-complete test-bin
[test-all] stage-complete test-python
[test-all] stage-complete test-python
[k3dm-test-metrics] 4312 cases, 0 failed
[k3dm-test-metrics] metrics pushed: test-all/local
[k3dm-test-metrics] metrics pushed: test-all/local
[test-all] metrics log: /tmp/k3dm-test-all-1793225872.log
```

## Read-only telemetry verification

Initial hub Prometheus reads returned the previous failed run (4309, failed4,
complete0, timestamp1793224286). This was stale telemetry during the scrape
interval, not a new test failure. The first ACG request used the hub service
name and returned NotFound; service discovery corrected it to
`acg-kube-prometheus-stack-prometheus`. No resources were changed or results
republished by coordinator. Actual initial diagnostic outputs:

```json
{
  "suite": {
    "exit": 0,
    "stdout": "{\"status\":\"success\",\"data\":{\"resultType\":\"vector\",\"result\":[{\"metric\":{\"__name__\":\"k3dm_test_cases_failed\",\"instance\":\"test-all-local\",\"job\":\"k3dm-tests\",\"target\":\"test-all\"},\"value\":[1793227344.863,\"4\"]},{\"metric\":{\"__name__\":\"k3dm_test_last_timestamp_seconds\",\"instance\":\"test-all-local\",\"job\":\"k3dm-tests\"},\"value\":[1793227344.863,\"1793224286\"]},{\"metric\":{\"__name__\":\"k3dm_test_run_complete\",\"instance\":\"test-all-local\",\"job\":\"k3dm-tests\",\"target\":\"test-all\"},\"value\":[1793227344.863,\"0\"]},{\"metric\":{\"__name__\":\"k3dm_test_last_step_reached\",\"instance\":\"test-all-local\",\"job\":\"k3dm-tests\",\"step\":\"test-pytest\",\"target\":\"test-all\"},\"value\":[1793227344.863,\"1\"]}]}}",
    "stderr": ""
  },
  "alerts": {
    "exit": 0,
    "stdout": "{\"status\":\"success\",\"data\":{\"resultType\":\"vector\",\"result\":[]}}",
    "stderr": ""
  }
}
```

```json
{
  "timestamp": "2026-10-28T22:42:47.803204+00:00",
  "k3d-k3d-cluster": {
    "suite": {
      "exit": 0,
      "stdout": "{\"status\":\"success\",\"data\":{\"resultType\":\"vector\",\"result\":[{\"metric\":{\"__name__\":\"k3dm_test_cases_failed\",\"instance\":\"test-all-local\",\"job\":\"k3dm-tests\",\"target\":\"test-all\"},\"value\":[1793227367.930,\"4\"]},{\"metric\":{\"__name__\":\"k3dm_test_cases_total\",\"instance\":\"test-all-local\",\"job\":\"k3dm-tests\",\"target\":\"test-all\"},\"value\":[1793227367.930,\"4309\"]},{\"metric\":{\"__name__\":\"k3dm_test_last_timestamp_seconds\",\"instance\":\"test-all-local\",\"job\":\"k3dm-tests\"},\"value\":[1793227367.930,\"1793224286\"]},{\"metric\":{\"__name__\":\"k3dm_test_run_complete\",\"instance\":\"test-all-local\",\"job\":\"k3dm-tests\",\"target\":\"test-all\"},\"value\":[1793227367.930,\"0\"]},{\"metric\":{\"__name__\":\"k3dm_test_last_step_reached\",\"instance\":\"test-all-local\",\"job\":\"k3dm-tests\",\"step\":\"test-pytest\",\"target\":\"test-all\"},\"value\":[1793227367.930,\"1\"]}]}}",
      "stderr": ""
    },
    "alerts": {
      "exit": 0,
      "stdout": "{\"status\":\"success\",\"data\":{\"resultType\":\"vector\",\"result\":[]}}",
      "stderr": ""
    }
  },
  "ubuntu-hostinger": {
    "suite": {
      "exit": 1,
      "stdout": "",
      "stderr": "Error from server (NotFound): services \"kube-prometheus-stack-prometheus\" not found\n"
    },
    "alerts": {
      "exit": 1,
      "stdout": "",
      "stderr": "Error from server (NotFound): services \"kube-prometheus-stack-prometheus\" not found\n"
    }
  }
}
```

Final independent queries show both hub and ACG Prometheus failed0/total4312/
complete1 and last-run/success timestamp1793227322 (2026-10-28T22:42:02Z).
ACG Pushgateway independently holds exit0/classificationpassed, both success
markers, and fresh push times. Both Prometheus ALERTS queries for
OfflineSuiteFailing/OfflineSuiteRunIncomplete returned empty results. Hub
Pushgateway has no local matching group in this sample; hub Prometheus's
matching scraped values are recorded rather than inventing a hub-group result.
No historical email retraction or Grafana visual check claimed.

```json
{
  "timestamp": "2026-10-28T22:43:07.835692+00:00",
  "k3d-k3d-cluster": {
    "suite": {
      "exit": 0,
      "stdout": "{\"status\":\"success\",\"data\":{\"resultType\":\"vector\",\"result\":[{\"metric\":{\"__name__\":\"k3dm_test_cases_failed\",\"instance\":\"test-all-local\",\"job\":\"k3dm-tests\",\"target\":\"test-all\"},\"value\":[1793227387.924,\"0\"]},{\"metric\":{\"__name__\":\"k3dm_test_cases_total\",\"instance\":\"test-all-local\",\"job\":\"k3dm-tests\",\"target\":\"test-all\"},\"value\":[1793227387.924,\"4312\"]},{\"metric\":{\"__name__\":\"k3dm_test_last_timestamp_seconds\",\"instance\":\"test-all-local\",\"job\":\"k3dm-tests\"},\"value\":[1793227387.924,\"1793227322\"]},{\"metric\":{\"__name__\":\"k3dm_test_run_complete\",\"instance\":\"test-all-local\",\"job\":\"k3dm-tests\",\"target\":\"test-all\"},\"value\":[1793227387.924,\"1\"]},{\"metric\":{\"__name__\":\"k3dm_test_last_step_reached\",\"instance\":\"test-all-local\",\"job\":\"k3dm-tests\",\"step\":\"test-pytest\",\"target\":\"test-all\"},\"value\":[1793227387.924,\"1\"]},{\"metric\":{\"__name__\":\"k3dm_test_last_success_timestamp_seconds\",\"instance\":\"test-all-local\",\"job\":\"k3dm-tests\"},\"value\":[1793227387.924,\"1793227322\"]},{\"metric\":{\"__name__\":\"k3dm_test_last_success_timestamp_seconds\",\"instance\":\"test-all-local-last-success\",\"job\":\"k3dm-tests\"},\"value\":[1793227387.924,\"1793227322\"]}]}}",
      "stderr": ""
    },
    "alerts": {
      "exit": 0,
      "stdout": "{\"status\":\"success\",\"data\":{\"resultType\":\"vector\",\"result\":[]}}",
      "stderr": ""
    },
    "pushgateway": {
      "exit": 0,
      "selected_lines": [],
      "stderr": ""
    }
  },
  "ubuntu-hostinger": {
    "suite": {
      "exit": 0,
      "stdout": "{\"status\":\"success\",\"data\":{\"resultType\":\"vector\",\"result\":[{\"metric\":{\"__name__\":\"k3dm_test_cases_failed\",\"instance\":\"test-all-local\",\"job\":\"k3dm-tests\",\"target\":\"test-all\"},\"value\":[1793227388.522,\"0\"]},{\"metric\":{\"__name__\":\"k3dm_test_cases_total\",\"instance\":\"test-all-local\",\"job\":\"k3dm-tests\",\"target\":\"test-all\"},\"value\":[1793227388.522,\"4312\"]},{\"metric\":{\"__name__\":\"k3dm_test_last_timestamp_seconds\",\"instance\":\"test-all-local\",\"job\":\"k3dm-tests\"},\"value\":[1793227388.522,\"1793227322\"]},{\"metric\":{\"__name__\":\"k3dm_test_run_complete\",\"instance\":\"test-all-local\",\"job\":\"k3dm-tests\",\"target\":\"test-all\"},\"value\":[1793227388.522,\"1\"]},{\"metric\":{\"__name__\":\"k3dm_test_last_step_reached\",\"instance\":\"test-all-local\",\"job\":\"k3dm-tests\",\"step\":\"test-pytest\",\"target\":\"test-all\"},\"value\":[1793227388.522,\"1\"]},{\"metric\":{\"__name__\":\"k3dm_test_last_success_timestamp_seconds\",\"instance\":\"test-all-local\",\"job\":\"k3dm-tests\"},\"value\":[1793227388.522,\"1793227322\"]},{\"metric\":{\"__name__\":\"k3dm_test_last_success_timestamp_seconds\",\"instance\":\"test-all-local-last-success\",\"job\":\"k3dm-tests\"},\"value\":[1793227388.522,\"1793227322\"]}]}}",
      "stderr": ""
    },
    "alerts": {
      "exit": 0,
      "stdout": "{\"status\":\"success\",\"data\":{\"resultType\":\"vector\",\"result\":[]}}",
      "stderr": ""
    },
    "pushgateway": {
      "exit": 0,
      "selected_lines": [
        "k3dm_test_cases_failed{instance=\"test-all-local\",job=\"k3dm-tests\",target=\"test-all\"} 0",
        "k3dm_test_cases_total{instance=\"test-all-local\",job=\"k3dm-tests\",target=\"test-all\"} 4312",
        "k3dm_test_exit_code{instance=\"test-all-local\",job=\"k3dm-tests\",target=\"test-all\"} 0",
        "k3dm_test_last_step_reached{instance=\"test-all-local\",job=\"k3dm-tests\",step=\"test-pytest\",target=\"test-all\"} 1",
        "k3dm_test_last_success_timestamp_seconds{instance=\"test-all-local\",job=\"k3dm-tests\"} 1.793227322e+09",
        "k3dm_test_last_success_timestamp_seconds{instance=\"test-all-local-last-success\",job=\"k3dm-tests\"} 1.793227322e+09",
        "k3dm_test_last_timestamp_seconds{instance=\"test-all-local\",job=\"k3dm-tests\"} 1.793227322e+09",
        "k3dm_test_run_classification{classification=\"passed\",instance=\"test-all-local\",job=\"k3dm-tests\",target=\"test-all\"} 1",
        "k3dm_test_run_complete{instance=\"test-all-local\",job=\"k3dm-tests\",target=\"test-all\"} 1",
        "k3dm_test_run_duration_seconds{instance=\"test-all-local\",job=\"k3dm-tests\",target=\"test-all\"} 1450",
        "push_time_seconds{instance=\"test-all-local\",job=\"k3dm-tests\"} 1.7932273233497655e+09",
        "push_time_seconds{instance=\"test-all-local-last-success\",job=\"k3dm-tests\"} 1.793227323921894e+09"
      ],
      "stderr": ""
    }
  }
}
```

## Completion record

Implementation commits include 5a2a958f, 0514e9d9, cfb60be0, a7b5e5df,
and 6578fb95. Current verification checkout: 418ea8aa. No runtime edits for
this verification. BATS full output is linked above; ShellCheck not rerun for
this documentation-only verification (prior touched-shell evidence retained).
Required documentation lint/audit/checkpoint hooks run before commit. No PR
created under repository rule. P2 full-suite acceptance M5/E3 now satisfied;
original missing historical raw output remains explicitly unavailable.
Cloudflare login/Slack acceptance and the Kine recovery decision are separate
open tasks; this pass does not authorize any live configuration or rebuild.
