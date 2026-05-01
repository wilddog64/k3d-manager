# Issue: `acg-up` misclassifies sealed Vault as port-forward failure

**Date:** 2026-04-28
**Status:** Fixed in `bin/acg-up`
**Severity:** High

## What Was Attempted

The user reran `make up` after the lib-acg credential fix and subtree sync.

Observed output:

```text
INFO: [k3s-aws] Verify: kubectl --context ubuntu-k3s get nodes
INFO: [acg-up] Step 3/12 — Starting SSH tunnel...
[tunnel] already running
INFO: [acg-up] Step 3.5/12 — Verifying local Hub cluster (create if missing)...
INFO: [acg-up] Local Hub cluster verified.
INFO: [acg-up] Step 4/12 — Starting Vault port-forward (k3d → localhost:8200)...
INFO: [acg-up] Vault port-forward PID: 4921 (log: /Users/cliang/.local/share/k3d-manager/vault-pf.log)
ERROR: [acg-up] Vault not responding on localhost:8200 — port-forward may have failed. Check: /Users/cliang/.local/share/k3d-manager/vault-pf.log
make: *** [up] Error 1
```

## Actual State

The port-forward log showed repeated pod disconnects:

```text
Handling connection for 8200
error: lost connection to pod
Forwarding from 127.0.0.1:8200 -> 8200
Forwarding from [::1]:8200 -> 8200
```

The actual Vault pod was running in namespace `secrets`, but sealed:

```text
$ kubectl --context k3d-k3d-cluster -n secrets get pods,svc,endpoints
NAME                                                    READY   STATUS    RESTARTS      AGE
pod/external-secrets-6546d4b9cf-xhkgl                   1/1     Running   1 (13h ago)   23h
pod/external-secrets-cert-controller-6cb7cd6b45-wjcwv   1/1     Running   1 (13h ago)   23h
pod/external-secrets-webhook-5545945875-rz4wr           1/1     Running   1 (13h ago)   23h
pod/vault-0                                             0/1     Running   1 (13h ago)   23h
```

Vault pod labels and readiness after manual recovery:

```text
$ kubectl --context k3d-k3d-cluster -n secrets get pod vault-0 -o jsonpath='{.metadata.labels.vault-sealed}{"\n"}{.status.containerStatuses[0].ready}{"\n"}'
false
true
```

Health after unseal:

```text
$ curl -sS -i --max-time 5 http://127.0.0.1:8200/v1/sys/health
HTTP/1.1 200 OK
Cache-Control: no-store
Content-Type: application/json
Strict-Transport-Security: max-age=31536000; includeSubDomains
Date: Tue, 28 Apr 2026 23:52:10 GMT
Content-Length: 420

{"initialized":true,"sealed":false,"standby":false,"performance_standby":false,"replication_performance_mode":"disabled","replication_dr_mode":"disabled","server_time_utc":1777420330,"version":"1.20.1","enterprise":false,"cluster_name":"vault-cluster-0a4c80aa","cluster_id":"e7eba381-0a43-d8c9-d4be-6686acd5bae5","echo_duration_ms":0,"clock_skew_ms":0,"replication_primary_canary_age_ms":0,"removed_from_cluster":false}
```

## Root Cause

`bin/acg-up` used:

```text
curl -sf --max-time 5 http://localhost:8200/v1/sys/health
```

Vault returns useful JSON for sealed state, but the health endpoint uses a non-2xx status for sealed Vault. `curl -f` discards that response and exits non-zero, so `acg-up` replaced the real response with `{}` and classified the state as `unknown`.

That caused the wrong operator-facing error:

```text
Vault not responding on localhost:8200 — port-forward may have failed
```

The correct classification was:

```text
Vault is sealed
```

## Fix

`bin/acg-up` now:

1. Uses `curl -s` without `-f` for `/v1/sys/health`, preserving sealed-state JSON.
2. Detects `"sealed":true`.
3. Switches to the local Hub context.
4. Runs the existing cached recovery path:

```text
./scripts/k3d-manager deploy_vault --re-unseal
```

5. Rechecks Vault health before continuing.

## Live Recovery Output

```text
$ kubectl config use-context k3d-k3d-cluster
Switched to context "k3d-k3d-cluster".
```

```text
$ ./scripts/k3d-manager deploy_vault --re-unseal
running under bash version 5.3.9(1)-release
INFO: [vault] applying 1 cached unseal shard(s) to secrets/vault
INFO: [vault] vault secrets/vault is now unsealed
```

## Verification

Post-fix checks:

```text
$ bash -n bin/acg-up
```

```text
$ shellcheck -x bin/acg-up
```

```text
$ git diff --check
```

```text
$ ./scripts/k3d-manager _agent_audit
running under bash version 5.3.9(1)-release
```

```text
$ bats scripts/tests/bin/acg_sync_apps.bats scripts/tests/lib/acg.bats
1..15
ok 1 acg-sync-apps reuses a managed port-forward
ok 2 acg-sync-apps replaces an unmanaged listener on 8080
ok 3 acg-sync-apps preserves the port-forward log on failure
ok 4 acg-sync-apps uses non-interactive ArgoCD login flags
ok 5 _acg_write_credentials writes [default] profile to ~/.aws/credentials
ok 6 _acg_write_credentials sets file permissions to 600
ok 7 _acg_write_credentials creates ~/.aws directory if missing
ok 8 acg_import_credentials parses label format (Pluralsight UI copy)
ok 9 acg_import_credentials parses export format
ok 10 acg_import_credentials succeeds with AKIA key and no session token
ok 11 acg_import_credentials returns 1 on empty/unparseable input
ok 12 acg_import_credentials --help exits 0
ok 13 acg_get_credentials --help exits 0
ok 14 _acg_extend_playwright: returns 0 when node script succeeds
ok 15 _acg_extend_playwright: returns 1 when node script fails
```
