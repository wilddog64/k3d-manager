# Bug: the embedding cache starts empty, though the hub store already holds every vector it needs

**Filed:** 2026-10-04, Claude
**Branch:** `k3d-manager-v1.41.0`
**Status:** FIXED — Codex, verified by Claude 2026-10-04: 654 pytest pass; mutations (drop hash match, skip the `get_many` check) each turn their test red. Claude reworded the howto paragraph.
**Severity:** low. Until the next full re-embed, a hub loss still costs more than a day of Gemini quota.

## Observed

The cache (`5c774874`, `12f3f105`) stores only vectors embedded **after** it landed. On 2026-10-04 the
operator's `~/.cache/k3dm/embeddings.sqlite` was 12 KB and empty, while the hub's pgvector table held
about 1,000 of the 1,120 corpus vectors. A backup made now would cover only the ~127 docs embedded
after the quota resets.

The hub table (`TABLE` in `scripts/lib/hermes/prior_art.py`) stores `path`, `title`, `content_hash`
and `embedding` for each doc, where `content_hash = sha256(embed_text)`. That is enough to rebuild the
cache key for every row whose doc is unchanged, at zero Gemini cost:

```
key = cache_key(EMBED_MODEL, EMBED_DIM, "RETRIEVAL_DOCUMENT", embed_text)
```

**Model assumption.** `EMBED_MODEL = "gemini-embedding-2"` has not changed since the store was
introduced (`git log -S'EMBED_MODEL = '` shows only `3a254484`), so every row in the store was embedded
with the current model. The seed must still reject a vector whose length is not `EMBED_DIM`.

## Fix spec

### File 1 — `scripts/embed-cache.py`, new subcommand `seed [--ref REF]`

1. **Corpus.** `docs = iter_corpus(ROOT)` when `--ref` is absent, else `iter_corpus(ROOT, args.ref)`.
   Build `{path: (embed_text, digest)}`.
2. **Read the store.** Call `run_sql` (import it with `TABLE`, `RetrievalUnavailable` and `EMBED_MODEL`
   from `hermes.prior_art`) with:
   ```sql
   COPY (SELECT path, content_hash, embedding::text FROM <TABLE>) TO STDOUT;
   ```
   Parse each output line as three tab-separated fields. Parse the vector with `json.loads`, since
   pgvector's text form is `[0.1,0.2,…]`. Unescape COPY's text format for `path` (`\\` → `\`, `\t` → tab,
   `\n` → newline), or simply skip any row whose path contains a backslash and count it as unmatched.
   Corpus paths never contain one.
3. **Match.** Seed a row only when its `path` is in the corpus, its `content_hash` equals that doc's
   digest, and `len(vector) == EMBED_DIM`. Count every other row as `unmatched`.
4. **Write without overwriting.** Compute the keys, call `get_many` to find the keys already cached,
   then `put_many` only the rest, with meta `{"model": EMBED_MODEL, "dim": EMBED_DIM,
   "task_type": "RETRIEVAL_DOCUMENT", "content_hash": digest}`. Write in chunks of 200 rows.
5. **Output.** Print
   `embed-cache: seeded <n> vectors from the store (<k> already cached, <u> unmatched, <total> in cache)`,
   then exit 0.
6. **Errors.**
   - A `RetrievalUnavailable` from `run_sql` prints `embed-cache: store unavailable — <exc>` and exits 1.
   - A disabled cache exits 1.
   - Never call `embed_batch`.

Update the module docstring to name `seed`.

### File 2 — `Makefile`

Add `embed-cache-seed` to `.PHONY`, next to the other `embed-cache-*` targets:

```make
## Fill the embedding cache from the hub's vector store at zero quota cost: make embed-cache-seed [REF=origin/<branch>]
embed-cache-seed:
	@python3 scripts/embed-cache.py seed $(if $(REF),--ref $(REF),)
```

### File 3 — `scripts/tests/bin/test_embed_cache_cli.py`

Monkeypatch `cli.run_sql` and `cli.iter_corpus`, and make `cli.embed_batch` (if imported) or
`hermes.prior_art.embed_batch` raise if called. Add:

1. **Seeds matching rows.** The corpus has a and b. The store has a with a matching hash, b with a
   stale hash, and c, which is not in the corpus. Assert that only a is cached, under the key built from
   a's embed text, with `content_hash` set. Assert the output reports `1 vectors`, `2 unmatched`, and
   that `embed_batch` was never called.
2. **Never overwrites.** Pre-seed a's key with `v_old`. The store has a with `v_store`. Assert that a
   still holds `v_old` and that the output reports `1 already cached`.
3. **Wrong-dimension rows are unmatched.**
4. **Store unavailable.** `run_sql` raises `RetrievalUnavailable`. Assert exit 1, `store unavailable`
   in stderr, and no cache rows.
5. **`--ref` is passed to `iter_corpus`.**

### File 4 — `docs/howto/find-prior-art.md`

In the "Second copy" paragraph, add: on a cache that predates the hub's vectors, run
`make embed-cache-seed` (at zero quota cost) before `make embed-cache-backup`.

### File 5 — `CHANGELOG.md`

Add one line to the existing embed-cache entry under `## [Unreleased]` → `### Added`, saying
`make embed-cache-seed` fills the cache from the hub store without Gemini calls.

## Rules

- Modify only Files 1–5. Do not change `prior_art.py`, `index-docs.py`, `embed_cache.py`, or
  `scripts/lib/foundation/`.
- Never run the real `seed`, kubectl, Vault or Gemini. Never touch the real `~/.cache/k3dm`.
- Run and paste:
  - `python -m pytest scripts/tests/bin/test_embed_cache_cli.py scripts/tests/bin/test_index_docs.py -q`
  - `make -n embed-cache-seed REF=origin/x`
- Mutations (snapshot first, then restore and check with `cmp`):
  - drop the hash match, and show test 1 red;
  - put every row without the `get_many` check, and show test 2 red.
- Do not run `make test`.
