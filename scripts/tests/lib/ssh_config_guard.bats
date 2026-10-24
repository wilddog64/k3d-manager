#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"
  export K3DM_SSH_CONFIG="$HOME/.ssh/config"
  export K3DM_SSH_OPERATOR_FRAGMENT="$HOME/.ssh/config.d/operator"
  mkdir -p "$(dirname "$K3DM_SSH_CONFIG")" "$(dirname "$K3DM_SSH_OPERATOR_FRAGMENT")"
  source "$BATS_TEST_DIRNAME/../../lib/ssh_config_guard.sh"
}

write_fragment() {
  cat > "$K3DM_SSH_OPERATOR_FRAGMENT" <<'EOF'
Host github-k3dm-hub-data
  HostName github.com
  User git
Host m2jump
  HostName m2.example.invalid
  User operator
EOF
}

@test "ssh guard: all required aliases present returns silently" {
  write_fragment
  printf 'Include %s\n' "$K3DM_SSH_OPERATOR_FRAGMENT" > "$K3DM_SSH_CONFIG"
  run _ssh_config_guard github-k3dm-hub-data m2jump
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "ssh guard: repairs an emptied config and records warning and secure backup" {
  write_fragment
  : > "$K3DM_SSH_CONFIG"
  run --separate-stderr _ssh_config_guard --repair github-k3dm-hub-data m2jump
  [ "$status" -eq 0 ]
  [[ "$stderr" == *'missing alias(es): github-k3dm-hub-data m2jump (config 0 bytes, mtime '* ]]
  [[ "$stderr" == *'restored Include for github-k3dm-hub-data m2jump'* ]]
  [ "$(grep -c '^Include ' "$K3DM_SSH_CONFIG")" -eq 1 ]
  backup_mode="$(stat -c '%a' "${K3DM_SSH_CONFIG}.k3dm-guard."* 2>/dev/null || stat -f '%Lp' "${K3DM_SSH_CONFIG}.k3dm-guard."*)"
  [ "$backup_mode" = 600 ]
  run ssh -G -F "$K3DM_SSH_CONFIG" github-k3dm-hub-data
  [[ "$output" == *'hostname github.com'* ]]
  run ssh -G -F "$K3DM_SSH_CONFIG" m2jump
  [[ "$output" == *'hostname m2.example.invalid'* ]]
}

@test "ssh guard: missing fragment or missing alias in fragment leaves config unchanged" {
  printf 'Host untouched\n  HostName unchanged\n' > "$K3DM_SSH_CONFIG"
  cp "$K3DM_SSH_CONFIG" "$BATS_TEST_TMPDIR/original"
  run _ssh_config_guard --repair missing-alias
  [ "$status" -ne 0 ]
  cmp -s "$BATS_TEST_TMPDIR/original" "$K3DM_SSH_CONFIG"
  printf 'Host other\n  HostName other.example.invalid\n' > "$K3DM_SSH_OPERATOR_FRAGMENT"
  run _ssh_config_guard --repair missing-alias
  [ "$status" -ne 0 ]
  cmp -s "$BATS_TEST_TMPDIR/original" "$K3DM_SSH_CONFIG"
}

@test "ssh guard: repair is idempotent and preserves existing config bytes after Include" {
  write_fragment
  printf 'Host ubuntu-1\n  HostName 192.0.2.1\n\nHost ubuntu\n  HostName 192.0.2.2' > "$K3DM_SSH_CONFIG"
  cp "$K3DM_SSH_CONFIG" "$BATS_TEST_TMPDIR/original"
  _ssh_config_guard --repair github-k3dm-hub-data
  tail -n +2 "$K3DM_SSH_CONFIG" > "$BATS_TEST_TMPDIR/after"
  cmp -s "$BATS_TEST_TMPDIR/original" "$BATS_TEST_TMPDIR/after"
  _ssh_config_guard --repair github-k3dm-hub-data
  [ "$(grep -c '^Include ' "$K3DM_SSH_CONFIG")" -eq 1 ]
  tail -n +2 "$K3DM_SSH_CONFIG" > "$BATS_TEST_TMPDIR/after-again"
  cmp -s "$BATS_TEST_TMPDIR/original" "$BATS_TEST_TMPDIR/after-again"
}

@test "ssh guard: retains only five timestamped backups" {
  write_fragment
  printf 'Host test\n  HostName test.example.invalid\n' > "$K3DM_SSH_CONFIG"
  for i in {1..7}; do
    printf 'Host test\n  HostName test-%s.example.invalid\n' "$i" > "$K3DM_SSH_CONFIG"
    _ssh_config_guard --repair github-k3dm-hub-data >/dev/null 2>&1
    rm -f "$K3DM_SSH_CONFIG"
  done
  [ "$(find "$(dirname "$K3DM_SSH_CONFIG")" -name 'config.k3dm-guard.*' | wc -l | tr -d ' ')" -eq 5 ]
}
