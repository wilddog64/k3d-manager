# Progress — k3d-manager

## Status
v1.14.0 RELEASED 2026-07-12 · v1.15.0 RELEASED 2026-07-14 · **v1.16.0 active — Istio ambient mesh**.

> Full per-item detail (gate dumps, live-verify logs) archived 2026-07-19 → `memory-bank/archive/progress-v1.16.0-detail-thru-2026-07-19.md`. Older: `progress-v1.6.5-v1.15.0.md`, `-v1.6.x-v1.6.4.md`, `-v1.4.2-v1.4.8.md`.

## v1.16.0 — DONE + CLAUDE-VERIFIED on `origin/k3d-manager-v1.16.0` (all one file unless noted)
- [x] `1cc55252` — pin hub k3d image `v1.32.0-k3s1` (istioctl precheck floor). Live-verified: fresh hub reports v1.32.0+k3s1, 0×IST0142.
- [x] `e118f664` — add `shopping-cart` AppProject + `_argocd_deploy_appproject` loop (2 files). Live e2e: appset ErrorOccurred cleared, `ubuntu-k3s-data-layer` generated.
- [x] `64168cc7` — permit `secrets` namespace in the `shopping-cart` AppProject for `vault-bridge`. One file; +8 lines. **CLAUDE-VERIFIED = PASS**: SHA on origin, exact message, diff byte-identical to spec, yq clean, `secrets`→4 / `shopping-cart-`→12, bats 15/15, `_agent_audit` 0; memory-bank separate commit `17ca8380`. **FRESH-REBUILD e2e PASS (2026-07-19):** `make down` (DOWN_EXIT=0) → `make up` (UP_EXIT=0) on new sandbox `739527292320`; committed template (no manual patch) → `secrets/Service/vault-bridge` Synced, `ubuntu-k3s-data-layer` Synced/Healthy, 7 data-layer + full app tier pods 1/1.
- [x] `1af15217` — right-size istiod (100m/512Mi) + ztunnel (100m/256Mi) for 2-CPU hostinger node. Code PASS; **istiod live-PROVEN 2026-07-19** (istiod 1/1 Running on ubuntu-k3s spoke after dest-validation cleared). ztunnel sizing untested (scheduled fine, but blocked on istio-cni conf/bin dir mismatch — separate spec `2026-07-17-...`).
- [x] `39788cb1` — cluster-up Step 10b: stop applying deleted data-layer manifest; key wait/sync to `${APP_CLUSTER_NAME}-data-layer`. Live: make up exit 0, abort gone.
- [x] `18b92cd2` — key `services-git` Application names by cluster (`{{.name}}-{{.path.basename}}`) + `preserveResourcesOnDeletion`. Live: 12 apps 6-per-cluster, ubuntu-k3s app tier up.
- [x] `2966a3b9` — fail loudly on unset appset envsubst vars + default `AMBIENT_ISTIO_VERSION` in bootstrap scope (3 files). Verified: render yields `targetRevision: 1.24.2`.
- [x] `89c2efd6` — app-cve-scan dispatch via wget + wget bats coverage (2 files). Verified incl. mutation A/B; network-isolation gate 0.
- [x] `babb3c80` — app-cve-scan curl→BusyBox wget. `5fcc3f89` — argocd-cve-scan fail loudly on missing infra secret (Phase 1).
- [x] Test-integrity batch `3b281a70`→`db1ed1ce`→`6f6212dd` (5 files); trivy dashboard split `4c89dabb`; argocd BATS regression fix `e3a75f1f`; ArgoCD-managed Grafana dashboards `0e8b49c3`; status not-deployed-vs-fail `3938626e`; webhook utcnow `a549a37a`; multi-app-cluster Phase 1 `2fa78e35` + Phase 3 `f03df202`; ambient Phases 1–2 (`125b797e`, `c5a730c1`, `7e88a9d5`, `bcc87f1c`) — all verified, ambient dataplane capture PASS on sandbox.

## PENDING
- [ ] **istio-ambient dest validation — SPECCED 2026-07-19, ASSIGNED to Codex 2026-07-19 (awaiting SHA).** Root cause: `_argocd_deploy_applicationsets` (`argocd.sh:1165`) defaults `APP_CLUSTER_NAME` to `ubuntu-hostinger` + never uses resolved `_active_app_cluster` → istio-ambient/observability-acg render against nonexistent cluster on k3s-aws. Spec `docs/bugs/2026-07-19-argocd-appset-loop-app-cluster-name-default.md`. Live-proven: re-render with ubuntu-k3s cleared error, 4 Applications generated, **istiod 1/1 Running (= `1af15217` istiod pod-level verify PASS)**.
- [ ] **istio-cni conf/bin dir mismatch — NEXT blocker (live-confirmed 2026-07-19), UNASSIGNED.** ztunnel `ContainerCreating`: `failed to find plugin "istio-cni"`. Already specced `docs/bugs/2026-07-17-ambient-istio-cni-conf-bin-dir-mismatch.md`; repo file unpatched.
- [ ] **app-cve-scan report-repository registry-prefix mismatch** — `docs/bugs/2026-07-18-app-cve-scan-report-repository-registry-prefix-mismatch.md`. Unassigned.
- [ ] **`app_cve_scan.bats` stubs curl not wget** (post-`89c2efd6` this is covered by the wget harness — but the standalone `docs/bugs/2026-07-18-app-cve-scan-bats-stubs-curl-not-wget.md` is SUPERSEDED; do not implement separately).
- [ ] **BLOCKED — Hub `environment=infra` registration** — `docs/bugs/2026-07-18-hub-infra-registration-blocked-platform-helm-selfheal.md`. DO NOT EXECUTE (platform-helm selfHeal → 2nd argo-cd release + downgrade). Owner decision (options A–D).
- [ ] **Triage — hub `argocd` Helm release `failed`** (rev 3, 2026-06-29). Blocks infra-registration options B/C.
- [ ] **Makefile stale ACG sandbox URL default** — `docs/bugs/2026-07-19-makefile-stale-acg-sandbox-url-default.md`. Unassigned.
- [ ] **app-cluster Vault portability** — `docs/bugs/2026-07-07-app-cluster-vault-portability.md` (hub-vault-profile global-file leak; `_hub_vault_profile_context()` returns empty on k3s-aws path). Unassigned.

## Releases
- [x] v1.15.0 (2026-07-14): PR #105 → `main` `14cdaea6`. Post-merge tag/release/retro deferred.
- [x] v1.14.0 (2026-07-12): PR #104 → `main` `5c412e15`. Tag + release + retro done.
