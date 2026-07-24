# Active Context — k3d-manager

## Status
v1.14.0 RELEASED 2026-07-12 · v1.15.0 RELEASED 2026-07-14 · **v1.16.0 RELEASED 2026-07-23** — Istio ambient mesh · PR #106 merged `4c5d3556` · enforce_admins restored on main · next branch k3d-manager-v1.17.0 open.

> Verbose per-item narrative (full gate dumps, live-verify logs, retracted-diagnosis trails) archived 2026-07-19 → `memory-bank/archive/activeContext-v1.16.0-detail-thru-2026-07-19.md`. Earlier windows: `activeContext-v1.8.0-v1.15.0.md`, `-v1.6.x-v1.7.1.md`, `-v1.4.2-v1.4.8.md`.

## Standing constraints (IN EFFECT)
- **Hostinger is the DEFAULT permanent host; the ACG AWS sandbox (`k3s-aws`) is the e2e test rig** (user, 2026-07-19). Current sprint focus: get `k3s-aws` green in the sandbox (reproducible proof of the ambient mesh) before un-parking hostinger — hostinger is not deprecated, just not the active debugging target this sprint.
- **Spec before implement** — Claude does NOT edit plugin/config/app code directly; write a `docs/bugs/` spec for Codex (exception: `gcp.sh` exact-match). Memory-bank editing IS Claude's own job (mandatory + immediate after every completed action, both files).
- **Verify before trust** — never trust a SHA/BATS/"done"; confirm on `origin/<branch>` via `gh`/`git log`. Code commit = spec files only; memory-bank in a SEPARATE commit.
- **False-pass trap:** always capture the exit code of the command under test on its OWN line (never after `; echo`). For `make up`/`down`, read `UP_EXIT=`/`DOWN_EXIT=` in the log — the wrapper block always exits 0.
- Branch always `k3d-manager-v<version>`; never commit to `main`; no `--no-verify`; route privileged cmds through `_run_command`. Never blind-close warm CDP tabs (cold nav → Cloudflare challenge). Never create a hub `environment=infra` cluster Secret without the owner decision (below). Vault reads are user-only via `! ./bin/vault-exec …`.

## Current live cluster state (2026-07-19) — FRESH-REBUILD e2e PASS for `64168cc7`
Full `make down` (`DOWN_EXIT=0`, hub + CFN stack deleted) → `make up CLUSTER_PROVIDER=k3s-aws` (`UP_EXIT=0`, exit on own line) on a brand-new sandbox (acct `739527292320`). Fresh hub `k3d-cluster` on **v1.32.0+k3s1**; `_argocd_deploy_appproject` deployed BOTH `platform` + `shopping-cart` AppProjects. `ubuntu-k3s` spoke: 3 nodes Ready.
- **`64168cc7` proven live WITHOUT any manual patch** (fresh hub rendered the committed template): the `shopping-cart` AppProject now permits `secrets` for all 4 clusters; `secrets/Service/vault-bridge` = **Synced** (was `SyncFailed: namespace secrets is not permitted` pre-fix); `ubuntu-k3s-data-layer` = **Synced/Healthy**; all 7 data-layer pods 1/1 (minio, postgresql-orders/payment/products, rabbitmq, redis-cart, redis-orders-cache); full app tier 1/1 (basket/frontend/order/product-catalog in `shopping-cart-apps` + payment in `shopping-cart-payment`). Step 10b took the early-exit ("StatefulSets already ready") because ArgoCD had already synced the data-layer. The ephemeral AppProject patch is now retired — permanent fix confirmed end-to-end.

## OPEN blockers
1. **Ambient k3s-aws cold-rebuild blocker is CLOSED, `acg_restart` is wired, and tmp-hygiene code fixes are now landed (2026-07-20).** `ce4d83f0` (istio-cni CNI paths), `bca7d59a` (default `K3S_AMBIENT_MESH=true` on k3s-aws), `5be42ae4` (pin k3sup version), and **`520621a9` (replace both `(( var++ ))` wait-loop post-increments with assignment form so `set -e` no longer aborts the first SSM/node-ready iteration)** are all on `k3d-manager-v1.16.0`, and the former manual-sandbox-restart regression is fixed end-to-end: upstream lib-foundation commit **`03312ae`** on `origin/feat/v0.4.5` adds `_acg_restart_playwright` + `acg_restart`, the subtree pull landed as **`78af86e8`**, and the local dispatcher stub landed as **`4332431f`**. Claude already proved the orphaned `acg_restart.js` recovered a dead sandbox with zero manual clicks, and the cold rebuild plus ambient dataplane verify are complete (`DOWN_RC=0`, `UP_RC=0`, Cilium/istio green, HBONE+mTLS capture PASS). **TMP-HYGIENE follow-through is now code-complete too:** upstream lib-foundation commit **`84d5b27`** on `origin/feat/v0.4.6` adds `_acg_sweep_stale_artifacts` plus the two wrapper call sites; the subtree pull landed as **`381cdf03`** on `k3d-manager-v1.16.0` with scope gate `git diff --stat HEAD~1 -- . ':(exclude)scripts/lib/foundation'` → EMPTY; and local trap guards for the six bare-`mktemp` sites landed as **`319762b9`**. Prior live tmp diagnosis still stands: 54 stale `/private/tmp` entries were swept on 2026-07-20 (44 `playwright-artifacts-*` + 10 `tmp.*`, all >24h; 32 within-24h kept; operator files untouched). Remaining follow-up is operational verification on future real runs/interrupts; no code blocker remains. **lib-foundation PR #37 MERGED** 2026-07-21 (`feat/v0.4.6` → `main`, merge commit `db336a6f`) — bundled `03312ae` (acg_restart wiring) + `84d5b27` (artifact sweep) + CI-fix `1c0dc51` (SC2119/2120) + Copilot-fix `330083b` (TMPDIR=/ guard + set -e-safe node exit) + issue doc `4a537c9`; cleared the feat/v0.4.5 upstream debt. **Released as lib-foundation v0.4.6** (2026-07-21): stamp commit `ae4616f` on main (`docs(changelog): stamp v0.4.6 release header`), annotated tag `v0.4.6`→`ae4616f`, GitHub release marked Latest — https://github.com/wilddog64/lib-foundation/releases/tag/v0.4.6 (v0.4.5 folded in, never separately tagged). **Follow-up PR #38 OPEN** (`feat/v0.4.7` → `main`, https://github.com/wilddog64/lib-foundation/pull/38, tip `f45c464`) — the documented out-of-scope follow-up: `acg_check_ttl` (was `acg.sh:517`) had the same pre-existing `output=$(...)`/`$?` set -e pattern; fixed to `|| exit_code=$?` matching the sibling wrappers. **PR #38 MERGED 2026-07-23 (merge commit `a36cf79` on main); released as lib-foundation v0.4.7** (stamp `21fdb9b`, tag `v0.4.7`→`21fdb9b`, GitHub release Latest — https://github.com/wilddog64/lib-foundation/releases/tag/v0.4.7). **Subtree pull DONE (owner-chosen order):** `K3DM_SUBTREE_SYNC=1 git subtree pull --prefix=scripts/lib/foundation lib-foundation v0.4.7 --squash` landed on `k3d-manager-v1.16.0` (ort, no conflicts); CLAUDE-VERIFIED vendored `scripts/lib/foundation/scripts/lib/acg/acg.sh` = IDENTICAL to `git show v0.4.7:scripts/lib/acg/acg.sh`, fix at line 516, CHANGE.md top `[v0.4.7]`. v1.16.0 now carries the full merged lib-foundation state; next = create the v1.16.0 release PR.

## Hub Grafana "ArgoCD Apps & Image Updater Hub" No-data — LIVE-FIXED 2026-07-23, durable git fix landed
Owner reported the dashboard all "No data" + a frontend login error. **Two independent hub issues, NOT the v1.16.0 release (unmerged).**
- **Grafana root cause:** hub Prometheus healthy (52 targets) but scraped **no `argocd` job** (`argocd_app_info`=0) — the argocd Helm release (rev 1, 2026-07-20) has `metrics.serviceMonitor.enabled: true` + `release: kube-prometheus-stack` label yet **zero argocd ServiceMonitors existed**; and **argocd-image-updater was never deployed** on this hub (defined at `scripts/etc/argocd/image-updater/kustomization.yaml`, deployed only by `_argocd_deploy_image_updater` argocd.sh:1138 in `deploy_argocd`'s bootstrap branch, argocd.sh:552 — not exercised here). `ghcr-pull-secret` absent in cicd.
- **LIVE FIX (owner: "do 2 and 3" = run live + spec):** (a) `kubectl apply -k scripts/etc/argocd/image-updater/` → deployment `2/2 Running`; (b) full `helm upgrade` FAILED on field-ownership conflict (argocd-cm/rbac-cm `.data.oidc.config`/`url`/`policy.csv`/`scopes` owned by kubectl-patch — do NOT force, would clobber OIDC/RBAC), so instead rendered ONLY the SMs: `helm template argocd argo/argo-cd --version 10.1.4 -f <helm get values> --api-versions monitoring.coreos.com/v1 | yq 'select(.kind=="ServiceMonitor")' | kubectl apply`. **VERIFIED:** 4 argocd SMs created, 4 targets `up=1`, `argocd_app_info` 0→**40 series**, image-updater `ready=1/desired=1`. Panels populate on refresh (rate panels need a few min history). NOT durable across a hub rebuild.
- **Durable git fix landed by Codex as `aef82f5a` on `origin/k3d-manager-v1.16.0` (2026-07-23)** from `docs/bugs/2026-07-23-hub-argocd-servicemonitors-and-image-updater-not-enrolled.md`: `scripts/plugins/argocd.sh` now adds CRD-guarded `_argocd_ensure_servicemonitors` inside `_argocd_helm_deploy_release` after the argocd `helm upgrade --install` and before `rm -f "$values_file"`, mirroring the real install version logic by using `ARGOCD_HELM_CHART_VERSION` only when set and rendering with `--api-versions monitoring.coreos.com/v1`; it also hoists `_argocd_deploy_image_updater` out of the `enable_bootstrap` block. Test coverage landed in `scripts/tests/plugins/argocd_servicemonitors_ensure.bats` and was wired into `.github/workflows/ci.yml`.
- **CLAUDE-VERIFIED `aef82f5a` = FAIL (2026-07-23) — every gate green, fix inert in production.** Gates independently re-run and confirmed: SHA on origin, exact commit message, exactly 3 files, memory-bank separate (`aa5690bd`), `shellcheck -S warning`/`-S error` on argocd.sh → RC=0/RC=0, `bats argocd_servicemonitors_ensure.bats` → 2/2 `BATS_RC=0`, `_agent_audit` → `AUDIT_RC=0`. All three Round-1 spec amendments honored; **Change 1's `_argocd_ensure_servicemonitors` body is correct and kept.** Two blockers: **(A) Change 2 is a no-op — Codex edited dead code.** `_argocd_configure_post_deploy` (argocd.sh:576) has **zero callers repo-wide** (`grep -rn` → definition only; orphaned since `aef115a0`/`e013d23b`). Live path is `deploy_argocd` → `_argocd_helm_deploy_release` → wait → `_argocd_ensure_logged_in` → `deploy_argocd_bootstrap`, and `deploy_argocd_bootstrap` deploys ONLY AppProject + ApplicationSets — image-updater still never deployed. *This also corrects Round 1's own diagnosis: the spec said "the bootstrap branch was not exercised on this hub"; the truth is the containing function is dead, which is why image-updater was never deployed anywhere.* **(B) CRD guard aborts instead of skipping** — `_kubectl get crd …` lacks `--no-exit`, so `_run_command` → `_run_command_handle_failure` (soft=0) → `_err` → **`exit 1`**; on a cluster without the SM CRD `deploy_argocd` dies rather than no-op'ing (spec required a no-op). Siblings at argocd.sh:417/:421/:443 all use `--no-exit`. The bats stub replaces `_kubectl` with a plain `return 1` function so `_run_command` is never reached — and both tests assert the argv WITHOUT `--no-exit`, so they lock the bug in and would fail once fixed.
- **ROUND 2 spec written + pushed: `d908ffd0`** — appended to the same `docs/bugs/` file (dedup). Exact old/new blocks for: A1 revert the dead-code hoist, A2 call `_argocd_deploy_image_updater` from `deploy_argocd_bootstrap` (which has its own `CLUSTER_ROLE=app` guard), B add `--no-exit`, B2 update both stub matchers + both assertions, B3 add a static call-site regression test using `awk '/^function deploy_argocd_bootstrap\(\)/,/^}$/'`. Scope gate: exactly 2 files (argocd.sh + the bats file — ci.yml already wired, do not touch). Post-state gate `grep -c '_argocd_deploy_image_updater' scripts/plugins/argocd.sh` → **3**. Commit msg: `fix(argocd): call image-updater from live bootstrap path + no-exit CRD guard`. Unassigned (ready to hand off).
- **ROUND 2 landed by Codex as `9ec7469b` on `origin/k3d-manager-v1.16.0` (2026-07-23)** exactly per the appended Round 2 section: A1 restored the dead-code hunk inside `_argocd_configure_post_deploy` verbatim; A2 added the real live-path call to `_argocd_deploy_image_updater` inside `deploy_argocd_bootstrap` after the two ArgoCD precondition checks and before the AppProject block; B added `--no-exit` to the ServiceMonitor CRD guard in `_argocd_ensure_servicemonitors` without rewriting the rest of that function; B2 updated both stub matchers and both assertions in `scripts/tests/plugins/argocd_servicemonitors_ensure.bats`; B3 added the static `awk` regression test that `deploy_argocd_bootstrap` contains `_argocd_deploy_image_updater`. Scope held to exactly two files (`scripts/plugins/argocd.sh`, `scripts/tests/plugins/argocd_servicemonitors_ensure.bats`); `grep -c '_argocd_deploy_image_updater' scripts/plugins/argocd.sh` now returns **3**. Static gates recorded by Codex: `shellcheck -S warning` RC=0, `shellcheck -S error` RC=0, `bats scripts/tests/plugins/argocd_servicemonitors_ensure.bats` → 3/3 `RC=0`, `_agent_audit` `RC=0`. **Claude still owes the next live hub rebuild/deploy verify** that image-updater and the 4 argocd ServiceMonitors now come up from git without the manual remediation.
- **Argocd dead-path cleanup follow-up is DONE in `db26dd61` on `origin/k3d-manager-v1.17.0` (2026-07-23)** exactly per `docs/bugs/2026-07-23-argocd-post-deploy-removal-followup.md`: scope held to exactly one file `scripts/plugins/argocd.sh`, removing only the orphaned `local enable_vault=1` in `deploy_argocd()` and restoring the single blank line between `_argocd_configure_vault_eso` and `_argocd_seed_vault_admin_secret()`. This closes the loose ends left by `ac729e14`: `grep -c 'enable_vault' scripts/plugins/argocd.sh` → `0`, `shellcheck -S warning scripts/plugins/argocd.sh` → zero warnings, `bash -n scripts/plugins/argocd.sh` clean, `bats scripts/tests/plugins/argocd_servicemonitors_ensure.bats` → `1..3` / `ok 1` / `ok 2` / `ok 3`, and `./scripts/k3d-manager _agent_audit` printed `running under bash version 5.3.15(1)-release`; both `git diff --cached --stat` and commit `git show --stat db26dd61` showed exactly one file changed. PR URL not created per repo rule. The newly-orphaned cascade remains OUT OF SCOPE and still needs its own owner decision if removal is ever desired.
- **Claude still owes a FRESH-REBUILD live hub verify** (after Round 2). **Current live end-state 2026-07-23 already passes** (`k3d-k3d-cluster`: 4 argocd SMs, image-updater 1/1, 40 apps, `applications=0` intended) — but that's ~11h-old state, not a from-git rebuild.
- **v1.17.0 specs filed 2026-07-23 (`46524697`, both `docs/bugs/`):** make-status login verification is **DONE** in `843e643a` on `origin/k3d-manager-v1.17.0` (`fix(webhook): verify real logins in smoke test, not just health pages`) with scope held to exactly one file `bin/k3dm-webhook`: added `_smoke_test_logins` directly above `_smoke_test_services` and appended `results.extend(_smoke_test_logins(provider, app_context))` before `return results`; `python3 -m py_compile bin/k3dm-webhook` passed, the explicit no-creds runtime check returned all four new login entries as `ok=None` / ⚪ (`Keycloak login`, `Frontend login`, `ArgoCD login`, `Grafana login`), `make restart-webhook` succeeded, and `./scripts/k3d-manager _agent_audit` passed. Remaining open decision stays exactly as the spec recorded: wire real `K3DM_SMOKE_*` credentials into the webhook runtime environment separately. PR URL not created per repo rule. Ambient cilium `ssh_cmd` string→array (Copilot PR #106 carry-forward) is **DONE** in `05d74f6c` on `origin/k3d-manager-v1.17.0` exactly per `docs/bugs/2026-07-23-ambient-cilium-ssh-cmd-string-to-array.md` (clarified in `84747f3c`: 1 declaration + 3 invocation sites, not "4 invocations"): scope held to exactly one file `scripts/plugins/shopping_cart.sh`, changing `ssh_cmd` to `local -a` plus the array literal and rewriting the 3 invocation sites in `_ambient_install_cilium` to `"${ssh_cmd[@]}"` without changing flags, hostnames, Helm `--set` values, retry logic, or the existing `SC2029` disable. Gates recorded on this machine: `grep -c '\${ssh_cmd}' scripts/plugins/shopping_cart.sh` → `0`; `shellcheck -S warning scripts/plugins/shopping_cart.sh` → zero warnings; `bash -n scripts/plugins/shopping_cart.sh` clean; `./scripts/k3d-manager _agent_audit` printed `running under bash version 5.3.15(1)-release`; `git diff --cached --stat` and commit `git show --stat 05d74f6c` each showed exactly one file changed. PR URL not created per repo rule. CLAUDE-VERIFIED = PASS. **Smoke-login credential auto-discovery is DONE in `cdeebfa6` on `origin/k3d-manager-v1.17.0` (2026-07-24)** exactly per `docs/bugs/2026-07-23-smoke-login-credential-autodiscovery.md` (spec commit `ce3eb1f0`): scope held to exactly one file `bin/k3dm-webhook`, adding `_smoke_secret` directly above `_smoke_test_logins` and wiring ArgoCD + Grafana to fall back to in-cluster admin Secrets when `K3DM_SMOKE_*` env vars are unset (`cicd/argocd-initial-admin-secret` on the hub with no `--context`; `monitoring/acg-kube-prometheus-stack-grafana` on the app cluster with `context=app_context`). Keycloak + Frontend remain intentionally untouched and env-driven because the realm end-user password is not discoverable from Secrets. Gates recorded on this machine: `python3 -m py_compile bin/k3dm-webhook` passed; `grep -c '_smoke_secret' bin/k3dm-webhook` → `4`; `make restart-webhook` succeeded; `./scripts/k3d-manager _agent_audit` printed `running under bash version 5.3.15(1)-release`; `git diff --cached --stat` and commit `git show --stat cdeebfa6` each showed exactly one file changed. PR URL not created per repo rule.
- **Spec 5 (Keycloak/Frontend login) is DONE in `647b4181` on `origin/k3d-manager-v1.17.0` (2026-07-24)** exactly per the revised `docs/bugs/2026-07-23-smoke-login-keycloak-smoke-user-seed.md` at spec commit `2bf83d0b`. The live blocker remains the same: the app-owned `frontend` client has `directAccessGrantsEnabled=false`, so password grant can never succeed against it. The landed fix follows owner-chosen Path 1: `scripts/plugins/keycloak.sh` now adds the five smoke defaults plus six functions above `test_keycloak` (five `_keycloak_smoke_*` helpers, then public `keycloak_seed_smoke_user`) so k3d-manager seeds its own `k3dm-smoke` DAG-enabled public client + local user and stores the credential in `identity/k3dm-smoke-user`; `bin/k3dm-webhook` now falls back to that Secret for the Keycloak login check and sets `kc_via_smoke_client`, while **Frontend login intentionally stays ⚪** when that smoke-client token is used because it is not scoped for the frontend `/api/cart` audience. Gates recorded on this machine: `shellcheck -S warning scripts/plugins/keycloak.sh` → zero warnings; `python3 -m py_compile bin/k3dm-webhook` passed; `grep -c 'kc_via_smoke_client' bin/k3dm-webhook` → `3`; `./scripts/k3d-manager _agent_audit` printed `running under bash version 5.3.15(1)-release`; `make restart-webhook` succeeded; `git show --stat 647b4181` shows exactly 2 files changed. PR URL not created per repo rule. Known limitation remains: app-owned realm reconcile could wipe `k3dm-smoke`; re-run `keycloak_seed_smoke_user` to restore.
- **CLAUDE-VERIFIED `647b4181` (2026-07-24)** — independently reconfirmed on `origin/k3d-manager-v1.17.0`: `git show --stat` = exactly 2 files; per-function if-counts `1/1/2/2/1/0/7` (all ≤8, matches the decomposed spec); `scripts/etc/agent/if-count-allowlist` untouched; `grep -c 'kc_via_smoke_client'` → 3; shellcheck & py_compile clean. The diff carries **seven** function declarations (six `_keycloak_smoke_*` helpers + entrypoint) — that is the authoritative spec code block; the "five helpers" phrasing in prose was a mislabel, the code is correct. Codex's memory-bank commit `9175ede3` is scope-clean (memory-bank only, separate commit).
- **GitGuardian incident 35144224 = FALSE POSITIVE, ignored in `a5306106`** — the generic-password detector flags the `--from-file=password="$wd/pword"` temp-file PATH in `_keycloak_smoke_write_secret` as a secret value; it is a `mktemp` path, i.e. the secret-safe pattern the spec mandated. Added SHA `d34d2aa6…` to `.gitguardian.yaml` (5th ignore); re-scan → `0 secrets detected, 2 secrets ignored`, exit 0. **STILL PENDING (user task):** resolve incident 35144224 on the GitGuardian dashboard as false-positive. **STILL PENDING (live):** run `keycloak_seed_smoke_user` on the hub, `make restart-webhook`, confirm Keycloak login ⚪→✅ while Frontend stays ⚪.
- **GitGuardian 35144224 dashboard-resolved 2026-07-24** — resolved via the API IGNORE endpoint (`POST /v1/incidents/secrets/35144224/ignore` `{"ignore_reason":"false_positive"}`, status → IGNORED). Dashboard side now closed; nothing owed on the web UI for this incident.
- **LIVE SMOKE RUN COMPLETE (2026-07-24) — Keycloak login ⚪→✅, Frontend stays ⚪, exactly as designed.** Ran `keycloak_seed_smoke_user` (RC=0, created `k3dm-smoke` client + user + Secret `identity/k3dm-smoke-user`), then the authenticated webhook health smoke (`GET localhost:7443/api/v1/health?provider=k3d` with the Keychain `k3dm-webhook-token`) reported `Keycloak login: token minted (realm=shopping-cart)` = ✅ and `Frontend login: skipped (smoke-client token not scoped for frontend audience)` = ⚪. (Unrelated pre-existing FAILs in the same smoke: Pushgateway, ESO ClusterSecretStore/ExternalSecrets timeouts, Data-layer postgres — not spec-5.)
- **BUT the green depended on a manual patch → NEW BUG in the spec-5 seed code.** Fresh seed left the user with an incomplete Keycloak-24+ declarative **User Profile** (`email`/`firstName`/`lastName` are required by default), so the first direct-grant token mint returned **HTTP 400 `invalid_grant` "Account is not fully set up"**. Root cause live-confirmed: `PUT /users/{uuid}` with `{email, firstName, lastName, emailVerified:true}` flipped the same mint to **HTTP 200 + access_token**. `_keycloak_smoke_ensure_user` creates the user with only `{username, enabled:true}`, so a clean cluster reproduces the failure. Durable fix specced for Codex: **`docs/bugs/2026-07-23-smoke-login-keycloak-user-profile-attributes.md`** (branch `k3d-manager-v1.17.0`, single file `scripts/plugins/keycloak.sh`, exact old/new block; edited-function if-count = 4 ≤ 8; commit `fix(keycloak): set required User Profile attrs on smoke user so direct-grant login succeeds`). NOT yet handed to Codex.
- **Spec amended `a0121c94`** after reviewing Codex's plan — three traps that would have produced a wrong implementation: (a) **chart version decoy** — `ARGOCD_CHART_VERSION` (argocd.sh:53, `7.8.1`) is annotation-only (used at :1317); the install actually uses `ARGOCD_HELM_CHART_VERSION` (:465-467) which is **unset by default**, so the release floats — that's why live is chart `10.1.4`. Render must mirror the install (`--version` only if that var is set), or SMs render from the wrong chart version. (b) **call site** — `values_file` is `local` to `_argocd_helm_deploy_release` and `rm -f`'d at :559-561, so the ensure step must be called from *inside* that function before cleanup, NOT from `deploy_argocd`. (c) **no new role guard** — `deploy_argocd` already returns early for `CLUSTER_ROLE=app` at :408; Change 2 is purely hoisting the `_argocd_deploy_image_updater` call out of the `if (( enable_bootstrap ))` block at :550.
- **Frontend login:** single `LOGIN_ERROR clientId=null error=invalid_code` (1 in 300 log lines) = stale auth session, NOT a config regression. Told owner to retry incognito; if it recurs → Keycloak proxy/cookie spec. (Old `keycloak-realm-reconcile` jobs Error exit=1 on a 2-day-old `duplicate key uk_orvsdmla...` realm partial-import conflict — unrelated to today's login.)

## Hostinger (REBUILT 2026-07-21 — Path B executed; ambient control plane GREEN, app-tier enrollment pending 2 Codex specs)

**REBUILD RESULT (2026-07-21, owner chose Path B = clean rebuild):** executed `make down` → `make up` →
`vault_deploy_hub_into_context` → `make refresh` → `deploy_istio_ambient` on `k3s-hostinger`.
- **`make down`** — k3s-uninstall ran; verified ON THE BOX: `k3s` binary gone, **`/var/lib/cni/networks/cbr0` gone** (the
  213-IP flannel leak is physically eliminated), deregistered from hub, context removed, VPS preserved.
  ⚠️ my `DOWN_RC=${PIPESTATUS[0]}` capture came back EMPTY (var didn't survive the pipeline) — outcome was
  verified by direct SSH inspection instead. Do not trust that capture idiom through `| tee`.
- **`make up`** `UP_RC=0` — fresh k3s **v1.36.2+k3s1**, node Ready, `cluster-ubuntu-hostinger` secret recreated on hub.
  Expected warn: app-cluster Vault auth failed (`vault-root missing`) — fresh cluster has no Vault yet.
- **ORDERING GAP:** first `make refresh` **FAILED `RC=2`** at Vault seeding — `could not read target vault-root token …
  run vault_deploy_hub_into_context first`. `deploy_cluster` for hostinger is BARE (ssh→k3sup→kubeconfig→node-ready→
  label→register only); it does NOT deploy Vault, and `refresh` assumes Vault already exists. Fix sequence is
  down → up → **`vault_deploy_hub_into_context ubuntu-hostinger`** (RC=0) → refresh (`RC=0` on 2nd run).
- **Data tier fully restored 7/7** (minio, postgres orders/payment/products, rabbitmq, redis-cart, redis-orders-cache).
  data-layer app had failed sync (`namespaces "shopping-cart-payment" not found`, retry limit 5 exhausted); recovered by
  forcing sync via `kubectl patch application … --type merge -p '{"operation":{...,"sync":{...}}}'` (the `refresh=hard`
  annotation alone does NOT re-trigger a sync past an exhausted retry budget).
- **VAULT WAS NEVER AT RISK (verified before destroying):** hostinger's Vault is a DOWNSTREAM replica. Canonical source =
  **hub Vault** (unsealed, alive) with **macOS Keychain** fallback (`k3d-manager-app-cluster-secrets`; confirmed present for
  `postgres/orders`, `keycloak/admin`, `github/pat`, `payment/stripe`). The in-cluster `vault-seed-backup` secret is a
  write-only DR **output** of seeding, never an input. `make backup` does NOT support hostinger (k3s-oci only).

**AMBIENT STATUS — control plane GREEN, dataplane NOT yet carrying app traffic:**
- `istio-cni-node 1/1`, `istiod 1/1`, `ztunnel 1/1` (stable ~50m); ztunnel receiving `istio.workload.Address` XDS from istiod.
- **istio-cni required the RANCHER CNI paths** — this REVERSES the stale note below. On fresh k3s+flannel:
  `/etc/cni/net.d` is EMPTY, the only conflist is `/var/lib/rancher/k3s/agent/etc/cni/net.d/10-flannel.conflist`,
  `/opt/cni/bin` holds only istio's own binary, and real CNI bins live in `/var/lib/rancher/k3s/data/cni`.
  istio-cni went `1/1` within ~2min after overriding to `cniConfDir=/var/lib/rancher/k3s/agent/etc/cni/net.d` +
  `cniBinDir=/var/lib/rancher/k3s/data/cni`. **This override is LIVE-ONLY on the hub appset — the next
  `deploy_istio_ambient` reverts it.** `ce4d83f0`'s standard paths are correct for Cilium, wrong for bare flannel →
  the appset needed to be substrate-aware. **Codex Session 1 landed as `9c0e336a` on
  `origin/k3d-manager-v1.16.0` (2026-07-22)**: `scripts/etc/argocd/applicationsets/istio-ambient.yaml` now
  parameterizes `cniConfDir`/`cniBinDir`, and `scripts/plugins/istio_ambient.sh` defaults/export/envsubst them while
  preserving the Cilium defaults (`/etc/cni/net.d`, `/opt/cni/bin`) byte-for-byte when unset. **Claude still must
  live re-run `deploy_istio_ambient` against hostinger with the rancher paths exported to verify `istio-cni-node`
  stays `1/1` from git.**
- **`9c0e336a` VERIFIED PASS on all 8 DoD boxes (Claude, 2026-07-22)** — SHA on `origin/k3d-manager-v1.16.0`; scope
  exactly the 2 target files (9+/4-); commit message verbatim; memory-bank a separate commit (`87cb4eba`); all FOUR
  spec changes applied incl. Change 4 (stale Cilium help precondition); only one `envsubst` call exists in the file
  and both vars are in it; `shellcheck -S warning` 0; `yaml.safe_load_all` 0; `ce4d83f0` defaults intact. Byte-identical
  render proven by full-file `diff` of the `9c0e336a^` render vs the new render (md5 `bedeb363…` both sides), not a
  `grep -A2` spot check.
- **REGRESSION FOUND OUTSIDE THE SPEC'S 2-FILE SCOPE (Claude's spec-scoping miss, not Codex's).**
  `_argocd_deploy_applicationsets` (`scripts/plugins/argocd.sh:1206-1220`) derives its `envsubst` allowlist by grepping
  `${VAR}` out of each appset file and **refuses to apply** any file with an unset var (`_err` + `continue`, then still
  `return 0`). `AMBIENT_CNI_CONF_DIR`/`AMBIENT_CNI_BIN_DIR` are defaulted ONLY in `istio_ambient.sh`, which that path
  never loads → `deploy_argocd_bootstrap` now **silently drops `istio-ambient.yaml`** and reports success.
  `scripts/etc/argocd/vars.sh:70-72` already documents this exact trap for the sibling `AMBIENT_ISTIO_VERSION`
  ("Must be defaulted here, not only in istio_ambient.sh"). Fix spec filed: **`be422467`** →
  `docs/bugs/2026-07-21-ambient-cni-vars-missing-from-argocd-vars.md` (one file, `scripts/etc/argocd/vars.sh`).
  Claude dry-ran the fix locally before filing: post-fix refusal gate prints nothing, `shellcheck`/`bash -n` 0, env
  override still beats the default — then reverted so Codex does the edit (spec-before-implement). **Codex landed the
  real fix as `a08911b3` on `origin/k3d-manager-v1.16.0` (2026-07-22)**: `scripts/etc/argocd/vars.sh` now defaults and
  exports both `AMBIENT_CNI_*` vars with the same Cilium defaults as `istio_ambient.sh`, so the bootstrap refusal gate
  no longer prints `UNSET:` lines for the ambient appset. **CLAUDE-VERIFIED LIVE PASS 2026-07-22:**
  `deploy_argocd_bootstrap --confirm` (hub `k3d-k3d-cluster`, rancher paths exported) → `APPLY_RC=0`,
  `Successfully deployed 10/10 ApplicationSet(s)`, zero `Refusing` lines. Applied appset on the hub renders
  `cniConfDir: /var/lib/rancher/k3s/agent/etc/cni/net.d` / `cniBinDir: /var/lib/rancher/k3s/data/cni` with
  `grep -c '${'` → **0** literal placeholders, and the generated `istio-cni-ubuntu-hostinger` Application inherits
  them. The rancher paths are now DURABLE FROM GIT — before this they were a live-only hub override that the next
  bootstrap would have clobbered back to the Cilium defaults.
- **⚠️ MY SPEC UNDERSTATED THIS BUG — the failure is an ABORT, not a silent drop.** Negative control run in a
  throwaway worktree at pre-fix `7226e7ea` with both vars unset: `PREFIX_RC=1` and the loop **terminated** at
  `istio-ambient.yaml`, so the FIVE appsets ordered after it (`eso`, `demo-rollout`, `services-git`,
  `grafana-dashboards-acg`, `observability-acg`) were never applied at all. The spec's Problem section claimed
  `_argocd_deploy_applicationsets` `continue`s past the bad file and still `return 0`s — it does not. Blast radius
  was mid-bootstrap collateral across unrelated appsets, including `services-git`, which is what carries the
  shopping-cart manifests. Correct the Problem text if that spec is ever reused as a template.
- **PRE-EXISTING, NOT A REGRESSION — separate spec needed.** `scripts/lib/providers/k3s-oci.sh:678-683` globs every
  appset through `envsubst '$ARGOCD_NAMESPACE'`, a one-var allowlist against a file with FIVE placeholders, so
  `${APP_CLUSTER_NAME}` and `${AMBIENT_ISTIO_VERSION}` were ALREADY reaching OCI's ArgoCD literally before `9c0e336a`
  (now 5 leaked vars). `k3s-hostinger.sh:791-794` uses an explicit 3-appset list excluding istio-ambient — unaffected.
- **APP TIER IS STILL SIDECAR-ENROLLED — the real CPU story.** `services/shopping-cart-namespace/namespace.yaml:10` sets
  `istio-injection: enabled`, so istiod injects a 100m `istio-proxy` into every pod → node hit **1860m (93%) requests**
  and pods went `Pending` on `Insufficient cpu` while **actual usage was only 408m (20%)**. The historical
  "hostinger is CPU-starved" reading was a SYMPTOM OF SIDECAR INJECTION, not real capacity pressure.
  Spec `docs/bugs/2026-07-21-shopping-cart-ns-sidecar-blocks-ambient.md`. **Codex landed that manifest fix as
  `ebf27de3` on `origin/k3d-manager-v1.16.0` (2026-07-22)**: `services/shopping-cart-namespace/namespace.yaml` now
  removes `istio-injection` entirely and declares `istio.io/dataplane-mode: ambient`, leaving the sync-wave annotation
  and both `app.kubernetes.io/*` labels untouched. **CLAUDE-VERIFIED LIVE PASS 2026-07-22 — AMBIENT DATAPLANE IS
  CARRYING APP TRAFFIC ON HOSTINGER.** ArgoCD had already synced `ebf27de3`; live ns shows
  `istio.io/dataplane-mode=ambient` with no `istio-injection` key. Deleted all pods in `shopping-cart-apps` (ArgoCD-
  neutral — no Application/appset edit, so nothing to revert); every replacement came back **`1/1`, zero
  `istio-proxy` containers**. ztunnel config_dump: all 3 running `shopping-cart-apps` workloads report
  `protocol: HBONE`, while `shopping-cart-data` and `shopping-cart-payment` still report `TCP` — the exact
  in-scope/out-of-scope split the spec defined, and a clean enrollment discriminator for future checks.
  **HBONE + mutual SPIFFE proof captured** on `frontend → basket-service:8083`:
  `src.identity="spiffe://cluster.local/ns/shopping-cart-apps/sa/default"` →
  `dst.identity="spiffe://cluster.local/ns/shopping-cart-apps/sa/basket-service"`,
  `dst.addr=10.42.0.97:15008 dst.hbone_addr=10.42.0.97:8083`, logged from BOTH `direction="outbound"` and
  `direction="inbound"` — same bar `k3s-aws` met.
- **⚠️ MY SPEC'S CPU CLAIM WAS WRONG — sidecar injection was NOT the cause of hostinger's CPU pressure.** The spec
  asserted the "hostinger is CPU-starved" reading was a SYMPTOM OF SIDECAR INJECTION and that removing injection
  would reclaim ~100m/pod and let the `Pending` pods schedule. Measured reality after every sidecar was gone:
  requests went **1910m (95%) → 1960m (98%) of 2000m allocatable — UP, not down** — and `order-service`
  (2nd ReplicaSet) + `product-catalog` are STILL `Pending` on `Insufficient cpu`. Only `frontend` (50m) converted
  Pending → Running. Actual usage stayed ~19%. The node is genuinely oversubscribed at the REQUESTS layer by
  non-app workloads: `trivy-server-0` 200m, `payment-service` 200m, `rabbitmq-0` 200m, 4× data-tier pods 400m,
  istio control plane 300m (istiod+ztunnel+istio-cni), monitoring ~110m. Requests went up because freed capacity
  was immediately consumed by a pod that previously could not schedule. **The 2-CPU hostinger box is a real
  capacity constraint, not a mesh artifact** — do not carry the "sidecars caused it" story forward. Right-sizing
  requests (or dropping trivy-server from this node) is a separate piece of work needing its own spec.
- **LIVE REMEDIATION IS IMPOSSIBLE HERE — the ApplicationSet controller wins.** Removing the ns label was reverted in ~15s;
  setting `selfHeal:false` was reverted; removing `automated` entirely was ALSO reverted, because the `services-git`
  ApplicationSet regenerates the Application `.spec` from its template. Only the git manifest is durable.
- **`istio-ambient` is a SINGLE appset** whose generator is keyed to one `${APP_CLUSTER_NAME}` — applying it for
  hostinger re-pointed it off `ubuntu-k3s`. Only one cluster can hold ambient at a time (design limit worth fixing).
  (No collateral damage this time: `ubuntu-k3s` apps show `Unknown` because the ACG sandbox has EXPIRED/unreachable.)
- **`make status` is BLIND to all of this** — `bin/cluster-status` (435 lines) has zero istio/cilium/ztunnel/ambient
  checks, which is why the mesh sat broken ~3 days unnoticed. Spec
  `docs/bugs/2026-07-21-cluster-status-no-mesh-cni-health.md` (filed under docs/bugs, NOT docs/plans — v1.16.0 already
  holds 4 plan docs and the limit is 5 on an unshipped release).

**HANDOFF STATE (2026-07-22):** branch `k3d-manager-v1.16.0` PUSHED to origin — prior specs commit `fd3be7f7`, then
Session 1 code commit **`9c0e336a`** (`fix(mesh): make ambient istio-cni conf/bin dirs CNI-substrate aware`) verified,
followed by the 2-file Session 2 code commits **`a08911b3`** (`fix(argocd): default ambient CNI dir vars in
argocd/vars.sh for the bootstrap path`) and **`ebf27de3`** (`fix(mesh): enroll shopping-cart namespace in ambient
instead of sidecar injection`), all confirmed on `origin/k3d-manager-v1.16.0`. The sequence is now:
(a) CNI-substrate-aware appset **DONE + CLAUDE-VERIFIED PASS** → (d) bootstrap ambient-CNI defaults in `vars.sh`
**DONE** → (b) namespace ambient label **DONE** → (c) `cluster-status` mesh section **DONE in `da67e2bf`**
(`feat(status): report service mesh, CNI substrate, and ambient enrollment`; PR URL not created per repo rule). (a) had to land before (b) became verifiable, since the app tier could not
enter the ambient dataplane while istio-cni was broken on a fresh deploy. **Spec gates tightened in `a242ec67`** after
review of Codex's plan: (c) no longer asks Codex to run `make status` live (Codex has NO live-cluster verify role —
static gates + `bash -n` only; Claude runs the live check); all sessions require push proof via
`git log origin/k3d-manager-v1.16.0 --oneline -1` and an explicit **separate** memory-bank commit.

**LIVE VERIFY DONE 2026-07-22 — (a)+(d)+(b) ALL CLAUDE-VERIFIED PASS, git AND live.** The ambient milestone's
functional goal is MET on hostinger: bootstrap applies 10/10 appsets from git with substrate-correct CNI paths,
the app namespace is ambient-enrolled, all app pods run sidecar-free `1/1`, and `frontend → basket-service`
traffic rides HBONE on :15008 with mutual SPIFFE identities both directions. Nothing on the git side is
outstanding for (a)/(d)/(b).

**SESSION RESULT (2026-07-22):** spec (c) `docs/bugs/2026-07-21-cluster-status-no-mesh-cni-health.md` is
**DONE in `da67e2bf` on `origin/k3d-manager-v1.16.0`**. Scope held to exactly one file, `bin/cluster-status`,
with one insertion after line 163; no `_kubectl` conversion; no live-cluster run. Static gates PASS:
`shellcheck -S warning bin/cluster-status` exit 0 with zero output, `bash -n bin/cluster-status` exit 0, and the
required 4-mode stub-`kubectl` harness passed all modes with `RC=0`, including `MODE=flaky` printing
`ambient ns:       <none>`. `git show --stat da67e2bf` lists exactly one file (`bin/cluster-status`, +45), and
push proof is `git log origin/k3d-manager-v1.16.0 --oneline -3` showing `da67e2bf` at the tip. PR URL not created
per repo rule.

**CLAUDE-VERIFIED PASS (2026-07-22) — spec (c) closed, nothing outstanding.** Every gate re-run independently
rather than trusting Codex's paste. Git side: both `da67e2bf` and memory-bank commit `66683150` confirmed on
`origin/k3d-manager-v1.16.0`; `git show --stat da67e2bf` = exactly one file, `bin/cluster-status`, +45/−0;
commit message byte-exact; `git status` clean with **0** untracked files, so the harness was never committed and
`scripts/tests/` was never touched. Content side: the landed block was `diff`ed against the spec's `Exact new
block to insert` and is **byte-identical** (the only delta is the required trailing blank separator); placement
confirmed `fi`(163) → blank → block(165–209) → blank → `echo ""` → Hub ArgoCD header, i.e. no existing section
reordered. Static gates on this machine: `shellcheck -S warning bin/cluster-status` `SC_RC=0` / `SC_LINES=0`
(baseline was also 0, so zero new warnings is exact, not approximate); `bash -n` `BN_RC=0`. Harness re-run by
Claude against the LANDED file, all four modes `RC=0` and matching the spec's required-results table.
**Negative control re-proved the gate bites:** stripping `|| true` from all six substitutions flips `MODE=flaky`
to `RC=1` with output truncating after the `istiod:` line — the `ambient ns:` line never prints. **Live verify
`make status CLUSTER_PROVIDER=k3s-hostinger` → `STATUS_RC=0`** (RC captured on its own line, not through `tee`),
printing `CNI substrate: flannel (no cilium daemonset)`, `istio-cni-node: 1/1 ready`, `ztunnel: 1/1 ready`,
`istiod: 1/1 ready`, `ambient ns: shopping-cart-apps`, and `grep -c CONFLICT` → **0**, which is the expected
result post-`ebf27de3`, not a coverage gap. Unrelated pre-existing finding surfaced by the same run:
`Product images: HTTP Error 502` in Service Health — not caused by this change, needs its own spec.

**Three corrections Claude made to spec (c) before handoff (revision commit below):**
1. **The spec's own code block was `set -e`-unsafe** — it omitted `|| true` on all six command substitutions
   while `bin/cluster-status:14` runs `set -euo pipefail` at top level, so one unreachable `kubectl` would have
   killed the WHOLE status tool. That directly contradicted the spec's own "What NOT to Do" bullet. Block now
   matches the App Observability convention (`2>/dev/null || true`, lines 136–154).
2. **CONFLICT branch is unreachable live** — `ebf27de3` removed `istio-injection`, so hostinger correctly prints
   no CONFLICT line. Added a REQUIRED stub-`kubectl` harness (4 modes: `normal`/`conflict`/`nomesh`/`flaky`) as
   the only proof of that branch. **Claude built and ran the harness first** — all 4 modes RC=0 — and confirmed
   via negative control that stripping `|| true` makes `flaky` exit **RC=1** with truncated output. The gate
   bites; it is not a rubber stamp.
3. **Retracted the CPU causation** from the spec's Problem section so the wrong story is not propagated.

Also pinned the insert anchor to exact line numbers (after 163, before the `echo ""` on 165) and forbade
`_kubectl` conversion — the file deliberately uses bare `kubectl --context` at all 5 existing call sites, and
switching would break the harness.

**OPEN AFTER THIS MILESTONE (each needs its own spec, none blocking (c)):**
1. ~~`k3s-oci.sh:678-683` one-var `envsubst` allowlist leaking 5 placeholders~~ — **DE-SCOPED 2026-07-22
   (owner): OCI is crossed out — the Always-Free A1 capacity never yields an instance, so the k3s-oci
   provider path is dead. Do NOT spend session time on OCI bugs. Focus is ACG/hostinger only.** The
   envsubst leak is real but unreachable; leave it filed, do not fix.
2. Hostinger 2-CPU requests oversubscription → product-catalog 502. **CLAUDE LIVE VERIFY 2026-07-22
   FOUND THE FIX TARGETED THE WRONG FILE.** `7345b24a` (spec `…-hostinger-trivy-cpu-oversubscription-502.md`)
   is correct-to-spec and passes all gates, but the GitOps file→cluster mapping is the INVERSE of what that
   spec assumed: `trivy-operator-values.yaml` → appset `observability.yaml` → **hub laptop**
   (`https://kubernetes.default.svc`, not CPU-starved); `trivy-operator-acg-values.yaml` → appset
   `observability-acg.yaml` → **`${APP_CLUSTER_NAME}` = ubuntu-hostinger** (the starved node). The `acg-`
   prefix is a misnomer — that appset is the app-cluster observability path and runs on hostinger. So
   `7345b24a` trimmed the hub server; hostinger `trivy-server-0` is still `200m` (chart default, verified
   live) and node is still `1960m/2000m` with `product-catalog` (100m) Pending 21h (`Insufficient cpu` ×254).
   Owner: KEEP `7345b24a` (harmless hub hygiene) AND add the identical `trivy.server.resources` block to the
   ACG file. **CODE FIX LANDED 2026-07-23 in `45381c7d` on `origin/k3d-manager-v1.16.0`:**
   `docs/bugs/2026-07-22-hostinger-trivy-acg-values-cpu-oversubscription-502.md` was implemented exactly in
   `scripts/etc/helm/observability/trivy-operator-acg-values.yaml` only; the nested
   `trivy.server.resources` block now sets requests `cpu: 50m` / `memory: 256Mi` and preserves chart-default
   limits `cpu: "1"` / `memory: 1Gi`. Static gates recorded by Codex: YAML validity
   `python3 -c "import yaml; yaml.safe_load(open('scripts/etc/helm/observability/trivy-operator-acg-values.yaml'))" && echo OK`
   → `OK`; helm render of the `trivy-server` StatefulSet request CPU → `50m`; `grep -c '^trivy:' …acg-values.yaml`
   → `1`. `git show --stat 45381c7d` = exactly one file (`trivy-operator-acg-values.yaml`, +8). The
   `acg-trivy-operator` values source tracks `targetRevision: k3d-manager-v1.16.0`, so ArgoCD auto-synced
   this to hostinger with no merge-to-main and no manual patch. **CLAUDE-VERIFIED LIVE PASS 2026-07-22:**
   ArgoCD `acg-trivy-operator` Synced/Healthy; hostinger `trivy-system/trivy-server-0` request now `50m`
   (was `200m`); node `srv1754834` CPU requests `1960m/2000m (98%)` → `1910m (95%)`; **0 Pending pods** — all
   four `shopping-cart-apps` pods `1/1 Running` incl. `product-catalog` and BOTH former stray dups
   (`frontend-8bbdc8599`, `order-service-75c5b998b7`), so the reconcile happened naturally. **502 CLEARED:**
   live `https://frontend.3ai-talk.org/` → `HTTP 200` and `…/api/products` → `HTTP 200` (both were the
   symptom). ⚠️ **The `make status` "Frontend 502 / Product images 502" I first saw was STALE** — captured
   before the sync scheduled product-catalog; live probes are 200. Caught it by probing live, nearly
   mis-reported a stale symptom. **RESIDUAL = APP BUG, ALREADY TRACKED (not k3d-manager, not 502, not CPU):**
   `/api/products` returned `{"items":[],"total":0}` — catalog serves `200 OK` end-to-end but the DB had
   **0 seeded products**. This is `wilddog64/shopping-cart-product-catalog` **Issue #34** ("PostSync seed hook
   never runs against a fresh volume") — a one-shot ArgoCD `PostSync` hook (`k8s/base/seed-job.yaml`,
   `hook-delete-policy: HookSucceeded` + `ttl 300`) that doesn't re-fire against a fresh/empty Postgres PVC;
   app reads Healthy because the deleted hook Job isn't a managed resource. **CLAUDE LIVE 2026-07-22:** newer
   failed sync than the issue body (`operationState.phase=Failed 2026-07-22T01:41:03Z`); ran the
   kustomize-built seed Job one-off → `1000 inserted, 0 skipped` (seed.py + idempotency guard PROVEN healthy,
   defect is purely the hook not re-firing); **re-seeded live → `/api/products` total=1000 with images, so the
   "Product images" check passes again.** Diagnostic Jobs cleaned up, no non-GitOps artifacts left. Posted the
   confirmation to Issue #34 (comment `5053261290`). Durable fix (options 1 startup-seed / 2 resilient-Job /
   3 health-surfacing) is an OWNER DECISION before any product-catalog PR — do NOT write a k3d-manager spec
   for this; app fix goes in that repo per bug-tracking-ownership. NOTE: my selfHeal-disable probe on
   `acg-trivy-operator` was a no-op (appset owns the Application spec and reverted it) — cluster left untouched.
3. `_hostinger_reapply_gitops_applicationsets` hostinger ambient reapply gap is **CLOSED in `470ef7d8` on
   `origin/k3d-manager-v1.16.0` (2026-07-22)** — `scripts/lib/providers/k3s-hostinger.sh` now appends
   `istio-ambient.yaml` to the reapply list, widens the `envsubst` allowlist with
   `AMBIENT_ISTIO_VERSION`/`AMBIENT_CNI_CONF_DIR`/`AMBIENT_CNI_BIN_DIR`, and updates the summary log line.
   Static gates PASS on this machine: `shellcheck -S warning` exit 0 with zero output, `bash -n` exit 0,
   render gate prints `data-git residual=0`, `services-git residual=0`, `platform-helm residual=0`,
   `istio-ambient residual=0`, and `grep -c 'export AMBIENT_' scripts/lib/providers/k3s-hostinger.sh` prints
   `0`. `git show --stat 470ef7d8` lists exactly one file. **CLAUDE-VERIFIED LIVE PASS (2026-07-22):**
   `make refresh CLUSTER_PROVIDER=k3s-hostinger` → RC=0; log line now reads "reapplied data-git, services-git,
   platform-helm, and istio-ambient ApplicationSets for ubuntu-hostinger"; hub `k3d-k3d-cluster` ns `cicd`
   carries the `istio-ambient` ApplicationSet; generated `istio-cni-ubuntu-hostinger` renders concrete rancher
   paths (`cniConfDir /var/lib/rancher/k3s/agent/etc/cni/net.d`, `cniBinDir /var/lib/rancher/k3s/data/cni`,
   istio `1.24.2`) with **0** literal `${AMBIENT_` placeholders in both istio-cni + ztunnel apps. Ambient
   dataplane live (istiod+ztunnel 22h Healthy; cni-agent actively enrolling `shopping-cart-apps` pods into
   ztunnel). **This closes the last ambient-milestone durability hole.** CAVEAT (NOT a spec-(e) regression):
   `istio-cni-ubuntu-hostinger` stays `OutOfSync/Progressing` because its cni-node `/readyz` returns 503 and
   won't flip Ready — root cause is node CPU at **98% requests (1960m/2000m)** (`Insufficient cpu` FailedScheduling),
   i.e. item 2 below. Mesh is functional (cni-agent enrolling, restarts=0, no error logs); only the readiness
   *report* lags under CPU starvation. Belongs to the v1.17.0 capacity work, not spec (e).
4. `istio-ambient` single-appset design limit — keyed to one `${APP_CLUSTER_NAME}`, so only one cluster can hold
   ambient at a time. Low priority now that OCI is de-scoped (hostinger is the only ambient host).

**PRE-REBUILD diagnosis (2026-07-21, superseded above — kept for the retracted-hypothesis trail):**
- **PRIMARY WALL = flannel pod-IP exhaustion.** `/var/lib/cni/networks/cbr0/` holds **253/254 allocated IPs but only 40 pods run** — ~213 LEAKED host-local IPAM reservations from 2d20h of orphaned-app churn. `10.42.0.0/24` full → every new pod (istiod, ztunnel, postgresql-orders-0, monitoring admission) stuck `ContainerCreating` with `flannel failed (add): no IP addresses available`. istiod's *separate* CPU-Pending (500m won't fit 290m free) is secondary — even at 100m it can't get an IP.
- **istio-cni IS HEALTHY (1/1 Running on flannel, 2d20h)** — the old "istio-cni binary missing" note is STALE/WRONG. No Cilium needed; ambient runs on flannel here. istio-cni conf/bin dirs `/etc/cni/net.d`+`/opt/cni/bin` (post-`ce4d83f0`) work on this k3s v1.36.
- **GitOps owner is broken both ways:** laptop hub (`k3d-k3d-cluster`, rebuilt 24h ago by k3s-aws e2e `make down/up`) has hostinger **UNREGISTERED** (no `cluster-ubuntu-hostinger` secret, no apps); the spoke's OWN ArgoCD (9 `argocd-ubuntu-hostinger-*` pods in `cicd`) has **ZERO applications**. Nothing reconciles hostinger. COUPLING: every k3s-aws e2e cycle rebuilds the laptop hub → de-registers hostinger → orphans its mesh.
- ESO/Vault HEALTHY (vault-0 23d, all ExternalSecrets synced 15m). `shopping-cart-apps` ns EMPTY (app tier never got IPs). `payment-service` stuck Terminating (no finalizers — wedged sandbox teardown). Data tier = `local-path` demo PVCs (reseedable, not authoritative).
- **CODE GAP (Codex spec pending):** `_hostinger_reapply_gitops_applicationsets` reapplies data/services/platform but NOT `istio-ambient.yaml`, so `refresh` never reconciles ambient after a hub rebuild. `1af15217` (istiod→100m/ztunnel→100m) lives inline in the appset (istio-ambient.yaml:26-28,42-44); delivered ONLY via `deploy_istio_ambient` (plugins/istio_ambient.sh), which was last applied pre-fix → live istiod still 500m.
- **Two repair paths (decision pending):** (A) surgical in-place — SSH-flush the flannel IPAM leak (stop k3s → rm /var/lib/cni/networks/cbr0/* + del cni0/flannel.1 → start k3s), force-delete wedged pods, register w/ hub, `deploy_istio_ambient` (100m), verify HBONE/mTLS, redeploy app tier (preserves data); vs (B) clean rebuild — `make down/up CLUSTER_PROVIDER=k3s-hostinger` (wipes local-path demo data, clears leak+orphan ArgoCD), then `deploy_istio_ambient` + verify. Both converge on the same ambient dataplane verify; rebuild does NOT auto-install ambient (provider is bare flannel k3sup — appset applied after either way).
- LESSON (still valid): `preserveResourcesOnDeletion` does NOT protect resources whose Applications predate the flag — the first appset rename still cascade-deletes; strip `resources-finalizer` first.

## CVE-scan (hub) — owner decisions pending
- `app-cve-scan` (`babb3c80`/`89c2efd6`) now runs exit-0, but **skips all services**: MAIN loop matches `ghcr.io/wilddog64/...` vs trivy-operator's prefix-less `.report.artifact.repository` → spec `docs/bugs/2026-07-18-app-cve-scan-report-repository-registry-prefix-mismatch.md` (unassigned).
- **Hub `environment=infra` registration — DO NOT EXECUTE.** `platform-helm` selfHeal would auto-deploy a 2nd argo-cd release + downgrade 9.5.15→7.8.1. Blocker doc `docs/bugs/2026-07-18-hub-infra-registration-blocked-platform-helm-selfheal.md`, options A–D, owner decision required. Also: hub `argocd` Helm release status `failed` (rev 3, 2026-06-29) needs triage before any Helm-touching option.

## Facts worth keeping (cost several wrong turns each)
- **ArgoCD installs into `cicd`, NOT `argocd`** — checking for an `argocd` namespace produces a false "it's gone".
- Frontend `shopping-cart` realm has exactly `admin`/`developer`/`operator` (LDAP-federated, `ou=users,dc=shopping-cart,dc=local`); **`alice` does not exist**; passwords generated per-run into Vault (`secret/keycloak/users/<user>`, `bin/cluster-up:957`) — doc values are stale.
- `payment` deploys into its OWN `shopping-cart-payment` namespace (not `shopping-cart-apps`). Always confirm a service's real target namespace before concluding it produced nothing.
- ACG sandbox creds expire ~4h independent of cluster age; `make up` auto-restarts the sandbox on ghost-state failure. Makefile ACG URL default was stale (`cloud-playground` → `hands-on/playground`) — spec `docs/bugs/2026-07-19-makefile-stale-acg-sandbox-url-default.md` (unassigned).
