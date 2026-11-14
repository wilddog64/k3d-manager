# Bug: four TrivyCriticalVulnerability alerts on hub platform-ops images

**Status:** OPEN — captured 2026-11-14 by Claude
**Priority:** P2
**Waiting on:** dispatch — since 2026-11-14 (operator approved the investigation; Luna, read-only, after Part B frees a slot)
**Introduced by:** unknown
**Should have been caught by:** unknown
**Prior art:** exact-slug glob: none; `make find-similar-docs` not run (vector store unreachable from the M4); no bug doc names these images with Trivy
**Approval:** none yet (capture only)

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
