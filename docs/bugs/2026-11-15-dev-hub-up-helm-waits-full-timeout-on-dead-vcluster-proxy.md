# Bug: dev-hub-up recovery waits out Helm's full 10 m timeout when the vCluster proxy dies

**Status:** OPEN — captured 2026-11-15 by Claude
**Priority:** P3
**Waiting on:** operator decision
**Introduced by:** pre-existing
**Should have been caught by:** live check
**Prior art:** exact-slug glob: none; find-similar-docs not run (vector store unreachable); parent `docs/bugs/2026-11-14-dev-hub-up-helm-wait-dies-with-vcluster-proxy-after-syncer-restart.md` (E5 attempt 3, where this was seen)

## Symptom

E5 of the parent bug (M5, 2026-11-15): the syncer pod was deleted at 02:17:17Z while `helm upgrade --install argocd
... --wait --timeout 10m` ran. The background proxy on 127.0.0.1:11444 died with it, but Helm only failed with
`context deadline exceeded: kubernetes cluster unreachable ... connection refused` at its deadline; the refresh-and-retry
(`scripts/plugins/dev_hub.sh:94`) then succeeded and argocd deployed at 02:27:21Z. Recovery works but costs about 10
minutes instead of seconds.

## Direction (not specced)

Watch proxy liveness during the Helm wait (probe the vCluster `/version` endpoint every few seconds alongside the Helm
process) and stop Helm early when it is refused for a sustained window, then take the existing refresh path. Needs proof
of how Helm v4 behaves on SIGTERM mid-wait before a spec.
