#!/usr/bin/env bats
# scripts/tests/lib/provider_contract.bats
# Contract tests: every cluster provider must implement the full interface.

# shellcheck disable=SC1091

# Setup providers directory path
setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../.." && pwd)"
  PROVIDERS_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../lib/providers" && pwd)"
  SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../.." && pwd)/scripts"
  _info() { :; }
  _warn() { :; }
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

@test "_hostinger_set_active_app_cluster targets the hub context for relabel" {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
  source "${REPO_ROOT}/scripts/lib/providers/k3s-hostinger.sh"

  _HOSTINGER_KUBE_CONTEXT="ubuntu-hostinger"
  ARGOCD_NAMESPACE="cicd"
  _argocd_hub_kubectl_cmd() {
    printf '%s\n' "kubectl --context k3d-k3d-cluster"
  }
  _hostinger_load_argocd_plugin() {
    :
  }

  kubectl() {
    case "$*" in
      --context\ k3d-k3d-cluster\ get\ secrets\ -n\ cicd\ -l\ argocd.argoproj.io/secret-type=cluster\ -o\ name)
        printf '%s\n' 'secret/cluster-ubuntu-hostinger'
        printf '%s\n' 'secret/cluster-ubuntu-k3s'
        ;;
      --context\ k3d-k3d-cluster\ get\ secret/cluster-ubuntu-hostinger\ -n\ cicd\ -o\ jsonpath=\{.metadata.labels.argocd\\.argoproj\\.io/cluster-name\})
        printf '%s' 'ubuntu-hostinger'
        ;;
      --context\ k3d-k3d-cluster\ get\ secret/cluster-ubuntu-k3s\ -n\ cicd\ -o\ jsonpath=\{.metadata.labels.argocd\\.argoproj\\.io/cluster-name\})
        printf '%s' 'ubuntu-k3s'
        ;;
      --context\ k3d-k3d-cluster\ label\ secret/cluster-ubuntu-hostinger\ -n\ cicd\ k3d-manager/role=app-cluster\ --overwrite)
        printf '%s\n' "$*" >> "${BATS_TEST_TMPDIR}/kubectl.log"
        return 0
        ;;
      --context\ k3d-k3d-cluster\ label\ secret/cluster-ubuntu-k3s\ -n\ cicd\ k3d-manager/role-)
        printf '%s\n' "$*" >> "${BATS_TEST_TMPDIR}/kubectl.log"
        return 0
        ;;
      *)
        return 1
        ;;
    esac
  }

  _info() {
    :
  }

  _hostinger_set_active_app_cluster

  run cat "${BATS_TEST_TMPDIR}/kubectl.log"
  [ "$status" -eq 0 ]
  [[ "${output}" == *"--context k3d-k3d-cluster label secret/cluster-ubuntu-hostinger -n cicd k3d-manager/role=app-cluster --overwrite"* ]]
  [[ "${output}" == *"--context k3d-k3d-cluster label secret/cluster-ubuntu-k3s -n cicd k3d-manager/role-"* ]]
}

@test "_hostinger_register_cluster routes through register_app_cluster labels" {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
  export PLUGINS_DIR="${REPO_ROOT}/scripts/plugins"
  _warn() { :; }
  _err() { printf '%s\n' "$*" >&2; return 1; }
  _cleanup_trap_command() { printf 'rm -f %q' "$1"; }
  source "${REPO_ROOT}/scripts/plugins/argocd.sh"
  source "${REPO_ROOT}/scripts/lib/providers/k3s-hostinger.sh"

  _HOSTINGER_KUBE_CONTEXT="ubuntu-hostinger"
  ARGOCD_NAMESPACE="cicd"
  ARGOCD_CHART_VERSION="7.8.1"
  _argocd_hub_kubectl_cmd() {
    printf '%s\n' "kubectl --context k3d-k3d-cluster"
  }
  _hostinger_ensure_argocd_manager_sa() {
    :
  }

  kubectl() {
    case "$*" in
      config\ view\ --raw\ -o\ jsonpath=\{.clusters\[\?\(@.name==\"ubuntu-hostinger\"\)\].cluster.server\})
        printf '%s' 'https://2.25.146.252:6443'
        ;;
      config\ view\ --raw\ -o\ jsonpath=\{.clusters\[\?\(@.name==\"ubuntu-hostinger\"\)\].cluster.certificate-authority-data\})
        printf '%s' 'ca-data'
        ;;
      --context\ ubuntu-hostinger\ create\ token\ argocd-manager\ -n\ kube-system\ --duration=8760h)
        printf '%s' 'hostinger-token'
        ;;
      --context\ k3d-k3d-cluster\ apply\ -f\ *)
        printf '%s\n' "$*" >> "${BATS_TEST_TMPDIR}/kubectl.log"
        local file="${*: -1}"
        cp "${file}" "${BATS_TEST_TMPDIR}/rendered-secret.yaml"
        return 0
        ;;
      --context\ k3d-k3d-cluster\ get\ secrets\ -n\ cicd\ -l\ argocd.argoproj.io/secret-type=cluster\ -o\ name)
        printf '%s\n' 'secret/cluster-ubuntu-hostinger'
        ;;
      --context\ k3d-k3d-cluster\ get\ secret/cluster-ubuntu-hostinger\ -n\ cicd\ -o\ jsonpath=\{.metadata.labels.argocd\\.argoproj\\.io/cluster-name\})
        printf '%s' 'ubuntu-hostinger'
        ;;
      --context\ k3d-k3d-cluster\ label\ secret/cluster-ubuntu-hostinger\ -n\ cicd\ k3d-manager/role=app-cluster\ --overwrite)
        printf '%s\n' "$*" >> "${BATS_TEST_TMPDIR}/kubectl.log"
        return 0
        ;;
      *)
        return 1
        ;;
    esac
  }

  _info() {
    :
  }

  run _hostinger_register_cluster
  [ "$status" -eq 0 ]

  run cat "${BATS_TEST_TMPDIR}/rendered-secret.yaml"
  [ "$status" -eq 0 ]
  [[ "${output}" == *'environment: "dev"'* ]]
  [[ "${output}" == *'argocd-chart-version: "7.8.1"'* ]]
  [[ "${output}" == *'argocd-replicas: "2"'* ]]
  [[ "${output}" == *'"caData": "ca-data"'* ]]
  [[ "${output}" == *'"insecure": false'* ]]
  [[ "${output}" != *'"insecure": true'* ]]
}

@test "_provider_k3s_hostinger_refresh_cluster reapplies observability on the hostinger context" {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
  source "${REPO_ROOT}/scripts/lib/providers/k3s-hostinger.sh"

  _HOSTINGER_KUBECONFIG="${BATS_TEST_TMPDIR}/hostinger.config"
  : > "${_HOSTINGER_KUBECONFIG}"

  _hostinger_require_host() { printf '%s\n' "srv1754834.hstgr.cloud"; }
  _hostinger_merge_kubeconfig() { printf '%s\n' "merge" >> "${BATS_TEST_TMPDIR}/refresh.log"; }
  _hostinger_register_cluster() { printf '%s\n' "register" >> "${BATS_TEST_TMPDIR}/refresh.log"; }
  deploy_observability_acg() { printf 'observability %s\n' "$1" >> "${BATS_TEST_TMPDIR}/refresh.log"; }
  _hostinger_reapply_gitops_applicationsets() { printf '%s\n' "gitops-appsets" >> "${BATS_TEST_TMPDIR}/refresh.log"; }
  _hostinger_clear_stale_platform_tracking_ids() { printf '%s\n' "tracking-fix" >> "${BATS_TEST_TMPDIR}/refresh.log"; }
  _hostinger_reconcile_vault_cluster_store() { printf '%s\n' "vault" >> "${BATS_TEST_TMPDIR}/refresh.log"; }
  _hostinger_refresh_access_layer() { printf '%s\n' "access" >> "${BATS_TEST_TMPDIR}/refresh.log"; }
  _acg_record_provider() { printf 'provider %s\n' "$1" >> "${BATS_TEST_TMPDIR}/refresh.log"; }
  _info() { :; }

  kubectl() {
    case "$*" in
      --context\ ubuntu-hostinger\ get\ --raw=/healthz*)
        return 0
        ;;
      *)
        return 1
        ;;
    esac
  }

  run _provider_k3s_hostinger_refresh_cluster
  [ "$status" -eq 0 ]
  [[ "$output" == *"__WEBHOOK_SUCCESS__"* ]]

  run cat "${BATS_TEST_TMPDIR}/refresh.log"
  [ "$status" -eq 0 ]
  [[ "$output" == *"merge"* ]]
  [[ "$output" == *"register"* ]]
  [[ "$output" == *"observability ubuntu-hostinger"* ]]
  [[ "$output" == *"gitops-appsets"* ]]
  [[ "$output" == *"tracking-fix"* ]]
  [[ "$output" == *"vault"* ]]
  [[ "$output" == *"access"* ]]
  [[ "$output" == *"provider k3s-hostinger"* ]]
}

@test "_hostinger_reapply_gitops_applicationsets reapplies data, services, and platform appsets from the current branch" {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
  source "${REPO_ROOT}/scripts/lib/providers/k3s-hostinger.sh"

  SCRIPT_DIR="${REPO_ROOT}/scripts"
  _HOSTINGER_KUBE_CONTEXT="ubuntu-hostinger"
  ARGOCD_NAMESPACE="cicd"
  K3D_MANAGER_BRANCH="k3d-manager-v1.12.0"
  APP_CLUSTER_NAME="ubuntu-hostinger"
  _hostinger_load_argocd_plugin() { :; }
  _argocd_hub_kubectl_cmd() {
    printf '%s\n' "kubectl --context k3d-k3d-cluster"
  }
  _info() { :; }
  _err() { printf '%s\n' "$*" >&2; return 1; }
  kubectl() {
    case "$*" in
      --context\ k3d-k3d-cluster\ apply\ -f\ -)
        printf '%s\n' "$*" >> "${BATS_TEST_TMPDIR}/appsets.log"
        printf '\n---\n' >> "${BATS_TEST_TMPDIR}/rendered-appsets.yaml"
        cat >> "${BATS_TEST_TMPDIR}/rendered-appsets.yaml"
        return 0
        ;;
      *)
        return 1
        ;;
    esac
  }

  run _hostinger_reapply_gitops_applicationsets
  [ "$status" -eq 0 ]

  run cat "${BATS_TEST_TMPDIR}/appsets.log"
  [ "$status" -eq 0 ]
  [[ "$(printf '%s\n' "$output" | wc -l | tr -d ' ')" -eq 3 ]]
  [[ "$output" == *"--context k3d-k3d-cluster apply -f -"* ]]

  run cat "${BATS_TEST_TMPDIR}/rendered-appsets.yaml"
  [ "$status" -eq 0 ]
  [[ "$output" == *"name: data-layer"* ]]
  [[ "$output" == *"k3d-manager/role: app-cluster"* ]]
  [[ "$output" == *".spec.persistentVolumeClaimRetentionPolicy"* ]]
  [[ "$output" == *"name: services-git"* ]]
  [[ "$output" == *".spec.source.kustomize.images"* ]]
  [[ "$output" == *"name: platform-helm"* ]]
  [[ "$output" == *"name: '{{.name}}-platform'"* ]]
}

@test "_hostinger_clear_stale_platform_tracking_ids strips product-catalog ownership from platform app and refreshes both apps" {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
  source "${REPO_ROOT}/scripts/lib/providers/k3s-hostinger.sh"

  _HOSTINGER_KUBE_CONTEXT="ubuntu-hostinger"
  ARGOCD_NAMESPACE="cicd"
  _hostinger_load_argocd_plugin() { :; }
  _argocd_hub_kubectl_cmd() {
    printf '%s\n' "kubectl --context k3d-k3d-cluster"
  }
  _info() { :; }

  kubectl() {
    case "$*" in
      --context\ ubuntu-hostinger\ -n\ shopping-cart-apps\ get\ deployment/product-catalog\ -o\ jsonpath=\{.metadata.annotations.argocd\\.argoproj\\.io/tracking-id\})
        printf '%s' 'ubuntu-hostinger-platform:apps/Deployment:shopping-cart-apps/product-catalog'
        ;;
      --context\ ubuntu-hostinger\ -n\ shopping-cart-apps\ get\ service/product-catalog\ -o\ jsonpath=\{.metadata.annotations.argocd\\.argoproj\\.io/tracking-id\})
        printf '%s' 'ubuntu-hostinger-platform:/Service:shopping-cart-apps/product-catalog'
        ;;
      --context\ ubuntu-hostinger\ -n\ shopping-cart-apps\ get\ service/product-catalog-nodeport\ -o\ jsonpath=\{.metadata.annotations.argocd\\.argoproj\\.io/tracking-id\})
        printf '%s' 'ubuntu-hostinger-platform:/Service:shopping-cart-apps/product-catalog-nodeport'
        ;;
      --context\ ubuntu-hostinger\ -n\ shopping-cart-apps\ get\ serviceaccount/product-catalog\ -o\ jsonpath=\{.metadata.annotations.argocd\\.argoproj\\.io/tracking-id\})
        printf '%s' 'ubuntu-hostinger-platform:/ServiceAccount:shopping-cart-apps/product-catalog'
        ;;
      --context\ ubuntu-hostinger\ -n\ shopping-cart-apps\ get\ configmap/product-catalog-seed-script\ -o\ jsonpath=\{.metadata.annotations.argocd\\.argoproj\\.io/tracking-id\})
        printf '%s' 'ubuntu-hostinger-platform:/ConfigMap:shopping-cart-apps/product-catalog-seed-script'
        ;;
      --context\ ubuntu-hostinger\ -n\ shopping-cart-apps\ get\ externalsecret.external-secrets.io/product-catalog-secrets\ -o\ jsonpath=\{.metadata.annotations.argocd\\.argoproj\\.io/tracking-id\})
        printf '%s' 'ubuntu-hostinger-platform:external-secrets.io/ExternalSecret:shopping-cart-apps/product-catalog-secrets'
        ;;
      --context\ ubuntu-hostinger\ -n\ shopping-cart-apps\ get\ configmap/product-catalog-config-8h4dfgdf4k\ -o\ jsonpath=\{.metadata.annotations.argocd\\.argoproj\\.io/tracking-id\})
        return 1
        ;;
      --context\ ubuntu-hostinger\ -n\ shopping-cart-apps\ annotate*)
        printf '%s\n' "$*" >> "${BATS_TEST_TMPDIR}/tracking.log"
        ;;
      --context\ k3d-k3d-cluster\ annotate\ application*)
        printf '%s\n' "$*" >> "${BATS_TEST_TMPDIR}/tracking.log"
        ;;
      *)
        return 1
        ;;
    esac
  }

  run _hostinger_clear_stale_platform_tracking_ids
  [ "$status" -eq 0 ]

  run cat "${BATS_TEST_TMPDIR}/tracking.log"
  [ "$status" -eq 0 ]
  [[ "$output" == *"--context ubuntu-hostinger -n shopping-cart-apps annotate deployment/product-catalog argocd.argoproj.io/tracking-id- --overwrite"* ]]
  [[ "$output" == *"--context ubuntu-hostinger -n shopping-cart-apps annotate service/product-catalog argocd.argoproj.io/tracking-id- --overwrite"* ]]
  [[ "$output" == *"--context ubuntu-hostinger -n shopping-cart-apps annotate externalsecret.external-secrets.io/product-catalog-secrets argocd.argoproj.io/tracking-id- --overwrite"* ]]
  [[ "$output" == *"--context k3d-k3d-cluster annotate application shopping-cart-product-catalog -n cicd argocd.argoproj.io/refresh=hard --overwrite"* ]]
  [[ "$output" == *"--context k3d-k3d-cluster annotate application ubuntu-hostinger-platform -n cicd argocd.argoproj.io/refresh=hard --overwrite"* ]]
}

@test "register_app_cluster falls back to insecure tlsClientConfig when CA data is unset" {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
  export PLUGINS_DIR="${REPO_ROOT}/scripts/plugins"
  _warn() { :; }
  _err() { printf '%s\n' "$*" >&2; return 1; }
  _cleanup_trap_command() { printf 'rm -f %q' "$1"; }
  source "${REPO_ROOT}/scripts/plugins/argocd.sh"

  ARGOCD_NAMESPACE="cicd"
  ARGOCD_APP_CLUSTER_SECRET_NAME="cluster-ubuntu-k3s"
  ARGOCD_APP_CLUSTER_NAME="ubuntu-k3s"
  ARGOCD_APP_CLUSTER_SERVER="https://host.k3d.internal:6443"
  ARGOCD_APP_CLUSTER_INSECURE="true"
  ARGOCD_APP_CLUSTER_CA_DATA=""
  ARGOCD_APP_CLUSTER_TOKEN="app-token"

  _kubectl() {
    case "$*" in
      apply\ -f\ *)
        local file="${*: -1}"
        cp "${file}" "${BATS_TEST_TMPDIR}/fallback-secret.yaml"
        return 0
        ;;
      get\ secret\ cluster-ubuntu-k3s\ -n\ cicd\ -o\ jsonpath=\{.metadata.labels.k3d-manager/role\})
        return 0
        ;;
      *)
        return 1
        ;;
    esac
  }

  _argocd_set_active_app_cluster() {
    :
  }

  _info() {
    :
  }

  run register_app_cluster
  [ "$status" -eq 0 ]

  run cat "${BATS_TEST_TMPDIR}/fallback-secret.yaml"
  [ "$status" -eq 0 ]
  [[ "${output}" == *'"tlsClientConfig": { "insecure": true }'* ]]
  [[ "${output}" != *'"caData":'* ]]
}

@test "_hostinger_refresh_access_layer restarts argocd port-forward before cloudflared" {
  HOME="${BATS_TEST_TMPDIR}"
  _ACG_STATE_DIR="${BATS_TEST_TMPDIR}/state"
  SCRIPT_DIR="${BATS_TEST_TMPDIR}/scripts"
  mkdir -p "${_ACG_STATE_DIR}/bin" "${HOME}/Library/LaunchAgents" "${HOME}/.cloudflared"
  mkdir -p "${SCRIPT_DIR}/etc/launchd" "${SCRIPT_DIR}/etc/hostinger" "${SCRIPT_DIR}/etc/argocd" "${SCRIPT_DIR}/plugins"
  : > "${HOME}/.cloudflared/config.yml"
  : > "${SCRIPT_DIR}/plugins/shopping_cart.sh"
  : > "${SCRIPT_DIR}/etc/hostinger/vars.sh"
  cp "${REPO_ROOT}/scripts/etc/argocd/port-forward-wrapper.sh.tmpl" "${SCRIPT_DIR}/etc/argocd/port-forward-wrapper.sh.tmpl"
  cp "${REPO_ROOT}/scripts/etc/argocd/browser-https-wrapper.sh.tmpl" "${SCRIPT_DIR}/etc/argocd/browser-https-wrapper.sh.tmpl"
  printf '#!/usr/bin/env bash\nexit 0\n' > "${_ACG_STATE_DIR}/bin/argocd-port-forward.sh"
  printf '#!/usr/bin/env bash\nexit 0\n' > "${_ACG_STATE_DIR}/bin/keycloak-port-forward.sh"
  chmod +x "${_ACG_STATE_DIR}/bin/argocd-port-forward.sh"
  chmod +x "${_ACG_STATE_DIR}/bin/keycloak-port-forward.sh"
  : > "${HOME}/Library/LaunchAgents/com.k3d-manager.cloudflare-tunnel.plist"
  cat > "${SCRIPT_DIR}/etc/launchd/com.k3d-manager.vault-port-forward.plist.tmpl" <<'EOF'
{{KUBECTL_PATH}}
{{HOME}}
EOF

  lsof() {
    case "$*" in
      *"-iTCP:8080"*)
        if [[ ! -f "${BATS_TEST_TMPDIR}/lsof-8080-cleared" ]]; then
          : > "${BATS_TEST_TMPDIR}/lsof-8080-cleared"
          printf '%s\n' "41517"
          return 0
        fi
        return 1
        ;;
      *"-iTCP:8880"*)
        if [[ ! -f "${BATS_TEST_TMPDIR}/lsof-8880-cleared" ]]; then
          : > "${BATS_TEST_TMPDIR}/lsof-8880-cleared"
          printf '%s\n' "51518"
          return 0
        fi
        return 1
        ;;
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
      *"${_ACG_STATE_DIR}/bin/keycloak-port-forward.sh"*)
        printf '%s\n' "79479"
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

  kubectl() {
    case "$*" in
      --context\ ubuntu-hostinger\ -n\ monitoring\ get\ svc\ pushgateway)
        return 0
        ;;
      *)
        return 1
        ;;
    esac
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
  run grep -F -- 'svc/keycloak' "${_ACG_STATE_DIR}/bin/keycloak-port-forward.sh"
  [ "$status" -eq 0 ]
  run grep -F -- '8880:80' "${_ACG_STATE_DIR}/bin/keycloak-port-forward.sh"
  [ "$status" -eq 0 ]
  run grep -F 'tunnel' "${HOME}/Library/LaunchAgents/com.k3d-manager.cloudflare-tunnel.plist"
  [ "$status" -eq 0 ]
  run grep -F 'services stop cloudflared' "${BATS_TEST_TMPDIR}/restart.log"
  [ "$status" -eq 0 ]
  run grep -F -- '--context "ubuntu-hostinger" port-forward --address=127.0.0.2' "${_ACG_STATE_DIR}/bin/frontend-browser-http.sh"
  [ "$status" -eq 0 ]
  run grep -F -- 'svc/kube-prometheus-stack-grafana' "${HOME}/Library/LaunchAgents/com.k3d-manager.grafana-port-forward.plist"
  [ "$status" -eq 0 ]
  run grep -F -- '<string>k3d-k3d-cluster</string>' "${HOME}/Library/LaunchAgents/com.k3d-manager.grafana-port-forward.plist"
  [ "$status" -eq 0 ]
  run grep -F -- 'svc/pushgateway' "${HOME}/Library/LaunchAgents/com.k3d-manager.pushgateway-port-forward.plist"
  [ "$status" -eq 0 ]
  run grep -F -- '<string>9091:9091</string>' "${HOME}/Library/LaunchAgents/com.k3d-manager.pushgateway-port-forward.plist"
  [ "$status" -eq 0 ]
  run grep -F -- "$(command -v kubectl)" "${HOME}/Library/LaunchAgents/com.k3d-manager.vault-port-forward.plist"
  [ "$status" -eq 0 ]
  run grep -F -- "${HOME}" "${HOME}/Library/LaunchAgents/com.k3d-manager.vault-port-forward.plist"
  [ "$status" -eq 0 ]

  run cat "${BATS_TEST_TMPDIR}/restart.log"
  [ "$status" -eq 0 ]
  [[ "${output}" == *"kill 69478"* ]]
  [[ "${output}" == *"kill -9 69478"* ]]
  [[ "${output}" == *"kill 79479"* ]]
  [[ "${output}" == *"kill -9 79479"* ]]
  [[ "${output}" == *"kill 41517"* ]]
  [[ "${output}" == *"kill 51518"* ]]
  [[ "${output}" == *"com.k3d-manager.argocd-port-forward"* ]]
  [[ "${output}" == *"com.k3d-manager.keycloak-port-forward"* ]]
  [[ "${output}" == *"com.k3d-manager.cloudflare-tunnel"* ]]
  [[ "${output}" == *"com.k3d-manager.argocd-browser-https"* ]]
  [[ "${output}" == *"com.k3d-manager.vault-port-forward"* ]]
}

@test "_hostinger_reconcile_vault_cluster_store bootstraps vault-backend when ESO is present" {
  source "${REPO_ROOT}/scripts/lib/providers/k3s-hostinger.sh"

  kubectl() {
    case "$*" in
      --context\ ubuntu-hostinger\ get\ crd\ clustersecretstores.external-secrets.io)
        return 0
        ;;
      --context\ ubuntu-hostinger\ -n\ secrets\ get\ deploy\ external-secrets)
        return 0
        ;;
      *)
        return 1
        ;;
    esac
  }

  _hostinger_require_host() {
    printf '%s\n' "2.25.146.252"
  }

  _setup_vault_bridge() {
    printf '%s\n' "setup-bridge" >> "${BATS_TEST_TMPDIR}/hostinger-css.log"
  }

  shopping_cart_create_vault_bridge() {
    printf '%s\n' "create-bridge-svc" >> "${BATS_TEST_TMPDIR}/hostinger-css.log"
  }

  shopping_cart_apply_vault_token_and_cluster_secret_store() {
    printf '%s\n' "bootstrap-css" >> "${BATS_TEST_TMPDIR}/hostinger-css.log"
  }

  _info() {
    :
  }

  _hostinger_reconcile_vault_cluster_store

  run cat "${BATS_TEST_TMPDIR}/hostinger-css.log"
  [ "$status" -eq 0 ]
  [[ "${output}" == *"setup-bridge"* ]]
  [[ "${output}" == *"create-bridge-svc"* ]]
  [[ "${output}" == *"bootstrap-css"* ]]
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
