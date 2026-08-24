# Active Context — k3d-manager

> Compressed 2026-08-24 (CVE panel ② saga closed → collapsed to pointers). Settled fixes
> live as pointers; detail in `memory-bank/archive/`, `CHANGELOG.md`, `docs/retro/`,
> `docs/issues/`, `docs/bugs/`, git history, and auto-memory.

## Current focus

- **v1.27.0 active branch** (`k3d-manager-v1.27.0`, branched from v1.26.0 merge). **Scope = 4 plan
  docs (4/5, under cap)**, dependency-ordered load-split leads (decision 2026-08-21 "keep all four"):
  1. `v1.27.0-foundation-managed-vcluster-cli.md` — **COMPLETE.** Part A = lib-foundation `v0.4.13`
     (PR #44 `0a3e4043`, subtree-pulled). Part B = HEAD `142fd06b` rewires `vcluster.sh` to
     `foundation_ensure_vcluster_cli` (module-scoped `_VCLUSTER_BIN`, guards non-zero+empty). Claude
     re-ran gates (BATS 36/36, shellcheck/`bash -n` clean, disappearance greps empty, subtree
     untouched) + **live `make e2e` CLI-contract gate PASSED** (real download+SHA+atomic install of
     vcluster `0.32.1` managed path; substrate rolled out; artifact/ConfigMap/exporter carry
     `9b3a5754`). Playwright app Job failed pre-existing (not the CLI change). No PR yet (release-time).
  2. `v1.27.0-m2-remote-e2e-runner.md` — **Increments 1–6 DONE** (inc 6 `b5fff9c4`, BATS 68/68).
     Producer runner-provenance, consumer/exporter+Grafana `runner` dim, `e2e_remote.sh`
     preflight/bootstrap/dispatch/restricted-publisher/lock+ops, `make e2e-remote|e2e-runner-health|
     e2e-replay|e2e-runner-unlock`. **Remaining: 2-run live acceptance gate** (1 fail + 1 pass via
     `make e2e-remote RUNNER=m2`) + deferred live redeploy of the inc-2 runner-labelled
     exporter/dashboard/rule via `argocd.sh`. **BLOCKED** on (a) e2e-tests image arch — PR **#7**
     (multiarch, `sha-52ffe10a` proven amd64+arm64) awaiting merge → rebuild `:latest`; (b) hostinger
     node CPU exhaustion. Publish-back still unconfigured (`E2E_M2_PUBLISH_BACK_HOST` empty → results
     retained `publication_pending`). M2 runner fully provisioned + proven end-to-end (dispatch→SSH→
     OrbStack→k3d→vCluster→substrate→Playwright launch). See M2 bug docs under `docs/bugs/2026-08-22-*`.
  3. `v1.27.0-image-signing-cve-loop-closure.md` — cosign sign+attest, Kyverno Audit→Enforce, promoter
     verify gate. Multi-repo, heavy. **Not started.**
  4. `v1.27.0-adaptive-checkout-load-testing.md` — API-level checkout load + telemetry. **Not started.**
  - Finding 1a — ✅ FIXED + live-verified `5cd67228` (`num()` coerces empty/None→0 so one malformed
    value can't zero the scrape; `up{exporter}=1`, both E2E + CVE dashboards receiving data).
    `docs/issues/2026-08-21-e2e-exporter-empty-duration-metric.md`.
  - Finding 2b — dispatcher `--confirm` strip on `deploy_app_cluster` (OPEN).
    `docs/issues/2026-08-21-dispatcher-strips-confirm-deploy-app-cluster.md`.

- **v1.26.0 RELEASED** — PR #117 `1bbe5439` merged, tag/release published, protection restored
  (`enforce_admins=true`, 1 approval). Shipped 3/5 scopes (fleet count-agnostic lifecycle, E2E
  promotion gate + observability, managed registration cleanup). Retro
  `docs/retro/2026-08-21-v1.26.0-retrospective.md`. v1.25.0 = PR #116 `d48e465f`.
- v1.28.0 planned: parallel multi-cloud provisioning + zero-downtime rollouts.

## Open follow-ups

- **✅ CVE panel ② ("Shopping-cart Unique CVEs") — RESOLVED + DURABLE (2026-08-24).** 75 actionable
  `trivy_vulnerability_inventory{image_repository=~"wilddog64/shopping-cart-.*"}` series, native
  operator-generated (self-refreshing 24h TTL), Prometheus-verified. Three durable commits in
  `trivy-operator-acg-values.yaml`: `49477017` (`trivy.slow`+`timeout 15m0s`) + `8bfcbcc9` (scan-job
  CPU request `50m→10m`) + **`aac9cb27` (`operator.privateRegistryScanSecretsNames` +
  `accessGlobalSecretsAndServiceAccount: true`)**. Real root cause: workloads carry NO imagePullSecret
  anywhere (pod spec AND `default` SA empty) → private images pull via node-level containerd cred,
  invisible to the operator → silent skip; operator-upgrade is a dead end. Manual-CR stopgap (352
  all-sev) deleted in favor of native (75 actionable). Hub-side wiring (RBAC/ESO/appset `84817d88`,
  live Vault SA + policy fixes `9c9c8bb8`/`0f7ea0ad`) complete + verified end-to-end.
  Bug: `docs/bugs/2026-08-24-trivy-operator-skips-private-images-sa-imagepullsecret.md`.
  Auto-memory: `reference_trivy_operator_node_cred_private_image_skip`.
  - **Remaining (release mechanics, non-blocking; live behavior already correct):**
    (a) `acg-trivy-operator` shows 3 resources OutOfSync (two configmaps + deployment env patched
    live) → converge via `argocd app sync acg-trivy-operator` or release-time observability-acg
    appset reapply at v1.27.0. (b) `allow-cve-scan-egress` netpol (live-applied, podSelector
    `app.kubernetes.io/managed-by=trivy-operator`, needed because payment's `default-deny-all` blocks
    the in-namespace scan pod) needs a durable home in the **shopping-cart-payment** repo (cross-repo,
    spec+Codex, gated). The originally-planned (a) pod-spec imagePullSecrets / (b) scan-CR CronJob /
    (c) operator upgrade are UNNECESSARY / redundant+harmful / dead — see bug doc "reassessed".
  - ⚠️ The 2026-08-23 "ArgoCD stale-render bug" was a **mis-diagnosis** (I read the hub's own trivy
    configmap, not hostinger's `acg-trivy-operator`, which has no `automated` syncPolicy so manual
    patches stick). Durable git fixes are correct + live.

- **Keycloak hub deploy DONE + dev SSO RESOLVED (2026-08-22).** `keycloak-0` 1/1, VirtualService
  live (`keycloak.3ai-talk.org/realms/master` 200); port-forward remote-port bug fixed (`04cc1e14`,
  →8080). Realm `home` (`dc=home,dc=org`) is the DESIGNED truth; admin/developer/operator synced,
  the only gap was missing LDAP passwords — fixed `bin/cluster-up` step 10d.5 seed loop (`9efb23f7`)
  + live `seed-dev-sso-passwords.sh` (all 3 verified via ldapwhoami, mirrored to
  `secret/keycloak/users/*`). Steps 10d.6/10d.7 realm-federation reconcile are broken+redundant →
  follow-up: delete or retarget `-r home`. **SSO login round-trip to realm `home` still to be
  confirmed by user.** Docs `docs/bugs/2026-08-22-keycloak-*`, `-hub-openldap-wrong-realm-*`.

- **hostinger istiod-scheduling cascade RESOLVED — 3/3 (2026-08-22).** Single 2-CPU node
  `srv1754834` chronically 95–98% CPU requests; istiod Pending 2d → ambient mesh down →
  product-catalog CrashLoop + frontend stuck. Break-glass restored istiod+frontend; product-catalog
  durable via PR #49 `505f758a` (cpu 100m→50m). **ArgoCD source gotcha (keep):** the hub app reads
  `repo=k3d-manager rev=k3d-manager-v1.26.0` whose kustomization pulls REMOTE
  `shopping-cart-product-catalog//k8s/base?ref=main`; a `refresh=hard` annotation re-fetched `ref=main`
  → OutOfSync, user-run `kubectl patch cpu=50m` landed it (durable, selfHeal won't revert).

- **Other live/tracked follow-ups:**
  - Replace the interim in-cluster CVE promoter git-writer token with a fine-grained
    contents-write-only PAT.
  - Reconcile stale port-forward/LaunchAgent state on public Grafana/status probe failures
    (`reference_single_service_502_zombie_port_forward` in auto-memory).
  - Re-seed display-only Vault paths wiped in rebuild (Prometheus basic-auth, ArgoCD/Grafana
    mirrors) — display-only, not ESO-managed; `make show-service-passwords` triage in
    `reference_show_service_passwords_na_root_causes`. Hub Prometheus is UNAUTHENTICATED (rotate fn
    targets ACG, not hub).
  - Keep ArgoCD smoke credential-drift + k3s-aws SSM registration issues visible in `docs/issues/`
    until their live follow-ups close. Account-level SSM Default Host Management Role optional.
  - Dependabot alert #6 (js-yaml) remediated as lib-foundation `v0.4.11` (subtree `1bf1d2ce`,
    lockfile `3.15.1`); reads `open` only because Dependabot scans main → auto-closes when
    v1.26.0 → main. Dev-only transitive, low risk.

## Operating decisions

- `make status` follows the active provider (concise/full/JSON); Slack reuses the same summary contract.
- CVE remediation current-state excludes terminal `superseded`/`deployment_advanced` events; history
  keeps the audit trail. Verifier cadence/bounds stay conservative under hub load.
- E2E runs use a throwaway vCluster, pinned service images, runtime-generated datastore credentials,
  and an EXIT-trap result artifact written before teardown.
- Do not deploy source-only changes until their release-branch/PR gates + live verification are explicit.
- When the laptop Vault reverse bridge is required (`HUB_VAULT_USE_BRIDGE=1`, default), k3s-aws selects
  SSH and overrides explicit SSM with a warning; SSM stays available for non-bridge Vault profiles.

## Canonical pointers

- Roadmap: `docs/roadmap.md`
- v1.27.0 plans: `docs/plans/v1.27.0-*`
- Active bugs/incidents: `docs/bugs/` and `docs/issues/`
- Release history: `CHANGELOG.md` and `docs/retro/`
