# v1.26.0 — live acceptance of the last two queue items (E2E gate + stale-cluster cleanup)

**Date:** 2026-08-21
**Branch:** `k3d-manager-v1.26.0`
**Context:** Hub `k3d-k3d-cluster` (healthy, 26h), fresh ACG sandbox `604492140645`
(1 server + 2 agents, provisioned + destroyed during this run).

Closes the two remaining `[ ]` items in the v1.26.0 queue — both were **code-done +
BATS-green, live-acceptance pending**. This run performed the live acceptance.

---

## Item 1 — E2E promotion-gate integration + durable success/failure artifacts — ✅ GREEN

Ran `e2e_verify_vcluster` live on the hub (throwaway vCluster + in-cluster Playwright
Job). The Playwright suite itself **failed** (`exit_code 1`, phase `running-playwright`) —
but that is the *app/test suite*, not the harness. The harness contract is that a run
(pass **or** fail) produces a durable artifact and lights the promotion-gate signal, and
that is exactly what happened:

- **Durable artifact:** `~/.k3dm/e2e/1787338912-32712.json` —
  `{"result":"fail","exit_code":1,"phase":"running-playwright","tier":"vcluster",
  "service":"product-catalog","commit":"35e9ecf2…"}`. The failure was captured faithfully,
  not lost.
- **Result event:** ConfigMap `e2e-result-r2fl9` in `platform-ops`
  (`k3dm.k3d.io/e2e-result=true`), `event.json` with `passed:"false"`, `commit:35e9ecf2…`.
- **Promotion-gate metrics** (scraped from `vulnerability-inventory-exporter:8080/metrics`):
  - `e2e_run_info{run_id="1787338912-32712",commit="35e9ecf2…",passed="false"} 1`
  - `e2e_last_run_pass{tier="vcluster",service="product-catalog",project="api+flows"} 0`
    → red on the E2E dashboard row and fires `E2EVerificationFailing` (`== 0`).
  - `e2e_last_run_timestamp_seconds{…} 1787340294.8…`

Full chain proven live: **run → durable artifact → result-event ConfigMap → exporter →
Prometheus `e2e_*` gauges → dashboard/alert.**

### Finding 1a (minor, non-blocking) — empty-valued duration metric
When `duration_seconds` is null (the Job crashed before emitting parseable results), the
exporter emits `e2e_last_run_duration_seconds{…}` **with no value** — an invalid Prometheus
exposition line. It should default to `0`. Fix: in
`scripts/etc/argocd/platform-ops/vulnerability-inventory-exporter.yaml` (embedded
`exporter.py`), coerce empty `duration_seconds` → `0` before emitting. Cosmetic; the other
four `e2e_*` series are correct.

---

## Item 2 — stale managed-registration cleanup without mutating unrelated Applications

Faithful reproduction of the original bug scenario (an expired sandbox leaving a
`ubuntu-k3s` registration + generated Applications behind):

1. Provisioned k3s on the sandbox; bootstrapped `argocd-manager` SA; minted a token.
2. `register_app_cluster` **managed** (`provider=k3s-aws`, `sandbox-id=acg-604492140645`,
   `expires-at` 1h in the past, `release=k3d-manager-v1.26.0`) → hub secret
   `cluster-ubuntu-k3s`; it auto-set `k3d-manager/role=app-cluster`, so the ApplicationSets
   generated **10 Applications** (data-layer, eso, grafana-dashboards, platform, and 6
   shopping-cart apps) — matching the plan's "ten generated Applications."
3. **Baseline:** 33 apps = 10 `ubuntu-k3s` + **23 survivors**; 2 registrations
   (`cluster-ubuntu-hostinger` managed=false; `cluster-ubuntu-k3s` managed=true).
4. Deleted the CFN stack directly (simulating **TTL reclaim with no graceful deregister**)
   → all EC2 gone → `kubectl --context ubuntu-k3s get --raw=/readyz` fails (exit 124).

### Semantics + safety — ✅ VERIFIED
- **Dry-run #1** (fresh first-failure): `keep cluster-ubuntu-k3s: API failure grace period
  (0s/1800s)` — the 30-min continuous-failure safety fired.
- **Dry-run #2** (`K3DM_CLEANUP_NOW` advanced past grace, first-failure genuine on disk):
  `expired cluster-ubuntu-k3s … DRY_RUN: would delete managed Applications … and Secret`.
  `cluster-ubuntu-hostinger` (managed=false) was **never evaluated** — filtered by the
  `k3d-manager/managed=true` selector.
- **Post-cleanup:** 23 apps remaining = **exact match** to the 23 baseline survivors
  (nothing extra, nothing missing); `cluster-ubuntu-hostinger` intact; hostinger apps
  unharmed. → *"unknown/out-of-sync handling without mutating unrelated live Applications"*
  is proven.

### Finding 2a (BLOCKING) — `cleanup-stale-clusters --confirm` deletion hangs
The eligibility/selection/safety logic is correct, but the **deletion mechanism** hangs on
ApplicationSet-generated apps against an unreachable cluster. `bin/cleanup-stale-clusters`
(lines ~124-136):
1. Deletes the generated Applications **first**, then the cluster Secret **last**. Because
   the Secret still exists, the ApplicationSets **regenerate** every app as fast as it is
   deleted.
2. Uses a **blocking** `kubectl delete application` (default `--wait=true`). ArgoCD re-adds
   the `resources-finalizer.argocd.argoproj.io` on apps whose target cluster is gone and
   can never complete the cascade delete → `kubectl delete` blocks indefinitely.

Result: `--confirm` printed `expired cluster-ubuntu-k3s …` then hung; 0 apps deleted after
minutes. Manually deleting the **Secret first** made the ApplicationSets prune all 10 apps
cleanly (`grep -c '^ubuntu-k3s' → 0`) — which is the correct order.

**Fix direction** (`bin/cleanup-stale-clusters`): on `--confirm`, delete the **cluster
Secret first** to stop ApplicationSet generation, then reconcile any lingering generated
Applications with a **finalizer-null patch + `kubectl delete --wait=false`** (never a
blocking delete against a dead cluster). Keep the audit record. BATS can't catch this
(kubectl is mocked, so neither the finalizer reattach nor appset regeneration occurs) —
add a note that the ordering + `--wait=false` are load-bearing, and assert the Secret
delete is issued before the Application deletes.

**RESOLVED (2026-08-21).** `bin/cleanup-stale-clusters` now deletes the cluster **Secret
first** (stops ApplicationSet generation + lets ArgoCD fast-path finalizer removal), then
force-removes any lingering generated Applications with a finalizer-null patch +
`kubectl delete --wait=false` (never a blocking delete against a dead cluster). BATS
`cleanup_stale_clusters.bats` strengthened to assert the Secret delete precedes the
Application deletes and that Application deletes carry `--wait=false` (2/2 green; shellcheck
clean). **Live re-verify (hub-only, synthetic unreachable `127.0.0.1:16443` managed
registration + 10 appset-generated apps):** the previously-hanging `--confirm` now
completes in **3s** (`rc=0`, "removed cluster-ubuntu-k3s and its managed Applications");
0 orphan apps remain, the 23 unrelated survivors are an exact match, and only the hostinger
registration remains.

### Finding 2b (medium) — dispatcher strips `--confirm` from `deploy_app_cluster`
`scripts/k3d-manager deploy_app_cluster --confirm` fails with
`deploy_app_cluster requires --confirm`. The dispatcher's `deploy_*` safety guard
(`__k3dm_deploy_guard_args`) **consumes** `--confirm` (sets an internal flag, strips it
from the args), but `deploy_app_cluster` still checks for `--confirm` as its own `$1`, so
the flag never reaches it. Today the only working path is a **lib-sourcing wrapper**
(as the e2e-sandbox spec notes). Fix direction: either have the guard export a
`K3DM_DEPLOY_CONFIRMED` env the function honours, or drop `deploy_app_cluster`'s redundant
own-`--confirm` gate (the guard already gates it) — mind the blast radius across every
`deploy_*` function before changing the shared guard.

---

## What verification confirmed WORKS
- Full E2E artifact → result-event → exporter → `e2e_*` metric chain (item 1).
- Managed-registration eligibility: `managed=true` + `k3s-aws` + `expires-at` past +
  API-unreachable + 30-min grace; `retain`/`managed=false`/wrong-provider all skipped.
- Cleanup removes **only** the target cluster's registration + generated Applications;
  the 23 unrelated apps and the hostinger registration are untouched.
- Teardown left the hub identical to baseline (23 apps, 1 registration, no EC2, no CFN,
  no `ubuntu-k3s` context).
