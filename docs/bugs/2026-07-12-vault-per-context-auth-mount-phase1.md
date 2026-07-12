# Bugfix: v1.14.0 — Vault per-context auth mount (Phase 1)

**Branch:** `k3d-manager-v1.14.0`
**Files:** `scripts/plugins/vault.sh`, `scripts/plugins/shopping_cart.sh`, `scripts/plugins/eso.sh`,
`scripts/tests/plugins/vault_app_auth.bats`, `scripts/tests/plugins/shopping_cart_css_auth_block.bats`

Implements **Phase 1** of the design doc
[`2026-07-07-app-cluster-vault-portability.md`](./2026-07-07-app-cluster-vault-portability.md)
(decisions signed off 2026-07-10). That doc is design-only and must NOT be handed off — this is the
copy-paste implementation spec it calls for.

---

## Problem

Every app cluster's Vault Kubernetes auth is written to the **single fixed mount `kubernetes-app`**.
`configure_vault_app_auth_for_context` (`vault.sh:1788`) derives per-context `server`/`ca_data`
correctly, but at `:1849-1853` it calls `configure_vault_app_auth` exporting only
`APP_CLUSTER_API_URL` + `APP_CLUSTER_CA_CERT_PATH`, so the callee falls through to its default
`mount="${APP_K8S_AUTH_MOUNT:-kubernetes-app}"` (`:1695`). Configuring a second app cluster
overwrites the first cluster's `kubernetes_host` + CA on that shared mount (`:1730-1732`),
invalidating the first cluster's ESO auth path — **last cluster wins.**

**Root cause:** the auth mount is a constant, not keyed by kube-context.

**Fix (design decision #2):** derive the mount as `kubernetes-<sanitized-context>` and thread the
same derived value through all three sites that reference the mount, so the Vault-side mount and the
ESO `SecretStore`/`ClusterSecretStore` `mountPath` always agree for a given cluster. `kubernetes-app`
remains the legacy default and the migration pin.

### The three mount sites (all already read env vars — inject one derived value)

| Site | Reads | Role |
|------|-------|------|
| `vault.sh:1695` | `APP_K8S_AUTH_MOUNT:-kubernetes-app` | Vault-side: enables + configures the mount, writes the role |
| `shopping_cart.sh:466` | `APP_K8S_AUTH_MOUNT:-kubernetes-app` | ESO `ClusterSecretStore` `mountPath` (app cluster reads back) |
| `eso.sh:215` | `REMOTE_VAULT_K8S_MOUNT:-kubernetes-app` | ESO remote `SecretStore` `mountPath` |

---

## Reproduction

```bash
# Configure two app contexts against the same hub Vault, in sequence:
configure_vault_app_auth_for_context "ubuntu-hostinger"
configure_vault_app_auth_for_context "k3s-oci"
# Inspect the (single) mount config — it now holds ONLY the k3s-oci API server + CA:
vault read auth/kubernetes-app/config     # kubernetes_host = k3s-oci's, not hostinger's
```

Expected: each cluster owns its own mount (`kubernetes-ubuntu-hostinger`, `kubernetes-k3s-oci`),
each with its own `kubernetes_host` + CA. Actual: both write `kubernetes-app`; hostinger's ESO auth
breaks after the k3s-oci run.

---

## Open implementation decision — helper location (resolve before handoff)

`_vault_app_auth_mount` must be visible to `vault.sh`, `shopping_cart.sh`, and `eso.sh`, which are
lazy-loaded plugins. Two options:

- **(A) Define in `vault.sh`; guard callers with `declare -f _vault_app_auth_mount` and lazy-load the
  vault plugin first.** Matches the existing `declare -f`-guard pattern (`vars.sh:26`,
  `k3s-oci.sh:648`). Risk: if a consumer runs without vault loaded, the guard's fallback to
  `kubernetes-app` silently reintroduces the mismatch this fix removes.
- **(B) Define in an always-sourced lib** (`scripts/lib/core.sh` or equivalent) so all three see it
  with no lazy-load race. Cleaner; slightly wider blast radius.

**Recommendation: (B).** The whole point is a single agreed derivation — a fallback that diverges
under a load race defeats it. Confirm the correct always-sourced lib before writing the helper block,
then adjust the "Change 1" file target accordingly. The blocks below are written for placement in
`vault.sh` (option A); if (B) is chosen, move the helper block verbatim to the chosen lib and drop
the `declare -f` guards in the two consumers.

---

## Fix

### Change 1 — `scripts/plugins/vault.sh`: add the derivation helper

Insert immediately **before** `function configure_vault_app_auth_for_context() {` (currently line 1788):

**Exact new block:**

```bash
# _vault_app_auth_mount CONTEXT
# Derive the per-cluster Vault Kubernetes auth mount path from a kube-context.
# Honors an explicit APP_K8S_AUTH_MOUNT override (migration pin / legacy single-cluster).
# Otherwise: kubernetes-<sanitized-context>, sanitized to a Vault-path-safe segment.
function _vault_app_auth_mount() {
  local ctx="${1:-}"
  if [[ -n "${APP_K8S_AUTH_MOUNT:-}" ]]; then
    printf '%s' "${APP_K8S_AUTH_MOUNT}"
    return 0
  fi
  local seg
  seg="$(printf '%s' "${ctx}" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9-]+/-/g; s/-+/-/g; s/^-+//; s/-+$//')"
  [[ -n "${seg}" ]] || seg="app"
  printf '%s' "kubernetes-${seg}"
}

```

### Change 2 — `scripts/plugins/vault.sh`: export the derived mount into the subshell

**Exact old block (lines 1849–1853):**

```bash
  (
    APP_CLUSTER_API_URL="${server}" \
    APP_CLUSTER_CA_CERT_PATH="${ca_path}" \
    configure_vault_app_auth
  ) || rc=$?
```

**Exact new block:**

```bash
  local app_mount
  app_mount="$(_vault_app_auth_mount "${cluster_name}")"
  _info "[vault] app-cluster auth mount for '${app_context}': ${app_mount}"
  (
    APP_CLUSTER_API_URL="${server}" \
    APP_CLUSTER_CA_CERT_PATH="${ca_path}" \
    APP_K8S_AUTH_MOUNT="${app_mount}" \
    configure_vault_app_auth
  ) || rc=$?
```

### Change 3 — `scripts/plugins/shopping_cart.sh`: derive the same mount for the ESO store

**Exact old block (lines 514–516):**

```bash
  local _css_vault_server="${HUB_VAULT_CSS_SERVER:-http://vault-bridge.secrets.svc.cluster.local:8201}"
  local _css_auth_block
  _css_auth_block="$(_shopping_cart_css_auth_block "${_css_auth}")"
```

**Exact new block:**

```bash
  local _css_vault_server="${HUB_VAULT_CSS_SERVER:-http://vault-bridge.secrets.svc.cluster.local:8201}"
  local _app_mount="${APP_K8S_AUTH_MOUNT:-kubernetes-app}"
  if declare -f _vault_app_auth_mount >/dev/null 2>&1; then
    _app_mount="$(_vault_app_auth_mount "${_app_context}")"
  fi
  local _css_auth_block
  _css_auth_block="$(APP_K8S_AUTH_MOUNT="${_app_mount}" _shopping_cart_css_auth_block "${_css_auth}")"
```

> If option (B) is chosen, drop the `declare -f` guard and call `_vault_app_auth_mount` directly.

### Change 4 — `scripts/plugins/eso.sh`: derive the remote mount from context

`_eso_configure_remote_vault` (`:210`) reads `REMOTE_VAULT_K8S_MOUNT:-kubernetes-app` (`:215`). When
a context is resolvable, default it to the per-context mount instead of `kubernetes-app`.

**Exact old block (line 215):**

```bash
  local mount_path="${REMOTE_VAULT_K8S_MOUNT:-kubernetes-app}"
```

**Exact new block:**

```bash
  local mount_path="${REMOTE_VAULT_K8S_MOUNT:-}"
  if [[ -z "${mount_path}" ]] && declare -f _vault_app_auth_mount >/dev/null 2>&1 \
     && declare -f _shopping_cart_resolve_app_context >/dev/null 2>&1; then
    mount_path="$(_vault_app_auth_mount "$(_shopping_cart_resolve_app_context)")"
  fi
  [[ -n "${mount_path}" ]] || mount_path="kubernetes-app"
```

---

## Migration path (live `ubuntu-hostinger`)

The one live app cluster today, `ubuntu-hostinger`, has its ESO `ClusterSecretStore` bound to
`kubernetes-app`. After this change its derived mount becomes `kubernetes-ubuntu-hostinger`. To avoid
a flag-day break:

1. **Next reconcile configures the NEW mount** (`kubernetes-ubuntu-hostinger`) alongside the existing
   `kubernetes-app` — the old mount is left intact, so nothing breaks mid-migration.
2. **Re-apply the ESO store in the same flow** so its `mountPath` moves to the new mount
   (`shopping_cart_apply_vault_token_and_cluster_secret_store` already re-renders it each run).
3. **Verify** the app cluster's ESO `ClusterSecretStore` reports `Valid` and secrets still sync.
4. **Only then** decommission the orphaned `kubernetes-app` mount (a follow-up, not this change).
5. **Rollback pin:** exporting `APP_K8S_AUTH_MOUNT=kubernetes-app` restores the exact prior behavior
   everywhere (helper honors the override first) — use it to freeze the migration if step 3 fails.

This is Claude's live step, not the agent's — the agent ships code + BATS only.

---

## Tests

- Extend `scripts/tests/plugins/vault_app_auth.bats`:
  - `_vault_app_auth_mount "ubuntu-hostinger"` → `kubernetes-ubuntu-hostinger`.
  - `_vault_app_auth_mount "k3s-oci"` → `kubernetes-k3s-oci`.
  - Uppercase / invalid chars (`Foo/Bar_1`) → sanitized (`kubernetes-foo-bar-1`).
  - Empty context → `kubernetes-app`.
  - `APP_K8S_AUTH_MOUNT` override wins (existing `:155` `custom-mount` case still passes).
- Extend `scripts/tests/plugins/shopping_cart_css_auth_block.bats`: the rendered block's `mountPath`
  reflects the derived per-context mount when `APP_K8S_AUTH_MOUNT` is unset (the `:34`
  `kubernetes-hostinger` example is the intended shape).

Run clean-env: `env -i HOME="$HOME" PATH="$PATH" bats scripts/tests/plugins/vault_app_auth.bats
scripts/tests/plugins/shopping_cart_css_auth_block.bats`.

---

## Files Changed

| File | Change |
|------|--------|
| `scripts/plugins/vault.sh` | add `_vault_app_auth_mount`; export derived mount into the auth subshell |
| `scripts/plugins/shopping_cart.sh` | derive per-context mount for the ESO `ClusterSecretStore` |
| `scripts/plugins/eso.sh` | default remote `SecretStore` mount to per-context |
| `scripts/tests/plugins/vault_app_auth.bats` | mount-derivation + sanitizer + override cases |
| `scripts/tests/plugins/shopping_cart_css_auth_block.bats` | rendered `mountPath` per-context case |

---

## Rules

- `shellcheck -S warning scripts/plugins/vault.sh scripts/plugins/shopping_cart.sh scripts/plugins/eso.sh` — zero new warnings.
- BATS suites above pass in a clean env.
- Do NOT change `configure_vault_app_auth`'s default (`kubernetes-app` stays the legacy default at `:1695`).
- Do NOT touch the `provider.sh:94` `ubuntu-k3s` mapping — that is Phase 3, out of scope here.
- Do NOT rename or delete the existing `kubernetes-app` mount — migration keeps it until step 4.
- No other files touched.

---

## Definition of Done

- [ ] `_vault_app_auth_mount` exists and is unit-tested (derivation + sanitizer + override + empty).
- [ ] All three mount sites resolve to the same per-context value for a given context.
- [ ] `configure_vault_app_auth`'s `kubernetes-app` default unchanged.
- [ ] `shellcheck -S warning` clean on all three changed shell files.
- [ ] Both BATS suites pass in a clean env.
- [ ] Committed and pushed to `k3d-manager-v1.14.0`.
- [ ] memory-bank updated with commit SHA and task status.

**Commit message (exact):**
```
fix(vault): derive per-context app-cluster auth mount
```

---

## What NOT to Do

- Do NOT create a PR.
- Do NOT skip pre-commit hooks (`--no-verify`).
- Do NOT modify any file outside the five listed targets.
- Do NOT commit to `main` — work on `k3d-manager-v1.14.0`.
- Do NOT apply/sync anything against a live cluster — Claude runs the migration (steps 1–5 above)
  and verifies ESO stays `Valid`. The agent ships code + BATS only.
- Do NOT touch Phase 2 (per-context hub-Vault profile) or Phase 3 (`ubuntu-k3s` demote + reachability
  preflight) — separate specs.
