# Bug: VectorDB row/corpus chart shows fractional ticks and hides overlapping series

**Filed:** 2026-10-15
**Branch:** `k3d-manager-v1.45.2` (triage 2026-10-15, operator-approved placement)
**Status:** OPEN — presentation defect, no data corruption observed
**Priority:** P3 — Grafana readability/presentation only; document counts remain integers
**Severity:** low
**Origin:** operator screenshots 2026-10-15, VectorDB dashboard corpus trend near 04:47 and matching row/corpus series near 05:56

## Symptom

The VectorDB dashboard's **Rows vs corpus docs (last published)** time-series panel displays fractional Y-axis tick labels such as `2013.2`, `2013.4`, `2013.6`, `2013.8` between two actual integer counts. The underlying corpus series changes from **2013 to 2014**; fractional document counts are not meaningful.

The screenshot is consistent with Grafana automatically choosing a fractional tick interval for a tightly zoomed continuous numeric axis, **not** evidence that Prometheus publishes fractional corpus counts.

### Additional symptom — overlapping series appear missing

At approximately **05:56** on 2026-10-15, the panel rendered the yellow `corpus docs (last published)` line at **2019**, apparently without the green `rows (last published)` line. Hovering over the same chart position showed a green tooltip entry **`rows (last published) 2019`**, confirming the row series was available but visually obscured when the two values coincided. The corpus trace was also at 2019 in the screenshot. This is a **visibility / presentation defect**, not proof that rows were missing from pgvector or Prometheus; a matching count alone does not prove index content freshness.

## Source

`scripts/etc/argocd/platform-ops/grafana-dashboard-vectordb.yaml`, time-series panel id `1`, titled `Rows vs corpus docs (last published)`:
- query `k3dm_vectordb_rows`
- query `k3dm_vectordb_corpus_docs`
- current panel definition does not configure integer display semantics

## Investigation / fix criteria

1. Verify the raw Prometheus samples for both metric series are integers, and confirm this is a Grafana tick-formatting issue rather than an exporter/query transformation.
2. Configure the panel with zero-decimal count presentation, but **check for duplicated rounded Y-axis tick labels** when the viewport spans one count. If zero-decimal standard option doesn't generate sensible ticks, use a better supported display (e.g. integer current-count Stat with a companion trend) without concealing single-document changes.
3. Ensure both series use consistent count units and readable legends, preserving row-versus-corpus comparison and existing queries.
4. Do not force the Y-axis minimum to zero merely to eliminate fractions; this would hide changes from 2013 to 2014.
5. Add or update dashboard contract tests to guard the presentation configuration, and visually verify the narrow 2013→2014 case at representative Grafana widths.
6. Investigate the draw order/overlap of the two series when `rows == corpus docs`, so operators do not mistake a fully indexed corpus for a missing row metric. Evaluate legible solutions such as contrasting solid/dashed line style, separate point symbols, tooltip display of both values, or an adjacent explicit drift/current-count indicator; choose based on an actual Grafana visual check. Preserve visibility of both series **and** their divergence when drift becomes nonzero.
7. Add a dashboard contract/visual regression case for two identical series at 2019 over a prolonged period (and a transition from drift 1 to 0). Confirm both values can be discovered without hiding one another and any drift display is correctly computed.
8. Run dashboard tests and canonical test suite; do not modify indexer, document metrics, or production data.

## Acceptance criteria

- Corpus and vector-row counts display as discrete whole documents, not fractional documents.
- Axis/readout remains understandable without repeated misleading rounded labels.
- A 1-document change remains visible.
- Panel remains readable at other corpus sizes and across 24-hour and short zoom ranges.
- Both row and corpus series are distinguishable when they overlap at the same integer value; tooltip/readout makes both values clear.
- A drift of 1 and a return to drift 0 are both visually identifiable.
- Existing datasource and queries remain unchanged unless inspection demonstrates an actual query defect.

No deployment or runtime modification is part of filing this report.
