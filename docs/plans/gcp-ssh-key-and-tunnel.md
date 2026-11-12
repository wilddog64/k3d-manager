# GCP provider 2/4 — SSH key, firewall and the hub tunnel for k3s-gcp

**Status:** PLANNED — ordered backlog (unnumbered); second of the four GCP provider plans
**Approval:** operator, 2026-11-12 ("let's get GCP provider plans into roadmap")
**Intent approved:** pending
**Branch:** unassigned (release chosen at grooming)
**Depends on:** `docs/plans/gcp-auth-without-oauth-clickthrough.md` (gcloud must authenticate first)
**Related:** Fable and Argon GCP reviews 2026-11-12

## Goal

A k3s-gcp node is reachable from the hub the same way a k3s-aws node is: over SSH, through the tunnel that carries
the API (`-L 16443:127.0.0.1:6443`) and the reverse Vault bridge (`-R 8201:127.0.0.1:18200`, `scripts/plugins/tunnel.sh:149`).

## Gaps today

- Nothing generates `~/.ssh/k3d-manager-gcp-key{,.pub}`; `k3s-gcp.sh:34,196-203` fails unless it already exists.
- The only firewall rule is `tcp:6443` (`k3s-gcp.sh:41-55`); SSH relies on the default network's rule.
- `bin/cluster-up:581` skips Step 3 `tunnel_start` for GCP, while `bin/cluster-refresh:219-228` starts it, so up and
  refresh disagree. `k3sup` writes the public IP into `~/.kube/k3s-gcp.yaml` and ArgoCD's
  `https://host.k3d.internal:16443` (`bin/cluster-up:1009`) has nothing behind it.

## Scope

1. Generate an ed25519 key if absent (0600), and pass it to the VM's metadata.
2. A `tcp:22` firewall rule scoped to the operator's egress IP, not `0.0.0.0/0`.
3. `k3sup install --tls-san 127.0.0.1 --tls-san host.k3d.internal` (`k3s-gcp.sh:135`); run Step 3 `tunnel_start`
   for k3s-gcp; rewrite the kubeconfig server to `https://127.0.0.1:16443`.

## Files

`scripts/lib/providers/k3s-gcp.sh`, `bin/cluster-up` (Step 3 guard only), `scripts/plugins/tunnel.sh` if the host
alias is hardcoded, a new `scripts/tests/lib/k3s_gcp_provider.bats` (no test covers `k3s-gcp.sh` today).

## Live evidence (when specced)

`kubectl --context ubuntu-gcp get nodes` through `127.0.0.1:16443`; `nc -z localhost 8201` run on `ubuntu-gcp`.
