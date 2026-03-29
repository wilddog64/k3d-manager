# Active Context — k3d-manager

## Current Branch: `k3d-manager-v1.0.0` (as of 2026-03-29)

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
**v1.0.0 ACTIVE** — branch `k3d-manager-v1.0.0` cut from `f98f2a8` 2026-03-29.
**enforce_admins:** restored on main 2026-03-29.
**Branch cleanup:** v0.9.7–v0.9.17 deleted (local + remote) 2026-03-28.
**v0.9.15 scope:** Antigravity × GitHub Copilot coding agent validation — 3 runs, determinism verdict; spec `docs/plans/v0.9.15-antigravity-copilot-agent.md`. Antigravity plugin rewritten in `b2ba187` per `docs/plans/v0.9.15-antigravity-plugin-impl.md`. Also: ldap-password-rotator `vault kv put` stdin hardening — spec `docs/plans/v0.9.15-ensure-copilot-cli.md` (closes v0.6.2 security debt; `_ensure_copilot_cli`/`_k3d_manager_copilot`/`_ensure_node` already shipped in v0.9.12).

---

## Roadmap Versioning Decision (2026-03-29)

| Version | Scope |
|---------|-------|
| v0.9.21 | `_ensure_k3sup` + `deploy_app_cluster` auto-install — SHIPPED `f98f2a8` |
| v1.0.0 | `k3s-aws` provider foundation — rename `k3s-remote` → `k3s-aws`; single-node deploy/destroy; SSH config auto-update |
| v1.0.1 | Multi-node: `acg_provision` × 3, k3sup join × 2, taints/labels |
| v1.0.2 | Full stack on 3 nodes: all 5 pods Running + E2E green |
| v1.0.3 | Samba AD DC plugin (`DIRECTORY_SERVICE_PROVIDER=activedirectory`) |
| v1.0.4 | GCP cloud provider (`k3s-gcp`) |
| v1.0.5 | Azure cloud provider (`k3s-azure`) |

`CLUSTER_PROVIDER` values: `k3s-aws` (AWS/ACG), `k3s-gcp` (GCP), `k3s-azure` (Azure) — symmetric naming across all three clouds.

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
| **Gemini e2e smoke test** | **COMPLETE** | Full lifecycle verified: `acg_get_credentials` → `deploy_cluster` → `get nodes` (Ready) → `destroy_cluster`. commit `4aba999`. |

## v1.0.0 Design Decisions

- **`acg_get_credentials <sandbox-url>`** — new function; extracts AWS credentials from Pluralsight sandbox "Cloud Access" panel via Antigravity Playwright; writes to `~/.aws/credentials`; stdin paste (`pbpaste | acg_import_credentials`) as fallback. Must run before any `acg_provision` call. Single extract covers all 3 nodes (same sandbox session).

---

## Current Focus (v0.9.21)

Scope: `_ensure_k3sup` helper + `deploy_app_cluster` replacement of raw `command -v k3sup` check.

| Item | Status | Notes |
|---|---|---|
| **v0.9.20 spec written** | **COMPLETE** | 3 fixes: Chrome launch, SPA nav, _ensure_k3sup. `b579043`. |
| **`_antigravity_launch` Chrome fix** | **COMPLETE** | Verified Chrome cold-start with `--password-store=basic` and dedicated profile. |
| **`acg_credentials.js` SPA nav fix** | **COMPLETE** | Verified SPA-navigation guard avoids hard goto when already on Pluralsight. |
| **`_ensure_k3sup`** | **COMPLETE** | Auto-installs via brew/curl + `deploy_app_cluster` guard rewired; commit `11a3ac1`. |
| **Gemini: smoke test `_ensure_k3sup`** | **COMPLETE** | Verified warm path (returns 0) and cold path (triggers install message when hidden). Ubuntu skip (unreachable). |
| **Gemini: Ubuntu smoke test `_ensure_k3sup`** | **COMPLETE** | Verified cold path on `ubuntu-parallels`. `k3sup` correctly installed via `curl | sudo sh` path after providing password. |
| **Static acg_credentials.js** | **COMPLETE** | Implemented `scripts/playwright/acg_credentials.js` and updated `acg_get_credentials`. Verified working with live Pluralsight sandbox via Chrome CDP. commit `67a445c`. |
| **scratch/ cleanup** | **PENDING** | `rm -f scratch/*` — wipe stale Playwright artifacts; policy: wipe at each release cut |
| **acg_get_credentials + acg_import_credentials** | **COMPLETE** | `3970623` adds credential extractor + stdin import helpers with docs/tests per `docs/plans/v0.9.19-acg-get-credentials.md` |
| **Pluralsight URL fix** | **COMPLETE** | `8f857ea` updates ACG + Antigravity plugins and docs to use `app.pluralsight.com`; Gemini e2e verified |
| **Nested agent fix** | **COMPLETE** | Implemented `--approval-mode yolo` + workspace temp path in `scripts/plugins/antigravity.sh`; commit `978b215`. |
| **E2E live test: ACG session** | **COMPLETE** | Verified `gemini-2.5-flash` is used as the first attempt (no fallback needed). Nested agent fix verified. Platform redirection issue remains but session check logic passed via manual login. |
| Reduce replicas + remove HPAs | **MERGED** | 5 repos squash-merged to main 2026-03-20 |
| Frontend nginx fix | **MERGED** | `65b354f` on main, tagged v0.1.1, released 2026-03-21 |
| **Gemini: verify frontend Running** | **COMPLETE** | Pod `frontend-85969b4bf-4wkdz` is `Running` on ubuntu-k3s |
| shopping-cart-infra PR #18 | **MERGED** | `a97ee04` — fix trivy-action 0.30.0→v0.35.0 |
| shopping-cart-infra PR #19 | **MERGED** | `4ecc6b5` — address Copilot PR #5 comments |
| **Gemini: Fix PostgreSQL Auth** | **COMPLETE** | Fixed `order-service` and `product-catalog` auth via secret patching |
| **Gemini: Fix Schema mismatch** | **COMPLETE** | Added missing columns to `orders` table in `postgresql-orders` |
| **Gemini: Fix Health Checks** | **COMPLETE** | Patched `product-catalog` readiness probe path `/health/ready` -> `/health` |
| **Gemini: Fix NetworkPolicies** | **COMPLETE** | Patched `allow-dns` and added `allow-to-istio` in `shopping-cart-payment` |
| **Codex: fix app manifests** | **MERGED** | PRs merged to main 2026-03-21; order `d109004`, product-catalog `aa5de3c`, infra `1a5c34d`; tagged v0.1.1; `docs/next-improvements` branches created |
| **Gemini: re-enable ArgoCD sync** | **COMPLETE** | Auto-sync re-enabled for all apps; verified tracking `HEAD` |
| **Gemini: force sync post-manifest-fix** | **FAILED** | `order-service` and `product-catalog` sync failed; ArgoCD server reachable but app cluster (`ubuntu-k3s`) connection refused via tunnel. Root cause: ACG sandbox credentials expired. See `docs/issues/2026-03-28-argocd-sync-acg-credentials-expired.md`. |
| **Frontend CrashLoopBackOff** | **DEFERRED → v1.0.0** | Root cause: resource exhaustion (FailedScheduling on t3.medium). PR #11 closed — Copilot P1 confirmed original port 8080 + /health was correct. Fix: 3-node k3sup. Doc: `docs/issues/2026-03-21-frontend-crashloopbackoff-misdiagnosis.md` |
| deploy_app_cluster automation | **MERGED** | commit `13c79b3` — adds k3sup install + kubeconfig merge + follow-up instructions |
| lib-foundation upstream sync | **MERGED** | commits `b60ddc6` (system.sh TTY fix) + `15f041a` (agent_rigor allowlist) on lib-foundation/feat/v0.3.4 |
| k3d system.sh sync | **MERGED** | commits `c216d45` (bare sudo allowlist) + `4c6e143` (cp from lib-foundation + missing BATS issue doc) |
| ACG plugin (aws sandbox) | **MERGED** | commit `37a6629` — acg_provision/status/extend/teardown plugin replaces bin/acg-sandbox.sh |
| **Copilot fixes (PR #39)** | **MERGED** | commit `7987453` — 9 findings: exit safety (`--soft`), VPC idempotency, CIDR security, heredoc fix, test pattern; `75f3b0f` — memory-bank roadmap; `157d431` — README + functions.md docs; CI green; all threads resolved; squash-merged in `8b09d577` |
| **product-catalog Degraded** | **OPEN** | Synced to `aa5de3c`; DB env vars correct; RABBITMQ_USER vs RABBITMQ_USERNAME mismatch via ESO |
| **App-layer bug tracking** | **DONE** | Filed GitHub Issues: order #16 (RabbitMQ), payment #16 (memory), product-catalog #16 (ESO key), frontend #12 (read-only FS) |
| **`bin/` consistency spec** | **MERGED** | commit `b0b76b3` — bin/smoke-test-cluster-health.sh sources system.sh and uses `_kubectl` |
| **if-count easy wins** | **MERGED** | commit `9a4f795` — `_jenkins_warn_on_cert_rotator_pull_failure` helper + allowlist trim; deferred functions in `docs/issues/2026-03-22-if-count-allowlist-deferred.md` |
| **if-count ldap refactor** | **MERGED** | commit `ba6f3a9` — extracted helpers so 7 `ldap.sh` functions drop ≤8 ifs; allowlist trimmed |
| **if-count vault refactor** | **MERGED** | commit `365846c` — extracted helpers + guard clauses so 5 `vault.sh` functions drop ≤8 ifs; allowlist cleared |
| **if-count jenkins refactor** | **MERGED** | commit `733123a` on k3d-manager-v0.9.10 — new helpers drop 4 `jenkins.sh` functions ≤8 ifs; allowlist entries removed |
| **ldap password rotator security** | **COMPLETE** | commit `e91a662` on k3d-manager-v0.9.15 — `vault kv put` now reads credentials from stdin (`@-`) per `docs/plans/v0.9.15-ensure-copilot-cli.md` |
| **v0.9.10 PR #44** | **MERGED** | `877ec970` — jenkins allowlist elimination; 4 Copilot findings fixed in `25e2b2a`; tagged v0.9.10; branch v0.9.11 cut |
| **v0.9.9 PR #43** | **MERGED** | `c1043175` — ldap+vault allowlist elimination; 9 Copilot findings fixed in `bbfc12e`; tagged v0.9.9; branch v0.9.10 cut |
| **Gemini: smoke test vault refactor** | **COMPLETE** | Ran `deploy_vault` and `deploy_vault --re-unseal` successfully. ESO integration confirmed working. |
| **Gemini: smoke test jenkins refactor** | **COMPLETE** | Ran `deploy_jenkins --enable-ldap --enable-vault` successfully. Helm, Istio, and CronJob resources created as expected. |
| **CI gap: no live cluster smoke tests** | **ROADMAP** | CI only runs pre-commit hooks; no automated deploy_vault/deploy_jenkins in CI — manual Gemini smoke tests are the only gate; track for v1.1.0 `provision_full_stack` work |
| **v0.9.11: dynamic plugin CI** | **MERGED** | commit `e2241d6` — implements detect job + conditional stage2 per doc-only / plugin change spec (`docs/plans/v0.9.11-dynamic-plugin-ci.md`) |
| **Dry-run docs/tests** | **MERGED** | commit `f1b4ca7` — README Safety Gates doc + `scripts/tests/lib/dry_run.bats` coverage |
| **v1.0.0 (3-node k3sup + Samba AD)** | **NEXT MILESTONE** | Replaces single t3.medium; resolves resource exhaustion structurally; spec: `docs/plans/roadmap-v1.md` |
| Re-enable e2e-tests schedule | **PENDING** | after all 5 pods Running |
| Playwright E2E green | **milestone gate** | |

---

## Cluster Architecture

**Infra cluster:** k3d on OrbStack on M2 Air — ArgoCD hub for Ubuntu k3s.
**App cluster:** Ubuntu k3s on AWS EC2 ACG sandbox — `i-0650af63c77af770c`, `34.219.1.106`, `t3.medium`, `us-west-2`.

### Infra Cluster (M2 Air — k3d/OrbStack)

| Component | Status |
|---|---|
| Vault | Running + Unsealed — `secrets` ns |
| ESO | Running — `secrets` ns |
| OpenLDAP | Running — `identity` + `directory` ns |
| Istio | Running — `istio-system` |
| Jenkins | Running — `cicd` ns |
| ArgoCD | Running — `cicd` ns |
| Keycloak | Running — `identity` ns |
| cert-manager | Running — `cert-manager` ns |

### App Cluster (EC2 — Ubuntu k3s)

| Component | Status |
|---|---|
| k3s node | **Ready** — v1.34.5+k3s1 |
| Istio | **Running** — `istio-system` |
| ghcr-pull-secret | **Verified** in `apps`, `data`, `payment` namespaces |
| basket-service | **Running** ✅ — ArgoCD Healthy |
| product-catalog | **Synced / Degraded** ⚠️ — Synced to `aa5de3c`, env vars corrected. Pod still not ready. |
| order-service | **Degraded** ⚠️ — PostgreSQL OK; RabbitMQ `Connection refused` persists |
| payment-service | **Progressing** ⚠️ — resource constraints; NetworkPolicies fixed |
| frontend | **CrashLoopBackOff** ⚠️ — root cause: FailedScheduling (t3.medium resource exhaustion); original port 8080 + /health correct; deferred to v1.0.0 |


---

## Key Capabilities Added (v0.9.4)

- **GitOps Reconciliation** — ArgoCD auto-sync re-enabled and tracking `HEAD` for all shopping-cart applications.
- **PostgreSQL Auth Fix** — manual secret patching on app cluster to sync passwords with data layer.
- **Schema Validation Fix** — manual DDL update (`ADD COLUMN`) to align DB with Hibernate expectations.
- **NetworkPolicy Hardening** — fixed `allow-dns` and added `allow-to-istio` to unblock `payment-service` initialization.
- **`_run_command` TTY fallback** — interactive sudo fallback when `sudo -n` unavailable.
- **autossh tunnel plugin** — `tunnel_start|stop|status`.

---

## v0.9.7 Tooling Changes

| Item | Status | Notes |
|---|---|---|
| `/create-pr` skill — Copilot reply+resolve flow | **DONE** | Added Steps 4+5: reply each comment via REST, resolve threads via GraphQL `resolveReviewThread`; 3 new Known Failure Modes |
| `/post-merge` skill — branch cleanup step | **DONE** | Step 8 added: delete stale branches every 5 releases; local `-d`/`-D` + remote protection removal + `git fetch --prune` |
| SSH config — persistent Keychain | **DONE** | Added `Host *` block with `UseKeychain yes` + `AddKeysToAgent yes` to `~/.ssh/config`; `lib-foundation` remote switched to SSH |
| Issue doc: frontend read-only filesystem | **MERGED** | `docs/issues/2026-03-21-frontend-readonly-filesystem-failure.md` |
| **gemini-skills repository** | **DONE** | Created `/Users/cliang/src/gitrepo/personal/gemini-skills` private repo; transitioned `~/.gemini` and `gemini-skills` remotes to SSH |
| **task-reporter skill** | **DONE** | Implemented and installed globally (`--scope user`); provides standardized task completion reports with metrics status bar |
| **README overhaul** | **MERGED** | PR #40 `de684fe7` — Plugins table (14), How-To by component, Issue Logs section, Releases 3+collapsible; enforce_admins restored |

---

## Operational Notes

- **Manifest fix PRs (2026-03-21):** order PR #15 (`d109004`), product-catalog PR #14 (`aa5de3c`), infra PR #20 (`1a5c34d`) — all squash-merged; v0.1.1 tagged; `docs/next-improvements` branches created on all three.
- **Copilot P1 bugs fixed:** product-catalog env var keys corrected (`DATABASE_*` → `DB_*`, `RABBITMQ_USER` → `RABBITMQ_USERNAME`, readiness probe `/health` → `/ready`); order-service `VAULT_ENABLED: false` set alongside `SPRING_CLOUD_VAULT_ENABLED: false`.
- **ArgoCD Sync Issues (resolved):** Original Codex SHAs (`007d80a`, `f9a7381`, `aaa08c1`) were committed to local `main` only — never pushed. Fixed by feature branch workflow. Manifests now on remote main.
- **Root findings (2026-03-21):**
    - `order-service` was missing `shipping_postal_code` and `total_amount` columns in PostgreSQL.
    - `product-catalog` was connecting to `localhost` fallback — env var key mismatch silently ignored.
    - `shopping-cart-payment` namespace had restrictive NetworkPolicies blocking DNS and Istiod egress.
    - `order-service` experiencing `Connection refused` to RabbitMQ service despite successful DB connection.
- **Memory Constraints** — `t3.medium` (4GB) is at 95% capacity; some pods scaled to 0 during troubleshooting.
- **PTY watchdog** — guards against Gemini CLI PTY leak.
- **Frontend regression (new finding):** The `CrashLoopBackOff` is caused by a read-only root filesystem preventing nginx from writing its config. See `docs/issues/2026-03-21-frontend-readonly-filesystem-failure.md`.
- **ArgoCD app status (as of this task):** basket Healthy ✅, frontend CrashLoopBackOff, order Degraded, payment Progressing, product-catalog Synced/Degraded, shopping-cart-apps OutOfSync.
