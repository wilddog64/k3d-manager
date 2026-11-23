# shellcheck shell=bash
_WC_LABEL=com.k3d-manager.web-console-sshd
_WC_CONF_DIR=/etc/k3dm-web-console
_WC_HELPER_DIR=/Library/PrivilegedHelperTools/k3dm-web-console
_WC_LAUNCHD_DIR=/Library/LaunchDaemons
_WC_LOCK=/var/db/k3dm-web-console.lock
_WC_JOURNAL=/var/db/k3dm-web-console.txn
_WC_LOG=/var/log/k3dm-web-console-sshd.log
_WC_PREFIX=

function _wc_message() {
  printf 'web-console-sshd: %s\n' "$*" >&2
}

function _wc_priv() {
  _run_command --interactive-sudo --soft --quiet -- "$@"
}

function _wc_tool() {
  "$@"
}

function _wc_fixture_call() {
  local role="$1" tool="$2"
  shift 2
  local shim="${_WC_PREFIX}/bin/${tool##*/}"
  [[ -x "$shim" ]] || return 2
  { printf '%s %q' "$role" "$tool"; printf ' %q' "$@"; printf '\n'; } >> "${_WC_PREFIX}/calls.log" || return 2
  PATH='' "$shim" "$@"
}

function _wc_fixture_gate() {
  [[ ${K3DM_WC_ROOT+x} ]] || return 0
  [[ -n "$K3DM_WC_ROOT" && -f "$K3DM_WC_ROOT/.k3dm-wc-fixture" ]] || return 2
  [[ $EUID != 0 && "$K3DM_WC_ROOT" == /* && "$K3DM_WC_ROOT" != / ]] || return 2
  _WC_PREFIX="${K3DM_WC_ROOT%/}"
  local tool
  for tool in install stat ls cp mv rm mkdir touch tee mktemp launchctl sshd ssh-keygen netstat ps shasum plutil id kill sleep true git uname head date; do
    [[ -x "$_WC_PREFIX/bin/$tool" ]] || return 2
  done
  # shellcheck disable=SC2329
  _wc_priv() { _wc_fixture_call priv "$@"; }
  # shellcheck disable=SC2329
  _wc_tool() { _wc_fixture_call tool "$@"; }
}

function _wc_priv_open() {
  if [[ -n "$_WC_PREFIX" ]]; then
    printf '%s\n' priv_open >> "$_WC_PREFIX/calls.log" || return 10
  elif [[ ! -t 0 || ! -t 1 ]]; then
    _wc_message 'an interactive terminal is required for the password prompt'
    return 10
  fi
  _wc_priv /bin/sleep 0 2>/dev/null || return 10
  _wc_priv_ticket || {
    _wc_message 'cached admin ticket not usable from a pipe; timestamp_timeout must be greater than 0'
    return 10
  }
}

function _wc_priv_ticket() {
  local out; out=$(_wc_priv /usr/bin/id -u </dev/null 2>/dev/null) && [[ "$out" = 0 ]] || return 10
}

function _wc_untrusted() {
  _wc_message "untrusted path $1 ($2); nothing written"
  return 8
}

function _wc_trust_one() {
  local name="$1" path="$_WC_PREFIX$1" owner mode listing target
  if [[ -L "$path" ]]; then
    target=$(_wc_tool /usr/bin/stat -f %Y "$path") || return 8
    case "$name:$target" in /etc:private/etc|/var:private/var|/tmp:private/tmp) ;; *) _wc_untrusted "$name" symlink; return 8 ;; esac
  fi
  owner=$(_wc_tool /usr/bin/stat -f %u "$path") || return 8
  [[ "$owner" = 0 ]] || { _wc_untrusted "$name" owner; return 8; }
  [[ -L "$path" ]] && return 0
  mode=$(_wc_tool /usr/bin/stat -f %Lp "$path") || return 8
  { [[ "$mode" =~ ^[0-7]{3,4}$ ]] && (( (8#$mode & 022) == 0 )); } || { _wc_untrusted "$name" writable; return 8; }
  listing=$(_wc_tool /bin/ls -lde "$path") || return 8
  [[ "${listing%%[[:space:]]*}" != *+ && "$listing" != *$'\n'* ]] || { _wc_untrusted "$name" ACL; return 8; }
  case "$name" in
    */.prev) [[ "$mode" = 700 ]] || { _wc_untrusted "$name" 'expected 0700'; return 8; } ;;
    */zdotdir)
      listing=$(_wc_tool /bin/ls -A "$path") || return 8
      [[ -z "$listing" ]] || { _wc_untrusted "$name" 'not empty'; return 8; } ;;
  esac
}

function _wc_trust_check() {
  local path
  for path in "$@"; do _wc_trust_one "$path" || return 8; done
}

function _wc_dest_check() {
  local path dest
  for path in "$@"; do
    dest="$_WC_PREFIX$path"
    [[ ! -L "$dest" ]] || { _wc_untrusted "$path" symlink; return 8; }
    [[ -e "$dest" ]] || continue
    [[ -f "$dest" ]] || { _wc_untrusted "$path" 'not a regular file'; return 8; }
    _wc_trust_one "$path" || return 8
  done
}

function _wc_port_lookup() {
  local line pattern='^ListenAddress 127\.0\.0\.1:([0-9]+)$'
  if line=$(_wc_tool /usr/bin/head -n 1 "$_WC_PREFIX$_WC_CONF_DIR/sshd_config" 2>/dev/null) && [[ "$line" =~ $pattern ]]; then
    printf '%s installed\n' "${BASH_REMATCH[1]}"
  elif line=$(_wc_priv /usr/bin/head -n 1 "$_WC_PREFIX$_WC_CONF_DIR/.prev/sshd_config" 2>/dev/null) && [[ "$line" =~ $pattern ]]; then
    printf '%s prev\n' "${BASH_REMATCH[1]}"
  elif [[ ${WEB_CONSOLE_SSH_PORT+x} ]]; then
    printf '%s env\n' "$WEB_CONSOLE_SSH_PORT"
  else
    printf '42722 default\n'
  fi
}

function _wc_job_absent() {
  local result rc
  result=$(_wc_tool /bin/launchctl print "system/${_WC_LABEL}" 2>&1) && return 1
  rc=$?
  [[ "$rc" = 113 && "$result" = *"Could not find service \"${_WC_LABEL}\" in domain for system" ]]
}

function _wc_revoke_reconcile() {
  local plist="$_WC_PREFIX$_WC_LAUNCHD_DIR/${_WC_LABEL}.plist" changed=0
  [[ -f "$_WC_PREFIX$_WC_CONF_DIR/revoked" ]] || return 0
  if [[ -e "$plist" ]]; then
    _wc_priv /bin/mv -f "$plist" "$_WC_PREFIX$_WC_CONF_DIR/launchd.plist.revoked" 2>/dev/null && changed=1
  fi
  if ! _wc_job_absent; then
    _wc_priv /bin/launchctl bootout "system/${_WC_LABEL}" 2>/dev/null || _wc_job_absent || return 1
    changed=1
  fi
  [[ ! -e "$plist" ]] || return 1
  (( changed == 0 )) || _wc_message 'revoked marker present; daemon plist parked'
  [[ ! -e "$plist" ]] && _wc_job_absent
}

function _wc_stage_new() {
  _wc_priv /usr/bin/mktemp -d "$_WC_PREFIX$1/.stage.XXXXXXXX" 2>/dev/null || return 8
}

function _wc_hash_stdin() {
  local result
  result=$(_wc_tool /usr/bin/shasum -a 256) || return 8
  printf '%s\n' "${result%% *}"
}

function _wc_stage_hash() {
  local result
  result=$(_wc_priv /usr/bin/shasum -a 256 "$1" 2>/dev/null) || return 8
  printf '%s\n' "${result%% *}"
}

function _wc_stage_put() {
  local stage="$1" name="$2" mode="$3" bytes expected actual
  [[ "$name" != */* && -n "$name" && "$name" != . && "$name" != .. ]] || return 8
  if IFS= read -r -d '' bytes; then return 8; fi
  expected=$(printf '%s' "$bytes" | _wc_hash_stdin) || return 8
  _wc_priv /usr/bin/install -o root -g wheel -m "$mode" "$_WC_PREFIX/dev/null" "$stage/$name" 2>/dev/null || return 8
  printf '%s' "$bytes" | _wc_priv /usr/bin/tee "$stage/$name" >/dev/null 2>/dev/null || return 8
  actual=$(_wc_priv /usr/bin/shasum -a 256 "$stage/$name" 2>/dev/null) || return 8
  [[ "${actual%% *}" = "$expected" ]] || return 8
}

function _wc_stage_clean() {
  local path
  for path in "$_WC_PREFIX$1"/.stage.*; do
    [[ -e "$path" || -L "$path" ]] || continue
    _wc_priv /bin/rm -rf -- "$path" 2>/dev/null || return 5
  done
}

function _wc_txn_begin() {
  _WC_SEQUENCE=0
  _wc_priv /usr/bin/install -o root -g wheel -m 0600 "$_WC_PREFIX/dev/null" "$_WC_PREFIX$_WC_JOURNAL" 2>/dev/null || return 5
}

function _wc_txn_record() {
  local kind="$1" dest="$2" backup="${3:--}"
  _WC_SEQUENCE=$(( ${_WC_SEQUENCE:-0} + 1 ))
  printf '%s %s %s %s\n' "$_WC_SEQUENCE" "$kind" "$dest" "$backup" |
    _wc_priv /usr/bin/tee -a "$_WC_PREFIX$_WC_JOURNAL" >/dev/null 2>/dev/null || return 5
}

function _wc_txn_end() {
  _wc_priv /bin/rm -f "$_WC_PREFIX$_WC_JOURNAL" 2>/dev/null || return 5
}

function _wc_backup_name() {
  local dest="$1" parent
  case "${dest%/*}" in
    "$_WC_CONF_DIR"|"$_WC_LAUNCHD_DIR") parent="$_WC_CONF_DIR" ;;
    "$_WC_HELPER_DIR") parent="$_WC_HELPER_DIR" ;;
    *) return 2 ;;
  esac
  [[ "${dest##*/}" != .* && -n "${dest##*/}" ]] || return 2
  printf '%s/.prev/%s\n' "$parent" "${dest##*/}"
}

function _wc_restore_line() {
  local kind="$1" dest="$2" backup="$3" target="$2" expected saved current
  case "$kind" in
    created)
      case "$dest" in
        "$_WC_CONF_DIR"|"$_WC_HELPER_DIR"|"$_WC_CONF_DIR/zdotdir"|"$_WC_CONF_DIR/.prev"|"$_WC_HELPER_DIR/.prev"|/var/db/k3dm-web-console|/var/db/k3dm-web-console-run) ;;
        *) return 5 ;;
      esac
      [[ "$dest" != "$_WC_CONF_DIR" || ! -f "$_WC_PREFIX$_WC_CONF_DIR/revoked" ]] || return 0
      _wc_priv /bin/rm -rf -- "$_WC_PREFIX$dest" 2>/dev/null || return 5
      ;;
    moved)
      expected=$(_wc_backup_name "$dest") || return 5
      if [[ "$dest" = "$_WC_LAUNCHD_DIR/${_WC_LABEL}.plist" && -f "$_WC_PREFIX$_WC_CONF_DIR/revoked" ]]; then
        target="$_WC_CONF_DIR/launchd.plist.revoked"
      fi
      if [[ "$backup" = - ]]; then
        _wc_priv /bin/rm -f -- "$_WC_PREFIX$target" 2>/dev/null || return 5
      else
        [[ "$backup" = "$expected" ]] || return 5
        saved=$(_wc_stage_hash "$_WC_PREFIX$backup") || return 5
        if [[ -f "$_WC_PREFIX$target" ]]; then
          current=$(_wc_stage_hash "$_WC_PREFIX$target") || return 5
          [[ "$current" != "$saved" ]] || return 0
        fi
        _wc_priv /bin/cp -p "$_WC_PREFIX$backup" "$_WC_PREFIX$backup.restore" 2>/dev/null || return 5
        _wc_priv /bin/mv -f "$_WC_PREFIX$backup.restore" "$_WC_PREFIX$target" 2>/dev/null || return 5
      fi ;;
    *) return 5 ;;
  esac
}

function _wc_txn_recover() {
  local lines=() content line seq kind dest backup extra i
  if [[ -f "$_WC_PREFIX$_WC_JOURNAL" ]]; then
    content=$(_wc_priv /usr/bin/head -n 10000 "$_WC_PREFIX$_WC_JOURNAL" 2>/dev/null) || return 5
    while IFS= read -r line; do
      [[ -z "$line" ]] || lines+=("$line")
    done <<< "$content"
    for ((i=${#lines[@]}-1; i>=0; i--)); do
      read -r seq kind dest backup extra <<< "${lines[i]}"
      if [[ "$seq" != "$((i+1))" || -n "$extra" ]] || ! _wc_restore_line "$kind" "$dest" "$backup"; then
        _wc_message 'restore incomplete; journal kept; rerun install'; return 5
      fi
    done
    _wc_txn_end || return 5
    _wc_message 'rolled back an interrupted install'
  fi
  _wc_revoke_reconcile || return 1
}

function _wc_commit_one() {
  local stage="$1" dest="$2" backup
  backup=$(_wc_backup_name "$dest") || return 2
  if [[ -e "$_WC_PREFIX$dest" ]]; then
    _wc_priv /bin/cp -p "$_WC_PREFIX$dest" "$_WC_PREFIX$backup" 2>/dev/null || return 5
  else
    backup=-
  fi
  _wc_txn_record moved "$dest" "$backup" || return 5
  _wc_priv /bin/mv -f "$stage/${dest##*/}" "$_WC_PREFIX$dest" 2>/dev/null || return 5
}

function _wc_commit() {
  local stage="$1" dest; shift
  for dest in "$@"; do _wc_backup_name "$dest" >/dev/null || return 2; done
  for dest in "$@"; do
    _wc_commit_one "$stage" "$dest" || {
      _wc_txn_recover || return "$?"
      _wc_message 'commit failed; previous generation restored'; return 5
    }
  done
}

function _wc_manifest_put() {
  local stage="$1" part="$2" path="$3" hash="$4" blob="$5"
  printf '%s %s %s %s\n' "$hash" "$path" "$part" "$blob" |
    _wc_priv /usr/bin/tee -a "$stage/manifest" >/dev/null 2>/dev/null || return 8
}

function _wc_listener() {
  local port="$1" sockets job proto _ _ addr _ state _ _ _ _ owner _ pid uid count=0
  sockets=$(_wc_tool /usr/sbin/netstat -anv -p tcp) || return 3
  while read -r proto _ _ addr _ state _ _ _ _ owner _; do
    [[ "$proto" = tcp* && "$state" = LISTEN && "${addr##*.}" = "$port" ]] || continue
    count=$((count+1))
    [[ "$addr" = "127.0.0.1.$port" ]] || return 3
    pid="${owner##*:}"
  done <<< "$sockets"
  if (( ! count )); then _wc_job_absent && return 1; return 3; fi
  [[ "$count" = 1 && "$pid" =~ ^[1-9][0-9]*$ ]] || return 3
  uid=$(_wc_tool /bin/ps -o uid= -p "$pid") || return 3
  [[ "${uid//[[:space:]]/}" = 0 ]] || return 3
  job=$(_wc_tool /bin/launchctl print "system/${_WC_LABEL}" 2>/dev/null) || return 3
  local line
  while IFS= read -r line; do
    [[ "$line" =~ ^[[:space:]]*pid[[:space:]]*=[[:space:]]*([0-9]+)[[:space:]]*$ ]] || continue
    [[ "${BASH_REMATCH[1]}" = "$pid" ]] || return 3
    printf '%s\n' "$pid"; return 0
  done <<< "$job"
  return 3
}

function _wc_ps_snapshot() {
  local table pid ppid uid dow mon day clock year args
  table=$(_wc_tool /bin/ps -axo pid=,ppid=,uid=,lstart=,command=) || return 1
  parents=() uids=() started=() titles=()
  while read -r pid ppid uid dow mon day clock year args; do
    [[ "$pid" =~ ^[1-9][0-9]*$ && "$ppid" =~ ^[0-9]+$ && "$uid" =~ ^[0-9]+$ ]] || continue
    parents[pid]="$ppid" uids[pid]="$uid" started[pid]="$dow $mon $day $clock $year"
    titles[pid]="${args%"${args##*[![:space:]]}"}"
  done <<< "$table"
}

function _wc_is_priv_session() {
  local pid="$1"
  [[ "${uids[pid]-}" = 0 && "${titles[pid]-}" = 'sshd-session: '*" [priv]" ]]
}

function _wc_expand_tree() {
  local changed=1 pid parent
  while (( changed )); do
    changed=0
    for pid in "${!parents[@]}"; do
      parent="${parents[pid]}"
      if [[ ${excluded[parent]+x} && ! ${excluded[pid]+x} ]]; then
        excluded[pid]=1; changed=1
      elif [[ ! ${excluded[pid]+x} && ! ${members[pid]+x} && ${members[parent]+x} && "${members[parent]}" = "${started[parent]-}" ]]; then
        members[pid]="${started[pid]}"; changed=1
      fi
    done
  done
}

function _wc_snapshot_sockets() {
  local port="$1" listener="$2" sockets proto _ _ addr _ state _ _ _ _ owner _ pid parent
  sockets=$(_wc_tool /usr/sbin/netstat -anv -p tcp) || return 1
  while read -r proto _ _ addr _ state _ _ _ _ owner _; do
    [[ "$proto" = tcp* && "${addr##*.}" = "$port" && "$state" = LISTEN ]] || continue
    pid="${owner##*:}"
    [[ "$pid" =~ ^[1-9][0-9]*$ && ${started[pid]+x} ]] || continue
    [[ "$pid" = "$listener" && "$addr" = "127.0.0.1.$port" ]] || { excluded[pid]=1; stop_error=1; }
  done <<< "$sockets"
  _wc_expand_tree
  live_count=0
  while read -r proto _ _ addr _ state _ _ _ _ owner _; do
    [[ "$proto" = tcp* && "$addr" = "127.0.0.1.$port" ]] || continue
    case "$state" in LISTEN|SYN_RCVD|ESTABLISHED|CLOSE_WAIT|FIN_WAIT_1) ;; *) continue ;; esac
    pid="${owner##*:}"
    [[ "$pid" =~ ^[1-9][0-9]*$ && ${started[pid]+x} ]] || continue
    live_count=$((live_count+1))
    [[ ! ${excluded[pid]+x} && ! ${members[pid]+x} ]] || continue
    parent="${parents[pid]}"
    if _wc_is_priv_session "$pid"; then members[pid]="${started[pid]}"
    elif [[ "${titles[pid]}" = 'sshd-session: '* && ! ${excluded[parent]+x} ]] && _wc_is_priv_session "$parent"; then
      members[pid]="${started[pid]}" members[parent]="${started[parent]}"
    else
      _wc_message "socket owner $pid is not a console session; not signalled"
      excluded[pid]=1; stop_error=1
    fi
  done <<< "$sockets"
  _wc_expand_tree
}

function _wc_signal_set() {
  local signal="$1" pid start
  for pid in "${!members[@]}"; do
    [[ ! ${excluded[pid]+x} ]] || continue
    start=$(_wc_tool /bin/ps -o lstart= -p "$pid" 2>/dev/null) || continue
    local dow mon day clock year
    read -r dow mon day clock year <<< "$start"
    [[ "$dow $mon $day $clock $year" = "${members[pid]}" ]] || continue
    _wc_priv /bin/kill "-$signal" "$pid" 2>/dev/null || continue
  done
}

function _wc_stop_wait() {
  local seconds="$1" scale="$2" whole fraction factor
  [[ "$scale" =~ ^([0-9]{1,4})(\.([0-9]{1,6}))?$ ]] || return 2
  whole="${BASH_REMATCH[1]}"; fraction="${BASH_REMATCH[3]}000000"
  factor=$((10#$whole * 1000000 + 10#${fraction:0:6}))
  (( factor != 0 )) || return 0
  local duration
  printf -v duration '%d.%06d' "$((seconds * factor / 1000000))" "$((seconds * factor % 1000000))"
  _wc_tool /bin/sleep "$duration"
}

function _wc_stop() {
  local port="$1" listener rc=0 stop_error=0 live_count=0 pid delay scale=1
  local parents=() uids=() started=() titles=() members=() excluded=()
  listener=$(_wc_listener "$port") || rc=$?
  [[ "$rc" != 3 ]] || stop_error=1
  _wc_ps_snapshot || stop_error=1
  if [[ "$rc" = 0 && ${started[listener]+x} ]]; then members[listener]="${started[listener]}"; fi
  _wc_snapshot_sockets "$port" "$listener" || stop_error=1
  _wc_priv /bin/launchctl bootout "system/${_WC_LABEL}" 2>/dev/null || rc=$?
  if [[ -n "$_WC_PREFIX" ]]; then scale="${K3DM_WC_STOP_WAIT_SCALE-1}"; fi
  for delay in 5 3; do
    _wc_stop_wait "$delay" "$scale" || return 1
    { _wc_ps_snapshot && _wc_snapshot_sockets "$port" "$listener"; } || { stop_error=1; continue; }
    if [[ "$delay" = 5 ]]; then _wc_signal_set TERM; else _wc_signal_set KILL; fi
  done
  { _wc_ps_snapshot && _wc_snapshot_sockets "$port" "$listener"; } || stop_error=1
  for pid in "${!members[@]}"; do
    [[ "${members[pid]}" != "${started[pid]-}" ]] || { _wc_message "survivor $pid"; stop_error=1; }
  done
  _wc_job_absent || { _wc_message 'job still registered after bootout'; stop_error=1; }
  (( stop_error == 0 && live_count == 0 ))
}

function _wc_trust_chain() {
  local pending="${1#/}" parent='' part path target hops=0 uid
  [[ "$1" = /* ]] || return 8
  _wc_trust_check / || return 8
  while [[ -n "$pending" ]]; do
    part="${pending%%/*}"
    if [[ "$pending" = */* ]]; then pending="${pending#*/}"; else pending=; fi
    case "$part" in ''|.) continue ;; ..) parent="${parent%/*}"; continue ;; esac
    path="$parent/$part"
    if [[ -L "$_WC_PREFIX$path" ]]; then
      (( hops < 16 )) || return 8
      hops=$((hops+1))
      uid=$(_wc_tool /usr/bin/stat -f %u "$_WC_PREFIX$path") || return 8
      [[ "$uid" = 0 ]] || return 8
      target=$(_wc_tool /usr/bin/stat -f %Y "$_WC_PREFIX$path") || return 8
      printf '%s -> %s\n' "$path" "$target"
      [[ "$target" != /* ]] || parent=
      pending="${target#/}${pending:+/$pending}"
      continue
    fi
    _wc_trust_check "$path" || return 8
    [[ -z "$pending" || -d "$_WC_PREFIX$path" ]] || return 8
    parent="$path"
  done
  [[ -f "$_WC_PREFIX$parent" ]] || return 8
}

function _wc_lock_live() {
  local lock="$_WC_PREFIX$_WC_LOCK" holder pid start now actual mtime
  if [[ -f "$lock/holder" ]]; then
    IFS= read -r holder < "$lock/holder" || return 0
    read -r pid start <<< "$holder"
    [[ "$pid" =~ ^[1-9][0-9]*$ ]] || return 1
    actual=$(_wc_tool /bin/ps -o lstart= -p "$pid" 2>/dev/null) || return 1
    [[ "$actual" = "$start" ]]
  else
    now=$(_wc_tool /bin/date +%s) || return 0
    mtime=$(_wc_tool /usr/bin/stat -f %m "$lock") || return 0
    [[ "$now" =~ ^[0-9]+$ && "$mtime" =~ ^[0-9]+$ ]] && (( now - mtime < 10 ))
  fi
}

function _wc_reclaim() {
  local guard="$_WC_PREFIX$_WC_LOCK.reclaim" lock="$_WC_PREFIX$_WC_LOCK" now mtime rc=0
  if ! _wc_priv /bin/mkdir "$guard" 2>/dev/null; then
    now=$(_wc_tool /bin/date +%s) || return 7
    mtime=$(_wc_tool /usr/bin/stat -f %m "$guard") || return 7
    if [[ "$now" =~ ^[0-9]+$ && "$mtime" =~ ^[0-9]+$ ]] && (( now - mtime > 60 )); then
      _wc_message "stale reclaim guard $_WC_LOCK.reclaim; remove it after checking that no install runs"
    fi
    return 7
  fi
  if _wc_lock_live; then rc=7
  else
    _wc_priv /bin/rm -rf -- "$lock" 2>/dev/null && _wc_priv /bin/mkdir "$lock" 2>/dev/null || rc=7
  fi
  _wc_priv /bin/rm -d "$guard" 2>/dev/null || return 7
  return "$rc"
}

function _wc_lock_take() {
  local lock="$_WC_PREFIX$_WC_LOCK" start
  if ! _wc_priv /bin/mkdir "$lock" 2>/dev/null; then
    if _wc_lock_live; then _wc_message 'another install or uninstall holds the lock'; return 7; fi
    _wc_reclaim || return 7
  fi
  start=$(_wc_tool /bin/ps -o lstart= -p "$$") || return 7
  printf '%s %s\n' "$$" "$start" | _wc_priv /usr/bin/tee "$lock/holder" >/dev/null 2>/dev/null || return 7
}

function _wc_lock_release() {
  _wc_priv /bin/rm -rf -- "$_WC_PREFIX$_WC_LOCK" 2>/dev/null || return 7
}

function _wc_revoke_mark() {
  local dir="$_WC_PREFIX$_WC_CONF_DIR" id
  if [[ ! -d "$dir" ]]; then
    _wc_priv /usr/bin/install -d -o root -g wheel -m 0755 "$dir" 2>/dev/null || return 1
  fi
  id=$(_wc_tool /bin/date -u +%Y%m%dT%H%M%SZ) || return 1
  id="$id.$$"
  _wc_priv /usr/bin/install -o root -g wheel -m 0644 "$_WC_PREFIX/dev/null" "$dir/revoked.tmp.$$" 2>/dev/null || return 1
  printf '%s\n' "$id" | _wc_priv /usr/bin/tee "$dir/revoked.tmp.$$" >/dev/null 2>/dev/null || return 1
  _wc_priv /bin/mv -f "$dir/revoked.tmp.$$" "$dir/revoked" 2>/dev/null || return 1
  printf '%s\n' "$id"
}
