# vault unseal watchdog: an empty shard file makes the shard filter drop every Vault error line

**Status:** OPEN — captured 2026-11-17 from Argon's blind review of PR #162 (v1.44.1), verified by Claude
**Priority:** P3 — needs an empty shard in the vault-unseal Secret; the `rc=` line still shows the failure
**Introduced by:** dd7c18ed (unseal watchdog stage 1, k3d-manager-v1.44.1)
**Should have been caught by:** offline test
**Introducing change reviewed:** unknown
**Waiting on:** operator decision
**Prior art:** none above threshold. Exact slug: no match; keyword grep of docs/bugs: no match. `make find-similar-docs` not run (vector store unreachable from this machine: no k3d-k3d-cluster context).
**Filed:** 2026-11-17

## Symptom

`scripts/etc/vault/unseal-watchdog.yaml.tmpl:72` filters the shard out of Vault's output with `grep -F -v -- "$(cat "$SHARD_FILE")"`. If the file is empty, the pattern is `""`, which matches every line, so all error lines are dropped: the same "error hidden" symptom stage 1 was meant to fix.

## Verified by Claude (2026-11-17)

`printf 'Error: invalid key\n' | grep -F -v -- ""` prints nothing (rc 1). The shard still goes into `vault operator unseal` argv inside the pod; that is pre-existing (main line 69) and outside stage 1.
