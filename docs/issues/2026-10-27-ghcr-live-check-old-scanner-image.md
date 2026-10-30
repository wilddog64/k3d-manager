# GHCR live check4: scanner rollout prerequisite not met

## Operator command and actual output

```bash
kubectl --context k3d-k3d-cluster -n platform-ops get cronjob app-cve-scan -o jsonpath='{.spec.jobTemplate.spec.template.spec.containers[0].image}{"\n"}'
```

```text
Exit code: 0
aquasec/trivy:0.63.0
```

The operator repeated the same value in terminal output. The proposed scanner
main image is `docker.io/alpine/k8s:1.31.4`, with Trivy0.63.0 supplied by an init
container. This observation is the main container, so it confirms that the
new CronJob image has not been deployed. It does not test the fixed registry
authentication, candidate resolution, metric replacement or promotion paths.
Result: PARTIAL / deployment prerequisite unmet, not a failed new-image test.

## Recommended next single operator action

`make platform-ops` on the current release checkout. Verified Makefile target
calls `./scripts/k3d-manager deploy_argocd_platform_ops --confirm`; the function
applies the scanner CronJob manifest and recreates the scan-script ConfigMap
from the checked-out files, along with the existing platform-ops resources.
The coordinator did not run it or mutate the cluster. Review its completion
output before repeating the image read and proceeding to a scan. No blind
PAT rotation, Secret decoding or manual scan was requested.

Canonical GHCR bug remains VERIFIED offline; live verification is pending.
No new duplicate bug or plan was filed. This evidence-only update needs no
new BATS/ShellCheck run; existing implementation gate outputs remain in
`docs/issues/2026-10-27-six-bug-luna-batch.md`. Staged audit/lint and doc links
are checked by normal checkpoint hooks.

## Operator rollout completion excerpt

Operator ran the requested make platform-ops and supplied the following
completion excerpt (not the complete terminal transcript; no numeric exit
code was supplied):

```text
patched automatically.
configmap/grafana-dashboard-e2e configured
INFO: [argocd] Deploying Alertmanager delivery Grafana dashboard...
Warning: resource configmaps/grafana-dashboard-alertmanager-delivery is missing the kubectl.kubernetes.io/last-applied-configuration annotation which is required by kubectl apply. kubectl apply should only be used on resources created declaratively by either kubectl create --save-config or kubectl apply. The missing annotation will be patched automatically.
configmap/grafana-dashboard-alertmanager-delivery configured
INFO: [argocd] Deploying VectorDB Grafana dashboard...
Warning: resource configmaps/grafana-dashboard-vectordb is missing the kubectl.kubernetes.io/last-applied-configuration annotation which is required by kubectl apply. kubectl apply should only be used on resources created declaratively by either kubectl create --save-config or kubectl apply. The missing annotation will be patched automatically.
configmap/grafana-dashboard-vectordb configured
INFO: [argocd] Syncing secrets from Keychain (DR — see argocd_sync_webhook_token_secret / argocd_sync_app_rebuild_secret)...
WARN: [argocd] k3dm-webhook-token not found in Keychain (k3dm-webhook-token/k3dm) — run bin/k3dm-webhook-setup to create it, then re-run; skipping cluster Secret sync
INFO: [argocd] platform-ops-app-rebuild not in Keychain (platform-ops-app-rebuild/k3dm) — Secret already present in platform-ops; leaving as-is
INFO: [argocd] platform-ops-git-writer not in Keychain (platform-ops-git-writer/k3dm) — optional CVE git-writer PAT; skipping (store a dedicated fine-grained PAT scoped to wilddog64/k3d-manager contents:write ONLY — do NOT reuse a broad gh CLI token)
INFO: [argocd] ArgoCD monthly credential rotator applied
Success! Uploaded policy: argocd-rotationSuccess! Data written to: auth/kubernetes/role/argocd-rotationINFO: [argocd] platform-ops deployed — CVE scan: 1st+15th, expiry check: every 30m
INFO: [argocd] Secrets still to create manually (no durable local source):
INFO: [argocd]   kubectl create secret generic oci-kubeconfig --from-file=config=<path> -n platform-ops
INFO: [argocd]   kubectl patch secret platform-ops-notifications -n platform-ops --type=merge \
INFO: [argocd]     -p '{"data":{"slack-incoming-webhook-url":"<base64-url>"}}'
```

The command reached its deployment-complete message. The annotation warnings
state they were automatically patched. Existing app-rebuild cluster Secret
was retained; its actual token validity is untested. Missing local Keychain
items do not themselves establish that the existing registry Secret is bad.
No credentials were printed, decoded or rotated by the coordinator. Optional
Git-writer/OCI/notification setup was not undertaken as unrelated scope.

Next single operator check reads both main and init images from the hub
CronJob. Expected main docker.io/alpine/k8s:1.31.4, init aquasec/trivy:0.63.0.
Only after deployed config is confirmed should the selected GHCR live check
advance to runtime diagnostics. No scan was requested yet. GHCR remains
VERIFIED offline / live pending. This evidence-only update reruns no code
tests; normal doc links, staged lint/audit and commit hooks apply.

## Deployed image and script confirmed

Operator repeated the main-image read and received:

```text
docker.io/alpine/k8s:1.31.4
```

Coordinator supplemental read-only CronJob fields:

```text
main=docker.io/alpine/k8s:1.31.4
init=aquasec/trivy:0.63.0
uid=65534
fsGroup=65534
```

Compared ConfigMap argocd-cve-scan-script data app-cve-scan.sh against the
reviewed local script, without reading any Secret:

```text
deployed_script_sha256=c6762a033e4b6ad66a0d448debc47f4e26cde14a750fff1a0cd7825e850ea258
local_script_sha256=c6762a033e4b6ad66a0d448debc47f4e26cde14a750fff1a0cd7825e850ea258
matches=true
```

Deployment prerequisite PASSED. Runtime registry auth, candidate reason and
metric behavior remain untested. A manual `make app-cve-scan` is the existing
operator runtime gate (can promote clean candidates); it was not executed
by the coordinator or requested while doctor lookup recheck is pending.
No new PAT, scan or Secret decoding.

## Runtime scan readiness after doctor correction

Current corrected doctor check is authenticated healthy with no restart
needed (full result in webhook-doctor-health-timeout-restart-inference issue).
Read-only hub Job list filtered by app-cve-scan owner/name and status.active:

```json
{"active_app_cve_scan_jobs": []}
```

No active scanner was observed. Previously confirmed main/init images,
UID/fsGroup and ConfigMap script hash match the reviewed fix. Next single
operator step is `make app-cve-scan`. This starts a real scan and may promote
a clean candidate to the app cluster. The coordinator did not create a Job,
promote an image or rotate a credential. Await command/job result before
checking registry auth reasons/metrics and moving to remaining live items.
