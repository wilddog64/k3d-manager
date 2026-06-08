# Bug: kube-prometheus-stack-operator Stuck in ContainerCreating — Admission Secret Missing

**Branch:** `k3d-manager-v1.6.4`
**Date:** 2026-06-07
**Files:** Helm values for `acg-kube-prometheus-stack`

---

## Symptom

After a cluster rebuild, `acg-kube-prometheus-stack-operator` is stuck in `ContainerCreating`
indefinitely, blocking Grafana from loading:

```
monitoring   acg-kube-prometheus-stack-operator-847bc9569c-sz6r6   0/1   ContainerCreating
```

`kubectl describe pod` shows:

```
Warning  FailedMount  kubelet  MountVolume.SetUp failed for volume "tls-secret" :
  secret "acg-kube-prometheus-stack-admission" not found
```

---

## Root Cause

The `kube-prometheus-stack` chart uses Helm `pre-install`/`pre-upgrade` hook jobs
(`admission-create` and `admission-patch`) to generate a TLS certificate and store it in
`acg-kube-prometheus-stack-admission`. ArgoCD does not run Helm hooks during sync — it only
applies rendered manifests. On every cluster rebuild, the operator starts but the secret is
never (re)created, so the operator pod hangs in `ContainerCreating` forever.

The `ValidatingWebhookConfiguration` and `MutatingWebhookConfiguration` for
`acg-kube-prometheus-stack-admission` are present (ArgoCD renders and applies those), but
the TLS backing secret is absent.

---

## Fix Options

### Option A — Disable admission webhooks in Helm values (recommended for dev clusters)

Add to the `kube-prometheus-stack` Helm values:

```yaml
admissionWebhooks:
  enabled: false
```

This removes the dependency on the admission secret entirely. The admission webhook
validates `PrometheusRule` CRDs — acceptable to skip in a dev cluster.

### Option B — Manually recreate the admission secret after every rebuild

```bash
kubectl create secret generic acg-kube-prometheus-stack-admission \
  -n monitoring \
  --from-literal=tls.crt="$(openssl req -x509 -newkey rsa:2048 -keyout /dev/fd/3 -out /dev/stdout -days 365 -nodes -subj '/CN=acg-kube-prometheus-stack-operator.monitoring.svc' 3>&1 2>/dev/null)" \
  --from-literal=tls.key="$(openssl genrsa 2048 2>/dev/null)"
```

This is fragile — the cert format must match what the operator expects.

### Option C — Add a post-sync ArgoCD hook to re-run the admission-create job

Add a `Job` manifest with `argocd.argoproj.io/hook: PostSync` annotation that runs
`k8s.gcr.io/ingress-nginx/kube-webhook-certgen` (the same image Helm uses) to regenerate
the secret. This mirrors what the Helm hook does, wired to ArgoCD's sync lifecycle.

---

## Immediate Workaround

Delete the webhook configs so the operator pod starts without the TLS mount failing:

```bash
kubectl delete validatingwebhookconfiguration acg-kube-prometheus-stack-admission --context ubuntu-k3s
kubectl delete mutatingwebhookconfiguration acg-kube-prometheus-stack-admission --context ubuntu-k3s
```

Then delete the stuck pod so it reschedules without the volume mount:

```bash
kubectl delete pod -n monitoring -l app=kube-prometheus-stack-operator --context ubuntu-k3s
```

After the operator comes up, Grafana should load.

---

## Recurrence

This bug affects every `acg-up` run that provisions a fresh cluster, because the Helm hook
jobs are not re-run by ArgoCD. Option A (disable admission webhooks) is the permanent fix.
