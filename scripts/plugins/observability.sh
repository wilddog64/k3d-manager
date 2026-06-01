#!/usr/bin/env bash
# scripts/plugins/observability.sh

function deploy_observability() {
  _info "[observability] Deploying Hub observability stack..."
  local _appset="${SCRIPT_DIR}/etc/argocd/applicationsets/observability.yaml"
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
}

function deploy_observability_acg() {
  _info "[observability] Deploying ACG observability stack..."
  local _appset="${SCRIPT_DIR}/etc/argocd/applicationsets/observability-acg.yaml"
  : "${ARGOCD_NAMESPACE:=cicd}"
  K3D_MANAGER_BRANCH="${K3D_MANAGER_BRANCH:-$(git -C "${SCRIPT_DIR}/.." rev-parse --abbrev-ref HEAD 2>/dev/null || echo main)}"
  export K3D_MANAGER_BRANCH ARGOCD_NAMESPACE
  # shellcheck disable=SC2016
  if envsubst '$ARGOCD_NAMESPACE $K3D_MANAGER_BRANCH' < "${_appset}" | _kubectl apply -f -; then
    _info "[observability] ACG ApplicationSet applied — ArgoCD will sync monitoring/trivy-system on ubuntu-k3s"
  else
    _err "[observability] Failed to apply ACG observability ApplicationSet"
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
    _warn "[observability] Alertmanager Vault secret not found — skipping SMS config on ACG"
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
      --context ubuntu-k3s \
      -n monitoring \
      --from-file=alertmanager.yaml="${_am_tmpfile}" \
      --dry-run=client -o yaml | _kubectl apply -f -
    rm -f "${_am_tmpfile}"
    _info "[observability] Alertmanager config secret created on ACG (ubuntu-k3s)"
  fi
}

function observability_status() {
  _info "[observability] === Hub (k3d-cluster) ==="
  for _ns in monitoring trivy-system; do
    _info "[observability] --- ${_ns} ---"
    _kubectl get pods -n "${_ns}" --no-headers 2>/dev/null || true
  done
  _info "[observability] === ACG (ubuntu-k3s) ==="
  for _ns in monitoring trivy-system; do
    _info "[observability] --- ${_ns} ---"
    _kubectl get pods -n "${_ns}" --context ubuntu-k3s --no-headers 2>/dev/null || true
  done
}

function trivy_scan_report() {
  _info "[observability] VulnerabilityReport summary — Hub:"
  _kubectl get vulnerabilityreports -A --no-headers 2>/dev/null \
    | awk '{print $1, $2, $6, $7, $8}' | column -t | sort -k4 -rn || true
  _info "[observability] VulnerabilityReport summary — ACG:"
  _kubectl get vulnerabilityreports -A --context ubuntu-k3s --no-headers 2>/dev/null \
    | awk '{print $1, $2, $6, $7, $8}' | column -t | sort -k4 -rn || true
}
