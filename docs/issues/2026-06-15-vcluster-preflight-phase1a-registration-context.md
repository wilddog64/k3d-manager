# 2026-06-15 — vCluster preflight Phase 1a needed hub-context handoff + stale Helm release cleanup

## What was attempted

I reran the Phase 1a spike for `make preflight NAME=spike` after moving the vCluster onto `ubuntu-hostinger`, exposing the API as NodePort, and adding the NodePort healthz guardrail.

## Actual output

The first live attempt reached registration and then failed because `register_app_cluster` was still targeting the wrong kubectl context:

```text
INFO: [preflight] Registering spike with hub ArgoCD...
running under bash version 5.3.15(1)-release
INFO: [argocd] registering app cluster 'spike' -> https://srv1754834.hstgr.cloud:32034
Error from server (NotFound): error when creating "/tmp/argocd-cluster-secret.JTPSPu.yaml": namespaces "cicd" not found
kubectl command failed (1): kubectl apply -f /tmp/argocd-cluster-secret.JTPSPu.yaml
ERROR: failed to execute kubectl apply -f /tmp/argocd-cluster-secret.JTPSPu.yaml: 1
make: *** [preflight] Error 1
```

After that failure, a follow-up create hit stale release state in `vclusters`:

```text
fatal  vcluster spike already exists in namespace vclusters
- Use `vcluster create spike -n vclusters --upgrade` to upgrade the vcluster
- Use `vcluster connect spike -n vclusters` to access the vcluster
vcluster command failed (1): vcluster create spike -n vclusters --chart-version 0.32.1 --connect=false -f /Users/cliang/src/gitrepo/personal/k3d-manager/scripts/etc/vcluster/values-preflight.yaml
ERROR: failed to execute vcluster create spike -n vclusters --chart-version 0.32.1 --connect=false -f /Users/cliang/src/gitrepo/personal/k3d-manager/scripts/etc/vcluster/values-preflight.yaml: 1
make: *** [preflight] Error 1
```

I then removed the stale `spike` resources and the Helm release secret, reran the spike, and the fixed path succeeded:

```text
INFO: [preflight] Switching kubectl context to k3d-k3d-cluster for ArgoCD registration...
INFO: [argocd] registering app cluster 'spike' -> https://srv1754834.hstgr.cloud:32034
secret/cluster-spike created
INFO: [argocd] cluster secret applied — verify with: kubectl get secret cluster-spike -n cicd
INFO: [preflight] Phase 1a spike reached registration stop point; vCluster spike is left running
```

## Root cause

Two live assumptions were wrong for the spike:

1. `register_app_cluster` needed to run in the hub ArgoCD context, not the Hostinger vCluster host context.
2. the previous failed run left the `spike` Helm release secret in `vclusters`, which blocked a fresh `vcluster create spike` until it was removed.

## Recommended follow-up

- Keep the hub-context switch before `register_app_cluster`.
- Remove stale `sh.helm.release.v1.<name>.v1` secrets when cleaning up a failed preflight spike so the same name can be reused cleanly.
