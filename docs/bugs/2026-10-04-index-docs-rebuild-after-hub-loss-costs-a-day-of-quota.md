# Bug: losing the hub's vector store costs more than a day of Gemini embedding quota to rebuild

**Filed:** 2026-10-04, Claude
**Branch:** `k3d-manager-v1.41.0`
**Status:** OPEN
**Severity:** low. `find-similar-docs` is partial or empty for one to two days after every hub rebuild.

## Observed

`scripts/index-docs.py` keeps embeddings only in the pgvector table on the hub (namespace `vectordb`).
Its docstring calls the store "a rebuildable cache: losing it costs one re-index".

The last full index paused at 1000/1120 on the daily quota (`perday`). So one re-index needs more than
a day of free-tier quota, and every hub rebuild pays it again for vectors we have already been given
once.

Facts the fix depends on (`scripts/lib/hermes/prior_art.py`):

- **Model:** `EMBED_MODEL = "gemini-embedding-2"`, `EMBED_DIM = 768`.
- **Vector size:** a vector is 768 floats, so the whole corpus is about 3.4 MB as float32.
- **Corpus:** `iter_corpus` yields `(path, title, embed_text, digest)`, where
  `digest = content_hash(embed_text)` (sha256).
- **Embedding:** `embed_batch(texts, task_type=...)` returns one vector per text, checks the dimension,
  and raises `RetrievalUnavailable` on quota or credential failure.

## Fix spec

### File 1 — `scripts/lib/hermes/embed_cache.py` (new)

A small SQLite cache, standard library only (`sqlite3`, `array`, `hashlib`, `os`, `pathlib`).

- **Location:** `cache_path()` returns `Path(os.environ["K3DM_EMBED_CACHE"])` if that is set, otherwise
  `Path.home() / ".cache" / "k3dm" / "embeddings.sqlite"`.
- **Schema:** one table, `CREATE TABLE IF NOT EXISTS embeddings (key TEXT PRIMARY KEY, vector BLOB NOT NULL)`.
- **Key:** `cache_key(model, dim, task_type, text)` returns
  `sha256(f"{model}\0{dim}\0{task_type}\0{text}")` as hex. Changing the model, the dimension or the
  task type is therefore a cache miss, never a silent mix.
- **Vectors** are stored as `array('f', vector).tobytes()`.
- **`class EmbedCache`:**
  - **`__init__(path=None)`:** `mkdir(parents=True, exist_ok=True)` on the parent, then
    `sqlite3.connect`, then create the table.
    - If any `OSError` or `sqlite3.Error` is raised, the cache is disabled: `self.enabled = False`.
      Print one warning to stderr: `index-docs: embedding cache unavailable (<path>): <error> — continuing without it`.
    - A cache failure must never fail the index.
  - **`get_many(keys)`** returns `{key: list[float]}` for the hits. When disabled, it returns `{}`.
  - **`put_many(items)`** takes `(key, vector)` pairs and does `INSERT OR REPLACE` in one transaction.
    It is a no-op when disabled. A `sqlite3.Error` disables the cache and warns, the same as above.
  - Every vector read from the cache must be checked: one whose length is not the expected dimension
    is treated as a miss.

### File 2 — `scripts/index-docs.py`

**Cache.** Inside the existing `try:` embedding loop, before `embed_batch`:

1. Create `cache = EmbedCache()` once, before the loop. Under `--dry-run` do not open it, so a dry run
   writes no file.
2. Compute the key per doc as `cache_key(EMBED_MODEL, EMBED_DIM, "RETRIEVAL_DOCUMENT", doc[2])`.
3. Call `get_many` for the batch's keys.
4. Call `embed_batch` only for the misses, keeping the batch order, and skip the call when there are
   no misses. Then `put_many` the newly embedded `(key, vector)` pairs before `run_sql`. A vector
   Gemini returned is then kept even if the hub write fails.
5. Assemble `rows` in the original batch order from the hits and the new vectors, then upsert as
   today.
6. Count `from_cache` and `embedded` separately. The existing `written` counter still counts rows
   committed to the store.

**Order.** Before applying `--limit`, sort `changed` so that docs whose file name starts with
`YYYY-MM-DD` come first, newest date first. All other docs follow in their current order. Use a stable
sort keyed on the name, not the mtime. Ordering costs nothing on a cache hit; on a miss it means a
partial index covers the most recent bugs and issues first.

**Summary line.** The final line becomes:

`index-docs: {docs} docs, {written} written ({from_cache} from cache, {embedded} embedded), {pruned} pruned, {indexed} in store, {remaining} remaining`

Also add `from_cache` to the per-batch `committed` progress line. The `paused` (quota) message and the
`unavailable` message are unchanged.

**Docstring.** Add one paragraph: every embedding is also kept in a local SQLite cache
(`~/.cache/k3dm/embeddings.sqlite`, override with `K3DM_EMBED_CACHE`), so rebuilding a lost store
re-reads vectors from it instead of spending embeddings quota.

### File 3 — `scripts/tests/bin/test_index_docs.py`

Follow the existing monkeypatch style. In an autouse fixture or per test, point `K3DM_EMBED_CACHE` at
`tmp_path / "cache.sqlite"`, so no test touches `~/.cache`.

Add these tests:

1. **Rebuild after store loss costs zero API calls.**
   - First run: `fetch_hashes` returns `{}`, and the stub `embed_batch` counts the texts it is given.
   - Second run: same corpus, `fetch_hashes` still returns `{}` (the store was lost), and `embed_batch`
     raises if called.
   - Assert that the second run exits 0, writes every doc through `run_sql`, and that its summary
     contains `5 from cache, 0 embedded`, or whatever counts match the fixture.
2. **A partial hit embeds only the misses, and rows keep corpus order.**
   - Pre-seed the cache with 2 of 4 docs.
   - Assert that `embed_batch` received exactly the other 2 texts.
   - Assert that the upsert script lists paths in the original order, each with the vector that
     belongs to it. Use distinct stub vectors per text.
3. **A model or task-type change is a miss.** Assert that `cache_key` differs when only the model
   differs, and when only the task type differs.
4. **An unwritable cache does not fail the index.**
   - Point `K3DM_EMBED_CACHE` at a path under a plain file, so `mkdir` fails.
   - Assert that the run exits 0, embeds everything, and that stderr contains
     `embedding cache unavailable`.
5. **Quota pause still keeps what was embedded.**
   - `embed_batch` succeeds for batch 1 and raises a `perday` `RetrievalUnavailable` for batch 2.
   - Assert that batch 1's vectors are in the cache afterwards.
   - Assert that a re-run with an empty store and a raising `embed_batch` still writes batch 1's docs,
     from the cache.
6. **Newest dated docs are embedded first under `--limit`.**
   - Use a corpus of `docs/plans/v1.0.0-x.md`, `docs/bugs/2026-01-01-a.md` and
     `docs/bugs/2026-10-01-b.md`, with `--limit 1`.
   - Assert that the single doc embedded is `2026-10-01-b`.
7. **`--dry-run` creates no cache file.**

### File 4 — `docs/howto/find-prior-art.md`

Add a short "Hub rebuilt?" note. It says:
- `make index-docs` reloads from the local cache with no embeddings quota spent;
- the summary line shows `from cache`;
- deleting `~/.cache/k3dm/embeddings.sqlite` only costs re-embedding.

### File 5 — `CHANGELOG.md`

Add one entry under `## [Unreleased]` → `### Changed`. It says that:
- index-docs keeps a local, content-addressed embedding cache keyed by model, dimension and task type,
  so a lost hub store is rebuilt without Gemini calls;
- misses embed the newest dated docs first;
- the summary reports cache hits.

## Rules

- Modify only Files 1–5. Do not change `prior_art.py`, `find-similar-docs.py`, the SQL schema, or
  `scripts/lib/foundation/`.
- Never call the real Gemini API, Vault, kubectl or the hub. Tests stub `embed_batch`, `run_sql`,
  `fetch_hashes`, `ensure_schema` and `iter_corpus`.
- The cache holds only vectors keyed by hashes. Never store the API key, and never store doc text.
- Run and paste:
  - `python3 -m pytest scripts/tests/bin/test_index_docs.py scripts/tests/bin/test_find_similar_docs.py scripts/tests/bin/test_prior_art.py -q`
  - `python3 scripts/index-docs.py --help`
- Mutations (snapshot first, then restore and check with `cmp`):
  - make the cache lookup always return `{}`, and show test 1 red;
  - drop the date ordering, and show test 6 red.
- Do not run `make index-docs` or `make test`.
