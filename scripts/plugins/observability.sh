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

  local _am_creds
  if ! _am_creds=$(curl -sf \
      -H "X-Vault-Token: ${_vault_token}" \
      "${_vault_addr}/v1/secret/data/k3d-manager/alertmanager" 2>/dev/null \
      | python3 -c "import json,sys; d=json.load(sys.stdin)['data']['data']; \
        print(d['gmail_from']+'|'+d['gmail_app_pw']+'|'+d['sms_gateway'])"); then
    _am_creds=""
  fi

  if [[ -z "${_am_creds}" ]]; then
    _warn "[observability] Alertmanager Vault secret not found — skipping SMS config"
    _warn "[observability] Run: make alertmanager-secret to configure"
  else
    export ALERTMANAGER_GMAIL_FROM="${_am_creds%%|*}"
    local _rest="${_am_creds#*|}"
    export ALERTMANAGER_GMAIL_APP_PW="${_rest%%|*}"
    export ALERTMANAGER_SMS_GATEWAY="${_rest##*|}"

    local _am_config
    _am_config=$(cat <<AMEOF
global:
  smtp_smarthost: 'smtp.gmail.com:587'
  smtp_from: '${ALERTMANAGER_GMAIL_FROM}'
  smtp_auth_username: '${ALERTMANAGER_GMAIL_FROM}'
  smtp_auth_password: '${ALERTMANAGER_GMAIL_APP_PW}'
  smtp_require_tls: true

route:
  receiver: 'null'
  group_wait: 5m
  group_interval: 2h
  repeat_interval: 24h
  routes:
    - matchers:
        - severity = critical
      receiver: sms-critical

receivers:
  - name: 'null'
  - name: sms-critical
    email_configs:
      - to: '${ALERTMANAGER_SMS_GATEWAY}'
        send_resolved: false
        headers:
          Subject: '[ALERT] {{ .GroupLabels.alertname }}'
        text: '{{ range .Alerts }}{{ .Annotations.summary }}{{ end }}'

inhibit_rules:
  - source_matchers:
      - alertname = ServiceDown
    target_matchers:
      - alertname =~ "PodCrashLooping|HighErrorRate|TargetDown"
    equal: [namespace]
AMEOF
)
    _kubectl create secret generic alertmanager-smtp-secret \
      --context k3d-k3d-cluster \
      -n monitoring \
      --from-literal=alertmanager.yaml="${_am_config}" \
      --dry-run=client -o yaml | _kubectl apply -f -
    _info "[observability] Alertmanager config secret created"
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
