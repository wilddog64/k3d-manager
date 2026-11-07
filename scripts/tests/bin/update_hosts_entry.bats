#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
  SCRIPT="${UPDATE_HOSTS_ENTRY_FILE:-${REPO_ROOT}/bin/update-hosts-entry.sh}"
  HOSTS_FILE="${BATS_TEST_TMPDIR}/hosts"
  [[ "$HOSTS_FILE" != "/etc/hosts" ]]
  export K3DM_HOSTS_FILE="$HOSTS_FILE"
  printf '127.0.0.1 localhost\n192.0.2.1 example.test\n' > "$HOSTS_FILE"
}

@test "valid hostname and IPv4 replace existing entry and append the new value" {
  [[ "$K3DM_HOSTS_FILE" == "$BATS_TEST_TMPDIR"/* ]]
  run "$SCRIPT" example.test 198.51.100.7
  [ "$status" -eq 0 ]
  [ "$(grep -c '^example.test$' "$HOSTS_FILE")" -eq 0 ]
  [ "$(grep -c '^198\.51\.100\.7 example\.test$' "$HOSTS_FILE")" -eq 1 ]
  [ "$(head -n 1 "$HOSTS_FILE")" = '127.0.0.1 localhost' ]
}

@test "invalid hostname does not modify hosts file" {
  [[ "$K3DM_HOSTS_FILE" == "$BATS_TEST_TMPDIR"/* ]]
  local before
  before="$(cat "$HOSTS_FILE")"
  run "$SCRIPT" $'bad\nhost' 198.51.100.7
  [ "$status" -ne 0 ]
  [ "$(cat "$HOSTS_FILE")" = "$before" ]
}

@test "whitespace hostname does not modify hosts file" {
  [[ "$K3DM_HOSTS_FILE" == "$BATS_TEST_TMPDIR"/* ]]
  local before
  before="$(cat "$HOSTS_FILE")"
  run "$SCRIPT" 'bad host' 198.51.100.7
  [ "$status" -ne 0 ]
  [ "$(cat "$HOSTS_FILE")" = "$before" ]
}

@test "hostname with invalid punctuation does not modify hosts file" {
  [[ "$K3DM_HOSTS_FILE" == "$BATS_TEST_TMPDIR"/* ]]
  local before
  before="$(cat "$HOSTS_FILE")"
  run "$SCRIPT" bad_host 198.51.100.7
  [ "$status" -ne 0 ]
  [ "$(cat "$HOSTS_FILE")" = "$before" ]
}

@test "invalid IPv4 does not modify hosts file" {
  [[ "$K3DM_HOSTS_FILE" == "$BATS_TEST_TMPDIR"/* ]]
  local before
  before="$(cat "$HOSTS_FILE")"
  run "$SCRIPT" example.test $'198.51.100.7\n127.0.0.1'
  [ "$status" -ne 0 ]
  [ "$(cat "$HOSTS_FILE")" = "$before" ]
}

@test "IPv4 octet above 255 does not modify hosts file" {
  [[ "$K3DM_HOSTS_FILE" == "$BATS_TEST_TMPDIR"/* ]]
  local before
  before="$(cat "$HOSTS_FILE")"
  run "$SCRIPT" example.test 198.51.100.256
  [ "$status" -ne 0 ]
  [ "$(cat "$HOSTS_FILE")" = "$before" ]
}

@test "wrong argument count does not modify hosts file" {
  [[ "$K3DM_HOSTS_FILE" == "$BATS_TEST_TMPDIR"/* ]]
  local before
  before="$(cat "$HOSTS_FILE")"
  run "$SCRIPT" example.test
  [ "$status" -ne 0 ]
  [ "$(cat "$HOSTS_FILE")" = "$before" ]
}

@test "extra arguments do not modify hosts file" {
  [[ "$K3DM_HOSTS_FILE" == "$BATS_TEST_TMPDIR"/* ]]
  local before
  before="$(cat "$HOSTS_FILE")"
  run "$SCRIPT" example.test 198.51.100.7 ignored
  [ "$status" -ne 0 ]
  [ "$(cat "$HOSTS_FILE")" = "$before" ]
}

@test "IPv4 octet that wraps 64-bit arithmetic does not modify hosts file" {
  [[ "$K3DM_HOSTS_FILE" == "$BATS_TEST_TMPDIR"/* ]]
  local before
  before="$(cat "$HOSTS_FILE")"
  run "$SCRIPT" example.test 18446744073709551616.1.1.1
  [ "$status" -ne 0 ]
  [ "$(cat "$HOSTS_FILE")" = "$before" ]
}

@test "hosts file override is ignored when running as root" {
  run grep -F 'if [[ "$EUID" -ne 0 && -n "${K3DM_HOSTS_FILE:-}" ]]; then' "$SCRIPT"
  [ "$status" -eq 0 ]
}
