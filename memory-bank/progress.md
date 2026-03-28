# Progress — k3d-manager

## Overall Status

**v0.9.3 SHIPPED** — squash-merged to main (8046c73), PR #36, 2026-03-16. Tagged + released.
**v0.9.4 SHIPPED** — merged to main (662878a), PR #37, 2026-03-21.
**v0.9.5 SHIPPED** — PR #38 squash-merged to main (`573c0ac`) 2026-03-21. Tagged v0.9.5, released.
**v0.9.6 SHIPPED** — PR #39 merged to main (`8b09d577`) 2026-03-22. Tagged v0.9.6, released.
**v0.9.7 SHIPPED** — PR #41 merged to main (`97249a6f`) 2026-03-22. Tagged v0.9.7, released.
**v0.9.8 SHIPPED** — PR #42 merged to main (`64525e3f`) 2026-03-22. if-count easy wins + dry-run doc/tests. No version tag (CHANGELOG [Unreleased]).
**v0.9.9 SHIPPED** — PR #43 merged to main (`c1043175`) 2026-03-22. Tagged v0.9.9, released. if-count allowlist: ldap (7) + vault (5) entries removed.
**v0.9.10 SHIPPED** — PR #44 merged to main (`877ec970`) 2026-03-22. Tagged v0.9.10, released. if-count allowlist: jenkins (4) entries removed; allowlist now system.sh only.
**v0.9.11 SHIPPED** — PR #45 merged to main (`1a0c913`) 2026-03-22. Tagged v0.9.11, released. Dynamic plugin CI: detect job + conditional stage2.
**v0.9.12 SHIPPED** — PR #47 merged to main (`f8014bc`) 2026-03-23. No version tag (CHANGE.md [Unreleased]). Copilot CLI CI integration + lib-foundation v0.3.6 subtree.
**v0.9.13 SHIPPED** — PR #48 merged to main (`c54fbe6`) 2026-03-23. Tagged v0.9.13, released. v0.9.12 retro + CHANGE.md backfill + mergeable_state process check.
**v0.9.14 SHIPPED** — PR #50 merged to main (`d317429b`) 2026-03-24. No version tag (CHANGE.md [Unreleased]). if-count allowlist fully cleared: _run_command + _ensure_node helpers extracted via lib-foundation PR #13.
**v0.9.15 SHIPPED** — PR #51 squash-merged to main (`484354da`) 2026-03-27. Tagged v0.9.15, released.
**v0.9.16 SHIPPED** — PR #51 squash-merged to main (`484354da`) 2026-03-27. Tagged v0.9.16, released. `enforce_admins` restored. Retro: `docs/retro/2026-03-27-v0.9.16-retrospective.md`.
**v0.9.17 SHIPPED** — PR #52 merged to main (`c88ca7a`) 2026-03-28. Tagged v0.9.17, released. `enforce_admins` restored. Retro: `docs/retro/2026-03-28-v0.9.17-retrospective.md`. Branches v0.9.7–v0.9.17 deleted.
**v0.9.18 SHIPPED** — PR #53 merged (`7567a5c`) 2026-03-28. Tagged v0.9.18. Released. `enforce_admins` restored. Retro: `docs/retro/2026-03-28-v0.9.18-retrospective.md`.
**v0.9.19 ACTIVE** — branch `k3d-manager-v0.9.19` cut from `7567a5c` 2026-03-28.

## v0.9.19 — In Progress

- [x] **`acg_get_credentials` + `acg_import_credentials`** — commit `3970623` adds `_acg_write_credentials`, both public functions, docs updates, and 8 BATS tests per `docs/plans/v0.9.19-acg-get-credentials.md`
- [ ] **Static Playwright script** — Codex assigned. Spec: `docs/plans/v0.9.19-acg-playwright-script.md`. Creates `scripts/playwright/acg_credentials.js`; replaces Gemini-prompt block in `acg_get_credentials` with direct `node` call. Commit message: `feat(acg): replace Gemini-generated Playwright with static acg_credentials.js`
- [ ] **Gemini: verify Playwright selectors** — after Codex, spin up live sandbox and run `acg_get_credentials <url>` to verify/update DOM selectors in `acg_credentials.js`
- [ ] **scratch/ cleanup** — `rm -rf scratch/*` — wipe stale Playwright artifacts at release cut

## v0.9.17 — Shipped

- [x] **`_antigravity_ensure_acg_session`** — Implemented in `scripts/plugins/antigravity.sh`; BATS coverage in `scripts/tests/lib/antigravity.bats`; verified via `env -i` BATS run.
- [x] **E2E live test: `_antigravity_ensure_acg_session`** — **COMPLETE**. Verified `gemini-2.5-flash` is used as first attempt. Fallback helper and nested agent fix (YOLO + workspace temp) verified working. ACG login logic verified via manual prompt. Spec: `docs/plans/v0.9.17-acg-session-e2e-test.md`.
- [x] **Pin gemini model to gemini-2.5-flash** — Gemini implemented in `scripts/plugins/antigravity.sh`; BATS tests pending Codex implementation. Spec: `docs/plans/v0.9.17-antigravity-model-flag.md`.
- [x] **Model fallback helper** — implemented (`d004bb3`), BATS added by Codex (`74d182d`). Spec: `docs/plans/v0.9.17-antigravity-model-fallback.md`.
- [x] **Nested agent fix** — Implemented `--approval-mode yolo` + workspace temp path in `scripts/plugins/antigravity.sh`; shellcheck clean; commit pushed (`978b215`). Spec: `docs/plans/v0.9.17-antigravity-nested-agent-fix.md`. Unblocks e2e retest.

---

## v0.9.15+v0.9.16 — Shipped

- [x] **Playwright Integration Documentation** — `docs/plans/playwright-gemini.md` created; defines high-level orchestration, MCP benefits, and cross-browser support strategy.
- [x] **Antigravity plugin rewrite** — commit `b2ba187` rewrites plugin to use gemini CLI + Playwright per `docs/plans/v0.9.15-antigravity-plugin-impl.md`
- [x] **Antigravity × Copilot coding agent validation** — Determinism verdict: **FAIL**. Automation blocked by auth isolation. Findings doc: `docs/issues/2026-03-24-antigravity-copilot-agent-validation.md`
- [x] **ldap-password-rotator vault kv put stdin fix** — commit `e91a662` implements stdin (`@-`) vault writes per `docs/plans/v0.9.15-ensure-copilot-cli.md`

---

## v0.9.16 — Planned

- [x] **antigravity.sh MCP refactor** — commit `45168cf` switches plugin to Antigravity IDE + Playwright MCP over CDP (`_ensure_antigravity_ide`, `_ensure_antigravity_mcp_playwright`, `_antigravity_browser_ready`); spec: `docs/plans/v0.9.16-antigravity-plugin-mcp-refactor.md`
- [x] **antigravity.sh launch + session** — commit `e83d89d` adds `_antigravity_launch` (auto-start IDE) + `_antigravity_ensure_github_session` (CDP login + wait) per `docs/plans/v0.9.16-antigravity-launch-session.md`
- [x] **antigravity _curl probe fix** — commit `6b98902` updates `_antigravity_launch` to `_run_command --soft -- curl` per `docs/plans/v0.9.16-antigravity-curl-probe-fix.md`
- [x] **lib-foundation v0.3.13 subtree pull** — commit `dfcb590` pulls `_antigravity_browser_ready` probe fix (`e870c6d9`) into `scripts/lib/foundation/`
*(v0.9.16 scope complete — PR ready)*

---

## v0.9.19 — Active

- [x] **Static acg_credentials.js** — **COMPLETE**. Replaced Gemini-generated Playwright with static `scripts/playwright/acg_credentials.js`. commit `a7aea9c`. Spec: `docs/plans/v0.9.19-acg-playwright-script.md`.
- [ ] **scratch/ cleanup** — `rm -f scratch/*`; stale Playwright artifacts from v0.9.18 and earlier
- [ ] **ArgoCD Sync — `order-service` & `product-catalog`** — **FAILED**. Attempted sync on infra cluster; ArgoCD server logged in successfully but app cluster connection failed. Root cause: ACG sandbox credentials expired; SSH tunnel down. See `docs/issues/2026-03-28-argocd-sync-acg-credentials-expired.md`.

---

## v0.9.18 — Shipped

- [x] **Pluralsight URL fix** — commit `8f857ea` updates `_ACG_SANDBOX_URL`, `_antigravity_ensure_acg_session`, and docs to `app.pluralsight.com`; Gemini e2e verified; PR #53 merged `7567a5c`

---

## v0.9.17 — Completed

- [x] **`_antigravity_ensure_acg_session`** — Implemented in `scripts/plugins/antigravity.sh`; BATS coverage in `scripts/tests/lib/antigravity.bats`; verified via `env -i` BATS run.

---

## v0.9.12 — Completed

- [x] lib-foundation v0.3.6 subtree pull — `9a030bc` — `doc_hygiene.sh` + hooks now in subtree
- [x] `_ensure_copilot_cli` / `_ensure_node` / `_k3d_manager_copilot` — already implemented (pre-compaction); BATS tests present in `scripts/tests/lib/`
- [x] Roadmap update — **STALE**: current roadmap already correct; no changes needed
- [x] **Copilot CLI auth CI integration** — PR #47 (`f8014bc`): installs Copilot CLI in lint job, wires `COPILOT_GITHUB_TOKEN`/`K3DM_ENABLE_AI`/`K3DM_COPILOT_LIVE_TESTS` into BATS, adds live binary check; 2 Copilot findings fixed (`fbb9ba4`)

## v0.9.14 — Completed

- [x] GitHub PAT rotation — rotated 2026-03-23; new expiry 2026-04-22
- [x] **if-count: `_run_command` + `_ensure_node`** — commit `b9fcbf6` (lib-foundation feat/v0.3.7) extracts helpers; subtree pull `aec6673` copies `system.sh` + clears allowlist per spec `docs/plans/v0.9.14-if-count-system-sh.md`
- [x] **PR #50 merged** — `d317429b` 2026-03-24; Copilot findings addressed; retro `docs/retro/2026-03-24-v0.9.14-retrospective.md`; branch v0.9.15 cut

---

## v0.9.13 — Completed

- [x] v0.9.12 retrospective — `docs/retro/2026-03-23-v0.9.12-retrospective.md` (`3f19383`)
- [x] `/create-pr` skill — `mergeable_state` check in Post-creation Steps + "Dirty PR silently kills CI" failure mode
- [x] CHANGE.md — backfill `[v0.9.12]` entry; add `[v0.9.13]` section
- [x] README + docs/releases.md — add v0.9.13 release row; v0.9.9 moved to collapsible
- [x] Copilot PR #48 findings fixed (`d1972ca`) — stale `memory/` ref, `CHANGELOG`→`CHANGE.md`, stale branch header
- [x] v0.9.13 retrospective — `docs/retro/2026-03-23-v0.9.13-retrospective.md`

---

## v0.9.4 — Completed

- [x] README releases table — v0.9.3 added — `1e3a930`
- [x] lib-foundation v0.3.3 subtree pull — `7684266`
- [x] Multi-arch workflow pin — all 5 app repos merged to main 2026-03-18
- [x] ArgoCD cluster registration fix — manual cluster secret `cluster-ubuntu-k3s` with `insecure: true`
- [x] Missing `frontend` manifest — `argocd/applications/frontend.yaml` in shopping-cart-infra (PR #17)
- [x] Verify `ghcr-pull-secret` — present in `apps`, `data`, `payment` namespaces
- [x] Tag refresh for ARM64 images — `newTag: latest` in all 5 repos
- [x] Codex: kubeconfig merge automation — `6699ce8`
- [x] payment-service missing Secrets — PR #14 merged (9d9de98)
- [x] Fix `_run_command` non-interactive sudo failure — `fix(system): fall back to interactive sudo when sudo -n unavailable and TTY present`
- [x] autossh tunnel plugin — `feat(tunnel): add autossh tunnel plugin with launchd boot persistence`
- [x] ArgoCD cluster registration automation — `register_app_cluster` + cluster-secret template
- [x] Smoke tests — `bin/smoke-test-cluster-health.sh`
- [x] Reduce replicas to 1 + remove HPAs — merged 2026-03-20
- [x] Fix frontend nginx CrashLoopBackOff — `65b354f` merged to main 2026-03-21; tagged v0.1.1
- [x] Gemini: rebuild Ubuntu k3s + E2E verification — `7d614bc`
- [x] Gemini: ArgoCD cluster registration + app sync — `7d614bc`
- [x] Force ArgoCD sync — order-service + product-catalog — verified
- [x] Gemini: deploy data layer to ubuntu-k3s — all Running in `shopping-cart-data`
- [x] Gemini: Fix PostgreSQL auth issues — patched `order-service` and `product-catalog` secrets
- [x] Gemini: Fix PostgreSQL schema mismatch — added columns to `orders` table
- [x] Gemini: Fix product-catalog health check — patched readiness probe path
- [x] Gemini: Fix NetworkPolicies — unblocked `payment-service` and local DNS
- [x] Codex: fix app manifests — PRs merged to main; order `d109004`, product-catalog `aa5de3c`, infra `1a5c34d`; tagged v0.1.1; `docs/next-improvements` branch created
- [x] Codex: fix frontend manifests — PR #11 CLOSED; Copilot P1 confirmed original port 8080 + /health was correct; root cause is resource exhaustion not manifest error; deferred to v1.0.0
- [x] Gemini: Re-enable ArgoCD auto-sync — all apps reconciled to `HEAD`
- [x] Codex: add deploy_app_cluster automation — commit `13c79b3` adds k3sup install + kubeconfig merge helper and BATS coverage

---

## v0.9.5 — Completed

- [x] **`deploy_app_cluster` via k3sup** — `k3sup install` on EC2 + kubeconfig merge + ArgoCD cluster registration; replaces manual Gemini rebuild; prerequisite for v1.0.0 multi-node extension
- [x] check_cluster_health.sh hardening — kubectl context pinning, API server retry loop, `kubectl wait` replacing `rollout status`
- [x] Retro: `docs/retro/2026-03-21-v0.9.5-retrospective.md`

---

## v0.9.6 — Shipped

**ACG plugin shipped + 9 Copilot findings resolved. PR #39 squash-merged `8b09d577` 2026-03-22. Tagged v0.9.6, released.**

- [x] **ACG plugin** — `scripts/plugins/acg.sh`: `acg_provision`, `acg_status`, `acg_extend`, `acg_teardown`; retire `bin/acg-sandbox.sh`; commit `37a6629`
- [x] **Copilot fixes** — 9 findings: exit safety (`--soft`), VPC idempotency, CIDR security, heredoc fix, test pattern; commits `7987453` + `75f3b0f` + `157d431`
- [x] **README + functions.md** — ACG plugin documented; v0.9.6 in releases table
- [x] **CHANGE.md** — v0.9.6 entry with Fixed + Documentation subsections
- [x] **Retrospective** — `docs/retro/2026-03-22-v0.9.6-retrospective.md`

---

## v0.9.7 — Shipped

**PR #41 merged to main (`97249a6f`) 2026-03-22. Tagged v0.9.7, released.**

### Tooling (done this session)
- [x] `/create-pr` skill — Copilot reply+resolve flow (Steps 4+5, 3 new failure modes)
- [x] `/post-merge` skill — branch cleanup step (Step 8, every 5 releases)
- [x] SSH config — persistent Keychain (`Host *` block); `lib-foundation` remote → SSH
- [x] Issue doc: `docs/issues/2026-03-21-frontend-readonly-filesystem-failure.md`
- [x] **README overhaul** — PR #40 merged (`de684fe7`); Plugins table (14), How-To by component, Issue Logs section, Releases 3+collapsible; `docs/releases.md` backfilled

### Code Quality / Architecture (carried from v0.9.6)
- [x] **Upstream local lib edits to lib-foundation** — commits `b60ddc6` (system.sh TTY fix) + `15f041a` (agent_rigor allowlist) on lib-foundation/feat/v0.3.4
- [x] **Sync scripts/lib/system.sh from lib-foundation** — commit `4c6e143` copies `b60ddc6`, `c216d45` adds bare-sudo allowlist so `_agent_audit` passes; tracked missing `scripts/tests/lib/system.bats` in `docs/issues/2026-03-22-missing-system-bats.md`
- [ ] **Reduce if-count allowlist** — v0.9.8 easy wins done (commit `9a4f795`); `docs/issues/2026-03-22-if-count-allowlist-deferred.md` tracks remaining 18 functions for v0.9.9+
- [x] **`bin/` script consistency** — commit `b0b76b3` makes `bin/smoke-test-cluster-health.sh` source system.sh + use `_kubectl`
- [x] **Relocate app-layer bug tracking** — filed as GitHub Issues: order #16, payment #16, product-catalog #16, frontend #12

### Secondary
- [x] **Safety gate audit** — commit `51a40b0` adds no-args guard to `deploy_cluster`; `deploy_k3d_cluster`/`deploy_k3s_cluster` inherit fix
- [x] **`--dry-run` / `-n` mode** — docs/tests added in commit `f1b4ca7` (README Safety Gates + `scripts/tests/lib/dry_run.bats`); implementation already shipped
- [x] **Reduce if-count allowlist (ldap)** — commit `ba6f3a9` extracts helpers so `_ldap_*` + `deploy_ldap`/`deploy_ad` drop under threshold; allowlist trimmed to vault/system entries only
- [x] **Reduce if-count allowlist (vault)** — commit `365846c` extracts deploy/HA helpers and guard clauses so 5 `vault.sh` functions drop ≤8 ifs; removed vault entries from the allowlist
- [x] **Reduce if-count allowlist (jenkins)** — commit `733123a` on k3d-manager-v0.9.10 extracts helpers + rewires deploy path so 4 `jenkins.sh` functions drop ≤8 ifs; allowlist cleared
- [x] **GitHub PAT rotation** — rotated 2026-03-23; new expiry 2026-04-22

### Deferred to v1.0.0 (needs multi-node)
- [ ] All 5 pods Running — order-service (RabbitMQ), payment-service (memory), frontend (resource exhaustion)
- [ ] Re-enable `shopping-cart-e2e-tests` + Playwright E2E green
- [ ] Re-enable `enforce_admins` on shopping-cart-payment
- [ ] Service mesh — Istio full activation

---

## Roadmap

- **v0.9.6** — ACG plugin (`acg_provision`, `acg_extend`, `acg_teardown`) + LoadBalancer for ArgoCD/Keycloak/Jenkins; retire `bin/acg-sandbox.sh`
- **v1.0.0** — 3-node k3s via k3sup + Samba AD DC; `CLUSTER_PROVIDER=k3s-remote`; resolves resource exhaustion; frontend + e2e milestone gate
- **v1.1.0** — Full stack provisioning: `provision_full_stack` single command (k3s + Vault + ESO + Istio + ArgoCD)
- **v1.2.0** — k3dm-mcp (gate: v1.0.0 multi-node proven; k3d + k3s-remote = two backends)
- **v1.3.0** — Home lab: k3s on Mac Mini M5 (`CLUSTER_PROVIDER=k3s-local-arm64`); home automation plugins
- **No EKS/GKE/AKS** — k3d-manager is kops-for-k3s; cloud-managed k8s is out of scope

---

## Known Bugs / Gaps

**Infra / tooling (tracked here):**

| Item | Status | Notes |
|---|---|---|
| SSH Tunnel timeouts | OPEN | Connection resets during heavy ArgoCD sync |

**App-layer (to be filed as GitHub Issues in their repos — v0.9.5 task):**

| Item | Repo | Notes |
|---|---|---|
| frontend CrashLoopBackOff | shopping-cart-frontend | Root cause: resource exhaustion (t3.medium); deferred to v1.0.0 3-node cluster |
| order-service CrashLoopBackOff | shopping-cart-order | PostgreSQL OK; RabbitMQ `Connection refused` only remaining |
| payment-service Pending | shopping-cart-payment | Memory constraints on `t3.medium` |
| product-catalog Degraded | shopping-cart-product-catalog | Synced to `aa5de3c`; `RABBITMQ_USERNAME` ESO key mismatch |
