# Active Context — k3d-manager

## Current Branch: `k3d-manager-v1.1.0` (as of 2026-04-20)

Renamed from `recovery-v1.1.0-aws-first` (2026-04-20). Old `k3d-manager-v1.1.0` (the messy branch)
preserved as `k3d-manager-v1.1.0-backup` on remote.

**v1.1.0 goal** — Unified ACG automation for AWS + GCP: shared vars, unified robot engine,
GCP identity/credential flow, docs alignment. All four phases complete. GCP cluster
provisioning is the remaining open item (next task on this branch).

## Completed (v1.1.0 Recovery)

| Task | Commit | Summary |
|---|---|---|
| Shared playwright vars | `3de58f4d` | `vars.sh` reconciled; sourced from `acg.sh` |
| Robot engine unification | `a986d5bb` | `acg_credentials.js`: CDP disconnect, `--provider` flag, IPv4, patient sign-in |
| GCP identity bridge | `9686e5c3` | `gcp.sh` plugin, `gcp_login.js` OAuth automation, `bin/acg-up` provider dispatch, core allowlist |
| Documentation alignment | `7f3bd0a6` | README + howto guides aligned to 127.0.0.1/vars.sh |
| GCP cluster provisioning | `c65f0c90` | Firewall, GCE instance, k3sup, functional E2E (timeout fix included) |
| GCP latch-on hardening | `e45d9a04` | `gcp_login.js` hardened with "Agree and continue" + "Confirm" buttons |

## Next Task: GCP cluster provisioning

**Status:** ASSIGNED TO GEMINI — spec committed `2d8a3607` (2026-04-20).
**Spec:** `docs/bugs/2026-04-20-gcp-provisioning-missing.md`
**Sandbox topology:** zone `us-west1-a`, SSH key `~/.ssh/k3d-manager-gcp-key`, user `ubuntu`,
machine `e2-standard-2`, image `ubuntu-2004-lts`, single-node, project from `$GCP_PROJECT`.

Provisioning steps (spec):
1. `gcloud compute firewall-rules create k3d-manager-k3s-api` — open port 6443
2. `gcloud compute instances create k3d-manager-gcp-node` — e2-standard-2, ubuntu-2004-lts
3. SSH config update (`~/.ssh/config`) + `_gcp_wait_for_ssh`
4. `k3sup install` — bootstrap k3s on remote node
5. Merge kubeconfig as context `ubuntu-gcp`, wait for node Ready, label node
**Commit message:** `feat(gcp): implement GCP cluster provisioning — firewall, GCE instance, k3sup, kubeconfig`

## Open Items

- **GCP cluster provisioning** — see Next Task above
- **Whitespace enforcement** — `_agent_lint` needs trailing-whitespace detection for `.js`/`.sh` files
  (lib-foundation v0.3.17 shipped glob expansion; whitespace rule is a follow-up)
- **SSH tunnel timeouts** — connection resets during heavy ArgoCD sync (infra, non-blocking)
