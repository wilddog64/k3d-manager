#!/usr/bin/env bash
# Protect operator-owned SSH aliases from config files managed by provisioning tools.

function _ssh_config_guard_has_alias() {
  local config="$1" alias="$2" hostname
  hostname="$(ssh -G -F "$config" "$alias" 2>/dev/null | awk '$1 == "hostname" { print $2; exit }')" || return 1
  [[ -n "$hostname" && "$hostname" != "$alias" ]]
}

function _ssh_config_guard_fragment_has_alias() {
  local fragment="$1" alias="$2" hostname
  hostname="$(ssh -G -F "$fragment" "$alias" 2>/dev/null | awk '$1 == "hostname" { print $2; exit }')" || return 1
  [[ -n "$hostname" && "$hostname" != "$alias" ]]
}

function _ssh_config_guard_bytes() {
  local config="$1"
  if [[ -f "$config" ]]; then wc -c < "$config" | tr -d ' '; else printf '0\n'; fi
}

function _ssh_config_guard_mtime() {
  local config="$1"
  if [[ ! -e "$config" ]]; then printf 'missing\n'; return 0; fi
  if stat -f '%Sm' -t '%Y-%m-%dT%H:%M:%S%z' "$config" >/dev/null 2>&1; then stat -f '%Sm' -t '%Y-%m-%dT%H:%M:%S%z' "$config"
  else date -r "$config" '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null || printf 'unknown\n'; fi
}

function _ssh_config_guard_write_include() {
  local config="$1" fragment="$2" backup stamp tmp include_line suffix=0 i
  local -a backups=()
  mkdir -p "$(dirname "$config")" || return 1
  stamp="$(date -u '+%Y%m%dT%H%M%SZ')"
  backup="${config}.k3dm-guard.${stamp}"
  while [[ -e "$backup" ]]; do suffix=$((suffix + 1)); backup="${config}.k3dm-guard.${stamp}.$$.$suffix"; done
  if [[ -e "$config" ]]; then cp "$config" "$backup" || return 1; else : > "$backup" || return 1; fi
  chmod 600 "$backup" || return 1
  include_line="Include $fragment"
  tmp="$(mktemp "$(dirname "$config")/.ssh-config-guard.XXXXXX")" || return 1
  if [[ -f "$config" ]] && grep -Fqx "$include_line" "$config"; then
    cp "$config" "$tmp" || { rm -f "$tmp"; return 1; }
  else
    { printf '%s\n' "$include_line"; [[ ! -f "$config" ]] || cat "$config"; } > "$tmp" || { rm -f "$tmp"; return 1; }
  fi
  if ! chmod 600 "$tmp"; then rm -f "$tmp"; return 1; fi
  if ! mv "$tmp" "$config"; then rm -f "$tmp"; return 1; fi
  while IFS= read -r backup; do backups+=("$backup"); done < <(find "$(dirname "$config")" -maxdepth 1 -type f -name "$(basename "$config").k3dm-guard.*" -print | sort -r)
  for ((i=5; i<${#backups[@]}; i++)); do rm -f "${backups[$i]}"; done
}

function _ssh_config_guard() {
  local repair=0 config fragment alias missing="" bytes mtime
  local -a aliases=() missing_aliases=()
  if [[ "${1:-}" == --repair ]]; then repair=1; shift; fi
  (($# > 0)) || { printf 'ERROR: [ssh-guard] usage: _ssh_config_guard [--repair] <alias>...\n' >&2; return 2; }
  aliases=("$@")
  config="${K3DM_SSH_CONFIG:-${HOME}/.ssh/config}"
  fragment="${K3DM_SSH_OPERATOR_FRAGMENT:-${HOME}/.ssh/config.d/operator}"
  for alias in "${aliases[@]}"; do
    _ssh_config_guard_has_alias "$config" "$alias" || missing_aliases+=("$alias")
  done
  ((${#missing_aliases[@]} == 0)) && return 0
  bytes="$(_ssh_config_guard_bytes "$config")"
  mtime="$(_ssh_config_guard_mtime "$config")"
  missing="$(printf '%s ' "${missing_aliases[@]}")"; missing="${missing% }"
  printf 'WARN: [ssh-guard] ~/.ssh/config missing alias(es): %s (config %s bytes, mtime %s)\n' "$missing" "$bytes" "$mtime" >&2
  if (( repair == 0 )) || [[ ! -r "$fragment" ]]; then
    printf 'WARN: [ssh-guard] cannot restore aliases; operator fragment: %s\n' "$fragment" >&2
    return 1
  fi
  for alias in "${missing_aliases[@]}"; do
    if ! _ssh_config_guard_fragment_has_alias "$fragment" "$alias"; then
      printf 'WARN: [ssh-guard] operator fragment %s does not define %s\n' "$fragment" "$alias" >&2
      return 1
    fi
  done
  _ssh_config_guard_write_include "$config" "$fragment" || return 1
  for alias in "${missing_aliases[@]}"; do _ssh_config_guard_has_alias "$config" "$alias" || return 1; done
  printf 'INFO: [ssh-guard] restored Include for %s\n' "$missing" >&2
}
