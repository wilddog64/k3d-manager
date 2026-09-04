#!/usr/bin/env bats
# scripts/tests/lib/provider_active_set.bats
# v1.28.0 parallel-multi-cloud: active-provider SET semantics + flat-state migration.

# shellcheck disable=SC1091

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../.." && pwd)"
  SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../.." && pwd)/scripts"
  _info() { :; }
  _warn() { :; }
  source "${REPO_ROOT}/scripts/lib/provider.sh"
  export SCRIPT_DIR
  _ACG_ACTIVE_PROVIDER_FILE="${BATS_TEST_TMPDIR}/active-provider"
  _ACG_ACTIVE_PROVIDERS_DIR="${BATS_TEST_TMPDIR}/active-providers"
  unset CLUSTER_PROVIDER
}

# --- register / list / unrecord ---

@test "_acg_record_provider writes a set marker and the legacy scalar" {
  _acg_record_provider k3s-aws
  [[ -f "${_ACG_ACTIVE_PROVIDERS_DIR}/k3s-aws" ]]
  [[ "$(cat "${_ACG_ACTIVE_PROVIDER_FILE}")" == "k3s-aws" ]]
}

@test "_acg_record_provider normalizes aliases into the set" {
  _acg_record_provider hostinger
  [[ -f "${_ACG_ACTIVE_PROVIDERS_DIR}/k3s-hostinger" ]]
}

@test "_acg_list_active_providers lists every live marker" {
  _acg_record_provider k3s-aws
  _acg_record_provider k3s-hostinger
  run _acg_list_active_providers
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"k3s-aws"* ]]
  [[ "${output}" == *"k3s-hostinger"* ]]
}

@test "_acg_unrecord_provider removes only its own marker; siblings survive" {
  _acg_record_provider k3s-aws
  _acg_record_provider k3s-hostinger
  _acg_unrecord_provider k3s-hostinger
  [[ ! -e "${_ACG_ACTIVE_PROVIDERS_DIR}/k3s-hostinger" ]]
  [[ -f "${_ACG_ACTIVE_PROVIDERS_DIR}/k3s-aws" ]]
}

@test "_acg_unrecord_provider clears the legacy scalar only when it names that provider" {
  _acg_record_provider k3s-aws          # scalar now = k3s-aws
  _acg_record_provider k3s-hostinger    # scalar now = k3s-hostinger
  _acg_unrecord_provider k3s-aws        # scalar names hostinger, not aws
  [[ "$(cat "${_ACG_ACTIVE_PROVIDER_FILE}")" == "k3s-hostinger" ]]
  _acg_unrecord_provider k3s-hostinger  # scalar names hostinger -> cleared
  [[ ! -e "${_ACG_ACTIVE_PROVIDER_FILE}" ]]
}

@test "_acg_list_active_providers falls back to the legacy scalar when no dir markers" {
  printf '%s\n' "k3s-aws" > "${_ACG_ACTIVE_PROVIDER_FILE}"
  run _acg_list_active_providers
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == "k3s-aws" ]]
}

# --- resolver: set-aware fallback (no reachable context, CLUSTER_PROVIDER unset) ---

_stub_kubectl_all_unreachable() {
  kubectl() { return 1; }
}

@test "_acg_resolve_provider uses the single live set member when offline" {
  _stub_kubectl_all_unreachable
  _acg_record_provider k3s-aws
  rm -f "${_ACG_ACTIVE_PROVIDER_FILE}"   # prove the SET, not the scalar, drives it
  [[ "$(_acg_resolve_provider)" == "k3s-aws" ]]
}

@test "_acg_resolve_provider on multiple live members falls back to the legacy scalar" {
  _stub_kubectl_all_unreachable
  _acg_record_provider k3s-aws
  _acg_record_provider k3s-hostinger     # scalar last-written = k3s-hostinger
  [[ "$(_acg_resolve_provider)" == "k3s-hostinger" ]]
}

@test "_acg_resolve_provider back-compat: legacy scalar only, no dir, resolves it" {
  _stub_kubectl_all_unreachable
  printf '%s\n' "k3s-aws" > "${_ACG_ACTIVE_PROVIDER_FILE}"
  [[ "$(_acg_resolve_provider)" == "k3s-aws" ]]
}

@test "_acg_resolve_provider defaults to k3s-hostinger with no set and no scalar" {
  _stub_kubectl_all_unreachable
  [[ "$(_acg_resolve_provider)" == "k3s-hostinger" ]]
}

# --- flat-state migration ---

@test "_acg_migrate_flat_state moves flat state under the legacy owner" {
  local base="${BATS_TEST_TMPDIR}/state"
  mkdir -p "${base}/run" "${base}/logs" "${base}/checkpoints"
  printf 'pid\n' > "${base}/run/vault-pf.pid"
  printf '%s\n' "k3s-hostinger" > "${base}/active-provider"
  _acg_migrate_flat_state "${base}" "k3s-aws"
  [[ -f "${base}/k3s-hostinger/run/vault-pf.pid" ]]
  [[ ! -e "${base}/run" ]]
}

@test "_acg_migrate_flat_state uses the run provider when no legacy owner marker" {
  local base="${BATS_TEST_TMPDIR}/state"
  mkdir -p "${base}/logs"
  _acg_migrate_flat_state "${base}" "k3s-aws"
  [[ -d "${base}/k3s-aws/logs" ]]
}

@test "_acg_migrate_flat_state is a no-op when there is no flat state" {
  local base="${BATS_TEST_TMPDIR}/state"
  mkdir -p "${base}"
  _acg_migrate_flat_state "${base}" "k3s-aws"
  [[ ! -e "${base}/k3s-aws" ]]
}

@test "_acg_migrate_flat_state skips when the target subdir already exists" {
  local base="${BATS_TEST_TMPDIR}/state"
  mkdir -p "${base}/run" "${base}/k3s-aws"
  printf 'pid\n' > "${base}/run/vault-pf.pid"
  _acg_migrate_flat_state "${base}" "k3s-aws"
  [[ -f "${base}/run/vault-pf.pid" ]]          # left in place, not moved
  [[ ! -e "${base}/k3s-aws/run" ]]
}
