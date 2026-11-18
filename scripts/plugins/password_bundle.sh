#!/usr/bin/env bash
# Encrypted, offline service-password delivery.

_password_bundle_paths() {
  PB_STATE="${K3DM_PASSWORD_BUNDLE_STATE_DIR:-${K3DM_STATE_DIR:-$HOME/.local/share/k3d-manager/state}/password-bundle}"
  PB_DIR="${K3DM_PASSWORD_BUNDLE_DIR:-$HOME/Library/Mobile Documents/com~apple~CloudDocs/k3dm/password-bundle}"
}

_password_bundle_metrics() {
  local success="$1" change="$2" count="$3" now body
  now=0
  [[ -r "$PB_STATE/last-publish" ]] && read -r now < "$PB_STATE/last-publish"
  if [[ "$success" == 1 ]]; then now="$( _run_command --no-exit -- date +%s)"; printf '%s\n' "$now" > "$PB_STATE/last-publish"; fi
  body="$(printf 'k3dm_password_bundle_publish_success %s\nk3dm_password_bundle_last_publish_timestamp %s\nk3dm_password_bundle_last_change_timestamp %s\nk3dm_password_bundle_recipients %s\n' "$success" "$now" "$change" "$count")"
  printf '%s\n' "$body" | _run_command --no-exit --quiet -- curl --fail -sS -X POST --data-binary @- "${K3DM_PASSWORD_BUNDLE_PUSHGATEWAY_URL:-http://localhost:19094/metrics/job/k3dm-password-bundle}" >/dev/null 2>&1 || true
}

function password_bundle_enroll() { (
  set +x
  local identity key rc=0
  _run_command --no-exit --quiet -- security find-generic-password -a identity -s k3dm-password-bundle-age -w >/dev/null 2>&1 || rc=$?
  if (( rc == 0 )) && [[ "${FORCE:-0}" != 1 ]]; then
    echo 'Identity already exists; use FORCE=1 to replace it.' >&2; return 1
  fi
  if (( rc != 0 && rc != 44 )); then echo 'Unable to read Keychain identity.' >&2; return 1; fi
  identity="$(_run_command --no-exit -- age-keygen 2>/dev/null)" || return 1
  key="$(printf '%s\n' "$identity" | _run_command --no-exit -- age-keygen -y)" || return 1
  printf 'add-generic-password -U -a identity -s k3dm-password-bundle-age -w %s\n' "${identity##*$'\n'}" | _run_command --no-exit -- security -i || return 1
  printf '%s\nOn the hub: make password-bundle-add-recipient NAME=<laptop> KEY=%s\n' "$key" "$key"
) }

function password_bundle_add_recipient() { (
  set +x
  local name="${NAME:-}" key="${KEY:-}" tmp
  [[ "$name" =~ ^[a-z0-9-]{1,32}$ && "$key" =~ ^age1[02-9ac-hj-np-z]{58}$ ]] || { echo 'Invalid recipient name or key.' >&2; return 1; }
  _password_bundle_paths
  umask 077
  _run_command --no-exit -- mkdir -p -- "$PB_STATE" || return 1
  _run_command --no-exit -- chmod 700 "$PB_STATE" || return 1
  tmp="$(_run_command --no-exit -- mktemp "$PB_STATE/recipients.XXXXXX")" || return 1
  trap '_run_command --no-exit -- rm -f -- "$tmp"' EXIT
  if [[ -f "$PB_STATE/recipients" ]]; then
    _run_command --no-exit -- awk -v name="$name" '$1 != name {print}' "$PB_STATE/recipients" > "$tmp" || return 1
  fi
  printf '%s %s\n' "$name" "$key" >> "$tmp"
  _run_command --no-exit -- mv -f -- "$tmp" "$PB_STATE/recipients"
) }

function password_bundle_remove_recipient() { (
  set +x
  local name="${NAME:-}" tmp
  [[ "$name" =~ ^[a-z0-9-]{1,32}$ ]] || return 1
  _password_bundle_paths
  [[ -f "$PB_STATE/recipients" ]] || return 1
  _run_command --no-exit -- awk -v name="$name" '$1 == name {found=1} END {exit !found}' "$PB_STATE/recipients" || return 1
  umask 077
  tmp="$(_run_command --no-exit -- mktemp "$PB_STATE/recipients.XXXXXX")" || return 1
  trap '_run_command --no-exit -- rm -f -- "$tmp"' EXIT
  _run_command --no-exit -- awk -v name="$name" '$1 != name {print}' "$PB_STATE/recipients" > "$tmp" || return 1
  _run_command --no-exit -- mv -f -- "$tmp" "$PB_STATE/recipients" || return 1
  FORCE=1 password_bundle_publish
) }

function password_bundle_publish() { (
  set +x
  local payload hash old='' change=0 count=0 name key extra tmp meta stamp host
  local -a args=() names=()
  _password_bundle_paths
  umask 077
  [[ -r "$PB_STATE/last-change" ]] && read -r change < "$PB_STATE/last-change"
  if [[ -r "$PB_STATE/recipients" ]]; then
    while read -r name key extra; do
      [[ "$name" =~ ^[a-z0-9-]{1,32}$ && "$key" =~ ^age1[02-9ac-hj-np-z]{58}$ && -z "$extra" ]] || { _password_bundle_metrics 0 "$change" "$count"; return 1; }
      args+=(-r "$key"); names+=("$name"); count=$((count + 1))
    done < "$PB_STATE/recipients"
  fi
  if (( count == 0 )); then _password_bundle_metrics 0 "$change" 0; echo 'No recipients.' >&2; return 1; fi
  _run_command --no-exit -- mkdir -p -- "$PB_DIR" || { _password_bundle_metrics 0 "$change" "$count"; return 1; }
  if _run_command --no-exit --quiet -- git -C "$PB_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then _password_bundle_metrics 0 "$change" "$count"; echo 'Delivery folder is inside a git work tree.' >&2; return 1; fi
  if ! payload="$(_run_command --no-exit -- make -s show-service-passwords && printf '\001')"; then _password_bundle_metrics 0 "$change" "$count"; return 1; fi
  payload="${payload%$'\001'}"
  hash="$(printf '%s' "$payload" | _run_command --no-exit -- shasum -a 256)" || return 1
  hash="${hash%% *}"
  [[ -r "$PB_STATE/last.sha256" ]] && read -r old < "$PB_STATE/last.sha256"
  if [[ "$hash" == "$old" && "${FORCE:-0}" != 1 ]]; then _password_bundle_metrics 1 "$change" "$count"; return 0; fi
  tmp="$(_run_command --no-exit -- mktemp "$PB_DIR/.service-passwords.age.XXXXXX")" || return 1
  meta="$(_run_command --no-exit -- mktemp "$PB_DIR/.service-passwords.meta.XXXXXX")" || { _run_command --no-exit -- rm -f -- "$tmp"; return 1; }
  trap '_run_command --no-exit -- rm -f -- "$tmp" "$meta"' EXIT
  if ! printf '%s' "$payload" | _run_command --no-exit -- age -e "${args[@]}" > "$tmp"; then _password_bundle_metrics 0 "$change" "$count"; return 1; fi
  stamp="$( _run_command --no-exit -- date -u +%Y-%m-%dT%H:%M:%SZ)"; host="$( _run_command --no-exit -- hostname)"
  printf 'generated_at: %s\nhub_host: %s\nrecipients:' "$stamp" "$host" > "$meta"
  printf ' %s' "${names[@]}" >> "$meta"; printf '\n' >> "$meta"
  _run_command --no-exit -- mv -f -- "$tmp" "$PB_DIR/service-passwords.age" || return 1
  _run_command --no-exit -- mv -f -- "$meta" "$PB_DIR/service-passwords.meta" || return 1
  printf '%s\n' "$hash" > "$PB_STATE/last.sha256"
  change="$( _run_command --no-exit -- date +%s)"; printf '%s\n' "$change" > "$PB_STATE/last-change"
  _password_bundle_metrics 1 "$change" "$count"
) }

function password_bundle_show() { (
  set +x
  local identity stamp epoch now
  _password_bundle_paths
  identity="$(_run_command --no-exit -- security find-generic-password -a identity -s k3dm-password-bundle-age -w)" || return 1
  [[ -r "$PB_DIR/service-passwords.meta" && -r "$PB_DIR/service-passwords.age" ]] || return 1
  stamp="$( _run_command --no-exit -- awk '/^generated_at: / {print $2; exit}' "$PB_DIR/service-passwords.meta")"
  [[ -n "$stamp" ]] || return 1
  printf 'generated_at: %s\n' "$stamp"
  epoch="$( _run_command --no-exit --quiet -- date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$stamp" +%s 2>/dev/null || _run_command --no-exit --quiet -- date -u -d "$stamp" +%s 2>/dev/null)" || return 1
  now="$( _run_command --no-exit -- date +%s)"; (( now - epoch <= 86400 )) || echo 'Warning: bundle is more than 24 hours old.' >&2
  _run_command --no-exit -- age -d -i <(printf '%s\n' "$identity") "$PB_DIR/service-passwords.age"
) }

function password_bundle_install() { (
  local template="$SCRIPT_DIR/etc/launchd/com.k3d-manager.password-bundle.plist.tmpl" plist="$HOME/Library/LaunchAgents/com.k3d-manager.password-bundle.plist"
  _is_mac || return 1
  _run_command --no-exit -- mkdir -p -- "${plist%/*}" || return 1
  _run_command --no-exit -- sed -e "s|{{K3D_MANAGER_PATH}}|${SCRIPT_DIR}/k3d-manager|g" -e "s|{{HOME}}|${HOME}|g" -e "s|{{REPO_ROOT}}|${SCRIPT_DIR%/*}|g" "$template" > "$plist" || return 1
  if [[ "${K3DM_AGENT_LOAD:-1}" != 0 ]]; then
    _run_command --no-exit --quiet -- launchctl bootout "gui/$(id -u)/com.k3d-manager.password-bundle" 2>/dev/null || true
    _run_command --no-exit -- launchctl bootstrap "gui/$(id -u)" "$plist"
  fi
) }

function password_bundle_uninstall() { (
  _is_mac || return 1
  _run_command --no-exit --quiet -- launchctl bootout "gui/$(id -u)/com.k3d-manager.password-bundle" 2>/dev/null || true
  _run_command --no-exit -- rm -f -- "$HOME/Library/LaunchAgents/com.k3d-manager.password-bundle.plist"
) }
