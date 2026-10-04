# Bug: the index-docs embedding cache has no second copy, and lives on the same Mac as the hub

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

## Fix spec

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

**Usage error:** exit 2, through argparse.

### File 2 — `Makefile`

Add the two targets to `.PHONY`, each with a `## ` help line, placed next to `index-docs`:

```make
## Copy the index-docs embedding cache to a second location: make embed-cache-backup DEST=<file or dir>
embed-cache-backup:
	@[ -n "$(DEST)" ] || { echo "ERROR: DEST is required, e.g. make embed-cache-backup DEST=/Volumes/m2-share/k3dm" >&2; exit 1; }
	@python3 scripts/embed-cache.py backup -- "$(DEST)"

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

### File 4 — `docs/howto/find-prior-art.md`

Extend the "Hub rebuilt?" note with a "Second copy" paragraph covering:
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

- Modify only Files 1–5. Do not change `embed_cache.py` or `index-docs.py`. Do not touch
  `scripts/lib/foundation/`.
- Never read or write the real `~/.cache/k3dm`.
- Run and paste:
  - `python -m pytest scripts/tests/bin/test_embed_cache_cli.py scripts/tests/bin/test_index_docs.py -q`
  - `make -n embed-cache-backup DEST=/tmp/x`
  - `make embed-cache-backup`, expecting the `DEST is required` error and a non-zero exit
- Mutations (snapshot first, then restore and check with `cmp`):
  - change `INSERT OR IGNORE` to `INSERT OR REPLACE`, and show test 2 red;
  - write straight to `DEST` without the temp file and `os.replace`, and show test 7 red.
- Do not run `make test`.
