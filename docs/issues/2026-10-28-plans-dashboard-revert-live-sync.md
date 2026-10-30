# Release Plans dashboard revert sync

## What was tested

After the operator asked to restore the original Plans table, pushed commit `915c55f4` (closeout `8f4cea4b`) and hard-refreshed the hub ArgoCD application `hub-grafana-dashboards` on M4. The app auto-synced from `k3d-manager-v1.43.9`.

## Actual output

The initial short SSH alias was invalid:

```text
ssh: Could not resolve hostname m4: nodename nor servname provided, or not known
```

Using the configured alias succeeded:

```text
m4-air.local
m4-air.local
```

ArgoCD accepted the hard refresh:

```text
application.argoproj.io/hub-grafana-dashboards annotated
```

The app was first observed during reconciliation:

```text
k3d-manager-v1.43.9	OutOfSync	Healthy	8f4cea4bb5ac5f4e1b2f31df86a424fb91cfbb28,8f4cea4bb5ac5f4e1b2f31df86a424fb91cfbb28	Running
```

It then reported:

```text
Synced	Healthy	Succeeded	8f4cea4bb5ac5f4e1b2f31df86a424fb91cfbb28,8f4cea4bb5ac5f4e1b2f31df86a424fb91cfbb28
Synced	Healthy	Succeeded	8f4cea4bb5ac5f4e1b2f31df86a424fb91cfbb28,8f4cea4bb5ac5f4e1b2f31df86a424fb91cfbb28
```

The final ConfigMap check returned:

```text
Plans
{
  "release": "Release",
  "order": "Order",
  "plan": "Plan",
  "title": "Title",
  "depends_on": "Depends on",
  "wave": "Wave",
  "wave_note": "Wave note",
  "overlaps": "Overlaps",
  "blocked_by": "Blocked by",
  "execution": "Execution",
  "verification": "Verified",
  "approval": "Spec approval",
  "dispatch_approval": "Dispatch",
  "dispatch_state": "Dispatch task",
  "slug": "Dispatch task"
}
false
false
```

The two booleans are checks that the panel query contains neither `landed; documentation stale` nor the `live_verified` projection. An earlier jq inspection expression failed with `jq: error (at <stdin>:2850): Cannot index string with string "id"`; this was only a malformed inspection filter. The corrected query above succeeded.

## Root cause and result

The short host alias was not configured; `m4-air.local` is the working SSH alias. The jq error was a local query-expression issue. Neither indicated an ArgoCD or Kubernetes failure. ArgoCD is now `Synced`/`Healthy` at commit `8f4cea4b`, and panel 107's live ConfigMap has the restored single Verification column, original Dispatch labels, and original Blocked by query.

## Recommended follow-up

Refresh the Grafana browser page to see the restored table. No pod restart was needed. The operator and Claude still need to decide which verification columns and status wording the Plans table should use before either P3 dashboard enhancement is resumed.

## Follow-up — Bug Tracking row still appeared Fixed in screenshot

The operator supplied a screenshot where `2026-10-26-plans-table-live-verification-column` still showed `Fixed`, `fixed_in=v1.43.9`, fix commit `7ec87a73`, and verification evidence. Read-only inspection confirmed the M4 checkout's `origin/k3d-manager-v1.43.9` contains the bug doc with `Status: OPEN`. The live Pushgateway and Prometheus were then checked directly. Prometheus returned the bug as `open` both by bug label and using the dashboard's Auto/current-release join. Exact output:

```text
open	v1.43.9	-	-	-	-	1
```

The Pushgateway had a current `k3dm-bug-open` publication:

```text
push_time_seconds{instance="",job="k3dm-bug-open"} 1.7930642165555031e+09
push_time_seconds{instance="lib-foundation",job="k3dm-bug-open"} 1.7930642245756197e+09
```

The live source of truth now says Open, with `fixed_in`, `fix_sha`, `verified`, and `live_verified` all absent (`-`). Therefore the screenshot is consistent with an older rendered panel result; browser refresh is still needed to confirm the UI catches up. If it continues to show Fixed after refresh, inspect the live panel query and variable values.
