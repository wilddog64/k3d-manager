# Active Context — k3d-manager

## Current Branch: `k3d-manager-v1.1.0` (as of 2026-04-20)

Renamed from `recovery-v1.1.0-aws-first` (2026-04-20). Old `k3d-manager-v1.1.0` (the messy branch)
preserved as `k3d-manager-v1.1.0-backup` on remote.

**v1.1.0 goal** — Unified ACG automation for AWS + GCP: shared vars, unified robot engine,
GCP identity/credential flow, docs alignment. All four phases complete. GCP cluster
provisioning is the remaining open item (next task on this branch).

## Completed (all phases done)

| Phase | Commit | Summary |
|---|---|---|
| A — shared vars | `3de58f4d` | `vars.sh` reconciled; sourced from `acg.sh` |
| B — robot engine | `a986d5bb` | `acg_credentials.js`: CDP disconnect, `--provider` flag, IPv4, patient sign-in |
| C — GCP identity | `9686e5c3` | `gcp.sh` plugin, `gcp_login.js` OAuth automation, `bin/acg-up` provider dispatch, core allowlist |
| D — docs | `7f3bd0a6` | README + howto guides aligned to 127.0.0.1/vars.sh |

## Next Task: GCP cluster provisioning

**Status:** OPEN — `scripts/lib/providers/k3s-gcp.sh` is a skeleton (placeholder functions only).
**Spec:** `docs/bugs/2026-04-20-gcp-provisioning-missing.md`
**Blocked on:** need live ACG GCP sandbox to determine zone, machine type, SSH key pattern.

Provisioning steps to implement:
1. `gcloud compute firewall-rules create` — open port 6443
2. `gcloud compute instances create` — provision GCE instance(s)
3. `k3sup install` — bootstrap k3s on remote node
4. SSH config update + tunnel equivalent
5. Wait for nodes Ready + label nodes

## Open Items

- **GCP cluster provisioning** — see Next Task above
- **Whitespace enforcement** — `_agent_lint` needs trailing-whitespace detection for `.js`/`.sh` files
  (lib-foundation v0.3.17 shipped glob expansion; whitespace rule is a follow-up)
- **SSH tunnel timeouts** — connection resets during heavy ArgoCD sync (infra, non-blocking)
