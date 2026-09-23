#!/usr/bin/env bash

set -euo pipefail

K3DM_SNAPSHOT_HOST="${K3DM_SNAPSHOT_HOST:-${E2E_M2_SSH_HOST:-m2jump}}"
K3DM_SNAPSHOT_DIR="${K3DM_SNAPSHOT_DIR:-k3dm-snapshots}"
K3DM_SNAPSHOT_KEEP="${K3DM_SNAPSHOT_KEEP:-3}"
K3DM_SNAPSHOT_CLUSTER="${K3DM_SNAPSHOT_CLUSTER:-k3d-k3d-cluster}"
K3DM_SNAPSHOT_CONTEXT="${K3DM_SNAPSHOT_CONTEXT:-k3d-k3d-cluster}"

if [[ -r "${PLUGINS_DIR}/hub_recovery.sh" ]] && ! declare -f _hub_recovery_records >/dev/null 2>&1; then
  # shellcheck disable=SC1091
  source "${PLUGINS_DIR}/hub_recovery.sh"
fi

function _hub_snapshot_ssh() {
  _run_command -- ssh -o BatchMode=yes -o ConnectTimeout=10 -- "$K3DM_SNAPSHOT_HOST" "$*"
}

function _hub_snapshot_node_container() {
  printf 'k3d-%s-%s\n' "${K3DM_SNAPSHOT_CLUSTER#k3d-}" "$1"
}

function _hub_snapshot_claim_node() {
  local _ns="$1" _claim="$2" _pv _nodes
  _pv="$(_kubectl -n "$_ns" get pvc "$_claim" -o jsonpath='{.spec.volumeName}')" || return 1
  [[ -n "$_pv" ]] || { echo "No bound PV for ${_ns}/${_claim}" >&2; return 1; }
  _nodes="$(_kubectl get pv "$_pv" -o jsonpath='{.spec.nodeAffinity.required.nodeSelectorTerms[0].matchExpressions[0].values[*]}')" || return 1
  if [[ "$(wc -w <<<"$_nodes" | tr -d ' ')" != "1" ]]; then
    echo "Expected exactly one node for ${_ns}/${_claim}; found: ${_nodes:-none}" >&2
    return 1
  fi
  printf '%s\n' "$_nodes"
}

function _hub_snapshot_claim_pv() {
  local _ns="$1" _claim="$2" _pv
  _pv="$(_kubectl -n "$_ns" get pvc "$_claim" -o jsonpath='{.spec.volumeName}')" || return 1
  [[ -n "$_pv" ]] || { echo "No bound PV for ${_ns}/${_claim}" >&2; return 1; }
  printf '%s\n' "$_pv"
}

function _hub_snapshot_claim_path() {
  local _pv="$1"
  _kubectl get pv "$_pv" -o jsonpath='{.spec.local.path}'
}

function _hub_snapshot_copy() {
  local _container="$1" _source="$2" _destination="$3"
  _run_command -- docker cp "${_container}:${_source}/." "$_destination"
}

function _hub_snapshot_manifest() {
  local _stage="$1" _node="$2" _namespace="$3" _claim="$4" _storage="$5" _uid="$6"
  printf '%s\t%s\t%s\t%s\tpvc-%s_%s_%s\n' "$_node" "$_namespace" "$_claim" "$_storage" "$_uid" "$_namespace" "$_claim" >> "${_stage}/MANIFEST.tsv"
}

function _hub_snapshot_checksums() {
  local _stage="$1" _file _relative _hash
  : > "${_stage}/SHA256SUMS"
  while IFS= read -r _file; do
    _relative="${_file#"$_stage/"}"
    _hash="$(_run_command -- sha256sum "$_file" | awk '{print $1}')"
    printf '%s  %s\n' "$_hash" "$_relative" >> "${_stage}/SHA256SUMS"
  done < <(find "$_stage" -type f ! -name SHA256SUMS -print | sort)
}

function _hub_snapshot_remote_mark_incomplete() {
  local _remote="$1"
  _hub_snapshot_ssh "mv -- '${_remote}' '${_remote}.INCOMPLETE'" || _warn "[hub-snapshot] could not mark ${_remote} incomplete"
}

function hub_snapshot_capture() {
  if [[ "${1:-}" == "--help" ]]; then
    echo "Usage: hub_snapshot_capture"
    return 0
  fi
  [[ "$#" -eq 0 ]] || { echo "Usage: hub_snapshot_capture" >&2; return 2; }
  local _stage _timestamp _remote _node _namespace _claim _storage _pv _uid _path _container
  _stage="$(_run_command -- mktemp -d "${TMPDIR:-/tmp}/k3dm-hub-snapshot.XXXXXX")"
  _run_command -- chmod 700 "$_stage"
  _hub_snapshot_stage="$_stage"
  trap 'rm -rf -- "$_hub_snapshot_stage"' EXIT
  _timestamp="${K3DM_SNAPSHOT_TIMESTAMP:-$(date -u +%Y%m%dT%H%M%SZ)}"
  _remote="${K3DM_SNAPSHOT_DIR}/${_timestamp}"
  if ! _hub_snapshot_ssh true; then
    _err "[hub-snapshot] M2 host ${K3DM_SNAPSHOT_HOST} is unreachable"
    return 1
  fi
  _run_command -- mkdir -p "${_stage}/server-db"
  _container="$(_hub_snapshot_node_container server-0)"
  _hub_snapshot_copy "$_container" /var/lib/rancher/k3s/server/db "${_stage}/server-db" || return 1
  _run_command -- docker cp "${_container}:/var/lib/rancher/k3s/server/token" "${_stage}/server-token" || return 1
  _kubectl --context "$K3DM_SNAPSHOT_CONTEXT" get pv,pvc -A -o yaml > "${_stage}/pv-pvc.yaml"
  while IFS='|' read -r _node _namespace _claim _storage; do
    _pv="$(_hub_snapshot_claim_pv "$_namespace" "$_claim")" || return 1
    _uid="$(_kubectl -n "$_namespace" get pvc "$_claim" -o jsonpath='{.metadata.uid}')" || return 1
    [[ -n "$_uid" ]] || { _err "[hub-snapshot] PVC UID missing for ${_namespace}/${_claim}"; return 1; }
    _node="$(_hub_snapshot_claim_node "$_namespace" "$_claim")" || return 1
    _path="$(_hub_snapshot_claim_path "$_pv")" || return 1
    [[ -n "$_path" ]] || { _err "[hub-snapshot] local path missing for ${_namespace}/${_claim}"; return 1; }
    _container="$(_hub_snapshot_node_container "$_node")"
    _run_command -- mkdir -p "${_stage}/${_storage}/pvc-${_uid}_${_namespace}_${_claim}"
    _hub_snapshot_copy "$_container" "$_path" "${_stage}/${_storage}/pvc-${_uid}_${_namespace}_${_claim}" || return 1
    _hub_snapshot_manifest "$_stage" "$_node" "$_namespace" "$_claim" "$_storage" "$_uid"
  done < <(_hub_recovery_records)
  _hub_snapshot_checksums "$_stage"
  _hub_snapshot_ssh "mkdir -p '$K3DM_SNAPSHOT_DIR' '$_remote'"
  _run_command -- rsync -a -e "ssh -o BatchMode=yes -o ConnectTimeout=10" "${_stage}/" "${K3DM_SNAPSHOT_HOST}:${_remote}/"
  if ! _hub_snapshot_ssh "cd '$_remote' && sha256sum -c SHA256SUMS"; then
    _hub_snapshot_remote_mark_incomplete "$_remote"
    _err "[hub-snapshot] checksum verification failed for ${_timestamp}"
    return 1
  fi
  _info "[hub-snapshot] captured ${_timestamp} to ${K3DM_SNAPSHOT_HOST}:${_remote}"
}

function _hub_snapshot_remote_names() {
  _hub_snapshot_ssh "find '$K3DM_SNAPSHOT_DIR' -mindepth 1 -maxdepth 1 -type d -name '20*' -exec basename {} \\; | sort"
}

function hub_snapshot_list() {
  local _name _size _state
  while IFS= read -r _name; do
    [[ -z "$_name" ]] && continue
    _size="$(_hub_snapshot_ssh "du -sh '$K3DM_SNAPSHOT_DIR/$_name' | awk '{print \$1}'")"
    _state="verified"
    [[ "$_name" == *.INCOMPLETE ]] && _state="incomplete"
    printf '%s\t%s\t%s\n' "${_name%.INCOMPLETE}" "$_size" "$_state"
  done < <(_hub_snapshot_remote_names)
}

function _hub_snapshot_remote_remove() {
  _hub_snapshot_ssh "rm -rf -- '$K3DM_SNAPSHOT_DIR/$1'"
}

function hub_snapshot_prune() {
  local _keep="${K3DM_SNAPSHOT_KEEP}" _name _count=0 _verified=0
  local -a _incomplete=() _good=()
  [[ "$_keep" =~ ^[1-9][0-9]*$ ]] || { _err "[hub-snapshot] K3DM_SNAPSHOT_KEEP must be a positive integer"; return 2; }
  while IFS= read -r _name; do
    [[ -z "$_name" ]] && continue
    if [[ "$_name" == *.INCOMPLETE ]]; then
      _incomplete+=("$_name")
    else
      _good+=("$_name")
    fi
  done < <(_hub_snapshot_remote_names)
  _verified="${#_good[@]}"
  if [[ "$_verified" -eq 0 ]]; then
    _err "[hub-snapshot] refusing to prune: no verified snapshots exist"
    return 1
  fi
  for _name in "${_incomplete[@]}"; do
    _hub_snapshot_remote_remove "$_name"
  done
  for _name in "${_good[@]}"; do
    _count=$((_count + 1))
    if [[ "$_count" -gt "$_keep" ]]; then
      _hub_snapshot_remote_remove "$_name"
    fi
  done
  _info "[hub-snapshot] retained ${_keep} newest verified snapshots"
}
