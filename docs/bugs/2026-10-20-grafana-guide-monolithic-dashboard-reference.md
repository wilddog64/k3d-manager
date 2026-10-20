# Bug: Grafana dashboards guide is monolithic and its dashboard inventory is stale

**Filed:** 2026-10-20 (operator report)
**Branch:** k3d-manager-v1.43.5
**Status:** OPEN — documentation refactor pending
**Priority:** P3 — documentation usability and maintenance; no runtime impact
**Severity:** low
**Approval:** operator requested bug filing before any implementation on 2026-10-20
**Component:** `docs/guides/grafana-dashboards.md`, dashboard documentation navigation
**Related:** `README.md` (Grafana Dashboards link); `scripts/etc/argocd/platform-ops/grafana-dashboard-*.yaml`; `scripts/etc/grafana/dashboards/*.yaml`

## Files

- `docs/guides/grafana-dashboards.md` — retain as the canonical landing page/index.
- `docs/guides/grafana-dashboards/` — proposed location for per-dashboard pages (check naming convention before implementation).
- `README.md` — keep the existing Grafana Dashboards link pointing to the landing page.

## Symptom / evidence

The operator reports that [Grafana Dashboards](../guides/grafana-dashboards.md) contains too much material in one page and asks for a main guide linking to individual dashboard guides.

Inspected on `k3d-manager-v1.43.5` on 2026-10-20: the document has approximately **673 lines / 46,932 characters**. It combines a dashboard inventory, hub-vs-ACG guidance, producer-chain explanation, **13 long dashboard reference subsections**, generic `No data` triage, maintenance instructions, and further reading. One of the longer sections, `k3dm Bug Tracking`, alone occupies approximately 136 lines.

The heading still says **“The seven dashboards”**, while the inventory table contains **16 entries** including dashboards and public-endpoint probes. The text immediately below says **“All eight”**. Both counts are stale/misleading. Not all listed items are necessarily Grafana dashboards (`probe_*` is a probe/metric entry), so enumerate the actual dashboard set from source/configuration rather than changing the heading to an unverified count.

This is a *documentation structure/content drift defect*, not a Grafana availability or metrics bug.

## Root cause / investigation

The guide accumulated panel-by-panel reference material as the number of deployed dashboards expanded, without separating an overview/navigation page from individual references. Some older hardcoded inventory counts were not updated. Confirm the current dashboard inventory and deployment locations before restructuring.

## Expected behavior / proposed design

1. Keep `docs/guides/grafana-dashboards.md` as a concise **entry point and dashboard index**. Retain the purpose, a compact inventory including dashboard name/UID/location/source/deployer, hub-vs-ACG distinction, and links to individual pages.
2. Move the existing dashboard-specific reference subsections into separate Markdown files under a consistent folder such as `docs/guides/grafana-dashboards/`; use stable, descriptive names (for example `k3dm-bugs.md`, `k3dm-pr-checks.md`, `cve-autopatch.md`). Preserve panel details, metrics/producer provenance, operational procedures, caveats, and related references.
3. Keep shared topics (producer chain, `No data` cause triage, adding/changing dashboards) discoverable from the index, either as succinct index content or appropriately named linked shared guides. Avoid unnecessary duplication.
4. Reconcile the inventory with the **actual current source definitions** and cluster placement. Resolve stale “seven”/“eight” labels and distinguish dashboards from Prometheus probes.
5. Preserve existing README and incoming links to `docs/guides/grafana-dashboards.md`; ensure links and relative paths still work after moving content. Update any internal cross-links/anchors that depended on relocated headings.
6. This change concerns documentation only. Do not modify Grafana ConfigMaps, PromQL, collection pipelines, or deployment logic.

## Acceptance

```yaml
must:
  - id: M1
    text: docs/guides/grafana-dashboards.md remains the canonical, concise dashboard landing page with functioning links to the per-dashboard documentation.
  - id: M2
    text: Every dashboard described in the original detailed reference has an accessible standalone page, preserving its panel, metrics, producer, operational, and troubleshooting information.
  - id: M3
    text: Shared producer-chain, hub-versus-ACG, No data triage, maintenance, and related-guidance information remains navigable and is not silently lost.
  - id: M4
    text: The inventory reflects actual deployed dashboard definitions, UIDs, source files and target clusters, without obsolete seven/eight counts or misclassifying probes as dashboards.
  - id: M5
    text: README and other links to the original grafana-dashboards.md path keep working, and all newly introduced relative links and relocated references resolve.
must_not:
  - id: N1
    text: Do not alter Grafana runtime manifests, queries, dashboards, exporter configuration, cluster resources, or live infrastructure.
  - id: N2
    text: Do not drop unique technical explanations, command examples, verification guidance, or provenance while splitting the guide.
  - id: N3
    text: Do not leave the index with dead links, circular navigation, or links to a renamed path that breaks existing README navigation.
evidence:
  - id: E1
    kind: offline
    proves: [M1, M2, M3, M4, M5, N1, N2, N3]
    text: Compare original and split guide section coverage; validate all relative Markdown links and dashboard inventory against definitions, show a documentation-only diff, and report missing/duplicate sections.
  - id: E2
    kind: live
    proves: [M1, M2, M3, M5]
    text: Inspect GitHub rendering of the index and several standalone dashboard guides on the release branch, including return navigation; record URL, commit SHA, and timestamp.
interface:
  - docs/guides/grafana-dashboards.md
  - docs/guides/grafana-dashboards/*.md
  - README.md
```

## Definition of Done

- [ ] Confirm complete inventory and mapping from existing dashboard-reference headings to standalone destinations.
- [ ] Keep index short, with a stable URL and meaningful navigation to each standalone page.
- [ ] Preserve all existing reference and triage content with appropriate cross-links.
- [ ] Prove link resolution and technical content retention offline.
- [ ] Inspect rendered GitHub pages and record live verification evidence.
- [ ] Update bug status only after validation and record the implementation commit.

## What NOT to Do

- Do not conflate documentation reorganization with implementing dashboard behavior.
- Do not create a PR merely for filing this bug; push to `k3d-manager-v1.43.5`, not `main`.
