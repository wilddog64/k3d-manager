# Vault unseal-watchdog pins a stale image → job dies before it can unseal

**Date:** 2026-08-28
**Status:** SPEC → FIX
**Area:** `scripts/plugins/vault.sh` (`vault_install_unseal_watchdog`), `scripts/etc/vault/unseal-watchdog.yaml.tmpl`
**Severity:** High — the watchdog is non-functional in the exact scenario it exists for.

## Symptom

`vault_install_unseal_watchdog` deploys a CronJob whose pod pins
`hashicorp/vault:1.18.3` (template default `VAULT_UNSEAL_IMAGE`). The live
Vault runs `hashicorp/vault:1.20.1`, so `1.18.3` is **not** cached on any
node. With `imagePullPolicy: IfNotPresent` the container must pull, but the
Job's `activeDeadlineSeconds: 50` kills the pod while it is still
`ContainerCreating`. Result: the Job reports `failed=1` and the watchdog
never runs its unseal logic.

Reproduced 2026-08-28: a manual `create job --from=cronjob/vault-unseal-watchdog`
sat in `ContainerCreating` and was killed by the deadline (`FAILED=1`) before
the 1.18.3 pull completed.

## Impact

The watchdog's whole purpose is to auto-unseal Vault after a cluster restart
(currently a manual `deploy_vault --re-unseal`). If Vault is sealed and the
watchdog can't even start its container within the deadline, the auto-unseal
never fires — the operator is back to unsealing by hand, silently.

## Root cause

The template default image (`1.18.3`) is hard-coded and has drifted from the
deployed Vault chart image (`1.20.1`). Bumping the hard-coded default just
moves the drift to the next chart bump.

A second layer made the first derivation attempt a no-op: `scripts/etc/vault/vars.sh`
unconditionally `export`ed `VAULT_UNSEAL_IMAGE=hashicorp/vault:1.18.3`, and
`_vault_source_optional_vars` sources that file at the top of the installer —
so `VAULT_UNSEAL_IMAGE` is *always* set to the stale value before the
function runs, and a `${VAULT_UNSEAL_IMAGE:-<derived>}` fallback never fires.
vars.sh must leave it empty (`${VAULT_UNSEAL_IMAGE:-}`) so the function's
derivation is the authority; an explicit user override is still honored.

## Fix (durable — derive, don't re-pin)

In `vault_install_unseal_watchdog`, when `VAULT_UNSEAL_IMAGE` is not explicitly
set, derive it from the **running** Vault StatefulSet's container image. That
image is guaranteed already cached on-node, so `IfNotPresent` starts instantly
and the 50s deadline is never a factor. Fall back to the pinned default only
when Vault is not deployed yet (fresh hub).

```bash
local _live_vault_image
_live_vault_image="$(_kubectl -n "$ns" get statefulset "${VAULT_RELEASE:-$VAULT_RELEASE_DEFAULT}" \
   -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null)"
VAULT_UNSEAL_IMAGE="${VAULT_UNSEAL_IMAGE:-${_live_vault_image:-hashicorp/vault:1.18.3}}"
```

- StatefulSet name = `vault` (`VAULT_RELEASE_DEFAULT`), namespace = `secrets`
  (`VAULT_NS_DEFAULT`).
- The `vault` CLI is version-compatible for `operator unseal` against a
  same-or-adjacent server; using the server's own image is the safest match.
- Pinned fallback retained (security rule: no floating `latest`).

## Second factor: per-node image cache vs the 50s deadline

In a multi-node k3d cluster each node has an independent containerd image
cache. The derived `1.20.1` is cached only on the node running vault-0; a
watchdog Job scheduled elsewhere still cold-pulls, and the original
`activeDeadlineSeconds: 50` killed the pod mid-pull (`ContainerCreating`).

Note this does **not** affect the real scenario the watchdog is for:
a `k3d cluster stop/start` preserves each node's containerd cache, so
post-restart the image is already present everywhere it ran before and the
Job starts in seconds. The cold-pull only bites a *first* deploy onto a node
that never held the image.

Fix: raise `activeDeadlineSeconds` 50 → 150 so a cold pull can complete.
`concurrencyPolicy: Forbid` + the every-minute schedule means an
overrunning cold-pull tick simply skips the next fire; warm runs finish in
seconds.

## Verification

1. Reinstall: `./scripts/k3d-manager vault_install_unseal_watchdog`
2. Confirm the CronJob image now equals the live Vault image (1.20.1).
3. Manual trigger `create job --from=cronjob/...`; job **succeeds** and logs
   `vault already unsealed` (cached image → instant start, no deadline hit).
4. Shard secret `vault-unseal/shard-1` present in `secrets` ns (already true).

## Auto-install from deploy_vault (decided: yes)

Previously "not in scope" pending a decision. Decision 2026-08-28: **yes** —
`deploy_vault` now calls `vault_install_unseal_watchdog "$ns"` on its
successful full-deploy path (after `_vault_setup_pki`, before the optional
re-unseal branch), guarded with `|| _warn` so a watchdog hiccup never fails
the deploy. Rationale: the watchdog is idempotent and safe, and its whole
purpose (auto-unseal after a restart) should survive a hub rebuild without an
operator remembering a second command — the same "survives rebuild" pattern
already used for `deploy_argocd_platform_ops` in the ArgoCD bootstrap. An
explicit standalone `vault_install_unseal_watchdog` call remains available.

## Not in scope

- Auto-installing the shard secret itself — the watchdog mounts `vault-unseal`
  `optional: true` and no-ops when it is absent; shard caching stays owned by
  the existing unseal/bootstrap paths.
