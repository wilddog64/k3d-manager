# Bugfix: v1.10.0 — Hostinger refresh must ensure the Vault port-forward LaunchAgent

**Branch:** `feat/v1.10.0-vault-auth-portable`
**Files:** `scripts/lib/providers/k3s-hostinger.sh`

---

## Problem

A live Hostinger outage (2026-06-26): frontend/product-images `502`, ClusterSecretStore
`vault-backend` `Ready=False` (`EOF` → `context deadline exceeded`), data-layer + several
shopping-cart apps Missing/CrashLooping.

The app cluster reaches the hub Vault through this chain:

```
app CSS → vault-bridge:8201 (Svc) → Hostinger host socat → host:8200
        → autossh reverse tunnel (-R) → Mac 127.0.0.1:18200 → vault-0:8200
```

The final hop — the Mac-side Vault port-forward LaunchAgent
`com.k3d-manager.vault-port-forward` (`127.0.0.1:18200 → vault-0:8200`) — **was not
installed/running**, so the chain dead-ended at `18200`. ESO could not validate the store,
every credential went stale, and a coincident namespace recreation could not recover.

**Root cause:** `bin/cluster-up` installs this LaunchAgent (step 4.1), but
`_hostinger_refresh_access_layer` in `scripts/lib/providers/k3s-hostinger.sh` restarts every
*other* access-layer port-forward (argocd, keycloak, cloudflared, browser wrappers, grafana,
pushgateway) and **never ensures `com.k3d-manager.vault-port-forward`**. Once it dies
(reboot / logout / crash) nothing brings it back, and `make refresh CLUSTER_PROVIDER=k3s-hostinger`
silently leaves the Vault path broken.

> **Note:** this is the fragile bridge that the v1.10.0 vault-auth-portability work
> (`docs/plans/v1.10.0-vault-auth-portable.md`) ultimately retires (direct k8s-auth, no bridge).
> This bugfix hardens `refresh` in the meantime so the bridge self-heals.

---

## Reproduction

1. On the Mac, `launchctl bootout gui/$(id -u)/com.k3d-manager.vault-port-forward` (simulate it dying).
2. `make refresh CLUSTER_PROVIDER=k3s-hostinger` → completes "successfully".
3. `kubectl --context ubuntu-hostinger get clustersecretstore vault-backend` → **`Ready=False`**
   (`invalid vault credentials: ... context deadline exceeded`); nothing on the Mac listens on `18200`.
   **Expected:** refresh re-installs + loads the LaunchAgent, `18200` listens, CSS goes `Valid`.

---

## Fix

### Change 1 — `scripts/lib/providers/k3s-hostinger.sh`: declare the vault-port-forward plist vars

In `_hostinger_refresh_access_layer`, add the var declarations alongside the existing
`_grafana_pf_plist` / `_pushgateway_pf_plist` declarations.

**Exact old block (line ~530):**

```bash
  local _grafana_pf_plist="${HOME}/Library/LaunchAgents/com.k3d-manager.grafana-port-forward.plist"
```

**Exact new block:**

```bash
  local _grafana_pf_plist="${HOME}/Library/LaunchAgents/com.k3d-manager.grafana-port-forward.plist"
  local _vault_pf_label="com.k3d-manager.vault-port-forward"
  local _vault_pf_plist="${HOME}/Library/LaunchAgents/${_vault_pf_label}.plist"
  local _vault_pf_tmpl="${SCRIPT_DIR}/etc/launchd/${_vault_pf_label}.plist.tmpl"
```

> Confirm the exact text of the `_grafana_pf_plist` line on the branch before matching (it may
> differ in spacing). The three new `local` lines must land inside `_hostinger_refresh_access_layer`.

---

### Change 2 — `scripts/lib/providers/k3s-hostinger.sh`: install-if-missing + restart the LaunchAgent

Render the plist from its template when absent (mirroring `bin/cluster-up` step 4.1), then restart
it via the existing `_hostinger_restart_launchd` (which already does bootout→bootstrap and no-ops on
a missing plist). Add this immediately **before** the existing grafana restart block.

**Exact old block (line ~639):**

```bash
  _hostinger_restart_launchd \
    "com.k3d-manager.grafana-port-forward" \
    "${_grafana_pf_plist}" \
    user
```

**Exact new block:**

```bash
  if [[ ! -f "${_vault_pf_plist}" && -f "${_vault_pf_tmpl}" ]]; then
    _info "[k3s-hostinger] Vault port-forward plist missing — installing from template..."
    local _vault_pf_kubectl
    _vault_pf_kubectl="$(command -v kubectl)"
    mkdir -p "$(dirname "${_vault_pf_plist}")"
    sed \
      -e "s|{{KUBECTL_PATH}}|${_vault_pf_kubectl}|g" \
      -e "s|{{HOME}}|${HOME}|g" \
      "${_vault_pf_tmpl}" > "${_vault_pf_plist}"
  fi
  _hostinger_restart_launchd \
    "${_vault_pf_label}" \
    "${_vault_pf_plist}" \
    user
  _hostinger_restart_launchd \
    "com.k3d-manager.grafana-port-forward" \
    "${_grafana_pf_plist}" \
    user
```

> `_hostinger_restart_launchd` returns early if the plist is still missing (e.g. template absent),
> so the call is safe in all cases. The user-domain bootout/bootstrap matches how `cluster-up`
> loads it (`gui/$(id -u)`).

---

## Files Changed

| File | Change |
|------|--------|
| `scripts/lib/providers/k3s-hostinger.sh` | refresh now installs (if missing) + restarts `com.k3d-manager.vault-port-forward` |

---

## Rules

- `shellcheck -S warning scripts/lib/providers/k3s-hostinger.sh` — zero new warnings
- `bash -n scripts/lib/providers/k3s-hostinger.sh`
- `bats scripts/tests/lib/provider_contract.bats` — all pass (add a case asserting the refresh path
  references `com.k3d-manager.vault-port-forward` if the suite already stubs launchctl; otherwise
  a `grep` guard test is acceptable)
- `./scripts/k3d-manager _agent_audit` — exit 0
- Double-quote every expansion; no bare `sudo`; `--` before hyphen-bearing args
- No other files touched

---

## Definition of Done

- [ ] `_hostinger_refresh_access_layer` declares the vault-port-forward plist/label/template vars
- [ ] Refresh renders the plist from `scripts/etc/launchd/com.k3d-manager.vault-port-forward.plist.tmpl` when missing, then restarts it via `_hostinger_restart_launchd`
- [ ] `shellcheck` / `bash -n` / `provider_contract.bats` / `_agent_audit` all green
- [ ] Committed and pushed to `feat/v1.10.0-vault-auth-portable`
- [ ] memory-bank `activeContext.md` + `progress.md` updated with the commit SHA

**Commit message (exact):**
```
fix(hostinger): ensure vault-port-forward LaunchAgent on refresh
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `scripts/lib/providers/k3s-hostinger.sh` (+ its BATS test)
- Do NOT commit to `main` — work on `feat/v1.10.0-vault-auth-portable`
- Do NOT change the vault-bridge / socat / reverse-tunnel design — that is retired separately by the v1.10.0 vault-auth-portability spec
