# bin/get-ldap-password: the Vault root token assignment is printed when the script runs under `bash -x`

**Status:** OPEN — captured 2026-11-17 from Argon's blind review of PR #162 (v1.44.1), verified by Claude
**Priority:** P3 — only when someone runs the script with xtrace; the script never enables it itself
**Introduced by:** pre-existing (line identical on main)
**Should have been caught by:** review
**Introducing change reviewed:** unknown
**Waiting on:** operator decision
**Prior art:** none above threshold. Exact slug: no match; keyword grep of docs/bugs: no match. `make find-similar-docs` not run (vector store unreachable from this machine: no k3d-k3d-cluster context).
**Filed:** 2026-11-17

## Symptom

`bin/get-ldap-password:121` assigns `VAULT_TOKEN=$(kubectl get secret … | base64 -d)` outside `_no_trace`. Under `bash -x` (or `SHELLOPTS=xtrace`) bash prints `+ VAULT_TOKEN=<root token>` to stderr. `scripts/lib/test.sh` wraps the same read in `_no_trace`.

## Verified by Claude (2026-11-17)

`bash -c 'set -x; T=$(echo s3cr3t); cat <<<"$T"'` prints `+ T=s3cr3t` and then only `+ cat`: the assignment leaks, the here-string feeding `kubectl exec` (the v1.44.1 fix, 2f8bd1ae) does not. `git show main:bin/get-ldap-password` has the same line 121.
