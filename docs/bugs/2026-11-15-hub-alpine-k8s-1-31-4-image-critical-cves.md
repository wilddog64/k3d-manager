# Bug: six hub CronJobs run `alpine/k8s:1.31.4` with 27 critical and 218 high CVEs

**Status:** OPEN — captured 2026-11-15 by Claude
**Priority:** P2
**Classified:** not run (queued for the next triage)
**Introduced by:** pre-existing (pin added in v1.23.0 `7253ece4` and v1.24.0 `fd281c85`)
**Should have been caught by:** none
**Introducing change reviewed:** unknown
**Prior art:** `make find-similar-docs` unavailable (vector store context missing on M4); exact-slug glob for `*alpine-k8s*` and `*rotator*`: none
**Waiting on:** operator decision — since 2026-11-15

## Symptom

Trivy on the M5 hub, 2026-11-15, after the Grafana 12.4.15 promote: every workload on `docker.io/alpine/k8s:1.31.4`
reports 27 critical and 218 high vulnerabilities.

| Namespace | VulnerabilityReport |
|---|---|
| cicd | `cronjob-argocd-credential-rotator-rotate` |
| identity | `cronjob-ldap-password-rotator-rotator` |
| monitoring | `cronjob-grafana-credential-rotator-rotate` |
| platform-ops | `cronjob-app-cve-scan-app-cve-scanner` |
| platform-ops | `cronjob-cve-remediation-verify-verifier` |

## Where the pin lives

- `scripts/etc/argocd/platform-ops/app-cve-scan-cronjob.yaml:72` and `:212`
- `scripts/etc/argocd/platform-ops/argocd-credential-rotator.yaml:104`
- `scripts/etc/argocd/platform-ops/grafana-credential-rotator.yaml:101`
- `scripts/etc/argocd/platform-ops/keycloak-credential-rotator.yaml:65`
- `scripts/etc/ldap/vars.sh:99` (`LDAP_ROTATOR_IMAGE` default)
- Tests that assert the exact tag: `scripts/tests/plugins/app_cve_scan.bats:1489`, `scripts/tests/plugins/argocd.bats:67`,
  `scripts/tests/plugins/ldap_password_rotator.bats:11`

The rotators handle credentials (ArgoCD, Grafana, Keycloak, LDAP), so the image's CVEs sit next to secrets. They are short-lived
CronJob pods with no inbound network surface. Per the supply-chain rule, critical CVEs on a pin mean a patch release: bump to a
current `alpine/k8s` tag pinned by digest, after checking the kubectl version skew against the hub's k3s.
