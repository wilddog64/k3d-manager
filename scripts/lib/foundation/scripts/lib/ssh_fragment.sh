#!/usr/bin/env bash
# Shared read/write helpers for the ACG sandbox SSH fragment.

function _ssh_fragment_path() {
  printf '%s\n' "${K3DM_SSH_SANDBOX_FRAGMENT:-${HOME}/.ssh/k3dm-sandbox.conf}"
}

function _ssh_fragment_main_config() {
  printf '%s\n' "${HOME}/.ssh/config"
}

function _ssh_fragment_error() {
  printf 'ERROR: %s\n' "[ssh-fragment] $*" >&2
}

function _ssh_fragment_warn() {
  printf 'WARN: %s\n' "[ssh-fragment] $*" >&2
}

function _ssh_fragment_write_python() {
  local fragment="$1" mode="$2" alias="${3:-}" extra="${4:-}" dir tmp rc=0
  [[ ! -L "$fragment" ]] || { _ssh_fragment_error "refusing symlink fragment: ${fragment}"; return 1; }
  dir="$(dirname "$fragment")"
  (umask 077 && mkdir -p "$dir") || { _ssh_fragment_error "cannot create fragment directory: ${dir}"; return 1; }
  tmp=$(mktemp "${dir}/.k3dm-sandbox.XXXXXX") || { _ssh_fragment_error "cannot create temporary fragment"; return 1; }
  _run_command -- python3 - "$fragment" "$tmp" "$mode" "$alias" "$extra" <<'PY' || rc=$?
import os, re, sys
path, out, mode, alias, extra = sys.argv[1:]
text = open(path).read() if os.path.exists(path) else ''
lines = text.splitlines(True)
starts = [i for i, line in enumerate(lines) if re.match(r'^\s*(Host|Match)(?:\s|=)', line, re.I)]
blocks = []
for n, start in enumerate(starts):
    end = starts[n + 1] if n + 1 < len(starts) else len(lines)
    chunk = lines[start:end]
    header = chunk[0].split('#', 1)[0].strip().replace('=', ' ', 1)
    head = header.split()
    blocks.append((head, chunk))
def matches(head, name):
    selected = len(head) > 1 and head[0].lower() == 'host'
    if selected and len(head) > 2 and name in head[1:]:
        print('WARN: [ssh-fragment] leaving multi-alias stanza unchanged: ' + ' '.join(head), file=sys.stderr)
    return selected and head[1:] == [name]
outlines, found = (list(lines[:starts[0]]) if starts else list(lines)), False
if mode == 'upsert':
    block = open(extra).read()
    for head, chunk in blocks:
        selected = matches(head, alias)
        outlines.extend(block.splitlines(True)) if selected and not found else outlines.extend(chunk)
        found = found or selected
    outlines.extend(['\n'] if not found and outlines and not outlines[-1].endswith('\n') else [])
    outlines.extend(block.splitlines(True) if not found else [])
elif mode == 'hostname':
    for head, chunk in blocks:
        selected = matches(head, alias) and not found
        changed = False
        for i, line in enumerate(chunk):
            if selected and re.match(r'^\s*HostName\s+', line, re.I):
                chunk[i] = re.sub(r'^(\s*HostName\s+)\S+', lambda m: m.group(1) + extra, line, flags=re.I)
                changed = found = True
                break
        if selected:
            chunk.insert(1, '  HostName ' + extra + '\n') if not changed else None
            found = True
        outlines.extend(chunk)
elif mode == 'remove':
    aliases = extra.split()
    for head, chunk in blocks:
        remove = any(matches(head, item) for item in aliases)
        remove = remove or (alias == 'acg' and any(re.fullmatch(r'ubuntu-[0-9]+', item) for item in head[1:]))
        outlines.extend(chunk) if not remove else None
elif mode == 'read':
    for head, chunk in blocks:
        if matches(head, alias):
            value = next((re.sub(r'^\s*HostName\s+', '', line, flags=re.I).strip() for line in chunk if re.match(r'^\s*HostName\s+', line, re.I)), '')
            if value:
                print(value)
                break
    sys.exit(0)
open(out, 'w').writelines(outlines)
PY
  if (( rc != 0 )); then rm -f "$tmp"; return "$rc"; fi
  chmod 600 "$tmp" || { rm -f "$tmp"; _ssh_fragment_error "cannot secure temporary fragment"; return 1; }
  if [[ "$mode" == remove ]] && ! grep -q '[^[:space:]]' "$tmp"; then
    rm -f "$tmp" "$fragment" || { _ssh_fragment_error "cannot remove empty fragment"; return 1; }
  else
    mv -f "$tmp" "$fragment" || { rm -f "$tmp"; _ssh_fragment_error "cannot install fragment"; return 1; }
  fi
}

function _ssh_fragment_upsert() {
  _ssh_fragment_write_python "$(_ssh_fragment_path)" upsert "$1" "$2"
}

function _ssh_fragment_set_hostname() {
  local fragment
  fragment="$(_ssh_fragment_path)"
  [[ ! -L "$fragment" ]] || { _ssh_fragment_error "refusing symlink fragment: ${fragment}"; return 1; }
  [[ -f "$fragment" ]] || return 0
  _ssh_fragment_write_python "$fragment" hostname "$1" "$2"
}

function _ssh_fragment_remove() {
  local mode="$1" fragment
  shift
  fragment="$(_ssh_fragment_path)"
  [[ ! -L "$fragment" ]] || { _ssh_fragment_error "refusing symlink fragment: ${fragment}"; return 1; }
  _ssh_fragment_write_python "$fragment" remove "$mode" "$*"
}

function _ssh_fragment_hostname() {
  local fragment main result
  fragment="$(_ssh_fragment_path)"
  if [[ -f "$fragment" ]]; then
    result=$(_run_command -- python3 - "$fragment" "$1" <<'PY'
import re, sys
lines = open(sys.argv[1]).read().splitlines()
active = False
for line in lines:
    head = re.match(r'^\s*(Host|Match)(?:\s+|=)(.+)', line, re.I)
    if head:
        active = head.group(1).lower() == 'host' and sys.argv[2] in head.group(2).split()
    elif active:
        match = re.match(r'^\s*HostName\s+(\S+)', line, re.I)
        if match:
            print(match.group(1))
            break
PY
)
    [[ -n "$result" ]] && { printf '%s\n' "$result"; return 0; }
  fi
  main="$(_ssh_fragment_main_config)"
  [[ -f "$main" ]] || return 0
  _run_command -- python3 - "$main" "$1" <<'PY'
import re, sys
lines = open(sys.argv[1]).read().splitlines()
active = False
for line in lines:
    head = re.match(r'^\s*(Host|Match)(?:\s+|=)(.+)', line, re.I)
    if head:
        active = head.group(1).lower() == 'host' and sys.argv[2] in head.group(2).split()
    elif active:
        match = re.match(r'^\s*HostName\s+(\S+)', line, re.I)
        if match:
            print(match.group(1))
            break
PY
}

function _ssh_fragment_include_preflight() {
  local fragment main home_form relative mode="error"
  fragment="$(_ssh_fragment_path)"
  main="$(_ssh_fragment_main_config)"
  if [[ "$fragment" == "$HOME"/* ]]; then
    home_form=$(printf '\176/%s' "${fragment#"$HOME"/}")
  fi
  if [[ "$fragment" == "$HOME/.ssh/"* ]]; then relative="${fragment#"$HOME/.ssh/"}"; fi
  [[ "${K3DM_SSH_SANDBOX_PREFLIGHT:-}" == warn ]] && mode=warn
  _run_command -- python3 - "$main" "$fragment" "$home_form" "${relative:-}" "$mode" <<'PY'
import os, re, sys
main, fragment, homeform, relative, mode = sys.argv[1:]
matches = False
try:
    lines = open(main).readlines()
except OSError:
    lines = []
for line in lines:
    stripped = line.strip()
    if re.match(r'^(Host|Match)(?:\s|=)', stripped, re.I):
        break
    match = re.match(r'^Include(?:\s|=)(.*)$', stripped, re.I)
    if match:
        value = match.group(1).strip().strip('"\'')
        matches = matches or (bool(value) and value in (fragment, homeform, relative))
if not matches:
    line = 'Include ' + (homeform or fragment)
    label = ('WARN' if mode == 'warn' else 'ERROR')
    print('%s: [ssh-fragment] add `%s` to %s before any Host block' % (label, line, main), file=sys.stderr)
    sys.exit(0 if mode == 'warn' else 1)
PY
}

function _ssh_fragment_check_resolves() {
  local alias="$1" ip="$2" main fragment resolved
  command -v ssh >/dev/null 2>&1 || return 0
  main="$(_ssh_fragment_main_config)"
  fragment="$(_ssh_fragment_path)"
  resolved=$(ssh -G -F "$main" "$alias" 2>/dev/null | awk '$1 == "hostname" {print $2; exit}') || resolved=""
  [[ "$resolved" == "$ip" ]] && return 0
  [[ "${_SSH_FRAGMENT_WARNED:-0}" == 1 ]] && return 0
  _SSH_FRAGMENT_WARNED=1
  _ssh_fragment_warn "${fragment} is not selected by ${main}; add Include ${fragment} before any Host block"
}
