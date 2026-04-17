# Active Context — k3d-manager

## Current Branch: `k3d-manager-v1.1.0`

Earlier branch/milestone context through `v1.0.7` is archived in `memory-bank/archive/activeContext-pre-v1.1.0.md`.

## v1.1.0 — GCP Full Stack Provision (branch: `k3d-manager-v1.1.0`)

**Active branch:** `k3d-manager-v1.1.0`

### Completed

| Item | SHA | Notes |
|---|---|---|
| `_ensure_k3sup` auto-install helper | `c322e483` | Follows `_ensure_gcloud` pattern; brew → curl fallback |
| `_gcp_load_credentials` helper | `a7195034` | Caches SA key; skips Playwright if key valid on disk |
| SA key cache simplification | `5e7566b8` | Single condition: file exists + project_id valid |
| `gcp_login` + `gcp_grant_compute_admin` | `153fc922` | Three-tier gcloud auth; IAM grant helper |
| `gcp_provision_stack` spec | `2745e57b` | `docs/plans/v1.1.0-gcp-provision-full-stack.md` |
| `gcp_provision_stack` implementation | `1430b47e` | Codex; Makefile case dispatch + full 7-step stack |
| Bug spec: ssm prereq + vault unbound $1 | `04943cdd` | COMPLETE — both fixes already in code (Makefile + vault.sh) |
| Makefile GCP up-target spec | `ae747192` | COMPLETE — `Makefile` now runs `deploy_cluster && gcp_provision_stack` from `make up CLUSTER_PROVIDER=k3s-gcp`; `sync-apps` is a GCP no-op; `provision` is AWS-only again |

### In Progress

| Item | Assignee | Spec |
|---|---|---|
| _(none — smoke test is next)_ | — | — |

### Pending
- **GCP IAM auto-grant** — HYBRID+ STRATEGY (`docs/plans/v1.1.0-gcp-iam-hybrid-plus.md`). Final strategy after exploring CLI and full-automation dead ends. Utilizes Chrome (now system default) with automated consent handling and surgical IAM binding via Playwright CDP latch-on. Secure stdin injection for credentials.
- Live smoke test: `make up CLUSTER_PROVIDER=k3s-gcp GHCR_PAT=<pat>` against running GCP node
- **ESO deploy_eso bugfix** — COMPLETE (`320ae211`). `docs/bugs/v1.1.0-bugfix-eso-deploy-unbound-arg.md` — `deploy_eso` now guards `$1` with `${1:-}` so gcp_provision_stack can call it without args under `set -u`; shellcheck + BATS re-run.
- **Stale SA key bugfix** — COMPLETE (`acfb0470`). `_gcp_load_credentials` probes cached project via `gcloud projects describe`; deletes key + re-extracts on new sandbox.
- **SSH readiness probe bugfix** — COMPLETE (`de83535d`). `docs/bugs/v1.1.0-bugfix-gcp-ssh-readiness-probe.md`; `_provider_k3s_gcp_deploy_cluster` now polls `nc -z ${ip} 22` (10s backoff, 30 retries) after `_gcp_ssh_config_upsert` so `k3sup install` waits for SSH to come up.
- **Stale kubeconfig merge bugfix** — COMPLETE (`fb694ac6`). `docs/bugs/v1.1.0-bugfix-gcp-kubeconfig-stale-merge.md`; `_provider_k3s_gcp_deploy_cluster` now deletes the k3s-gcp context/cluster/user from `~/.kube/config` before merging so new k3sup credentials win after an IP change. Reran shellcheck + BATS.
- **k3s API server readiness probe** — COMPLETE (`afbcc44b`). Spec `docs/bugs/v1.1.0-bugfix-gcp-k3s-api-readiness-probe.md`; `_provider_k3s_gcp_deploy_cluster` now polls `nc -z ${external_ip} 6443` (10s backoff, 30 retries) between kubeconfig merge and `kubectl label` so labeling waits for the API server.
- **make provision depends on make up** — COMPLETE (`050160d9`). `docs/bugs/v1.1.0-bugfix-gcp-provision-depends-on-up.md`; Makefile now runs `$(MAKE) up CLUSTER_PROVIDER=...` before `gcp_provision_stack` so the cluster is guaranteed up before provisioning; BATS re-run.
- **deploy_argocd not loaded + invalid flag** — COMPLETE (`17d16e8c`). Spec `docs/bugs/v1.1.0-bugfix-gcp-deploy-argocd-not-loaded.md`. `gcp_provision_stack` now sources `argocd.sh` before calling `deploy_argocd`, removes the invalid `--skip-ldap` flag, and clears the EXIT trap so `rendered` is deleted immediately; `shellcheck scripts/plugins/gcp.sh` + `bats scripts/tests/providers/k3s_gcp.bats` pass.
- **ArgoCD rendered unbound EXIT trap bugfix** — COMPLETE (`17d16e8c`). Spec `docs/bugs/v1.1.0-bugfix-argocd-rendered-unbound-exit-trap.md`. Replaced RETURN trap with explicit `rm -f "$rendered"` + `trap - EXIT`; dangling EXIT trap no longer fires with unbound local after function returns.
- **ACG AWS functions wrong plugin** — COMPLETE (`b5f9754b`). 9 AWS-specific functions + constants moved from `acg.sh` to `aws.sh`; no circular dep since `acg.sh` already sources `aws.sh`.
- **GCP pre-flight stale project bug** — COMPLETE (`acfb0470`). `_gcp_load_credentials` probes cached project via `gcloud projects describe`; deletes key + re-extracts when sandbox changes.
- **GCP provider missing status command** — COMPLETE (`00b1b8c7`, `bf156657`). Added `_provider_k3s_gcp_status` plus top-level `status()` dispatcher so `make status CLUSTER_PROVIDER=k3s-gcp` runs gcloud describe + kubectl nodes/pods.
- **PLAN — `_kubectl` consistency sweep** — OPEN. Replace bare `kubectl` calls in runtime modules (scripts/lib/providers, scripts/plugins, scripts/lib system helpers) with `_kubectl`. Steps: 1) inventory hits via `rg -n '(?<!_)kubectl'` excluding bin/Makefile/docs; 2) refactor providers (k3s-aws/gcp) + high-traffic plugins (acg, vault, argocd, jenkins, shopping_cart) in batches with shellcheck+tests; 3) sweep shared libs; 4) add `_agent_audit` lint to block future raw usage. docs/plans entry TBD (check plan-count limit first).
- **PLAN — GCP IAM Hybrid+** — UPDATED (`docs/plans/v1.1.0-gcp-iam-hybrid-plus.md`). Plan now documents CDP port bootstrap, identity guard selectors, IAM UI steps, fallback exit codes, and verification gates so Gemini automation doesn’t misfire.
- **GCP topology parity gap** — OPEN (`docs/bugs/2026-04-13-gcp-single-node-topology-mismatch.md`). `k3s-gcp` provisions one node instead of the standard 3-node cluster shape used by AWS; provider should match server + 2 agents.
- **Provider Make lifecycle inconsistency** — OPEN (`docs/bugs/2026-04-13-provider-make-target-inconsistency.md`). `make up` / post-cluster bootstrap flow diverges between AWS and GCP; all providers should share one lifecycle contract.
- **Provider SSH alias inconsistency** — OPEN (`docs/bugs/2026-04-13-provider-ssh-alias-inconsistency.md`). SSH aliases should be standardized across providers (`ubuntu-tunnel`, `ubuntu-1`, `ubuntu-2`) with dynamic IP refresh.
