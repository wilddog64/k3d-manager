# Active Context — k3d-manager

> Compressed 2026-08-21 (v1.26.0 committed work complete). Settled fixes collapsed to
> pointers; detail lives in `memory-bank/archive/`, `CHANGELOG.md`, `docs/retro/`,
> `docs/issues/`, `docs/bugs/`, and git history.

## Current focus

- **v1.27.0 foundation-managed vCluster CLI Part B DELIVERED + VERIFIED + PUSHED** — HEAD
  `142fd06b` on `origin/k3d-manager-v1.27.0` (Codex; its own note cited `6c2dd94d` which was
  amended away and is not in history). Rewires `vcluster.sh` to `foundation_ensure_vcluster_cli`
  (module-scoped `_VCLUSTER_BIN`, guards non-zero + empty path), removes the consumer installer,
  updates help/docs, reworks BATS to stub the contract. **Claude re-ran gates independently:**
  BATS 36/36, shellcheck clean, `bash -n` clean, both disappearance greps empty, subtree
  untouched. **LIVE `make e2e` gate PASSED for the CLI contract:** real download + SHA-verify +
  atomic install of vcluster `0.32.1` (managed path, not PATH Homebrew), plugin created the
  throwaway vCluster + substrate via the managed binary, teardown clean; artifact/ConfigMap/exporter
  all carry commit `9b3a5754`. The Playwright app Job failed (`running-playwright`, pre-existing
  app-test failure — NOT the CLI change). **Plan #1 (Parts A+B) functionally COMPLETE.** No PR yet
  (v1.27.0-release-time step). Part A shipped as lib-foundation `v0.4.13`.
  - ✅ **Finding 1a FIXED + LIVE-VERIFIED** (`5cd67228`): added a `num()` helper coercing
    empty/None/non-numeric → `0` (timestamps keep integer display), routed every numeric gauge
    emission through it so no single malformed value can zero out the whole scrape. Redeployed
    via `kubectl apply` + `rollout restart`; live-confirmed `up{exporter}=1` (new pod, 3711
    samples), `e2e_last_run_duration_seconds … 0`, `trivy_vulnerability_inventory`=3706 series
    back — both E2E and CVE dashboards receiving data again.
    `docs/issues/2026-08-21-e2e-exporter-empty-duration-metric.md`.

- **v1.26.0 RELEASED** — PR #117 `1bbe5439` merged to main, tag/release published. Branch protection restored (`enforce_admins=true`, 1 required approval). Shipped 3/5 scopes (fleet node lifecycle count-agnostic, E2E promotion gate + observability, managed registration cleanup). Retrospective: `docs/retro/2026-08-21-v1.26.0-retrospective.md`.

- **v1.27.0 active branch** (`k3d-manager-v1.27.0`, branched from merge commit). **Scope = 4 plan docs (4/5, under cap):**
  1. `docs/plans/v1.27.0-foundation-managed-vcluster-cli.md` — load-split **prerequisite**. **Part A DONE:** lib-foundation `v0.4.13` released (PR #44 `0a3e4043`, tag/release live), subtree-pulled into `scripts/lib/foundation` — `foundation_ensure_vcluster_cli` vendored + verified. **Part B UNBLOCKED (next up):** rewire `scripts/plugins/vcluster.sh` to call `foundation_ensure_vcluster_cli "$VCLUSTER_VERSION"`, drop the local installer/Homebrew paths.
  2. `docs/plans/v1.27.0-m2-remote-e2e-runner.md` — the actual E2E load-split off the M4 laptop; depends on #1 (now met). **STARTED.**
     - Increment 1 DONE (`5c863dcc`): producer-side runner-provenance contract — E2E summary + result-event ConfigMap carry a `runner` field (default `local-m4`, `E2E_RUNNER` override), `k3dm.k3d.io/e2e-runner` label, prune keyed per (service,tier,runner). Backward-compatible; BATS 18/18 + 10/10.
     - Increment 2 DONE (`6d2ce551`): consumer side — exporter reads `runner` (legacy→`local-m4`), adds it to metric dims + `e2e_run_info` + emitted label body; Grafana e2e dashboard gains a `runner` template var (multi/includeAll/All default), every panel filters `runner=~"$runner"`; e2e alert summaries include runner. RBAC unchanged. BATS 11/11 (+1). ⚠️ **LIVE redeploy of these platform-ops manifests DEFERRED to the plan-#2 live-accept gate** (when real `runner=m2` data exists) — live exporter is still the Finding 1a hotfix (`5cd67228`); source is ahead by the runner label. Redeploy exporter+dashboard+rule via `argocd.sh` at acceptance.
     - Increment 3 DONE (new plugin `scripts/plugins/e2e_remote.sh`): M2 bootstrap/preflight — public `e2e_runner_preflight`/`e2e_runner_bootstrap`/`e2e_runner_status`. Pure BATS-testable gate core (`_e2e_remote_eval_gates`) + SSH probe; gates docker-up/lock-free/CPU-idle≥35% (2 samples)/mem≥25%/disk≥40GiB → structured `status=` (available|busy|docker_down|capacity_*|unreachable). Bootstrap: reachability → start OrbStack only if stopped (bounded wait) → reconcile a **dedicated** `k3d-e2e-runner` cluster (refuses hub name `k3d-cluster`) → verify vCluster CLI via foundation contract. Safe SSH opts (BatchMode, no StrictHostKeyChecking=no). BATS 17/17, shellcheck clean, `bash -n` clean. **LIVE-VERIFIED against real M2** (`k3d-manager e2e_runner_preflight` → `status=available`, cpu 70/72%, mem 46%, disk 153GiB).
     - **M2 live resource re-check (2026-08-22, user-requested):** M2 = `m2jump`→`m2-air.local` (hostname `Mac`, user cliang), 8 cores/16 GiB, macOS 26.5.1. Host gates pass (CPU idle ~60-73%, mem 45-46% free, disk 153 GiB). **Caveats found:** (a) real container budget is the **OrbStack Linux VM cap = 7.818 GiB**, not 16 GiB — and a pre-existing `k3d-k3d-cluster` (server+3 agents) already eats ~1.8 GiB of it + ~6 GiB host swap in use → ~6 GiB free in the VM for the ephemeral E2E vCluster (workable but tight; consider tearing down M2's stray hub-shaped cluster or raising the VM mem cap before acceptance). (b) `/opt/homebrew/bin` (k3d, vcluster) is **not** on M2's non-interactive SSH PATH → remote cmds 127 without a PATH prefix; fixed via `E2E_M2_REMOTE_PATH=/opt/homebrew/bin:/usr/local/bin` injected by `_e2e_remote_ssh`. (c) An earlier probe caught OrbStack mid-`Stopped`/VM-start-timeout; it is **Running** now — the preflight's docker gate is exactly the right guard for that transient.
     - Increment 4 DONE (`e2e_remote.sh` + Makefile): `make e2e-remote RUNNER=m2 [DIGEST=sha256:…]` → `e2e_runner_dispatch`. Validates RUNNER against an allowlist (`E2E_RUNNER_ALLOWLIST`, default `m2`; value reused verbatim as provenance, never free text) + DIGEST against `^([repo]@)?sha256:<64hex>$` (rejects injection), gates on `e2e_runner_preflight` (busy/capacity/unreachable → abort, **no local fallback**), SSHes the remote `e2e_verify_vcluster <digest>` with `E2E_RUNNER=m2`/runner KUBECONFIG/remote report dir, streams output via `tee` to a local transcript (`~/.k3dm/e2e/dispatch/m2-<ts>.log`), returns the remote exit code unchanged (`PIPESTATUS[0]`). `make e2e` unchanged. BATS 26/26, shellcheck clean, `bash -n` clean; Makefile guard verified (no RUNNER → usage+exit 2). Not live-dispatched (would consume M2 — reserved for the inc-6 acceptance).
     - Increment 5 DONE (`e2e_remote.sh`): restricted M4-side result publisher — public `e2e_result_publish` (SSH forced command) + `e2e_result_publisher_install`. `e2e_result_publish` reads ONE JSON doc on stdin (bounded by `E2E_PUBLISH_MAX_BYTES`=64KB), strict-validates the exact E2E schema via `_e2e_publish_build` (exact allowed-key set → rejects namespace/kubeconfig/labels/annotations injection; required keys; bounded lengths + safe charsets; runner must be a **remote** allowlist member, local-m4 rejected; digest `[repo@]sha256:<64hex>` or null; exit_code 0..255; result pass|fail), then `_kubectl --context k3d-k3d-cluster -n platform-ops apply -f` a **deterministic-name** ConfigMap (`e2e-result-<runner>-<sha256_12(run_id)>`) → **idempotent per run id** (SSH retries can't dup). Hub context + namespace assigned INTERNALLY (never from payload); KUBECONFIG pinned so an inherited/sandbox context can't redirect the write; retention pruning also pinned to the hub context. Redacted audit log (run_id/runner/result/outcome only — no digest/payload). `e2e_result_publisher_install <pub>` writes an idempotent `command="…e2e_result_publish",restrict,no-pty,no-*-forwarding` authorized_keys entry (marker `e2e-m2-publisher`), refuses non-keys. Static disappearance test confirms no scp/rsync/VAULT_TOKEN/cloudflare/StrictHostKeyChecking=no and the M4 publish-kubeconfig never crosses SSH. Also fixed an inc-4 latent bug: `e2e_remote.sh` now self-defines `E2E_REPORT_DIR`/`E2E_RESULT_EVENT_*` defaults (lazy-load sources only the matched plugin, so it can't rely on e2e.sh under `set -u`). BATS 40/40, shellcheck clean, `bash -n` clean; e2e.bats(18)+e2e_observability.bats(11) still green (no regression). Publisher not live-installed (needs the dedicated M2 key — inc-6 acceptance).
     - Increment 6 DONE (`b5fff9c4`, `e2e_remote.sh` + Makefile + BATS): §5 failure/ops. Runner lock is now an **atomic directory** (`mkdir`) holding an owner-token `meta`; `_e2e_remote_lock_acquire`/`_release` claim/free by token (release only when `grep -qxF` matches — never blind `rm`); dispatch claims the lock (busy → `_err`, **no local fallback**), sets a RETURN trap to release, and chains `e2e_runner_publish_back $rc` after the E2E preserving the remote exit code. **Publish-back (M2-side):** `e2e_runner_publish_back` finds the newest run summary (`_e2e_newest_summary`, excludes markers) or synthesizes a schema-valid failed one (`_e2e_synth_summary`, clamps exit 0..255) when a crash left none, pushes it to the M4 forced-command publisher over the dedicated key (`_e2e_publish_back_push`, `ssh -i`), else retains `*.publication_pending.json`; **always returns 0** so it can't mask the E2E rc. `e2e_runner_publish_replay` (nullglob) replays retained pendings → `*.published.json` (idempotent), non-zero while any still pending. **M4-side ops:** `e2e_runner_replay <runner>` (allowlist + reachability guarded) drives the remote replay; `e2e_runner_unlock <runner>` clears a lock ONLY past `E2E_M2_LOCK_MAX_AGE`=7200s with no live `e2e_verify_vcluster` (refuses fresh/running — never automatic, never restarts OrbStack, never deletes a cluster); `e2e_runner_health` prints **hub vs runner as distinct lines** — hub outage=critical(rc1), runner-merely-unavailable=warning(rc0) unless `E2E_RUN_REQUESTED=1`/`E2E_FRESHNESS_ALERT=1`→critical. `make e2e-runner-health`/`e2e-replay`/`e2e-runner-unlock` wired (RUNNER-guarded). BATS **68/68** (27 new), shellcheck + `bash -n` clean. Not live-dispatched yet.
     - **Remaining:** the **2-run live acceptance gate** (1 failing + 1 passing E2E via `make e2e-remote RUNNER=m2`; confirm each result lands once in platform-ops, runner-labelled Grafana metrics, unavailable-M2 warning) — folds in the deferred live redeploy of the inc-2 runner-labelled exporter/dashboard/rule via `argocd.sh`. **BLOCKED on hostinger capacity** (see incident below): the hostinger node is CPU-saturated and istiod is down — acceptance against the full stack should wait until that is resolved.
  3. `docs/plans/v1.27.0-image-signing-cve-loop-closure.md` — cosign sign+attest, Kyverno Audit→Enforce (multi-repo, heavy).
  4. `docs/plans/v1.27.0-adaptive-checkout-load-testing.md` — API-level checkout load + telemetry.
  Plans #1 and #2 (both promoted from v1.26.0 deferred, 2026-08-21, "keep all four") are the dependency-ordered chain that moves E2E off the laptop — the response to Prometheus+Grafana over-stressing the M4.

- **Deferred findings from v1.26.0** (filed as tracked issues):
  - Finding 1a — ✅ FIXED + live-verified `5cd67228` (was BLOCKING, not cosmetic). `docs/issues/2026-08-21-e2e-exporter-empty-duration-metric.md`.
  - Finding 2b — dispatcher `--confirm` strip on `deploy_app_cluster` (OPEN). `docs/issues/2026-08-21-dispatcher-strips-confirm-deploy-app-cluster.md`.

- **v1.25.0 released** (PR #116 `d48e465f`, tag/release live).
- **Milestone v1.26.0 — committed work is DONE and pushed on `k3d-manager-v1.26.0`:**
  - **Fleet node lifecycle (count-agnostic)** — Phase A shipped as lib-foundation `v0.4.12`
    (PR #43, subtree-pulled `e60dff69`/`2c083258`); Phase B implemented `b0fe320a` and
    live-verified at `ACG_AGENT_COUNT=4` (5 nodes = ACG cap). Two live-only defects found +
    fixed (`_k3s_agent_is_ready` private-IP match; `fleet-plan` change-set) — `46bfdf1c`,
    memory-bank followup `35e9ecf2`. Suite 17/17, teardown clean. **DONE.**
  - **E2E promotion-gate + durable artifacts** — live acceptance GREEN 2026-08-21: run →
    `~/.k3dm/e2e/*.json` artifact → result-event ConfigMap → exporter `e2e_*` gauges →
    dashboard/alert. **DONE.**
  - **Stale managed-registration cleanup** — live acceptance GREEN 2026-08-21 on a real
    expired sandbox; 23 unrelated survivors exact-match, hostinger untouched. Found + fixed
    BLOCKING Finding 2a (`cleanup-stale-clusters` hung — Secret-first + `--wait=false` fix,
    `0274fdde`). **DONE.**
  - Live-acceptance findings: `docs/bugs/2026-08-21-lifecycle-e2e-live-acceptance-findings.md`
    and `docs/bugs/2026-08-21-fleet-phaseb-live-verification-findings.md`.
- **Load-split promoted into v1.27.0** (2026-08-21): the two v1.26.0-deferred plans
  (foundation-managed vCluster CLI → M2 remote E2E runner) are renamed to `v1.27.0-*` and
  are the leading dependency-ordered work. v1.27.0 now holds 4 plan docs (4/5, under cap).
  v1.28.0 planned: parallel multi-cloud provisioning + zero-downtime rollouts.

## Open follow-ups

- **2026-08-22 service-credentials incident** (`docs/issues/2026-08-22-service-credentials-na-multi-root-cause.md`):
  `make show-service-passwords` all-N/A + no login had THREE independent causes.
  (1) ✅ FIXED: `com.k3d-manager.vault-port-forward` plist was missing from
  `~/Library/LaunchAgents/` (only the `vault-failover` watchdog remained, which does
  NOT own :18200) → nothing on 127.0.0.1:18200 → every Vault-sourced cred N/A.
  `make install-vault-port-forward` restored it (Grafana/Alertmanager resolve; ArgoCD
  works via `argocd admin initial-password -n cicd`). (2) Vault KV lost its display-mirror
  paths (only `ldap/`+`observability/` remain); ArgoCD/Prometheus/Alertmanager are NOT
  ESO-managed so services are unaffected — display-only. ArgoCD re-seed one-liner handed to
  user. (3) **Keycloak never deployed on the hub** (no pod/app/keycloak-Vault-paths) → the
  only genuine login blocker (admin + frontend SSO); spec at
  `docs/bugs/2026-08-22-keycloak-not-deployed-on-hub-sso-down.md`. NOTE: hub Prometheus is
  UNAUTHENTICATED (empty `spec.web`, no edge basic-auth; prometheus.3ai-talk.org→:19090→200
  open) — `observability_rotate_prometheus_basic_auth` targets the ACG app cluster, NOT the
  hub, so it was deliberately NOT run. Also Makefile show-service-passwords reads wrong
  keycloak secret name (`keycloak-secrets` vs deploy's `keycloak-admin-secret`).

- **2026-08-22 hostinger istiod-scheduling cascade** — single 2-CPU node
  (`srv1754834`) chronically at 1910–1960m/2000m (95–98%) CPU requests. `istiod`
  (requests 100m) sat **Pending 2d** (FailedScheduling ×581) → ztunnel/istio-cni
  couldn't wire ambient-mesh routing → `product-catalog` CrashLoopBackOff ×570
  (`postgresql-products ... Connection refused` despite postgres Running) +
  `frontend` new pod stuck ContainerCreating 2d. Surfaced as `make status`
  Product-images 502 + frontend churn. **NOT** stale resources ("23 unknown" was
  the benign ArgoCD operation-status filter); cleanup-stale had nothing to clean.
  **Break-glass (user-approved, `product-catalog`→0):** freed 100m → istiod
  scheduled+Ready instantly → mesh recovered → frontend `578f549949` went 1/1.
  **But `product-catalog` (Product images) can't be restored by break-glass:** node
  is ~10m too tight to run it *alongside* istiod, and **ArgoCD reverts any scale-down
  in ~14s** (trivy-server `--replicas=0` self-restored). Durable fix REQUIRED —
  **RESOLVED — PR #49 `505f758a` (shopping-cart-product-catalog):** cpu 100m→50m
  trimmed in `k8s/base/deployment.yaml:63`. **ArgoCD source gotcha (keep):** the hub app
  `ubuntu-hostinger-shopping-cart-product-catalog` (ns `cicd`) reads
  `repo=k3d-manager path=services/shopping-cart-product-catalog rev=k3d-manager-v1.26.0`,
  whose kustomization pulls a REMOTE base `shopping-cart-product-catalog//k8s/base?ref=main`.
  So #49 IS in the render path, but ArgoCD's tracked revision (k3d-manager) never changed,
  so it kept a cached 100m render and reported Synced. Sequence that landed it:
  (1) `argocd.argoproj.io/refresh=hard` annotation → re-fetched `ref=main`, app went
  **OutOfSync** (target 50m vs live 100m); (2) selfHeal stalled (app Progressing on the
  41m-Pending pod) and manual `kubectl patch`/`argocd sync` were auto-mode-classifier
  BLOCKED; (3) user ran the `kubectl patch deploy … cpu=50m` manually → new pod scheduled
  in the ~90m headroom, went 1/1 Ready, app now **Synced + Healthy**, seed/fts-index jobs
  fired. Patch is durable (live==git 50m, selfHeal won't revert).
  Recovery outcome: **3/3** (istiod + frontend + product-catalog all up).

- **2026-08-22 Keycloak hub deploy — DONE (reachable), dev-users BLOCKED.**
  `deploy_keycloak --enable-ldap --enable-vault`
  (`KEYCLOAK_VIRTUALSERVICE_HOST=keycloak.3ai-talk.org`) → `keycloak-0` 1/1,
  `keycloak-admin-secret` + `secret/keycloak/admin` seeded, VirtualService live.
  **Port-forward bug found+fixed:** `bin/cluster-up:1544` installed the :8880
  forward against remote port 80 but `svc/keycloak` is 8080 (+ healthz `/health/live`
  404s) → every restart failed → public 502. Fixed source (`04cc1e14`, →8080 +
  `/realms/master` healthz) + live stopgap on the installed wrapper + kickstart →
  local :8880 and public `keycloak.3ai-talk.org/realms/master` both **200**. Spec
  `docs/bugs/2026-08-22-keycloak-port-forward-wrong-remote-port.md`.
  **dev SSO — RESOLVED 2026-08-22 (code-fixed `9efb23f7`; live seed applied).** The
  direction was inverted: `dc=home,dc=org` + `ldap-admin` + realm **`home`** is the
  DESIGNED truth (`ldap/vars.sh`, `keycloak/vars.sh:38 KEYCLOAK_REALM_NAME=home`);
  `shopping-cart` is only the smoke realm. Live-verified: realm `home` already has
  working LDAP federation (`realm-config.json.tmpl`), and admin/developer/operator
  are already synced into Keycloak — the ONLY gap is those 3 have **no LDAP
  password** (login can't validate). Fixed `bin/cluster-up` step 10d.5 seed loop
  (label `openldap-stack-ha`, port 1389, `cn=ldap-admin,dc=home,dc=org`,
  `ou=users,dc=home,dc=org`). Steps 10d.6/10d.7 (realm-federation reconcile) are
  broken (target realm `shopping-cart`, path `/opt/keycloak/bin` vs Bitnami
  `/opt/bitnami/keycloak/bin`, no writable HOME) AND redundant → follow-up: delete
  or retarget to `-r home`. Live fix applied: `seed-dev-sso-passwords.sh` run
  out-of-band (classifier-blocked in-agent), all 3 users "LDAP password set +
  verified" via ldapwhoami; passwords mirrored into `secret/keycloak/users/*`.
  Retrieve with `bin/vault-exec --namespace secrets -- vault kv get -field=password
  secret/keycloak/users/admin`. SSO login round-trip to realm `home` still to be
  confirmed by user. `docs/bugs/2026-08-22-hub-openldap-wrong-realm-blocks-sso-users.md`.

- **2026-08-22 Prometheus password N/A in `make show-service-passwords`.** Root
  cause: the entire `secret/k3d-manager` Vault subtree was wiped in a rebuild
  (display-only mirror, not ESO-managed), so `secret/k3d-manager/prometheus-basic-auth`
  is absent. :18200 port-forward is UP; hub Prometheus does not enforce basic-auth
  (`.spec.web` empty) so the value is display-only. Fix = re-seed the Vault path
  (scratchpad `seed-prometheus-display-cred.sh`; classifier-blocked in-agent).
  Cross-ref `reference_show_service_passwords_na_root_causes` cause (2).

- **2026-08-22 v1.27.0 plan #2 live-acceptance — M2 runner NOT provisioned; gate BLOCKED
  on runner setup, not hostinger.** Connection verified green (SSH `m2jump`→`m2-air.local`,
  OrbStack Running, `e2e-runner-health` hub=ok/runner=available). Passing dispatch
  (`make e2e-remote RUNNER=m2`) surfaced three runner-side gaps:
  1. **Lock-acquire false-busy (code bug, spec filed `89d4c67f`):** `_e2e_remote_lock_acquire`
     bare `mkdir` (no `-p`) misreports a missing parent `$HOME/.k3dm/e2e` as "busy (lock
     held)"; `e2e-runner-unlock`/`health` disagree (they use `[ -e ]`). Fix = `mkdir -p`
     parent before atomic leaf mkdir. `docs/bugs/2026-08-22-e2e-m2-runner-lock-acquire-missing-parent-dir.md`.
     Worked around live by `ssh m2jump 'mkdir -p ~/.k3dm/e2e'`.
  2. **M2 repo stale at `k3d-manager-v1.7.2`** → `e2e_verify_vcluster` (plugins/e2e.sh) +
     `e2e_runner_publish_back` (e2e_remote.sh) "not found in plugins"; dispatch has no
     repo-sync step (assumes runner already at dispatched rev).
  3. **M2 has no GitHub fetch access** (`git@github.com: Permission denied (publickey)`) →
     can't `git pull` to advance the repo. Decision needed: how M2 authenticates to GitHub
     + whether bootstrap should sync the runner repo, WITHOUT persisting an M4 credential
     on M2 (plan security constraint). Passing run capacity-bounced once too (WebKit tab
     pegging M2 CPU → idle 12.9% < 35% floor; recovered).

- **Dependabot alert #6 (js-yaml)** — remediated upstream as lib-foundation `v0.4.11`,
  subtree-pulled (`1bf1d2ce`, vendored lockfile `3.15.1`). Still reads `open` only because
  Dependabot scans the default branch (main = v1.25.0); **auto-closes when v1.26.0 → main.**
  Dev-only transitive dep, low effective risk.
- **Un-fixed findings** (filed as tracked issues, deferred out of v1.26.0):
  - Finding 2b — dispatcher `deploy_*` guard strips `--confirm` from `deploy_app_cluster`;
    use a lib-sourcing wrapper. Shared-guard blast radius.
    `docs/issues/2026-08-21-dispatcher-strips-confirm-deploy-app-cluster.md`.
- Replace the interim in-cluster CVE promoter git-writer token with a fine-grained
  contents-write-only PAT.
- Reconcile stale local port-forward/LaunchAgent state when public Grafana or status probes
  fail (see `reference_single_service_502_zombie_port_forward` in auto-memory).
- Keep the ArgoCD smoke credential-drift and k3s-aws SSM registration issues visible in
  `docs/issues/`/`docs/bugs/` until their live follow-ups close.
- 2026-08-20 provisioning/recovery batch (all landed + pushed, recorded in `docs/issues/`):
  k3s-aws SSM→SSH fallback (`fef71219`/`40f1d19a`/`2424f55f`), kubeconfig TLS SAN loopback
  fix (`3603b60c`), SSM Vault-bridge selects SSH, data-layer CoreDNS alias + guarded
  `make down CLEANUP_STALE=1` (`316f26d2`/`f24c0c96`, implies `--keep-hub`), hostinger-only
  hub rebuild, cloudflared IPv4-loopback pin. Account-level SSM Default Host Management Role
  remains an optional infra follow-up.

## Operating decisions

- `make status` follows the active provider (concise/full/JSON modes); Slack reuses the same
  summary contract.
- CVE remediation current-state excludes terminal `superseded`/`deployment_advanced` events;
  history keeps the audit trail. Verifier cadence/bounds stay conservative under hub load.
- E2E runs use a throwaway vCluster, pinned service images, runtime-generated datastore
  credentials, and an EXIT-trap result artifact written before teardown.
- Do not deploy source-only changes until their release-branch/PR gates and live verification
  are explicit.
- When the laptop Vault reverse bridge is required (`HUB_VAULT_USE_BRIDGE=1`, default),
  k3s-aws selects SSH and overrides explicit SSM with a warning; SSM stays available for
  non-bridge Vault profiles.

## Canonical pointers

- Roadmap: `docs/roadmap.md`
- v1.26.0 plans: `docs/plans/`
- Active bugs/incidents: `docs/bugs/` and `docs/issues/`
- Release history: `CHANGELOG.md` and `docs/retro/`
