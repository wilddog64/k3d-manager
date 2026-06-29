#!/usr/bin/env bash
# scripts/plugins/observability.sh

function deploy_observability() {
  _info "[observability] Deploying Hub observability stack..."
  local _appset="${SCRIPT_DIR}/etc/argocd/applicationsets/observability.yaml"
  local _hub_context="k3d-k3d-cluster"
  : "${ARGOCD_NAMESPACE:=cicd}"
  K3D_MANAGER_BRANCH="${K3D_MANAGER_BRANCH:-$(git -C "${SCRIPT_DIR}/.." rev-parse --abbrev-ref HEAD 2>/dev/null || echo main)}"
  export K3D_MANAGER_BRANCH ARGOCD_NAMESPACE
  # shellcheck disable=SC2016
  if envsubst '$ARGOCD_NAMESPACE $K3D_MANAGER_BRANCH' < "${_appset}" | _kubectl apply -f -; then
    _info "[observability] Hub ApplicationSet applied — ArgoCD will sync monitoring/trivy-system"
  else
    _err "[observability] Failed to apply Hub observability ApplicationSet"
    return 1
  fi

  _info "[observability] Reading Alertmanager credentials from Vault..."
  local _vault_addr="http://127.0.0.1:18200"
  local _vault_token
  _vault_token=$(_kubectl get secret vault-root -n secrets \
    --context k3d-k3d-cluster -o jsonpath='{.data.root_token}' | base64 -d)

  local _am_creds _vault_hdr
  _vault_hdr=$(mktemp)
  printf 'X-Vault-Token: %s\n' "${_vault_token}" > "${_vault_hdr}"
  if ! _am_creds=$(curl -sf \
      -H "@${_vault_hdr}" \
      "${_vault_addr}/v1/secret/data/k3d-manager/alertmanager" 2>/dev/null \
      | python3 -c "import json,sys; d=json.load(sys.stdin)['data']['data']; \
        print(d['gmail_from']+'|'+d['gmail_app_pw']+'|'+d['sms_gateway'])" 2>/dev/null); then
    _am_creds=""
  fi
  rm -f "${_vault_hdr}"

  if [[ -z "${_am_creds}" ]]; then
    _warn "[observability] Alertmanager Vault secret not found — skipping SMS config"
    _warn "[observability] Run: make alertmanager-secret to configure"
  else
    export ALERTMANAGER_GMAIL_FROM="${_am_creds%%|*}"
    local _rest="${_am_creds#*|}"
    export ALERTMANAGER_GMAIL_APP_PW="${_rest%%|*}"
    export ALERTMANAGER_SMS_GATEWAY="${_rest##*|}"

    local _am_tmpl="${SCRIPT_DIR}/etc/prometheus/alertmanager.yaml.tmpl"
    local _am_config
    # shellcheck disable=SC2016
    _am_config=$(envsubst '${ALERTMANAGER_GMAIL_FROM} ${ALERTMANAGER_GMAIL_APP_PW} ${ALERTMANAGER_SMS_GATEWAY}' \
      < "${_am_tmpl}")
    local _am_tmpfile
    _am_tmpfile=$(mktemp)
    printf '%s' "${_am_config}" > "${_am_tmpfile}"
    _kubectl create secret generic alertmanager-smtp-secret \
      --context k3d-k3d-cluster \
      -n monitoring \
      --from-file=alertmanager.yaml="${_am_tmpfile}" \
      --dry-run=client -o yaml | _kubectl apply -f -
    rm -f "${_am_tmpfile}"
    _info "[observability] Alertmanager config secret created"
  fi

  local _rules_dir="${SCRIPT_DIR}/etc/prometheus/rules"
  if [[ -d "${_rules_dir}" ]]; then
    _kubectl apply -f "${_rules_dir}/" >/dev/null \
      && _info "[observability] PrometheusRules applied from ${_rules_dir}/"
  fi

  if ( _kubectl get application shopping-cart-rules -n cicd >/dev/null 2>&1 ); then
    _kubectl delete application shopping-cart-rules -n cicd >/dev/null \
      && _info "[observability] Removed stale shopping-cart-rules ArgoCD Application"
  fi

  local _istio_manifest="${SCRIPT_DIR}/etc/observability/istio.yaml"
  if [[ -f "${_istio_manifest}" ]]; then
    _kubectl apply -f "${_istio_manifest}" >/dev/null \
      && _info "[observability] Istio Gateway + VirtualServices applied (prometheus/grafana.shopping-cart.local)"
  fi

  _observability_apply_argocd_dashboard "${_hub_context}"
  _deploy_promtail_acg "${_hub_context}"
}

function _observability_acg_context() {
  local context="${1:-}"

  if [[ -n "${context}" ]]; then
    printf '%s\n' "${context}"
    return 0
  fi

  if declare -f _acg_provider_context >/dev/null 2>&1 && \
      declare -f _acg_resolve_provider >/dev/null 2>&1; then
    context="$(_acg_provider_context "$(_acg_resolve_provider)" 2>/dev/null || true)"
  fi

  printf '%s\n' "${context:-ubuntu-k3s}"
}

function _observability_ensure_namespace() {
  local context
  context="$(_observability_acg_context "${1:-}")"
  local namespace="${2:-monitoring}"

  _kubectl create namespace "${namespace}" \
    --context "${context}" \
    --dry-run=client -o yaml | _kubectl apply --context "${context}" -f - >/dev/null
}

function deploy_observability_acg() {
  _info "[observability] Deploying ACG observability stack..."
  local _appset="${SCRIPT_DIR}/etc/argocd/applicationsets/observability-acg.yaml"
  : "${ARGOCD_NAMESPACE:=cicd}"
  K3D_MANAGER_BRANCH="${K3D_MANAGER_BRANCH:-$(git -C "${SCRIPT_DIR}/.." rev-parse --abbrev-ref HEAD 2>/dev/null || echo main)}"
  local _app_context
  _app_context="$(_observability_acg_context "${1:-}")"
  APP_CLUSTER_NAME="${APP_CLUSTER_NAME:-${_app_context}}"
  export K3D_MANAGER_BRANCH ARGOCD_NAMESPACE APP_CLUSTER_NAME
  # shellcheck disable=SC2016
  if envsubst '$ARGOCD_NAMESPACE $K3D_MANAGER_BRANCH $APP_CLUSTER_NAME' < "${_appset}" | _kubectl apply -f -; then
    _info "[observability] ACG ApplicationSet applied — ArgoCD will sync monitoring/trivy-system on ${_app_context}"
  else
    _err "[observability] Failed to apply ACG observability ApplicationSet"
    return 1
  fi

  _observability_ensure_namespace "${_app_context}" monitoring
  _info "[observability] Ensured monitoring namespace exists on ${_app_context}"
  _observability_remove_argocd_dashboard "${_app_context}"

  _info "[observability] Reading Alertmanager credentials from Vault..."
  local _vault_addr="http://127.0.0.1:18200"
  local _vault_token
  _vault_token=$(_kubectl get secret vault-root -n secrets \
    --context k3d-k3d-cluster -o jsonpath='{.data.root_token}' | base64 -d)

  local _am_creds _vault_hdr
  _vault_hdr=$(mktemp)
  printf 'X-Vault-Token: %s\n' "${_vault_token}" > "${_vault_hdr}"
  if ! _am_creds=$(curl -sf \
      --header "@${_vault_hdr}" \
      "${_vault_addr}/v1/secret/data/k3d-manager/alertmanager" 2>/dev/null \
      | python3 -c "import json,sys; d=json.load(sys.stdin)['data']['data']; \
        print(d['gmail_from']+'|'+d['gmail_app_pw']+'|'+d['sms_gateway'])" 2>/dev/null); then
    _am_creds=""
  fi
  rm -f "${_vault_hdr}"

  if [[ -z "${_am_creds}" ]]; then
    _warn "[observability] Alertmanager Vault secret not found — skipping SMS config on ACG"
    _warn "[observability] Run: make alertmanager-secret to configure"
  else
    local _gmail_from _gmail_app_pw _sms_gateway _rest
    _gmail_from="${_am_creds%%|*}"
    _rest="${_am_creds#*|}"
    _gmail_app_pw="${_rest%%|*}"
    _sms_gateway="${_rest##*|}"

    local _am_tmpl="${SCRIPT_DIR}/etc/prometheus/alertmanager.yaml.tmpl"
    local _am_config
    # shellcheck disable=SC2016
    _am_config=$(ALERTMANAGER_GMAIL_FROM="${_gmail_from}" \
      ALERTMANAGER_GMAIL_APP_PW="${_gmail_app_pw}" \
      ALERTMANAGER_SMS_GATEWAY="${_sms_gateway}" \
      envsubst '${ALERTMANAGER_GMAIL_FROM} ${ALERTMANAGER_GMAIL_APP_PW} ${ALERTMANAGER_SMS_GATEWAY}' \
      < "${_am_tmpl}")
    local _am_tmpfile
    _am_tmpfile=$(mktemp)
    printf '%s' "${_am_config}" > "${_am_tmpfile}"
    _kubectl create secret generic alertmanager-smtp-secret \
      --context "${_app_context}" \
      -n monitoring \
      --from-file=alertmanager.yaml="${_am_tmpfile}" \
      --dry-run=client -o yaml | _kubectl apply --context "${_app_context}" -f -
    rm -f "${_am_tmpfile}"
    _info "[observability] Alertmanager config secret created on ACG (${_app_context})"
  fi
  _prometheus_acg_web_config_secret "${_app_context}"
  _deploy_pushgateway_acg "${_app_context}"
  _deploy_promtail_acg "${_app_context}"
}

function _deploy_pushgateway_acg() {
  local _app_context
  _app_context="$(_observability_acg_context "${1:-}")"
  _info "[observability] Deploying Prometheus Pushgateway on ${_app_context}..."
  if ! command -v helm >/dev/null 2>&1; then
    _warn "[observability] helm not found — skipping Pushgateway install"
    return 0
  fi
  if helm upgrade --install prometheus-pushgateway prometheus-community/prometheus-pushgateway \
      --kube-context "${_app_context}" \
      --namespace monitoring \
      --create-namespace \
      --version "2.14.0" \
      --set service.type=ClusterIP \
      --set replicaCount=1 \
      --wait --timeout 120s >/dev/null; then
    _info "[observability] Pushgateway installed (monitoring/prometheus-pushgateway)"
  else
    _warn "[observability] Pushgateway install failed — deployment metrics disabled"
    return 0
  fi

  local _dashboard_cm="${SCRIPT_DIR}/etc/grafana/dashboards/k3dm-deployments-configmap.yaml"
  if [[ -f "${_dashboard_cm}" ]]; then
    _kubectl apply --context "${_app_context}" -f "${_dashboard_cm}" >/dev/null \
      && _info "[observability] k3dm deployment metrics dashboard applied"
  fi
}

function _deploy_promtail_acg() {
  local _app_context
  _app_context="$(_observability_acg_context "${1:-}")"
  local _promtail_manifest="${SCRIPT_DIR}/etc/observability/promtail.yaml"
  if [[ -f "${_promtail_manifest}" ]]; then
    _kubectl apply --context "${_app_context}" -f "${_promtail_manifest}" >/dev/null \
      && _info "[observability] Loki/Promtail log shipper applied on ${_app_context}"
  fi
}

function _observability_apply_argocd_dashboard() {
  local _app_context
  _app_context="$(_observability_acg_context "${1:-}")"
  local _dashboard_manifest="${SCRIPT_DIR}/etc/argocd/platform-ops/grafana-dashboard-argocd.yaml"
  if [[ -f "${_dashboard_manifest}" ]]; then
    _kubectl apply --context "${_app_context}" -f "${_dashboard_manifest}" >/dev/null \
      && _info "[observability] ArgoCD/Image Updater dashboard applied on ${_app_context}"
  fi
}

function _observability_remove_argocd_dashboard() {
  local _app_context
  _app_context="$(_observability_acg_context "${1:-}")"
  if _kubectl --context "${_app_context}" -n monitoring get configmap grafana-dashboard-argocd >/dev/null 2>&1; then
    _kubectl --context "${_app_context}" -n monitoring delete configmap grafana-dashboard-argocd >/dev/null \
      && _info "[observability] Removed stale ArgoCD/Image Updater dashboard from ${_app_context}"
  fi
}

function _prometheus_acg_web_config_secret() {
  local _app_context
  _app_context="$(_observability_acg_context "${1:-}")"
  local _vault_addr="http://127.0.0.1:18200"
  local _vault_token
  _vault_token=$(_kubectl get secret vault-root -n secrets \
    --context k3d-k3d-cluster -o jsonpath='{.data.root_token}' | base64 -d)

  local _vault_hdr
  _vault_hdr=$(mktemp)
  printf 'X-Vault-Token: %s\n' "${_vault_token}" > "${_vault_hdr}"

  local _prom_creds
  if ! _prom_creds=$(curl -sf \
      --header "@${_vault_hdr}" \
      "${_vault_addr}/v1/secret/data/k3d-manager/prometheus-basic-auth" 2>/dev/null \
      | python3 -c "import json,sys; d=json.load(sys.stdin)['data']['data']; \
        print(d['user']+'|'+d['password_bcrypt'])" 2>/dev/null); then
    _prom_creds=""
  fi
  if [[ -z "${_prom_creds}" ]]; then
    local _default_bcrypt_hash="\$2a\$12\$NqL.y.Z1.h.1.E.1.p.9.Q.2.a.7.I.3.Z.7.d.3.Q.2.v.0.K.2.x.6" # bcrypt hash for 'password'

    local _prom_password="${PROM_ADMIN_PASSWORD:-password}"
    _info "[observability] Ensuring Prometheus basic auth secret exists in Vault."
    if ! curl -sf \
        --header "@${_vault_hdr}" \
        --header 'Content-Type: application/json' \
        --request POST \
        --data "{\"data\":{\"user\":\"admin\",\"password\":\"${_prom_password}\",\"password_bcrypt\":\"${_default_bcrypt_hash}\"}}" \
        "${_vault_addr}/v1/secret/data/k3d-manager/prometheus-basic-auth" >/dev/null; then
      rm -f "${_vault_hdr}"
      _err "[observability] Failed to create Prometheus basic auth secret in Vault."
      return 1
    fi

    for _attempt in 1 2 3; do
      if _prom_creds=$(curl -sf \
          --header "@${_vault_hdr}" \
          "${_vault_addr}/v1/secret/data/k3d-manager/prometheus-basic-auth" 2>/dev/null \
          | python3 -c "import json,sys; d=json.load(sys.stdin)['data']['data']; \
            print(d['user']+'|'+d['password_bcrypt'])" 2>/dev/null); then
        break
      fi
      sleep 1
    done

    if [[ -z "${_prom_creds}" ]]; then
      rm -f "${_vault_hdr}"
      _err "[observability] Failed to retrieve Prometheus basic auth secret after creation attempt."
      return 1
    fi
  fi
  rm -f "${_vault_hdr}"

  local _web_config _tmpfile
  _tmpfile=$(mktemp)

  local _prom_user _prom_hash
  _prom_user="${_prom_creds%%|*}"
  _prom_hash="${_prom_creds#*|}"
  _web_config=$(printf 'basic_auth_users:\n  %s: %s\n' "${_prom_user}" "${_prom_hash}")
  printf '%s' "${_web_config}" > "${_tmpfile}"

  _observability_ensure_namespace "${_app_context}" monitoring
  _kubectl create secret generic prometheus-web-config \
    --context "${_app_context}" \
    -n monitoring \
    --from-file=web.yml="${_tmpfile}" \
    --dry-run=client -o yaml | _kubectl apply --context "${_app_context}" -f -
  rm -f "${_tmpfile}"
  _info "[observability] Prometheus web config secret applied (monitoring/prometheus-web-config on ${_app_context})"
}

function observability_status() {
  local _app_context
  _app_context="$(_observability_acg_context "${1:-}")"
  _info "[observability] === Hub (k3d-cluster) ==="
  for _ns in monitoring trivy-system; do
    _info "[observability] --- ${_ns} ---"
    _kubectl get pods -n "${_ns}" --no-headers 2>/dev/null || true
  done
  _info "[observability] === ACG (${_app_context}) ==="
  for _ns in monitoring trivy-system; do
    _info "[observability] --- ${_ns} ---"
    _kubectl get pods -n "${_ns}" --context "${_app_context}" --no-headers 2>/dev/null || true
  done
}

function trivy_scan_report() {
  local _app_context
  _app_context="$(_observability_acg_context "${1:-}")"
  _info "[observability] VulnerabilityReport summary — Hub:"
  _kubectl get vulnerabilityreports -A --no-headers 2>/dev/null \
    | awk '{print $1, $2, $6, $7, $8}' | column -t | sort -k4 -rn || true
  _info "[observability] VulnerabilityReport summary — ACG (${_app_context}):"
  _kubectl get vulnerabilityreports -A --context "${_app_context}" --no-headers 2>/dev/null \
    | awk '{print $1, $2, $6, $7, $8}' | column -t | sort -k4 -rn || true
}
