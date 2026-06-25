#!/usr/bin/env bash
# scripts/lib/providers/k3s-hostinger.sh
# Single-node k3s app cluster on a pre-existing, permanent Hostinger VPS (SSH target).
# The VPS is provisioned out-of-band (Hostinger panel); this provider never creates or
# deletes the VM — it only installs/uninstalls k3s over SSH and registers the context.

# shellcheck source=/dev/null
source "${SCRIPT_DIR}/plugins/shopping_cart.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/etc/hostinger/vars.sh"

_ACG_STATE_DIR="${_ACG_STATE_DIR:-${HOME}/.local/share/k3d-manager}"
_HOSTINGER_SSH_USER="${HOSTINGER_SSH_USER:-ubuntu}"
_HOSTINGER_SSH_KEY="${HOSTINGER_SSH_KEY:-${HOME}/.ssh/hostinger}"
_HOSTINGER_KUBE_CONTEXT="ubuntu-hostinger"
_HOSTINGER_KUBECONFIG="${HOME}/.kube/hostinger.config"

function _hostinger_require_host() {
  local host="${HOSTINGER_HOST:-}"
  if [[ -z "${host}" ]]; then
    printf 'ERROR: %s\n' "[k3s-hostinger] HOSTINGER_HOST is not set — export HOSTINGER_HOST=<vps-host-or-ip>" >&2
    return 1
  fi
  printf '%s' "${host}"
}

function _hostinger_wait_for_ssh() {
  local host="$1" ssh_user="$2" ssh_key="$3"
  _info "[k3s-hostinger] Waiting for SSH on ${ssh_user}@${host}..."
  local attempts=0
  until ssh -i "${ssh_key}" -o BatchMode=yes -o ConnectTimeout=10 \
        -o StrictHostKeyChecking=accept-new \
        "${ssh_user}@${host}" 'true' >/dev/null 2>&1; do
    (( ++attempts ))
    if (( attempts >= 12 )); then
      printf 'ERROR: %s\n' "[k3s-hostinger] SSH not ready after 120s on ${host}" >&2
      return 1
    fi
    sleep 10
  done
}

function _hostinger_resolve_ip() {
  local host="$1" ip=""
  if [[ "${host}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    printf '%s' "${host}"
    return 0
  fi
  if command -v dig >/dev/null 2>&1; then
    ip="$(dig +short "${host}" 2>/dev/null | grep -Em1 '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$')"
  fi
  if [[ -z "${ip}" ]] && command -v getent >/dev/null 2>&1; then
    ip="$(getent ahostsv4 "${host}" 2>/dev/null | awk '{print $1; exit}')"
  fi
  if [[ -z "${ip}" ]] && command -v python3 >/dev/null 2>&1; then
    ip="$(python3 -c 'import socket,sys; print(socket.gethostbyname(sys.argv[1]))' "${host}" 2>/dev/null)"
  fi
  if [[ -z "${ip}" ]]; then
    printf 'ERROR: %s\n' "[k3s-hostinger] could not resolve ${host} to an IPv4 address" >&2
    return 1
  fi
  printf '%s' "${ip}"
}

function _hostinger_k3sup_install() {
  local host="$1" ssh_user="$2" ssh_key="$3" ip
  ip="$(_hostinger_resolve_ip "${host}")" || return 1
  _ensure_k3sup
  mkdir -p "$(dirname "${_HOSTINGER_KUBECONFIG}")" "${HOME}/.kube"
  _info "[k3s-hostinger] Installing k3s on ${ssh_user}@${host} (${ip}) via k3sup..."
  _run_command -- k3sup install \
    --ip "${ip}" \
    --user "${ssh_user}" \
    --ssh-key "${ssh_key}" \
    --local-path "${_HOSTINGER_KUBECONFIG}" \
    --context "${_HOSTINGER_KUBE_CONTEXT}" \
    --k3s-extra-args '--disable traefik --disable servicelb'
}

function _hostinger_merge_kubeconfig() {
  local tmp_kube tmp_merged prev_ctx
  tmp_kube="${HOME}/.kube/ubuntu-hostinger.tmp"
  tmp_merged="${HOME}/.kube/config.tmp"
  prev_ctx="$(kubectl config current-context 2>/dev/null || true)"
  if kubectl config get-contexts "${_HOSTINGER_KUBE_CONTEXT}" >/dev/null 2>&1; then
    kubectl config delete-context "${_HOSTINGER_KUBE_CONTEXT}" >/dev/null 2>&1 || true
    _info "[k3s-hostinger] Removed stale ${_HOSTINGER_KUBE_CONTEXT} context"
  fi
  cp "${_HOSTINGER_KUBECONFIG}" "${tmp_kube}" || return 1
  chmod 600 "${tmp_kube}"
  if ! KUBECONFIG="${tmp_kube}:${HOME}/.kube/config" kubectl config view --flatten > "${tmp_merged}"; then
    rm -f "${tmp_kube}" "${tmp_merged}"
    return 1
  fi
  mv "${tmp_merged}" "${HOME}/.kube/config" || { rm -f "${tmp_kube}" "${tmp_merged}"; return 1; }
  chmod 600 "${HOME}/.kube/config"
  rm -f "${tmp_kube}"
  if [[ -n "${prev_ctx}" ]] && kubectl config get-contexts "${prev_ctx}" >/dev/null 2>&1; then
    kubectl config use-context "${prev_ctx}" >/dev/null 2>&1 || true
  fi
  _info "[k3s-hostinger] ${_HOSTINGER_KUBE_CONTEXT} merged into ~/.kube/config (current-context preserved: ${prev_ctx:-none})"
}

function _hostinger_register_cluster() {
  local argocd_ns="${ARGOCD_NAMESPACE:-cicd}"
  local secret_name="cluster-${_HOSTINGER_KUBE_CONTEXT}"
  local server ca_data cert_data key_data
  server="$(kubectl config view --raw -o jsonpath="{.clusters[?(@.name==\"${_HOSTINGER_KUBE_CONTEXT}\")].cluster.server}" 2>/dev/null)"
  ca_data="$(kubectl config view --raw -o jsonpath="{.clusters[?(@.name==\"${_HOSTINGER_KUBE_CONTEXT}\")].cluster.certificate-authority-data}" 2>/dev/null)"
  cert_data="$(kubectl config view --raw -o jsonpath="{.users[?(@.name==\"${_HOSTINGER_KUBE_CONTEXT}\")].user.client-certificate-data}" 2>/dev/null)"
  key_data="$(kubectl config view --raw -o jsonpath="{.users[?(@.name==\"${_HOSTINGER_KUBE_CONTEXT}\")].user.client-key-data}" 2>/dev/null)"
  if [[ -z "${server}" || -z "${ca_data}" || -z "${cert_data}" || -z "${key_data}" ]]; then
    printf 'ERROR: %s\n' "[k3s-hostinger] could not read ${_HOSTINGER_KUBE_CONTEXT} credentials from ~/.kube/config" >&2
    return 1
  fi

  _info "[k3s-hostinger] Registering '${_HOSTINGER_KUBE_CONTEXT}' (${server}) with hub ArgoCD ns ${argocd_ns}..."
  local rendered rc=0
  rendered="$(mktemp -t k3s-hostinger-cluster.XXXXXX.yaml)"
  local wasx=0
  case $- in *x*) wasx=1; set +x;; esac
  cat > "${rendered}" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: ${secret_name}
  namespace: ${argocd_ns}
  labels:
    argocd.argoproj.io/secret-type: cluster
    argocd.argoproj.io/cluster-name: ${_HOSTINGER_KUBE_CONTEXT}
    k3d-manager/role: app-cluster
type: Opaque
stringData:
  name: ${_HOSTINGER_KUBE_CONTEXT}
  server: ${server}
  config: |
    {
      "tlsClientConfig": {
        "caData": "${ca_data}",
        "certData": "${cert_data}",
        "keyData": "${key_data}"
      }
    }
EOF
  _kubectl apply -f "${rendered}" || rc=$?
  rm -f "${rendered}"
  (( wasx )) && set -x
  if (( rc != 0 )); then
    printf 'ERROR: %s\n' "[k3s-hostinger] failed to apply cluster secret ${secret_name} to hub ArgoCD" >&2
    return 1
  fi
  _info "[k3s-hostinger] Registered — verify: kubectl get secret ${secret_name} -n ${argocd_ns}"
}

function _hostinger_deregister_cluster() {
  local argocd_ns="${ARGOCD_NAMESPACE:-cicd}"
  local secret_name="cluster-${_HOSTINGER_KUBE_CONTEXT}"
  _kubectl delete secret "${secret_name}" -n "${argocd_ns}" --ignore-not-found=true >/dev/null 2>&1 || true
  _info "[k3s-hostinger] Deregistered ${secret_name} from hub ArgoCD"
}

function _hostinger_restart_launchd() {
  local label="$1" plist="$2" domain="${3:-user}"

  [[ -f "${plist}" ]] || return 0

  _hostinger_wait_for_port_free() {
    local port="$1" timeout="${2:-30}" attempt=0
    if ! command -v lsof >/dev/null 2>&1; then
      return 0
    fi
    while lsof -nP -iTCP:"${port}" -sTCP:LISTEN >/dev/null 2>&1; do
      (( ++attempt ))
      if (( attempt >= timeout )); then
        _warn "[k3s-hostinger] port ${port} still busy after ${timeout}s — continuing with launchd restart"
        return 0
      fi
      sleep 1
    done
  }

  if [[ "${domain}" == "system" ]]; then
    _run_command --interactive-sudo --quiet --soft -- launchctl bootout system "${plist}" >/dev/null 2>&1 || true
    if [[ "${label}" == "com.k3d-manager.argocd-port-forward" ]]; then
      _hostinger_wait_for_port_free 8080 30
    fi
    _run_command --interactive-sudo --quiet --soft -- launchctl bootstrap system "${plist}" >/dev/null 2>&1 \
      && _info "[k3s-hostinger] launchd ${label}: restarted" \
      || _warn "[k3s-hostinger] launchd ${label}: restart failed"
  else
    launchctl bootout "gui/$(id -u)" "${plist}" >/dev/null 2>&1 || true
    if [[ "${label}" == "com.k3d-manager.argocd-port-forward" ]]; then
      _hostinger_wait_for_port_free 8080 30
    fi
    launchctl bootstrap "gui/$(id -u)" "${plist}" >/dev/null 2>&1 \
      && _info "[k3s-hostinger] launchd ${label}: restarted" \
      || _warn "[k3s-hostinger] launchd ${label}: restart failed"
  fi
}

function _hostinger_write_cloudflared_plist() {
  local plist="$1" log_file="$2" config_file="$3" cloudflared_bin="$4"

  mkdir -p "$(dirname "${plist}")"
  cat > "${plist}" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.k3d-manager.cloudflare-tunnel</string>
  <key>ProgramArguments</key>
  <array>
    <string>${cloudflared_bin}</string>
    <string>tunnel</string>
    <string>--config</string>
    <string>${config_file}</string>
    <string>run</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>${log_file}</string>
  <key>StandardErrorPath</key>
  <string>${log_file}</string>
</dict>
</plist>
PLIST
}

function _hostinger_restart_cloudflared() {
  local plist="${HOME}/Library/LaunchAgents/com.k3d-manager.cloudflare-tunnel.plist"
  local log_file="${_ACG_STATE_DIR}/logs/cloudflare-tunnel.log"
  local config_file="${HOME}/.cloudflared/config.yml"
  local cloudflared_bin

  if [[ ! -f "${config_file}" ]]; then
    _warn "[k3s-hostinger] ${config_file} missing — skipping cloudflared restart"
    return 0
  fi

  if command -v brew >/dev/null 2>&1; then
    if [[ "$(brew services list 2>/dev/null | awk '$1 == "cloudflared" { print $2; exit }')" != "" ]]; then
      _info "[k3s-hostinger] Homebrew cloudflared service detected — stopping before loading repo-managed tunnel..."
      brew services stop cloudflared >/dev/null 2>&1 || true
    fi
  fi

  cloudflared_bin="$(command -v cloudflared 2>/dev/null || printf '%s' cloudflared)"
  _hostinger_write_cloudflared_plist "${plist}" "${log_file}" "${config_file}" "${cloudflared_bin}"
  _hostinger_restart_launchd "com.k3d-manager.cloudflare-tunnel" "${plist}" user
}

function _hostinger_write_argocd_port_forward_wrapper() {
  local wrapper_path="$1" log_file="$2" template_path="${SCRIPT_DIR}/etc/argocd/port-forward-wrapper.sh.tmpl"
  local kubectl_bin curl_bin

  if [[ ! -r "${template_path}" ]]; then
    _warn "[k3s-hostinger] ArgoCD port-forward template missing — leaving wrapper untouched"
    return 0
  fi

  kubectl_bin="$(command -v kubectl 2>/dev/null || printf '%s' kubectl)"
  curl_bin="$(command -v curl 2>/dev/null || printf '%s' curl)"
  mkdir -p "$(dirname "${wrapper_path}")"
  KUBECTL_BIN="${kubectl_bin}" \
  CURL_BIN="${curl_bin}" \
  LOG_FILE="${log_file}" \
  KUBECONFIG_FILE="" \
  NAMESPACE="cicd" \
  CONTEXT="k3d-k3d-cluster" \
  SERVICE="svc/argocd-server" \
  LOCAL_PORT="8080" \
  REMOTE_PORT="80" \
  HEALTHZ_URL="http://localhost:8080/healthz" \
  STARTUP_TIMEOUT="30" \
    envsubst '$KUBECTL_BIN $CURL_BIN $LOG_FILE $KUBECONFIG_FILE $NAMESPACE $CONTEXT $SERVICE $LOCAL_PORT $REMOTE_PORT $HEALTHZ_URL $STARTUP_TIMEOUT' \
      < "${template_path}" > "${wrapper_path}"
  chmod 700 "${wrapper_path}"
}

function _hostinger_write_argocd_browser_https_wrapper() {
  local wrapper_path="$1" log_file="$2" template_path="${SCRIPT_DIR}/etc/argocd/browser-https-wrapper.sh.tmpl"
  local socat_bin curl_bin

  if [[ ! -r "${template_path}" ]]; then
    _warn "[k3s-hostinger] ArgoCD browser HTTPS template missing — leaving wrapper untouched"
    return 0
  fi

  socat_bin="$(command -v socat 2>/dev/null || printf '%s' socat)"
  curl_bin="$(command -v curl 2>/dev/null || printf '%s' curl)"
  mkdir -p "$(dirname "${wrapper_path}")"
  SOCAT_BIN="${socat_bin}" \
  CURL_BIN="${curl_bin}" \
  LOG_FILE="${log_file}" \
  LOCAL_HOST="127.0.0.1" \
  LOCAL_PORT="${ARGOCD_BROWSER_PORT:-443}" \
  UPSTREAM_HOST="127.0.0.1" \
  UPSTREAM_PORT="8080" \
  CERT_FILE="${ARGOCD_BROWSER_TLS_CERT_FILE:-${HOME}/.local/share/k3d-manager/argocd-browser-https-tls/fullchain.crt}" \
  KEY_FILE="${ARGOCD_BROWSER_TLS_KEY_FILE:-${HOME}/.local/share/k3d-manager/argocd-browser-https-tls/tls.key}" \
  HEALTHZ_URL="https://127.0.0.1:${ARGOCD_BROWSER_PORT:-443}/healthz" \
  STARTUP_TIMEOUT="${ARGOCD_BROWSER_LISTENER_STARTUP_TIMEOUT:-30}" \
    envsubst '$SOCAT_BIN $CURL_BIN $LOG_FILE $LOCAL_HOST $LOCAL_PORT $UPSTREAM_HOST $UPSTREAM_PORT $CERT_FILE $KEY_FILE $HEALTHZ_URL $STARTUP_TIMEOUT' \
      < "${template_path}" > "${wrapper_path}"
  chmod 700 "${wrapper_path}"
}

function _hostinger_write_frontend_browser_wrapper() {
  local wrapper_path="$1" log_file="$2"
  local kubectl_bin

  kubectl_bin="$(command -v kubectl 2>/dev/null || printf '%s' kubectl)"
  mkdir -p "$(dirname "${wrapper_path}")"
  cat > "${wrapper_path}" <<FRONTEND_WRAPPER
#!/usr/bin/env bash
set -euo pipefail
export KUBECONFIG="${HOME}/.kube/config"
_log="${log_file}"
while true; do
  printf '%s\n' "[\$(date)] starting frontend port-forward: svc/frontend → 127.0.0.2:80" >> "\${_log}"
  ${kubectl_bin} --context "${_HOSTINGER_KUBE_CONTEXT}" port-forward --address=127.0.0.2 \
    svc/frontend 80:80 -n shopping-cart-apps >> "\${_log}" 2>&1 || true
  sleep 2
done
FRONTEND_WRAPPER
  chmod 700 "${wrapper_path}"
}

function _hostinger_clear_port_listeners() {
  local port="$1" label="$2"
  local _listener_pids=()

  if command -v lsof >/dev/null 2>&1; then
    while IFS= read -r _pid; do
      [[ -n "${_pid}" ]] && _listener_pids+=("${_pid}")
    done < <(lsof -nP -iTCP:"${port}" -sTCP:LISTEN -t 2>/dev/null | sort -u)
  fi

  if ((${#_listener_pids[@]} == 0)); then
    return 0
  fi

  _info "[k3s-hostinger] Port ${port} is in use — killing stale ${label} listener(s)..."
  kill "${_listener_pids[@]}" 2>/dev/null || true
  for _i in $(seq 1 30); do
    if ! command -v lsof >/dev/null 2>&1 || ! lsof -nP -iTCP:"${port}" -sTCP:LISTEN >/dev/null 2>&1; then
      break
    fi
    sleep 1
  done
  if command -v lsof >/dev/null 2>&1 && lsof -nP -iTCP:"${port}" -sTCP:LISTEN >/dev/null 2>&1; then
    _listener_pids=()
    while IFS= read -r _pid; do
      [[ -n "${_pid}" ]] && _listener_pids+=("${_pid}")
    done < <(lsof -nP -iTCP:"${port}" -sTCP:LISTEN -t 2>/dev/null | sort -u)
    if ((${#_listener_pids[@]} > 0)); then
      _warn "[k3s-hostinger] Port ${port} still busy after graceful stop — force killing ${label} listener(s)..."
      kill -9 "${_listener_pids[@]}" 2>/dev/null || true
      for _i in $(seq 1 5); do
        if ! lsof -nP -iTCP:"${port}" -sTCP:LISTEN >/dev/null 2>&1; then
          break
        fi
        sleep 1
      done
    fi
  fi
}

function _hostinger_refresh_access_layer() {
  if [[ "$(uname)" != "Darwin" ]]; then
    return 0
  fi

  _info "[k3s-hostinger] Refreshing local access layer listeners..."
  local _argocd_pf_label="com.k3d-manager.argocd-port-forward"
  local _argocd_pf_plist="${HOME}/Library/LaunchAgents/${_argocd_pf_label}.plist"
  local _argocd_pf_log="${_ACG_STATE_DIR}/logs/argocd-pf.log"
  local _argocd_pf_wrapper="${_ACG_STATE_DIR}/bin/argocd-port-forward.sh"
  local _argocd_browser_wrapper="${ARGOCD_BROWSER_LISTENER_WRAPPER:-${_ACG_STATE_DIR}/bin/argocd-browser-https.sh}"
  local _argocd_browser_log="${ARGOCD_BROWSER_LISTENER_LOG:-${_ACG_STATE_DIR}/logs/argocd-browser-https.log}"
  local _frontend_browser_wrapper="${_ACG_STATE_DIR}/bin/frontend-browser-http.sh"
  local _frontend_browser_log="${_ACG_STATE_DIR}/logs/frontend-browser-http.log"
  if [[ ! -f "${_argocd_pf_plist}" && -f "${_argocd_pf_wrapper}" ]]; then
    _info "[k3s-hostinger] ArgoCD port-forward plist missing — regenerating from wrapper..."
    mkdir -p "$(dirname "${_argocd_pf_log}")"
    cat > "${_argocd_pf_plist}" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${_argocd_pf_label}</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>${_argocd_pf_wrapper}</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>${_argocd_pf_log}</string>
  <key>StandardErrorPath</key>
  <string>${_argocd_pf_log}</string>
</dict>
</plist>
PLIST
  fi
  _hostinger_write_argocd_port_forward_wrapper "${_argocd_pf_wrapper}" "${_argocd_pf_log}"
  _hostinger_write_argocd_browser_https_wrapper \
    "${_argocd_browser_wrapper}" \
    "${_argocd_browser_log}"
  _hostinger_write_frontend_browser_wrapper \
    "${_frontend_browser_wrapper}" \
    "${_frontend_browser_log}"
  _hostinger_clear_port_listeners 8080 "ArgoCD port-forward"
  _hostinger_restart_launchd \
    "${_argocd_pf_label}" \
    "${_argocd_pf_plist}" \
    user
  _hostinger_restart_cloudflared
  _hostinger_restart_launchd \
    "com.k3d-manager.argocd-browser-https" \
    "/Library/LaunchDaemons/com.k3d-manager.argocd-browser-https.plist" \
    system
  _hostinger_restart_launchd \
    "com.k3d-manager.keycloak-browser-http" \
    "/Library/LaunchDaemons/com.k3d-manager.keycloak-browser-http.plist" \
    system
  _hostinger_restart_launchd \
    "com.k3d-manager.frontend-browser-http" \
    "/Library/LaunchDaemons/com.k3d-manager.frontend-browser-http.plist" \
    system
  _hostinger_restart_launchd \
    "com.k3d-manager.grafana-port-forward" \
    "${HOME}/Library/LaunchAgents/com.k3d-manager.grafana-port-forward.plist" \
    user
  _hostinger_restart_launchd \
    "com.k3d-manager.pushgateway-port-forward" \
    "${HOME}/Library/LaunchAgents/com.k3d-manager.pushgateway-port-forward.plist" \
    user
}

function _provider_k3s_hostinger_deploy_cluster() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    cat <<'HELP'
Usage: CLUSTER_PROVIDER=k3s-hostinger ./scripts/k3d-manager deploy_cluster

Install a single-node k3s app cluster on a pre-existing Hostinger VPS:
  1. SSH ready wait     — up to 120s
  2. k3sup install      — install k3s; merge kubeconfig as ubuntu-hostinger
  3. kubectl wait       — node Ready

The VPS is provisioned out-of-band (Hostinger panel) and is permanent; this
provider never creates or deletes the VM.

Config (env overrides; defaults in scripts/etc/hostinger/vars.sh):
  HOSTINGER_HOST       VPS host (default: srv1754834.hstgr.cloud)
  HOSTINGER_SSH_USER   SSH user (default: ubuntu)
  HOSTINGER_SSH_KEY    SSH private key path (default: ~/.ssh/hostinger)
HELP
    return 0
  fi

  local host ssh_user ssh_key
  host="$(_hostinger_require_host)" || return 1
  ssh_user="${_HOSTINGER_SSH_USER}"
  ssh_key="${_HOSTINGER_SSH_KEY}"

  if [[ ! -f "${ssh_key}" ]]; then
    printf 'ERROR: %s\n' "[k3s-hostinger] SSH key not found: ${ssh_key}" >&2
    return 1
  fi

  _hostinger_wait_for_ssh "${host}" "${ssh_user}" "${ssh_key}" || return 1
  _hostinger_k3sup_install "${host}" "${ssh_user}" "${ssh_key}" || return 1
  _hostinger_merge_kubeconfig || return 1

  _info "[k3s-hostinger] Waiting for node to be Ready..."
  local attempts=0
  until KUBECONFIG="${_HOSTINGER_KUBECONFIG}" kubectl get nodes 2>/dev/null | grep -q " Ready"; do
    (( ++attempts ))
    if (( attempts >= 60 )); then
      printf 'ERROR: %s\n' "[k3s-hostinger] Node did not become Ready after 300s" >&2
      return 1
    fi
    sleep 5
  done

  _info "[k3s-hostinger] Labeling node..."
  local node_name
  node_name=$(KUBECONFIG="${_HOSTINGER_KUBECONFIG}" kubectl get nodes \
    --no-headers -o custom-columns=NAME:.metadata.name 2>/dev/null | head -n1)
  [[ -n "${node_name}" ]] && \
    KUBECONFIG="${_HOSTINGER_KUBECONFIG}" kubectl label node "${node_name}" \
      k3d-manager/node-type=server --overwrite >/dev/null 2>&1 || true

  _info "[k3s-hostinger] Registering cluster with hub ArgoCD..."
  _hostinger_register_cluster || return 1
  _acg_record_provider "k3s-hostinger"

  _info "[k3s-hostinger] Cluster ready."
  _info "[k3s-hostinger] Verify: kubectl --context ${_HOSTINGER_KUBE_CONTEXT} get nodes"
  _info "[k3s-hostinger] ArgoCD:  kubectl get secret cluster-${_HOSTINGER_KUBE_CONTEXT} -n ${ARGOCD_NAMESPACE:-cicd}"
}

function _provider_k3s_hostinger_destroy_cluster() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    cat <<'HELP'
Usage: CLUSTER_PROVIDER=k3s-hostinger ./scripts/k3d-manager destroy_cluster --confirm

Uninstall k3s from the Hostinger VPS (the VM is permanent and is NOT deleted):
  1. Run k3s-uninstall.sh on the box via SSH
  2. Remove ubuntu-hostinger kubeconfig context
HELP
    return 0
  fi

  if [[ "${1:-}" != "--confirm" ]]; then
    printf 'ERROR: %s\n' "[k3s-hostinger] destroy_cluster requires --confirm" >&2
    return 1
  fi

  local host ssh_user ssh_key
  host="$(_hostinger_require_host)" || return 1
  ssh_user="${_HOSTINGER_SSH_USER}"
  ssh_key="${_HOSTINGER_SSH_KEY}"

  _info "[k3s-hostinger] Uninstalling k3s on ${ssh_user}@${host}..."
  local _uninstall_rc=0
  _run_command -- ssh -i "${ssh_key}" -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new "${ssh_user}@${host}" 'sudo sh -c "test -x /usr/local/bin/k3s-uninstall.sh && /usr/local/bin/k3s-uninstall.sh"' || _uninstall_rc=$?
  if [[ "${_uninstall_rc}" -eq 255 ]]; then
    printf 'ERROR: %s\n' "[k3s-hostinger] SSH to ${ssh_user}@${host} failed — cannot uninstall k3s" >&2
    return 1
  elif [[ "${_uninstall_rc}" -ne 0 ]]; then
    _info "[k3s-hostinger] k3s-uninstall.sh not present or returned ${_uninstall_rc} — skipping"
  fi

  _hostinger_deregister_cluster || true

  if kubectl config get-contexts "${_HOSTINGER_KUBE_CONTEXT}" >/dev/null 2>&1; then
    kubectl config delete-context "${_HOSTINGER_KUBE_CONTEXT}" >/dev/null 2>&1 || true
    _info "[k3s-hostinger] Removed kubeconfig context ${_HOSTINGER_KUBE_CONTEXT}"
  fi

  rm -f "${_HOSTINGER_KUBECONFIG}"
  rm -f "${_ACG_ACTIVE_PROVIDER_FILE}"
  _info "[k3s-hostinger] k3s uninstalled; VPS preserved."
}

function _provider_k3s_hostinger_refresh_cluster() {
  _hostinger_require_host >/dev/null || return 1
  if [[ ! -f "${_HOSTINGER_KUBECONFIG}" ]]; then
    printf 'ERROR: %s\n' "[k3s-hostinger] saved kubeconfig ${_HOSTINGER_KUBECONFIG} missing — run deploy_cluster (/cluster-up) first" >&2
    return 1
  fi
  _info "[k3s-hostinger] Refreshing ${_HOSTINGER_KUBE_CONTEXT} kubeconfig + ArgoCD registration…"
  _hostinger_merge_kubeconfig || return 1
  _hostinger_register_cluster || return 1
  _hostinger_refresh_access_layer || return 1
  if kubectl --context "${_HOSTINGER_KUBE_CONTEXT}" get --raw='/healthz' >/dev/null 2>&1; then
    _acg_record_provider "k3s-hostinger"
    _info "[k3s-hostinger] Refresh complete — ${_HOSTINGER_KUBE_CONTEXT} reachable"
    printf '%s\n' "__WEBHOOK_SUCCESS__"
  else
    printf 'ERROR: %s\n' "[k3s-hostinger] ${_HOSTINGER_KUBE_CONTEXT} still unreachable after refresh" >&2
    return 1
  fi
}
