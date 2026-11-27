# Bug: the fast gate does not select tests that sed-extract functions from a changed file

**Status:** OPEN — capture
**Priority:** P3
**Introduced by:** pre-existing
**Should have been caught by:** offline test
**Introducing change reviewed:** unknown
**Waiting on:** operator decision — since 2026-11-27
**Prior art:** exact-slug glob: none; `make find-similar-docs` unavailable on m4 (no k3d-k3d-cluster context) — not run
**Filed:** 2026-11-27, Claude, from CI red on `6fa6560a`

## Evidence

- W3 (`ef2dae48`) made `_argocd_deploy_applicationsets` (`scripts/plugins/argocd.sh`) call a new helper,
  `_argocd_ambient_appset_wanted`. `scripts/tests/plugins/argocd_cve_pin_appset.bats` loads only two functions with
  `source <(sed -n '/^function …()/,/^}/p' …/argocd.sh)`, so the helper was undefined in the test and test 4 failed.
- W3's land fast gate (`scripts/ci/fast_gate.sh`) passed; CI shard `test (3)` caught it after push. Fixed in
  `b6c261b3` (test loads the real helper; mutant "helper always skips" turns it red).

## Notes for triage

The gate's file→test mapping does not see a test that reads a plugin through `sed`. Options: treat a `sed -n
'/^function …/' <file>` reference as a dependency on <file>; or a lint that flags a sed-extracted function calling a
same-file `_name` the test neither loads nor stubs.
