# dev-hub-sync without a dev hub fails with a raw kubeconfig stat error

**Status:** OPEN — captured 2026-11-13
**Priority:** P3 (Claude proposal: error wording only; the operation correctly fails)
**Classified:** pending (Argon, from this doc alone)
**Waiting on:** operator decision — since 2026-11-13
**Introduced by:** pre-existing (dev-hub B, `scripts/plugins/dev_hub.sh` `dev_hub_sync`)
**Should have been caught by:** spec
**Prior art:** exact-slug glob, no match; `make find-similar-docs` unavailable (vector store context `k3d-k3d-cluster` missing)

## Symptom

On m5-air, 2026-11-13, after the promote of 9a579a05, `make dev-hub-sync` with no dev hub up printed:

    error: stat /Users/cliang/.kube/vclusters/dev-hub.yaml: no such file or directory
    ERROR: failed to execute kubectl --kubeconfig /Users/cliang/.kube/vclusters/dev-hub.yaml apply -f /tmp/k3dm-dev-hub-appset.XXXX: 1

## Cause

`dev_hub_sync` goes straight to `_dev_hub_child_kubectl apply` without checking that the dev hub exists or that `DEV_HUB_KUBECONFIG` is present. The plan's E2 sequence runs `make dev-hub-up` first; the sync was run alone.

## Fix

Before rendering, if `DEV_HUB_KUBECONFIG` is missing (or `_dev_hub_cluster_exists` is false), `_err "dev-hub-sync: no dev hub found; run make dev-hub-up first"`. One bats test: missing kubeconfig → that message, no kubectl call; positive control: present kubeconfig → apply called.
