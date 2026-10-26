#!/usr/bin/env bash

set -euo pipefail

K3DM_SNAPSHOT_HOST="${K3DM_SNAPSHOT_HOST:-${E2E_M2_SSH_HOST:-m2jump}}"
K3DM_SNAPSHOT_DIR="${K3DM_SNAPSHOT_DIR:-k3dm-snapshots}"
K3DM_SNAPSHOT_KEEP="${K3DM_SNAPSHOT_KEEP:-3}"
K3DM_SNAPSHOT_MAX_AGE_DAYS="${K3DM_SNAPSHOT_MAX_AGE_DAYS:-30}"
K3DM_SNAPSHOT_AUTO_PRUNE="${K3DM_SNAPSHOT_AUTO_PRUNE:-1}"
K3DM_SNAPSHOT_MIN_FREE_GB="${K3DM_SNAPSHOT_MIN_FREE_GB:-20}"
K3DM_SNAPSHOT_CLUSTER="${K3DM_SNAPSHOT_CLUSTER:-k3d-k3d-cluster}"
K3DM_SNAPSHOT_CONTEXT="${K3DM_SNAPSHOT_CONTEXT:-k3d-k3d-cluster}"
K3DM_SNAPSHOT_MAX_AGE_HOURS="${K3DM_SNAPSHOT_MAX_AGE_HOURS:-24}"
K3DM_SNAPSHOT_STAMP="${K3DM_SNAPSHOT_STAMP:-${HOME}/.local/share/k3d-manager/hub-snapshot-last}"
K3DM_HUB_DATA_REPO="${K3DM_HUB_DATA_REPO:-git@github-k3dm-hub-data:wilddog64/k3dm-hub-data.git}"

if [[ -r "${PLUGINS_DIR}/hub_recovery.sh" ]] && ! declare -f _hub_recovery_records >/dev/null 2>&1; then
  # shellcheck disable=SC1091
  source "${PLUGINS_DIR}/hub_recovery.sh"
fi

function _hub_snapshot_ssh() {
  _run_command -- ssh -n -o BatchMode=yes -o ConnectTimeout=10 -- "$K3DM_SNAPSHOT_HOST" "$*"
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
  _run_command -- docker exec "$_container" tar -C "$_source" -cf - . > "$_destination"
}

function _hub_snapshot_copy_token() {
  local _container="$1" _source="$2" _destination="$3"
  _run_command -- docker exec "$_container" cat "$_source" > "$_destination"
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

function _hub_snapshot_age_hours() {
  local _name="$1"
  python3 -c 'import datetime, sys
try:
    stamp = datetime.datetime.strptime(sys.argv[1], "%Y%m%dT%H%M%SZ").replace(tzinfo=datetime.timezone.utc)
except (IndexError, ValueError):
    raise SystemExit(1)
age = int((datetime.datetime.now(datetime.timezone.utc) - stamp).total_seconds() // 3600)
print(age)' "$_name"
}

function _hub_snapshot_latest_verified() {
  local _name
  while IFS= read -r _name; do
    [[ -z "$_name" || "$_name" == *.INCOMPLETE ]] && continue
    printf '%s\n' "$_name"
    return 0
  done < <(_hub_snapshot_remote_names | sort -r)
  return 1
}

function _hub_snapshot_guard_read() {
  (
    export DRY_RUN=0 K3DM_DEPLOY_DRY_RUN=0
    # The base runner's empty probe array is not nounset-safe on Bash 3.2.
    # shellcheck disable=SC2329
    _run_command() {
      while [[ "$1" != "--" ]]; do
        shift
      done
      shift
      "$@"
    }
    "$@"
  )
}

function _hub_snapshot_preflight_space() {
  local _stage="$1" _remote="$2" _stage_kib _free_kib _required_kib _min_free_kib
  _stage_kib="$(_run_command -- du -sk "$_stage" | awk '{print $1}')"
  _free_kib="$(_hub_snapshot_ssh "df -Pk '$K3DM_SNAPSHOT_DIR' | awk 'NR==2 {print \$4}'")"
  _min_free_kib="$((K3DM_SNAPSHOT_MIN_FREE_GB * 1024 * 1024))"
  if [[ ! "$_stage_kib" =~ ^[0-9]+$ || ! "$_free_kib" =~ ^[0-9]+$ ]]; then
    _err "[hub-snapshot] unable to read free space on ${K3DM_SNAPSHOT_HOST}"
    _hub_snapshot_ssh "rm -rf -- '${_remote}.INCOMPLETE'" || true
    return 1
  fi
  _required_kib=$((_stage_kib + _min_free_kib))
  if [[ "$_free_kib" -lt "$_required_kib" ]]; then
    _err "[hub-snapshot] insufficient free space on ${K3DM_SNAPSHOT_HOST}: ${_free_kib} KiB free, ${_required_kib} KiB needed"
    _hub_snapshot_ssh "rm -rf -- '${_remote}.INCOMPLETE'" || true
    return 1
  fi
}

function _hub_snapshot_capture_retention_notice() {
  local _name _stamp _epoch _now _incomplete_count=0 _current="${1:-${K3DM_SNAPSHOT_TIMESTAMP:-}}"
  _now="${K3DM_SNAPSHOT_NOW_EPOCH:-$(date -u +%s)}"
  while IFS= read -r _name; do
    [[ "$_name" == *.INCOMPLETE ]] || continue
    _stamp="${_name%.INCOMPLETE}"
    [[ "$_stamp" == "$_current" ]] && continue
    if _epoch="$(_hub_snapshot_timestamp_epoch "$_stamp")" && (( _now - _epoch > 86400 )); then
      _hub_snapshot_remote_remove "$_name" || _warn "[hub-snapshot] could not remove stale incomplete snapshot ${_name}"
    fi
  done < <(_hub_snapshot_remote_names)
  if [[ "$K3DM_SNAPSHOT_AUTO_PRUNE" == 1 ]]; then
    if ! _hub_snapshot_prune_verified "$K3DM_SNAPSHOT_KEEP"; then
      _warn "[hub-snapshot] auto-prune failed; run make snapshot-prune"
    fi
  fi
  while IFS= read -r _name; do
    [[ "$_name" == *.INCOMPLETE ]] && _incomplete_count=$((_incomplete_count + 1))
  done < <(_hub_snapshot_remote_names)
  if [[ "$_incomplete_count" -gt 0 ]]; then
    _warn "[hub-snapshot] ${_incomplete_count} incomplete snapshot(s) on ${K3DM_SNAPSHOT_HOST}; remove with make snapshot-prune"
  fi
}

function _hub_snapshot_latest_export_age_hours() {
  local stage repo stamp
  stage="$(mktemp -d "${TMPDIR:-/tmp}/k3dm-hub-data-guard.XXXXXX")" || return 1
  chmod 700 "$stage"
  if ! git ls-remote --exit-code "$K3DM_HUB_DATA_REPO" refs/heads/snapshots >/dev/null 2>&1; then
    rm -rf -- "$stage"; return 1
  fi
  repo="${stage}/repo"
  if ! git clone --depth 1 --branch snapshots "$K3DM_HUB_DATA_REPO" "$repo" >/dev/null 2>&1; then
    rm -rf -- "$stage"; return 1
  fi
  stamp="$(find "$repo/snapshots" -mindepth 1 -maxdepth 1 -type d -name '20*T*Z' -print 2>/dev/null | sort -r | head -1 || true)"
  stamp="${stamp##*/}"
  rm -rf -- "$stage"
  [[ -n "$stamp" ]] || return 1
  _hub_snapshot_age_hours "$stamp"
}

function hub_snapshot_guard_delete() {
  local _latest _age _export_age
  if _export_age="$(_hub_snapshot_latest_export_age_hours 2>/dev/null)" && [[ "$_export_age" =~ ^[0-9]+$ ]] && (( _export_age <= 24 )); then
    _info "[hub-snapshot] fresh encrypted hub export is ${_export_age}h old"
    return 0
  fi
  if ! _hub_snapshot_guard_read _hub_snapshot_ssh true; then
    _warn "[hub-snapshot] M2 host ${K3DM_SNAPSHOT_HOST} is unreachable; run make snapshot or set DISCARD_HUB_DATA=1 (--discard-hub-data), which permanently loses the seven hub claims"
    return 1
  fi
  if ! _latest="$(_hub_snapshot_guard_read _hub_snapshot_latest_verified)"; then
    _warn "[hub-snapshot] no verified snapshot exists on ${K3DM_SNAPSHOT_HOST}; run make snapshot or set DISCARD_HUB_DATA=1 (--discard-hub-data), which permanently loses the seven hub claims"
    return 1
  fi
  if ! _age="$(_hub_snapshot_age_hours "$_latest")"; then
    _warn "[hub-snapshot] latest snapshot ${_latest} has an invalid timestamp; run make snapshot or set DISCARD_HUB_DATA=1 (--discard-hub-data), which permanently loses the seven hub claims"
    return 1
  fi
  if [[ "$_age" -gt "$K3DM_SNAPSHOT_MAX_AGE_HOURS" ]]; then
    _warn "[hub-snapshot] latest verified snapshot ${_latest} on ${K3DM_SNAPSHOT_HOST} is ${_age}h old, older than ${K3DM_SNAPSHOT_MAX_AGE_HOURS}h; run make snapshot or set DISCARD_HUB_DATA=1 (--discard-hub-data), which permanently loses the seven hub claims"
    return 1
  fi
  _info "[hub-snapshot] latest verified snapshot ${_latest} on ${K3DM_SNAPSHOT_HOST} is ${_age}h old"
}

# shellcheck disable=SC2120
function hub_snapshot_capture() (
  if [[ "${1:-}" == "--help" ]]; then
    echo "Usage: hub_snapshot_capture"
    return 0
  fi
  [[ "$#" -eq 0 ]] || { echo "Usage: hub_snapshot_capture" >&2; return 2; }
  local _lock="${K3DM_SNAPSHOT_LOCK:-${HOME}/.local/share/k3d-manager/hub-snapshot.lock}"
  if [[ "${HUB_SNAPSHOT_LOCK_HELD:-0}" != 1 ]]; then
    if ! mkdir "$_lock" 2>/dev/null; then _info "[hub-snapshot] another capture is running; skipping"; return 0; fi
    trap 'rmdir -- "$_lock" 2>/dev/null || true' EXIT
  fi
  local _stage _timestamp _remote _node _namespace _claim _storage _pv _uid _path _container
  [[ "${K3DM_SNAPSHOT_KEEP}" =~ ^[1-9][0-9]*$ ]] || { _err "[hub-snapshot] K3DM_SNAPSHOT_KEEP must be a positive integer"; return 2; }
  [[ "${K3DM_SNAPSHOT_MAX_AGE_DAYS}" =~ ^[1-9][0-9]*$ ]] || { _err "[hub-snapshot] K3DM_SNAPSHOT_MAX_AGE_DAYS must be a positive integer"; return 2; }
  _stage="$(_run_command -- mktemp -d "${TMPDIR:-/tmp}/k3dm-hub-snapshot.XXXXXX")"
  _run_command -- chmod 700 "$_stage"
  _hub_snapshot_stage="$_stage"
  trap 'rm -rf -- "$_hub_snapshot_stage"; [[ "${HUB_SNAPSHOT_LOCK_HELD:-0}" == 1 ]] || rmdir -- "$_lock" 2>/dev/null || true' EXIT
  _timestamp="${K3DM_SNAPSHOT_TIMESTAMP:-$(date -u +%Y%m%dT%H%M%SZ)}"
  _remote="${K3DM_SNAPSHOT_DIR}/${_timestamp}"
  if ! _hub_snapshot_ssh true; then
    _err "[hub-snapshot] M2 host ${K3DM_SNAPSHOT_HOST} is unreachable"
    return 1
  fi
  _container="$(_hub_snapshot_node_container server-0)"
  _hub_snapshot_copy "$_container" /var/lib/rancher/k3s/server/db "${_stage}/server-db.tar" || return 1
  _hub_snapshot_copy_token "$_container" /var/lib/rancher/k3s/server/token "${_stage}/server-token" || return 1
  _kubectl --context "$K3DM_SNAPSHOT_CONTEXT" get pv,pvc -A -o yaml > "${_stage}/pv-pvc.yaml"
  while IFS='|' read -r _node _namespace _claim _storage; do
    _pv="$(_hub_snapshot_claim_pv "$_namespace" "$_claim")" || return 1
    _uid="$(_kubectl -n "$_namespace" get pvc "$_claim" -o jsonpath='{.metadata.uid}')" || return 1
    [[ -n "$_uid" ]] || { _err "[hub-snapshot] PVC UID missing for ${_namespace}/${_claim}"; return 1; }
    _node="$(_hub_snapshot_claim_node "$_namespace" "$_claim")" || return 1
    _path="$(_hub_snapshot_claim_path "$_pv")" || return 1
    [[ -n "$_path" ]] || { _err "[hub-snapshot] local path missing for ${_namespace}/${_claim}"; return 1; }
    _node="$(_hub_recovery_logical_node "$_node")" || return 1
    _container="$(_hub_snapshot_node_container "$_node")"
    _run_command -- mkdir -p "${_stage}/${_storage}"
    _hub_snapshot_copy "$_container" "$_path" "${_stage}/${_storage}/pvc-${_uid}_${_namespace}_${_claim}.tar" || return 1
    _hub_snapshot_manifest "$_stage" "$_node" "$_namespace" "$_claim" "$_storage" "$_uid"
  done < <(_hub_recovery_records)
  _hub_snapshot_checksums "$_stage"
  _hub_snapshot_ssh "mkdir -p '$K3DM_SNAPSHOT_DIR' '${_remote}.INCOMPLETE'"
  if ! _hub_snapshot_preflight_space "$_stage" "$_remote"; then return 1; fi
  if ! _run_command -- rsync -a -e "ssh -o BatchMode=yes -o ConnectTimeout=10" "${_stage}/" "${K3DM_SNAPSHOT_HOST}:${_remote}.INCOMPLETE/"; then
    _err "[hub-snapshot] rsync upload failed for ${_timestamp}; left ${_remote}.INCOMPLETE"
    return 1
  fi
  if ! _hub_snapshot_ssh "cd '${_remote}.INCOMPLETE' && sha256sum -c SHA256SUMS"; then
    _err "[hub-snapshot] checksum verification failed for ${_timestamp}"
    return 1
  fi
  if ! _hub_snapshot_ssh "mv -- '${_remote}.INCOMPLETE' '${_remote}'"; then
    _err "[hub-snapshot] rename failed for ${_timestamp}; left ${_remote}.INCOMPLETE"
    return 1
  fi
  _run_command -- mkdir -p "$(dirname "$K3DM_SNAPSHOT_STAMP")"
  printf '%s\n' "$_timestamp" > "$K3DM_SNAPSHOT_STAMP"
  _info "[hub-snapshot] captured ${_timestamp} to ${K3DM_SNAPSHOT_HOST}:${_remote}"
  _hub_snapshot_capture_retention_notice "$_timestamp"
)

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

function _hub_snapshot_timestamp_epoch() {
  local _name="$1" _parsed
  [[ "$_name" =~ ^[0-9]{8}T[0-9]{6}Z$ ]] || return 1
  if _parsed="$(date -j -u -f '%Y%m%dT%H%M%SZ' "$_name" +%s 2>/dev/null)"; then printf '%s\n' "$_parsed"; return 0; fi
  date -u -d "${_name:0:4}-${_name:4:2}-${_name:6:2} ${_name:9:2}:${_name:11:2}:${_name:13:2} UTC" +%s 2>/dev/null
}

function _hub_snapshot_prune_verified() {
  local _keep="$1" _name _count=0 _age _epoch _now _max_age="${K3DM_SNAPSHOT_MAX_AGE_DAYS}"
  [[ "$_keep" =~ ^[1-9][0-9]*$ ]] || return 2
  [[ "$_max_age" =~ ^[1-9][0-9]*$ ]] || { _err "[hub-snapshot] K3DM_SNAPSHOT_MAX_AGE_DAYS must be a positive integer"; return 2; }
  _now="${K3DM_SNAPSHOT_NOW_EPOCH:-$(date -u +%s)}"
  while IFS= read -r _name; do
    [[ -z "$_name" || "$_name" == *.INCOMPLETE ]] && continue
    _count=$((_count + 1))
    if ! _epoch="$(_hub_snapshot_timestamp_epoch "$_name")"; then
      _warn "[hub-snapshot] keeping ${_name}: name is not a timestamp"
      continue
    fi
    if [[ "$_count" -le "$_keep" ]]; then continue; fi
    _age=$((_now - _epoch))
    if (( _age > _max_age * 86400 )); then
      _hub_snapshot_remote_remove "$_name" || return 1
    fi
  done < <(_hub_snapshot_remote_names | sort -r)
}

function hub_snapshot_prune() {
  local _keep="${K3DM_SNAPSHOT_KEEP}" _name _verified=0
  local -a _incomplete=()
  [[ "$_keep" =~ ^[1-9][0-9]*$ ]] || { _err "[hub-snapshot] K3DM_SNAPSHOT_KEEP must be a positive integer"; return 2; }
  [[ "${K3DM_SNAPSHOT_MAX_AGE_DAYS}" =~ ^[1-9][0-9]*$ ]] || { _err "[hub-snapshot] K3DM_SNAPSHOT_MAX_AGE_DAYS must be a positive integer"; return 2; }
  while IFS= read -r _name; do
    [[ -z "$_name" ]] && continue
    if [[ "$_name" == *.INCOMPLETE ]]; then
      _incomplete+=("$_name")
    fi
  done < <(_hub_snapshot_remote_names)
  _verified="$(_hub_snapshot_remote_names | while IFS= read -r _name; do [[ -n "$_name" && "$_name" != *.INCOMPLETE ]] && printf '%s\n' "$_name"; done | wc -l | tr -d ' ')"
  if [[ "$_verified" -eq 0 ]]; then
    _err "[hub-snapshot] refusing to prune: no verified snapshots exist"
    return 1
  fi
  for _name in "${_incomplete[@]}"; do
    _hub_snapshot_remote_remove "$_name"
  done
  _hub_snapshot_prune_verified "$_keep" || return 1
  _info "[hub-snapshot] retained verified snapshots newer than ${K3DM_SNAPSHOT_MAX_AGE_DAYS} days (at least ${_keep} newest)"
}

function hub_snapshot_scheduled() { (
  local _lock="${K3DM_SNAPSHOT_LOCK:-${HOME}/.local/share/k3d-manager/hub-snapshot.lock}" _rc=0 _start
  if ! mkdir "$_lock" 2>/dev/null; then _info "[hub-snapshot] another capture is running; skipping"; return 0; fi
  trap 'rmdir -- "$_lock" 2>/dev/null || true' EXIT
  _start="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  _info "[hub-snapshot] scheduled capture started at ${_start}"
  if declare -f _ssh_config_guard >/dev/null 2>&1; then _ssh_config_guard --repair "$K3DM_SNAPSHOT_HOST" || _rc=$?; fi
  if (( _rc == 0 )); then
    # shellcheck disable=SC2119
    HUB_SNAPSHOT_LOCK_HELD=1 hub_snapshot_capture || _rc=$?
  fi
  _info "[hub-snapshot] scheduled capture ended at $(date -u '+%Y-%m-%dT%H:%M:%SZ') (exit ${_rc})"
  return "$_rc"
) }

function hub_snapshot_schedule() { (
  local template="${SCRIPT_DIR}/etc/launchd/com.k3d-manager.hub-snapshot.plist.tmpl" plist="${HOME}/Library/LaunchAgents/com.k3d-manager.hub-snapshot.plist"
  _is_mac || return 0; command -v launchctl >/dev/null 2>&1 || { _warn "[hub-snapshot] launchctl not available"; return 0; }
  mkdir -p "$(dirname "$plist")"
  sed -e "s|{{K3D_MANAGER_PATH}}|${SCRIPT_DIR}/k3d-manager|g" -e "s|{{HOME}}|${HOME}|g" "$template" > "$plist"
  launchctl bootout "gui/$(id -u)/com.k3d-manager.hub-snapshot" 2>/dev/null || true
  launchctl bootstrap "gui/$(id -u)" "$plist"
) }

function hub_snapshot_unschedule() { (
  _is_mac || return 0
  launchctl bootout "gui/$(id -u)/com.k3d-manager.hub-snapshot" 2>/dev/null || true
) }

function hub_snapshot_retain_pvs() {
  local _node _namespace _claim _storage _pv _policy _rc=0
  while IFS='|' read -r _node _namespace _claim _storage; do
    if ! _pv="$(_hub_snapshot_claim_pv "$_namespace" "$_claim")"; then
      _rc=1
      continue
    fi
    if ! _policy="$(_kubectl get pv "$_pv" -o jsonpath='{.spec.persistentVolumeReclaimPolicy}')"; then
      _rc=1
      continue
    fi
    if [[ "$_policy" == Retain ]]; then
      _info "${_namespace}/${_claim} ${_pv} already Retain"
    elif _kubectl patch pv "$_pv" -p '{"spec":{"persistentVolumeReclaimPolicy":"Retain"}}'; then
      _info "${_namespace}/${_claim} ${_pv} ${_policy:-unknown} -> Retain"
    else
      _rc=1
    fi
  done < <(_hub_recovery_records)
  return "$_rc"
}
