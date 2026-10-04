# Bug: the index-docs embedding cache has no second copy, no metadata, and no pruning

**Filed:** 2026-10-04, Claude
**Branch:** `k3d-manager-v1.41.0`
**Status:** OPEN. Depends on `2026-10-04-index-docs-rebuild-after-hub-loss-costs-a-day-of-quota.md`
(`scripts/lib/hermes/embed_cache.py`), which must land first.
**Severity:** low. The cache can be rebuilt, so losing it costs quota and time, not data.

## Observed

The cache at `~/.cache/k3dm/embeddings.sqlite` sits on the same M4 that runs the hub. One machine
loss, whether disk, reinstall or theft, takes out both pgvector and the cache. That moves the recovery
dependency without removing it.

The operator agreed (2026-10-04) to add a light second copy, e.g. to the M2 or to a synced folder. It
needs no encryption: the vectors derive from the repo's own docs.

A second review (2026-10-04) asked for integrity metadata, so the cache can reject incompatible entries.

**What the cache key already guarantees.** The key is `sha256(model, dim, task_type, text)`, so a
stale or incompatible entry can never be looked up: any change is a miss by construction. Columns add
no correctness there.

**What metadata does add:**
- **Pruning.** Every doc edit adds a new key, and nothing ever removes the old one, so the cache only
  grows.
- **Visibility.** You can see which models and dimensions a cache holds.
- **A defence-in-depth check** on reads and restores, against a corrupt blob or a hand-built file.
- **A schema version** for future migrations.

Layering this establishes: git docs (source of truth) → embedding cache (derived, reusable) →
pgvector (runtime serving store). Each layer can be rebuilt from the one before it.

## Fix spec

### File 0 — `scripts/lib/hermes/embed_cache.py` (metadata, schema version 2)

**Schema.**
- Version 2 is recorded with `PRAGMA user_version`.
- The table gains the columns `model TEXT`, `dim INTEGER`, `task_type TEXT`, `content_hash TEXT`,
  `created_at TEXT` and `last_used_at TEXT`, as UTC ISO-8601 timestamps.
- **Migration on open:** if `user_version < 2`, run `ALTER TABLE … ADD COLUMN` for each missing
  column, then set `user_version = 2`.
  - Existing rows keep NULL metadata. They stay usable, because their key still guarantees
    compatibility.
  - Never drop rows during a migration.

**`put_many`** takes `(key, vector, meta)`, where `meta` holds `model`, `dim`, `task_type` and
`content_hash`. It sets `created_at` and `last_used_at` to now. Update the one caller in
`scripts/index-docs.py`, passing `content_hash` as the doc digest it already has.

**`get_many(keys, model, dim, task_type)`** treats a row as a miss when any of these hold:
- `len(blob) != dim * 4`;
- `model`, `dim` or `task_type` is non-NULL and differs from the request.

It sets `last_used_at = now` on every hit, in one `UPDATE … WHERE key IN (…)`.

**`prune(keep_hashes, max_age_days=90)`** deletes rows that are both:
- **stale:** `content_hash` is not in `keep_hashes`, or `model` / `dim` differs from the current
  `EMBED_MODEL` / `EMBED_DIM`;
- **unused for longer than `max_age_days`:** `last_used_at` is older than that, or is NULL.

It returns the count deleted. Delete only when both conditions hold. A cache shared between two Macs
on different branches must not lose the other branch's vectors after one run.

**`stats()`** returns the row count per `(model, dim, task_type)`, plus the oldest `created_at` and the
newest `last_used_at`.


### File 1 — `scripts/embed-cache.py` (new)

A CLI with two subcommands. It uses only the standard library and imports `cache_path` from
`hermes.embed_cache`. Never shell out to `sqlite3`: the Python `sqlite3` module avoids quoting a user
path into a dot-command.

**`backup DEST`**

- Source: `cache_path()`. If it does not exist, exit 1 with `embed-cache: no cache at <path> — run make index-docs first`.
- **Write path:**
  - If `DEST` is an existing directory, write `DEST/embeddings.sqlite`.
  - Write to a temporary file in the destination directory first, using `src.backup(tmp)`, which takes
    a consistent snapshot even while index-docs writes.
  - Then `os.replace` it into place. A backup that is interrupted never leaves a truncated file at the
    destination.
- **Output:** print `embed-cache: backed up <n> vectors to <dest>`, where `n` is the row count of the
  copy, then exit 0.

**`restore SRC`**

- **Validate the source:**
  - If `SRC` does not exist, exit 1.
  - If `SRC` has no `embeddings` table with `key` and `vector` columns, exit 1 with
    `embed-cache: <src> is not an embedding cache`.
- **Merge, never overwrite:**
  - Create the primary if it is absent, with the same schema as `EmbedCache`.
  - Run `ATTACH DATABASE ? AS b`, with the path as a bound parameter.
  - Run `INSERT OR IGNORE INTO embeddings (key, vector) SELECT key, vector FROM b.embeddings`, in one
    transaction.
  - Keys are content hashes, so an older backup only fills gaps. It never replaces a newer vector.
- **Output:** print `embed-cache: restored <added> new vectors (<total> in cache)`, then exit 0.

**`restore` integrity:** skip any backup row whose `len(vector) != dim * 4`, where `dim` is the row's
own `dim` column, or `EMBED_DIM` when that is NULL. Count the skipped rows, and print them as
`, <k> skipped (wrong size)` when there are any.

**`stats`:** print `stats()` as one line per model, dimension and task type, plus the two timestamps.

**`prune [--days N]`:**
- Read `keep_hashes` from `iter_corpus(ROOT)`. This is a git read only: no network, no Vault.
- Call `prune`, and print `embed-cache: pruned <n> stale vectors (<total> remain)`.
- The default is 90 days.

**Usage error:** exit 2, through argparse.

### File 2 — `Makefile`

Add the four targets to `.PHONY`, each with a `## ` help line, placed next to `index-docs`:

```make
## Copy the index-docs embedding cache to a second location: make embed-cache-backup DEST=<file or dir>
embed-cache-backup:
	@[ -n "$(DEST)" ] || { echo "ERROR: DEST is required, e.g. make embed-cache-backup DEST=/Volumes/m2-share/k3dm" >&2; exit 1; }
	@python3 scripts/embed-cache.py backup -- "$(DEST)"

## Show what the embedding cache holds (models, dims, age)
embed-cache-stats:
	@python3 scripts/embed-cache.py stats

## Drop cached vectors for deleted/edited docs or old models unused for DAYS (default 90)
embed-cache-prune:
	@python3 scripts/embed-cache.py prune $(if $(DAYS),--days $(DAYS),)

## Merge a backed-up embedding cache into the local one: make embed-cache-restore SRC=<file>
embed-cache-restore:
	@[ -n "$(SRC)" ] || { echo "ERROR: SRC is required, e.g. make embed-cache-restore SRC=/Volumes/m2-share/k3dm/embeddings.sqlite" >&2; exit 1; }
	@python3 scripts/embed-cache.py restore -- "$(SRC)"
```

### File 3 — `scripts/tests/bin/test_embed_cache_cli.py` (new)

Point `K3DM_EMBED_CACHE` at `tmp_path` in every test. Seed caches through `EmbedCache.put_many`.

The tests:

1. **Backup and restore round trip.** Back up a 3-vector cache, delete the primary, restore, and assert
   that the same 3 keys come back with byte-identical vectors.
2. **Restore merges and never overwrites.**
   - The primary holds keys A and B, with B carrying vector `v_new`.
   - The backup holds B with `v_old`, and C.
   - After restore, the primary has A, B and C, B still holds `v_new`, and the output reports `1 new`.
3. **A directory `DEST`** writes `DEST/embeddings.sqlite`.
4. **Backup with no primary** exits 1 with `no cache at`.
5. **Restore from a non-cache SQLite file** exits 1 with `is not an embedding cache`, and leaves the
   primary unchanged.
6. **A `DEST` path containing a space and a single quote** works, which proves there is no
   dot-command quoting.
7. **No partial file on failure.** Make `backup` fail mid-copy, e.g. by monkeypatching
   `sqlite3.Connection.backup` to raise. Assert that the destination file does not exist and that no
   temp file is left in the destination directory.

8. **Migration.**
   - Hand-build a version-1 file with only `key` and `vector`, holding 2 rows.
   - Open it with `EmbedCache` and assert that `user_version == 2`, that both rows still return, and
     that their metadata is NULL.
9. **Integrity on read.**
   - A row whose blob is the wrong length is a miss.
   - A row whose stored `model` differs from the request is a miss.
10. **A hit updates `last_used_at`.**
11. **Prune.**
    - Rows covered: a current-hash row, a stale-hash row last used 100 days ago, a stale-hash row
      used yesterday, and an old-model row last used 100 days ago.
    - `prune(keep, 90)` deletes exactly the two old rows.
12. **Restore skips wrong-size rows** and reports `1 skipped (wrong size)`.

Add the metadata tests to `scripts/tests/bin/test_index_docs.py` or to a new
`scripts/tests/bin/test_embed_cache.py`, whichever keeps the files smaller.

### File 4 — `docs/howto/find-prior-art.md`

Extend the "Hub rebuilt?" note with a "Second copy" paragraph covering:
- the layering: git docs → embedding cache → pgvector, each rebuildable from the one before;
- `make embed-cache-stats` and `make embed-cache-prune`;
- `make embed-cache-backup DEST=…` after a big index run, e.g. to the M2 or to a synced folder;
- `make embed-cache-restore SRC=…` on a fresh or rebuilt Mac, before `make index-docs`;
- that restore merges and is safe to repeat;
- that Time Machine already covers `~/.cache` unless it is excluded, which can be checked with
  `tmutil isexcluded`.

### File 5 — `CHANGELOG.md`

Add one entry under `## [Unreleased]` → `### Added`. It covers:
- the two targets;
- that the snapshot is consistent and the replace atomic;
- that restore merges by content hash and never overwrites.

## Rules

- Modify only Files 0–5, plus `scripts/index-docs.py` (the `put_many`/`get_many` call sites only) and
  `scripts/tests/bin/test_embed_cache.py` if created. Do not touch `scripts/lib/foundation/`.
- Never read or write the real `~/.cache/k3dm`.
- Run and paste:
  - `python -m pytest scripts/tests/bin/test_embed_cache_cli.py scripts/tests/bin/test_index_docs.py -q`
  - `make -n embed-cache-backup DEST=/tmp/x`
  - `make embed-cache-backup`, expecting the `DEST is required` error and a non-zero exit
- Mutations (snapshot first, then restore and check with `cmp`):
  - change `INSERT OR IGNORE` to `INSERT OR REPLACE`, and show test 2 red;
  - write straight to `DEST` without the temp file and `os.replace`, and show test 7 red.
  - make `prune` delete on staleness alone, without the age check, and show test 11 red;
  - drop the blob-length check in `get_many`, and show test 9 red.
- Do not run `make test`.
