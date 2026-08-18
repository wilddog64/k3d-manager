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
