# Find prior art before filing a bug or issue doc

The dedup rule in `CLAUDE.md` starts with an exact-slug glob. That catches a re-file only when
whoever files it guesses the same slug as last time. This repo has already refiled the same ESO
defect under a name the glob could not match. Similarity search is the second pass that catches
the near-miss.

## The two-pass check

```bash
# Pass 1 — exact slug. Cheap, offline, authoritative when it hits.
ls docs/bugs/*-eso-403-vault-path.md 2>/dev/null

# Pass 2 — similarity. Advisory; catches the doc filed under a different name.
make find-similar-docs Q="eso 403 on a vault path"
```

Pass 2 never blocks. It exits 0 even when the store is down, the credential is missing or the index
is empty, and says so on stderr — so it can sit in a pre-commit path or an agent workflow without
becoming a new way for filing to fail.

## Reading the output

```
Prior art for: "eso 403 on a vault path"
  0.847  docs/bugs/v1.4.5-bugfix-eso-ldap-policy-missing-keycloak.md
         https://github.com/wilddog64/k3d-manager/blob/k3d-manager-v1.41.0/docs/bugs/v1.4.5-bugfix-eso-ldap-policy-missing-keycloak.md
         Bugfix: v1.4.5 — eso-ldap-directory Vault policy missing keycloak/* paths
```

Each result includes a clickable GitHub link. Links use the checked-out release branch when it is
available, otherwise `main`; set `K3DM_DOCS_BRANCH` to override the branch explicitly. Set
`K3DM_DOCS_REPO_URL` to use a repository mirror or fork.

The score is cosine similarity in `[-1, 1]`; 1.0 is identical text. Rough bands, pending the
v1.40.0 eval that will actually measure this:

| Score | What it means |
|---|---|
| ≥ 0.80 | Very likely the same defect class — **read it before filing** |
| 0.60–0.80 | Related; often the recurrence belongs appended to that file |
| < 0.60 | Probably unrelated |

**A high score means read that file first. It does not mean do not file.** A recurrence of a fixed
bug is worth recording; the question is whether it belongs as a new file or as a `Recurrence`
section appended to the existing one.

## Options

```bash
make find-similar-docs Q="kine compaction stopped" K=10   # more results
scripts/find-similar-docs.py --json "grafana panel is blank"  # machine-readable
```

From Slack, the same search is `/k3dm find-similar-docs Q=<a sentence> [K=n]` (reader role), with
no quotes: `Q` runs to the next `KEY=value` or `confirm`, for example
`/k3dm find-similar-docs Q=mac scheduler cannot find tools K=10`. `Q` is restricted to
letters, digits, spaces and `._,:/?!-`: the value reaches a Makefile recipe where `$(Q)` expands
into a shell command line, so every shell metacharacter is rejected rather than escaped.

## When results look wrong

The index is only as current as the last `make index-docs`. A doc committed since then is not
searchable.

```bash
make index-docs DRY_RUN=1   # how many docs would be embedded / pruned
make index-docs             # bring it current
```

An empty result set with no error means the store is reachable but has no rows — the index was
never built, or the volume was lost. See [the vector store guide](../guides/vector-store.md) for
what is deployed, the credential resolution order, and why losing the volume costs only a re-index.

### Hub rebuilt?

Hermes notices an empty store and re-indexes it on its own within one poll. With the local cache,
that reload costs no embeddings quota, and the vectordb dashboard shows the restored documents as
`from cache`; deleting `~/.cache/k3dm/embeddings.sqlite` only costs re-embedding.

Second copy: the layers are git docs → embedding cache → pgvector, and each layer can be rebuilt
from the one before it. Use `make embed-cache-stats` to inspect the cache and
`make embed-cache-prune` to remove old vectors. After a large index run, copy it to a second
location with `make embed-cache-backup DEST=…`, such as an M2 share or synced folder. On a fresh or
rebuilt Mac, run `make embed-cache-restore SRC=…` before `make index-docs`; restore merges by
content hash and is safe to repeat. `DEST`/`SRC` may be `host:path`, for example `make embed-cache-backup DEST=m2-air:~/.local/backup`.
The copy goes over ssh/scp with the operator's own keys, the directory is created when missing, and
the file lands atomically. Each step retries twice (after 5s and 15s) and ssh keepalives
fail a dead link in about 15 seconds, so a flaky local network leaves the previous backup intact. If the cache holds fewer vectors than the hub store (for example,
a cache created after the store was already full), run `make embed-cache-seed` first: it copies every
store vector whose doc is unchanged into the cache, makes no Gemini calls, and never overwrites a
cached vector. Then take the backup. Time Machine already covers `~/.cache` unless it is excluded;
check that with `tmutil isexcluded`.
