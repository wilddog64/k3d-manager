# dev-hub Part B: dry run still runs commands, and three probe paths are untested

**Status:** OPEN — captured 2026-11-13 from the round-6 cross-model review of dev-hub Part B (Claude)
**Priority:** P3 (proposed: dry-run fidelity and test gaps; the live path behaves correctly)
**Classified:** pending second-agent classification
**Introduced by:** dev-hub Part B (`dev-hub-vcluster-b` dispatch, round 6 correction)
**Should have been caught by:** spec (the round-6 brief said "return 0 right after the host objects", which allows host writes in dry run)
**Prior art:** `docs/bugs/2026-11-12-dev-hub-bats-tmpdir-unset-on-linux-ci.md` (exact-slug glob; vector search unavailable, hub context absent on this machine) — read, different root cause
**Waiting on:** operator decision

## Symptom

From the round-6 review (Fable, 2026-11-13). Each item below was shown in a scratch copy, by an ad hoc test or a mutant left green:

1. `DRY_RUN=1 make dev-hub-up` with an existing vCluster and a missing kubeconfig runs the real
   `_vcluster_export_kubeconfig` (`vcluster connect dev-hub --print`, which writes `dev-hub.yaml`) before the dry-run
   return at `scripts/plugins/dev_hub.sh:166`. Live, that connect probably also starts the proxy container (inferred).
2. A dry run applies the host PriorityClass, namespace, ResourceQuota and LimitRange for real. `scripts/plugins/vcluster.sh:98-99`
   says a dry run must run nothing.
3. Mutants the suite does not catch:
   - The connection refresh skipped on the create path: no test asserts `refresh-connection dev-hub` there (`dev_hub.bats` ~713).
   - The outer DRY_RUN block deleted (`dev_hub.sh:166-170`): the only dry-run test uses the create path.
   - `--request-timeout=5s` removed from the `/readyz` probe.
4. On the create path, a failed reconnect after `vcluster_create` prints "if the vCluster was recreated, remove <kubeconfig>",
   which misleads on a first create (inferred).
5. Nit: the first `vcluster_create` stub in `dev_hub.bats` (~150-168) is dead (overridden at ~190) and has a duplicated block.

## Proposed fix (when chosen)

- In dry run, return before any host write or `vcluster connect` on both paths, printing what would run.
- Add the three missing assertions.
- Word the create-path failure as "proxy not reachable; rerun make dev-hub-up".
