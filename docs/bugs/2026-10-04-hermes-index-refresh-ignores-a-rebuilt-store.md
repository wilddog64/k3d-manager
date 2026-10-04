# Bug: Hermes never re-indexes a rebuilt vector store, and the dashboard cannot show cache reloads

**Filed:** 2026-10-04, Claude
**Branch:** `k3d-manager-v1.41.0`
**Status:** FIXED — re-index commit, 2026-10-04. (Depended on `2026-10-04-index-docs-rebuild-after-hub-loss-costs-a-day-of-quota.md`
(the `from cache` summary).)
**Severity:** medium for recovery. After a hub rebuild, `find-similar-docs` stays empty until a corpus doc
changes.

## Observed

### 1. The fingerprint short-circuit ignores the store

`bin/k3dm-hermes` `_refresh_index`:

```python
        fingerprint = corpus_fingerprint(ROOT, ref)
        if fingerprint == state.get("index_fingerprint"):
            metrics["result"] = "noop"
            metrics["backlog"] = 0
            return
```

The fingerprint covers the git corpus only. When the hub is rebuilt, the pgvector table comes back
empty but the corpus is unchanged, so every 5-minute poll reports `noop` with backlog 0. Recovery
happens only by accident, when some doc next changes, because `index-docs` then sees an empty store.

Meanwhile:
- `k3dm_vectordb_drift_docs` (corpus minus rows, from `bin/k3dm-vectordb-metrics`) shows the gap;
- `k3dm_vectordb_index_backlog_docs` reports 0.

The two panels contradict each other.

### 2. `--limit` counts cache hits as if they cost quota

Hermes runs `index-docs --limit 100`. The limit exists to bound embeddings API spend per run. Once the
cache lands, a rebuild that needs no API calls is still cut into chunks of 100, so an 1,120-doc reload
takes 12 polls, about an hour, instead of one.

### 3. The dashboard reads `embedded` with a new meaning

Hermes parses `(\d+) embedded` from the summary line. After the cache change, that number is
**Gemini calls**, not docs written. This is the better quota signal, so the regex stays. But a cache
reload now shows 0 on "Docs embedded / pruned per run", and nothing shows the docs restored from the
cache.

## Fix spec

### File 1 — `bin/k3dm-hermes`, `_refresh_index`

When the fingerprint matches, check the store before declaring `noop`:

- Run `bin/k3dm-vectordb-status --json` with a 120 s timeout and `check=False`, exactly as
  `bin/k3dm-vectordb-metrics` `_status()` does.
- If the result has `available` true, and integer `rows` and `corpus_docs` with
  `rows < corpus_docs`, then:
  - clear `state["index_fingerprint"]`;
  - log `vectordb index: store has <rows> of <corpus_docs> docs; re-indexing despite unchanged corpus`
    to stderr;
  - continue into the normal `index-docs` run.
- Otherwise, including when the status is unavailable, unparsable, or reports `rows >= corpus_docs`,
  keep today's `noop` behaviour.
- Never fail the poll on a status error.

**Metrics.** Parse `(\d+) from cache` the same way as `embedded`, into `metrics["from_cache"]`, which
defaults to 0. In `_push_index_metrics`, add
`f"k3dm_vectordb_index_from_cache_last {metrics['from_cache']}"` after the `embedded` line.

### File 2 — `scripts/index-docs.py`

`--limit N` caps the docs that need an **embeddings API call**, i.e. cache misses. Cache hits are not
counted against it.

- Process `changed` in date order, as today.
- Stop adding misses after N of them.
- Keep writing hits from every batch.
- Update the `--limit` help text to: `embed at most N uncached documents (0 = no limit)`.
- `remaining` still counts the docs not written.

### File 3 — `scripts/etc/argocd/platform-ops/grafana-dashboard-vectordb.yaml`

Change panel id 13:

- **Title:** `Docs embedded (API) / from cache / pruned per run (last published)`.
- **Targets:** add `{"expr": "k3dm_vectordb_index_from_cache_last", "legendFormat": "from cache (last published)"}`
  between the existing two.
- Rename the `embedded` legend to `embedded via API (last published)`.

Change nothing else in the dashboard.

### File 4 — tests

**`scripts/tests/hermes/`**, in the file that already covers `_refresh_index`. Find it with
`grep -ln _refresh_index scripts/tests/hermes`. Stub `subprocess.run` per command and add:

1. **An unchanged fingerprint with a store at 0 of 5** runs `index-docs`, sets result to success, and
   clears the fingerprint first.
2. **An unchanged fingerprint with a store at 5 of 5** stays `noop` and does not run `index-docs`.
3. **An unchanged fingerprint with the status command failing** (rc 1, or not JSON) stays `noop`.
4. **`from cache` is parsed** into `k3dm_vectordb_index_from_cache_last`.

**`scripts/tests/bin/test_index_docs.py`**:

5. **`--limit 1` with 3 cache hits and 2 misses** writes 4 docs, calls `embed_batch` with exactly 1
   text, and reports `1 remaining`.

**Dashboard.** If a test already loads `grafana-dashboard-vectordb.yaml`, assert that panel 13 has the
`k3dm_vectordb_index_from_cache_last` target. Otherwise add that assertion to the test in item 4.

### File 5 — `docs/howto/find-prior-art.md` and `CHANGELOG.md`

**`docs/howto/find-prior-art.md`.** Extend "Hub rebuilt?":
- Hermes now notices an empty store and re-indexes on its own within one poll;
- with the cache, that reload costs no quota;
- the vectordb dashboard shows it as "from cache".

**`CHANGELOG.md`.** Add one `### Fixed` entry under `## [Unreleased]`.

## Rules

- Modify only Files 1–5 and the test files named. Do not touch `scripts/lib/foundation/`.
- Never run Hermes, `bin/k3dm-vectordb-status` for real, kubectl, Gemini, or `make index-docs`.
- Run and paste: `python -m pytest scripts/tests/hermes scripts/tests/bin/test_index_docs.py -q`.
  Also run `python3 -c` with a `yaml.safe_load` of the dashboard, then `json.loads` of its embedded
  JSON, to prove both still parse.
- Mutations (snapshot first, then restore and check with `cmp`):
  - remove the store check, and show test 1 red;
  - count hits against `--limit`, and show test 5 red.
- Do not run `make test`.
