#!/usr/bin/env bats
# scripts/tests/lib/provider_contract.bats
# Contract tests: every cluster provider must implement the full interface.

# shellcheck disable=SC1091

# Setup providers directory path
setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../.." && pwd)"
  PROVIDERS_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../lib/providers" && pwd)"
  SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../.." && pwd)/scripts"
  source "${REPO_ROOT}/scripts/lib/provider.sh"
  export SCRIPT_DIR
}

teardown_file() {
  # Clean up any potential leftover test clusters
  k3d cluster delete "k3d-test-orbstack-exists" 2>/dev/null || true
}

# --- K3D Provider Contract ---

@test "_acg_normalize_provider normalizes short aliases" {
  [[ "$(_acg_normalize_provider aws)" == "k3s-aws" ]]
  [[ "$(_acg_normalize_provider az)" == "k3s-az" ]]
  [[ "$(_acg_normalize_provider azure)" == "k3s-az" ]]
  [[ "$(_acg_normalize_provider gcp)" == "k3s-gcp" ]]
  [[ "$(_acg_normalize_provider oci)" == "k3s-oci" ]]
  [[ "$(_acg_normalize_provider foo)" == "foo" ]]
}

@test "_acg_provider_context maps providers to app contexts" {
  [[ "$(_acg_provider_context k3s-aws)" == "ubuntu-k3s" ]]
  [[ "$(_acg_provider_context k3s-az)" == "ubuntu-azure" ]]
  [[ "$(_acg_provider_context k3s-gcp)" == "ubuntu-gcp" ]]
  [[ "$(_acg_provider_context k3s-hostinger)" == "ubuntu-hostinger" ]]
  [[ "$(_acg_provider_context foo)" == "ubuntu-k3s" ]]
}

@test "_acg_resolve_provider prefers Hostinger when both providers are reachable" {
  _ACG_ACTIVE_PROVIDER_FILE="${BATS_TEST_TMPDIR}/active-provider"
  rm -f "${_ACG_ACTIVE_PROVIDER_FILE}"

  kubectl() {
    case "$*" in
      --context\ ubuntu-hostinger\ --request-timeout=5s\ get\ --raw=/readyz*) return 0 ;;
      --context\ ubuntu-k3s\ --request-timeout=5s\ get\ --raw=/readyz*) return 0 ;;
      --context\ ubuntu-azure\ --request-timeout=5s\ get\ --raw=/readyz*) return 1 ;;
      --context\ ubuntu-gcp\ --request-timeout=5s\ get\ --raw=/readyz*) return 1 ;;
      *) return 1 ;;
    esac
  }

  [[ "$(_acg_resolve_provider)" == "k3s-hostinger" ]]
}

@test "_acg_resolve_provider ignores a stale active-provider file" {
  _ACG_ACTIVE_PROVIDER_FILE="${BATS_TEST_TMPDIR}/active-provider"
  printf '%s\n' "k3s-hostinger" > "${_ACG_ACTIVE_PROVIDER_FILE}"

  kubectl() {
    case "$*" in
      --context\ ubuntu-hostinger\ --request-timeout=5s\ get\ --raw=/readyz*) return 1 ;;
      --context\ ubuntu-k3s\ --request-timeout=5s\ get\ --raw=/readyz*) return 0 ;;
      --context\ ubuntu-azure\ --request-timeout=5s\ get\ --raw=/readyz*) return 1 ;;
      --context\ ubuntu-gcp\ --request-timeout=5s\ get\ --raw=/readyz*) return 1 ;;
      *) return 1 ;;
    esac
  }

  [[ "$(_acg_resolve_provider)" == "k3s-aws" ]]
}

@test "_acg_resolve_provider prefers live Hostinger over a stale ACG active-provider file" {
  _ACG_ACTIVE_PROVIDER_FILE="${BATS_TEST_TMPDIR}/active-provider"
  printf '%s\n' "k3s-aws" > "${_ACG_ACTIVE_PROVIDER_FILE}"

  kubectl() {
    case "$*" in
      --context\ ubuntu-hostinger\ --request-timeout=5s\ get\ --raw=/readyz*) return 0 ;;
      --context\ ubuntu-k3s\ --request-timeout=5s\ get\ --raw=/readyz*) return 0 ;;
      --context\ ubuntu-azure\ --request-timeout=5s\ get\ --raw=/readyz*) return 1 ;;
      --context\ ubuntu-gcp\ --request-timeout=5s\ get\ --raw=/readyz*) return 1 ;;
      *) return 1 ;;
    esac
  }

  [[ "$(_acg_resolve_provider)" == "k3s-hostinger" ]]
}

@test "_acg_resolve_provider honors a live Hostinger active-provider file" {
  _ACG_ACTIVE_PROVIDER_FILE="${BATS_TEST_TMPDIR}/active-provider"
  printf '%s\n' "k3s-hostinger" > "${_ACG_ACTIVE_PROVIDER_FILE}"

  kubectl() {
    case "$*" in
      --context\ ubuntu-hostinger\ --request-timeout=5s\ get\ --raw=/readyz*) return 0 ;;
      --context\ ubuntu-k3s\ --request-timeout=5s\ get\ --raw=/readyz*) return 0 ;;
      --context\ ubuntu-azure\ --request-timeout=5s\ get\ --raw=/readyz*) return 1 ;;
      --context\ ubuntu-gcp\ --request-timeout=5s\ get\ --raw=/readyz*) return 1 ;;
      *) return 1 ;;
    esac
  }

  [[ "$(_acg_resolve_provider)" == "k3s-hostinger" ]]
}

@test "_hostinger_refresh_access_layer restarts argocd port-forward before cloudflared" {
  HOME="${BATS_TEST_TMPDIR}"
  _ACG_STATE_DIR="${BATS_TEST_TMPDIR}/state"
  mkdir -p "${_ACG_STATE_DIR}/bin" "${HOME}/Library/LaunchAgents" "${HOME}/.cloudflared"
  : > "${HOME}/.cloudflared/config.yml"
  printf '#!/usr/bin/env bash\nexit 0\n' > "${_ACG_STATE_DIR}/bin/argocd-port-forward.sh"
  chmod +x "${_ACG_STATE_DIR}/bin/argocd-port-forward.sh"
  : > "${HOME}/Library/LaunchAgents/com.k3d-manager.cloudflare-tunnel.plist"

  lsof() {
    case "$*" in
      *"-iTCP:8080"*) printf '%s\n' "41517" ;;
      *) return 1 ;;
    esac
  }

  kill() {
    printf '%s\n' "kill $*" >> "${BATS_TEST_TMPDIR}/restart.log"
  }

  brew() {
    case "$*" in
      services\ list)
        printf '%s\n' "cloudflared error 1 cliang ~/Library/LaunchAgents/homebrew.mxcl.cloudflared.plist"
        ;;
      services\ stop\ cloudflared)
        printf '%s\n' "brew $*" >> "${BATS_TEST_TMPDIR}/restart.log"
        ;;
      *)
        return 1
        ;;
    esac
  }

  pgrep() {
    case "$*" in
      *"${_ACG_STATE_DIR}/bin/argocd-port-forward.sh"*)
        printf '%s\n' "69478"
        ;;
      *)
        return 1
        ;;
    esac
  }

  uname() {
    printf '%s\n' Darwin
  }

  socat() {
    :
  }

  curl() {
    :
  }

  _info() {
    :
  }

  _warn() {
    :
  }

  source "${REPO_ROOT}/scripts/lib/providers/k3s-hostinger.sh"
  _hostinger_restart_launchd() {
    printf '%s\n' "$1" >> "${BATS_TEST_TMPDIR}/restart.log"
  }
  _hostinger_refresh_access_layer

  run grep -F 'port 8080 still in use — clearing stale listener(s) before retry' "${_ACG_STATE_DIR}/bin/argocd-port-forward.sh"
  [ "$status" -eq 0 ]
  run test -x "${_ACG_STATE_DIR}/bin/argocd-browser-https.sh"
  [ "$status" -eq 0 ]
  run test -x "${_ACG_STATE_DIR}/bin/frontend-browser-http.sh"
  [ "$status" -eq 0 ]
  run grep -F 'for (( _attempt=1; _attempt<=30; _attempt++ ))' "${_ACG_STATE_DIR}/bin/argocd-port-forward.sh"
  [ "$status" -eq 0 ]
  run grep -F 'sleep 30' "${_ACG_STATE_DIR}/bin/argocd-port-forward.sh"
  [ "$status" -eq 0 ]
  run grep -F 'LOCK_DIR=' "${_ACG_STATE_DIR}/bin/argocd-port-forward.sh"
  [ "$status" -eq 0 ]
  run grep -F '_acquire_lock' "${_ACG_STATE_DIR}/bin/argocd-port-forward.sh"
  [ "$status" -eq 0 ]
  run grep -F '_pf_alive()' "${_ACG_STATE_DIR}/bin/argocd-port-forward.sh"
  [ "$status" -eq 0 ]
  run grep -F 'if ! _pf_alive; then' "${_ACG_STATE_DIR}/bin/argocd-port-forward.sh"
  [ "$status" -eq 0 ]
  run grep -F '_pf_alive && {' "${_ACG_STATE_DIR}/bin/argocd-port-forward.sh"
  [ "$status" -eq 0 ]
  run grep -F 'tunnel' "${HOME}/Library/LaunchAgents/com.k3d-manager.cloudflare-tunnel.plist"
  [ "$status" -eq 0 ]
  run grep -F 'services stop cloudflared' "${BATS_TEST_TMPDIR}/restart.log"
  [ "$status" -eq 0 ]
  run grep -F -- '--context "ubuntu-hostinger" port-forward --address=127.0.0.2' "${_ACG_STATE_DIR}/bin/frontend-browser-http.sh"
  [ "$status" -eq 0 ]

  run cat "${BATS_TEST_TMPDIR}/restart.log"
  [ "$status" -eq 0 ]
  [[ "${output}" == *"kill 69478"* ]]
  [[ "${output}" == *"kill -9 69478"* ]]
  [[ "${output}" == *"kill 41517"* ]]
  [[ "${output}" == *"com.k3d-manager.argocd-port-forward"* ]]
  [[ "${output}" == *"com.k3d-manager.cloudflare-tunnel"* ]]
  [[ "${output}" == *"com.k3d-manager.argocd-browser-https"* ]]
}

@test "_provider_k3d_exec is defined" {
  source "${PROVIDERS_DIR}/k3d.sh"
  declare -f "_provider_k3d_exec" >/dev/null
}

@test "_provider_k3d_cluster_exists is defined" {
  source "${PROVIDERS_DIR}/k3d.sh"
  declare -f "_provider_k3d_cluster_exists" >/dev/null
}

@test "_provider_k3d_list_clusters is defined" {
  source "${PROVIDERS_DIR}/k3d.sh"
  declare -f "_provider_k3d_list_clusters" >/dev/null
}

@test "_provider_k3d_apply_cluster_config is defined" {
  source "${PROVIDERS_DIR}/k3d.sh"
  declare -f "_provider_k3d_apply_cluster_config" >/dev/null
}

@test "_provider_k3d_install is defined" {
  source "${PROVIDERS_DIR}/k3d.sh"
  declare -f "_provider_k3d_install" >/dev/null
}

@test "_provider_k3d_create_cluster is defined" {
  source "${PROVIDERS_DIR}/k3d.sh"
  declare -f "_provider_k3d_create_cluster" >/dev/null
}

@test "_provider_k3d_destroy_cluster is defined" {
  source "${PROVIDERS_DIR}/k3d.sh"
  declare -f "_provider_k3d_destroy_cluster" >/dev/null
}

@test "_provider_k3d_deploy_cluster is defined" {
  source "${PROVIDERS_DIR}/k3d.sh"
  declare -f "_provider_k3d_deploy_cluster" >/dev/null
}

@test "_provider_k3d_configure_istio is defined" {
  source "${PROVIDERS_DIR}/k3d.sh"
  declare -f "_provider_k3d_configure_istio" >/dev/null
}

@test "_provider_k3d_expose_ingress is defined" {
  source "${PROVIDERS_DIR}/k3d.sh"
  declare -f "_provider_k3d_expose_ingress" >/dev/null
}

# --- K3S Provider Contract ---

@test "_provider_k3s_exec is defined" {
  source "${PROVIDERS_DIR}/k3s.sh"
  declare -f "_provider_k3s_exec" >/dev/null
}

@test "_provider_k3s_cluster_exists is defined" {
  source "${PROVIDERS_DIR}/k3s.sh"
  declare -f "_provider_k3s_cluster_exists" >/dev/null
}

@test "_provider_k3s_list_clusters is defined" {
  source "${PROVIDERS_DIR}/k3s.sh"
  declare -f "_provider_k3s_list_clusters" >/dev/null
}

@test "_provider_k3s_apply_cluster_config is defined" {
  source "${PROVIDERS_DIR}/k3s.sh"
  declare -f "_provider_k3s_apply_cluster_config" >/dev/null
}

@test "_provider_k3s_install is defined" {
  source "${PROVIDERS_DIR}/k3s.sh"
  declare -f "_provider_k3s_install" >/dev/null
}

@test "_provider_k3s_create_cluster is defined" {
  source "${PROVIDERS_DIR}/k3s.sh"
  declare -f "_provider_k3s_create_cluster" >/dev/null
}

@test "_provider_k3s_destroy_cluster is defined" {
  source "${PROVIDERS_DIR}/k3s.sh"
  declare -f "_provider_k3s_destroy_cluster" >/dev/null
}

@test "_provider_k3s_deploy_cluster is defined" {
  source "${PROVIDERS_DIR}/k3s.sh"
  declare -f "_provider_k3s_deploy_cluster" >/dev/null
}

@test "_provider_k3s_configure_istio is defined" {
  source "${PROVIDERS_DIR}/k3s.sh"
  declare -f "_provider_k3s_configure_istio" >/dev/null
}

@test "_provider_k3s_expose_ingress is defined" {
  source "${PROVIDERS_DIR}/k3s.sh"
  declare -f "_provider_k3s_expose_ingress" >/dev/null
}

# --- OrbStack Provider Contract ---

@test "_provider_orbstack_exec is defined" {
  source "${PROVIDERS_DIR}/orbstack.sh"
  declare -f "_provider_orbstack_exec" >/dev/null
}

@test "_provider_orbstack_cluster_exists is defined" {
  source "${PROVIDERS_DIR}/orbstack.sh"
  declare -f "_provider_orbstack_cluster_exists" >/dev/null
}

@test "_provider_orbstack_list_clusters is defined" {
  source "${PROVIDERS_DIR}/orbstack.sh"
  declare -f "_provider_orbstack_list_clusters" >/dev/null
}

@test "_provider_orbstack_apply_cluster_config is defined" {
  source "${PROVIDERS_DIR}/orbstack.sh"
  declare -f "_provider_orbstack_apply_cluster_config" >/dev/null
}

@test "_provider_orbstack_install is defined" {
  source "${PROVIDERS_DIR}/orbstack.sh"
  declare -f "_provider_orbstack_install" >/dev/null
}

@test "_provider_orbstack_create_cluster is defined" {
  source "${PROVIDERS_DIR}/orbstack.sh"
  declare -f "_provider_orbstack_create_cluster" >/dev/null
}

@test "_provider_orbstack_destroy_cluster is defined" {
  source "${PROVIDERS_DIR}/orbstack.sh"
  declare -f "_provider_orbstack_destroy_cluster" >/dev/null
}

@test "_provider_orbstack_deploy_cluster is defined" {
  source "${PROVIDERS_DIR}/orbstack.sh"
  declare -f "_provider_orbstack_deploy_cluster" >/dev/null
}

@test "_provider_orbstack_configure_istio is defined" {
  source "${PROVIDERS_DIR}/orbstack.sh"
  declare -f "_provider_orbstack_configure_istio" >/dev/null
}

@test "_provider_orbstack_expose_ingress is defined" {
  source "${PROVIDERS_DIR}/orbstack.sh"
  declare -f "_provider_orbstack_expose_ingress" >/dev/null
}
