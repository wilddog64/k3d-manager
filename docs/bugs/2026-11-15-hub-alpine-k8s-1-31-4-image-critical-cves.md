# Bug: six hub CronJobs run `alpine/k8s:1.31.4` with 27 critical and 218 high CVEs

**Status:** OPEN — captured 2026-11-15 by Claude
**Priority:** P2
**Classified:** not run (queued for the next triage)
**Introduced by:** pre-existing (pin added in v1.23.0 `7253ece4` and v1.24.0 `fd281c85`)
**Should have been caught by:** none
**Introducing change reviewed:** unknown
**Prior art:** `make find-similar-docs` unavailable (vector store context missing on M4); exact-slug glob for `*alpine-k8s*` and `*rotator*`: none
**Waiting on:** operator decision — since 2026-11-16 (intent approval)
**Triage:** patch → v1.44.1 — operator 2026-11-15 ("go with your recommendation")

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

## Evidence (Claude drafter, 2026-11-16, M4 laptop, read-only)

- Registry: `docker buildx imagetools inspect alpine/k8s:<tag>` and Docker Hub `/v2/repositories/alpine/k8s/tags`
  (both reached, 2026-11-16). `1.31.4` = `sha256:9c4976d47656d78cf53a92b0203fc54ac45eae18a2b45001ac221c27da4c8036`
  (pushed 2024-12-15, Alpine 3.21.0, EOSL). `1.31.x` ends at `1.31.13` (2025-09-25), so no current 1.31 patch exists.
- Candidate `1.35.10` (pushed 2026-11-13), manifest-list digest
  `sha256:6b9b607247ab8f0d0bd2d6173a0b842b4d173c652475c9a715eec0c7ef27eac5` (imagetools and Hub agree).
  `1.34.13` is `sha256:4011c68d73de6803987509ad1ab9520124a27e31484e3f0e45f95a74ecac7a45`.
- Trivy 0.76.2 local scan (`trivy image --scanners vuln`, fresh DB, 2026-11-16): `1.31.4` 27 critical / 763 high;
  `1.35.10` 0 critical / 130 high; `1.34.13` 0 critical / 130 high. Base of both new tags is Alpine
  `3.25.0_alpha20260805` (an alpha base, upstream's choice; note it, do not fight it).
- Not proven: the hub's k3s server version. Repo records show clusters at v1.32.0 (k3d), v1.35.5 and v1.36.4 (Hostinger);
  the M5 hub version is not recorded. kubectl is supported within one minor of the server, so `1.35.10` is valid for a
  hub on 1.34, 1.35 or 1.36 and `1.34.13` for 1.33 to 1.35. E3 below must read it before the pin ships.

## Fix

Replace `docker.io/alpine/k8s:1.31.4` with
`docker.io/alpine/k8s:1.35.10@sha256:6b9b607247ab8f0d0bd2d6173a0b842b4d173c652475c9a715eec0c7ef27eac5` in:

1. `scripts/etc/argocd/platform-ops/app-cve-scan-cronjob.yaml:72` and `:212`.
2. `scripts/etc/argocd/platform-ops/argocd-credential-rotator.yaml:104`.
3. `scripts/etc/argocd/platform-ops/grafana-credential-rotator.yaml:101`.
4. `scripts/etc/argocd/platform-ops/keycloak-credential-rotator.yaml:65`.
5. `scripts/etc/ldap/vars.sh:99` (default of `LDAP_ROTATOR_IMAGE`, same reference).
6. Tests: `scripts/tests/plugins/argocd.bats:67` and `scripts/tests/plugins/app_cve_scan.bats:1489` assert the new full
   reference; `scripts/tests/plugins/ldap_password_rotator.bats:11` uses the new reference as its fixture value.
7. Add one test to `scripts/tests/plugins/app_cve_scan.bats`: for each of the five manifests plus `vars.sh`, every
   `alpine/k8s:` reference matches `alpine/k8s:[0-9]+\.[0-9]+\.[0-9]+@sha256:[0-9a-f]{64}` (use `run !` for the negatives).

If E3 shows the hub on 1.33 or older, the operator switches the tag and digest to `1.34.13` before dispatch; nothing else changes.

## Files

- `scripts/etc/argocd/platform-ops/app-cve-scan-cronjob.yaml`
- `scripts/etc/argocd/platform-ops/argocd-credential-rotator.yaml`
- `scripts/etc/argocd/platform-ops/grafana-credential-rotator.yaml`
- `scripts/etc/argocd/platform-ops/keycloak-credential-rotator.yaml`
- `scripts/etc/ldap/vars.sh`
- `scripts/tests/plugins/argocd.bats`
- `scripts/tests/plugins/app_cve_scan.bats`
- `scripts/tests/plugins/ldap_password_rotator.bats`

## Contract readers

Grep: `grep -rn "alpine/k8s" scripts bin Makefile deploy .github` (2026-11-16).

- Writers (image reference changes): the five manifests and `vars.sh:99` listed in Fix 1-5.
- `scripts/etc/ldap/ldap-password-rotator.yaml.tmpl:335` (`image: ${LDAP_ROTATOR_IMAGE}`) and `scripts/plugins/ldap.sh:930,945`
  (export and envsubst list) — readers of `LDAP_ROTATOR_IMAGE`; they pass the value through, no change. A digest-pinned
  reference contains `@` and `:`, neither a shell metacharacter in this envsubst use.
- Readers asserting the tag: `argocd.bats:67`, `app_cve_scan.bats:1489`, `ldap_password_rotator.bats:11` — change as in Fix 6.
- No tag reader: `scripts/tests/fixtures/webhook/alertmanager-analyze-batch.json:9,12,20` (repository name only) and the
  comment at `scripts/etc/signing/cluster-policy-verify-images.yaml.tmpl:55` (names the image, not the tag).
- `LDAP_ROTATOR_IMAGE` has no other reader in `scripts/`, `bin/` or `Makefile`.

## Acceptance

```yaml
must:
  - id: M1
    text: all six manifest and default references use docker.io/alpine/k8s:1.35.10 pinned by the digest above
  - id: M2
    text: every alpine/k8s reference in the manifests and vars.sh is a tag plus sha256 digest
must_not:
  - id: N1
    text: any alpine/k8s reference is 1.31.4 or a tag without a digest — red today (all six are 1.31.4, none has a digest)
  - id: N2
    text: the rotator or scanner manifests change anything other than the image line
evidence:
  - id: E1
    proves: [M1, M2, N1, N2]
    kind: offline
    command: bats scripts/tests/plugins/app_cve_scan.bats scripts/tests/plugins/argocd.bats scripts/tests/plugins/ldap_password_rotator.bats
    intent: The credential rotators and CVE scanner can only run an image we named by tag and digest.
  - id: E2
    proves: [M1]
    kind: live
    command: trivy image docker.io/alpine/k8s:1.35.10@sha256:6b9b6072... --severity CRITICAL (Claude or operator)
    intent: The new image really has no critical vulnerabilities, as the hub scanner will see it.
  - id: E3
    proves: [M1]
    kind: live
    command: kubectl version on the M5 hub (read-only), then a one-off job run from each CronJob after hub-promote and sync (operator)
    intent: The rotators and the scanner still work with the new kubectl against the hub's Kubernetes version.
interface: none
```

**Intent approved:** pending

## Worker definition of done

- The eight files in Files edited as in Fix; no other file touched; no digest other than the one above.
- E1 passes on the worktree, and the new test in Fix 7 is shown red on the pre-fix manifests.
- Commit and push to `origin/<branch>` verified with `git log origin/<branch>`; no cluster, make-install or registry write.
