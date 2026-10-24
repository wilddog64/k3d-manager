# k3dm VectorDB Health (`k3dm-vectordb`)

[← Grafana dashboards index](../grafana-dashboards.md)

The hub dashboard reports the latest VectorDB publisher snapshot. Its panels use
`k3dm_vectordb_*` metrics and show corpus alignment, reachability, ExternalSecret sync, and
indexing activity.

| Panel | Metric | Meaning |
|---|---|---|
| Rows vs corpus docs (last published) | `k3dm_vectordb_rows`, `k3dm_vectordb_corpus_docs` | Indexed rows compared with expected corpus documents. |
| Drift docs (last published) | `k3dm_vectordb_drift_docs` | Documents whose indexed content differs from the corpus. |
| Index age (last published) | `time() - k3dm_vectordb_last_index_timestamp_seconds` | Age of the most recent index. |
| Reachability and ExternalSecret sync | `k3dm_vectordb_reachable`, `k3dm_vectordb_external_secret_synced` | Last observed connection and credential-sync states; 1 is healthy and 0 is not. |
| Last run result | `k3dm_vectordb_index_last_result` | Last index result (success, noop, paused, or failed). |
| Time since last successful index | `time() - k3dm_vectordb_index_last_success_timestamp_seconds` | Age since a successful indexing run. |
| Paused on daily quota until | `k3dm_vectordb_index_paused_until_timestamp_seconds` | Quota pause expiry, or “not paused”. |
| Docs embedded / from cache / pruned per run | `k3dm_vectordb_index_embedded_last`, `k3dm_vectordb_index_from_cache_last`, `k3dm_vectordb_index_pruned_last` | Work completed by the last run. |
| Backlog | `k3dm_vectordb_index_backlog_docs`, `k3dm_vectordb_drift_docs` | Pending and drifted documents. |
| Run duration | `k3dm_vectordb_index_duration_seconds` | Duration of the last indexing run. |

Values are the latest published snapshot, not a live query of the vector store. A stale age or
missing data points to the publisher or Pushgateway path. See [the VectorDB guide](../vector-store.md)
for indexing operations and [the shared producer chain](shared-operations.md#the-producer-chain).
