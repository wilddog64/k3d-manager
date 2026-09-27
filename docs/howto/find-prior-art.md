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
         Bugfix: v1.4.5 — eso-ldap-directory Vault policy missing keycloak/* paths
```

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

From Slack, the same search is `/k3dm find-similar-docs Q=...` (reader role). `Q` is restricted to
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
