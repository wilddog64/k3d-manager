# Bug: dev-hub B N1 wording does not allow the read-only `kubectl get nodes` from the unchanged prerequisite check

**Status:** OPEN — captured 2026-11-13 from the independent Acceptance re-verification of dev-hub B at e9c375c4 (Opus verifier)
**Priority:** P3 (spec wording; code is correct)
**Waiting on:** operator decision — since 2026-11-13
**Introduced by:** `65e4799f` (v1.44.0 dev-hub B spec Acceptance)
**Should have been caught by:** spec
**Prior art:** exact-slug glob: none. `make find-similar-docs` not run

## Symptom

`docs/plans/v1.44.0-dev-hub-vcluster.md` N1: "No kubectl or helm call from any dev-hub target uses the hub context without -n dev-hub, except the cluster-scoped PriorityClass". The verifier's stub log shows `kubectl --context k3d-k3d-cluster get nodes` with no namespace. It comes from `_vcluster_check_prerequisites` in `scripts/plugins/vcluster.sh`, which dev-hub B must not change. It is read-only and cluster-scoped. The verifier passed N1 on intent but noted the wording does not list it.

## Fix

Amend N1 to: "… except the cluster-scoped PriorityClass apply and the read-only `get nodes` prerequisite probe in `_vcluster_check_prerequisites`". Spec text only; no code change.
