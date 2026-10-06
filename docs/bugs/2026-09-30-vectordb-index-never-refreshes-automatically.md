# Bug: the vector store is only re-indexed by hand, so new docs are invisible to prior-art search

**Branch:** `k3d-manager-v1.40.0`
**Filed:** 2026-09-30 by Claude (cloud session), from the operator's question "are new docs injected
into the vector DB?"
**Status:** FIXED — Codex `29b7f55c`, verified by Claude 2026-09-30 with four defects fixed in the
follow-up commit (see Verification). Unexercised live until Hermes restarts on the new code.
Superseded on the quota reset time by `2026-10-04-hermes-quota-pause-ends-at-utc-not-pacific-midnight.md`.
**Severity:** Medium. Prior-art dedup (`make find-similar-docs`, which CLAUDE.md requires before
filing) silently misses recent docs, and the v1.40.0 retrieval eval would measure a stale index.

## Evidence

- Hermes `vectordb` sensor, every poll on 2026-09-29: `rows=1705, corpus=1722, indexed 2.5d ago`. The
  last index run was about 2026-09-27; 23 corpus docs were added between then and 2026-09-30, and none
  of them is searchable.
- Nothing runs `make index-docs` (or `/k3dm index-docs`): no launchd job, cron, Hermes tick or CI job.
  Neither `v1.39.0-vector-store-platform-and-retrieval.md` nor
  `v1.40.0-hermes-prior-art-and-retrieval-eval.md` plans one.
- `VectorDBIndexStale` fires only when the index is **7 days** old, so a week of drift is silent.

## Root cause

1. **No trigger.** Indexing is a manual command only.
2. **Working-tree corpus.** `prior_art.iter_corpus` enumerates `git ls-files` and reads files from the
   M4's checkout, so docs pushed from cloud sessions or by Codex are invisible until the operator
   pulls. `bin/k3dm-vectordb-status` counts `corpus_docs` the same way, so the drift metric is
   relative to whatever happens to be checked out.

## Cost model (why frequent is fine)

The index is keyed by a SHA-256 of the embedded text (title, lead paragraph, `##` headings), so a run
with no doc changes makes **zero** embedding calls. Changed docs cost one call each. A busy day adds
10–25 docs; the free tier allows about 100 calls/minute and about 1,000/day. Only a cold start from
nothing hits the daily cap (see `docs/guides/vector-store.md`, "Re-indexing, and what it costs").

**Cadence decision:** event-driven, checked every Hermes poll (about 5 min). Hermes fetches, and
re-indexes only when the corpus on the tracked ref changed since the last successful index.

## Codex brief

**Goal:** a doc pushed to the tracked branch is searchable within about one Hermes poll, without the
operator pulling. Every ingestion run is visible on the *k3dm VectorDB Health* dashboard, and a stuck
or failing indexer alerts within hours, not a week.

**Runs where:** Codex web is fine. Offline tests only: use temporary git repositories and stub
`run_sql`/`embed_batch`; never call the embeddings API or a real database.

**Files to touch (only these):**
- `scripts/lib/hermes/prior_art.py`: `iter_corpus(repo_root=None, ref=None)`. With `ref=None`, behaviour
  is unchanged. With a ref, list paths with `git ls-tree -r -z --name-only <ref>` and filter them with
  `fnmatch` against `CORPUS_GLOBS`. Git pathspec `*` matches `/`, and so does `fnmatch`, so the set is
  identical to today's `git ls-files`. Read contents through one `git cat-file --batch` process (stdin
  requests; never one subprocess per file, never file contents in argv). Add `corpus_fingerprint(repo_root, ref)`:
  a SHA-256 over the sorted `(path, blob-sha)` pairs of corpus files at the ref.
- `scripts/index-docs.py`: `--ref REF` (default: none → working tree, unchanged).
- `bin/k3dm-vectordb-status`: count `corpus_docs` at the same ref as the indexer, from env
  `K3DM_INDEX_REF` when set; otherwise unchanged.
- `bin/k3dm-hermes`: `_refresh_index(state)`, called each poll **before** `k3dm-vectordb-metrics`.
  - The ref is env `K3DM_INDEX_REF`, else the checkout's upstream (`git rev-parse --abbrev-ref @{upstream}`).
  - `git fetch --quiet origin <branch>` (timeout 60 s). Never `pull`, `checkout`, `reset` or `merge`:
    the operator's working tree must not change.
  - If `corpus_fingerprint` equals `state["index_fingerprint"]`, do nothing.
  - Otherwise run `scripts/index-docs.py --ref <ref> --limit 100 --quiet` (timeout 900 s), with
    `K3DM_INDEX_REF` exported for the metrics step. On exit 0, store the fingerprint. On output
    containing `paused` (daily quota), set `state["index_paused_until"]` to the next 00:00 UTC and skip
    until then. On any other failure, log one line and continue; retrieval is advisory and must never
    break a poll.
  - With `--limit 100`, a large backlog drains over successive polls. The fingerprint is stored only
    when the run reports zero remaining changes, so the next poll continues.
- `scripts/etc/prometheus/rules/vectordb.yaml`: add `VectorDBIndexDrift`:
  `k3dm_vectordb_drift_docs != 0` for `2h`, `severity: warning`, with a description pointing at the
  Hermes log and `make index-docs DRY_RUN=1`. Keep `VectorDBIndexStale` as it is.
- `docs/guides/vector-store.md` (a "Freshness" section: cadence, ref, quota behaviour),
  `CHANGELOG.md`, `memory-bank/activeContext.md`, `memory-bank/progress.md`, and this doc (Status →
  FIXED with the SHA).
- **Ingestion metrics (operator request 2026-09-30: "monitor injections via the Grafana dashboard").**
  After each index attempt, `_refresh_index` pushes gauges to the Pushgateway under a **separate job**,
  `k3dm-vectordb-index`, so they never overwrite `k3dm-vectordb`. Reuse `bin/k3dm-vectordb-metrics`'
  push idiom and `K3DM_PUSHGATEWAY_URL`. Gauges only: Pushgateway replaces on push, so no counters.
  - `k3dm_vectordb_index_last_run_timestamp_seconds`: every attempt, including no-op checks.
  - `k3dm_vectordb_index_last_success_timestamp_seconds`: the last run that exited 0.
  - `k3dm_vectordb_index_last_result{result="success|noop|paused|failed"}`: 1 for the current result,
    0 for the other three (all four series always present).
  - `k3dm_vectordb_index_embedded_last`, `k3dm_vectordb_index_pruned_last`: from the index-docs summary line.
  - `k3dm_vectordb_index_backlog_docs`: changed docs still to embed after this run (0 when caught up).
  - `k3dm_vectordb_index_duration_seconds`: wall time of the last run.
  - `k3dm_vectordb_index_paused_until_timestamp_seconds`: 0 unless paused on the daily quota.
  The run must still count as done when the push fails (log one line; retrieval stays advisory).
- `scripts/etc/grafana/dashboards/k3dm-vectordb-configmap.yaml`: add a row **"Ingestion"** to the
  existing *k3dm VectorDB Health* dashboard (same datasource and conventions; label pushed panels
  "(last published)" like the others):
  - **Last run result** (stat, colour by result: success/noop green, paused amber, failed red);
  - **Time since last successful index** (stat; amber > 1 h, red > 6 h);
  - **Docs embedded / pruned per run** (time series of the two gauges);
  - **Backlog** (time series of `backlog_docs`, with `drift_docs` overlaid);
  - **Run duration** (time series);
  - **Paused on daily quota until** (stat, date format; hidden value 0 shows "not paused").
- `scripts/etc/prometheus/rules/vectordb.yaml`: also add `VectorDBIndexFailing`:
  `k3dm_vectordb_index_last_result{result="failed"} == 1` for `30m`, `severity: warning`.
- Tests: `scripts/tests/bin/test_prior_art.py` and `scripts/tests/bin/test_index_docs.py` (corpus/ref),
  `scripts/tests/hermes/test_hermes.py` and `scripts/tests/hermes/test_vectordb_sensor.py` (refresh and
  metrics), plus a rules/dashboard test in the style of the existing vectordb ones.

**Tests (offline, realistic sizes: a temporary repo with at least 500 corpus docs across all four trees
plus an `archive/` subdirectory and non-corpus files):**
1. Parity: `iter_corpus(root, ref="HEAD")` equals `iter_corpus(root)` on a clean checkout, including the
   `archive/` docs.
2. Ref over working tree: a doc committed on a branch but not checked out is included with
   `ref=<branch>`; an uncommitted working-tree edit is not.
3. `git cat-file --batch` is started once per `iter_corpus` call, whatever the number of docs.
4. Hermes: an unchanged fingerprint → no index subprocess; a changed one → exactly one index run with
   `--ref` and `--limit 100`; success stores the fingerprint; `paused` output → no run until the next
   UTC day; a failure → the poll still completes.
5. Hermes never issues `pull`, `checkout`, `reset` or `merge` (assert over the recorded commands).
6. The rules file has `VectorDBIndexDrift` with `for: 2h` and `VectorDBIndexFailing` with `for: 30m`.
7. Metrics: after a success, a no-op, a paused and a failed run, the pushed body carries the right
   `last_result` series (exactly one at 1), and the job is `k3dm-vectordb-index`, never `k3dm-vectordb`.
   A push failure doesn't change the run's outcome or the stored fingerprint.
8. Dashboard: valid JSON, an "Ingestion" row with the six panels, and every query references a metric
   this change actually emits (no typos: assert each metric name in the queries appears in the metrics code).

**Mutations (paste each red run, then green):** read files from the working tree even when a ref is
given → test 2 red; spawn `git show` per file → test 3 red; always re-index → test 4 red; store the
fingerprint on failure → test 4 red; push under job `k3dm-vectordb` → test 7 red.

**Gates (paste output):** `make test-pytest`; `python3 scripts/check-doc-links.py`; `git diff --stat`
lists only the files above.

**Lessons from earlier reviews:** realistic input sizes; never pass file contents or cluster JSON as
command-line arguments; every early-return path has a test; cover every numbered test or say which one
you skipped and why.

**Do not change:** the embedding text or hash (`doc_embed_text`, `content_hash`), `EMBED_MIN_INTERVAL`,
retry behaviour, the store schema, `find-similar-docs`. No live API or database calls.

**Commit and hand back:** one commit on `k3d-manager-v1.40.0`, message
`fix(vectordb): re-index changed docs from the tracked ref each Hermes poll and chart ingestion`.
No PR, no merge, no force-push, no `--no-verify`.

## Immediate catch-up (operator, until this lands)

```bash
git pull && make index-docs DRY_RUN=1 && make index-docs
```

## Prerequisite: a credential that launchd can read (operator, 2026-09-30)

The catch-up run failed with `no embeddings credential` (0 of 32 committed): env unset,
`k3dm-embeddings-api-key` rc 44, `gemini-cli-api-key` rc 36, Vault `No value found at
secret/data/embeddings/gemini`. This is not a regression. The 2026-09-27 index ran on a one-shot
`K3DM_EMBEDDINGS_API_KEY` export, and the durable slot has been open since 2026-09-26
(`memory-bank/progress.md`, "the durable slot is still open").

It blocks this fix too. Hermes runs under launchd with no login session, so an env export in a
terminal never reaches it, and a keychain item only works if its ACL serves `/usr/bin/security`
without a dialog. **The Vault copy is the source Hermes can rely on.** Write it with the prompted
command in `docs/guides/vector-store.md`, "Writing the Vault copy", then run the catch-up.

Two notes for the implementation:

- A missing credential makes `index-docs` print `unavailable` and exit non-zero. `_refresh_index`
  records it as `last_result{result="failed"}` and logs the first line of the error, so
  `VectorDBIndexFailing` fires within 30 minutes instead of drift growing silently. It is not
  `paused`: waiting for 00:00 UTC does not fix it.
- The Vault copy lives in the hub's Vault, so it is lost on a hub rebuild, as the cosign key was
  (`2026-09-29-hub-rebuild-loses-cosign-signing-key.md`). Unlike cosign there is no Keychain backup
  for bring-up to restore from, so after a rebuild the operator re-runs the Vault write. The
  `VectorDBIndexFailing` alert is how that surfaces.

**Where the dashboard lives:** *k3dm VectorDB Health* is deployed to the **app-cluster** Grafana by
`grafana-dashboards-acg`, and its data arrives through the M4's `localhost:9091` Pushgateway forward.
That forward points at whichever app cluster was last brought up. On 2026-09-29 it pointed at an
expired ACG sandbox and every panel was empty until a hostinger refresh re-pointed it. The ingestion
panels share that dependency; the hub-vs-app-cluster placement of hub-owned metrics is a separate issue.

## Verification (Claude, 2026-09-30)

Verified independently rather than from the report. `29b7f55c` touches only files the brief allows;
`make test-pytest` 415/415 and `vectordb_rules.bats` 8/8 as committed. The brief's mutations (read the
working tree with a ref, always re-index, store the fingerprint on failure, push under
`k3dm-vectordb`) each went red. Brief test 1 (parity on at least 500 docs), test 4's pause case,
test 5, and test 7's push-failure case were not written. The fixtures held four docs.

**Four defects found and fixed:**

1. **`iter_corpus(ref=…)` deadlocks on the real corpus.** `_batch_contents` wrote every object ID
   to `git cat-file --batch` before reading any output. Once the IDs pass the pipe buffer (64 KiB,
   about 1,600 docs at 41 bytes each), both processes block writing: us on stdin, git on stdout. On
   this repo (1,728 docs), `iter_corpus(".", "HEAD")` never returned (killed at 60 s). In Hermes,
   every changed-corpus poll would have held `index-docs` for its full 900 s timeout and indexed
   nothing, and the metrics step would have hung too. Fix: one request, one read, same single
   process. Real corpus: 0.43 s, identical to the working-tree read. Regression test: a 2,000-doc
   repo with `archive/` subtrees and non-corpus files, run under a 60 s watchdog. Codex's function
   fails it.
2. **Drift counted from the wrong tree.** Hermes' per-poll `k3dm-vectordb-metrics` ran without
   `K3DM_INDEX_REF`, so `corpus_docs` came from the M4's working tree while the store followed
   `origin`. The M4 is often behind (it was 3 commits behind on 2026-09-30), so `VectorDBIndexDrift`
   would fire on a correct index. Fix: `_refresh_index` records the ref and the health step passes it.
3. **Any output containing "paused" was a quota pause.** `"paused" in output.lower()` also matches
   a failure that names a path such as `…-monitoring-paused.md`, which would silence indexing until
   midnight UTC. Fix: match the indexer's own `index-docs: paused` prefix.
4. **The existing `VectorDBIndexStale` rule was broken, and so was the whole PrometheusRule.** Its
   `annotations:` was re-indented under `labels:`, giving a label `annotations: null`. kubeconform
   against the PrometheusRule CRD schema rejects it (`labels/annotations … expected string, but got
   null`), so none of the four vectordb alerts would load. The brief said to keep that rule as it is.
   Also, the Ingestion row nested its six panels inside an expanded row with no `gridPos`, and the
   brief's colours, thresholds and date format were missing. Fixed: panels flattened below the row
   with layout; result colours (success/noop green, paused orange, failed red); age amber > 1 h and
   red > 6 h; paused-until as a date, with 0 shown as "not paused".

Tests added: realistic-size parity; pause until next UTC midnight and no run before it; a failure
naming a "paused" path stays `failed`; backlog > 0 leaves the fingerprint unset; Hermes never
issues pull/checkout/switch/reset/merge/rebase; a push failure keeps the outcome; health metrics get
the indexed ref; every rule has string labels and its own annotations; the expanded row nests
nothing. Mutations: Codex's `_batch_contents`, the loose "paused" match, dropping the ref from
health metrics, storing the fingerprint with a backlog, Codex's rules file and Codex's dashboard
each went red. `make test-pytest` 423/423; `vectordb_rules.bats` 9/9.
