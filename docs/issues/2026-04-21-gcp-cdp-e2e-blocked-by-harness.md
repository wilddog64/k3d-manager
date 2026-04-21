# GCP CDP end-to-end check blocked by local harness restrictions

## What I tested

- Ran `make up CLUSTER_PROVIDER=k3s-gcp`
- Ran a traced `gcp_get_credentials "https://app.pluralsight.com/hands-on/playground/cloud-sandboxes"`

## Actual output

```text
[make] Running bin/acg-up...
INFO: [acg-up] Step 1/12 — Getting k3s-gcp credentials...
INFO: [gcp] Chrome CDP not available on 127.0.0.1:9222 — launching Chrome...
make: *** [up] Error 1
```

```text
scripts/plugins/acg.sh: line 225: /Users/cliang/Library/LaunchAgents/com.k3d-manager.chrome-cdp.plist: Operation not permitted
Load failed: 5: Input/output error
Try running `launchctl bootstrap` as root for richer errors.
```

```text
*   Trying 127.0.0.1:9222...
* Immediate connect fail for 127.0.0.1: Operation not permitted
* Failed to connect to 127.0.0.1 port 9222 after 0 ms: Couldn't connect to server
```

## Root cause

The code path now attempts to bootstrap CDP, but this CLI harness cannot complete the local macOS Chrome/localhost flow: it cannot write the LaunchAgents plist and it cannot connect to `127.0.0.1:9222` even when probing locally.

## Follow-up

- Re-run `make up CLUSTER_PROVIDER=k3s-gcp` from the normal interactive shell with the user-managed Chrome/CDP session
- Confirm the updated flow stays on the sandbox tab, extracts the GCP fields, and proceeds into cluster creation
