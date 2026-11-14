# Bug: four TrivyCriticalVulnerability alerts on hub platform-ops images

**Status:** OPEN — captured 2026-11-14 by Claude
**Priority:** P2
**Waiting on:** operator decision — since 2026-11-14 (Grafana target: no 11.x clears the criticals; 12.4.15 does)
**Introduced by:** unknown
**Should have been caught by:** unknown
**Prior art:** exact-slug glob: none; `make find-similar-docs` not run (vector store unreachable from the M4); no bug doc names these images with Trivy
**Approval:** operator, 2026-11-14 ("go with your suggestion" on the four dispositions)

## Symptom

Grafana alert list (operator screenshot, 2026-11-14), cluster hub, namespace platform-ops, severity warning:

| Image | Active since (PST) |
|---|---|
| grafana/grafana | 2026-11-14 06:24:54 |
| nginxinc/nginx-unprivileged | 2026-11-13 17:31:54 |
| pgvector/pgvector | 2026-11-13 16:30:54 |
| rancher/local-path-provisioner | 2026-11-13 15:28:54 |

## Needed

For each: the CVE ids and package from the VulnerabilityReport, the pinned tag and where it is pinned, whether a fixed upstream tag exists, and whether it is reachable in our use (see memory `reference_trivy_critical_upstream_image_noise`). Then: patch release, workaround, or documented accept.

## Investigation (Claude, 2026-11-14 ~21:50Z, read-only `kubectl get vulnerabilityreport` on m5-air.local, context k3d-k3d-cluster)

Done by Claude instead of a Luna dispatch: the codex sandbox cannot reach the hub cluster. Hub nodes run arm64
(`rancher/k3s:v1.32.0-k3s1`, `scripts/etc/cluster.yaml.tmpl:7`).

| Image (namespace) | Where pinned | Critical findings (package installed -> fixed) | Reachable in our use? |
|---|---|---|---|
| rancher/local-path-provisioner v0.0.30 (kube-system), 4 crit / 21 high | bundled with k3s v1.32.0 (`cluster.yaml.tmpl:7`) | CVE-2026-31789 libcrypto3/libssl3 3.3.2-r0 -> 3.3.7-r0; CVE-2025-62878 provisioner path traversal via parameters v0.0.30 -> 0.0.34; CVE-2025-68121 Go stdlib crypto/tls 1.23.1 -> 1.24.13 | OpenSSL bug is 32-bit only: no (arm64). Path traversal needs someone who can set StorageClass/PVC parameters, i.e. a cluster admin on a one-operator hub: low. TLS: provisioner talks only to the API server |
| grafana/grafana 11.4.0 (monitoring), 9 crit / 57 high | default of chart kube-prometheus-stack 67.9.0 (`applicationsets/observability.yaml:18`) | CVE-2026-31789 (as above); GHSA-r277-6w6q-xmqw kin-openapi 0.125.0 -> 0.144.0 (auth fail-open); CVE-2026-33815/33816 pgx 5.5.5 -> 5.9.0 (memory safety); CVE-2026-33186 grpc 1.66.0 -> 1.79.3 (authz bypass); CVE-2025-68121 stdlib x3 | The most exposed: Grafana serves HTTP to the operator and holds datasource credentials. grpc authz and kin-openapi fail-open need code paths not yet traced; pgx is the Postgres datasource driver (vectordb). Treat as reachable until shown otherwise |
| nginxinc/nginx-unprivileged 1.31-alpine (monitoring, loki-gateway), 1 crit / 3 high | default of chart loki 18.2.0 (`observability.yaml:36`); floating minor tag, `imagePullPolicy: IfNotPresent` | CVE-2026-111497 brotli-libs 1.2.0-r1 -> 1.2.1-r0 (decoder out-of-bounds write) | Loki gateway proxies plain push/query traffic inside the cluster; stock nginx does not decode Brotli bodies: not reachable as configured |
| pgvector/pgvector pg17 (vectordb), 1 crit / 6 high | `scripts/etc/argocd/vectordb/statefulset.yaml:23`; floating major tag (breaks the Security Rules A08 pin rule) | CVE-2025-68121 Go stdlib 1.24.6 -> 1.24.13 (in the bundled `gosu` binary) | gosu only drops privileges at entrypoint and does no TLS: not reachable |

Proposed disposition (operator decides; CLAUDE.md: critical/high CVE -> patch release; reachability from memory
`reference_trivy_critical_upstream_image_noise`):

1. **Grafana: fix in a patch release.** Override `grafana.image.tag` in `kube-prometheus-stack-values.yaml:80` to the
   newest 11.x patch whose Go deps clear these findings (or bump the chart). The fixed tag must be proven before
   dispatch (Trivy scan of the candidate tag, or upstream release notes at that tag).
2. **pgvector: pin, accept the CVE.** Pin to an exact pgvector tag plus digest (A08 hygiene, P3), document the gosu
   finding as not reachable.
3. **nginx (loki-gateway): accept, documented.** A fixed brotli-libs exists in newer `1.31-alpine` builds; pin a dated
   tag at the next loki chart bump.
4. **local-path-provisioner: accept until the next k3s bump**, documented; the path-traversal fix (0.0.34) arrives with
   a newer k3s image, which is release-sized work, not a patch.

## Decision and follow-up (2026-11-14)

Operator approved all four dispositions. Applied:

- **pgvector:** pin filed as P3 `docs/bugs/2026-11-14-vectordb-pgvector-image-floating-tag.md` (running digest = `0.8.7-pg17`; the
  existing bats test asserts the floating tag and changes with it). CVE accepted, not reachable.
- **nginx-unprivileged (loki-gateway):** accepted, not reachable; pin a dated tag at the next loki chart bump.
- **local-path-provisioner:** accepted until the next k3s image bump.
- **Grafana:** fixed-tag proof (Claude, local `trivy` 0.76.2, `--platform linux/arm64 --severity CRITICAL`, 2026-11-14):

  | Tag | Criticals | High |
  |---|---|---|
  | 11.4.0 (running) | 9 | — |
  | 11.6.16 (newest 11.x) | 2: GHSA-r277-6w6q-xmqw kin-openapi 0.132.0 (auth fail-open), CVE-2026-111497 brotli-libs | — |
  | 12.4.15 (newest 12.x) | 0 | 2 |
  | 13.3.1 (newest) | 0 | 20 |

  No 11.x tag clears the criticals, so the approved "fixed 11.x" target does not exist. Our dashboards use no Angular
  panel types (`graph`, `singlestat`, `table-old`, piechart/worldmap plugins: none found in `scripts/etc` or `docs`), and
  `kube-prometheus-stack-values.yaml` sets no Grafana image today. Pending operator choice: 12.4.15 (major bump) or
  11.6.16 (accept the kin-openapi finding).
