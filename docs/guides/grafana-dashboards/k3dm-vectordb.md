# k3dm VectorDB Health (`k3dm-vectordb`)

[← Grafana dashboards index](../grafana-dashboards.md)

The hub dashboard reports the latest VectorDB publisher snapshot and daily retrieval probe. Its
four rows answer: **Infrastructure health** (is pgvector available and accepting queries?), **Data
consistency** (are indexed documents synchronized with the repository?), **Retrieval quality** (do
agents retrieve the correct, current documents?), and **Ingestion** (what work did the indexer do?).

The Retrieval quality row shows recall@5 against each directory's floor, hard-negative
intrusion@5, stale plus deleted returned rows, and time since the last successful probe. Hermes
runs it after a successful or no-op index refresh, at most once per day.

| Panel | Metric | Meaning |
|---|---|---|
| Rows vs corpus docs (last published) | `k3dm_vectordb_rows`, `k3dm_vectordb_corpus_docs` | Indexed rows compared with expected corpus documents. |
| Drift docs by kind (last published), panel 2 | `k3dm_vectordb_drift_docs_by_kind{kind=...}` | Missing: corpus path absent from index; stale: path in both with different hashes; deleted: index path absent from corpus. |
| Oldest drift (last published), panel 5 | `max(k3dm_vectordb_oldest_drift_age_seconds)` | Age of the oldest drifted document, from the first exporter run that saw it. |
| Index age (last published) | `time() - k3dm_vectordb_last_index_timestamp_seconds` | Age of the most recent index. |
| Reachability and ExternalSecret sync | `k3dm_vectordb_reachable`, `k3dm_vectordb_external_secret_synced` | Last observed connection and credential-sync states; 1 is healthy and 0 is not. |
| Last run result | `k3dm_vectordb_index_last_result` | Last index result (success, noop, paused, or failed). |
| Time since last successful index | `time() - k3dm_vectordb_index_last_success_timestamp_seconds` | Age since a successful indexing run. |
| Paused on daily quota until | `k3dm_vectordb_index_paused_until_timestamp_seconds` | Quota pause expiry, or “not paused”. |
| Docs embedded / from cache / pruned per run | `k3dm_vectordb_index_embedded_last`, `k3dm_vectordb_index_from_cache_last`, `k3dm_vectordb_index_pruned_last` | Work completed by the last run. |
| Backlog | `k3dm_vectordb_index_backlog_docs`, `k3dm_vectordb_drift_docs` | Pending and drifted documents. |
| Run duration | `k3dm_vectordb_index_duration_seconds` | Duration of the last indexing run. |
| Recall@5 by directory | `k3dm_vectordb_retrieval_recall_at5{directory}` and `k3dm_vectordb_retrieval_recall_floor{directory}` | Share of labelled positive pairs retrieved in the top five and that directory's floor. |
| Hard-negative intrusion@5 | `k3dm_vectordb_retrieval_intrusion_at5{directory}` | Share of labelled hard-negative pairs retrieved in the top five. |
| Outdated results | `k3dm_vectordb_retrieval_stale_hits` + `k3dm_vectordb_retrieval_deleted_hits` | Returned rows whose content hash differs from the indexed corpus or whose path has been deleted. |
| Time since last retrieval probe | `k3dm_vectordb_retrieval_probe_last_success_timestamp_seconds` | Age of the last completed daily probe; green below 24 hours, yellow from 24 to 48 hours, and red at 48 hours or more. |

Prometheus alerts on recall below floor for one hour, outdated results for one hour, or a probe
that has not succeeded in 48 hours. The probe uses about 52 query embeddings per run. See
[the VectorDB guide](../vector-store.md#measuring-retrieval-quality) for the live test command and
operator response.

Values are the latest published snapshot, not a live query of the vector store. A stale age or
missing data points to the publisher or Pushgateway path. See [the VectorDB guide](../vector-store.md)
for indexing operations and [the shared producer chain](shared-operations.md#the-producer-chain).
