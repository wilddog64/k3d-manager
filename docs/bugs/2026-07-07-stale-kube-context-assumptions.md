# Bug: Stale kube context assumptions

**Filed:** 2026-07-07
**Source:** /ask agent observation

## Description

The current machine does not have a local `ubuntu-k3s` kube context, but the repo still hardcodes it in multiple operational paths, including [bin/k3dm-webhook](/Users/cliang/src/gitrepo/personal/k3d-manager/bin/k3dm-webhook:95), [scripts/lib/provider.sh](/Users/cliang/src/gitrepo/personal/k3d-manager/scripts/lib/provider.sh:94), and [bin/cluster-up](/Users/cliang/src/gitrepo/personal/k3d-manager/bin/cluster-up:611). That is a real drift issue and makes diagnostics/reporting inaccurate after the Hostinger migration.

**Consolidated into:** [App-cluster Vault portability design spec](./2026-07-07-app-cluster-vault-portability.md) — see there for verified findings, phased plan, and open decisions.
