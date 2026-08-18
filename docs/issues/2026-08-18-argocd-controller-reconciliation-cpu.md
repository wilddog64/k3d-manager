# ArgoCD controller reconciliation CPU

## Finding

The hub CPU snapshot identified `argocd-application-controller` as the largest pod
consumer at 860m CPU. Its logs showed repeated refreshes for already-Synced Istio
Applications after updates to `istio-leader` and
`istio-namespace-controller-election` ConfigMaps. Those updates are leader-election
heartbeats and are not GitOps desired-state changes.

## Fix

The ArgoCD values template now:

- ignores the Istio leader-election annotation under
  `resource.customizations.ignoreResourceUpdates.ConfigMap`;
- caps the single controller's worker pools at `--status-processors=5` and
  `--operation-processors=2` (instead of the chart defaults).

This preserves one controller replica and normal reconciliation while preventing
volatile election metadata from causing avoidable refresh work and bounding concurrent
reconciliation on the 4-core hub.

## Evidence

```text
argocd-application-controller-0  860m
prometheus-0                     373m
argocd-repo-server               203m
grafana                          191m
```

The change is source-persistent through the repository's ArgoCD Helm values template;
it must be applied with the normal ArgoCD deployment/reconciliation path.

## Live verification

The first Helm deployment attempt was rejected by server-side apply ownership conflicts
on existing `argocd-cm` and `argocd-rbac-cm` fields. Retrying the same release with Helm's
explicit `--force-conflicts` option succeeded. The live controller now reports:

```text
["/usr/local/bin/argocd-application-controller","--metrics-port=8082","--status-processors=5","--operation-processors=2"]
```

and the live `argocd-cm` contains the ConfigMap leader-election ignore customization.
After the rollout settled, node CPU was:

```text
k3d-k3d-cluster-agent-0    826m   8%
k3d-k3d-cluster-agent-1   2094m  20%
k3d-k3d-cluster-agent-2    676m   6%
k3d-k3d-cluster-server-0  1714m  17%
```

The hub is no longer CPU-saturated; the controller settled at approximately 910m during
the observation window. The initial post-rollout spike was transient reconciliation work.
