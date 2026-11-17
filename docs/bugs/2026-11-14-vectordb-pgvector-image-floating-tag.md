# Bug: vectordb runs pgvector on the floating `pg17` tag, not a pinned version

**Status:** LIVE-VERIFIED — live E2 2026-11-17 (Claude, hub m5-air at deploy/hub 6fe58dcb: vectordb-0 runs 0.8.7-pg17@sha256:b513c485…, Running; ledger live_verified). Landed 74c8c7f3 on k3d-manager-v1.44.1, 2026-11-16 (Flash; Claude verified: new test red on pre-fix manifest, digest matches Docker Hub and the live pod)
**Fix commit:** 74c8c7f3
**Live evidence:** 2026-11-17 · run claude-tmux-m5-kubectl-get-vectordb-pod · env hub/k3d-k3d-cluster-deploy-hub-6fe58dcb · scenario vectordb-0-imageid-pinned-digest-after-platform-ops · commit 74c8c7f3 · proves E2
**Priority:** P3
**Branch:** k3d-manager-v1.44.1
**Triage:** patch → v1.44.1 (one-line pin; A08 rule) — operator grooming 2026-11-15 ("Accept as shown")
**Introduced by:** pre-existing
**Should have been caught by:** review
**Prior art:** exact-slug glob: none; `make find-similar-docs` unavailable (vector store needs the hub context, unreachable from the M4); parent `docs/bugs/2026-11-14-trivy-critical-hub-grafana-pgvector-nginx-local-path.md` (disposition 2)
**Approval:** operator, 2026-11-14 ("go with your suggestion", on the Trivy dispositions: pin pgvector, accept its CVE)

## Symptom

`scripts/etc/argocd/vectordb/statefulset.yaml:23` uses `image: pgvector/pgvector:pg17` with
`imagePullPolicy: IfNotPresent`. `pg17` is a floating tag (Security Rules A08: images pinned), so a pod rescheduled to
a node without the image pulls whatever `pg17` means that day, and a Trivy report describes a build no commit names.
The test `scripts/tests/plugins/argocd_vectordb.bats:13-14` asserts the floating tag itself
(`image:[[:space:]]*pgvector/pgvector:pg17([[:space:]]*)$`), so it locks the defect in.

## Evidence (Claude, 2026-11-14)

The running image's digest on the hub (VulnerabilityReport `vectordb/statefulset-vectordb-postgres`, read-only
`kubectl` on m5-air.local) is `sha256:b513c48566e4…`. Docker Hub (`/v2/repositories/pgvector/pgvector/tags`, read
2026-11-14) maps that digest to `0.8.7-pg17` (also `pg17`, `pg17-bookworm`, `0.8.7-pg17-bookworm`), full digest
`sha256:b513c48566e4777cd3370451400000c78eda6a08131d68f4c31d4a76f27bd8fd`. Pinning to it changes nothing that runs.

The one critical Trivy finding (CVE-2025-68121, Go stdlib 1.24.6 in the bundled `gosu`) is accepted as not reachable:
gosu only drops privileges at entrypoint and opens no TLS connection.

## Fix

1. `statefulset.yaml:23`: `image: pgvector/pgvector:0.8.7-pg17@sha256:b513c48566e4777cd3370451400000c78eda6a08131d68f4c31d4a76f27bd8fd`.
2. `argocd_vectordb.bats:13-14`: assert an exact `X.Y.Z-pg17@sha256:<64 hex>` reference and reject a bare `pg17`
   or `latest`.

## Files

- `scripts/etc/argocd/vectordb/statefulset.yaml`
- `scripts/tests/plugins/argocd_vectordb.bats`

## Contract readers

- `scripts/etc/argocd/vectordb/statefulset.yaml:23` — writer; the image reference changes (same digest).
- `scripts/tests/plugins/argocd_vectordb.bats:13-14` — reader; the asserted pattern changes.
- No other reader: `grep -rn pgvector scripts bin Makefile` (2026-11-14) finds only prose, dashboard titles and the
  embedding code, none of which reads the image tag.

## Acceptance

```yaml
must:
  - id: M1
    text: the vectordb StatefulSet image is pgvector/pgvector:0.8.7-pg17 pinned by the digest above
must_not:
  - id: N1
    text: the manifest uses a bare floating tag (pg17, latest) — red today
evidence:
  - id: E1
    proves: [M1, N1]
    kind: offline
    command: bats scripts/tests/plugins/argocd_vectordb.bats
    intent: The vectordb image can no longer change under us without a commit.
  - id: E2
    proves: [M1]
    kind: live
    command: after platform-ops sync, kubectl -n vectordb get pod -o jsonpath='{..imageID}' shows sha256:b513c48566e4777c…
    intent: The hub still runs the same database image after the pin.
interface: none
```

**Intent approved:** operator, 2026-11-14
