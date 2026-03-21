# Issue: App cluster deploy required manual Gemini rebuild

**Date:** 2026-03-22
**Owner:** Codex

## Summary

`bin/acg-sandbox.sh` provisions the EC2 instance but leaves k3s install + kubeconfig merge as a
manual Gemini task. After each rebuild we had to:

1. Run `k3sup install ...` by hand
2. Copy the kubeconfig locally and merge it into `~/.kube/config`
3. Remember to instruct operators to fetch the ArgoCD bearer token

Mistakes here repeatedly blocked the ubuntu-k3s cluster recovery steps.

## Fix

Add `deploy_app_cluster` to `scripts/k3d-manager` (shopping_cart plugin). The command:
- Installs k3s via k3sup (disabling Traefik + ServiceLB)
- Waits for the node to become Ready
- Merges the remote kubeconfig into `~/.kube/config` under the `ubuntu-k3s` context
- Prints follow-up steps (rest of bearer token + ArgoCD registration)

`bin/acg-sandbox.sh` now points to this command instead of the manual rebuild spec.

## Follow-up

- Future: wire `deploy_app_cluster` into the acg-sandbox provisioning flow automatically
  once the EC2 resizing work for v1.0.0 (3-node k3sup install) is complete.
