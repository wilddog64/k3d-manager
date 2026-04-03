# P2: `deploy_eso` Passes Wrong Namespace to Remote SecretStore

**Date:** 2026-03-02
**Reported:** Codex bot review comment on PR #8
**Status:** FIXED — `_eso_configure_remote_vault` now receives the caller namespace
**Severity:** P2
**Type:** Bug — namespace mismatch in cross-cluster SecretStore configuration

---

## What Was Reported

The Codex bot flagged that when `REMOTE_VAULT_ADDR` is set, `deploy_eso` calls
`_eso_configure_remote_vault` with `${ESO_REMOTE_SERVICE_ACCOUNT_NAMESPACE:-${ESO_NAMESPACE:-secrets}}`
as the service-account namespace. This ignores the actual `$ns` argument that
`deploy_eso` was invoked with, causing the SecretStore to point at the wrong
service-account namespace when a custom namespace is passed.

---

## Root Cause

**File:** `scripts/plugins/eso.sh`

```bash
function deploy_eso() {
  local ns="${1:-${ESO_NAMESPACE:-secrets}}"   # line 16 — ns comes from arg or env
  ...
  if [[ -n "${REMOTE_VAULT_ADDR:-}" ]]; then
    _eso_configure_remote_vault "${ESO_REMOTE_SECRETSTORE_NAME:-remote-vault-store}" \
      "${ESO_REMOTE_SERVICE_ACCOUNT:-external-secrets}" \
      "${ESO_REMOTE_SERVICE_ACCOUNT_NAMESPACE:-${ESO_NAMESPACE:-secrets}}"  # line 101 — WRONG
  fi
}
```

The fallback `${ESO_NAMESPACE:-secrets}` on line 101 does not use `$ns`.
If a caller runs `deploy_eso custom-ns` without exporting `ESO_NAMESPACE`, the
generated `(Cluster)SecretStore` will reference the `external-secrets` service
account in namespace `secrets` — not `custom-ns` where ESO was actually installed.
Vault Kubernetes auth will then fail because the service account token comes from
the wrong namespace.

---

## Fix

Replace `${ESO_NAMESPACE:-secrets}` with `$ns` in the fallback so the installed
namespace is used when `ESO_REMOTE_SERVICE_ACCOUNT_NAMESPACE` is not explicitly set.

**Exact change in `scripts/plugins/eso.sh` line 101:**

```bash
# Before:
      "${ESO_REMOTE_SERVICE_ACCOUNT_NAMESPACE:-${ESO_NAMESPACE:-secrets}}"

# After:
      "${ESO_REMOTE_SERVICE_ACCOUNT_NAMESPACE:-${ns}}"
```

No other changes needed.

---

## Resolution & Verification (2026-03-02)

- Updated `scripts/plugins/eso.sh` to pass the resolved `ns` argument to
  `_eso_configure_remote_vault` whenever the remote namespace override is left
  unset, so ESO installs in custom namespaces wire the SecretStore to the
  correct service account.
- Re-ran the plugin unit tests via
  `PATH="/opt/homebrew/bin:$PATH" bats scripts/tests/plugins/eso.bats` — all cases
  (usage, skip, fresh install, and airgapped chart) passed, confirming no
  regressions in the helm/namespace flow.

---

## Risk Assessment

| Factor | Assessment |
|---|---|
| Correctness | Remote Vault auth fails when `deploy_eso` is called with a custom namespace and `ESO_NAMESPACE` is not exported |
| Scope | Only the `REMOTE_VAULT_ADDR` code path in `deploy_eso` |
| Fix risk | Minimal — one-line change, uses the `$ns` variable already in scope |
| Severity | P2 — only affects cross-cluster (app cluster) deployments with non-default namespace |
