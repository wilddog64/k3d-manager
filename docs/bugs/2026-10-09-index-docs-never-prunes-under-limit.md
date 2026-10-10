# Bug: the scheduled index never prunes, so renamed and deleted docs stay in the vector store

**Filed:** 2026-10-09
**Branch:** `k3d-manager-v1.43.0`
**Status:** OPEN
**Priority:** P2 — retrieval keeps returning documents that no longer exist; the workaround is a manual unlimited `make index-docs`
**Severity:** medium
**Origin:** operator, 2026-10-09: the vectordb dashboard showed drift docs at −2 and `VectorDBIndexDrift` firing.

## Symptom

`k3dm_vectordb_drift_docs` (corpus docs − rows) has been −2 since about 15:40 on 2026-10-09, and
`VectorDBIndexDrift` is firing. The store has two rows that are not in the corpus:

```
in index, not in corpus: ['docs/plans/v1.43.0-test-metrics-log-retention.md',
                          'docs/plans/v1.45.0-worktree-isolated-codex-dispatch.md']
```

These are the **old** paths of the two plans swapped between v1.43.0 and v1.45.0 that day. The new
paths were indexed; the old rows were never removed. `/ask-docs` and prior-art search can still
return them, with a version that is no longer true.

## Cause

`scripts/index-docs.py`, just before the prune:

```python
present = [doc[0] for doc in docs]
if args.limit > 0 and stale:
    present = sorted(set(present) | set(existing))
```

Any run with `--limit` adds every stored path back to `present`, so the prune deletes nothing.
Hermes always runs `index-docs.py --ref <ref> --limit 100 --quiet` (`bin/k3dm-hermes`), so the
scheduled index has **never** pruned. The guard came in with #133 (`3a254484`) with no test and no
recorded reason.

`stale` does not depend on `--limit`. It is the stored paths minus the **full** corpus
(`iter_corpus`), and `--limit` only caps how many changed docs are embedded. So the guard protects
nothing that a limited run could get wrong.

A second path hides the problem: when the corpus fingerprint is unchanged, Hermes reports `noop`
and re-indexes only when `rows < corpus_docs`. A store with **extra** rows is never revisited.

## Fix

1. **`scripts/index-docs.py`**
   - Delete the `if args.limit > 0 and stale:` block. A limited run prunes stale paths like any
     other run.
   - Keep one safety valve against a wrong ref or an empty corpus listing. If `len(stale)` exceeds
     `max(20, len(existing) // 20)`, skip the prune and keep every path. Print one stderr line,
     `index-docs: refusing to prune N of M stored docs; run make index-docs DRY_RUN=1 to review`,
     and exit 1.
2. **`bin/k3dm-hermes` `_refresh_index`**, noop branch: re-index when `rows != corpus_docs`, not only
   when `rows < corpus_docs`, so extra rows are pruned on the next poll. Update the stderr line to
   `store has R rows for C corpus docs`.
3. **`scripts/etc/prometheus/rules/vectordb.yaml`**: in the `VectorDBIndexDrift` description, say
   what the sign means. Positive: corpus docs are missing from the store (the backlog). Negative:
   the store holds docs no longer in the corpus (not pruned).

## Files

| File | Change |
|---|---|
| `scripts/index-docs.py` | item 1 |
| `bin/k3dm-hermes` | item 2 |
| `scripts/etc/prometheus/rules/vectordb.yaml` | item 3 |
| `scripts/tests/bin/test_index_docs.py` | tests 1–3 |
| `scripts/tests/hermes/test_hermes.py` | test 4 |

## Tests

1. `main(["--limit", "5"])` with one stored path missing from the corpus: the prune script's
   `present` list omits that path, so the prune deletes it.
2. The same with no `--limit`: unchanged behaviour.
3. With 30 stale paths out of 100 stored: no `DELETE` script is run, the refusal line is printed,
   and the exit code is 1.
4. `_refresh_index` with an unchanged fingerprint and a status of `rows 1948, corpus_docs 1947`:
   `index-docs.py` is run, and the result is not `noop`.

Mutation checks. Paste the red output for each:
- Restore the `--limit` guard. Test 1 must fail.
- Change `!=` back to `<` in item 2. Test 4 must fail.

## Rules

- Bare `pytest scripts/tests/bin/test_index_docs.py scripts/tests/hermes/test_hermes.py`: green.
- No test reaches the real store or the embeddings API.
- Do not commit. `.git` is read-only in the sandbox.

## After landing (not Codex's job)

The Hermes LaunchAgent runs `bin/k3dm-hermes` from the operator checkout every 300 s, so the fix is
live from the next poll. Claude confirms that `k3dm_vectordb_drift_docs` returns to 0 and that
`VectorDBIndexDrift` resolves.
