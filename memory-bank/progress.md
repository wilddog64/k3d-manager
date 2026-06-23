# Progress — k3d-manager

## Status (v1.7.2 — trunk-based off `main`; v1.7.1 RELEASED 2026-06-19)

Trunk = `origin/main` @ `e507f7be`. Live/in-flight work and open loose ends are tracked in `activeContext.md`. Full per-task verification history for shipped work is in `archive/progress-2026-06-22.md` (and `archive/progress-v1.4.2-v1.4.8.md`).

### In flight (handed to Codex / awaiting)
- **ESO Phase 2** — ClusterSecretStore + external Vault auth. Spec `docs/plans/v1.8.0-eso-phase2-clustersecretstore-vault.md`, branch `feat/eso-phase2-clustersecretstore` (origin `02628d3`). Codex-ready. Detail in `activeContext.md`.
- **lib-acg absorption Phase 2 + agy retarget** — spec `docs/plans/v1.8.0-acg-absorb-phase2-agy-rewire.md`, branch `feat/v1.8.0-acg-absorb-phase2-agy` (origin `f612c306`). Handed to Codex. Depends on lib-foundation `_sts_valid` fix (upstream-first, `feat/v0.4.1`) + `agy --help` flag verification.

### Recently shipped (this cycle)
- **PR #97** — app-cluster ESO operator generator + data-layer routing label — MERGED to main (`e507f7be`).
- **Go rewrite PR1:** shopping-cart-order #33 MERGED (`81401ba`), shopping-cart-payment #23 MERGED (`ff817b8`); both went through Copilot rounds 2–5 (PCI card-zeroing, currency trim, tx error-cause, locked-row gateway IDs, RabbitMQ vhost double-escape, Go CI integration gates). enforce_admins restored; `feat/go-rewrite-pr2` cut on both. **PR2 = Keycloak JWT/JWKS + RBAC (next).**
- **agy migration:** lib-acg PR #45 (`1da2df7`) + lib-foundation PR #31 (`7d72876`) merged; subtree-pulled into k3d-manager; `make credential-test PROVIDER=aws` live-verified. Start-Sandbox viewport regression re-fixed via `_robustClick` (see [[reference_playwright_viewport_click]]).
- **lib-acg → lib-foundation absorption v0.4.0** — MERGED + tagged (cross-repo; lib-foundation). See [[project_lib_acg_absorption]].
- **Pre-push hook rollout** — `.githooks/pre-push` (block direct main push) committed across shopping-cart repos + k3d-manager; pre-commit relocated to `.githooks/`.
- **Branch-protection consistency** — all 9+2 active repos now `enforce_admins=true` + 1 review.

---

## Future milestones (specs written, not started)

- **Observability (OCI)** — `docs/plans/v1.7.0-observability-oci.md`: kube-prometheus-stack on OCI ARM64; Prometheus agent mode on laptop+ACG with remote_write; Grafana via `grafana.3ai-talk.org`. Gates on OCI cluster live.
- **Self-Healing** — `docs/plans/v1.8.0-self-healing-alertmanager-webhook.md`: Alertmanager→k3dm-webhook, 5 handlers (VaultSealed, ArgoCDAppOutOfSync, ESOSecretStale, PodCrashLooping, ACGClusterUnreachable); per-(alert,cluster) cooldown. Gates on webhook + monitoring.
- **Blue/Green + Stress** — `docs/plans/v1.9.0-blue-green-argo-rollouts.md`: Argo Rollouts + vCluster blue/green on OCI; stress-runner (k6, ARM64); AnalysisTemplate spins ephemeral full-stack vCluster → k6 → cleanup; `autoPromotionEnabled: false`. Gates on v1.5.0 + observability.

---

## Released versions (detail in archive + CHANGELOG + git tags)

| Version | Released | PR / SHA |
|---------|----------|----------|
| v1.7.1 | 2026-06-19 | #96 `0c9b2707` |
| v1.7.0 | 2026-06 | #95 `e6156a2a` (k3s-hostinger provider) |
| v1.6.4 | 2026-06-10 | #93 `e282048` |
| v1.6.3 | 2026-06-07 | #92 `0d8d240` |
| v1.6.2 | 2026-06-05 | — |
| v1.6.1 | 2026-06-05 | — |
| v1.6.0 | 2026-06-04 | k3dm-webhook server + ArgoCD upgrade pipeline |
| v1.5.3 | 2026-06-01 | — |
| v1.5.2 | 2026-06-01 | — |
| v1.5.1 | 2026-05-31 | — |
| v1.5.0 | 2026-05-31 | passwordless sudo + OCI |
| v1.4.12 | 2026-05-29 | — |
| v1.4.9 | 2026-05-22 | #79 `160a5ed` |
| v1.4.8 | 2026-05-19 | #77 |

Older releases (v1.4.2–v1.4.8): `archive/progress-v1.4.2-v1.4.8.md`.
