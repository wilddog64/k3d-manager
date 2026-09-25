# Bug: a hub rebuild silently drops the hostinger app-cluster registration, and nothing reports the gap

**Filed:** 2026-09-23
**Branch:** `k3d-manager-v1.37.0`
**Status:** OPEN — spec only, assigned to Codex.
**Predecessor:** `docs/bugs/2026-09-13-hostinger-app-cluster-registration-lost-orphaned-workloads.md`
(fixed `14f26f3d`, **RECURRED 2026-09-23**). That doc restored the registration and gave us a
safe way to restore it again. This one makes the restore automatic and the gap visible.

---

## Problem

Two hub rebuilds have now dropped `cicd/cluster-ubuntu-hostinger`, on 2026-09-11 and again on
2026-09-20. Each time the rebuild recreated **only** the hub's own in-cluster registration
(`cicd/ubuntu-k3s-app-cluster`), every `ubuntu-hostinger-*` Application disappeared, and the
workloads still running on `ubuntu-hostinger` were left unmanaged. The second time it also broke
the CVE Auto-Patch dashboard, because `cve-remediation-verify` reads that Secret by name and
failed 15 consecutive times.

Both rebuild paths register exactly one cluster and know nothing about any other:

| Path | Line | Registers |
|---|---|---|
| `bin/cluster-up` (the rebuild — bare `make up`) | `bin/cluster-up:759` | `register_app_cluster` for the ACG/in-cluster app cluster only |
| `hub_recovery_reconcile` | `scripts/plugins/hub_recovery.sh:252` | `ubuntu-k3s-app-cluster` only, hardcoded inline |

Nothing enumerates the app clusters the hub is supposed to have, so nothing can notice one is
missing. **This is the actual defect** — the lost Secret is a symptom.

### Why it stayed silent

`bin/cluster-status:233-239` does check a registration, but only for the *current* provider's
context:

```bash
if kubectl get secret "cluster-${APP_CONTEXT}" -n "${ARGOCD_NAMESPACE}" ...
```

On the hub-as-app-cluster topology `APP_CONTEXT` is `ubuntu-k3s`, whose Secret is present, so
`make status` printed `Registered:` while hostinger was orphaned. The one check that could have
caught this was structurally incapable of seeing it.

### What is NOT broken

The restore path exists and is safe. `14f26f3d` added
`_provider_k3s_hostinger_refresh_registration` (`scripts/lib/providers/k3s-hostinger.sh:1033`),
reachable as `refresh_registration` (`scripts/lib/core.sh:571`) and
`make refresh-registration CLUSTER_PROVIDER=k3s-hostinger` (`Makefile:144`). It is additive-only,
refuses `K3DM_EXCLUSIVE_APP_CLUSTER=true`, touches no GitOps ApplicationSet and no edge, and has
three passing tests at `scripts/tests/lib/provider_contract.bats:456-513`.

This spec does not re-implement any of that. It calls it.

## Fix

Give the hub a declared list of the app clusters it should have, reconcile that list on every
rebuild, and report any gap in `make status`.

Design constraints, all load-bearing:

- **Additive only.** `K3DM_EXCLUSIVE_APP_CLUSTER=true` would strip `k3d-manager/role=app-cluster`
  from `ubuntu-k3s-app-cluster`, and `services-git`/`data-git` would then delete every hub
  `ubuntu-k3s-*` Application — taking down the shopping cart the public edge serves.
- **Never abort the rebuild.** If the VPS is unreachable, a rebuild must still finish. A failed
  re-registration is a loud warning, not a non-zero exit.
- **Loud, not just logged.** The rebuild prints thousands of lines; a `_warn` buried in it is how
  this bug hid twice. The gap must also surface in `make status`, which the operator reads.
- **The inventory lives in exactly one file.** Duplicating the cluster/secret names is what the
  `cluster-ubuntu-hostinger` string already did in five places. Do not add a sixth.

### Before You Start

- `git pull origin k3d-manager-v1.37.0`; read `memory-bank/activeContext.md` and
  `memory-bank/progress.md`.
- Read the predecessor bug doc named above, in full — especially its "Live Result (2026-09-13)"
  section, which records that `_hostinger_register_cluster` also configures the Vault app-cluster
  auth mount. That is intended and idempotent.
- Read `scripts/lib/providers/k3s-hostinger.sh:1033-1043` (`_provider_k3s_hostinger_refresh_registration`).
- Read `scripts/etc/cloudflared/origins.tsv` — the TSV-with-comment-header format S1 mirrors.
- Read `bin/cluster-up:750-775` (the registration + controller-restart block).
- Read `scripts/plugins/hub_recovery.sh:234-259` (`hub_recovery_reconcile`, including the `steps`
  array).
- Read `bin/cluster-status:36-46` (its sourcing block) and `:232-239` (the registration check).
- Read `scripts/tests/plugins/hub_recovery.bats:133-149` (the dry-run step-count test).

### S1 — the inventory (new file `scripts/etc/argocd/app-clusters.tsv`)

Tab-separated, one row per **remotely registered** app cluster. The hub's own in-cluster
registration is deliberately absent: the rebuild already creates it, and it must never be
re-registered through a provider action.

```
# context	secret	provider
ubuntu-hostinger	cluster-ubuntu-hostinger	k3s-hostinger
```

The header line is a comment and must be skipped by every reader. Blank lines are skipped.

### S2 — the reconcile function (`scripts/plugins/argocd.sh`)

Append both functions at the end of the file.

```bash
function _argocd_app_cluster_inventory() {
   local _table="${ARGOCD_APP_CLUSTER_TABLE:-${SCRIPT_DIR}/etc/argocd/app-clusters.tsv}"
   if [[ ! -r "${_table}" ]]; then
      _err "[argocd] app-cluster inventory not readable: ${_table}"
      return 1
   fi
   grep -v '^[[:space:]]*#' "${_table}" | grep -v '^[[:space:]]*$'
}

function argocd_reconcile_app_cluster_registrations() {
   if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
      cat <<'HELP'
Usage: argocd_reconcile_app_cluster_registrations

Re-register any app cluster listed in scripts/etc/argocd/app-clusters.tsv that has a local
kubeconfig context but no cluster Secret on the hub. Additive only; never aborts the caller.
A cluster with no kubeconfig context is skipped, not an error.
HELP
      return 0
   fi
   if [[ "${K3DM_EXCLUSIVE_APP_CLUSTER:-false}" == "true" ]]; then
      _err "[argocd] app-cluster reconcile is additive-only; K3DM_EXCLUSIVE_APP_CLUSTER=true would strip the app-cluster role from other registrations"
      return 1
   fi
   local _ns="${ARGOCD_NAMESPACE:-cicd}"
   local _dispatcher="${K3DM_DISPATCHER:-${SCRIPT_DIR}/k3d-manager}"
   local -a _hub_kubectl=()
   read -r -a _hub_kubectl <<< "$(_argocd_hub_kubectl_cmd)"
   local _rows _context _secret _provider _restored=0 _gaps=0
   _rows="$(_argocd_app_cluster_inventory)" || return 1
   while IFS=$'\t' read -r _context _secret _provider; do
      [[ -z "${_context}" ]] && continue
      if ! kubectl config get-contexts "${_context}" >/dev/null 2>&1; then
         _info "[argocd] ${_context}: no kubeconfig context on this host — skipping"
         continue
      fi
      if "${_hub_kubectl[@]}" get secret "${_secret}" -n "${_ns}" >/dev/null 2>&1; then
         _info "[argocd] ${_context}: already registered (${_ns}/${_secret})"
         continue
      fi
      _warn "[argocd] ${_context}: hub registration ${_ns}/${_secret} is MISSING — re-registering additively"
      if CLUSTER_PROVIDER="${_provider}" K3DM_EXCLUSIVE_APP_CLUSTER=false \
            "${_dispatcher}" refresh_registration; then
         _restored=$(( _restored + 1 ))
         _info "[argocd] ${_context}: re-registered"
      else
         _gaps=$(( _gaps + 1 ))
         _warn "[argocd] ${_context}: re-registration FAILED"
      fi
   done <<< "${_rows}"
   _info "[argocd] app-cluster reconcile: ${_restored} restored, ${_gaps} still missing"
   if (( _gaps > 0 )); then
      printf '%s\n' "!! APP-CLUSTER REGISTRATION GAP: ${_gaps} cluster(s) not registered with the hub — rerun: make refresh-registration CLUSTER_PROVIDER=k3s-hostinger" >&2
   fi
   return 0
}
```

Notes for the implementer, do not deviate from these:

- The dispatcher is invoked as a **child process**, not by sourcing the provider file. Sourcing
  `scripts/lib/providers/k3s-hostinger.sh` would pull in `shopping_cart.sh` and the hostinger vars
  as a side effect, in the middle of a rebuild. `K3DM_DISPATCHER` exists so BATS can stub it.
- `return 0` even when `_gaps > 0` is deliberate — see "Never abort the rebuild" above. The exit
  code is not the signal; the banner and S4 are.
- Use `_warn`/`_err`/`_info` as shown; they already exist in `scripts/lib/system.sh`.

### S3 — call it from both rebuild paths

**`bin/cluster-up`** — insert directly after the
`_info "[acg-up] ArgoCD cluster registered: ubuntu-k3s → https://host.k3d.internal:6443"` line
(currently `:765`):

```bash
_info "[acg-up] Reconciling other app-cluster registrations (additive)..."
argocd_reconcile_app_cluster_registrations || true
```

`argocd.sh` is already sourced at `bin/cluster-up:52`, so no new source line is needed.

**`scripts/plugins/hub_recovery.sh`** — in `hub_recovery_reconcile`:

1. Append `"Other app-cluster registrations"` to the end of the `steps` array (it currently ends
   with `"Cloudflare origins"`).
2. Insert directly after the existing `register_app_cluster ... || return 1` line (`:252`):

```bash
  argocd_reconcile_app_cluster_registrations || true
```

Keep it before `_hub_recovery_seed_app_cluster_reader`, because that step seeds a credential into
the app cluster and reads better once the registration exists.

### S4 — report the gap in `make status` (`bin/cluster-status`)

Replace the body of the `=== Hub ArgoCD Registration ===` section (`:233-239`) so it reports
**every** inventory row plus the current context, instead of only the current context. Read the
TSV directly — `bin/cluster-status` must not start sourcing `argocd.sh`.

```bash
echo ""
echo "=== Hub ArgoCD Registration (${INFRA_CONTEXT}, ns ${ARGOCD_NAMESPACE}) ==="
if kubectl get secret "cluster-${APP_CONTEXT}" -n "${ARGOCD_NAMESPACE}" \
     --context "${INFRA_CONTEXT}" >/dev/null 2>&1; then
  echo "Registered: secret cluster-${APP_CONTEXT} present"
else
  echo "NOT registered: secret cluster-${APP_CONTEXT} missing"
fi
_app_cluster_table="${REPO_ROOT}/scripts/etc/argocd/app-clusters.tsv"
if [[ -r "${_app_cluster_table}" ]]; then
  while IFS=$'\t' read -r _ac_context _ac_secret _ac_provider; do
    [[ -z "${_ac_context}" || "${_ac_context}" == \#* ]] && continue
    if kubectl get secret "${_ac_secret}" -n "${ARGOCD_NAMESPACE}" \
         --context "${INFRA_CONTEXT}" >/dev/null 2>&1; then
      echo "Registered: ${_ac_context} (secret ${_ac_secret})"
    elif kubectl config get-contexts "${_ac_context}" >/dev/null 2>&1; then
      echo "REGISTRATION GAP: ${_ac_context} has a kubeconfig context but no hub secret ${_ac_secret}"
      echo "                  its workloads are unmanaged — run: make refresh-registration CLUSTER_PROVIDER=${_ac_provider}"
    else
      echo "Not present: ${_ac_context} (no kubeconfig context on this host)"
    fi
  done < "${_app_cluster_table}"
fi
```

`REPO_ROOT` is already set at `bin/cluster-status:17`. The existing `cluster-${APP_CONTEXT}` check
stays — an inventory row for the hub is deliberately absent, so removing it would lose that check.

### Tests

**New file `scripts/tests/plugins/argocd_app_cluster_reconcile.bats`.** Source
`scripts/plugins/argocd.sh` the way `scripts/tests/plugins/argocd.bats` does. Point
`ARGOCD_APP_CLUSTER_TABLE` at a fixture TSV written into `${BATS_TEST_TMPDIR}`, stub
`K3DM_DISPATCHER` with a script that logs its args, and stub `kubectl` /
`_argocd_hub_kubectl_cmd` so the hub lookup is controllable. Six tests:

1. **Missing secret + present context → dispatcher called once with the row's provider.** Assert
   the log contains `refresh_registration`, that `CLUSTER_PROVIDER=k3s-hostinger` reached the
   child, and that the output says `1 restored, 0 still missing`.
2. **Secret already present → dispatcher never called.** Assert the log file is empty or absent
   and the output contains `already registered`.
3. **No kubeconfig context → dispatcher never called, status 0.** Assert output contains
   `no kubeconfig context`. This is the "cluster genuinely retired" case and must not warn as a
   gap.
4. **Dispatcher fails → status is still 0, and the banner is emitted.** Assert
   `[ "$status" -eq 0 ]`, output contains `APP-CLUSTER REGISTRATION GAP`, and
   `1 still missing`.
5. **`K3DM_EXCLUSIVE_APP_CLUSTER=true` → non-zero, dispatcher never called**, output contains
   `additive-only`.
6. **The comment header and blank lines are skipped** — a fixture whose first line is
   `# context\tsecret\tprovider` plus a blank line must yield exactly one dispatcher call.

**`scripts/tests/bin/cluster_up.bats`.** Add one test asserting the reconcile call exists in
`bin/cluster-up` and lands **after** `register_app_cluster`, using the line-number `awk` idiom
already used by the `_acg_repair_hub_host_alias` test at `:19-26`.

**`scripts/tests/plugins/hub_recovery.bats`.** Two changes:
- The dry-run test at `:133` loops `for step in {1..10}` — change to `{1..11}` and add
  `[[ "$output" == *"Other app-cluster registrations"* ]]`. Leaving it at 10 would let a dropped
  step pass.
- Add one test that `hub_recovery_reconcile --confirm` calls
  `argocd_reconcile_app_cluster_registrations`, stubbing every step the way the existing
  `--confirm` tests in that file do.

**New file `scripts/tests/bin/cluster_status_app_cluster_registration.bats`.** Follow
`scripts/tests/bin/cluster_status_image_updater.bats` for the stub-`kubectl`-on-PATH idiom. Three
tests:
1. Secret present → output contains `Registered: ubuntu-hostinger`.
2. Secret absent but kubeconfig context present → output contains `REGISTRATION GAP:` and
   `make refresh-registration`.
3. Secret absent and no kubeconfig context → output contains `Not present:` and **not**
   `REGISTRATION GAP`.

Assert on tokens, never on whole source lines.

**Mutation-prove every new guard.** A new test that passes is not evidence it can fail. For each
of the three, reintroduce the defect, run the suite, paste the red, then restore the file and
confirm `git diff --quiet` before the next mutation:

- **M1** — delete the two added lines from `bin/cluster-up`. The `cluster_up.bats` ordering test
  must go red.
- **M2** — in `argocd_reconcile_app_cluster_registrations`, change `return 0` at the end to
  `return "${_gaps}"`. Reconcile test 4 must go red. (This mutation is the "never abort the
  rebuild" contract; if it does not red, test 4 is not asserting the status.)
- **M3** — in `bin/cluster-status`, revert the S4 block to only the original
  `cluster-${APP_CONTEXT}` check. `cluster_status_app_cluster_registration.bats` test 2 must go
  red.

### Docs — `docs/guides/app-cluster-registration.md` (new)

There is no guide for this today, and its absence is part of why the same loss happened twice.
Cover:

- what a hub app-cluster registration is (the `cicd` Secret, its `k3d-manager/role=app-cluster`
  label) and that **four ApplicationSets select on that label**, so it is load-bearing, not
  bookkeeping;
- the inventory file, and that it is the single place cluster/secret names are declared;
- the three ways a registration gets created: the rebuild's own in-cluster call, the S3 reconcile,
  and `make refresh-registration CLUSTER_PROVIDER=k3s-hostinger` by hand;
- **why additive-only matters** — exclusive mode strips the role from the other registration and
  the AppSets then prune its Applications;
- a triage table: hostinger workloads unmanaged / `ubuntu-hostinger-*` apps all gone /
  `secrets "cluster-ubuntu-hostinger" not found` in a CronJob log → check the registration, not
  the workload;
- that `make status` now prints `REGISTRATION GAP:` when a cluster has a kubeconfig context but no
  hub Secret, and what to run;
- a pointer to both bug docs as the history.

Link it from `README.md` under the guides list, next to the `Alerting` line added in `a7135966`.

## Definition of Done

- [ ] S1-S4 implemented exactly as written; only these files change:
      `scripts/etc/argocd/app-clusters.tsv` (new), `scripts/plugins/argocd.sh`, `bin/cluster-up`,
      `scripts/plugins/hub_recovery.sh`, `bin/cluster-status`,
      `scripts/tests/plugins/argocd_app_cluster_reconcile.bats` (new),
      `scripts/tests/bin/cluster_up.bats`, `scripts/tests/plugins/hub_recovery.bats`,
      `scripts/tests/bin/cluster_status_app_cluster_registration.bats` (new),
      `docs/guides/app-cluster-registration.md` (new), `README.md`, `CHANGELOG.md`,
      `memory-bank/activeContext.md`, `memory-bank/progress.md`
- [ ] `grep -c 'cluster-ubuntu-hostinger' scripts/etc/argocd/app-clusters.tsv` outputs `1`, and
      the string is added to **no other** shell or manifest file (it is already hardcoded in five
      places; this must not become six — `grep -rn 'cluster-ubuntu-hostinger' scripts/ bin/` count
      must be unchanged except for the new TSV row)
- [ ] `shellcheck -x scripts/plugins/argocd.sh scripts/plugins/hub_recovery.sh bin/cluster-up bin/cluster-status`
      — zero new warnings vs `HEAD~`; paste both counts
- [ ] `bats scripts/tests/plugins/argocd_app_cluster_reconcile.bats scripts/tests/bin/cluster_up.bats scripts/tests/plugins/hub_recovery.bats scripts/tests/bin/cluster_status_app_cluster_registration.bats`
      — all green; paste the full output with counts
- [ ] `make test` green (~15 min — that is NOT a hang; let it finish). Paste the summary line.
- [ ] M1, M2, M3 each reproduced; paste the red for each and confirm the tree was restored
- [ ] `make check-doc-links` OK (the pre-commit hook runs it on staged `.md`)
- [ ] CHANGELOG `## [Unreleased]` → `### Fixed`: "A hub rebuild no longer drops the
      `ubuntu-hostinger` app-cluster registration — `bin/cluster-up` and `hub_recovery_reconcile`
      reconcile every cluster declared in `scripts/etc/argocd/app-clusters.tsv`, and `make status`
      reports a `REGISTRATION GAP` when one is missing"
- [ ] Commit message verbatim:

```
fix(argocd): reconcile app-cluster registrations on hub rebuild and report gaps

A hub rebuild recreated only the in-cluster ubuntu-k3s registration, so
cluster-ubuntu-hostinger vanished on 2026-09-11 and again on 2026-09-20,
orphaning every ubuntu-hostinger workload. cluster-status only checked the
current provider's context, so make status reported Registered while hostinger
was unmanaged. Declares the app clusters in one TSV, reconciles them additively
from both rebuild paths via the existing refresh_registration entry point, and
surfaces any remaining gap in make status.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01B9RRyT5eU8S76oXYMrLZN8
```

- [ ] Pushed to `origin/k3d-manager-v1.37.0`; `git rev-parse HEAD` equals
      `git rev-parse origin/k3d-manager-v1.37.0`; report both
- [ ] `memory-bank/activeContext.md` and `memory-bank/progress.md` updated with the SHA and status

## What NOT to Do

- Do NOT create a pull request. Do NOT merge. Do NOT commit to `main`. Do NOT force-push.
- Do NOT use `--no-verify` or otherwise skip the pre-commit hooks.
- Do NOT modify files outside the list above.
- Do NOT touch the live cluster: no `kubectl`, no `helm`, no `docker`, no `make up`, no
  `make refresh`, no `make refresh-registration` without `-n`. This task is code + tests + docs.
  The live run is the operator's and is in the runbook below.
- Do NOT change `_hostinger_register_cluster`, `_provider_k3s_hostinger_refresh_registration`,
  `register_app_cluster`, `_hostinger_set_active_app_cluster`, or any ApplicationSet.
- Do NOT flip the root `K3DM_EXCLUSIVE_APP_CLUSTER` default, and do NOT add an exclusive-mode path.
- Do NOT edit `scripts/lib/foundation/` or `scripts/lib/acg/` — subtrees, fixed upstream.
- Do NOT rename `cluster-ubuntu-hostinger`. It is hardcoded in five places including an RBAC
  `resourceNames`; renaming is separate work that must change all five in one commit.

---

## Live runbook (operator — needs the user's go; hub mutation)

Run only after the code above is verified, and note that step 2 is also the outstanding item 1
("re-register hostinger"), which needs no new code.

1. **Pre-check (read-only).**
   ```
   kubectl --context k3d-k3d-cluster -n cicd get secret -l argocd.argoproj.io/secret-type=cluster -L k3d-manager/role,environment
   kubectl --context k3d-k3d-cluster -n cicd get applications --no-headers | grep -c '^ubuntu-k3s-'
   make status CLUSTER_PROVIDER=k3s-hostinger   # must now print REGISTRATION GAP: ubuntu-hostinger
   ```
2. **Re-register.** `make refresh-registration CLUSTER_PROVIDER=k3s-hostinger`
3. **Verify (read-only).** `cluster-ubuntu-hostinger` present with `role=app-cluster` and
   `environment=dev`; `ubuntu-k3s-app-cluster` still has `role=app-cluster` and **no**
   `environment`; the `ubuntu-k3s-*` count unchanged; `ubuntu-hostinger-*` apps generated and
   reaching Synced/Healthy; hub `istiod-ubuntu-k3s` unchanged;
   `bin/smoke-test-cluster-health` still 9/0; `make status` no longer prints a gap.
4. **Confirm the alert path now works too** — with `a7135966` deployed, a still-failing
   `cve-remediation-verify` should produce a `KubeJobFailed` email. If the registration fixes the
   CronJob before that lands, force the check another way rather than assuming.
5. **Prove the durability claim.** The fix is unverified until a rebuild has actually happened with
   it in place. On the next hub rebuild, confirm `cluster-ubuntu-hostinger` returns without manual
   intervention. Until then this doc stays open.

### Risks and out of scope

- **Auto-sync converges hostinger to the branch's git state** once registered. On a 2-CPU node
  watch for Pending pods (`reference_hostinger_maxsurge_rollout_deadlock`).
- **Hostinger ExternalSecrets depend on the Vault bridge/tunnel**, which `refresh_registration`
  deliberately does not touch. ESO stores going NotReady is separate follow-up, not a reason to
  run `make refresh`.
- **`istio-ambient` stays single-destination (hub).** Hostinger istio remains unmanaged.
- **The five hardcoded `cluster-ubuntu-hostinger` sites** are untouched here.
- **`Watchdog` still routes to `'null'`** — tracked in the alerting bug doc, not here.
