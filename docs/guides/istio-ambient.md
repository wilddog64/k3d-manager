# Istio ambient mesh

Ambient Istio's CNI DaemonSet must mount the directories used by the target cluster's CNI
substrate. `_argocd_appset_live_overrides` derives `AMBIENT_CNI_CONF_DIR` and
`AMBIENT_CNI_BIN_DIR` from that target first. A live ApplicationSet is only a fallback for cases
where the provider cannot be resolved; it must not permanently override deterministic substrate
values. For a k3s target, generic `/etc/cni/net.d` is refused.

`ARGOCD_APPSET_IGNORE_LIVE=1` bypasses the live read entirely. Use it when deliberately applying
the repository values, then confirm the generated `istio-cni` DaemonSet mounts the expected paths.
The generic defaults remain `/etc/cni/net.d` and `/opt/cni/bin` for Cilium-backed targets; bare
k3s flannel uses the `/var/lib/rancher/k3s/agent/etc/cni/net.d` and
`/var/lib/rancher/k3s/data/cni` pair exported by its provider path.

## Provider label and CNI directories

The ambient CNI directories are derived from the target's
`k3d-manager/provider` label. The only substrate-specific provider values are `k3d` and
`k3s-hostinger`; bare `k3s` resolves to the generic pair. A cluster registered without a
provider silently gets generic CNI directories. Check the label with:

```bash
kubectl -n cicd get secret cluster-<name> -o jsonpath='{.metadata.labels.k3d-manager/provider}'
```
