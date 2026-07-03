# Alertmanager status 502 when local LaunchAgents are missing

## What was tested

- `make status CLUSTER_PROVIDER=k3s-hostinger`
- Local LaunchAgent / listener inspection on the Mac host

## Actual output

`make status CLUSTER_PROVIDER=k3s-hostinger` reported:

```text
❌ Alertmanager: HTTP 502 (https://alertmanager.3ai-talk.org/api/v2/status)
```

Local inspection showed the access layer was absent:

```text
$ launchctl list | grep alertmanager

$ ls -1 "$HOME/Library/LaunchAgents" | grep alertmanager

$ lsof -nP -iTCP:9093 -sTCP:LISTEN

$ lsof -nP -iTCP:19093 -sTCP:LISTEN
```

Existing logs showed the proxy and port-forward had worked earlier:

```text
[alertmanager-auth-proxy] code 502, message backend error: [Errno 61] Connection refused
[alertmanager-auth-proxy] "GET /api/v2/status HTTP/1.1" 502 -
```

```text
Forwarding from 127.0.0.1:19093 -> 9093
Handling connection for 19093
```

## Root cause

`bin/cluster-status` only probed the public Alertmanager URL, the Cloudflare URL, and `http://127.0.0.1:9093/api/v2/status`. It did not restore the local Alertmanager access layer when the macOS LaunchAgents had been unloaded or their plist files were missing.

That left the status command stuck reporting `502` / `000` even though the fix was local and mechanical: recreate the Alertmanager port-forward and auth-proxy LaunchAgents.

## Fix

- Added `_observability_restore_alertmanager_access_layer()` in `scripts/plugins/observability.sh`
- The helper now best-effort reinstalls the local Alertmanager port-forward and auth-proxy when:
  - either plist is missing, or
  - `localhost:19093` / `localhost:9093` are not listening
- `bin/cluster-status` now calls that helper before running service-health checks
- Added regression coverage in:
  - `scripts/tests/lib/observability.bats`
  - `scripts/tests/bin/cluster_status_observability.bats`

## Recommended follow-up

- Keep `make status CLUSTER_PROVIDER=k3s-hostinger` as the smoke test after any reboot or launchd cleanup
- If the local helper still cannot recover Alertmanager, inspect:
  - `~/Library/Logs/k3dm-alertmanager-port-forward.log`
  - `~/Library/Logs/k3dm-alertmanager-auth-proxy.log`
