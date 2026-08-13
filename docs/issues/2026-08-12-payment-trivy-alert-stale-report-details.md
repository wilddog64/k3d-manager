# Bug: Payment Trivy alerts use stale reports and omit CVE details

**Filed:** 2026-08-12
**Source:** live investigation of repeated `TrivyCriticalVulnerabilityDetected` notifications

## Findings

The live `shopping-cart-payment` Deployment points at:

```text
ghcr.io/wilddog64/shopping-cart-payment:sha-76fbd486cf83ae4e8bc5f5275d6b4953998f7921
```

The ready pod is actually running:

```text
ghcr.io/wilddog64/shopping-cart-payment:latest
ghcr.io/wilddog64/shopping-cart-payment@sha256:022e737a20189dd857d7605562d58f2d4baf52d32b63c3f195ff73d3643229f8
```

Both existing payment vulnerability reports are owned by old ReplicaSets and scan a different
digest:

```text
replicaset-payment-service-67b4d694d6-payment-service sha-76fbd486cf83ae4e8bc5f5275d6b4953998f7921 sha256:4abd59357b6aaec354b3ef066723cc675ae8202e6cd923d50a3d4f0bdb5f6dc5
replicaset-payment-service-76d848d879-payment-service sha-76fbd486cf83ae4e8bc5f5275d6b4953998f7921 sha256:4abd59357b6aaec354b3ef066723cc675ae8202e6cd923d50a3d4f0bdb5f6dc5
```

The critical findings in that stale digest are:

| CVE | Package | Installed | Fixed | Score |
|---|---|---:|---|---:|
| CVE-2025-24813 | `org.apache.tomcat.embed:tomcat-embed-core` | 10.1.16 | 10.1.35 (or 11.0.3 / 9.0.99) | 9.8 |
| CVE-2026-41293 | `org.apache.tomcat.embed:tomcat-embed-core` | 10.1.16 | 10.1.55 (or 11.0.22 / 9.0.118) | 9.8 |
| CVE-2026-43512 | `org.apache.tomcat.embed:tomcat-embed-core` | 10.1.16 | 10.1.55 (or 11.0.22 / 9.0.118) | 6.5 |
| CVE-2026-43515 | `org.apache.tomcat.embed:tomcat-embed-core` | 10.1.16 | 10.1.55 (or 11.0.22 / 9.0.118) | 9.1 |
| CVE-2024-1597 | `org.postgresql:postgresql` | 42.6.0 | 42.6.1+ | 9.8 |
| CVE-2024-38821 | `org.springframework.security:spring-security-web` | 6.2.0 | 6.2.7 (or later fixed line) | 9.1 |
| CVE-2026-22732 | `org.springframework.security:spring-security-web` | 6.2.0 | 6.5.9 (or 7.0.4) | 9.1 |

## Root cause of incomplete Slack diagnostics

`prometheusrule.yaml` aggregates `trivy_vulnerability_inventory` by only
`cluster, namespace, image_repository`, so the alert no longer carries CVE, package,
installed-version, fixed-version, title, or digest labels. Its description contains only the
count, repository, and namespace. `bin/k3dm-webhook` then gathers an ArgoCD description (only when
an ArgoCD app label exists) and a cluster-wide non-running pod list; it does not query the Trivy
reports or inventory metric. Gemini therefore receives no vulnerability-specific evidence and
correctly reports that the notification is insufficient to diagnose.

## Recommended follow-up

1. Delete or expire vulnerability reports for retired ReplicaSets, and ensure Trivy scans the
   currently running image digest (`022e737a…`) before treating the finding as current.
2. Add a diagnostics path that looks up the matching inventory/report by repository and digest,
   and include a bounded CVE/package/version summary in the alert annotation or webhook prompt.
3. Upgrade the payment service dependencies/base image to remediate the seven findings if they are
   confirmed on the current digest; do not rebuild solely from this stale report.

## Evidence

The live report query returned repository `wilddog64/shopping-cart-payment`, tag
`sha-76fbd486cf83ae4e8bc5f5275d6b4953998f7921`, and digest
`sha256:4abd59357b6aaec354b3ef066723cc675ae8202e6cd923d50a3d4f0bdb5f6dc5`; the ready pod image ID
was `sha256:022e737a20189dd857d7605562d58f2d4baf52d32b63c3f195ff73d3643229f8`.
