# `KubeHpaMaxedOut` fires permanently for `istiod` and `istio-ingressgateway`: the HPAs are pinned at min = max = 1

**Filed:** 2026-10-02
**Branch:** `k3d-manager-v1.40.0`
**Severity:** low. Two alerts that can never clear (firing since 2026-09-27T18:46Z, the hub rebuild) teach the
operator to ignore `KubeHpaMaxedOut`, and they keep the Overview's Firing Alerts panel red.
**Status:** FIXED (pending rollout)

## Evidence (hub `k3d-k3d-cluster`, 2026-10-02)

| HPA | Targets | Min | Max | Replicas |
|---|---|---|---|---|
| `istio-system/istio-ingressgateway` | cpu 15% / 80% | 1 | 1 | 1 |
| `istio-system/istiod` | cpu 7% / 80% | 1 | 1 | 1 |

No load: `kubectl top` shows 15m and 7m CPU against 100m requests. The kube-prometheus rule fires when
`current_replicas == max_replicas` for 15 minutes, which is always true when max is 1.

## Cause

`scripts/etc/istio-operator.yaml.tmpl` (used by `scripts/lib/providers/k3d.sh` and `k3s.sh`) deliberately pins
both components to one replica on the single-node hub, but does it with an HPA whose `minReplicas` and
`maxReplicas` are both `1`. The pin is correct; expressing it as an HPA that can never scale is the defect.

## Fix (`scripts/etc/istio-operator.yaml.tmpl` only)

Turn autoscaling off and set one replica, so no HPA exists:

1. `components.pilot.k8s`: remove the `hpaSpec` block and add `replicaCount: 1`. Keep the comment, reworded to:
   `# Single-node hub: one replica, no HPA. The default HPA (max 5 @ 80% of a small request) scales out under CPU pressure and worsens overcommit; an HPA pinned at min = max = 1 fires KubeHpaMaxedOut forever.`
2. `components.ingressGateways[istio-ingressgateway].k8s`: remove `hpaSpec`, add `replicaCount: 1`. Comment:
   `# One replica, no HPA, on the single-node hub (see pilot note above).`
3. `values`: add
   ```yaml
   pilot:
     autoscaleEnabled: false
   gateways:
     istio-ingressgateway:
       autoscaleEnabled: false
   ```
   next to the existing `values.global` block. Keep `values.global` unchanged.
4. Change nothing else: resources, limits, the service type, the profile.

Out of scope: `scripts/etc/argocd/applicationsets/istio-ambient.yaml` (app clusters, `autoscaleMax: 2`, does not
fire).

## Tests (new `scripts/tests/lib/istio_operator_template.bats`; no cluster)

1. Render the template with `envsubst` (set `PILOT_K8S_CPU`, `PILOT_K8S_MEM`, `ING_K8S_CPU`, `ING_K8S_MEM`,
   `GLO_PROXY_CPU`, `GLO_PROXY_MEM`) and parse it with `yq`.
2. Assert: no `hpaSpec` anywhere; `.spec.components.pilot.k8s.replicaCount == 1`; the ingress gateway's
   `k8s.replicaCount == 1`; `.spec.values.pilot.autoscaleEnabled == false`;
   `.spec.values.gateways.istio-ingressgateway.autoscaleEnabled == false`.
3. Assert the resource requests/limits are unchanged (`500m` / `1Gi` for pilot, `500m` / `512Mi` for the gateway).

Mutations, each red, then `cp`-restored and `cmp`-proved: (a) put an `hpaSpec` back on pilot; (b) set
`values.pilot.autoscaleEnabled: true`.

## Rules

- `bats scripts/tests/lib/istio_operator_template.bats` is green; the rendered YAML parses with `yq`.
- No cluster, network or git commits. Leave the changes uncommitted. Do not touch `CHANGELOG.md` or memory-bank.
- Update this doc: Status FIXED (pending rollout), plus a short Resolution section.

## Resolution

The single-node hub now runs `istiod` and `istio-ingressgateway` with one replica and no HPA. Istio autoscaling is disabled for both components, preventing the permanently maxed-out HPA alerts while preserving the existing resources, service type, and profile.

## Rollout (operator)

There is no public entry point for `_provider_k3d_configure_istio`; apply the template the same way it does:

```bash
source scripts/etc/istio_var.sh
envsubst < scripts/etc/istio-operator.yaml.tmpl > "$TMPDIR/istio-operator.yaml"
istioctl --context k3d-k3d-cluster install -y -f "$TMPDIR/istio-operator.yaml"
```

Then confirm
`kubectl --context k3d-k3d-cluster -n istio-system get hpa` is empty. If `istioctl` leaves the old HPAs behind,
delete them: `kubectl -n istio-system delete hpa istiod istio-ingressgateway`. Both `KubeHpaMaxedOut` alerts
resolve within 15 minutes.

## Rollout done (2026-10-02)

Operator ran the rollout; Claude verified live: `istio-system` has no HPAs, istiod and istio-ingressgateway run 1/1, `KubeHpaMaxedOut` no longer firing.
