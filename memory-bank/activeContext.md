# Active Context — k3d-manager

## Status
v1.14.0 RELEASED 2026-07-12 · v1.15.0 RELEASED 2026-07-14 · **v1.16.0 active branch — Istio ambient mesh**.

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
1. **Ambient k3s-aws cold-rebuild blocker is CLOSED, `acg_restart` is wired, and tmp-hygiene code fixes are now landed (2026-07-20).** `ce4d83f0` (istio-cni CNI paths), `bca7d59a` (default `K3S_AMBIENT_MESH=true` on k3s-aws), `5be42ae4` (pin k3sup version), and **`520621a9` (replace both `(( var++ ))` wait-loop post-increments with assignment form so `set -e` no longer aborts the first SSM/node-ready iteration)** are all on `k3d-manager-v1.16.0`, and the former manual-sandbox-restart regression is fixed end-to-end: upstream lib-foundation commit **`03312ae`** on `origin/feat/v0.4.5` adds `_acg_restart_playwright` + `acg_restart`, the subtree pull landed as **`78af86e8`**, and the local dispatcher stub landed as **`4332431f`**. Claude already proved the orphaned `acg_restart.js` recovered a dead sandbox with zero manual clicks, and the cold rebuild plus ambient dataplane verify are complete (`DOWN_RC=0`, `UP_RC=0`, Cilium/istio green, HBONE+mTLS capture PASS). **TMP-HYGIENE follow-through is now code-complete too:** upstream lib-foundation commit **`84d5b27`** on `origin/feat/v0.4.6` adds `_acg_sweep_stale_artifacts` plus the two wrapper call sites; the subtree pull landed as **`381cdf03`** on `k3d-manager-v1.16.0` with scope gate `git diff --stat HEAD~1 -- . ':(exclude)scripts/lib/foundation'` → EMPTY; and local trap guards for the six bare-`mktemp` sites landed as **`319762b9`**. Prior live tmp diagnosis still stands: 54 stale `/private/tmp` entries were swept on 2026-07-20 (44 `playwright-artifacts-*` + 10 `tmp.*`, all >24h; 32 within-24h kept; operator files untouched). Remaining follow-up is operational verification on future real runs/interrupts; no code blocker remains. **lib-foundation PR #37 MERGED** 2026-07-21 (`feat/v0.4.6` → `main`, merge commit `db336a6f`) — bundled `03312ae` (acg_restart wiring) + `84d5b27` (artifact sweep) + CI-fix `1c0dc51` (SC2119/2120) + Copilot-fix `330083b` (TMPDIR=/ guard + set -e-safe node exit) + issue doc `4a537c9`; cleared the feat/v0.4.5 upstream debt. **Released as lib-foundation v0.4.6** (2026-07-21): stamp commit `ae4616f` on main (`docs(changelog): stamp v0.4.6 release header`), annotated tag `v0.4.6`→`ae4616f`, GitHub release marked Latest — https://github.com/wilddog64/lib-foundation/releases/tag/v0.4.6 (v0.4.5 folded in, never separately tagged). **Follow-up PR #38 OPEN** (`feat/v0.4.7` → `main`, https://github.com/wilddog64/lib-foundation/pull/38, tip `f45c464`) — the documented out-of-scope follow-up: `acg_check_ttl` (was `acg.sh:517`) had the same pre-existing `output=$(...)`/`$?` set -e pattern; fixed to `|| exit_code=$?` matching the sibling wrappers. All 3 CI checks green (shellcheck/bats/acg-node), `mergeStateStatus=CLEAN`, Copilot review clean (0 inline findings, 0 threads), main unprotected so no enforce_admins gate — awaiting owner merge, do NOT auto-merge. **Pending after #38 merges (owner-chosen order = fix-upstream-first-then-one-pull):** single `git subtree pull` into k3d-manager carrying the whole merged lib-foundation acg.sh state (03312ae + 84d5b27 + 1c0dc51 + 330083b + f45c464) so `scripts/lib/foundation/scripts/lib/acg/acg.sh` matches lib-foundation main — vendored copy currently reflects `84d5b276` only.

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
  the appset needs to be substrate-aware, spec `docs/bugs/2026-07-21-istio-ambient-cni-dirs-not-substrate-aware.md`.
- **APP TIER IS STILL SIDECAR-ENROLLED — the real CPU story.** `services/shopping-cart-namespace/namespace.yaml:10` sets
  `istio-injection: enabled`, so istiod injects a 100m `istio-proxy` into every pod → node hit **1860m (93%) requests**
  and pods went `Pending` on `Insufficient cpu` while **actual usage was only 408m (20%)**. The historical
  "hostinger is CPU-starved" reading was a SYMPTOM OF SIDECAR INJECTION, not real capacity pressure.
  Spec `docs/bugs/2026-07-21-shopping-cart-ns-sidecar-blocks-ambient.md`.
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

**HANDOFF STATE (2026-07-21):** branch `k3d-manager-v1.16.0` PUSHED to origin — tip `35cf743d`, specs commit
`fd3be7f7`; all three spec files verified present via `git ls-tree origin/k3d-manager-v1.16.0 docs/bugs/`. The 3 specs
are handed to Codex, **one SEPARATE session each**, in order: (a) CNI-substrate-aware appset → (b) namespace ambient
label → (c) `cluster-status` mesh section. (a) must land before (b) is verifiable, since the app tier cannot enter the
ambient dataplane while istio-cni is broken on a fresh deploy. **Spec gates tightened in `a242ec67`** after review of
Codex's plan: (c) no longer asks Codex to run `make status` live (Codex has NO live-cluster verify role — static gates
+ `bash -n` only; Claude runs the live check); all three now require push proof via
`git log origin/k3d-manager-v1.16.0 --oneline -1` and an explicit **separate** memory-bank commit. Claude must NOT edit
memory-bank while a Codex session is in flight — same lines, guaranteed conflict.

**NEXT after Codex lands (a)+(b):** Claude re-runs `deploy_istio_ambient` with the rancher paths exported, restarts the
app deployments, and captures the ambient dataplane proof (HBONE `dst.hbone_addr=…:80` on :15008 + mutual SPIFFE mTLS
both ends) — same bar `k3s-aws` met. Claude runs all live verification; Codex is never given a live-cluster verify.

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
