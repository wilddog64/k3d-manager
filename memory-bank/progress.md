# Progress — k3d-manager

> Compressed 2026-08-21. Settled fix entries collapsed to pointers; detail is in
> `memory-bank/archive/progress-2026-08-19.md`, `docs/issues/`, release notes, and git.

## Releases

| Version | State |
|---|---|
| v1.26.0 | RELEASED — PR #117 `1bbe5439`, tag v1.26.0 + GitHub release published, branch protection restored (enforce_admins=true, 1 required approval). Shipped 3/5 scopes. |
| v1.25.0 | RELEASED — PR #116 `d48e465f`, tag/release published, protection restored |
| v1.24.1 | RELEASED — PR #115, tag and GitHub release published |
| v1.24.0 | RELEASED — PR #113, tag and GitHub release published |
| v1.23.0 and earlier | RELEASED — see `CHANGELOG.md` |

## v1.26.0 queue

- [x] **Fleet node lifecycle (count-agnostic)** — Phase A shipped as lib-foundation `v0.4.12`
  (PR #43 `c4f3211`, Copilot addressed `32ce9c9`, tag/release live; subtree-pulled into
  `scripts/lib/foundation` `e60dff69`/`2c083258`). Phase B implemented `b0fe320a`
  (`ACG_AGENT_COUNT`-driven hosts/nodes, parallel+idempotent SSH/SSM joins with per-node
  readiness, `make fleet-render|validate|plan|up` rungs; `scripts/etc/acg-cluster.yaml`
  unchanged). **Live-verified** at `ACG_AGENT_COUNT=4` (5 nodes = ACG cap): two live-only
  defects found + fixed + re-verified — `_k3s_agent_is_ready` false-negative (private-IP
  exact-match resolver in `shopping_cart.sh`) and `fleet-plan` invalid `--no-execute`/missing
  params (rewritten to `create-change-set --change-set-type CREATE` on a throwaway stack).
  Suite 17/17; teardown clean (0 EC2, stack gone, ArgoCD == baseline). Commits `46bfdf1c` +
  `35e9ecf2`, pushed + origin-verified. Findings:
  `docs/bugs/2026-08-21-fleet-phaseb-live-verification-findings.md`. **DONE.**
- [x] **E2E promotion-gate integration with durable success/failure artifacts** — live GREEN
  2026-08-21. `e2e_verify_vcluster` on the hub; the Playwright suite failed and the harness
  captured it faithfully: durable artifact `~/.k3dm/e2e/1787338912-32712.json`, result-event
  ConfigMap in `platform-ops`, exporter `e2e_run_info`/`e2e_last_run_pass=0`
  (fires `E2EVerificationFailing`)/`e2e_last_run_timestamp_seconds`. Full chain proven. Minor
  Finding 1a (empty duration metric) filed, not fixed.
  Evidence: `docs/bugs/2026-08-21-lifecycle-e2e-live-acceptance-findings.md`.
- [x] **Verify unknown/out-of-sync cleanup without mutating unrelated live Applications** —
  live GREEN 2026-08-21. Faithful full-ACG run on expired sandbox `604492140645`: 10 appset
  apps + 23 survivors + hostinger baseline; post-cleanup 23 survivors EXACT match, hostinger
  untouched. Found + fixed BLOCKING Finding 2a (`cleanup-stale-clusters` hung — now deletes
  Secret first + non-blocking `--wait=false`; BATS asserts order+wait 2/2; re-verify 3s, 0
  orphans). Commit `0274fdde`, pushed. Medium Finding 2b (dispatcher strips `--confirm`) filed.
- [x] Lifecycle cleanup foundation — registration metadata + dry-run/confirm
  `cleanup-stale-clusters`, provider/grace/retain guards, generated-Application-only deletion,
  JSONL audit (`f90c8e0d`).
- [ ] Keep all new work within the five-plan milestone limit (at 5/5 — split before a 6th).
- [x] 2026-08-20 provisioning/recovery batch (all pushed on `k3d-manager-v1.26.0`, each with a
  `docs/issues/2026-08-20-*.md` record + BATS/shellcheck evidence): k3s-aws SSM→SSH fallback
  (`fef71219`/`40f1d19a`/`2424f55f`), kubeconfig TLS SAN loopback (`3603b60c`), SSM Vault-bridge
  selects SSH, data-layer CoreDNS + guarded `make down CLEANUP_STALE=1` (`316f26d2`/`20a13862`/
  `f24c0c96`, implies `--keep-hub`), hostinger-only hub rebuild, stale unknown-Application match
  fix (`2f4de4fd`), ACG credential s2-404 + CDP-listener recovery (`f6bb7bb`/`c7f7b37`),
  cloudflared IPv4-loopback pin (`929ebed7`).
- [x] Dependabot alert #6 (js-yaml `3.15.0`, CVE-2026-59870, dev-only transitive) — fixed
  upstream as lib-foundation `v0.4.11` (PR #42 `b92f494`), subtree-pulled (`1bf1d2ce`, lockfile
  `3.15.1`). Reads `open` only because Dependabot scans main; auto-closes when v1.26.0 → main.

## v1.27.0 queue

- [x] **CVE panel ② ("Shopping-cart Unique CVEs") POPULATED + Prometheus-verified + DURABLE
  (2026-08-24)** — 75 actionable `trivy_vulnerability_inventory{image_repository=~"wilddog64/
  shopping-cart-.*"}` series, native operator-generated (self-refreshing 24h TTL). Three commits:
  scan-job CPU request `50m→10m` (`8bfcbcc9`) + `trivy.slow`/`timeout 15m0s` (`49477017`) +
  **native private-image scanning via `operator.privateRegistryScanSecretsNames` (`aac9cb27`)** in
  `trivy-operator-acg-values.yaml`. Real root cause: workloads carry NO imagePullSecret anywhere
  (node-level containerd cred, invisible to operator) — so operator-upgrade is a dead end; the
  named-secret-per-namespace config is the fix. Live-verified; manual-CR stopgap (352 all-sev) was
  deleted in favor of native (75 actionable). Bug doc:
  `docs/bugs/2026-08-24-trivy-operator-skips-private-images-sa-imagepullsecret.md`.
  **Close-out (2026-08-24):** `acg-trivy-operator` ArgoCD-synced (3 OutOfSync res converged; ref
  contains `aac9cb27` so private-registry env survived; Synced/Healthy, panel ② held at 75) +
  `allow-cve-scan-egress` netpol durable-home spec'd + pushed to shopping-cart-payment
  (`feat/trivy-scan-egress-netpol` `3ca0dca`, PR gated).

- [x] **Hostinger CVE inventory manifest authoring** — commit `84817d88`: added the
  Hostinger-only read-only SA/ClusterRole/Binding ApplicationSet, Vault-backed ESO
  `app-cluster-kubeconfig` ExternalSecret, platform-ops ApplicationSet wiring, and minimal
  exporter warning. Focused provider suite 54/54; full curated-suite failures are recorded in
  `docs/issues/2026-08-22-manifest-authoring-test-failures.md`. No live mutations performed;
  pushed to `k3d-manager-v1.27.0`. PR: none per user instruction.

- [x] Investigated CVE dashboard empty tables (2026-08-22): platform data is present in Prometheus and
  Grafana's datasource API; shopping-cart is empty because hub-only exporter scope excludes the remote
  Hostinger cluster, and remediation event metrics have no current records. Issue evidence:
  `docs/issues/2026-08-22-cve-dashboard-empty-tables.md`. Remote inventory aggregation and durable
  remediation-event retention remain follow-up work.

- [~] **hostinger CPU right-sizing (2026-08-24)** — node `srv1754834` request-bound (98% CPU
  requests / ~20% actual). Durable overlay fix committed `6851b5b0`: payment cpu 200m→50m +
  maxSurge=0 on basket/order/frontend (deadlock class). Builds verified. **Inert until the
  `services-git` appset is reapplied at v1.27.0** (frozen at v1.26.0; `services/` byte-identical so
  only this fix moves). Live patch won't stick (selfHeal). **Status 2026-08-24:** (a) services-git
  reapply rendered+diff-verified (apply classifier-blocked → user `!` cmd); (b) ✅ rabbitmq 200m→50m
  MERGED (PR #93 `59ed6342`, enforce_admins restored, trim live on ref=main); (c) istiod pilot cpu
  100m→50m `1dbe68dc` (maxSurge=100% is a non-overridable istio chart default; request trim shrinks the
  surge pod; reapply rendered+diff-verified → user `!` cmd).

Scope = 4 plan docs (4/5, under cap). Dependency-ordered load-split leads; decision
2026-08-21 "keep all four".

- [x] **Foundation-managed vCluster CLI** (`docs/plans/v1.27.0-foundation-managed-vcluster-cli.md`)
  — **COMPLETE.** Part A = lib-foundation `v0.4.13` (Codex `b2adb8f2` → PR #44 `0a3e4043`; Copilot
  caught a real `curl -o` after-`--` bug, fixed + BATS-tightened; subtree-pulled into
  `scripts/lib/foundation`, curl fix intact). Part B = HEAD `142fd06b` on `origin/k3d-manager-v1.27.0`
  (Codex; its `6c2dd94d` note was amended away): removes the consumer installer, adds module-scoped
  `_VCLUSTER_BIN`, rewires `_vcluster_check_prerequisites` to
  `foundation_ensure_vcluster_cli "$VCLUSTER_VERSION"` (guards non-zero+empty), routes all 6 lifecycle
  invocations through it, updates help/docs, reworks BATS to stub the contract. Claude re-ran gates
  (BATS 36/36, shellcheck/`bash -n` clean, disappearance greps empty, subtree untouched) + **live
  `make e2e` CLI-contract gate PASSED** (real download+SHA+atomic install of vcluster `0.32.1` managed
  path, substrate rolled out inside the throwaway vCluster; artifact/ConfigMap/exporter carry
  `9b3a5754`). Playwright app Job failed pre-existing (not the CLI change). PR = release-time step.
  - ⚠️ Finding 1a (empty `e2e_last_run_duration_seconds` failing the whole scrape) — ✅ FIXED
    `5cd67228` (`num()` coercion). `docs/issues/2026-08-21-e2e-exporter-empty-duration-metric.md`.
- [~] **M2 remote E2E runner** (`docs/plans/v1.27.0-m2-remote-e2e-runner.md`) — SSH-dispatch
  ephemeral E2E to m2-air, restricted M4-side publisher → hub ConfigMap → Grafana. The actual
  E2E load-split off the M4 laptop. **Depends on the foundation vCluster CLI.**
  Increments 1–6 DONE (inc 6 = failure behavior + operations, `b5fff9c4`, 68/68 BATS green).
  **Publish-back source-pin durability DONE 2026-08-24:** commit `0cf69e28` adds optional
  `E2E_PUBLISH_FROM` handling while preserving the unpinned authorized_keys line, and forces
  `AddressFamily=inet` for publish-back SSH. Focused BATS `68/68`, `bash -n`, ShellCheck, and
  explicit default-path proof passed. No live SSH or authorized_keys access; no PR per instruction.
  **Remaining: 2-run live acceptance gate (1 fail + 1 pass via `make e2e-remote RUNNER=m2`)
  + live redeploy of the inc-2 runner-labelled exporter/dashboard/rule.** Image-arch blocker
  CLEARED 2026-08-24: multiarch PR **#7 MERGED** (`90c13994`, shopping-cart-e2e-tests) →
  `:latest` rebuilt multiarch, VERIFIED amd64+arm64 (`docker manifest inspect`, run
  `32725667211`). Publish-back CONFIGURED 2026-08-24: restricted key `~/.ssh/e2e-m4-publisher`
  on M2 + M4 forced-command `authorized_keys` entry + `E2E_M2_PUBLISH_BACK_HOST=cliang@m4-air.local`
  in gitignored `.envrc` (`source_up`); M2→M4 smoke test auths + forced command fires + bad payload
  rejected (no ConfigMap). Only remaining gate = hostinger node CPU exhaustion (see activeContext).
- [ ] **Image signing / CVE-loop closure** (`docs/plans/v1.27.0-image-signing-cve-loop-closure.md`)
  — cosign sign+attest, Kyverno Audit→Enforce, promoter verify gate. Multi-repo, heavy.
- [x] **Image-signing Part 0 — `signing.sh` plugin** (Slice A) — DONE, Claude-verified `e1ef0037`
  on `origin/k3d-manager-v1.27.0`. Lazy signing plugin (seed/rotate/status), pub-only ESO template,
  read-only Vault policy, structural BATS 6/6; shellcheck clean. Codex generated (session
  `01a0363c`); Claude committed (Codex sandbox `.git` read-only) after trimming an over-privileged
  `_signing_configure_writer` (kyverno-bound create/update role — parent-plan line 270 / OWASP A01).
- [ ] **Adaptive checkout load testing** (`docs/plans/v1.27.0-adaptive-checkout-load-testing.md`)
  — API-level checkout load + Grafana/Prometheus telemetry + small browser cohort.
  - [x] Part 0 controller (Slice E) — commit `17be2e69` pushed to
    `origin/k3d-manager-v1.27.0`: pure stage-ladder + stop-condition-hysteresis decision logic,
    immutable jq summaries, opt-in guard, and BATS 9/9. Syntax, warning-level ShellCheck, and
    Bash `_agent_audit` passed. No cluster/Prometheus/k6/Stripe (that is Slice F, live). PR URL:
    none (task prohibits PR creation).
- Both load-split plans were promoted from v1.26.0-deferred (renamed `v1.26.0-*` →
  `v1.27.0-*`, headers/cross-refs updated) on 2026-08-21.

## Verification record

- v1.25.0 release validation: E2E BATS 16/16; webhook BATS 54/54; syntax/shellcheck gates
  passed; Copilot findings resolved before merge.
- Node-health watchdog and E2E diagnostics hardening shipped in the released branch.
- Prometheus/Grafana recovery, status retry, remediation-table cleanup, and Slack status/thread
  fixes are shipped; remaining live follow-ups are in `activeContext.md`.

## Process

- Every implementation updates this file and `activeContext.md` with the real commit/PR SHA.
- Unexpected live failures get a dated `docs/issues/YYYY-MM-DD-*.md` record with verbatim
  evidence.
- Historical specs/issues are archived only when superseded or unreferenced; files are never
  deleted.
