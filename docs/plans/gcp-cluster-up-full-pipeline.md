# GCP provider 3/4 — cluster-up runs steps 5–12 for k3s-gcp; no hardcoded `ubuntu` / `ubuntu-k3s`

**Status:** PLANNED — ordered backlog (unnumbered); third of the four GCP provider plans
**Approval:** operator, 2026-11-12 ("let's get GCP provider plans into roadmap")
**Intent approved:** pending
**Branch:** unassigned (release chosen at grooming)
**Depends on:** `docs/plans/gcp-ssh-key-and-tunnel.md` (the Vault bridge and ArgoCD reach need the tunnel)
**Related:** `docs/bugs/2026-07-07-app-cluster-vault-portability.md` (same hardcoded `ubuntu-k3s` context, from the
app-cluster side; read it first, it may share the parameter); Fable and Argon GCP reviews 2026-11-12

## Goal

`make up CLUSTER_PROVIDER=k3s-gcp` deploys the full app cluster, not just a node. Today `bin/cluster-up:909-914`
prints "Steps 5–12 not yet ported for GCP" and exits 0, skipping GHCR secrets, the Vault bridge, ESO, ArgoCD
registration, the data layer, Keycloak and LDAP, the shopping-cart apps, ACG observability, the TTL watcher and
`_acg_record_provider`.

## Scope

1. Remove the early exit.
2. One SSH-host and one kube-context variable per provider, replacing the literals at `shopping_cart.sh:120-146,549,
   992-1050`, `bin/cluster-up:419,446,923,1519,1582,1593-1595`, `bin/cluster-refresh:531` and the `argocd-registration`
   target (`Makefile:388-402`). Re-grep at spec time: line numbers drift.
3. k3s-aws behaviour must not change: its offline tests and one k3s-aws `make up` are part of the evidence.

## Out of scope

Two agent nodes (AWS runs 1 server + `ACG_AGENT_COUNT` agents with Cilium; GCP runs one `e2-standard-2`). That is
a follow-up plan once one node works end to end.

## Live evidence (when specced)

A full `make up CLUSTER_PROVIDER=k3s-gcp` with every ArgoCD app `Synced`/`Healthy`, and
`~/.local/share/k3d-manager/acg-state.json` recording `k3s-gcp`.
