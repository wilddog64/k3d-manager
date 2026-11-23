# Bug: `make dr-drill` (and any fresh `hub-up`) fails: unpinned Homebrew istioctl 1.32 rejects the pinned k3s v1.32 image

**Status:** OPEN — captured 2026-11-23 by Claude from the operator's m2-air run
**Priority:** P2 (proposed; flagged — it blocks the DR drill and a from-scratch hub rebuild on this Mac; workaround below, untested)
**Introduced by:** pre-existing (istioctl never pinned); exposed by Homebrew upgrading istioctl to 1.32.0 on m2-air 2026-11-12
**Should have been caught by:** live check (the weekly drill; not run 2026-11-04 → 2026-11-23)
**Introducing change reviewed:** no
**Waiting on:** operator decision
**Prior art:** `docs/bugs/2026-11-22-istio-ambient-appset-targets-retired-ubuntu-k3s.md` (exact-slug glob + grep; vector store unavailable) — read, different root cause
**Detected by:** operator, `make dr-drill` on m2-air, 2026-11-23 ~03:55 PST; also explains the failing daily `Hub DR drill freshness` workflow in `wilddog64/k3dm-hub-data` (stale since 2026-11-04 result)

## Evidence

- Drill output: `Error [IST0142] (Cluster) The Kubernetes Version "v1.32.0+k3s1" is lower than the minimum version: 1.33`,
  then `ERROR: failed to execute istioctl x precheck: 1`, `ERROR: [hub-up] Step 1/5 failed: creating local Hub cluster`.
- m2-air (read-only, 2026-11-23): `/opt/homebrew/bin/istioctl -> ../Cellar/istioctl/1.32.0/bin/istioctl` (link dated
  2026-11-12); `istioctl version --remote=false` → `client version: 1.32.0`.
- k3s pin: `scripts/etc/cluster.yaml.tmpl:7` `image: rancher/k3s:v1.32.0-k3s1`.
- Precheck: `scripts/lib/providers/k3d.sh:105` and `scripts/lib/providers/k3s.sh:89` run `_istioctl x precheck`.
- Unpinned istioctl: `scripts/lib/core.sh:457-461` (`_install_istioctl`) accepts any `istioctl` on PATH; when absent it
  installs the latest candidate from `istio/istio` `master` (`downloadIstioCandidate.sh`). Same in
  `scripts/lib/foundation/scripts/lib/core.sh:455` (lib-foundation subtree: upstream first).
- Last good drill 2026-11-04 predates the 2026-11-12 upgrade.

## Workaround (untested)

Put an istioctl whose support range includes Kubernetes 1.32 ahead of `/opt/homebrew/bin` for the drill only, from the
official Istio release archive, and re-run `make dr-drill` in Terminal.

## Fix direction (operator decision)

1. Pin istioctl: a version variable, install or verify that version, refuse a PATH istioctl of another minor (upstream
   in lib-foundation first; repo rule A08 pins). And/or
2. Bump `rancher/k3s` in `cluster.yaml.tmpl` to a supported 1.33+ tag — but the drill must rebuild what the live hub
   runs, so first record the hub's server version and Istio version (read-only) and match them.

Either way the istioctl that `hub-up` uses should be the version the live hub's control plane runs.
