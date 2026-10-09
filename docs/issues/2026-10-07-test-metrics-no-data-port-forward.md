# Test dashboard no-data state caused by missing Pushgateway forward

## Request

The operator reported that the k3dm Tests dashboard became `No data` after the P0
last-success retention change.

## Investigation

The local metrics endpoint used by the exporter and hub scrape topology was unavailable:

```text
curl: (7) Failed to connect to localhost port 9091 after 0 ms: Couldn't connect to server
Could not find service "com.k3d-manager.pushgateway-port-forward" in domain for user gui: 501
```

The hub Pushgateway forward on port 19094 was separate and did not restore the Hostinger
endpoint expected at localhost:9091. No `com.k3d-manager.pushgateway-port-forward` LaunchAgent
was loaded.

## Recovery

Ran:

```text
make refresh-edge CLUSTER_PROVIDER=k3s-hostinger
```

The access-layer refresh restarted `com.k3d-manager.pushgateway-port-forward`. Read-only
verification then returned:

```text
TCP 127.0.0.1:9091 (LISTEN)
OK
k3dm_test_last_success_timestamp_seconds{instance="test-all-local",job="k3dm-tests"} 1.791379071e+09
k3dm_test_run_classification{classification="passed",instance="test-all-local",job="k3dm-tests",target="test-all"} 1
```

## Conclusion

This incident was local access-layer downtime, not a regression in the P0 success-marker
implementation. If the dashboard becomes empty again, verify the 9091 Pushgateway forward
before changing dashboard or exporter code.
