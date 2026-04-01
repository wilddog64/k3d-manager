# Active Context — k3d-manager

## Current Branch: `k3d-manager-v1.0.2` (as of 2026-03-31)

**v0.9.12 SHIPPED** — PR #47 merged to main (`f8014bc`) 2026-03-23. Copilot CLI CI integration.
**v0.9.13 SHIPPED** — PR #48 merged to main (`c54fbe6`) 2026-03-23. Tagged v0.9.13, released.
**v0.9.14 SHIPPED** — PR #50 merged to main (`d317429b`) 2026-03-24. No version tag. if-count allowlist fully cleared.
**v0.9.15 SHIPPED** — PR #51 merged (`484354da`) 2026-03-27. Tagged v0.9.15, released.
**v0.9.16 SHIPPED** — PR #51 merged (`484354da`) 2026-03-27. Tagged v0.9.16, released. `enforce_admins` restored. Retro: `docs/retro/2026-03-27-v0.9.16-retrospective.md`.
**v0.9.17 SHIPPED** — PR #52 merged (`c88ca7a`) 2026-03-28. Tagged v0.9.17. Released.
**v0.9.18 SHIPPED** — PR #53 merged (`7567a5c`) 2026-03-28. Tagged v0.9.18. Released. `enforce_admins` restored. Retro: `docs/retro/2026-03-28-v0.9.18-retrospective.md`.
**v0.9.19 SHIPPED** — PR #54 merged (`0f13be1`) 2026-03-28. Tagged v0.9.19. Released. `enforce_admins` restored. Retro: `docs/retro/2026-03-28-v0.9.19-retrospective.md`.
**v0.9.20 SHIPPED** — PR #55 merged to main (`bfd66fe`) 2026-03-29. Tagged v0.9.20, released. `enforce_admins` restored. Retro: `docs/retro/2026-03-29-v0.9.20-retrospective.md`.
**v0.9.21 SHIPPED** — PR #56 merged to main (`f98f2a8`) 2026-03-29. Tagged v0.9.21, released. `enforce_admins` restored. Retro: `docs/retro/2026-03-29-v0.9.21-retrospective.md`.
**v1.0.0 SHIPPED** — PR #57 merged to main (`807c0432`) 2026-03-29. Tagged v1.0.0, released. `enforce_admins` restored. Retro: `docs/retro/2026-03-29-v1.0.0-retrospective.md`.
**v1.0.1 SHIPPED** — PR #58 merged to main (`a8b6c583`) 2026-03-31. Tagged v1.0.1, released. `enforce_admins` restored. Retro: `docs/retro/2026-03-31-v1.0.1-retrospective.md`.
**v1.0.2 ACTIVE** — branch `k3d-manager-v1.0.2` cut from `a8b6c583` 2026-03-31.
**enforce_admins:** restored on main 2026-03-31.
**Branch cleanup:** v0.9.7–v0.9.17 deleted 2026-03-28; v1.0.0 deleted 2026-03-29.
**v0.9.15 scope:** Antigravity × GitHub Copilot coding agent validation — 3 runs, determinism verdict; spec `docs/plans/v0.9.15-antigravity-copilot-agent.md`. Antigravity plugin rewritten in `b2ba187` per `docs/plans/v0.9.15-antigravity-plugin-impl.md`. Also: ldap-password-rotator `vault kv put` stdin hardening — spec `docs/plans/v0.9.15-ensure-copilot-cli.md` (closes v0.6.2 security debt; `_ensure_copilot_cli`/`_k3d_manager_copilot`/`_ensure_node` already shipped in v0.9.12).

---

## Roadmap Versioning Decision (2026-03-29)

| Version | Scope |
|---------|-------|
| v0.9.21 | `_ensure_k3sup` + `deploy_app_cluster` auto-install — SHIPPED `f98f2a8` |
| v1.0.0 | `k3s-aws` provider foundation — rename `k3s-remote` → `k3s-aws`; single-node deploy/destroy; SSH config auto-update |
| v1.0.1 | Multi-node: `acg_provision` × 3, k3sup join × 2, taints/labels |
| v1.0.2 | Full stack on 3 nodes: all 5 pods Running + E2E green |
| v1.0.3 | Service mesh: Istio fully activated + MetalLB + VirtualServices for all apps; GUI access via hostnames (`argocd.k3s.local`, `vault.k3s.local`, `keycloak.k3s.local`, `jenkins.k3s.local`) over SSH/Cloudflare tunnel |
| v1.0.4 | Samba AD DC plugin (`DIRECTORY_SERVICE_PROVIDER=activedirectory`) |
| v1.0.5 | GCP cloud provider (`k3s-gcp`) |
| v1.0.6 | Azure cloud provider (`k3s-azure`) |

`CLUSTER_PROVIDER` values: `k3s-aws` (AWS/ACG), `k3s-gcp` (GCP), `k3s-azure` (Azure) — symmetric naming across all three clouds.

**v1.0.3 GUI access gate:** service mesh must be fully functional (all 5 pods Running, Istio sidecar injection verified, mTLS active) before adding MetalLB + VirtualService layer.

## v1.0.0 — Spec Written (2026-03-29)

**Spec:** `docs/plans/v1.0.0-k3s-aws-provider.md` — assigned to Codex.

4 file changes:
1. `scripts/lib/provider.sh` — `provider_slug="${provider//-/_}"` so hyphenated `k3s-aws` maps to `_provider_k3s_aws_*` functions
2. `scripts/lib/core.sh` — add `k3s-aws` to `deploy_cluster` case statement; fix no-args guard to skip when `CLUSTER_PROVIDER` env is set
3. NEW `scripts/lib/providers/k3s-aws.sh` — `_provider_k3s_aws_deploy_cluster` + `_provider_k3s_aws_destroy_cluster`
4. NEW `scripts/tests/lib/k3s_aws_provider.bats` — 3 tests (--help, destroy without --confirm)

| Item | Status | Notes |
|---|---|---|
| **`_cluster_provider_call` slug guard** | **COMPLETE** | Hyphen providers map to `_provider_k3s_aws_*`; commit `4aba999`. |
| **`deploy_cluster` guard + case** | **COMPLETE** | Accepts `k3s-aws` and respects env-configured providers; commit `4aba999`. |
| **`scripts/lib/providers/k3s-aws.sh`** | **COMPLETE** | Wires `acg_provision` → `deploy_app_cluster` → `tunnel_start` + teardown helper; commit `4aba999`. |
| **`k3s_aws_provider.bats`** | **COMPLETE** | New suite validates help + `--confirm` gate; runs via `./scripts/k3d-manager test lib`; commit `4aba999`. |
| **BATS PATH fix** | **COMPLETE** | Jenkins auth cleanup suite prepends Homebrew bash so plugin sourcing works on macOS; commit `4aba999`. |
| **`aws_import_credentials` refactor** | **COMPLETE** | New `aws.sh` helper (CSV + quoted export) + acg alias/back-compat; commit `be7e997`. |
| **`acg_get_credentials` Antigravity source** | **COMPLETE** | `acg.sh` now sources `antigravity.sh` so helpers are always defined; commit `4357f90`. |
| **`deploy_app_cluster` IP resolve** | **COMPLETE** | Reads `HostName` from `~/.ssh/config` before falling back to alias; commit `51983d3`. |
| **`acg_watch` + pre-flight extend`** | **COMPLETE** | `acg_provision --recreate`, new `acg_watch`, and provider pre-flight extend/watch wiring; commit `51bdf3a`. |
| **`k3s-aws` multi-node deploy** | **COMPLETE** | `_acg_provision_agents`, `_k3sup_join_agent`, node labeling + tests; commit `0c89f4e`. |
| **Keypair + extend hotfix** | **COMPLETE** | Keypair import uses `--soft` + extend prompt forces `page.goto`; commit `4a57f44`. |
| **Gemini e2e smoke test (run 1)** | **COMPLETE** | Full lifecycle verified: `acg_get_credentials` → `deploy_cluster` → `get nodes` (Ready) → `destroy_cluster`. commit `4aba999`. |
| **Gemini e2e smoke test (run 2)** | **FAILED** | Blocked by `KeyPair` import conflict in `acg_provision`. Documented in `docs/issues/2026-03-29-acg-provision-keypair-import-fail.md`. |
| **Gemini e2e smoke test (run 3)** | **COMPLETE** | Verified hotfixes: Keypair import is idempotent (no error on duplicate); `antigravity_acg_extend` uses unconditional navigation. Full lifecycle confirmed functional. commit `df8f77f`. |
| **Gemini e2e smoke test (3-node)** | **COMPLETE** | Full 3-node lifecycle verified: `acg_get_credentials` → `deploy_cluster` (CloudFormation + 3 nodes Ready) → `destroy_cluster`. |
| **Gemini blocker fixes verification** | **COMPLETE** | Verified cluster rebuilding, ESO CRD patching, and registry auth restore. 3 nodes Ready. Pods 5/5 transition from ImagePullBackOff to Running/CrashLoopBackOff (Vault dependency). |
| **Vault Token transition** | **FAILED** | `ClusterSecretStore` applied with static Vault Token; still `False` due to unstable `socat` bridge on remote server. Documented in `docs/issues/2026-04-01-remote-vault-bridge-instability.md`. |

## v1.0.0 Design Decisions

- **`acg_get_credentials <sandbox-url>`** — new function; extracts AWS credentials from Pluralsight sandbox "Cloud Access" panel via Antigravity Playwright; writes to `~/.aws/credentials`; stdin paste (`pbpaste | acg_import_credentials`) as fallback. Must run before any `acg_provision` call. Single extract covers all 3 nodes (same sandbox session).

---

## Operational Notes

- **3-node Cluster Up:** Rebuilt via `acg_provision` (CloudFormation) + `k3sup install/join` after sandbox recreation.
- **ArgoCD Registered:** App cluster `ubuntu-k3s` registered with fresh token.
- **ESO CRDs Patched:** `v1beta1` enabled for `ExternalSecret`, `SecretStore`, and `ClusterSecretStore`.
- **Registry Auth:** `ghcr-pull-secret` restored in `apps` and `payment` namespaces.
- **Vault connectivity:** Transitioned to **Vault Token** auth. Secret `vault-token` exists on remote cluster. `ClusterSecretStore` applied but blocked by `socat` bridge failure.
- **vault-bridge bugfix specced:** `docs/plans/v1.0.2-bugfix-vault-bridge.md` — Codex to add `_setup_vault_bridge` in `shopping_cart.sh`, Endpoints step in `bin/acg-up`, fix ClusterSecretStore server address, add `vault-bridge-svc.yaml` in shopping-cart-infra.
- **ArgoCD app status:** basket `CrashLoopBackOff`, frontend `CrashLoopBackOff`, order `Running`, payment `Running`, product-catalog `Error`. All app pods reached remote execution phase.
