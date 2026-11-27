#!/usr/bin/env bats
# shellcheck shell=bash disable=SC1091,SC2317
bats_require_minimum_version 1.5.0

setup() {
  export HOME="${BATS_TEST_TMPDIR}/home"
  mkdir -p "${HOME}"
  [[ "$HOME" == "$BATS_TEST_TMPDIR"/* ]]
  # shellcheck source=/dev/null
  source "${BATS_TEST_DIRNAME}/../../lib/ssh_fragment.sh"
  _info() { :; }
  _warn() { printf '%s\n' "$*" >&2; }
  _run_command() { while [[ "$1" == --* ]]; do [[ "$1" == -- ]] && { shift; break; }; shift; done; "$@"; }
  [[ "$(_ssh_fragment_path)" == "$HOME"/* ]]
}

@test "fragment writes are private, atomic, idempotent and honor call-time override" {
  [[ "$HOME" == "$BATS_TEST_TMPDIR"/* ]]
  [[ "$(_ssh_fragment_path)" == "$HOME"/* ]]
  local block override
  block="${BATS_TEST_TMPDIR}/block"
  printf 'Host ubuntu\n  HostName 192.0.2.1\n' >"$block"
  _ssh_fragment_upsert ubuntu "$block"
  _ssh_fragment_upsert ubuntu "$block"
  [ "$(grep -c '^Host ubuntu$' "$(_ssh_fragment_path)")" -eq 1 ]
  [ "$(python3 -c 'import os,stat,sys; print(oct(stat.S_IMODE(os.stat(sys.argv[1]).st_mode))[2:])' "$(_ssh_fragment_path)")" = 600 ]
  [ "$(python3 -c 'import os,stat,sys; print(oct(stat.S_IMODE(os.stat(sys.argv[1]).st_mode))[2:])' "$(dirname "$(_ssh_fragment_path)")")" = 700 ]
  override="${HOME}/override/hosts"
  mkdir -p "$(dirname "$override")"
  export K3DM_SSH_SANDBOX_FRAGMENT="$override"
  _ssh_fragment_upsert ubuntu "$block"
  [ -f "$override" ]
}

@test "hostname update is stanza bounded and removal matches whole aliases" {
  [[ "$HOME" == "$BATS_TEST_TMPDIR"/* ]]
  [[ "$(_ssh_fragment_path)" == "$HOME"/* ]]
  mkdir -p "${HOME}/.ssh"
  cat >"$(_ssh_fragment_path)" <<'EOF'
Host ubuntu
  User ubuntu
Host ubuntu-gcp
  HostName 203.0.113.8
Host ubuntu-3
  HostName 203.0.113.3
Host ubuntu-1x
  HostName 203.0.113.1
Host ubuntu-azure
  HostName 203.0.113.9
EOF
  _ssh_fragment_set_hostname ubuntu 192.0.2.1
  grep -A1 '^Host ubuntu$' "$(_ssh_fragment_path)" | grep -q '192.0.2.1'
  grep -q '203.0.113.8' "$(_ssh_fragment_path)"
  _ssh_fragment_remove acg ubuntu ubuntu-tunnel
  run ! grep -q '^Host ubuntu$' "$(_ssh_fragment_path)"
  run ! grep -q '^Host ubuntu-3$' "$(_ssh_fragment_path)"
  grep -q '^Host ubuntu-gcp$' "$(_ssh_fragment_path)"
  grep -q '^Host ubuntu-1x$' "$(_ssh_fragment_path)"
  grep -q '^Host ubuntu-azure$' "$(_ssh_fragment_path)"
}

@test "symlink and dangling symlink fragments are refused for write and removal" {
  [[ "$HOME" == "$BATS_TEST_TMPDIR"/* ]]
  [[ "$(_ssh_fragment_path)" == "$HOME"/* ]]
  local block target
  mkdir -p "${HOME}/.ssh"
  target="${BATS_TEST_TMPDIR}/target"
  printf 'keep\n' >"$target"
  block="${BATS_TEST_TMPDIR}/block"
  printf 'Host ubuntu\n  HostName 192.0.2.1\n' >"$block"
  ln -s "$target" "$(_ssh_fragment_path)"
  run _ssh_fragment_upsert ubuntu "$block"
  [ "$status" -ne 0 ]
  run _ssh_fragment_remove acg ubuntu
  [ "$status" -ne 0 ]
  [ -L "$(_ssh_fragment_path)" ]
  [ "$(cat "$target")" = keep ]
  rm "$(_ssh_fragment_path)"
  ln -s "${BATS_TEST_TMPDIR}/absent" "$(_ssh_fragment_path)"
  run _ssh_fragment_remove acg ubuntu
  [ "$status" -ne 0 ]
  [ -L "$(_ssh_fragment_path)" ]
}

@test "preflight requires an unconditional Include and supports warn mode" {
  [[ "$HOME" == "$BATS_TEST_TMPDIR"/* ]]
  [[ "$(_ssh_fragment_path)" == "$HOME"/* ]]
  mkdir -p "${HOME}/.ssh"
  printf 'Host first\nInclude %s\n' "$(_ssh_fragment_path)" >"$(_ssh_fragment_main_config)"
  run _ssh_fragment_include_preflight
  [ "$status" -ne 0 ]
  [[ "$output" == *'before any Host block'* ]]
  [[ "$output" == *'Include ~/.ssh/k3dm-sandbox.conf'* ]]
  printf 'Include "~/.ssh/k3dm-sandbox.conf"\nHost first\n' >"$(_ssh_fragment_main_config)"
  run _ssh_fragment_include_preflight
  [ "$status" -eq 0 ]
  printf 'include  "%s"\n' "$(_ssh_fragment_path)" >"$(_ssh_fragment_main_config)"
  run _ssh_fragment_include_preflight
  [ "$status" -eq 0 ]
  printf 'Include k3dm-sandbox.conf\n' >"$(_ssh_fragment_main_config)"
  run _ssh_fragment_include_preflight
  [ "$status" -eq 0 ]
  printf 'Host first\n' >"$(_ssh_fragment_main_config)"
  export K3DM_SSH_SANDBOX_PREFLIGHT=warn
  run _ssh_fragment_include_preflight
  [ "$status" -eq 0 ]
  [[ "$output" == *WARN* ]]
}

@test "effect check uses offline ssh config and warns once for an earlier Host" {
  [[ "$HOME" == "$BATS_TEST_TMPDIR"/* ]]
  [[ "$(_ssh_fragment_path)" == "$HOME"/* ]]
  command -v ssh >/dev/null 2>&1 || skip "ssh unavailable"
  mkdir -p "${HOME}/.ssh"
  printf 'Host ubuntu\n  HostName 192.0.2.1\n' >"$(_ssh_fragment_path)"
  printf 'Include %s\n' "$(_ssh_fragment_path)" >"$(_ssh_fragment_main_config)"
  run _ssh_fragment_check_resolves ubuntu 192.0.2.1
  [ "$status" -eq 0 ]
  printf 'Host ubuntu\n  HostName 192.0.2.9\nInclude %s\n' "$(_ssh_fragment_path)" >"$(_ssh_fragment_main_config)"
  unset _SSH_FRAGMENT_WARNED
  local warnings="${BATS_TEST_TMPDIR}/warnings"
  _ssh_fragment_check_resolves ubuntu 192.0.2.1 2>>"$warnings"
  _ssh_fragment_check_resolves ubuntu 192.0.2.1 2>>"$warnings"
  [ "$(grep -c WARN "$warnings")" -eq 1 ]
}

@test "hostname reader checks fragment before main config without modifying main config" {
  [[ "$HOME" == "$BATS_TEST_TMPDIR"/* ]]
  [[ "$(_ssh_fragment_path)" == "$HOME"/* ]]
  mkdir -p "${HOME}/.ssh"
  printf 'Host ubuntu\n  HostName 192.0.2.1\n' >"$(_ssh_fragment_path)"
  printf 'Host ubuntu\n  HostName 192.0.2.2\n' >"$(_ssh_fragment_main_config)"
  [ "$(_ssh_fragment_hostname ubuntu)" = 192.0.2.1 ]
  [ "$(cat "$(_ssh_fragment_main_config)")" = $'Host ubuntu\n  HostName 192.0.2.2' ]
}

@test "teardown removal deletes fragment when only blank lines remain" {
  [[ "$HOME" == "$BATS_TEST_TMPDIR"/* ]]
  [[ "$(_ssh_fragment_path)" == "$HOME"/* ]]
  mkdir -p "${HOME}/.ssh"
  printf 'Host ubuntu\n  HostName 192.0.2.1\n' >"$(_ssh_fragment_path)"
  _ssh_fragment_remove acg ubuntu
  [ ! -e "$(_ssh_fragment_path)" ]
}

@test "commented and multi-alias headers are not treated as exact aliases" {
  local block
  mkdir -p "${HOME}/.ssh"
  cat >"$(_ssh_fragment_path)" <<'EOF'
Host ubuntu-gcp # formerly ubuntu
  HostName 203.0.113.8
Host ubuntu-gcp ubuntu
  HostName 203.0.113.9
EOF
  block="${BATS_TEST_TMPDIR}/block"
  printf 'Host ubuntu\n  HostName 192.0.2.1\n' >"$block"
  _ssh_fragment_upsert ubuntu "$block" 2>"${BATS_TEST_TMPDIR}/warnings"
  _ssh_fragment_set_hostname ubuntu 192.0.2.2 2>>"${BATS_TEST_TMPDIR}/warnings"
  _ssh_fragment_remove acg ubuntu 2>>"${BATS_TEST_TMPDIR}/warnings"
  grep -q 'Host ubuntu-gcp # formerly ubuntu' "$(_ssh_fragment_path)"
  grep -q 'Host ubuntu-gcp ubuntu' "$(_ssh_fragment_path)"
  [ "$(grep -c 'multi-alias stanza unchanged' "${BATS_TEST_TMPDIR}/warnings")" -ge 1 ]
}

@test "preflight recognizes equals headers and ignores empty includes" {
  mkdir -p "${HOME}/.ssh"
  printf 'Include ""\nHost=foo\nInclude %s\n' "$(_ssh_fragment_path)" >"$(_ssh_fragment_main_config)"
  run _ssh_fragment_include_preflight
  [ "$status" -ne 0 ]
  printf 'Match=all\nInclude=~/.ssh/k3dm-sandbox.conf\n' >"$(_ssh_fragment_main_config)"
  run _ssh_fragment_include_preflight
  [ "$status" -ne 0 ]
}
