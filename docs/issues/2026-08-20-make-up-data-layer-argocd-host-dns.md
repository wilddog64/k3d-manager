# Bug: `make up` can leave the data layer unsynced when Hub CoreDNS loses its host alias

**Filed:** 2026-08-20
**Source:** live `make up` investigation

## Observed output

```text
ERROR: [acg-up] data-layer ArgoCD Application did not reach Synced after force-sync + 180s retry — check: kubectl get application ubuntu-k3s-data-layer -n cicd --context k3d-k3d-cluster
WARN: [acg-up] failed (exit 1) — cleaning up local processes...
make: *** [up] Error 1
```

The corresponding ArgoCD condition was:

```text
Failed to load live state: failed to get cluster info for "https://host.k3d.internal:6443":
Get "https://host.k3d.internal:6443/version?timeout=32s":
dial tcp: lookup host.k3d.internal on 10.43.0.10:53: no such host
```

## Root cause

The Hub cluster registration uses `https://host.k3d.internal:6443`, whose address is
provided by the Hub CoreDNS `NodeHosts` ConfigMap. A Hub CoreDNS restart or rebuild can
drop that entry. `make up` registered the app cluster and waited for the data-layer
Application before repairing the alias, so ArgoCD could not load live state and timed
out.

## Fix

`bin/cluster-up` now restores the `host.k3d.internal` NodeHosts entry and waits for the
CoreDNS rollout immediately before registering the app cluster. If the host address or
CoreDNS is unavailable, setup continues with a warning and the later readiness check
reports the real failure.

Stale cleanup remains opt-in: `make down CLEANUP_STALE=1` runs the guarded expired
ArgoCD registration cleanup and, for k3s-aws, local stale-sandbox cleanup. The default
`make down` behavior is unchanged.

## Validation note

While inspecting the generated teardown recipe, `make -n down` still executed
recursive `$(MAKE)` and therefore ran the existing teardown command. The sandbox
was already gone, the Hub registration was deregistered, and teardown stopped at
the local Vault LaunchAgent permission error:

```text
INFO: [acg-down] AWS credentials invalid or expired — sandbox already removed. Skipping CloudFormation teardown.
INFO: [acg-down] Deregistering sandbox from hub ArgoCD...
INFO: [k3s-aws] Deregistered cluster-ubuntu-k3s + generated Applications from hub ArgoCD (cicd)
rm: cannot remove '/Users/cliang/Library/LaunchAgents/com.k3d-manager.vault-port-forward.plist': Operation not permitted
make: *** [down] Error 1
```

No follow-up live cleanup was run; subsequent verification uses static Makefile
inspection and stubbed tests only.
