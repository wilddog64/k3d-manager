# Bug: Research required: clarify docs/issues versus docs/bugs lifecycle and migration

**Status:** OPEN — RESEARCH REQUIRED; documentation taxonomy defect/ambiguity, solution not decided
**Branch:** `k3d-manager-v1.50.1` (triage 2026-10-15, operator-approved placement)
**Priority:** P2 (tracking and retrieval reliability)
**Filed:** 2026-10-13, operator request
**Release:** v1.50.1 (triage 2026-10-15, operator-approved placement)
**Approval:** explicit operator request to file research bug; no bulk rename or migration authorized
**Component:** docs taxonomy, bug dashboard, doc indexing/RAG, references, decision tracking

## Problem

Historically `docs/issues/` was used to document bugs and investigations. The project later introduced `docs/bugs/` as a separate canonical bug ledger, but the two directories coexist with unclear boundaries. Recent investigation into repeated CVE `applied` records was initially filed in `docs/issues/` and then duplicated as a research-required bug in `docs/bugs/` solely so it would show up in Grafana. Its original issue was marked superseded. This demonstrates a taxonomy/workflow problem rather than evidence that all investigations should be bugs.

The current bug tracking design intentionally scans only top-level `docs/bugs/*.md` and excludes `docs/issues/`. Document indexing can include both paths, so ambiguity may affect retrieval, counts, deduplication and where agents file future work.

## Research questions

1. **Historical contract:** When and why was `docs/bugs/` created? What did `docs/issues/` originally mean and how is it now used (confirmed defects, research investigations, incidents, action items, triage, proposals)? Review git history, roadmap, filing conventions and representative documents; do not assume names alone establish semantics.
2. **Inventory:** Count active/archived records by folder and status; sample or classify `docs/issues/` to establish how many are true bugs, research-only, closed historical notes, or duplicates. Distinguish counts from verified content classification.
3. **Consumers:** Enumerate all path-dependent workflows: bug-tally/metrics and Grafana, Slack /ask-docs and find-similar-docs indexing, decision digest, specs/approvals, agent dispatch, file-bugs actions, tests, document links and archive policies. Record where moving a file would break a consumer or historical reference.
4. **Canonical policy options:** Compare (A) keep distinct `issues` for research and `bugs` for proven/research-pending defects with explicit statuses; (B) unify into a single typed work-item ledger; (C) keep `docs/issues/` as archived legacy and redirect new filings; (D) another simpler option. Compare maintenance, dashboard accuracy and existing backward compatibility.
5. **Lifecycle clarity:** Specify required states for `research_required`, `confirmed_bug`, `expected_behavior`, `enhancement`, `superseded`, `closed` without pretending an unverified issue is a confirmed bug. Define promotion and linking rules; avoid duplicate open counts.
6. **Migration strategy:** If relocation is recommended, propose phased migration with `git mv`, link/reference updates, aliases/redirects where needed, regression tests, Git history retention, indexing rebuild impacts and rollback. No destructive mass rename just to clean up directory names.
7. **Observability:** Decide whether investigations deserve their own Grafana lifecycle view or a unified filtered work-item dashboard; do not distort confirmed bug totals to gain visibility for research.

## Deliverable / definition of done

- [ ] Produce an evidence-backed report in this same bug file: origin/history, directory inventory, live consumers, examples of ambiguity and tradeoffs.
- [ ] Recommend one canonical taxonomy and an unambiguous filing decision tree for agents and operator.
- [ ] Specify required data fields, transitions, indexing behavior and Grafana semantics, including what to do with existing docs.
- [ ] Identify whether this warrants a separate implementation spec and which future release can accommodate it; don't consume an already-full milestone without checking roadmap.
- [ ] Add acceptance tests for discovery/visibility/duplicate counting to that future spec if changes are needed.
- [ ] Document operator approval before any migration or change to producer, dashboard or runtime.

## Safety / scope

Research only in v1.43.2. Do not move, delete, archive, automatically classify or modify any existing `docs/issues/` / `docs/bugs/` records; do not change dashboards, indexing or workflows. Preserve historical auditability and git links. The outcome may be a documented policy with no code changes.
