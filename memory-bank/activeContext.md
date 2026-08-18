# Active Context — k3d-manager

> **Compressed 2026-08-11.** Live focus + carried-forward blockers only. Shipped detail lives in
> `CHANGELOG.md` (v1.24.0 section), `docs/plans/v1.24.0-*`, `docs/bugs/v1.24.0-*`, `docs/retro/`,
> `docs/issues/`, and git history (`git log --follow memory-bank/`).

## Current focus — v1.24.1 RELEASED; v1.25.0 = workstream G (open for development)

**Maintenance update 2026-08-17:** `a638a9ca` pushed on `k3d-manager-v1.25.0`. The existing daily
`com.k3d-manager.cleanup` LaunchAgent now safely removes unreferenced Packer ISO/lock artifacts older
than 30 days and port-cache markers older than 7 days. BATS 5/5 and shellcheck passed; OrbStack/Codex
caches and active logs remain out of scope. Grafana/control-plane load investigation remains open.

**Observability recovery 2026-08-17:** `1e990cc3` pushed and deployed. Prometheus is `2/2 Running` with
zero restarts after raising the local CPU budget; kube-state-metrics and node exporters are `1/1`,
Prometheus `/-/ready` passes, and queries return 15 remediation events / 5181 inventory series. Grafana
health is database `ok`. `make status` now runs; remaining failures are stale local ArgoCD/Keycloak/product
port-forwards, not the Grafana data path.

**Remediation dashboard correction 2026-08-17:** `37b06795` pushed and deployed. `deployment_advanced`
and `superseded` events are now audit-only (`current=false`), so Current CVE Remediation Status cannot
show an unapplied terminal event as active; the History panel retains the explanation.

**Remediation table cleanup 2026-08-18:** `f60e1c07` pushed and platform-ops reconciled on the hub. The
Current CVE Remediation Status and Remediation History tables now hide the redundant `pod` column and
retain the more useful `job` column.

**Grafana 502 recovery 2026-08-18:** Grafana itself stayed healthy; Cloudflare 502 came from the local
`com.k3d-manager.grafana-port-forward` agent retaining a stale Pending pod after the dashboard restart.
The agent was fully reloaded after the replacement pod became Ready; local and public `/api/health` now
return HTTP 200. See `docs/issues/2026-08-18-grafana-502-stale-port-forward.md`.

**★ ROADMAP (sequenced 2026-08-15):** v1.25.0 (current) = Stripe/Go live acceptance + hostinger capacity + E2E harness (G) — platform PROVEN live, remaining = codify `e2e_verify_sandbox`+BATS, file the live-discovered config-gap bugfix specs for Codex, hostinger `maxSurge=0` durable commit, hand task #28 k3s-aws specs to Codex, then cut. → **v1.26.0** = fleet-node-lifecycle-Lambda (résumé-critical, [[project_fleet_node_lifecycle_lambda]]) + `docs/plans/v1.26.0-sandbox-registration-lifecycle-cleanup.md`. → **v1.27.0** = image signing (cosign sign+attest close CVE loop, [[project_image_signing_cve_loop]]; slid from v1.26.0 when fleet took the slot; spec not yet written). → **v1.28.0** = parallel multi-cloud provisioning (concurrent `make up` per provider; spec WRITTEN 2026-08-15 `docs/plans/v1.28.0-parallel-multi-cloud-provisioning.md` — provider-scope local state/ports/launchd + hub-bootstrap lock; sequential bring-up is the only safe path today).

**★ v1.25.0 E2E SMOKE — ALL 4 CONNECTION/SUBSTRATE BLOCKERS RESOLVED; SUBSTRATE PROVEN GREEN LIVE; FINAL
FULL RE-RUN PENDING (2026-08-16, Claude).** Four-layer root cause fully cracked across 6 smoke runs:
(1) proxy port drift → pin `--local-port` (`1f1f98ce`); (2) proxy port-forward death → recreate proxy in
gate (`95e09b20`); (3) syncer crash-loop from kine datastore I/O starvation → **tmpfs (memory emptyDir)
control-plane datastore** `scripts/etc/vcluster/values.yaml` (`a5485bf5`, LOCAL) + decouple probe/refresh
cadence (`2c93e702`); (4) THE decisive bug — readiness probe used a HARD `_run_command` that **exits** on
failure, so the first not-ready `/readyz` silently killed the harness at probe 1 (message swallowed by
`2>&1`); fixed to soft `_run_command --no-exit --quiet` (`3adaad5b`, LOCAL) + regression BATS. Smoke #6
became the FIRST run to pass readiness (control plane 1/1 RESTARTS 0 — tmpfs works; `[e2e] vCluster API is
ready`), apply the substrate, and reach rollout-wait. It exited 1 there on a NEW, deeper bug:
**substrate DB env-var mismatch** — `order` (now Go, reads `DB_HOST/DB_PORT/DB_NAME/DB_USERNAME/DB_PASSWORD/
DB_SSLMODE`) was fed dead `SPRING_DATASOURCE_*`; `product-catalog` (pydantic, reads `DB_HOST` etc) was fed
an ignored `DATABASE_URL`; both defaulted to `localhost` → connection-refused → CrashLoopBackOff. Fixed in
`scripts/etc/e2e/{order,product-catalog}.yaml` (`3d4e5a4f`, LOCAL) + spec
`docs/bugs/2026-08-16-e2e-substrate-db-env-var-mismatch.md`. **VALIDATED LIVE** by patching the still-running
orphan vCluster's deploys: both reached 1/1 Running (order up, product-catalog `Uvicorn 0.0.0.0:8080` +
`/health 200`); all 5 substrate services green; no RabbitMQ blocker (order publisher is lazy). LOCAL commits
ahead of origin (`81bdca1c`): `a5485bf5`, `3adaad5b`, `3d4e5a4f`. **HOLD PUSH until a full smoke goes green
through the Playwright verdict + JSON summary** (user rule). Next: teardown orphan, run smoke #7 (fresh
create → readiness → substrate → Playwright Job → `~/.k3dm/e2e/*.json`); if green, push all 3 + do Grafana
Path A live-verify. Teardown EXIT-trap still broken (orphan survived — noted in spec). Prior status ↓

**★ v1.25.0 E2E TIER 1 — READINESS GATE + GRAFANA PATH A LANDED; SMOKE STILL RED ON NEW PROXY-PORT-DRIFT
BUG (2026-08-16, Claude).** PR #6 MERGED (`edc50427`), GHCR image published, protection restored. Two
implementations landed + pushed on `k3d-manager-v1.25.0` (origin tip `6b85bb56`):
1. **Readiness gate** (`38abfab5`) — `_e2e_wait_vcluster_ready` polls `/readyz` (`E2E_VCLUSTER_READY_TIMEOUT=600`)
   between `vcluster_create` and `_e2e_deploy_substrate`. BATS ordering + timeout guards green. Closes
   `docs/bugs/2026-08-16-e2e-vcluster-api-readiness-race.md`.
2. **Grafana observability Path A** (`3a1f7ce5`) — harness `_e2e_write_result_event` publishes each run as a
   durable `k3dm.k3d.io/e2e-result=true` ConfigMap in hub `platform-ops` (best-effort, prune to N=20/svc+tier);
   `vulnerability-inventory-exporter` gains `refresh_e2e_events` + 5 `e2e_*` gauges (no RBAC widening); new
   `grafana-dashboard-e2e.yaml` + `e2e.alerts` group (E2EVerificationFailing/Stale) wired via `argocd.sh`.
   BATS `e2e_observability.bats` (7) + writer tests green; py_compile clean. Implements
   `docs/plans/v1.25.0-e2e-observability-path-a.md`. **Live-verify still PENDING** (needs a green smoke to
   emit a real ConfigMap → series → dashboard).
**Live re-run of the smoke fired the gate correctly ("Waiting for vCluster API") but STILL exited 1** — a
**separate, deeper defect** the gate exposed: **vcluster is 0.36.1 (NOT 0.32.1 as memory said)**; 0.36.x
connects via a **background-proxy docker container on a RANDOM host port**, and `_vcluster_export_kubeconfig`
(vcluster.sh:246, `vcluster connect --print`) hard-codes that port into the kubeconfig at create time. On
syncer pod restart the proxy is recreated on a NEW port (observed 12128→12707) → create-time kubeconfig
goes stale → every `_e2e_kc` call gets `EOF`. NEXT FIX: pin `--local-port` in `_vcluster_export_kubeconfig`.
Specced: `docs/bugs/2026-08-16-e2e-vcluster-kubeconfig-proxy-port-drift.md` (`6b85bb56`). vCluster + probe
files cleaned up. Retry the smoke after the port-pin lands. Prior context ↓

**★ E2E TRIGGER SURFACE (2026-08-16, Claude).** Added `make e2e` target (Makefile) → dispatches
`./scripts/k3d-manager e2e_verify_vcluster $(DIGEST)` (verified `make -n e2e` + `DIGEST=`). Specced the
Slack async trigger `docs/plans/v1.25.0-e2e-slack-command.md` (5th v1.25.0 plan doc = AT cap, not over):
`/api/v1/e2e-verify` operator-gated, async worker on `_run_upgrade` shape, busy-lock via the
`_CVE_COOLDOWN_DIR` pattern (serialize-live-sandbox — ONE run), digest `^sha256:[0-9a-f]{64}$` validate,
result rendered from the harness JSON summary (same keys as Grafana Path-A). ALL three triggers
(`make e2e` local / Slack async / future GHA) funnel through the one `e2e_verify_vcluster` entrypoint.
**Slack spec is GATED on a green smoke** — do NOT wire it while the proxy-port-drift bug keeps the smoke red.

**★ E2E SMOKE — CODE FIXES DONE + VERIFIED; LIVE GREEN BLOCKED BY vCLUSTER CONTROL-PLANE INSTABILITY (2026-08-16, Claude).**
Landed & pushed on `k3d-manager-v1.25.0`: `1f1f98ce` (pin `--local-port`), `95e09b20` (`_vcluster_refresh_connection`
recreates the wedged background-proxy; gate takes the vcluster name), `2c93e702` (decouple probe cadence 5s from
refresh cadence 30s). 33/33 BATS green (18 vcluster + 15 e2e). Three live re-runs all exited 1 at the readiness
gate. Root cause chain, empirically nailed:
1. vcluster 0.36.x background-proxy = a docker container running an internal `kubectl port-forward` on a random
   host port; froze into the create-time kubeconfig, died on syncer restart, never reconnected → EOF. Fixed by
   pin `--local-port` + recreate-proxy-in-gate. (Proven: on a healthy pod, recreate proxy → create-time kubeconfig
   returns `/readyz ok`.)
2. **THE REMAINING BLOCKER — the ephemeral vcluster syncer CRASH-LOOPS from datastore I/O starvation.** Syncer logs:
   `Slow SQL ... 1.8–2.3s` (kine) → `leaderelection lost` → `error running controller-manager: exit status 1` →
   pod restart, repeat (RESTARTS 1→3→12 across runs; pod flaps 0/1↔1/1). NOT clock skew (~14s epoch diff). A
   crash-looping API server defeats ALL connection logic — this is infra, not code.
   Default vcluster datastore = embedded SQLite (kine) on the statefulSet's disk-backed volume; on k3d that's the
   slow OrbStack overlay FS. `scripts/etc/vcluster/values.yaml` only sets CPU/mem (200m/256Mi–500m/512Mi), nothing
   for the datastore. **Proposed fix (needs decision): back the ephemeral vcluster's data dir with a memory-backed
   emptyDir (tmpfs) — throwaway cluster needs no persistence, RAM I/O kills the starvation** — and/or relax leader
   election timeouts. Alt: only run the smoke on a calm host. Teardown STILL doesn't run on failure (EXIT trap) →
   orphan crash-looping vclusters compound the pressure; manual `vcluster delete` each time.
Full detail: `docs/bugs/2026-08-16-e2e-vcluster-kubeconfig-proxy-port-drift.md` (3 UPDATE sections).
NEXT: decide the datastore/tmpfs fix vs calm-host acceptance; also `make e2e` (landed `1161f414`) + Slack spec
(`docs/plans/v1.25.0-e2e-slack-command.md`) both still gated on this green smoke.

**★ v1.25.0 E2E TIER 1 — PART 1 PR OPEN (2026-08-16, Claude).** Codex `3e798e88` (repo
`shopping-cart-e2e-tests`, branch `feat/e2e-image-and-workflow-call`) independently VERIFIED GOOD
(branched from origin/main, exactly 4 files: Dockerfile `playwright:v1.57.0-jammy` + .dockerignore +
publish-image.yml + e2e-tests.yml `workflow_call`; all actions pinned; minimal perms; all-tests gate
untouched). **PR #6** opened (`gh pr view 6 --repo wilddog64/shopping-cart-e2e-tests`), base `main`,
NOT merged. CI = GitGuardian pass only (repo has NO pull_request build/lint CI → nothing validates the
image builds on the PR). **Copilot review ADDRESSED (2026-08-16, Claude):** 2 inline comments fixed in
`ac304032` (pushed to PR branch) + both threads resolved — (a) Dockerfile `ENV PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1`
before `npm ci` (base image already ships browsers); (b) `.dockerignore` now excludes `.env`/`.env.*`/`.envrc`
(keeps `.env.example`) so a local `.env` can't be baked into the image via `COPY . .`. **Branch protection on
`main` currently DISABLED** (backup at `scratchpad/e2e-main-protection-backup.json`: 1 review + enforce_admins
true) so user can self-review+merge; MUST restore after merge. **Remaining pre-merge gaps:** (1) build smoke — the GHCR image
`ghcr.io/wilddog64/shopping-cart-e2e-tests` does NOT exist yet (publish-image.yml fires only on push to
main / manual dispatch), so `e2e_verify_vcluster` cannot run end-to-end until it's published. Part 2
(k3d-manager `e2e.sh` + `scripts/etc/e2e` substrate, `567e923e`) already merged. No `make e2e` target
exists — run via `./scripts/k3d-manager e2e_verify_vcluster [digest]` (ergonomic gap; candidate for a
`make e2e` wrapper).

**★ v1.25.0 HARNESS CODIFIED + CONFIG-GAP BUGFIX FILED (2026-08-15, Claude).** Two deliverables, both
ready for Codex:
1. **Harness codification** — folded the copy-paste-exact `e2e_verify_sandbox` sequence + BATS contract into
   `docs/plans/v1.25.0-e2e-harness-tier2-sandbox.md` (new "## Implementation — codified from the live run"
   section; kept plan-doc count at 4, under the ≤5 cap by folding rather than a 5th doc). Encodes GAP 2/3
   CLOSED (identity = **public Cloudflare issuer** + internet egress, NO DNAT/CoreDNS/ssh-R; e2e Job reaches
   services by ClusterIP DNS) and the **three substrate overrides the harness applies** (a order URLs→svc DNS,
   d payment gateway mock→stripe, e JWK→public issuer) — these stay in the harness, NOT the app repos, because
   the defaults are production-correct (hub Istio + hub-internal Keycloak DNS). Records the app-level
   boundaries as explicit non-goals (payment role-authority fix `aeb89e8`; e2e X-User-ID keying).
2. **Config-gap bugfix (real, substrate-independent)** — `docs/bugs/2026-08-15-namespace-labels-missing-for-payment-netpol.md`.
   Root-caused the (b)/(c) label gaps: `shopping-cart-data` is created BARE by the `data-git` appset's ArgoCD
   `CreateNamespace=true` (no `component=data`); `shopping-cart-apps` from the k3d-manager namespace app is
   missing `component=application`+`name=shopping-cart`. Both payment NetworkPolicy selectors then never match
   → all traffic denied under Cilium (masked on k3d/OrbStack default CNI). Two k3d-manager-only fixes (single
   repo, no cross-repo): add labels to `services/shopping-cart-namespace/namespace.yaml`, and add
   `managedNamespaceMetadata.labels` to `scripts/etc/argocd/applicationsets/data-git.yaml`. Canonical
   `shopping-cart-infra/namespaces/namespaces.yaml` HAS the labels but is orphaned (appset sources `data-layer`,
   not `namespaces`). Commit msg: `fix(netpol): stamp component/name labels so payment NetworkPolicies match`.
**FIX PUSHED 2026-08-16:** commit `8ea02b51` is pushed to `origin/k3d-manager-v1.25.0`; both exact label edits passed the Kustomize and YAML parse gates. No live deployment was performed. **VERIFIED 2026-08-16 (Claude):** `8ea02b51` on origin, exact commit msg, only the 2 spec'd files (7 ins/0 del), diff matches spec verbatim; memory-bank in separate commit `a068995f`. Codex netpol task DONE.

**★ HOSTINGER EDGE RECOVERED + PERMANENT-FIX SPEC FILED (2026-08-16, Claude).** `make status CLUSTER_PROVIDER=k3s-hostinger` went all-red (all-530 + argocd connection-refused) after a provider-switch stopped the laptop edge — cluster was healthy, only cloudflared tunnel + port-forward launchd agents were down. Recovered edge-only via `_hostinger_refresh_access_layer` (throwaway scratchpad script, user-run) → all 13 checks green, HEALTHY. Root gap: that function is private with no first-class entrypoint, and the only wired path (`make refresh`) also reapplies GitOps appsets + repoints the `$values` ref. Specced the durable fix: **`docs/bugs/2026-08-16-hostinger-edge-recovery-no-narrow-entrypoint.md`** — add `refresh_access_layer` verb (core.sh) + `_provider_k3s_hostinger_refresh_access_layer` wrapper + `make refresh-edge` target (edge-only, no reapply). Exact old→new blocks in the spec; commit msg `feat(hostinger): add narrow refresh-edge entrypoint (edge-only, no GitOps reapply).` **DONE 2026-08-16:** code commit `f28b6cda` pushed to `origin/k3d-manager-v1.25.0`; syntax, shellcheck, and dispatch gates passed. Live Hostinger verification remains Claude-owned.

**★ JENKINS REMOVED FROM README (2026-08-16, Claude).** User escalated the 2026-08-10 "mark deprecated in docs"
decision → remove Jenkins from current-facing README entirely. Chose scope "Diagram + all README prose" (offered
diagrams-only / +prose / +arch-docs). Edited `README.md` only: deleted the ⚠️ deprecation banner, the `JENKINS[...]`
node in the Architecture mermaid diagram, the `deploy_jenkins` Quick-Start line, the Plugins-table row, the `guides/`
tree blurb, and the two Guides + two How-To Jenkins doc links (1 ins / 12 del). **Kept:** the two historical
release-log rows (v1.22.0, v0.9.10) — factual release record, not current architecture. **Left untouched (per
decision + user scope):** `scripts/plugins/jenkins.sh` + `scripts/etc/jenkins/` code, `docs/architecture/*`
illustrative-example docs (already disclaimed), all `docs/{issues,retro,plans/archive,tests}` history and Jenkins
*feature* docs. Memory `[[project_jenkins_deprecation]]` updated. Committed `d5128a7e` (pushed).

**★ HOSTINGER EDGE-DOWN SELF-DIAGNOSIS IMPLEMENTED 2026-08-16.** Follow-up to the verified `f28b6cda`
`refresh-edge` entrypoint. Commit `f4b6985e` pushed to `origin/k3d-manager-v1.25.0`: summary mode now counts
Cloudflare `HTTP 530` failures and, for `k3s-hostinger` with `_edge530>=2`, prints the `make refresh-edge`
hint. Added three curl-stub BATS cases; all 8 tests pass. The JSON branch, exit codes, warning/healthy arms,
and plists remain untouched. Live edge verification remains Claude-owned.

**★ v1.25.0 E2E HARNESS TIER 1 — PART 2 IMPLEMENTED (2026-08-16, Claude).** Implemented the k3d-manager side of
`docs/plans/v1.25.0-e2e-harness-tier1-impl.md` directly (user approved "do your recommendation" over the doc's
original spec→Codex handoff). **New in-repo assets (uncommitted, on `k3d-manager-v1.25.0`):**
`scripts/plugins/e2e.sh` (`e2e_verify_vcluster [candidate_ref]` + `_e2e_*`), the self-contained substrate bundle
`scripts/etc/e2e/` (postgres+redis+product-catalog+basket+order+seed, kustomize, zero Vault/ESO/ArgoCD,
`OAUTH2_ENABLED=false`, all images pinned — service defaults = each repo's own last-known-good `sha-` tag),
`scripts/tests/plugins/e2e.bats` (9 tests, all green), guide `docs/guides/vcluster-e2e-harness.md`, plus
README (Guides + How-To) / `docs/api/functions.md` / CHANGELOG `[Unreleased]`. **Design calls made (spec open
items):** (1) product-catalog image really listens on **:8080** not :8000 (compose `8000:8000` is stale) → Service
decouples port 8000→targetPort 8080; basket 8083, order 8080 direct. (2) Vendored MINIMAL Deployments (not the
repos' `k8s/base`, which drag in ESO `externalsecret`/`secret`). (3) Job manifest written to a temp file, not
piped, to avoid SIGPIPE+pipefail. **Caught a latent bug in the spec's own skeleton:** `trap '_e2e_teardown
"$name"' EXIT` faults under `set -u` because the local `$name` is out of scope when the trap fires at shell
exit → teardown never ran + non-zero exit; fixed by hoisting to a global `_E2E_ACTIVE_NAME` with `${…:-}`
expansion. Gates: `bash -n` + `shellcheck -S warning` clean, `kubectl kustomize scripts/etc/e2e` builds (selectors
intact, all pinned), 9/9 BATS. Dispatcher auto-discovers the verb (plugin grep) — no dispatcher edit. **NOT run
live** (needs Part 1's e2e image + a vCluster host). **Part 1 (shopping-cart-e2e-tests repo: Dockerfile +
publish-image.yml + `workflow_call` on e2e-tests.yml) is still a Codex handoff** — barred from editing
shopping-cart-family repos directly; the impl spec already contains Part 1 verbatim.

**PART 1 HANDED OFF TO CODEX (2026-08-16, Claude).** No live Codex agent to dispatch to (ListAgents = one
offline peer), so the deliverable is a self-contained, ground-truth-verified Codex prompt at
`scratchpad/codex-handoff-part1.md` (session scratchpad). Verified before writing: e2e repo currently on
`feat/stripe-checkout-e2e` → Codex branches `feat/e2e-image-and-workflow-call` from **origin/main**; locked
Playwright is **1.57.0** (spec's `v1.40.0` was only an example) → base `mcr.microsoft.com/playwright:v1.57.0-jammy`;
`e2e-tests.yml` `on:` block lines 3–24 and three env blocks (api 49–52, flow 89–92, all 129–132) match the impl
spec's find/replace snippets exactly. Guardrails baked in: keep `push`/`schedule` disabled, don't touch
k3d-manager, no PR, no push-to-main, push branch + report `origin` SHA, no `--no-verify`, exact commit msg
`feat(ci): publishable e2e image + workflow_call substrate inputs`. **Still pending user action:** paste the
prompt into Codex (no live agent); on Codex "done" → verify per protocol (SHA on origin, `git show --stat`) before
trust. k3d-manager Part 2 remains uncommitted awaiting user go.

**CODEX `f28b6cda` VERIFIED GOOD — but it's NOT the e2e Part 1 (2026-08-16, Claude).** SHA `f28b6cda` =
`feat(hostinger): add narrow refresh-edge entrypoint` on `origin/k3d-manager-v1.25.0` (the hostinger
edge-recovery bugfix, spec `docs/bugs/2026-08-16-hostinger-edge-recovery-no-narrow-entrypoint.md`), NOT the
shopping-cart-e2e Part 1. (Self-correction: I first searched the e2e repo and wrongly called it a fabricated
SHA — [[feedback_codex_verification_protocol]] lesson = confirm WHICH repo before declaring absent.) Verification
PASSED: diff matches spec verbatim (core.sh `refresh_access_layer` verb + `_provider_k3s_hostinger_refresh_access_layer`
wrapper + Makefile `refresh-edge`), `bash -n` clean, helpers exist, `make -n refresh-edge` dispatches the narrow
verb, k3d refuses+exits 1, ZERO new shellcheck findings, full-refresh fn untouched. Only unrun = live edge-down +
`argocd_check_values_branch` before/after (needs a down edge). **The e2e Part 1 (Dockerfile/publish-image.yml/
`workflow_call`) is STILL genuinely pending** — prompt at `scratchpad/codex-handoff-part1.md`, never given to
Codex yet; the "fabricated" scare was my repo mix-up, not a real Codex miss.

**★ 2B REPLAY CHECKPOINT (2026-08-15, fresh ACG sandbox, LIVE).** Account `975049916979`, server `34.220.155.130` (internal `10.0.1.78`), 3-node k3s v1.32.0 all Ready. Progress this run: (1) `deploy_cluster --confirm` with `CLUSTER_PROVIDER=k3s-aws K3S_AWS_SSM_ENABLED=false` → 3 nodes + Cilium + vault-bridge socat + autossh tunnel + ssh -R reverse tunnel (provisioner did all of this now, incl. the reverse tunnel that was manual last run). (2) In-sandbox ArgoCD 10.1.4 Helm-installed (ns `argocd`, `--kube-context ubuntu-k3s`, `server.insecure`+ClusterIP; dex crashloops, irrelevant). (3) Local RBAC `argocd-manager` SA created in-sandbox (NOT `register_app_cluster`) → minted bearer token → `ubuntu-k3s` cluster secret (name load-bearing) + platform/shopping-cart AppProjects applied. (4) 3 appsets (eso/data-git/services-git, `K3D_MANAGER_BRANCH=k3d-manager-v1.25.0`) → 8 apps generated, all keyed `ubuntu-k3s`. (5) **Secrets path fully wired + PROVEN:** created missing `vault-bridge` Endpoints → `10.0.1.78:8201` (Service had no selector, no Endpoints); chain pod→bridge:8201→socat→ssh-R→laptop:18200→hub vault reachable (health OK). ⭐ **TokenReview seam re-proven:** `configure_vault_app_auth_for_context ubuntu-k3s` created mount `kubernetes-ubuntu-k3s`+policy `app-cluster-reader`(already includes `secret/data/github/pat` read)+role `eso-app-cluster`, THEN overwrote mount config with `disable_local_ca_jwt=true kubernetes_host=https://34.220.155.130:6443 kubernetes_ca_cert=@ token_reviewer_jwt=@` using a sandbox `vault-reviewer` SA (kube-system, system:auth-delegator, long-lived token). Created `vault-backend` ClusterSecretStore (mountPath `kubernetes-ubuntu-k3s`, role `eso-app-cluster`, sa external-secrets/secrets) → **Ready=True Valid**, all **15 ExternalSecrets SecretSynced** (incl. ghcr-pull-secret). GOTCHAS: local `base64` is GNU (`-d` not macOS `-d`/`-D`); zsh no-word-split (don't stuff `kubectl … ` in a var). REMAINING: payment fix test (services/shopping-cart-payment kustomization refs `shopping-cart-payment//k8s/base?ref=main` — fix `7cae043` is on unmerged branch `fix/payment-ghcr-eso-pull-secret`, so straight deploy tests PRE-fix; need branch override to test the fix) → then GAP3 hub-Keycloak identity + ingress → Stripe E2E. Default kube-context left on `k3d-k3d-cluster` (hub) after the vault work.

**★★ PAYMENT GHCR FIX (`7cae043`, branch `fix/payment-ghcr-eso-pull-secret`) VERIFIED LIVE 2026-08-15.** Deployed via a disposable in-cluster override (patched services-git appset to `exclude` services/shopping-cart-payment, deleted the appset-generated payment app, applied a standalone ArgoCD Application sourcing `shopping-cart-payment//k8s/base?ref=fix/payment-ghcr-eso-pull-secret`, prune+selfHeal on). All 5 criteria PASS: (1) `ghcr-pull-secret` ExternalSecret `Ready=True SecretSynced` (Vault `secret/data/github/pat` prop token); (2) target secret type `kubernetes.io/dockerconfigjson` renders correctly (the b64enc `auth` template line is intact live); (3) `payment-service` SA `imagePullSecrets: [ghcr-pull-secret]` — fix patches the RIGHT SA, not `default`; (4) payment pod **Running** (image PULLED, no ImagePullBackOff); (5) **survives a `prune:true` sync** — ExternalSecret + secret both persist (git/ESO-owned, not extraneous — the exact original bug is fixed). Payment app then boots into a postgres-payment connection retry (DB-timing, NOT the ghcr fix). ⇒ **The payment PR to shopping-cart-payment main is now cleared to proceed** (was the last blocker). NOTE the override is sandbox-only/disposable; the real path is: merge payment PR → `services/shopping-cart-payment/kustomization.yaml` (ref=main) picks it up unchanged (no k3d-manager change needed). REMAINING this run: GAP3 hub-Keycloak identity reach (DNAT/CoreDNS/ssh-R + Cloudflare issuer) + ingress → Stripe live E2E (moves G past 2/4).

**★★★ FULL STACK 8/8 HEALTHY 2026-08-15 (beats prior 7/8).** After the payment fix, one more gap surfaced+fixed: payment→postgres was blocked by Cilium NetworkPolicy — payment ns has `default-deny-all` + `allow-to-postgresql` egress that permits 5432 only to a namespace labeled `app.kubernetes.io/component=data`, but the namespace app creates `shopping-cart-data` with ONLY `kubernetes.io/metadata.name` (missing `component=data`). Fix: `kubectl label ns shopping-cart-data app.kubernetes.io/component=data` → payment Flyway migration ran, pod 1/1. **THIS IS A REAL CONFIG GAP worth a bugfix spec:** the namespace app (services/shopping-cart-namespace or shopping-cart-infra namespaces manifest) should stamp `app.kubernetes.io/component=data` on the data ns so payment netpol works without manual labeling (Cilium enforces netpol on k3s-aws; k3d/OrbStack default CNI may not, which is why it didn't bite before). Also product-catalog + data-git StatefulSets need explicit ArgoCD sync (data-git appset lacks `automated`), and `shopping-cart-payment` ns needs manual precreate (namespace app makes apps+data only). Final state: 7 DBs + basket/order/frontend/product-catalog/payment all 1/1, all 8 ArgoCD apps Synced/Healthy. Frontend needed product-catalog Ready first (nginx resolves upstream at boot) → restart after product-catalog up.

**★★★★ STRIPE E2E — PLATFORM PROVEN END-TO-END; blocked only at the Stripe API (2026-08-15).** GAP3 identity is SOLVED without DNAT/CoreDNS/ssh-R: hub Keycloak is live + the PUBLIC Cloudflare issuer `keycloak.3ai-talk.org` returns 200, so sandbox services validate against the public issuer over internet egress. Got a live JWT via password grant (client `order-service` + its secret from Vault `secret/keycloak/clients` key `order_service_client_secret`; user `developer`, pw from `secret/keycloak/users/developer`). The e2e suite is `shopping-cart-e2e-tests` (`--project=flows --no-deps tests/flows/stripe-checkout-orchestrator.spec.ts`; flows depends on api, so `--no-deps` to isolate). Env: OAUTH2_ENABLED/STRIPE_E2E=true, KEYCLOAK_URL=public, service URLs via 4 port-forwards (basket:8083 order:8081 product-catalog:8082 payment:8084 — note order svc port is 8081 not 8080, pc is 8082 not 8000). A MANUAL curl reproduction drove the full path: add-to-cart (200, correct fields `{productId,name,quantity,unitPrice}`), order checkout → **order created, amount $39.98 (cart consistency WORKS), payment attempted at the LIVE Stripe API.** **THE CASCADE OF CONFIG GAPS fixed to get there (all ambient-mesh / in-cluster-URL assumptions that break on a self-contained non-Istio Cilium sandbox — these are the harness-codification TODOs for Codex):** (a) order `BASKET_URL`/`PAYMENT_URL` default to `http://localhost:8083/8084` (ambient-mesh localhost assumption) → set to in-cluster svc DNS; (b) payment `default-deny-all` + `allow-to-postgresql`/`allow-to-rabbitmq` egress require ns `shopping-cart-data` labeled `app.kubernetes.io/component=data` (namespace app doesn't stamp it); (c) payment `allow-from-order-service` ingress requires ns `shopping-cart-apps` labeled `app.kubernetes.io/component=application` + `app.kubernetes.io/name=shopping-cart`; (d) payment `PAYMENT_GATEWAY_DEFAULT=mock` → set `stripe` (+`MOCK_GATEWAY_ENABLED=false`) or mock declines Stripe test cards; (e) ⭐ payment `OAUTH2_JWK_SET_URI` defaults to in-cluster `http://keycloak.identity.svc.cluster.local/.../certs` (doesn't exist in sandbox) → set to PUBLIC `https://keycloak.3ai-talk.org/realms/shopping-cart/protocol/openid-connect/certs` (this was the 401→403 fix). **FINAL BOUNDARY: payment→Stripe returns HTTP 403** on the PaymentIntent/pm_card_visa flow. The sk_test key itself is VALID (direct `curl api.stripe.com/v1/balance` = 200; Vault==Keychain `k3dm-stripe-sk-test`, sha b0c4d0…, and the pod's `STRIPE_API_KEY` matches). So the 403 is an APPLICATION/Stripe-integration detail (PaymentIntent confirm/PM-attach semantics or Stripe test-account config), NOT a platform gap — hand to the shopping-cart payment-service owner. **e2e-suite note:** the Playwright orchestrator sees an empty cart (X-User-ID header keying: test sends X-User-ID=TEST_USER_ID while order resolves by JWT sub → basket keys mismatch; manual JWT-only path is consistent). NET: the self-contained 2B substrate for the Stripe live E2E is fully proven from provisioning through a real authenticated order hitting the live Stripe API; only the in-app Stripe charge semantics + the e2e X-User-ID keying remain, both app-level.

**★ 403 ROOT CAUSE FIX PUSHED (2026-08-15):** The deployed Java payment service's stock Spring converter ignored Keycloak `realm_access.roles` and `resource_access.<client>.roles`, producing no `ROLE_*` authorities and causing the authenticated payment request to return 403. shopping-cart-payment commit `aeb89e8` is pushed on `origin/fix/keycloak-role-authority-mapping` (spec branch off `origin/main`), adding `KeycloakRealmRoleConverter`, wiring it through `JwtAuthenticationConverter`, adding 3 converter tests, and updating CHANGELOG. Full `mvn test` passed with Java 21: 133 tests, 0 failures/errors. Follow-up after merge: verify the `shopping-cart` realm grants the test principal a `PAYMENT_*` role; if absent, a separate Keycloak-realm change is needed.


**★ ACG k3s-aws UP/DOWN SMOKE (2026-08-15, fresh sandbox acct `843089371063`, LIVE).** `aeb89e8` mvn test INDEPENDENTLY RE-VERIFIED in a Temurin-21 Maven container (host has no JDK — `/usr/bin/java` is Apple's stub that hangs): 99 unit + the 3 `KeycloakRealmRoleConverter` tests all pass; the only 3 "errors" are Testcontainers integration tests failing on `Could not find a valid Docker environment` (no Docker-in-Docker) — env, not code. FULL `make up` (`CLUSTER_PROVIDER=k3s-aws`, GHCR_PAT from Keychain `ghcr-pat`) **FAILED at SSM registration:** creds valid (skipped Playwright) → sandbox TTL read `-971m` (stale CDP-tab timestamp; extend button not found, NON-fatal, `sts` confirms creds live) → CFN stack `k3d-manager-cluster` created OK (3 EC2 in parallel: server 34.222.27.4 + 2 agents; SSM IAM profile CORRECT — role `k3d-manager-cluster-ssm-role` has `AmazonSSMManagedInstanceCore`) → but `ssm describe-instance-information` stayed **EMPTY (0 managed instances even 20 min post-launch)** → SSM-tunnel wait timed out at 300s → `make up` Error 1. `make up` failure-cleanup only kills LOCAL procs, so the 3-instance stack was **ORPHANED/billable** until teardown. Root cause is downstream of IAM: AMI `ami-0eb3161272dc9c6eb` has no running `amazon-ssm-agent`, or the subnet lacks egress to the SSM endpoints. **Maps to task #28** (k3s-aws provisioning bug) — note it fails at the SSM-tunnel wait, BEFORE `deploy_app_cluster` installs k3s. `make down KEEP_LOCAL=1` (→ `--keep-hub`) then ran **CLEAN + independently verified:** CFN stack gone (`ValidationError … does not exist`), all 3 EC2 `terminated`, `ubuntu-k3s` context removed, deregistered from hub ArgoCD, and **local hub `k3d-k3d-cluster` PRESERVED (4 nodes Ready, 26d uptime, untouched)**. Two benign WARNs: LaunchDaemon boot-outs skipped (`no sudo in headless context`). NET: teardown incl. keep-hub is reliable; the UP path is blocked on SSM-agent registration and needs an AMI/egress fix before a full self-contained provision works via `make up` (the 2B replay run above got a cluster via `deploy_cluster` with `K3S_AWS_SSM_ENABLED=false` + reverse-tunnel, which sidesteps SSM). **Specs filed for Codex (task #28):** SSM spec `docs/bugs/2026-08-14-k3s-aws-ssm-agent-cannot-register.md` got a 2026-08-15 corroboration note (2nd sandbox acct, same empty SSM record → not one-off), and the orphaned-stack cleanup gap is a NEW spec `docs/bugs/2026-08-15-cluster-up-failure-orphans-cloudformation-stack.md` (`_acg_up_cleanup` kills only local procs; upstream cause of the 2026-05-16 CFN rollback-state bug).

**DRY_RUN Phase 2 COMPLETE (2026-08-14):** commit `c8b6a1aa` (`fix(lifecycle): honor DRY_RUN per-op across make up/down for all providers`) is pushed to `origin/k3d-manager-v1.25.0`. Per-operation guards now cover `bin/cluster-up`, `bin/cluster-down`, and all five provider deploy/destroy paths; shellcheck is clean, the relevant lifecycle/provider BATS suite passes 47/47, and dry `make up/down` emits intent without follow-on deployment. Phase 3 remains separate (k3s-aws `make down` deregistration wiring).

**DRY_RUN Phase 2b COMPLETE (2026-08-14):** commit `d2263cc2` is pushed to `origin/k3d-manager-v1.25.0`. The canonical `DRY_RUN` flag and bridged `K3DM_DEPLOY_DRY_RUN` alias now drive `_run_command`, both lifecycle bins, Vault/Jenkins, and dispatcher dry-run gates; cluster-up stops successfully at the Step 4 seam with a plan summary, and cluster-down emits per-operation teardown intent. Stubbed lifecycle BATS (21/21), provider BATS (38/38), and shellcheck passed. Phase 3/4 remain queued.

**DRY_RUN Phase 3 COMPLETE (2026-08-14):** commit `469a3427` is pushed to `origin/k3d-manager-v1.25.0`. `make down` now deregisters the k3s-aws sandbox from hub ArgoCD before teardown, and the local-provider path sources the dry-run bridge before common launchd cleanup. Stubbed cluster-down BATS (12/12) and shellcheck passed; Phase 4 remains queued.

**DRY_RUN Phase 4 COMPLETE + Claude-verified (2026-08-14):** commit `7a34856c` (feature) + `aca42562` (memory-bank, separate) pushed to `origin/k3d-manager-v1.25.0`. Slack `cluster-up`/`cluster-down` now support DRY_RUN preview via env-injection into `_posix_spawn_job`. Independently verified: scope = allow-list only (`bin/cluster-down` NOT in commit), py_compile OK, webhook.bats 54/54 with a genuinely BEHAVIORAL test (SourceFileLoader + spies on `_posix_spawn_job`/`_record_acg_state`/`_run_post_provision_check`/`_push_metrics`), cluster_down.bats 12/12, and Part B mutation check independently reproduced pass→fail→pass. **DRY_RUN Phases 1–4 all shipped; the thread is closed.**

**Standalone `make down` PLUGINS_DIR bug FIXED (2026-08-14):** `d02c8e92` pushed to
`origin/k3d-manager-v1.25.0`. `bin/cluster-down` now exports `PLUGINS_DIR` before the lazy
ArgoCD plugin load; the exact `set -u` failure is recorded in
`docs/bugs/2026-08-14-cluster-down-argocd-plugin-plugindir.md`. Cluster-down BATS 13/13,
shellcheck, and agent lint/audit passed.

**`make up` credential-check recursion FIXED (2026-08-14):** `d793a1d5` pushed to
`origin/k3d-manager-v1.25.0`. Removed the redundant post-plugin dry-run wrapper re-capture
that made `__k3dm_base_run_command` call the wrapper recursively at Step 1. The bug report is
`docs/bugs/2026-08-14-cluster-up-dryrun-wrapper-recursion.md`; cluster-up BATS 7/7, shellcheck,
bounded wrapper smoke, and agent lint/audit passed.

**Tier 2 sandbox harness — ARCHITECTURE LOCKED, NOT handoff-ready (2026-08-14, user chose "design fully first").** D1 RESOLVED → **disposable in-sandbox ArgoCD** (the app-cluster stack — istio-ambient/eso/data-git/services-git — is ApplicationSet-driven keyed on `k3d-manager/role: app-cluster`; install ArgoCD inside the sandbox, label its `in-cluster` secret, apply the same appsets against `kubernetes.default.svc`; kubectl-kustomize alt rejected). Grounding recorded in `docs/plans/v1.25.0-e2e-harness-tier2-sandbox.md` ("Deploy architecture (resolved)"). **Blocked on a Claude live dry-run** to pin THREE undesigned deploy paths before Codex can get copy-paste code: GAP 1 = in-sandbox ArgoCD install is unsupported (`deploy_argocd_bootstrap` short-circuits on `CLUSTER_ROLE=app`, argocd.sh:969); GAP 2 = Keycloak/identity deploy is not a reusable fn (`services-git` excludes `services/shopping-cart-identity`); GAP 3 = no app-cluster ingress-exposure helper for the Playwright Job. **Next action = Claude live dry-run on a sandbox → pins GAP 1–3 AND moves G past 2/4 (the live Stripe run is Claude's per rules), then write exact `e2e_verify_sandbox`+BATS → Codex handoff.** Tier 2 also creates the shared `scripts/plugins/e2e.sh` scaffolding (`E2E_REPORT_DIR`/`_e2e_write_summary`) carved so Tier 1 layers `e2e_verify_vcluster` in later.

**Tier 2 live dry-run STARTED 2026-08-14 (user: "do 1 first then 2").** Fresh ACG AWS sandbox up via `acg_restart` (creds valid, `arn:…:user/cloud_user`, TTL ~232m). Two blockers + one major design finding surfaced, all BEFORE reaching the Stripe E2E:
- **k3s-aws provisioning fix COMPLETE 2026-08-14:** `7a24d768` pushed to `origin/k3d-manager-v1.25.0`. Replaced the `env` prefix that attempted to execute the `deploy_app_cluster` shell function with the export-then-call form required by `_dry_guard`'s direct `"$@"` invocation. Shellcheck and k3s-aws provider BATS (8/8) pass; the unrelated Tier 2 plan edit remained untouched.
> - **BUG (filed) — k3s-aws provisioning cannot install k3s.** `deploy_cluster --provider k3s-aws` stands up the 3 EC2 nodes then dies: `env: 'deploy_app_cluster': No such file or directory`. Root cause `scripts/lib/providers/k3s-aws.sh:178` — `env VAR=val deploy_app_cluster` can't invoke a shell function (`deploy_app_cluster` is one, shopping_cart.sh:1109); drop `env`. Hits both SSM+SSH modes on every fresh provision. Spec: `docs/bugs/v1.25.0-bugfix-k3s-aws-env-cannot-call-deploy-app-cluster.md`. Worked around live (SSH to nodes confirmed reachable).
> - **BUG (filed) — observability DRY_RUN `base64: invalid input`.** The `Reading Alertmanager credentials from Vault` block reads vault-root via `_kubectl … | base64 --decode`; under DRY_RUN `_run_command` prints a `[dry-run] …` banner to stdout that gets piped into `base64 --decode` → `invalid input` + false "Alertmanager Vault secret not found". 5 sites in `observability.sh` (38/200/400/555/579). Fix = plain `kubectl` for the read (precedent cluster-up:409). Spec: `docs/bugs/v1.25.0-bugfix-observability-dryrun-base64-invalid-input.md`.
> - **DESIGN FINDING — Tier 2 splits into 2A vs 2B (reshapes the spec).** Grounding full `bin/cluster-up`: identity (Keycloak+LDAP) is HUB-hosted (`destination: kubernetes.default.svc` = hub), reached from the app cluster via ssh-reverse-tunnel + iptables DNAT + CoreDNS, with the OIDC issuer being the **Cloudflare public** `keycloak.3ai-talk.org`; per-service issuer is baked into each `shopping-cart-*/k8s/base` repo. So D1 "in-sandbox ArgoCD + same 4 appsets" covers apps/data/mesh/secrets but **NOT identity/OIDC**. Two shapes: **2A** fully self-contained (re-home identity + local issuer + per-service cross-repo overrides — weeks-scale bespoke) vs **2B** self-contained apps + shared hub identity via existing tunnel/Cloudflare issuer (still never `register_app_cluster` → no orphan; ~80/20, unblocks G now). Full detail in scratchpad `tier2-dryrun-findings.md`.
> - **DECISION 2026-08-14 (user): "Both, staged" — build 2B NOW to unblock G this release; keep 2A as a later "fully isolated substrate" goal.** Fold into `docs/plans/v1.25.0-e2e-harness-tier2-sandbox.md` (still uncommitted-modified).
> - **LIVE CLUSTER UP + Codex batch VERIFIED 2026-08-14.** Codex delivered 4 items on the k3s-aws path, all Claude-verified (shellcheck clean, cluster_up.bats 7/7, cluster_down.bats 13/13, pushed): assigned `7a24d768` (export-then-call, correct) + on-path `d02c8e92` (cluster-down PLUGINS_DIR) + `d793a1d5` (cluster-up 99%-CPU dry-run recursion) + FILED `docs/bugs/2026-08-14-k3s-aws-ssm-agent-cannot-register.md`. **SSM path is BROKEN on ACG** (agent never registers, `InstanceInformationList` empty) → **Tier-2-on-ACG must use SSH/k3sup, not SSM.** Live app-role k3s cluster is UP via SSH/k3sup (invoked `deploy_app_cluster --confirm` directly through a lib-sourcing wrapper, `K3S_AWS_SSM_ENABLED=false`): node Ready v1.32.0+k3s1, `ubuntu-k3s` context merged, reachable `https://44.246.200.209:6443` (agents not joined yet).
> - **GAP1 PINNED.** App-role clusters skip BOTH `deploy_argocd` (argocd.sh:408) and `deploy_argocd_bootstrap` (968); infra-role bypass cascades vault+ldap+hub-bootstrap (too heavy). 2B minimal = call `_argocd_helm_deploy_release` (argocd.sh:455) directly against ubuntu-k3s + apply the 4 appsets manually. The `k3d-manager/role=app-cluster` label (argocd.sh:1250) is hub-side spoke bookkeeping — OUT OF SCOPE for self-contained 2B. Open sub-Q: ESO/secrets appset Vault target (hub-via-tunnel vs sandbox).
> - **2B PROVEN END-TO-END 2026-08-14/15 (sandbox then TTL-expired).** In-sandbox ArgoCD + the 4 appsets delivered the FULL shopping-cart stack on the app-role sandbox: all 7 databases (postgres orders/payment/products, redis cart/orders, rabbitmq, minio) Running, and 7/8 apps Healthy (basket/frontend/order/product-catalog/namespace/eso/data-layer) — only payment lagged on a namespace pull-secret propagation detail (manual copy got pruned by services-git prune:true; needs a git/ESO-owned ghcr ExternalSecret in shopping-cart-payment). The Stripe E2E itself was NOT reached (still needs identity: hub-Keycloak reach from sandbox via DNAT/CoreDNS/ssh-R + Cloudflare issuer, then the Playwright run) before the ACG sandbox hit its 4h(+4h) TTL and tore down. **Full recipe + the ⭐ Vault-auth-portability fix are captured in [[project_app_cluster_vault_auth_portability]] and the v1.25.0 Tier 2 dry-run findings.** KEY WIRING: local app-cluster secret MUST be named `ubuntu-k3s` (AppProjects whitelist by cluster name); ArgoCD ns = argocd (ARGOCD_NAMESPACE=argocd); secrets path = vault-bridge Service+Endpoints→node socat:8201→node:8200→ssh -R→laptop:18200→hub vault; Vault mount `kubernetes-ubuntu-k3s` MUST use TokenReview (`disable_local_ca_jwt=true` + `token_reviewer_jwt`), NOT local-CA validation, for remote k3s. Codex's SSM bug means Tier-2-on-ACG uses SSH/k3sup.
> - **PLAN DOC FOLDED + COMMITTED 2026-08-15:** `a358d8cb` pushed to `origin/k3d-manager-v1.25.0`. `docs/plans/v1.25.0-e2e-harness-tier2-sandbox.md` now carries the 2A/2B decision (D6), GAP 1 CLOSED (exact in-sandbox ArgoCD Helm install), GAP 2 reframed (2B shares hub identity), GAP 3 open, and a "Proven 2B recipe" section with the durable wiring (SSH-not-SSM, `ubuntu-k3s` secret name, vault-bridge+TokenReview, payment ghcr ExternalSecret follow-up). **NEXT: fresh ACG sandbox → replay 2B → wire hub-Keycloak identity reach (GAP 3) → run Stripe E2E (moves G past 2/4) → write exact `e2e_verify_sandbox`+BATS → Codex handoff.** Identity + Stripe E2E need a fresh sandbox (proving sandbox hit TTL).
> - **PAYMENT GHCR FIX PUSHED 2026-08-15:** The Tier-2 payment image-pull blocker is fixed in shopping-cart-payment commit `7cae043` on `origin/fix/payment-ghcr-eso-pull-secret`. The git/ESO-owned `externalsecret-ghcr.yaml` reads only `secret/data/github/pat`, produces the dockerconfigjson pull secret, and `payment-service` now references it. `kubectl kustomize k8s/base` rendered successfully (only the repository's existing `commonLabels` deprecation warning). Follow-up (k3d-manager, out of scope): trim the now-redundant imperative payment-ns branch to avoid ESO-vs-imperative tug-of-war.
> - **GAP1 EMPIRICALLY CLOSED 2026-08-14 — in-sandbox ArgoCD RUNNING.** On rebuilt cluster #2 (54.190.133.35, node Ready) installed argo-cd 10.1.4 scoped (`helm upgrade --install argocd argo/argo-cd -n argocd --create-namespace --set server.insecure=true --set server.service.type=ClusterIP`, KUBECONFIG hard-pinned to `~/.kube/k3s-ubuntu.yaml`), bypassing the app-role short-circuit, zero hub involvement, no `register_app_cluster`. argocd-server rolled out; all pods 1/1 incl. applicationset-controller. This IS the ldap-off `_argocd_helm_deploy_release` path line-for-line. NEXT = apply the 4 appsets → pin ESO→Vault target → Stripe live E2E.
> - **COLLISION 2026-08-14:** Codex ran live `make up/down` on the SAME sandbox mid-build, terminated cluster #1 (44.246.200.209) + re-provisioned #2 via the broken SSM path. Recovered via SSH/k3sup on the new IP. Lesson saved: [[feedback_serialize_live_sandbox_access]] — ONE agent per live sandbox.

**Scope split executed 2026-08-13 (user decision).** The branch formerly named `k3d-manager-v1.25.0`
held only status/observability work (zero G implementation), so it was **renamed to
`k3d-manager-v1.24.1`** and was cut as a point release; `v1.25.0` is reserved for **workstream G**.

### v1.24.1 (point release) — RELEASED
Content (implemented + live-verified): status-output contract (concise/JSON `make status` + `SERVICE=`
focus, `7ed82b89` + status fixes), Slack `/cluster-status` concise-summary wiring (`5b9442cf`),
CVE-dashboard/exporter cleanup (`a119fdde`, `d471d075`). Dependabot auto-merge observability = scoped
spec only (not implemented; doc renumbered to v1.24.1).
- **Done 2026-08-13:** branch renamed `v1.25.0`→`v1.24.1` (old remote deleted); dashboards appset
  (`grafana-dashboards-hub`/`-acg`) repointed to `k3d-manager-v1.24.1`, `hub-grafana-dashboards`
  Synced/Healthy; plan/bug docs renumbered `v1.25.0-*`→`v1.24.1-*` (kept `v1.25.0-e2e-*` as G);
  CHANGELOG `[1.24.1]`, README releases table (3-most-recent, de-duplicated) + Issue Logs (5 newest) +
  `docs/releases.md`.
- **Released 2026-08-13:** PR #115 merged to main (e7a32bb9), tag v1.24.1 created and pushed, GitHub
  release published. `enforce_admins` branch protection restored. Retrospective filed
  (`docs/retro/2026-08-13-v1.24.1-retrospective.md`). Three Copilot findings addressed (Makefile
  shell-injection quoting + roadmap/plan-header doc sweep). **Partial hub repoint complete**
  (dashboards appset repointed to v1.24.1, Synced/Healthy). **Full repoint deferred** to v1.25.0
  release-ops (`observability` + `observability-acg` + `services-git` still track v1.23.0; safe to defer
  until v1.25.0 ships, do NOT delete v1.23.0 branch yet).

### v1.25.0 = workstream G (branch created, ready for development, BLOCKED cross-repo)
Stripe/Go live acceptance (stuck 2/4) + E2E verification harness (Tier 1 vCluster blocking + Tier 2 ACG
sandbox periodic) + e2e observability. Plan docs `v1.25.0-e2e-*`. **Branch created 2026-08-13** from
merged main (`e7a32bb9`, inherits v1.24.1, no back-merge; avoids divergent `vulnerability-inventory-exporter.yaml`
— v1.24.1 touched it via `a119fdde`, e2e-observability plan #2 edits it again). Critical path: build the
harness (buildable now, not blocked) → run the Stripe E2E on Tier 2 to move G past 2/4. Roadmap order:
v1.24.1 → v1.25.0-G → v1.26 → v1.27 → v1.28.

### E2E harness Tier 1 — IMPL spec written 2026-08-14 (Claude), ready for Codex handoff
Impl-grade spec: `docs/plans/v1.25.0-e2e-harness-tier1-impl.md` (plan #3 for v1.25.0; within ≤5 cap).
**Locked decisions (user, 2026-08-14):** (1) execution = spec→Codex handoff; (2) runner placement =
in-cluster Playwright **Job** (ClusterIP DNS, not host port-forward); (3) test delivery = build+publish a
dedicated e2e image to GHCR (`ghcr.io/wilddog64/shopping-cart-e2e-tests`), Job pulls pinned digest;
(4) standing rule — every major tech gets a learning guide → this release ships
`docs/guides/vcluster-e2e-harness.md` (memory `feedback_guide_per_major_tech`).
**Key discovery:** existing `shopping_cart_reconcile_*` are hardcoded to the live app cluster
(`--context ubuntu-k3s`, ESO/Vault/Postgres) — NOT reusable for a throwaway vCluster. The real Tier 1 core
is a **self-contained substrate bundle** `scripts/etc/e2e/` (3 services + minimal postgres/redis + seed, no
ESO/Vault/ArgoCD, `OAUTH2_ENABLED=false`), derived from the e2e repo's `docker-compose.yml` (the
service+datastore contract) + each service's `k8s/base`. Actual Playwright project is `flows` (not `flow`);
JSON report → `test-results/results.json`. Scope = Tier 1 only (Part 1 e2e-image+workflow_call + Part 2
`e2e_verify_vcluster`); Tier 2 `e2e_verify_sandbox` + exporter/dashboard deferred (plan #2 / v1.26.0).
**Strategic note (unresolved, for user):** for unblocking **G's Stripe acceptance** specifically, Tier 2
(ACG sandbox full-stack via existing bring-up) may be the SHORTER path — it runs the Stripe E2E and reuses
the normal stack, whereas Tier 1 requires inventing the minimal bundle. Tier 1 mainly serves the v1.26.0
per-candidate gate. Not yet decided whether to build Tier 1 first (current plan) or jump to Tier 2 for G.
Not yet handed off to Codex.

### ACG cleanup + Tier 2 self-contained — specs written 2026-08-14 (Claude); user chose "start with ACG"
- **G unblock finding:** the order schema blocker (`order_items.total_price NOT NULL`) is ALREADY resolved on
  `origin/main` (`cb58e8b`, PR #67 — squash-merge, so `0e3feb9` reads as not-ancestor: false-negative per
  `reference_squash_merge_branch_cleanup_safety`) and the order image promoted (`df35ea8`). G's remaining work
  = **rerun** the Stripe live E2E on a real substrate (Tier 2), not a code fix.
- **Root cause of ArgoCD "unknown resources" after sandbox death:** `_provider_k3s_aws_destroy_cluster`
  (k3s-aws.sh) is the ONLY app-cluster provider with no hub-deregister step (OCI + hostinger both have
  `_<p>_deregister_cluster`). It tears down CFN + tunnel but never deletes the hub `cluster-ubuntu-k3s` Secret
  / generated Apps → they go `Sync: Unknown`. **Registration is opt-in** (`deploy_app_cluster` does NOT
  auto-register; prints "Then run: register_app_cluster").
- **Two specs written (user greenlit both):**
  (a) `docs/bugs/v1.25.0-bugfix-k3s-aws-hub-deregister.md` — add `_k3s_aws_deregister_cluster` (delete
      `cluster-ubuntu-k3s` + generated `destination.name==ubuntu-k3s` Apps, finalizers stripped) and call it in
      `destroy_cluster` before `acg_teardown`. Graceful-teardown safety net only; TTL-expiry watchdog stays
      v1.26.0. Implemented and pushed as `d6217640`; shellcheck and provider BATS gates passed.
  (b) `docs/plans/v1.25.0-e2e-harness-tier2-sandbox.md` (plan #4) — `e2e_verify_sandbox` runs the full stack +
      Stripe live E2E in-sandbox with `OAUTH2_ENABLED=true`, **INVARIANT: never calls `register_app_cluster`**
      (self-contained island → nothing to orphan on TTL expiry). This is the shortest path to G past 2/4.
- **v1.25.0 plan-doc count = 4** (observability-path-a, verification-harness, tier1-impl, tier2-sandbox); within
  ≤5 cap. Neither harness spec handed off yet.
- **Dependabot check (payment PR #53):** benign auto-close (superseded); bcprov 1.85→1.85.2 now in open group
  PR #62 (main still 1.85). #62 is MERGEABLE but BLOCKED by a **Checkstyle & SpotBugs failure** (NOT the
  PACKAGES_TOKEN/401 issue). Payment has ~10 stacked dependabot PRs; #60 (built-in GITHUB_TOKEN) unblocks the
  PAT-rotation ones. Not yet actioned.

This branch (now `k3d-manager-v1.24.1`) is based on merged `main` (`fd281c85`). Its queued scope now contains three
implementation-grade plans: `docs/plans/v1.25.0-e2e-verification-harness.md`,
`docs/plans/v1.25.0-e2e-observability-path-a.md`, and
`docs/plans/v1.25.0-dependabot-automerge-observability.md` (event-driven Dependabot auto-merge
monitoring with Grafana/Alertmanager visibility), plus
`docs/plans/v1.25.0-status-output-contract.md` (concise color-coded `make status` with failed-service
health/HTTP codes, `SERVICE=<name>` focused diagnostics, full and JSON modes). Implementation is not started.
The status refactor is now implemented on this branch and live-verified healthy after the
webhook login credential/KUBECONFIG fix (`fix(status): use current Vault credentials for login smoke`).
**Status source verified 2026-08-12:** `bin/k3dm-webhook-setup` restored the existing 64-byte
Keychain token, refreshed the GitHub secret, and reinstalled the LaunchAgent; health endpoint HTTP 200.
Concise status now works. It reports separate Keycloak, ArgoCD, and Grafana login 401 failures plus
expected ESO/data-layer warnings; see `docs/issues/2026-08-12-webhook-token-restored-status-verification.md`.
Follow-up fixed provider selection from the active-provider file and classified optional Pushgateway
refusal as a warning; remaining login 401s are genuine service credential issues. See
`docs/issues/2026-08-12-status-provider-and-optional-pushgateway.md`.
The login checks are now green after reading hub-scoped Keycloak credentials and current ArgoCD/Grafana
values from Vault; the LaunchAgent renderer now substitutes the real HOME in KUBECONFIG. See
`docs/issues/2026-08-12-status-login-credentials-and-launchagent-kubeconfig.md`.
`make status-json` now follows the active provider as well as `make status`; the live JSON result is
`overall=healthy`, provider `k3s-hostinger`. See `docs/issues/2026-08-13-status-json-default-provider.md`.
Stale Istio `ubuntu-k3s` Applications were diagnosed as deletion-tombstoned objects targeting retired
`host.k3d.internal`; their finalizers were removed and ArgoCD deleted them. Hostinger Istio remains
Synced/Healthy. See `docs/issues/2026-08-13-stale-istio-ubuntu-k3s-applications.md`.
The CVE remediation dashboard cleanup is implemented: exporter events now expose `current=true` and
mark superseded failed events; Grafana separates Current Remediation Status from Remediation History.
Historical ConfigMaps remain intact. See the updated `docs/issues/2026-08-12-cve-remediation-failed-history-investigation.md`.
The mistaken `docs/argocd-login-smoke-diagnosis` branch was closed/deleted and is not part of v1.25.0.

### Branch-hygiene reconciliation — 2026-08-13 (Claude)

Post-v1.23.0-release work had been committed onto the **released, dead-end `k3d-manager-v1.23.0`
branch** and was stranded (v1.23.0 was squash-merged as `7253ece4`, so those commits never reach a
forward branch). Reconciled onto `v1.25.0`:

- **Orphaned future plans rescued + renumbered** (`4cdd7abf`): resolved a v1.26.0 collision (image-signing
  vs new sandbox-cleanup). **User decision: sandbox-registration=v1.26.0, image-signing=v1.27.0,
  zero-downtime=v1.28.0.** `docs/plans/v1.26.0-sandbox-registration-lifecycle-cleanup.md` moved as-is;
  `v1.26.0-image-signing-cve-loop-closure.md` → `v1.27.0-…`; `v1.27.0-platform-zero-downtime-rollouts.md`
  → `v1.28.0-…`; internal refs + `docs/roadmap.md` "Queued milestones" reconciled.
- **Live CVE dashboard + exporter forward-ported** (`a119fdde`): the concise-header dashboard cleanup and
  exporter `deployment_advanced`/`display_reason` logic existed only on v1.23.0 (which the hub
  `hub-grafana-dashboards` ApplicationSet **currently tracks**). Both files were a strict superset of the
  v1.25.0 versions; carried onto v1.25.0. YAML-parse + embedded-python checks clean.

**Dashboards repointed live 2026-08-13 (Claude):** `grafana-dashboards-hub` + `grafana-dashboards-acg`
appsets reapplied with `K3D_MANAGER_BRANCH=k3d-manager-v1.25.0`; live `hub-grafana-dashboards`
Application now `targetRevision=k3d-manager-v1.25.0`, **Synced/Healthy** (forward-port is byte-identical
to live → no drift). Repointed to v1.25.0 (not v1.24.0) because v1.24.0's dashboard is the older verbose
version — pointing there would revert the live cleanup.
**⚠️ STILL on `k3d-manager-v1.23.0`:** `observability`, `observability-acg`, `services-git` (the exporter
is synced by `observability`, not the dashboards appset). They keep serving the correct (identical)
content, so nothing reverts — but **do NOT delete the v1.23.0 branch until these are repointed too.**
That is a release-grade full-hub repoint (services-git pulls service-manifest deltas), best done when
v1.25.0 is cut; confirm with `argocd_check_values_branch`. **Process:** forward work goes on `v1.25.0`,
never a released branch.

### Slack `/cluster-status` concise-summary wiring — IMPLEMENTED 2026-08-13 (Claude)

Spec `docs/bugs/v1.25.0-bugfix-slack-cluster-status-summary-wiring.md` (`2094398e`); fix `5b9442cf`
(`bin/k3dm-webhook`). `_run_hostinger_status` now runs `bin/cluster-status --json` (token passed via env
so no Keychain read; `NO_COLOR=1`), parses the last JSON line, and renders a concise Slack summary via new
`_format_status_summary_slack` — emoji severity (`:x:`/`:warning:`/`:white_check_mark:`/`:grey_question:`)
+ `N ok / N warn / N fail` counts + error/warning lines, **no ANSI**, raw-report fallback retained.
**Verified static:** py_compile clean; formatter unit-exercised (fail/healthy/unknown → correct emoji, no
ANSI); webhook.bats 53/53. **Scoped OUT:** `_run_cluster_status` (ACG path) — bespoke reachability report,
already emoji-based, not backed by `cluster-status --json` (documented non-goal in the spec).
**Live-verified 2026-08-13:** `make restart-webhook` done (health 401 = up+auth). End-to-end smoke with
real cluster data — `CLUSTER_PROVIDER=k3s-hostinger bin/cluster-status --json` → exit 0, 13 services
healthy; fed through the live `_format_status_summary_slack` →
`:white_check_mark: *Cluster status: HEALTHY* — \`k3s-hostinger\`  (13 ok / 0 warn / 0 fail)` (no ANSI).
Only an actual Slack `/cluster-status` trigger (user action) remains as final confirmation.

## Current focus — v1.24.0 CODE-COMPLETE + LIVE-VERIFIED; release complete

**v1.24.0 = platform hardening (D+E+F+#18).** All code committed + pushed to
`origin/k3d-manager-v1.24.0`, Claude-verified on origin. CHANGELOG + README + `docs/releases.md`
written. **Next: PR gate → merge → tag → reapply ApplicationSets (hub + ACG) → confirm
`argocd_check_values_branch`.**

| Slice | Commit(s) | State |
|---|---|---|
| D — webhook auth fail-closed + Slack allowlist enforcement | `3fddcf3e`; hostinger truncation `8eb8cc34` | live; py_compile + webhook.bats 53/53 |
| F — Istio ambient / hostinger CNI drift reconcile onto release branch | `357edf52` | shellcheck + YAML pass |
| E — Prometheus weak-default removal + ArgoCD/Prometheus rotators + 4 live-verify bugfixes | `e1256d0a`, `3db193cb`, `84232cc0` | LIVE-VERIFIED (see below) |
| #18 — CVE promoter persists to git | `3df62fbf` | dry-run verified live (see below) |
| agy headless analyze fix | `69e21e15` | live-smoked (real analysis text) |
| show-service-passwords ArgoCD reads Vault | `33e42905` | shown password logs in |

### Live-verify state (release-ops, done 2026-08-11)

- **E ArgoCD rotator DEPLOYED + verified live:** rotator manifest applied + Vault `argocd-rotation`
  policy/role created via `deploy_argocd_platform_ops`; one-shot Job rotated → `argocd-secret` mtime
  advanced, stored bcrypt clean/valid, new Vault password → ArgoCD `/api/v1/session` **LOGIN SUCCESS**
  (wrong pw rejected as control). Prometheus host-side launchd agent installed + rotate regenerated a
  strong bcrypt on `ubuntu-hostinger`. **The live ArgoCD admin password is now the ROTATED value**
  (old bcrypt `$2y$10$AgfGS5Vm…390Uqy.` retained as manual restore net; new plaintext in Vault
  `secret/argocd/admin`). ⚠️ **Restore-on-failure path is code-present (trap) but not fault-injected**
  (avoided breaking the live credential).
- **#18 promoter git-persist DRY-RUN verified live:** exercised `_git_persist_promotion`'s exact path
  non-destructively — clone release branch via `x-access-token:` URL (exit 0), real `set_image_digest.awk`
  on `services/shopping-cart-order/kustomization.yaml` (appended `images:` block correctly),
  promoter-author local commit, `git push --dry-run origin HEAD:k3d-manager-v1.24.0` → exit 0
  (**token authenticates WRITE**). Remote untouched.
  - ⚠️ **INTERIM TOKEN — MUST REPLACE before in-cluster promoter use.** Keychain
    `platform-ops-git-writer`/`k3dm` currently holds `gh auth token` (`repo` scope) — acceptable ONLY
    for the local dry-run (runs as the user). Before the promoter runs **in-cluster** (token lives in
    a cluster Secret), replace with a dedicated **fine-grained `contents:write`-only PAT** on
    `wilddog64/k3d-manager`, then re-run `argocd_sync_git_writer_secret platform-ops`. The full E deploy
    already brought the promoter code live with `GIT_WRITE_TOKEN` `optional:true` (safe live-patch fallback).

### Follow-up (non-blocking)

- Update auto-memory `reference_trivy_critical_upstream_image_noise` "still errors" note once a real
  `wilddog64/*` TrivyCritical analyze is observed posting real text via the `69e21e15` fix.
- **CVE remediation dashboard history (investigated 2026-08-12):** the displayed `ready_pod_digest_mismatch`
  rows are retained Aug 6/Aug 9 historical events. Payment has later `applied` events; current order/payment
  workloads are healthy. The flat panel does not collapse superseded failures. Follow-up issue:
  `docs/issues/2026-08-12-cve-remediation-failed-history-investigation.md`.

## Pending releases (forward scope)

- **v1.25.0 = Stripe/Go live acceptance + hostinger capacity (G, BLOCKED, cross-repo).** Merge
  order-repo `0e3feb9` schema fix (`order_items.total_price NOT NULL`) + promote image → rerun Stripe
  live E2E (2/4 now). **Live deadlock stopgapped 2026-08-10** (`docs/issues/2026-08-10-hostinger-rollout-deadlock-maxsurge-on-2cpu-node.md`):
  order/basket wedged mid-rollout — `maxSurge=1` needs 2× CPU on a 95%-full 2-CPU node → `FailedScheduling`;
  live-patched both to `maxSurge=0/maxUnavailable=1`, converged. **Durable fix = this workstream:** commit
  `maxSurge=0` into app git manifests (ArgoCD may selfHeal the live patch away) OR bump node CPU.
  **+ E2E verification harness (plan doc #1 `v1.25.0-e2e-verification-harness.md`):** enable the disabled
  e2e suite on ephemeral substrates — Tier 1 vCluster (per-candidate blocking, `OAUTH2_ENABLED=false`) +
  Tier 2 ACG sandbox (periodic full-stack, real ingress/OIDC, runs Stripe live E2E). Substrate-agnostic
  (needs basket/catalog/order URLs + oauth flag); new `scripts/plugins/e2e.sh`; `workflow_call` on
  `shopping-cart-e2e-tests`. Exit-code + JSON-summary contract seeds the v1.26.0 gate.
  **+ e2e observability (plan doc #2 `v1.25.0-e2e-observability-path-a.md`):** reuse the CVE exporter seam
  — harness writes a `k3dm.k3d.io/e2e-result=true` ConfigMap; extend `vulnerability-inventory-exporter.py`
      to emit `e2e_*` gauges; new `grafana-dashboard-e2e.yaml` + `E2EVerificationFailing/Stale` rules; deploy
      via `argocd.sh`. No new component, no Tempo (span tracing = separate forward theme).
      **+ Dependabot auto-merge observability (plan doc #3 `v1.25.0-dependabot-automerge-observability.md`):**
      signed GitHub PR/check/workflow events plus 15-minute read-only reconciliation feed bounded
      Prometheus metrics, Grafana panels, and owned Alertmanager Slack alerts. Monitor never merges or
      changes branch protection; implementation not started.
- **v1.26.0 = image signing + attestation — close the CVE loop (SCOPED, not started).** Spec
  `docs/plans/v1.26.0-image-signing-cve-loop-closure.md`. cosign sign + Trivy vuln/SBOM attest at build;
  `cosign verify` at promotion (promoter gate) AND admission (Kyverno, staged Audit→Enforce, app
  namespaces only, upstream/`tier:upstream` excluded). Key-based, private key in Vault + Keychain backup,
  pub via ESO (LOCKED, not keyless). Multi-repo: k3d-manager `signing.sh`/Kyverno/ClusterPolicy/promoter
  gate + shopping-cart `{order,payment,basket,frontend,product-catalog}` CI. CI key delivered as GH
  secrets seeded from Vault (runners can't reach Vault). Slots after v1.25.0. See
  [[project_image_signing_cve_loop]].

## Backlog / queued (not release-gated)

- **Secure Vault remote access (QUEUED — start after v1.24.0 release).** Expose the **Vault UI** via the
  existing laptop cloudflared as `vault.3ai-talk.org → http://localhost:18200`, gated by **Cloudflare
  Access** with **MFA = Google IdP** (TOTP). Two gates: Access (identity+MFA) then Vault login
  (userpass/OIDC — NOT root token). **Non-negotiable build order:** create the Access application +
  default-deny allow-only-me policy FIRST, THEN add cloudflared ingress + proxied DNS; verify an
  anonymous request redirects to Access before trusting. Enable a Vault audit device; root token
  laptop-only (break-glass). Vault today has NO public path (reverse-tunnel loopback only). Filing
  (decision pending): `docs/howto/secure-vault-remote-access-cloudflare-access.md`. No changes made yet.
  See [[project_secure_vault_remote_access]].
- **Jenkins DEPRECATED in docs — DONE 2026-08-10, code KEPT.** Built-in but unused (no live pods, opt-in
  `ENABLE_JENKINS=1` only, not in roadmap; real CI/CD = GHA+ArgoCD). Marked deprecated in current-state
  docs; historical docs untouched. Earlier code-retirement plan **cancelled**. See
  [[project_jenkins_deprecation]].
- Dashboard parts (b)+(c) — spec `v1.23.0-cve-dashboard-parts-bc-*` superseded by the Codex 1:1 dashboard;
  re-scope before executing. `docs/bugs/2026-08-01-app-cve-scan-nonzero-exit-and-missing-pod-labels.md`
  carry; the observability.sh E per-hunk carry was **VACUOUS** (empty diff) → dropped.
- Shopping-cart Dependabot backlog (Go builder-image bumps, majors held) — `project_backlog.md`.
- rabbitmq-client-java NPE fix `36ed860` — JAR publish + pom update pending.

## Recently shipped (pointers only — detail in CHANGELOG + retro)

- **DRY_RUN Phase 4 COMPLETE (2026-08-14):** `7a34856c` pushed to `origin/k3d-manager-v1.25.0`.
  Slack `cluster-up`/`cluster-down` now parse provider and dry-run tokens in any order, inject
  `DRY_RUN=1` into the spawned make job, skip post-provision/metrics side effects for previews,
  and document the command syntax. Behavioral webhook BATS (54/54), cluster-down BATS (12/12),
  py_compile, agent lint/audit, and isolated smoke test passed. Mutation check was pass → fail
  after removing the `*)` bridge source → pass after restoration; `bin/cluster-down` remained
  unchanged. `make restart-webhook` intentionally deferred for Claude's live process.

- **PR #113 Copilot follow-up (2026-08-11):** six actionable review threads addressed and resolved in
  `be29b5a0` (credential exposure, portability, launchd PATH, and test dependency). CI is green; PR
  remains review-gated pending an approving reviewer.

- **v1.23.0** RELEASED — CVE observability + remediation lifecycle (B+C). PR #112 `7253ece4`, tagged;
  platform-ops deployed live (alert-noise split active), retro `docs/retro/2026-08-09-v1.23.0-retrospective.md`.
- **v1.22.0** RELEASED — OpenLDAP bitnami→Symas migration. PR #111 `1bbb74b0`, tagged.
- **v1.21.0** RELEASED — webhook security hardening. PR #110 `f68bdee1`, tagged.
- **v1.20.0** RELEASED — CVE auto-patch-loop hardening. PR #109 `9da73458`, tagged.
- Stripe checkout A–F all MERGED to main across the 5 shopping-cart repos (2026-08-02); payment side
  live on hostinger. Remaining live-acceptance work = v1.25.0 (workstream G).

**Open bug (2026-08-14): k3s-aws SSM agent never registers.** Fresh instance
`i-015dbcd49b4f8eec6` was running/healthy with its instance profile associated, but
`describe-instance-information` returned no managed-instance record. Console output reports that
the SSM agent cannot acquire EC2 credentials and that the account's Systems Manager instance
management role is not configured. This blocks the provider's 150-second SSM wait; the flannel
fallback message is informational. Evidence and follow-up are recorded in
`docs/bugs/2026-08-14-k3s-aws-ssm-agent-cannot-register.md`; no live mutation was performed.

**Grafana port-forward hardening (2026-08-18):** `87382c7b` pushed to `origin/k3d-manager-v1.25.0`. Hostinger monitoring LaunchAgents now use health-aware supervisors: Grafana checks `/api/health` and Pushgateway checks `/metrics`, restarting stale kubectl forwards after the startup grace period. Issue and verification are recorded in `docs/issues/2026-08-18-grafana-502-stale-port-forward.md`.

**Grafana live verification follow-up (2026-08-18):** After `87382c7b` was applied, the health-aware wrapper correctly retried the forward, but the hub API reported embedded etcd and etcd-readiness failures and broad pod probe timeouts; public Grafana remained HTTP 502 during that control-plane incident. Follow-up is documented in `docs/issues/2026-08-18-grafana-502-hub-control-plane-degradation.md` and is separate from the stale-forward fix.
