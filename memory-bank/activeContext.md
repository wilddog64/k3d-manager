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
1. **Ambient k3s-aws cold-rebuild blocker is CLOSED; `acg_restart` shell wiring is now landed everywhere it needs to be (2026-07-20).** `ce4d83f0` (istio-cni CNI paths), `bca7d59a` (default `K3S_AMBIENT_MESH=true` on k3s-aws), `5be42ae4` (pin k3sup version), and **`520621a9` (replace both `(( var++ ))` wait-loop post-increments with assignment form so `set -e` no longer aborts the first SSM/node-ready iteration)** are all on `k3d-manager-v1.16.0`, and the former manual-sandbox-restart regression is now fixed end-to-end: upstream lib-foundation commit **`03312ae`** on `origin/feat/v0.4.5` adds `_acg_restart_playwright` + `acg_restart` and repoints the expired-creds guidance at the automation, the subtree pull landed as **`78af86e8`** on `k3d-manager-v1.16.0`, and the local dispatcher stub landed as **`4332431f`**. Prior live evidence still stands: Claude already proved the orphaned `acg_restart.js` recovered a dead sandbox with zero manual clicks, and the cold rebuild plus ambient dataplane verify are complete (`DOWN_RC=0`, `UP_RC=0`, Cilium/istio green, HBONE+mTLS capture PASS). Remaining ACG follow-up is operational verification on the next real expiry via `./scripts/k3d-manager acg_restart`; no code blocker remains. PR URL: not created per repo rule.

## Hostinger (PARKED — do not investigate without go)
App tier DOWN. Root cause = **CPU-request over-subscription on the 2-CPU node `srv1754834`** (requests 1710m/85%, istiod needs 500m, actual usage only 16%); istiod Pending 13h → sidecar-injector webhook dead → no injected pod can recreate. Second breakage: `istio-cni` plugin binary missing from the node. `1af15217` already right-sized istiod→100m/ztunnel→100m in-repo but is untested live (blocker 2). LESSON: `preserveResourcesOnDeletion` does NOT protect resources whose Applications predate the flag — the first appset rename still cascade-deletes; strip `resources-finalizer` first.

## CVE-scan (hub) — owner decisions pending
- `app-cve-scan` (`babb3c80`/`89c2efd6`) now runs exit-0, but **skips all services**: MAIN loop matches `ghcr.io/wilddog64/...` vs trivy-operator's prefix-less `.report.artifact.repository` → spec `docs/bugs/2026-07-18-app-cve-scan-report-repository-registry-prefix-mismatch.md` (unassigned).
- **Hub `environment=infra` registration — DO NOT EXECUTE.** `platform-helm` selfHeal would auto-deploy a 2nd argo-cd release + downgrade 9.5.15→7.8.1. Blocker doc `docs/bugs/2026-07-18-hub-infra-registration-blocked-platform-helm-selfheal.md`, options A–D, owner decision required. Also: hub `argocd` Helm release status `failed` (rev 3, 2026-06-29) needs triage before any Helm-touching option.

## Facts worth keeping (cost several wrong turns each)
- **ArgoCD installs into `cicd`, NOT `argocd`** — checking for an `argocd` namespace produces a false "it's gone".
- Frontend `shopping-cart` realm has exactly `admin`/`developer`/`operator` (LDAP-federated, `ou=users,dc=shopping-cart,dc=local`); **`alice` does not exist**; passwords generated per-run into Vault (`secret/keycloak/users/<user>`, `bin/cluster-up:957`) — doc values are stale.
- `payment` deploys into its OWN `shopping-cart-payment` namespace (not `shopping-cart-apps`). Always confirm a service's real target namespace before concluding it produced nothing.
- ACG sandbox creds expire ~4h independent of cluster age; `make up` auto-restarts the sandbox on ghost-state failure. Makefile ACG URL default was stale (`cloud-playground` → `hands-on/playground`) — spec `docs/bugs/2026-07-19-makefile-stale-acg-sandbox-url-default.md` (unassigned).
