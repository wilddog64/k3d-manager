# Bug: Trivy scan jobs OOMKilled at 512Mi scanner limit

**Branch:** `k3d-manager-v1.14.0`
**Files:** `scripts/etc/helm/observability/trivy-operator-values.yaml`, `scripts/etc/helm/observability/trivy-operator-acg-values.yaml`

---

## Problem

Trivy Operator scan jobs on the hub cluster (`k3d-k3d-cluster`, `trivy-system` namespace) are
periodically **OOMKilled**. Observed 2026-07-12: pod `scan-vulnerabilityreport-56dd7499d-msq7x`,
scanner container terminated `exitCode: 137, reason: OOMKilled`. A secondary symptom appears in the
same pod's second container:

```
Failed to acquire cache or database lock ... cache may be in use by another process: timeout
... unable to initialize fs cache: cache may be in use by another process: timeout
```

Because scan jobs carry a 1h TTL (`operator.scanJobTTL: 1h`), the failed pod is garbage-collected
and the reconciler respawns the scan — so the workload's `VulnerabilityReport` is repeatedly
stale/missing until a scan happens to fit under the cap. Coverage is partial, not zero (51
`VulnerabilityReport` objects exist), so this is heavier scan targets exceeding the limit, not a
total scanner outage.

**Root cause:** the scan-job scanner container is capped at `trivy.resources.limits.memory: 512Mi`
(`trivy-operator-values.yaml:14`; mirrored in `trivy-operator-acg-values.yaml`). In `trivy.mode:
Standalone` every scan job initializes the Trivy DB in-process and analyzes the target image within
that 512Mi ceiling; heavier targets exceed it and are OOMKilled. The cache-lock timeout is a
secondary effect of concurrent scans contending on the shared DB cache while one scan is mid-init.

This is the same memory-pressure class as the Grafana OOM already fixed in this milestone
(`1af49f44`, 192Mi→512Mi) — coincidentally the trivy scanner ceiling is also 512Mi.

---

## Reproduction

```bash
# Watch for OOMKilled scan pods on the hub
kubectl --context k3d-k3d-cluster get pods -n trivy-system | grep OOMKilled
# Inspect the scanner container's terminated state
kubectl --context k3d-k3d-cluster get pod <scan-pod> -n trivy-system \
  -o jsonpath='{range .status.containerStatuses[*]}{.name}={.state.terminated.reason} exit={.state.terminated.exitCode}{"\n"}{end}'
# Confirm the live cap
kubectl --context k3d-k3d-cluster get cm trivy-operator-trivy-config -n trivy-system \
  -o jsonpath='{.data.trivy\.resources\.limits\.memory}'   # -> 512Mi
```

Expected: scan jobs complete and write a `VulnerabilityReport`.
Actual: heavier scans terminate `OOMKilled` (exit 137); reports go stale.

**Safety confirmed:** hub node memory is well within headroom (`server-0` ~24% of ~12Gi; agents
12–20%), and scan jobs are ephemeral, so raising the per-scan limit to 1Gi cannot pressure the node.

---

## Fix

Raise the scanner memory limit 512Mi → 1Gi and the request 64Mi → 256Mi (a realistic floor for
Standalone-mode DB init, so the scheduler reserves enough and fewer scans race the cache). Apply the
**same** change to both the hub values file and the ACG/app-cluster values file so the two clusters
stay in parity.

### Change 1 — `scripts/etc/helm/observability/trivy-operator-values.yaml`

**Exact old block (lines 9–15):**

```yaml
  resources:
    requests:
      memory: 64Mi
      cpu: 50m
    limits:
      memory: 512Mi
      cpu: 500m
```

**Exact new block:**

```yaml
  resources:
    requests:
      memory: 256Mi
      cpu: 50m
    limits:
      memory: 1Gi
      cpu: 500m
```

### Change 2 — `scripts/etc/helm/observability/trivy-operator-acg-values.yaml`

**Exact old block (lines 9–15):**

```yaml
  resources:
    requests:
      memory: 64Mi
      cpu: 50m
    limits:
      memory: 512Mi
      cpu: 500m
```

**Exact new block:**

```yaml
  resources:
    requests:
      memory: 256Mi
      cpu: 50m
    limits:
      memory: 1Gi
      cpu: 500m
```

> Note: these `trivy.resources.*` values map to the `trivy-operator-trivy-config` ConfigMap keys
> `trivy.resources.limits.memory` / `trivy.resources.requests.memory`, which govern the scan-job
> scanner container — NOT the operator Deployment's own `operator.resources` block (lines 21–27),
> which must stay unchanged.

---

## Files Changed

| File | Change |
|------|--------|
| `scripts/etc/helm/observability/trivy-operator-values.yaml` | scanner mem limit 512Mi→1Gi, request 64Mi→256Mi |
| `scripts/etc/helm/observability/trivy-operator-acg-values.yaml` | same, for the ACG/app-cluster stack |

---

## Rules

- Do NOT touch the `operator.resources` block (lines 21–27) in either file — only `trivy.resources`.
- Do NOT change `trivy.mode`, `image.tag` (`0.31.2`), `serviceMonitor`, `ignoreUnfixed`, or `severity`.
- No other files touched. These are ArgoCD-managed Helm values — Claude applies/syncs, not the agent.

---

## Definition of Done

- [ ] Both values files show `memory: 1Gi` under `trivy.resources.limits` and `memory: 256Mi` under `trivy.resources.requests`.
- [ ] `operator.resources` unchanged in both files.
- [ ] Committed and pushed to `k3d-manager-v1.14.0`.
- [ ] memory-bank updated with commit SHA and task status.

**Commit message (exact):**
```
fix(observability): raise trivy scan-job memory limit to stop OOMKills
```

---

## What NOT to Do

- Do NOT create a PR.
- Do NOT skip pre-commit hooks (`--no-verify`).
- Do NOT modify any file other than the two listed targets.
- Do NOT commit to `main` — work on `k3d-manager-v1.14.0`.
- Do NOT apply/sync the ArgoCD Helm release — Claude does the live apply + verifies the new limit
  in `trivy-operator-trivy-config` and watches for OOMKills to stop.

---

## Deferred (do NOT do in this bugfix)

- Migrating `trivy.mode` from `Standalone` to `ClientServer` with a central `trivy-server`
  Deployment/Service. That eliminates per-scan in-process DB init memory **and** the shared
  cache-lock contention entirely, and would let the per-scan limit drop again — but it is a
  structural change (new workload, chart wiring, DB-refresh strategy), not a memory bump. File as a
  separate follow-up if the OOMKills persist after the limit raise.
