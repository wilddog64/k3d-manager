# Bug: Hostinger Vault stays sealed after a node reboot — no unseal watchdog there

**Status:** LIVE-VERIFIED — 2026-10-18: E3 passed on ubuntu-hostinger. After `make refresh CLUSTER_PROVIDER=k3s-hostinger`, the operator deleted `secrets/vault-0` at 19:12:54Z; it came back sealed and the next watchdog run (`vault-unseal-watchdog-29872515`, 19:15:00Z) logged `vault sealed — replaying shard` / `unseal succeeded`; `vault-sealed=false` and ready at 19:15:04Z, 2m10s after the restart (limit 10 min). Fixed by Codex `a1c2f800`; offline: Codex BATS 24/24, independent verifier 9/9, N1/N3 red on pre-fix
**Priority:** P1
**Approval:** approved — operator, 2026-10-17: "apporve the fix"
**Found:** 2026-10-17, Claude, while `make appsets-reapply` failed its final check
**Branch:** `k3d-manager-v1.43.4`
**Affected:** `ubuntu-hostinger` Vault (`secrets/vault-0`), every ExternalSecret on Hostinger

## Symptom

`make appsets-reapply` ended with `Error 1`, listing `ubuntu-hostinger-data-layer` and
`ubuntu-hostinger-shopping-cart-namespace` as `health Degraded` under "Applications on a stale
values branch". Neither is on a stale branch; both are Synced. They are Degraded because their
ExternalSecrets are.

## Evidence (live, read-only, 2026-10-17)

- `vault status` in `secrets/vault-0` on Hostinger: `Sealed true`, `Unseal Progress 0/1`; the pod
  is `0/1 Running` since the 18:10:52Z reboot (`docs/bugs/2026-10-17-hostinger-node-unresponsive-then-rebooted.md`).
- `ClusterSecretStore/vault-backend`: `Ready=False InvalidProviderConfig: unable to create client`.
- 14 of 15 ExternalSecrets in `shopping-cart-apps` / `shopping-cart-data` are `SecretSyncedError`.
  App and data pods still run on the Secrets synced before the reboot.
- The hub has `secrets/vault-unseal-watchdog` (CronJob, `*/5`). Hostinger has **no CronJob at all**,
  although its `secrets/vault-unseal` Secret exists. `vault_install_unseal_watchdog` is only called
  from `deploy_vault` for the cluster it deploys; nothing installs it on an app cluster.

## Impact

Any Hostinger reboot leaves Vault sealed until someone notices. Secrets keep working until a pod
needs a Secret that changed or was deleted, or a new ExternalSecret is added — then that app breaks.
Rotations stop silently.

## Secondary: the reapply check mislabels health as a stale branch

`appsets-reapply` prints Degraded Applications under "Applications on a stale values branch" with
"Fix: reapply the ApplicationSets", which sends the operator to the wrong fix. A Degraded app on the
correct branch should be reported separately.

## Secondary: the watchdog image is read from the wrong cluster

With a context argument, `vault_install_unseal_watchdog` still reads the Vault image from
`_kubectl` (the current context, i.e. the hub), not from the target context.

## Fix direction

1. Install the unseal watchdog on every cluster that runs its own Vault — at least on Hostinger,
   as part of the Hostinger provisioning/refresh path — and read the image from that cluster.
2. Split the reapply check's output: wrong branch vs. right branch but unhealthy.

## Fix

Three changes, all in `k3d-manager` on `k3d-manager-v1.43.4`.

### 1. `scripts/plugins/vault.sh` — read the image from the target context

Old:

```bash
   _live_vault_image="$(_kubectl -n "$ns" get statefulset "${VAULT_RELEASE:-$VAULT_RELEASE_DEFAULT}" -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null)"
```

New:

```bash
   if [[ -n "$app_context" ]]; then
      _live_vault_image="$(kubectl --context "$app_context" -n "$ns" get statefulset "${VAULT_RELEASE:-$VAULT_RELEASE_DEFAULT}" -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null)"
   else
      _live_vault_image="$(_kubectl -n "$ns" get statefulset "${VAULT_RELEASE:-$VAULT_RELEASE_DEFAULT}" -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null)"
   fi
```

### 2. `scripts/lib/providers/k3s-hostinger.sh` — install the watchdog on refresh

Add this function directly above `function _hostinger_reconcile_vault_cluster_store() {`:

```bash
function _hostinger_ensure_vault_unseal_watchdog() {
  local ns="${HOSTINGER_VAULT_NS:-secrets}"
  local release="${VAULT_RELEASE:-vault}"
  if ! kubectl --context "${_HOSTINGER_KUBE_CONTEXT}" -n "${ns}" get statefulset "${release}" >/dev/null 2>&1; then
    _info "[k3s-hostinger] No Vault StatefulSet ${ns}/${release} on ${_HOSTINGER_KUBE_CONTEXT} — skipping unseal watchdog"
    return 0
  fi
  if ! declare -f vault_install_unseal_watchdog >/dev/null 2>&1; then
    source "${SCRIPT_DIR}/plugins/vault.sh"
  fi
  _info "[k3s-hostinger] Ensuring Vault unseal watchdog on ${_HOSTINGER_KUBE_CONTEXT}..."
  if ! ( vault_install_unseal_watchdog "${ns}" "${_HOSTINGER_KUBE_CONTEXT}" ); then
    printf 'ERROR: %s\n' "[k3s-hostinger] Vault unseal watchdog install failed on ${_HOSTINGER_KUBE_CONTEXT} — a reboot will leave Vault sealed" >&2
    return 1
  fi
}
```

The subshell is deliberate: `vault_install_unseal_watchdog` sets and then clears `trap … EXIT TERM`,
which would wipe any EXIT trap the refresh path holds.

In `_provider_k3s_hostinger_refresh_cluster`, old:

```bash
  _hostinger_refresh_access_layer || return 1
  if kubectl --context "${_HOSTINGER_KUBE_CONTEXT}" get --raw='/healthz' >/dev/null 2>&1; then
```

New:

```bash
  _hostinger_refresh_access_layer || return 1
  _hostinger_ensure_vault_unseal_watchdog || return 1
  if kubectl --context "${_HOSTINGER_KUBE_CONTEXT}" get --raw='/healthz' >/dev/null 2>&1; then
```

(After the edge refresh, so a watchdog failure never leaves the edge down.) The deploy path is
not changed: Vault does not exist yet at `deploy_cluster` time; the first `make refresh` installs it.

### 3. `scripts/plugins/argocd.sh` — separate Degraded from stale branch

In `argocd_check_values_branch`, old:

```bash
   _warn "[argocd] Applications on a stale values branch:"
   printf '%s\n' "${_drift}" >&2
   _warn "[argocd] Fix: reapply the ApplicationSets with K3D_MANAGER_BRANCH=${_expected}"
   return 1
```

New:

```bash
   local _stale _degraded
   _stale="$(printf '%s\n' "${_drift}" | grep -v ' health Degraded$' || true)"
   _degraded="$(printf '%s\n' "${_drift}" | grep ' health Degraded$' || true)"
   if [[ -n "${_stale}" ]]; then
      _warn "[argocd] Applications on a stale values branch:"
      printf '%s\n' "${_stale}" >&2
      _warn "[argocd] Fix: reapply the ApplicationSets with K3D_MANAGER_BRANCH=${_expected}"
   fi
   if [[ -n "${_degraded}" ]]; then
      _warn "[argocd] Applications Degraded on the expected branch (health, not a values-branch problem):"
      printf '%s\n' "${_degraded}" >&2
      _warn "[argocd] Fix: inspect the Application's resources (often an ExternalSecret behind a sealed Vault); reapplying will not fix these"
   fi
   return 1
```

### 4. Tests

- `scripts/tests/plugins/vault_unseal_watchdog_context.bats` (new): stub `kubectl` and `_kubectl` as
  functions that append their args to a log; call `vault_install_unseal_watchdog secrets ubuntu-hostinger`;
  assert every recorded `get statefulset` call carries `--context ubuntu-hostinger` and `_kubectl` was
  never called; assert the rendered image is the one the stub returned for that context.
- `scripts/tests/lib/hostinger_vault_unseal_watchdog.bats` (new): source the provider with stubs;
  no StatefulSet → returns 0 and does not call `vault_install_unseal_watchdog`; StatefulSet present →
  calls it with `secrets ubuntu-hostinger`; installer failure → returns 1 with the ERROR line;
  `_provider_k3s_hostinger_refresh_cluster` text calls the helper after `_hostinger_refresh_access_layer`.
- `scripts/tests/plugins/argocd_values_branch_drift.bats`: add a case with one app on a stale branch
  and one Degraded on the expected branch; assert each heading lists only its own app. Update any
  existing assertion that expected a Degraded line under the stale heading.

## Definition of Done

- [ ] The three source changes above, exactly; the three test files.
- [ ] `bats scripts/tests/plugins/vault_unseal_watchdog_context.bats scripts/tests/lib/hostinger_vault_unseal_watchdog.bats scripts/tests/plugins/argocd_values_branch_drift.bats scripts/tests/etc/vault_unseal_watchdog.bats` green; paste output.
- [ ] Show the new N1 and N3 tests red against the pre-fix source (temp copy, never the tree); paste output.
- [ ] `shellcheck` on the three changed scripts: no new warnings.
- [ ] Commit message, verbatim: `fix(vault): install the unseal watchdog on Hostinger and read its image from the target context`
- [ ] Push to `origin/k3d-manager-v1.43.4`; report the SHA from `git rev-parse origin/k3d-manager-v1.43.4`.

## What NOT to Do

- Do NOT create a PR, and do NOT commit to `main`.
- Do NOT skip pre-commit hooks (`--no-verify`).
- Do NOT modify files outside the listed targets (no memory-bank, no other docs).
- Do NOT edit `scripts/lib/foundation/`.
- Do NOT run anything against a live cluster or print any Secret content; tests use stubs only.
- Do NOT change `unseal-watchdog.yaml.tmpl`.

## Acceptance

```yaml
must:
  - id: M1
    text: After a Hostinger Vault pod restart, Vault is unsealed within 10 minutes with no operator action.
  - id: M2
    text: The Hostinger provisioning/refresh path installs the unseal watchdog CronJob in the Vault namespace on ubuntu-hostinger.
  - id: M3
    text: The watchdog image is taken from the target cluster's Vault StatefulSet when a context is given.
  - id: M4
    text: appsets-reapply reports a Degraded Application on the expected branch under a health heading, not as a stale branch.
must_not:
  - id: N1
    text: The watchdog install never reads the Vault image from a context other than the one it installs into (red on pre-fix).
  - id: N2
    text: The install never prints or logs unseal key material.
  - id: N3
    text: An app on the expected values branch is never listed as "on a stale values branch" (red on pre-fix).
evidence:
  - id: E1
    proves: [M2, M3, N1, N2]
    kind: offline
    text: BATS with a kubectl stub recording --context per call.
  - id: E2
    proves: [M4, N3]
    kind: offline
    text: BATS over the reapply check with a stubbed Application list (one stale, one Degraded on-branch).
  - id: E3
    proves: [M1]
    kind: live
    text: Claude or operator deletes secrets/vault-0 on Hostinger and confirms `Sealed false` within 10 minutes.
interface:
  - scripts/plugins/vault.sh vault_install_unseal_watchdog [ns] [context]
  - make appsets-reapply / the values-branch confirmation it runs
  - CronJob secrets/vault-unseal-watchdog, Secret secrets/vault-unseal
```

## Live evidence

**Live evidence:** 2026-10-18 · run vault-unseal-watchdog-29872515 · env ubuntu-hostinger · scenario vault-0-pod-delete · commit a1c2f800 · proves E3

2026-10-18, run by the operator, observed read-only by Claude:

- `kubectl --context ubuntu-hostinger -n secrets delete pod vault-0`; new pod `startTime`
  19:12:54Z, labelled `vault-sealed=true`, container not ready.
- CronJob `vault-unseal-watchdog` (`*/5 * * * *`, not suspended) ran job
  `vault-unseal-watchdog-29872515` at 19:15:00Z, which completed in 4s. Log:
  `[unseal-watchdog] vault sealed — replaying shard`, `[unseal-watchdog] unseal succeeded`.
- 19:15:04Z: `vault-sealed=false`, container ready. Total sealed time 2m10s, inside the 10-minute
  bound in E3.
