# Bugfix: Vault Auth Already Enabled, Observability ConfigMap Get Exit, and Secret Leak

**Classification:** Bugfix in `docs/bugs/` (exempt from the max-5-plan limit).

## Problem

During `make refresh CLUSTER_PROVIDER=k3s-hostinger`, the refresh execution fails with:
1. `_observability_remove_argocd_dashboard` calls `_kubectl` without `--no-exit`. If the target ConfigMap `grafana-dashboard-argocd` does not exist on the cluster node, `_kubectl` returns non-zero and aborts the refresh immediately with Error 1.
2. `configure_vault_app_auth` calls `_vault_exec` without `--no-exit` on `vault auth enable -path=kubernetes-app kubernetes`. If `kubernetes-app` is already enabled, the Vault CLI exits with code 2. The script then terminates immediately, and the `|| true` fallback is dead code.
3. The command tracing error output prints the raw `VAULT_TOKEN=hvs...` secret to the console logs because `_run_command_handle_failure` prints all arguments verbatim on failure without filtering sensitive tokens (such as inline environment variable assignments).

## Fix

1. **Fix `_observability_remove_argocd_dashboard` in `scripts/plugins/observability.sh`**:
   Add `--no-exit` to both `_kubectl` commands inside the function so that if the configmap is absent or delete fails, the refresh continues successfully.
2. **Fix `configure_vault_app_auth` in `scripts/plugins/vault.sh`**:
   Check if the custom auth mount path is already enabled via `vault auth list` before attempting to enable it. Also prefix the `_vault_exec` call with `--no-exit`.
3. **Fix Secret Leak and tracing in `scripts/lib/system_overrides.sh`**:
   - Override `_args_have_sensitive_flag` to identify `*VAULT_TOKEN=*` as a sensitive argument.
   - Override `_run_command_handle_failure` to check if `_args_have_sensitive_flag` is true for the arguments. If true, set `cmd_str="[redacted command containing secrets]"` and set `quiet=1` to suppress printing of the raw command containing the token to the console logs.

---

## Files

- `scripts/plugins/observability.sh` (edit)
- `scripts/plugins/vault.sh` (edit)
- `scripts/lib/system_overrides.sh` (edit)
- `scripts/tests/plugins/observability_no_exit_remove.bats` (new)
- `scripts/tests/plugins/vault_app_auth_enable_idempotent.bats` (new)

---

## Changes

### 1. `scripts/plugins/observability.sh`

Replace the implementation of `_observability_remove_argocd_dashboard` (lines ~232-240) with:

```bash
function _observability_remove_argocd_dashboard() {
  local _app_context
  _app_context="$(_observability_acg_context "${1:-}")"
  if _kubectl --no-exit --context "${_app_context}" -n monitoring get configmap grafana-dashboard-argocd >/dev/null 2>&1; then
    _kubectl --no-exit --context "${_app_context}" -n monitoring delete configmap grafana-dashboard-argocd >/dev/null \
      && _info "[observability] Removed stale ArgoCD/Image Updater dashboard from ${_app_context}"
  fi
}
```

### 2. `scripts/plugins/vault.sh`

In `configure_vault_app_auth` (lines ~1662-1664), replace:

```bash
  # b. Enable kubernetes auth mount (idempotent)
  _vault_exec "$ns" "vault auth enable -path=${mount} kubernetes" "$release" || true
```

with:

```bash
  # b. Enable kubernetes auth mount (idempotent)
  local auth_json=""
  auth_json=$(_vault_exec --no-exit "$ns" "vault auth list -format=json" "$release" 2>/dev/null || true)
  if [[ -z "$auth_json" ]] || ! printf '%s' "$auth_json" | jq -e --arg PATH "${mount}/" 'has($PATH)' >/dev/null 2>&1; then
     _vault_exec --no-exit "$ns" "vault auth enable -path=${mount} kubernetes" "$release" || true
  fi
```

### 3. `scripts/lib/system_overrides.sh`

Append the following re-definitions to the end of the file:

```bash
if declare -f _args_have_sensitive_flag >/dev/null 2>&1 && ! declare -f __k3dm_base_args_have_sensitive_flag >/dev/null 2>&1; then
  eval "$(declare -f _args_have_sensitive_flag | sed '1s/_args_have_sensitive_flag/__k3dm_base_args_have_sensitive_flag/')"

  _args_have_sensitive_flag() {
    local arg
    local expect_secret=0

    for arg in "$@"; do
      if (( expect_secret )); then
        return 0
      fi
      case "$arg" in
        --password|--token|--username)
          expect_secret=1
          ;;
        --password=*|--token=*|--username=*|*VAULT_TOKEN=*)
          return 0
          ;;
      esac
    done

    return 1
  }
fi

if declare -f _run_command_handle_failure >/dev/null 2>&1 && ! declare -f __k3dm_base_run_command_handle_failure >/dev/null 2>&1; then
  eval "$(declare -f _run_command_handle_failure | sed '1s/_run_command_handle_failure/__k3dm_base_run_command_handle_failure/')"

  _run_command_handle_failure() {
    local prog="$1" rc="$2" quiet="$3" soft="$4"
    shift 4
    local cmd_str=""
    if _args_have_sensitive_flag "$@"; then
      cmd_str="[redacted command containing secrets]"
      quiet=1
    else
      printf -v cmd_str '%q ' "$@"
    fi

    if (( quiet == 0 )); then
      printf '%s command failed (%d): ' "$prog" "$rc" >&2
      printf '%q ' "$@" >&2
      printf '\n' >&2
    fi

    if (( soft )); then
      return "$rc"
    else
      _err "failed to execute ${cmd_str% }: $rc"
    fi
  }
fi
```
