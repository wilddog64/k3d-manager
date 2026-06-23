# Active Context — k3d-manager

## Current Status (v1.7.2 — trunk-based off `main`; v1.7.1 RELEASED 2026-06-19)

Trunk = `origin/main` @ `e507f7be` (v1.7.1 `0c9b2707` #96 + PR #97 ESO operator generator). Adopted trunk-based flow after the multi-branch sprawl reset (2026-06-21). Full history of completed work is in `archive/activeContext-2026-06-22.md` (and `progress.md`).

---

## Active work streams

### 1. ESO Phase 2 — ClusterSecretStore + external Vault auth (Codex-ready, awaiting handoff)
- **Spec:** `docs/plans/v1.8.0-eso-phase2-clustersecretstore-vault.md`
- **Branch:** `feat/eso-phase2-clustersecretstore` (origin tip `02628d3`)
- 4 user decisions baked in: (1) Vault hop = **Istio ingress + VirtualService** on wildcard `istio-system/default-gateway` (HTTP:80, no gateway edit), cloudflared `vault.3ai-talk.org`→`localhost:18080`→istio-ingressgateway:80, TLS at Cloudflare edge; (2) guardrails = **all 3** (Cloudflare Access + WAF/IP + k8s-auth/policy); (3) `eso-reader` **widened** to enumerated app prefixes `secret/{data,metadata}/{postgres,payment,rabbitmq,redis,minio}/*` (current `secret/data/eso/*`-only policy covers NONE of the live shopping-cart-infra ExternalSecrets); (4) mount **`secret` KV v2** now — **Postgres→`database/` dynamic engine = Phase 3** (separate spec, reuses CSS/ingress/auth).
- Changes: 1 CSS manifest, 2 ApplicationSet, 3 Istio VS + vars + cloudflared, 4 `_hostinger_register_cluster` guarded `configure_vault_app_auth` call + policy HCL widen. Reuses `configure_vault_app_auth` (vault.sh:~1315) + VS pattern.
- **Runner-wiring gap (fold into Phase 2):** `scripts/tests/etc/argocd_platform_project.bats` is NOT discovered by the `test` runner on this baseline (no `scripts/tests/etc/` scan).

### 2. lib-acg absorption Phase 2 + agy retarget (handed to Codex)
- **Spec:** `docs/plans/v1.8.0-acg-absorb-phase2-agy-rewire.md`
- **Branch:** `feat/v1.8.0-acg-absorb-phase2-agy` (origin `f612c306`)
- Combined spec: re-pull lib-foundation → `git rm -r scripts/lib/acg` (collapse 2 subtrees→1) → repoint `scripts/plugins/acg.sh` stub + `scripts/plugins/gemini.sh` cdp source to `scripts/lib/foundation/scripts/lib/acg/` → fix template/test paths → drop `lib-acg` remote → agy retarget of `gemini.sh` (`agy --dangerously-skip-permissions`).
- **Pre-handoff dependencies:** (a) lib-foundation `_sts_valid` bug (acg-credential-test) — fix **upstream-first on `feat/v0.4.1`** before Codex runs the subtree pull; (b) agy prompt/model flags are undocumented — Codex must verify via `agy --help` (only `--dangerously-skip-permissions` confirmed).
- Context: lib-acg absorbed into lib-foundation **v0.4.0 — MERGED + TAGGED** (PR #32 `aed8c56`, tag `v0.4.0`, release published). See [[project_lib_acg_absorption]], [[project_antigravity_migration]].

---

## Open loose ends (need user go)

- **webhook `/gemini`→agy retarget:** `_call_gemini` (`bin/k3dm-webhook:897`) still calls gemini-cli. Bugfix spec `docs/bugs/2026-06-21-webhook-call-gemini-agy-retarget.md`; lands on a k3d-manager branch then `make restart-webhook`.
- ~~Delete bogus branches `feat/v0.1.8` + `feat/ensure-agy-cli`~~ **DONE 2026-06-23** (local+origin; commits preserved under salvage tags `salvage/agy-cdp-wrong-repo` `c84f6a5d`, `salvage/agy-ensure-cli-wrong-repo` `8c4e44dc`).
- ~~Branch cleanup~~ **DONE 2026-06-23** — deleted 15 branches (local+origin): 2 bogus agy + 13 tagged release (`v1.5.0..1.5.4` [v1.5.4 docs-only, retro on main], `v1.6.0..1.6.5`, `v1.7.0`, `v1.7.1`). **STILL HELD (real unmerged content):** `k3d-manager-v1.7.2`+`backup/v1.7.2-before-revert` (carry the provider-generic platform fix — see below); `docs/next-improvements` (162 commits, NO merge-base with main — anomalous, investigate separately).
- ~~15 git stashes~~ **DROPPED all 15 (2026-06-23)** — verified debris (obsolete pre-absorption subtree state + trivial memory-bank deltas + ancient WIP on shipped branches).
- ~~main missing the provider-generic platform AppProject fix~~ **RESOLVED via (a), 2026-06-23.** Verified `5a3e6f48` (`platform.yaml.tmpl` `name:'*'` ×7 + `eso.yaml` destination + `scripts/tests/etc/argocd_platform_project.bats`) is **already an ancestor of the ESO branch** and in its diff-vs-main → it reaches main when the ESO Phase 2 PR merges. Preserved as tag `salvage/platform-appproject-provider-generic`. Added **Change 5** to the ESO Phase 2 spec (`7d417a9e`): wires the `test` runner to scan `scripts/tests/etc/` (`scripts/k3d-manager` lines ~174 + ~435) so `argocd_platform_project.bats` actually runs in `test all` + CI — without it the test exists but is never executed. (Note: `scripts/tests/lib/acg_session_check.bats` is a separate acg-subtree concern, handled by the lib-acg absorb Phase 2, not here.)
- **Rotate** hardcoded `SLACK_BOT_TOKEN`/`SLACK_SIGNING_SECRET`/webhook in `.claude/settings.local.json`.

---

## Recently shipped (cross-repo, this cycle)

- **Go rewrite PR1:** shopping-cart-order #33 MERGED (`81401ba`) + shopping-cart-payment #23 MERGED (`ff817b8`); enforce_admins restored; `feat/go-rewrite-pr2` branches cut. **PR2 = Keycloak JWT/JWKS + RBAC (next).**
- **agy migration:** landed upstream (lib-acg PR #45 `1da2df7`, lib-foundation PR #31 `7d72876`), subtree-pulled into k3d-manager, `make credential-test PROVIDER=aws` live-verified.
- **lib-acg→lib-foundation absorption v0.4.0:** MERGED + tagged (lib-foundation). See memory files.

---

## Notes
- Full per-task verification history (Go-rewrite Copilot rounds 2–5, pre-push hook rollout, preflight bugfix batch, trunk-reset detail) → `archive/activeContext-2026-06-22.md`.
