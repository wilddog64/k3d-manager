#!/usr/bin/env bats

setup() {
  VARS_SH="${BATS_TEST_DIRNAME}/../../etc/vault/vars.sh"
  export HUB_VAULT_PROFILE_STATE_FILE="${BATS_TEST_TMPDIR}/no-such-hub-profile"
}

@test "default (laptop) profile uses the bridge endpoint" {
  unset HUB_VAULT_PROFILE HUB_VAULT_CSS_SERVER HUB_VAULT_USE_BRIDGE VAULT_NS
  # shellcheck disable=SC1090
  source "${VARS_SH}"
  [ "${HUB_VAULT_PROFILE}" = "laptop" ]
  [ "${HUB_VAULT_CSS_SERVER}" = "http://vault-bridge.secrets.svc.cluster.local:8201" ]
  [ "${HUB_VAULT_USE_BRIDGE}" = "1" ]
}

@test "hostinger profile uses the in-cluster endpoint and disables the bridge" {
  unset HUB_VAULT_CSS_SERVER HUB_VAULT_USE_BRIDGE
  export HUB_VAULT_PROFILE="hostinger" VAULT_NS="secrets"
  # shellcheck disable=SC1090
  source "${VARS_SH}"
  [ "${HUB_VAULT_CSS_SERVER}" = "http://vault.secrets.svc:8200" ]
  [ "${HUB_VAULT_USE_BRIDGE}" = "0" ]
}

@test "explicit overrides win over profile defaults" {
  export HUB_VAULT_PROFILE="hostinger" HUB_VAULT_CSS_SERVER="http://example:8200" HUB_VAULT_USE_BRIDGE="1"
  # shellcheck disable=SC1090
  source "${VARS_SH}"
  [ "${HUB_VAULT_CSS_SERVER}" = "http://example:8200" ]
  [ "${HUB_VAULT_USE_BRIDGE}" = "1" ]
}

@test "laptop profile derives token CSS auth" {
  unset HUB_VAULT_PROFILE HUB_VAULT_CSS_AUTH VAULT_NS
  # shellcheck disable=SC1090
  source "${VARS_SH}"
  [ "${HUB_VAULT_CSS_AUTH}" = "token" ]
}

@test "hostinger profile derives kubernetes CSS auth" {
  unset HUB_VAULT_CSS_AUTH
  export HUB_VAULT_PROFILE="hostinger" VAULT_NS="secrets"
  # shellcheck disable=SC1090
  source "${VARS_SH}"
  [ "${HUB_VAULT_CSS_AUTH}" = "kubernetes" ]
}

@test "persisted state file selects the profile when env is unset" {
  unset HUB_VAULT_PROFILE HUB_VAULT_CSS_SERVER HUB_VAULT_USE_BRIDGE HUB_VAULT_CSS_AUTH
  export HUB_VAULT_PROFILE_STATE_FILE="${BATS_TEST_TMPDIR}/hub-profile"
  printf 'hostinger\n' > "${HUB_VAULT_PROFILE_STATE_FILE}"
  export VAULT_NS="secrets"
  # shellcheck disable=SC1090
  source "${VARS_SH}"
  [ "${HUB_VAULT_PROFILE}" = "hostinger" ]
  [ "${HUB_VAULT_USE_BRIDGE}" = "0" ]
}

@test "explicit env wins over the persisted state file" {
  export HUB_VAULT_PROFILE="laptop"
  export HUB_VAULT_PROFILE_STATE_FILE="${BATS_TEST_TMPDIR}/hub-profile"
  printf 'hostinger\n' > "${HUB_VAULT_PROFILE_STATE_FILE}"
  unset HUB_VAULT_CSS_SERVER HUB_VAULT_USE_BRIDGE HUB_VAULT_CSS_AUTH
  # shellcheck disable=SC1090
  source "${VARS_SH}"
  [ "${HUB_VAULT_PROFILE}" = "laptop" ]
  [ "${HUB_VAULT_USE_BRIDGE}" = "1" ]
}

@test "app context uses its own persisted profile instead of the legacy global file" {
  unset HUB_VAULT_PROFILE HUB_VAULT_CSS_SERVER HUB_VAULT_USE_BRIDGE HUB_VAULT_CSS_AUTH HUB_VAULT_PROFILE_STATE_FILE
  export K3DM_STATE_DIR="${BATS_TEST_TMPDIR}"
  export APP_CONTEXT="ubuntu-k3s"
  printf 'hostinger\n' > "${BATS_TEST_TMPDIR}/hub-vault-profile"
  printf 'laptop\n' > "${BATS_TEST_TMPDIR}/hub-vault-profile-ubuntu-k3s"
  # shellcheck disable=SC1090
  source "${VARS_SH}"
  [ "${HUB_VAULT_PROFILE}" = "laptop" ]
  [ "${HUB_VAULT_PROFILE_STATE_FILE}" = "${BATS_TEST_TMPDIR}/hub-vault-profile-ubuntu-k3s" ]
}

@test "hostinger context falls back to the legacy global file for backward compatibility" {
  unset HUB_VAULT_PROFILE HUB_VAULT_CSS_SERVER HUB_VAULT_USE_BRIDGE HUB_VAULT_CSS_AUTH HUB_VAULT_PROFILE_STATE_FILE
  export K3DM_STATE_DIR="${BATS_TEST_TMPDIR}"
  export APP_CONTEXT="ubuntu-hostinger"
  printf 'hostinger\n' > "${BATS_TEST_TMPDIR}/hub-vault-profile"
  # shellcheck disable=SC1090
  source "${VARS_SH}"
  [ "${HUB_VAULT_PROFILE}" = "hostinger" ]
  [ "${HUB_VAULT_PROFILE_STATE_FILE}" = "${BATS_TEST_TMPDIR}/hub-vault-profile" ]
}

@test "per-context CSS override applies when base env is unset" {
  unset HUB_VAULT_PROFILE HUB_VAULT_CSS_SERVER HUB_VAULT_USE_BRIDGE HUB_VAULT_CSS_AUTH HUB_VAULT_PROFILE_STATE_FILE
  export K3DM_STATE_DIR="${BATS_TEST_TMPDIR}"
  export APP_CONTEXT="ubuntu-hostinger"
  export HUB_VAULT_CSS_SERVER__ubuntu_hostinger="http://percontext:8200"
  # shellcheck disable=SC1090
  source "${VARS_SH}"
  [ "${HUB_VAULT_CSS_SERVER}" = "http://percontext:8200" ]
}

@test "explicit base env CSS wins over a per-context override" {
  unset HUB_VAULT_PROFILE HUB_VAULT_USE_BRIDGE HUB_VAULT_CSS_AUTH HUB_VAULT_PROFILE_STATE_FILE
  export K3DM_STATE_DIR="${BATS_TEST_TMPDIR}"
  export APP_CONTEXT="ubuntu-hostinger"
  export HUB_VAULT_CSS_SERVER="http://baseenv:8200"
  export HUB_VAULT_CSS_SERVER__ubuntu_hostinger="http://percontext:8200"
  # shellcheck disable=SC1090
  source "${VARS_SH}"
  [ "${HUB_VAULT_CSS_SERVER}" = "http://baseenv:8200" ]
}

@test "without a per-context override the profile default is used" {
  unset HUB_VAULT_PROFILE HUB_VAULT_CSS_SERVER HUB_VAULT_USE_BRIDGE HUB_VAULT_CSS_AUTH HUB_VAULT_PROFILE_STATE_FILE
  export K3DM_STATE_DIR="${BATS_TEST_TMPDIR}"
  export APP_CONTEXT="ubuntu-hostinger"
  export VAULT_NS="secrets"
  # shellcheck disable=SC1090
  source "${VARS_SH}"
  [ "${HUB_VAULT_CSS_SERVER}" = "http://vault-bridge.secrets.svc.cluster.local:8201" ]
}

@test "per-context overrides apply to bridge and auth with a sanitized context key" {
  unset HUB_VAULT_PROFILE HUB_VAULT_CSS_SERVER HUB_VAULT_USE_BRIDGE HUB_VAULT_CSS_AUTH HUB_VAULT_PROFILE_STATE_FILE
  export K3DM_STATE_DIR="${BATS_TEST_TMPDIR}"
  export APP_CONTEXT="k3s-gcp"
  export HUB_VAULT_USE_BRIDGE__k3s_gcp="0"
  export HUB_VAULT_CSS_AUTH__k3s_gcp="kubernetes"
  # shellcheck disable=SC1090
  source "${VARS_SH}"
  [ "${HUB_VAULT_USE_BRIDGE}" = "0" ]
  [ "${HUB_VAULT_CSS_AUTH}" = "kubernetes" ]
}
