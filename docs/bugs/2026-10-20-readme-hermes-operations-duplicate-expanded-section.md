# Bug: README duplicates Hermes operations guide as expanded top-level section

**Filed:** 2026-10-20 (operator screenshot, GitHub README)
**Branch:** k3d-manager-v1.43.5
**Status:** OPEN — documentation cleanup not yet implemented
**Priority:** P3 — readability and information architecture; no functional impact
**Severity:** low
**Approval:** operator requested bug filing 2026-10-20; implementation not authorized
**Component:** `README.md` (Guides index and separate Hermes operations section)
**Related:** `docs/guides/hermes.md`, `docs/architecture/hermes-phase1-monitoring-scope.md`, `docs/architecture/hermes-phase2-repair-scope.md`

## Files

- `README.md`
- `docs/guides/hermes.md` (preserve or relocate details here only if needed)

## Symptom / evidence

The operator screenshot from 2026-10-20 shows the README **Guides** list followed immediately by another large **Hermes operations** section. The guide index already contains:

```markdown
- **[Hermes operations](docs/guides/hermes.md)** — Off-hub monitoring, multi-signal correlation, Slack reporting, and approval-gated repairs
```

Yet `README.md` also embeds a `### Hermes operations` heading, introductory paragraph, Mermaid flowchart, and three links (Hermes guide, Phase 1 monitoring scope, Phase 2 repair scope). This makes the guide unusually prominent, duplicates navigation, and lengthens the README rather than keeping detailed operations documentation behind the Guides index.

This is a documentation hierarchy / presentation bug, **not** a broken or absent Hermes link.

## Expected behavior / fix direction

- Keep the existing **Hermes operations** link in the **Guides** index, pointing to `docs/guides/hermes.md`.
- Remove the redundant expanded `### Hermes operations` block from `README.md` (intro, Mermaid diagram, and duplicate links), with the smallest scoped documentation change.
- Preserve the operating model, diagram, and Phase 1 / Phase 2 scope navigation in the canonical Hermes guide or linked architecture documents; if any information exists only in the README, migrate it before deleting the block.
- Keep the Guides list readable and ensure README continues naturally into **Providers** without a duplicate Hermes exposition.

## Root cause / investigation

The README grew a second Hermes-specific explanatory section even though Hermes already has a canonical `docs/guides/hermes.md` linked from the Guides index. Confirm any README-only material before consolidation; do not assume the diagram has already been duplicated in the guide.

## Acceptance

```yaml
must:
  - id: M1
    text: The README Guides index includes one working Hermes operations link to docs/guides/hermes.md.
  - id: M2
    text: The redundant expanded Hermes operations section is removed from README; Providers follows the Guides index normally.
  - id: M3
    text: Hermes explanation, operational flow/diagram and Phase 1/Phase 2 scope links remain available in the canonical guide or its linked documentation.
must_not:
  - id: N1
    text: Do not remove the Hermes guide or leave its entry broken.
  - id: N2
    text: Do not change Hermes executable behavior, sensor logic, repair policy or approval boundaries.
  - id: N3
    text: Do not discard unique operational instructions or diagrams while removing README duplication.
evidence:
  - id: E1
    kind: offline
    proves: [M1, M2, M3, N1, N2, N3]
    text: Inspect README and guide after the change, validate links and confirm retained diagram/scope content; show git diff contains documentation changes only.
  - id: E2
    kind: live
    proves: [M1, M2]
    text: Render README in GitHub on the release branch and confirm a compact Guides list followed by Providers, without a second Hermes operations block.
interface:
  - README.md
  - docs/guides/hermes.md
```

## Definition of Done

- [ ] Move any unique Hermes README-only information to the canonical guide.
- [ ] Remove duplicate expanded Hermes section while retaining the Guides link.
- [ ] Validate all changed Markdown links and preserved scope references.
- [ ] Inspect rendered GitHub README and record verification evidence.

## What NOT to Do

- Do not alter any Hermes runtime, cluster infrastructure, Slack approvals, or repair controls.
- Do not mark this bug VERIFIED or LIVE-VERIFIED before actual documentation/rendering verification.
- Do not commit directly to main; implement on a release branch and use the existing release PR process.
