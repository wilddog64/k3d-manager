# Bug: ask-docs misses an explicit priority count without the word bugs

**Status:** OPEN — reproduced locally; implementation not dispatched
**Priority:** P2
**Filed:** 2026-10-27
**Branch:** `k3d-manager-v1.43.9`
**Related:** `docs/plans/v1.45.1-bug-count-query-translation.md`; `docs/bugs/2026-10-10-ask-docs-bug-count-ignores-release-range.md`

`ask-docs how many P1 open for v1.43.5` returns unrelated documentation
excerpts and cannot answer the count. The deterministic matcher requires the
literal noun bugs; adding it selects the correct release/priority/state query.
This degrades the question interface with a working rephrasing workaround.

Evidence and exact reproduction:
[Investigation](../issues/2026-10-27-ask-docs-priority-count-misses-bug-noun.md).

The existing v1.45.1 translation plan's `_BUG_RE` gate would also reject this
question. A scoped fix should recognize a bounded priority-count question,
use the deterministic tally, and retain ordinary non-bug count fallback.
Required regressions: this exact wording selects P1/open/v1.43.5 and bypasses
retrieval/model; existing bug wording retains its result; unrelated pod counts
still fall through. No implementation or live deployment is included here.
