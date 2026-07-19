# Active Context — k3d-manager

## Status
v1.14.0 RELEASED 2026-07-12 · v1.15.0 RELEASED 2026-07-14 · **v1.16.0 active branch — Istio ambient mesh**.

> Verbose per-item narrative (full gate dumps, live-verify logs, retracted-diagnosis trails) archived 2026-07-19 → `memory-bank/archive/activeContext-v1.16.0-detail-thru-2026-07-19.md`. Earlier windows: `activeContext-v1.8.0-v1.15.0.md`, `-v1.6.x-v1.7.1.md`, `-v1.4.2-v1.4.8.md`.

## Standing constraints (IN EFFECT)
- **k3s-aws is the ONLY target until it is green — hostinger stays parked** (user, 2026-07-19).
- **Spec before implement** — Claude does NOT edit plugin/config/app code directly; write a `docs/bugs/` spec for Codex (exception: `gcp.sh` exact-match). Memory-bank editing IS Claude's own job (mandatory + immediate after every completed action, both files).
- **Verify before trust** — never trust a SHA/BATS/"done"; confirm on `origin/<branch>` via `gh`/`git log`. Code commit = spec files only; memory-bank in a SEPARATE commit.
- **False-pass trap:** always capture the exit code of the command under test on its OWN line (never after `; echo`). For `make up`/`down`, read `UP_EXIT=`/`DOWN_EXIT=` in the log — the wrapper block always exits 0.
- Branch always `k3d-manager-v<version>`; never commit to `main`; no `--no-verify`; route privileged cmds through `_run_command`. Never blind-close warm CDP tabs (cold nav → Cloudflare challenge). Never create a hub `environment=infra` cluster Secret without the owner decision (below). Vault reads are user-only via `! ./bin/vault-exec …`.

## Current live cluster state (2026-07-19)
Fresh hub `k3d-cluster` on **v1.32.0+k3s1** (pin `1cc55252` verified live); ArgoCD in `cicd` + all 10 appsets deployed. `ubuntu-k3s` spoke: 3 nodes Ready, `ubuntu-k3s-data-layer` **Synced/Healthy**, all 7 data-layer pods Running (minio, postgresql-orders/payment/products, rabbitmq, redis-cart, redis-orders-cache), app tier lands on ubuntu-k3s.
- ⚠️ The data-layer sync is healthy via an **EPHEMERAL live AppProject patch** (added 4 `secrets` destinations). Permanent fix is specced + handed to Codex — until that SHA lands and is verified, a fresh rebuild re-introduces the blocker.

## OPEN blockers
1. **`shopping-cart` AppProject missing `secrets` destination** — SPEC HANDED TO CODEX (2026-07-19). `docs/bugs/2026-07-19-shopping-cart-appproject-secrets-destination.md`, single file `scripts/etc/argocd/projects/shopping-cart.yaml.tmpl`, add 4 `secrets` destinations mirroring `platform.yaml.tmpl:16-23`. Commit `fix(argocd): permit secrets namespace in shopping-cart AppProject for vault-bridge`. Gates: yq clean · `grep -c 'namespace: secrets'`→4 · `grep -c 'namespace: shopping-cart-'`→12 · bats 15/15 · `_agent_audit` 0 · one file. Live-proved by Claude already; k3s-aws-only (does NOT touch parked Hostinger). **Awaiting Codex SHA → Claude verify on origin.**
2. **istio-ambient dest validation** — `no clusters with this name: ubuntu-hostinger (and 3 more)` blocks the pod-level istiod/ztunnel verify of `1af15217`. **NOT yet specced.**

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
