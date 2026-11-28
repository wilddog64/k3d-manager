# Bug: lib-foundation has no bare-negation BATS lint, so `! cmd` assertions that never fail land there

**Status:** OPEN — capture
**Priority:** P3
**Introduced by:** pre-existing
**Should have been caught by:** offline test
**Introducing change reviewed:** unknown
**Waiting on:** operator decision — since 2026-11-27
**Prior art:** exact-slug glob: none; `make find-similar-docs` unavailable on m4 (no k3d-k3d-cluster context) — not run
**Filed:** 2026-11-27, Claude, from the lib-foundation v0.5.12 review (W4)

## Evidence

- In BATS a bare `! cmd` never fails the test (SC2314); `run ! cmd` must be used. k3d-manager's fast gate runs
  `scripts/tests/lib/bats_negation_lint.bats`; lib-foundation has no equivalent.
- W4's lib-foundation tests had bare negations; Claude missed them, Argon caught them in PR #96 review.
- Still present upstream: `scripts/tests/lib/install_istioctl.bats:191-192` in lib-foundation
  (`! _istioctl_pinned_sha256 1.32.0 osx arm64`, `! _istioctl_pinned_sha256 1.31.4 freebsd arm64`).

## Notes for triage

Port the lint to lib-foundation (upstream first, per subtree discipline) and fix the two lines; k3d-manager receives
them on the next subtree pull.
