# Issue: `acg-up` browser listener bootout fails when no listener is loaded

## Summary

While debugging `make up`, the macOS browser listener teardown step failed before the wrapper ever started:

```text
Boot-out failed: 5: Input/output error
ERROR: failed to execute sudo launchctl bootout system /Library/LaunchDaemons/com.k3d-manager.argocd-browser-https.plist: 5
```

## What was tested

- Ran `make up` until the Argo CD browser HTTPS listener setup block.
- Inspected `~/.local/share/k3d-manager/argocd-browser-https-launchctl.log`.

## Actual output

```text
Boot-out failed: 5: Input/output error
ERROR: failed to execute sudo launchctl bootout system /Library/LaunchDaemons/com.k3d-manager.argocd-browser-https.plist: 5
```

## Root Cause

`launchctl bootout system <plist>` returns exit code `5` when the listener is not currently loaded. That is an expected no-op during rebuilds and should not abort bootstrap.

## Follow-up

- Treat the browser listener bootout step as best-effort in `bin/acg-up`.
- Preserve the `launchctl` stderr for bootstrap/install failures so real launchd problems remain visible.
