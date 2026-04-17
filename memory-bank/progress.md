# Progress — k3d-manager

## Overall Status

History through `v0.9.18` is archived in `memory-bank/archive/progress-pre-v0.9.19.md`.

## v0.9.19 — Active

- [x] **Static acg_credentials.js** — **COMPLETE**. Replaced Gemini-generated Playwright with static `scripts/playwright/acg_credentials.js`. Verified with live Pluralsight sandbox. commit `67a445c`. Spec: `docs/plans/v0.9.19-acg-playwright-script.md`.
- [ ] **scratch/ cleanup** — `rm -f scratch/*`; stale Playwright artifacts from v0.9.18 and earlier
- [ ] **ArgoCD Sync — `order-service` & `product-catalog`** — **FAILED**. Attempted sync on infra cluster; ArgoCD server logged in successfully but app cluster connection failed. Root cause: ACG sandbox credentials expired; SSH tunnel down. See `docs/issues/2026-03-28-argocd-sync-acg-credentials-expired.md`.


## v1.1.0 — GCP Full Stack Provision

**Branch:** `k3d-manager-v1.1.0`

| Item | Status | Notes |
|---|---|---|
| `gcp_provision_stack` + `_gcp_seed_vault_kv` | COMPLETE | SHA `1430b47e` — Codex |
| Makefile `provision` case dispatch | COMPLETE | SHA `1430b47e` — Codex |
| Bug: `provision: ssm` unconditional prereq | COMPLETE | Already in code; `make provision` has no top-level `ssm` prereq |
| Bug: `deploy_vault` bare `$1` unbound var | COMPLETE | Already in code; `vault.sh:901` uses `${1:-}` |
| Bug: Makefile `make up` GCP inconsistency | COMPLETE | SHA `ae747192` — `make up CLUSTER_PROVIDER=k3s-gcp` now runs cluster + stack; `sync-apps` is a GCP no-op; `provision` is AWS-only |
| Remove dead `gcp_grant_compute_admin` + test | ASSIGNED → Codex | `docs/bugs/v1.1.0-bugfix-remove-gcp-grant-compute-admin.md` |
| Live smoke test `make up CLUSTER_PROVIDER=k3s-gcp GHCR_PAT=<pat>` | PENDING | After dead code removal |
- [x] **ESO deploy_eso bugfix** — COMPLETE (`320ae211`). Spec `docs/bugs/v1.1.0-bugfix-eso-deploy-unbound-arg.md`. `scripts/plugins/eso.sh:12` now uses `${1:-}` so Stage 3 of GCP provision stops crashing under `set -u`; `shellcheck` + `bats scripts/tests/providers/k3s_gcp.bats` pass.
- [x] **Stale SA key auto-re-extract** — COMPLETE (`acfb0470`). Spec `docs/bugs/v1.1.0-bugfix-gcp-stale-sa-key-project-probe.md`. `_gcp_load_credentials` probes cached project via `gcloud projects describe`; deletes key + re-extracts on new sandbox.
- [x] **SSH readiness probe** — COMPLETE (`de83535d`). Spec `docs/bugs/v1.1.0-bugfix-gcp-ssh-readiness-probe.md`. `_provider_k3s_gcp_deploy_cluster` now runs an `nc -z` loop (10s backoff, 30 retries) after `_gcp_ssh_config_upsert` so SSH is ready before `k3sup install`; `shellcheck scripts/lib/providers/k3s-gcp.sh` + `bats scripts/tests/providers/k3s_gcp.bats` pass.
- [x] **Stale kubeconfig merge** — COMPLETE (`fb694ac6`). Spec `docs/bugs/v1.1.0-bugfix-gcp-kubeconfig-stale-merge.md`. Purges stale k3s-gcp context/cluster/user entries from `~/.kube/config` before merging with fresh `k3s-gcp.yaml` so IP-change re-runs pick up the new credentials.
- [x] **k3s API server readiness probe** — COMPLETE (`afbcc44b`). Spec `docs/bugs/v1.1.0-bugfix-gcp-k3s-api-readiness-probe.md`. Added `nc -z` poll (10s backoff, 30 retries) on port 6443 between kubeconfig merge and `kubectl label nodes` so labeling waits for the k3s API server; shellcheck + bats pass.
- [x] **make provision depends on make up** — COMPLETE (`050160d9`). Spec `docs/bugs/v1.1.0-bugfix-gcp-provision-depends-on-up.md`. Makefile `provision` now runs `$(MAKE) up CLUSTER_PROVIDER=...` before `gcp_provision_stack` so the cluster is guaranteed up before the stack deploys; BATS suite re-run.
- [x] **Makefile GCP up-target** — COMPLETE (`ae747192`). Spec `docs/bugs/v1.1.0-bugfix-makefile-gcp-up-target.md`. `make up CLUSTER_PROVIDER=k3s-gcp` now runs `deploy_cluster` then `gcp_provision_stack`; `sync-apps` is a GCP no-op; `provision` is AWS-only again.
- [x] **Remove dead `gcp_grant_compute_admin`** — COMPLETE (`840ae84c`). Spec `docs/bugs/v1.1.0-bugfix-remove-gcp-grant-compute-admin.md`. Deleted the dead IAM grant helper from `scripts/plugins/gcp.sh` and replaced its BATS case with a negative assertion that the function is no longer defined.
- [x] **deploy_argocd not loaded + invalid flag** — COMPLETE (`17d16e8c`). Spec `docs/bugs/v1.1.0-bugfix-gcp-deploy-argocd-not-loaded.md`. `gcp_provision_stack` now sources `argocd.sh` before calling `deploy_argocd`, removes the invalid `--skip-ldap` flag, and clears the EXIT trap so the rendered manifest is deleted immediately; shellcheck + bats pass.
