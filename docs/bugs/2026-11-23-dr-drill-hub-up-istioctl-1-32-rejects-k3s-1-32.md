# Bug: `make dr-drill` (and any fresh `hub-up`) fails: unpinned Homebrew istioctl 1.32 rejects the pinned k3s v1.32 image

**Status:** OPEN — captured 2026-11-23 by Claude from the operator's m2-air run
**Priority:** P2 (operator, 2026-11-23; flagged — it blocks the DR drill and a from-scratch hub rebuild on this Mac)
**Triage:** patch → v1.45.1 (operator, 2026-11-23); pin target: match the live hub — corrected 2026-11-23 to k3s v1.32.0 + Istio 1.31.x (pin 1.31.4, the first CVE-free 1.31; hub's 1.31.1 to be raised to match)
**Branch:** k3d-manager-v1.45.1
**Introduced by:** pre-existing (istioctl never pinned); exposed by Homebrew upgrading istioctl to 1.32.0 on m2-air 2026-11-12
**Should have been caught by:** live check (the weekly drill; not run 2026-11-04 → 2026-11-23)
**Introducing change reviewed:** no
**Waiting on:** dispatch — since 2026-11-23 (spec to write)
**Prior art:** `docs/bugs/2026-11-22-istio-ambient-appset-targets-retired-ubuntu-k3s.md` (exact-slug glob + grep; vector store unavailable) — read, different root cause; `CHANGELOG.md:2565` — recurrence: k3s was raised to v1.32.0-k3s1 in July "to satisfy the istioctl precheck floor" (same class)
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
- **Live hub** (m5-air, context `k3d-k3d-cluster`, read-only 2026-11-23 by Claude): server `v1.32.0+k3s1`, istiod
  `docker.io/istio/pilot:1.31.1`. It matches the template's k3s pin. (Correction: an earlier line here recorded the m2-air
  cluster, `v1.31.5+k3s1` + Istio 1.28.3, as the hub; that is an older cluster, not the hub. Its Istio 1.28 is past
  end of life, Jul 1 2026.)
- istio.io supported-releases, read verbatim 2026-11-23 (no last-updated date on the page): 1.31 → k8s 1.32–1.37,
  EOL ~Mar 2027, no known CVEs from 1.31.4; 1.32 → k8s 1.33–1.37; 1.28 → 1.30–1.34, EOL Jul 1 2026.

## Workaround (untested)

Put an istioctl whose support range includes Kubernetes 1.32 ahead of `/opt/homebrew/bin` for the drill only, from the
official Istio release archive, and re-run `make dr-drill` in Terminal.

## Fix direction (operator decision)

1. Pin istioctl: a version variable, install or verify that version, refuse a PATH istioctl of another minor (upstream
   in lib-foundation first; repo rule A08 pins). And/or
2. Bump `rancher/k3s` in `cluster.yaml.tmpl` to a supported 1.33+ tag — but the drill must rebuild what the live hub
   runs, so first record the hub's server version and Istio version (read-only) and match them.

Either way the istioctl that `hub-up` uses should be the version the live hub's control plane runs.

## Triage input (2026-11-23; decision pending with the operator)

- **Fable (blind, from this doc and the repo):** P2; `patch → v1.45.1`. Pin istioctl from the tagged release archive with
  checksum, refuse a PATH istioctl of another minor; lib-foundation first, then the local `scripts/lib/core.sh` (sourced
  last, `scripts/k3d-manager:81-86`, so it is the live definition). `_istioctl install` (`k3d.sh:106`, `k3s.sh:90`)
  also picks the control-plane version; no hub Istio version is pinned anywhere. Carry any k3s bump to v1.46.0.
  Proposed 1.31.4 (istio.io supported-releases, fetched through a summary 2026-11-23: 1.31 → k8s 1.32–1.37).
- **Claude:** P2 agreed. Fable did not see the live versions: the hub runs k8s 1.31.5 + Istio 1.28.3, which a
  1.31.x pin would not match (1.31 does not list k8s 1.31). The pin choice is either "match the hub" (1.28.x, if its
  range covers the drill's k3s) or "pin forward" (1.31.x) with a hub upgrade in v1.46.0. Re-read the istio.io table
  directly before the spec.
- Adjacent, not this bug (Fable): ambient Istio pinned at an end-of-life 1.24.2 (`scripts/etc/argocd/vars.sh:76`); k3d
  installed from `k3d-io/k3d` `main` unpinned (`scripts/lib/providers/k3d.sh:75`).
