# acg-down aborted when browser launchd listeners were already absent

## What Happened
`make down` failed during the browser daemon teardown step even when the Keycloak or Argo CD browser listeners were already gone.

Observed output:

```text
launchctl command failed (5): sudo launchctl bootout system /Library/LaunchDaemons/com.k3d-manager.keycloak-browser-http.plist
WARN: [acg-down] existing Keycloak browser HTTP listener was not loaded; continuing
INFO: [acg-down] Stopping ArgoCD browser HTTPS listener launchd daemon...
make: *** [down] Error 1
```

## Root Cause
The ArgoCD browser listener teardown still used a fatal `_run_command` invocation, so a missing launchd daemon turned the no-op bootout into a hard failure.

## Fix
- Treat both browser listener bootout calls as best-effort.
- Capture the `launchctl` stderr and warn when the listener is already absent.

## Follow-Up
- Keep teardown idempotent.
- Missing launchd daemons should never fail `make down` when `--keep-hub` or teardown cleanup is being run repeatedly.
