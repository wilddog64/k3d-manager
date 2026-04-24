# Progress — k3d-manager

## Shipped — pointer, not record

The authoritative release record lives in `docs/releases.md`, `CHANGE.md`, and `git tag -l`. Retros for each release are under `docs/retro/`. This file tracks **in-flight** work only.

**Most recent shipped:**

- v1.0.6 — AWS SSM support for `k3s-aws` (PR #64, `a54e152f`, 2026-04-11)
- v1.0.5 — antigravity decoupling + LDAP Vault KV seeding + Copilot fix-up (PR #62/#63, `71c88b05`, 2026-04-11)
- v1.0.4 — acg-up random passwords, acg_extend hardening (PR #61, `bc9028fb`, 2026-04-10)
- v1.0.3 — `bin/` SCRIPT_DIR, Vault KV seeding, ArgoCD registration fixes (PR #60, `91552139`, 2026-04-05)

Pre-v1.0.3 detail removed from this file (2026-04-19 cleanup); see `git log --tags` and `docs/retro/`.

---

## v1.1.0 Track (branch: `k3d-manager-v1.1.0`)

- **Baseline** — branched off `main` (`279db18c`); AWS path verified 2026-04-19.
- [x] **Shared playwright vars** — COMPLETE (`3de58f4d`)
- [x] **Robot engine unification** — COMPLETE (`a986d5bb`)
- [x] **GCP identity bridge** — COMPLETE (`9686e5c3`). Credential extraction, identity bridge, OAuth automation verified.
- [x] **Documentation alignment** — COMPLETE (`7f3bd0a6`)
- [x] **lib-foundation v0.3.17** — COMPLETE (PR #23 merged). `_agent_lint` glob expanded to `*.sh *.js *.md`.
- [ ] **GCP cluster provisioning** — **PARTIAL**. CLUSTER_NAME default fix committed in `3a3806aa`; live smoke test is still blocked by Chrome CDP startup (`docs/issues/2026-04-21-cluster-name-smoke-test-blocked-by-cdp.md`).
- [ ] **E2E verify** — **BLOCKED**. Needs a clean `make up` run past Chrome CDP startup.
- [x] **CDP Linux headless + profile unification** — **COMPLETE** (`1ab14ebf`). Implemented `docs/bugs/2026-04-21-cdp-linux-headless-launch-failure.md`; D1/D2/D3 passed locally and D4 live sandbox validation remains pending user execution.
- [ ] **ACG repo extraction** — **PLANNED** (`8639592c`). Plan: `docs/plans/v1.1.0-acg-extraction-repo-split.md`. Extract browser/CDP/Playwright automation into its own repo to stop polluting `k3d-manager` stability.

---

- [ ] **Safe Identity Reset** — OPEN. Plan `docs/plans/v1.1.0-recovery-phase-b-safe-identity-reset.md`; implement domain-isolated cookie wipe (.google.com only) and trap escape for fresh login.
## Agent Rigor CLI Improvements

- [ ] **Whitespace Enforcement** — OPEN. Add trailing-whitespace detection to `_agent_lint` for `.js`/`.sh` files.

---

## Known Bugs / Gaps
- [ ] **Orchestration Fragility** — OPEN. Issue `docs/bugs/2026-04-23-infra-orchestration-fragility.md`; the local Hub flow does not explicitly unify ArgoCD install, bootstrap, app-cluster registration, and operator access setup.
- [ ] **Dual-cluster Status UX** — OPEN. Issue `docs/bugs/2026-04-23-make-up-dual-cluster-status-and-orbstack-gap.md`; `make up` and `make status` do not clearly separate local Hub health, remote app-cluster health, tunnel endpoint state, and local ArgoCD access setup.
- [ ] **ACG Extraction Boundary** — OPEN. Issue `docs/bugs/2026-04-23-acg-extraction-boundary-gemini-coupling.md`; the `acg_*` workflow still keeps Gemini/browser automation coupled to `k3d-manager` instead of an extracted ACG subsystem.
- [x] **Teardown State Drift** — COMPLETE (`3fd6f4d6`). Implemented the spec in `docs/bugs/2026-04-23-acg-down-full-teardown-spec.md`; `acg-down` now tears down the local Hub by default and preserves it only with `--keep-hub`.
- [x] **acg-sync-apps + acg-status dual-cluster** — COMPLETE (`a5422141`). Implemented the spec in `docs/bugs/2026-04-23-acg-sync-apps-and-acg-status-dual-cluster.md`; `acg-sync-apps` now polls port-forward readiness and uses configurable `ARGOCD_APP`, and `acg-status` now reports Hub cluster nodes + pods.
- [ ] **Repo Retention Cleanup** — OPEN. Issue `docs/issues/2026-04-23-repo-retention-cleanup-for-scratch-and-docs.md`; `scratch/` and historical docs should be reviewed for purge/archive based on active references.
- [x] **Vault Preflight After Sleep** — COMPLETE (`e577579e`). Spec `docs/bugs/2026-04-23-acg-up-vault-state-preflight-gap-after-mac-sleep.md`; `bin/acg-up` now checks Hub reachability before Vault PF startup and exits early if Vault is sealed or unreachable.
- [x] **acg-extend isPanelOpen false positive** — COMPLETE (`79b87e36`). Spec `docs/bugs/2026-04-24-acg-extend-ispanelopen-false-positive.md`; `isPanelOpen` now follows `clicked`, and Open Sandbox targets the running sandbox card instead of `.first()`.
- [x] **acg-sync-apps app not found** — COMPLETE (`eaaf9a9e`). Spec `docs/bugs/2026-04-24-acg-sync-apps-argocd-app-not-found.md`; missing-app errors now list available ArgoCD app names.
- [x] **acg-down provider dispatch** — COMPLETE (`706e0ba2`). Spec `docs/bugs/2026-04-24-acg-down-provider-dispatch-gcp-teardown.md`; `bin/acg-down` now dispatches remote teardown by `CLUSTER_PROVIDER` and calls `destroy_cluster --confirm` for GCP.
- [ ] **acg-credentials Open Sandbox provider-blind** — DEFERRED to lib-acg. Spec `docs/bugs/2026-04-24-acg-credentials-open-sandbox-provider-blind.md`; will be fixed in provider-isolated files during lib-acg extraction.
- [x] **acg-down expired credentials abort** — COMPLETE (`ae2fca66`, follow-up `07ca18a6`). Spec `docs/bugs/2026-04-24-acg-down-expired-credentials-abort.md`; local Hub + Vault PF cleanup remains non-fatal on expired AWS credentials, and the follow-up fix now suppresses the prior ERROR noise.
- [x] **acg-down credential check noise** — COMPLETE (`07ca18a6`). Spec `docs/bugs/2026-04-24-acg-down-credential-check-noise.md`; `bin/acg-down` now pre-checks AWS creds silently before calling `acg_teardown` and skips with a single clean INFO when invalid.
- [x] **acg-up Hub cluster auto-create** — COMPLETE (`73382eb2`). Spec `docs/bugs/2026-04-24-acg-up-hub-cluster-not-created.md`; Step 3.5 now auto-creates the local Hub cluster when missing and still uses `kubectl get nodes` as the true OrbStack-broken-state guard.
- [x] **k3d-provider EXIT trap leak** — COMPLETE (`258de0d1`). Spec `docs/bugs/2026-04-24-k3d-provider-exit-trap-leak.md`; `_provider_k3d_configure_istio` now uses `RETURN` for temp file cleanup, matching `_provider_k3d_create_cluster` and preventing EXIT trap leakage into inline callers.
- [x] **k3d-provider RETURN trap scope** — COMPLETE (`e6a9ec91`). Spec `docs/bugs/2026-04-24-k3d-provider-return-trap-scope.md`; both k3d provider RETURN trap handlers now self-clear on first fire, preventing re-fire in parent functions with out-of-scope local variables.
- [ ] **Vault Resilience Gap** — BLOCKED. `docs/bugs/2026-04-23-vault-keychain-sync-mismatch.md` now tracks the remaining gap accurately: cached unseal replacement and some automatic recovery already exist, but local Vault can still land in drifted states that are not fully reconciled before seeding.
- [x] **GCP Login Linux Headless OAuth** — COMPLETE (`927cb452`). Spec `docs/bugs/2026-04-23-gcp-login-linux-headless-oauth-url-capture.md`; `gcp.sh` captures OAuth URL from gcloud on Linux; `gcp_login.js` navigates directly via `GCP_AUTH_URL`. Live test pending.
- [x] **GCP Provisioning Error 1** — COMPLETE (`346c3df2`). Bug `docs/bugs/2026-04-23-gcp-node-readiness-timeout-bash-pitfall.md`; `(( attempts++ ))` → `(( ++attempts ))` at lines 109 + 211 of `k3s-gcp.sh`. Spec complete; committed 2026-04-23.
- [x] **Start Sandbox Disabled Timeout** — COMPLETE (`13d398ab`). Bug `docs/bugs/2026-04-23-acg-start-sandbox-button-disabled-timeout.md`; add `isEnabled()` guard before `startButton.click()` in `acg_credentials.js`; committed 2026-04-23.
- [x] **acg-up Hub cluster bootstrap** — COMPLETE (`c59f2c3a`). Bug `docs/bugs/2026-04-24-acg-up-hub-cluster-bootstrap.md`; `bin/acg-up` now tracks fresh Hub creation in Step 3.5 and runs Step 3.6 to bootstrap Vault + ArgoCD before the Vault port-forward path.
- [x] **acg-up Hub bootstrap safety gate** — COMPLETE (`8b43122f`). Bug `docs/bugs/2026-04-24-acg-up-hub-bootstrap-safety-gate.md`; Step 3.6 now passes `--confirm` to both dispatcher calls so Hub bootstrap clears the deploy safety gate.
- [x] **acg-up Hub bootstrap LDAP missing** — COMPLETE (`c650f032`). Bug `docs/bugs/2026-04-24-acg-up-hub-bootstrap-ldap-missing.md`; Step 3.6 now deploys LDAP through the dispatcher before ArgoCD, preventing the direct `deploy_ldap --confirm` failure path.
- [x] **Google Identity Drift** — **COMPLETE** (`6ae2a6c3`). Implemented clean-slate login pattern (logout + explicit credentials entry).

**Infra / tooling (tracked here):**

| Item | Status | Notes |
|---|---|---|
| GCP node readiness timeout | COMPLETE | Extended to 300s (`c65f0c90`). |
| GCP latch-on selector gap | COMPLETE | `gcp_login.js` hardened with "Agree and continue" + "Confirm" (`e45d9a04`). |
| Google identity drift | COMPLETE | `6ae2a6c3` — implemented clean-slate login pattern. |
| Polite tab selection | COMPLETE | Hardened `acg_credentials.js` to avoid hijacking active page (RCA 1 fix: `131dca33`). |
| Gemini CLI Throttling | OPEN | Policy-driven traffic prioritization may cause capacity errors. |
| macOS CDP Direct Launch | OPEN | `open -a` can reuse an existing Chrome instance and fail to apply CDP flags; bug doc is now scoped as a problem statement, not an implementation script. |
| SSH Tunnel timeouts | OPEN | Connection resets during heavy ArgoCD sync |

**App-layer bugs** live in their repos as GitHub Issues:

- `wilddog64/shopping-cart-order#26` — RabbitMQHealthIndicator NPE on stale `:latest` image; fix in `rabbitmq-client 1.0.1`, remediation is rebuild + rollout.

---

## Roadmap

- **v1.1.0** — Unified ACG automation AWS + GCP (IN PROGRESS on `k3d-manager-v1.1.0`; extraction plan now defined for browser automation)
- **v1.2.0** — k3dm-mcp (gate: v1.1.0 AWS+GCP fully provisioning; two cloud backends)
- **v1.3.0** — Home lab on Mac Mini M5 (`CLUSTER_PROVIDER=k3s-local-arm64`); home automation plugins
- **No EKS/GKE/AKS** — k3d-manager is kops-for-k3s; cloud-managed k8s is out of scope
