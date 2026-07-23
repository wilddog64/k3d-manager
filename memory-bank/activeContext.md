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
   ACG file. **SPEC WRITTEN + ASSIGNED TO CODEX (2026-07-22):**
   `docs/bugs/2026-07-22-hostinger-trivy-acg-values-cpu-oversubscription-502.md` on `k3d-manager-v1.16.0` —
   commit msg `fix(observability): trim acg trivy-server CPU request to relieve hostinger node`. Render gate
   PROVEN by Claude on the ACG file (`helm template … -f …acg-values.yaml | yq … .requests.cpu` → `200m`
   before / `50m` after, anchor unique). The `acg-trivy-operator` values source tracks
   `targetRevision: k3d-manager-v1.16.0`, so once Codex pushes, ArgoCD auto-syncs to hostinger — no
   merge-to-main, no manual patch. Then Claude live-verifies product-catalog schedules + 502 clears and
   reconciles the 2 stray Pending rollout dups (`frontend-8bbdc8599`, `order-service-75c5b998b7`) from the
   earlier `make refresh`. NOTE: my selfHeal-disable probe on `acg-trivy-operator` was a no-op (appset owns
   the Application spec and reverted it) — cluster left untouched.
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
