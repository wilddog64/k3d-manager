# Bug: ArgoCD marks ubuntu-k3s Applications Unknown because cluster DNS is stale

**Filed:** 2026-08-13
**Source:** live ArgoCD investigation

## Finding

Ten `ubuntu-k3s-*` Applications show `Sync: Unknown` with Healthy resources. Every Application
has the same ArgoCD `ComparisonError`:

```text
Failed to load live state: failed to get cluster info for "https://host.k3d.internal:6443" ...
Get "https://host.k3d.internal:6443/version?timeout=32s": dial tcp: lookup host.k3d.internal on 10.43.0.10:53: no such host
```

The hub cluster registration Secret is `cluster-ubuntu-k3s` and contains:

```text
name: ubuntu-k3s
server: https://host.k3d.internal:6443
```

The local kubeconfig's `ubuntu-k3s` cluster uses `https://34.222.252.197:6443`, confirming the
ArgoCD registration is using a stale/unresolvable OrbStack/k3d hostname. This is a shared
cluster-registration problem, not an application sync or manifest problem.

## Impact

ArgoCD cannot load target/live state or sync any Application destined for `ubuntu-k3s`. The Healthy
status is the last observed resource health and must not be treated as current sync verification.

## Recommended fix

Update the durable cluster registration path to use an address resolvable from the hub ArgoCD pods,
then refresh the `ubuntu-k3s` cluster and all ten Applications. Do not hand-edit individual
Application statuses. Validate DNS/API connectivity from inside an ArgoCD pod and require every
affected Application to return `Synced` or a documented resource-level failure.

## Live endpoint update attempt

The hub Secret `cluster-ubuntu-k3s` was updated to:

```text
https://34.222.252.197:6443
```

The ArgoCD application-controller was restarted to reload the Secret. The error changed from DNS
failure to:

```text
Get "https://34.222.252.197:6443/version?timeout=32s": net/http: TLS handshake timeout
```

The host-side kubeconfig also cannot reach the endpoint:

```text
Get "https://34.222.252.197:6443/api?timeout=8s": context deadline exceeded (Client.Timeout exceeded while awaiting headers)
```

Thus the registration hostname issue is corrected, but the ubuntu-k3s API endpoint itself is
currently unavailable or blocked by network/firewall state. The ten Applications remain Unknown
until the API path is restored.

Follow-up network checks confirmed the failure is below ArgoCD:

```text
34.222.252.197:6443 (sun-sr-https): Operation timed out
PING 34.222.252.197: 100% packet loss
kubectl ubuntu-k3s: context deadline exceeded while awaiting headers
```

The registration Secret remains on `https://34.222.252.197:6443`; restore/restart the k3s control
plane or its AWS security-group/network route before refreshing ArgoCD again.
