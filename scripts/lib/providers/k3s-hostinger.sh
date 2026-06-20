#!/usr/bin/env bash
# scripts/lib/providers/k3s-hostinger.sh
# Single-node k3s app cluster on a pre-existing, permanent Hostinger VPS (SSH target).
# The VPS is provisioned out-of-band (Hostinger panel); this provider never creates or
# deletes the VM — it only installs/uninstalls k3s over SSH and registers the context.

# shellcheck source=/dev/null
source "${SCRIPT_DIR}/plugins/shopping_cart.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/etc/hostinger/vars.sh"

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
  if kubectl --context "${_HOSTINGER_KUBE_CONTEXT}" get --raw='/healthz' >/dev/null 2>&1; then
    _info "[k3s-hostinger] Refresh complete — ${_HOSTINGER_KUBE_CONTEXT} reachable"
    printf '%s\n' "__WEBHOOK_SUCCESS__"
  else
    printf 'ERROR: %s\n' "[k3s-hostinger] ${_HOSTINGER_KUBE_CONTEXT} still unreachable after refresh" >&2
    return 1
  fi
}
