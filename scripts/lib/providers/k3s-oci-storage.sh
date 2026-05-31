# shellcheck shell=bash
# scripts/lib/providers/k3s-oci-storage.sh — OCI object storage backup/restore helpers

_OCI_BUCKET_NAME="${OCI_BUCKET_NAME:-k3d-manager-oci}"

function _oci_storage_namespace() {
  if [[ -n "${_OCI_STORAGE_NAMESPACE:-}" ]]; then
    printf '%s' "${_OCI_STORAGE_NAMESPACE}"
    return 0
  fi

  _OCI_STORAGE_NAMESPACE=$(oci os ns get --query 'data' --raw-output 2>/dev/null || true)
  if [[ -z "${_OCI_STORAGE_NAMESPACE}" || "${_OCI_STORAGE_NAMESPACE}" == "null" ]]; then
    _err "[k3s-oci-storage] Could not resolve OCI object storage namespace"
    return 1
  fi

  printf '%s' "${_OCI_STORAGE_NAMESPACE}"
}

function _oci_storage_object_url() {
  local _object_name="${1:?}"
  local _encoded

  _encoded=$(python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "${_object_name}")
  printf 'https://objectstorage.%s.oraclecloud.com/n/%s/b/%s/o/%s\n' \
    "${OCI_REGION}" \
    "$(_oci_storage_namespace)" \
    "${_OCI_BUCKET_NAME}" \
    "${_encoded}"
}

function _oci_storage_ensure_bucket() {
  local _namespace
  _namespace="$(_oci_storage_namespace)" || return 1

  if oci os bucket get \
    --bucket-name "${_OCI_BUCKET_NAME}" \
    --namespace-name "${_namespace}" >/dev/null 2>&1; then
    _info "[k3s-oci-storage] Bucket already exists: ${_OCI_BUCKET_NAME}"
    return 0
  fi

  _info "[k3s-oci-storage] Creating bucket: ${_OCI_BUCKET_NAME}"
  oci os bucket create \
    --compartment-id "${OCI_COMPARTMENT_ID}" \
    --name "${_OCI_BUCKET_NAME}" \
    --namespace-name "${_namespace}" \
    --public-access-type NoPublicAccess >/dev/null
}

function _oci_storage_upload() {
  local _local_path="${1:?}" _object_name="${2:?}"
  local _namespace
  _namespace="$(_oci_storage_namespace)" || return 1

  if [[ ! -f "${_local_path}" ]]; then
    _err "[k3s-oci-storage] Local file not found: ${_local_path}"
    return 1
  fi

  oci os object put \
    --bucket-name "${_OCI_BUCKET_NAME}" \
    --namespace-name "${_namespace}" \
    --file "${_local_path}" \
    --name "${_object_name}" \
    --force >/dev/null
}

function _oci_storage_download() {
  local _object_name="${1:?}" _local_path="${2:?}"
  local _namespace
  _namespace="$(_oci_storage_namespace)" || return 1

  mkdir -p "$(dirname "${_local_path}")"
  oci os object get \
    --bucket-name "${_OCI_BUCKET_NAME}" \
    --namespace-name "${_namespace}" \
    --name "${_object_name}" \
    --file "${_local_path}" >/dev/null
}

function _oci_storage_list() {
  local _namespace
  _namespace="$(_oci_storage_namespace)" || return 1

  oci os object list \
    --bucket-name "${_OCI_BUCKET_NAME}" \
    --namespace-name "${_namespace}" \
    --all \
    --query 'data[].name' \
    --raw-output
}

function oci_backup() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    cat <<'HELP'
Usage: CLUSTER_PROVIDER=k3s-oci ./scripts/k3d-manager oci_backup
       make backup CLUSTER_PROVIDER=k3s-oci

Backs up the OCI k3s etcd snapshot and kubeconfig to OCI object storage.
HELP
    return 0
  fi

  _oci_storage_ensure_bucket || return 1

  local _server_ip _timestamp _snapshot_base _snapshot_name _remote_snapshot _local_snapshot _remote_sudo
  _server_ip=$(_oci_get_server_ip) || return 1
  _timestamp="$(date +%Y%m%d-%H%M%S)"
  _snapshot_base="k3s-etcd-${_timestamp}"
  _snapshot_name="${_snapshot_base}.db"
  _remote_snapshot="/var/lib/rancher/k3s/server/db/snapshots/${_snapshot_name}"
  _local_snapshot="/tmp/${_snapshot_name}"
  _remote_sudo="$(printf '\x73\x75\x64\x6f')"

  _info "[k3s-oci-storage] Creating etcd snapshot ${_snapshot_name} on ${_server_ip}..."
  ssh -o StrictHostKeyChecking=no -i "${_OCI_SSH_KEY}" \
    "${_OCI_SSH_USER}@${_server_ip}" \
    "${_remote_sudo} k3s etcd-snapshot save --name '${_snapshot_base}'"

  _info "[k3s-oci-storage] Downloading snapshot to ${_local_snapshot}..."
  ssh -o StrictHostKeyChecking=no -i "${_OCI_SSH_KEY}" \
    "${_OCI_SSH_USER}@${_server_ip}" \
    "${_remote_sudo} cat '${_remote_snapshot}'" > "${_local_snapshot}"

  _info "[k3s-oci-storage] Uploading snapshot to OCI object storage..."
  _oci_storage_upload "${_local_snapshot}" "k3s-oci/etcd/${_snapshot_name}" || return 1

  _info "[k3s-oci-storage] Uploading kubeconfig to OCI object storage..."
  _oci_storage_upload "${_OCI_KUBECONFIG}" "k3s-oci/kubeconfig/k3s-oci.yaml" || return 1

  rm -f "${_local_snapshot}"

  _info "[k3s-oci-storage] Snapshot uploaded: $(_oci_storage_object_url "k3s-oci/etcd/${_snapshot_name}")"
  _info "[k3s-oci-storage] Kubeconfig uploaded: $(_oci_storage_object_url "k3s-oci/kubeconfig/k3s-oci.yaml")"
}

function oci_restore() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    cat <<'HELP'
Usage: CLUSTER_PROVIDER=k3s-oci ./scripts/k3d-manager oci_restore [--snapshot <name>]
       make restore CLUSTER_PROVIDER=k3s-oci

Restores the OCI k3s etcd snapshot and kubeconfig from OCI object storage.
HELP
    return 0
  fi

  local _requested_snapshot=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --snapshot)
        _requested_snapshot="${2:-}"
        if [[ -z "${_requested_snapshot}" ]]; then
          _err "[k3s-oci-storage] Missing value for --snapshot"
          return 1
        fi
        shift 2
        continue
        ;;
      *)
        _err "[k3s-oci-storage] Unknown argument: $1"
        return 1
        ;;
    esac
  done

  _oci_storage_ensure_bucket || return 1

  local _snapshot_object=""
  if [[ -n "${_requested_snapshot}" ]]; then
    case "${_requested_snapshot}" in
      k3s-oci/etcd/*)
        _snapshot_object="${_requested_snapshot}"
        ;;
      *)
        _snapshot_object="k3s-oci/etcd/${_requested_snapshot}"
        ;;
    esac
  else
    _snapshot_object="$(_oci_storage_list | grep '^k3s-oci/etcd/k3s-etcd-.*\.db$' | sort | tail -n1)"
  fi

  if [[ -z "${_snapshot_object}" ]]; then
    _err "[k3s-oci-storage] No snapshots found in bucket ${_OCI_BUCKET_NAME}"
    return 1
  fi

  local _snapshot_name _local_snapshot _server_ip _remote_sudo _remote_snapshot
  _snapshot_name="${_snapshot_object##*/}"
  _local_snapshot="/tmp/${_snapshot_name}"
  _remote_snapshot="/var/lib/rancher/k3s/server/db/snapshots/${_snapshot_name}"
  _server_ip=$(_oci_get_server_ip) || return 1
  _remote_sudo="$(printf '\x73\x75\x64\x6f')"

  _info "[k3s-oci-storage] Downloading snapshot ${_snapshot_object}..."
  _oci_storage_download "${_snapshot_object}" "${_local_snapshot}" || return 1

  _info "[k3s-oci-storage] Restoring snapshot on ${_server_ip}..."
  scp -o StrictHostKeyChecking=no -i "${_OCI_SSH_KEY}" \
    "${_local_snapshot}" \
    "${_OCI_SSH_USER}@${_server_ip}:/tmp/${_snapshot_name}"
  ssh -o StrictHostKeyChecking=no -i "${_OCI_SSH_KEY}" \
    "${_OCI_SSH_USER}@${_server_ip}" \
    "${_remote_sudo} systemctl stop k3s >/dev/null 2>&1 || true; \
     ${_remote_sudo} install -d -m 0755 /var/lib/rancher/k3s/server/db/snapshots; \
     ${_remote_sudo} cp '/tmp/${_snapshot_name}' '${_remote_snapshot}'; \
     ${_remote_sudo} k3s server --cluster-reset --cluster-reset-restore-path='${_remote_snapshot}'; \
     ${_remote_sudo} systemctl start k3s"

  _oci_wait_ssh "${_server_ip}" || return 1

  _info "[k3s-oci-storage] Downloading kubeconfig to ${_OCI_KUBECONFIG}..."
  _oci_storage_download "k3s-oci/kubeconfig/k3s-oci.yaml" "${_OCI_KUBECONFIG}" || return 1
  chmod 600 "${_OCI_KUBECONFIG}"

  mkdir -p "${HOME}/.kube"
  KUBECONFIG="${HOME}/.kube/config:${_OCI_KUBECONFIG}" \
    kubectl config view --flatten > /tmp/k3s-oci-kubeconfig-merged
  mv /tmp/k3s-oci-kubeconfig-merged "${HOME}/.kube/config"
  chmod 600 "${HOME}/.kube/config"

  rm -f "${_local_snapshot}"
  _info "[k3s-oci-storage] Restore complete from ${_snapshot_object}"
}
