# Keycloak browser launchd plist was installed under `~/Library/LaunchDaemons`

## What was tested
- Ran `make up` on the macOS browser bootstrap path after the Keycloak listener changes.
- Observed the Keycloak listener fail during the privileged install step.

## Actual output
```text
Password:
install: /Users/cliang/Library/LaunchDaemons/INS@aFDBm9: No such file or directory
ERROR: failed to execute sudo install -m 644 /Users/cliang/.local/share/k3d-manager/keycloak-browser-http.plist /Users/cliang/Library/LaunchDaemons/com.k3d-manager.keycloak-browser-http.plist: 71
```

## Root cause
- `bin/acg-up` staged the Keycloak browser plist under `~/Library/LaunchDaemons`.
- That directory does not exist on this machine, so `sudo install` failed before `launchctl bootstrap` could run.
- The daemon is meant to run in the system launchd domain, so it should live under `/Library/LaunchDaemons` instead.

## Follow-up
- Move the Keycloak browser plist path to `/Library/LaunchDaemons`.
- Keep `bin/acg-down` aligned with the same plist path so teardown can remove it reliably.
