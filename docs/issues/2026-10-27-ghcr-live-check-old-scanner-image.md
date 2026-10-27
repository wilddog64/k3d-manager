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
