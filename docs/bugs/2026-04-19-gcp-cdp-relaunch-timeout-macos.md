# Bug: macOS Chrome relaunch with CDP times out after warned restart

**Branch:** `k3d-manager-v1.1.0`
**Files Implicated:** `scripts/plugins/gcp.sh`

---

## Summary

When `gcp_get_credentials` detects that Chrome is running without CDP on macOS,
the current warned-restart flow kills Chrome, relaunches it with
`--remote-debugging-port=9222`, then waits up to 15 seconds for
`http://localhost:9222/json` to respond. In practice, the relaunch often does not
expose CDP on port `9222`, so `make up CLUSTER_PROVIDER=k3s-gcp` fails before
Playwright even starts.

---

## Actual Output

```text
[make] CLUSTER_PROVIDER=k3s-gcp — running deploy_cluster...
running under bash version 5.3.9(1)-release
INFO: Detected macOS environment.
INFO: Using cluster provider: k3s-gcp
INFO: [k3s-gcp] Extracting GCP sandbox credentials...
INFO: [gcp] Chrome is running without CDP. It must be restarted to enable --remote-debugging-port=9222.
INFO: [gcp] Chrome will restore your tabs via session restore.
INFO: [gcp] Restarting Chrome in 5 seconds — Ctrl+C to abort...
INFO: [gcp] Launching Chrome with CDP port 9222 and your default profile...
ERROR: [gcp] Timed out waiting for Chrome CDP on port 9222
make: *** [up] Error 1
```

---

## Root Cause

The current spec chain assumed that this macOS relaunch sequence is reliable:

```bash
pkill -x "Google Chrome"
sleep 1
open -a "Google Chrome" --args --remote-debugging-port=9222
```

That assumption is not reliable in practice. On macOS, `open -a ... --args ...`
after a Chrome restart does not consistently result in a browser process that
exposes CDP on port `9222` within the expected 15-second window.

This is not the older Playwright CDP cleanup bug:

- The timeout occurs **before** Playwright connects to CDP
- The failure is in the GCP launcher/restart path in `scripts/plugins/gcp.sh`
- The old `acg_credentials.js` `.close()` / `allPages[0]` issues were real, but are
  already fixed and are not what this log shows

---

## Impact

- `make up CLUSTER_PROVIDER=k3s-gcp` fails before credential extraction begins
- The user loses time and browser continuity for no successful outcome
- Re-running produces the same restart → wait → timeout cycle, creating an
  operational loop even though each individual run exits

---

## Recommended Follow-up

1. Do **not** silently restart Chrome on macOS unless CDP availability after
   relaunch is proven reliable in the target environment.
2. Prefer the safer behavior already described in
   `docs/bugs/v1.1.0-bugfix-gcp-cdp-no-auto-restart.md`:
   - if Chrome is already running without CDP, print exact restart instructions and fail fast
   - if Chrome is not running, launch with CDP
3. Reconcile memory-bank so the older "Playwright CDP Destructive Cleanup" issue is
   marked historical/resolved, and this launcher timeout is tracked as the active problem.
