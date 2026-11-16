#!/usr/bin/env bats

load "${BATS_TEST_DIRNAME}/../python_yaml.bash"

setup() {
  TMPL="${BATS_TEST_DIRNAME}/../../etc/vault/unseal-watchdog.yaml.tmpl"
  RENDERED="$(mktemp)"
  # shellcheck disable=SC2016,SC2034
  VAULT_NS="secrets" \
  VAULT_UNSEAL_IMAGE="hashicorp/vault:1.18.3" \
  VAULT_ENDPOINT="http://vault.secrets.svc:8200" \
  envsubst '$VAULT_NS $VAULT_UNSEAL_IMAGE $VAULT_ENDPOINT' < "$TMPL" > "$RENDERED"

  TEST_DIR="$(mktemp -d)"
  BIN_DIR="$TEST_DIR/bin"
  mkdir -p "$BIN_DIR"
  CALLS_FILE="$TEST_DIR/calls.log"
  STATUS_RESPONSES_FILE="$TEST_DIR/status_responses.txt"
  SHARD_FILE="$TEST_DIR/shard-1"
  printf 'test-shard-content-secret123\n' > "$SHARD_FILE"
  : > "$CALLS_FILE"

  cat << 'EOF' > "$BIN_DIR/vault"
#!/bin/sh
printf 'vault %s\n' "$*" >> "$CALLS_FILE"
if [ "$1" = "status" ]; then
  if [ -s "$STATUS_RESPONSES_FILE" ]; then
    rc=$(head -n 1 "$STATUS_RESPONSES_FILE")
    tail -n +2 "$STATUS_RESPONSES_FILE" > "$STATUS_RESPONSES_FILE.tmp"
    mv "$STATUS_RESPONSES_FILE.tmp" "$STATUS_RESPONSES_FILE"
    exit "$rc"
  fi
  exit "${DEFAULT_STATUS_RC:-1}"
fi
if [ "$1" = "operator" ] && [ "$2" = "unseal" ]; then
  exit 0
fi
exit 0
EOF
  chmod +x "$BIN_DIR/vault"

  cat << 'EOF' > "$BIN_DIR/sleep"
#!/bin/sh
printf 'sleep %s\n' "$*" >> "$CALLS_FILE"
exit 0
EOF
  chmod +x "$BIN_DIR/sleep"
}

teardown() {
  rm -f "$RENDERED"
  rm -rf "$TEST_DIR"
}

extract_script() {
  local py
  py="$(k3dm_python_yaml 2>/dev/null || true)"
  if [[ -n "$py" ]]; then
    "$py" -c '
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
sys.stdout.write(d["spec"]["jobTemplate"]["spec"]["template"]["spec"]["containers"][0]["command"][2])
' "$RENDERED"
  else
    awk '/command:/{c=1;next} c && /^[ ]*- \|/{flag=1;next} flag && /^[ ]*volumeMounts:/{flag=0;c=0} flag{sub(/^ {18}/, ""); print}' "$RENDERED"
  fi
}

run_script() {
  local script_file="$TEST_DIR/watchdog.sh"
  extract_script | sed "s|SHARD_FILE=/etc/vault-unseal/shard-1|SHARD_FILE=\"\${SHARD_FILE:-$SHARD_FILE}\"|" > "$script_file"
  chmod +x "$script_file"
  PATH="$BIN_DIR:$PATH" \
  CALLS_FILE="$CALLS_FILE" \
  STATUS_RESPONSES_FILE="$STATUS_RESPONSES_FILE" \
  DEFAULT_STATUS_RC="${DEFAULT_STATUS_RC:-1}" \
  SHARD_FILE="$SHARD_FILE" \
  VAULT_ADDR="http://vault.secrets.svc:8200" \
  sh "$script_file"
}

@test "watchdog renders into the provided namespace" {
  grep -q "namespace: secrets" "$RENDERED"
}

@test "watchdog image is pinned (not latest)" {
  grep -q "image: hashicorp/vault:1.18.3" "$RENDERED"
  run grep -qE "image:.*:latest" "$RENDERED"
  [ "$status" -ne 0 ]
}

@test "watchdog mounts the vault-unseal secret optionally" {
  grep -q "secretName: vault-unseal" "$RENDERED"
  grep -q "optional: true" "$RENDERED"
}

@test "watchdog targets the in-cluster endpoint and unseals via shard-1" {
  grep -q "http://vault.secrets.svc:8200" "$RENDERED"
  grep -q "/etc/vault-unseal/shard-1" "$RENDERED"
  grep -q "vault operator unseal" "$RENDERED"
}

@test "inline shell vars survived envsubst (not expanded away)" {
  grep -q 'rc=$?' "$RENDERED"
  # shellcheck disable=SC2016
  grep -q '\$(cat "\$SHARD_FILE")' "$RENDERED"
}

@test "M1: vault status returns 1, 1, then 2 -> retries, unseals once, rc 0" {
  printf '1\n1\n2\n0\n' > "$STATUS_RESPONSES_FILE"
  run run_script
  [ "$status" -eq 0 ]
  [[ "$output" =~ "retry 1/12" ]]
  [[ "$output" =~ "retry 2/12" ]]
  local unseal_calls
  unseal_calls=$(grep -c "vault operator unseal" "$CALLS_FILE" || true)
  [ "$unseal_calls" -eq 1 ]
}

@test "M2: vault status returns 1 every time -> 12 status calls, 11 sleeps, skipping, no unseal" {
  yes 1 | head -n 20 > "$STATUS_RESPONSES_FILE"
  DEFAULT_STATUS_RC=1
  run run_script
  [ "$status" -eq 0 ]
  local status_calls sleep_calls unseal_calls
  status_calls=$(grep -c "vault status" "$CALLS_FILE" || true)
  sleep_calls=$(grep -cx "sleep 5" "$CALLS_FILE" || true)
  unseal_calls=$(grep -c "vault operator unseal" "$CALLS_FILE" || true)
  [ "$status_calls" -eq 12 ]
  [ "$sleep_calls" -eq 11 ]
  [ "$unseal_calls" -eq 0 ]
  [[ "${lines[-1]}" =~ —[[:space:]]*skipping$ ]] || [[ "$output" =~ "— skipping" ]]
}

@test "M3: vault status returns 0 first -> already unsealed, 1 status call, no sleep" {
  printf '0\n' > "$STATUS_RESPONSES_FILE"
  run run_script
  [ "$status" -eq 0 ]
  [[ "$output" =~ "vault already unsealed" ]]
  local status_calls sleep_calls
  status_calls=$(grep -c "vault status" "$CALLS_FILE" || true)
  sleep_calls=$(grep -c "sleep" "$CALLS_FILE" || true)
  [ "$status_calls" -eq 1 ]
  [ "$sleep_calls" -eq 0 ]
}

@test "M3: vault status returns 2 first -> unseal path runs with no retry line and no sleep" {
  printf '2\n0\n' > "$STATUS_RESPONSES_FILE"
  run run_script
  [ "$status" -eq 0 ]
  [[ "$output" =~ "vault sealed — replaying shard" ]]
  [[ ! "$output" =~ "retry" ]]
  local sleep_calls unseal_calls
  sleep_calls=$(grep -c "sleep" "$CALLS_FILE" || true)
  unseal_calls=$(grep -c "vault operator unseal" "$CALLS_FILE" || true)
  [ "$sleep_calls" -eq 0 ]
  [ "$unseal_calls" -eq 1 ]
}

@test "M4: extracted script passes sh -n, cronjob parameters unchanged, shard never logged" {
  local script_file="$TEST_DIR/watchdog_sh_n.sh"
  extract_script > "$script_file"
  run sh -n "$script_file"
  [ "$status" -eq 0 ]

  grep -q 'schedule: "\*/5 \* \* \* \*"' "$RENDERED"
  grep -q 'activeDeadlineSeconds: 150' "$RENDERED"
  grep -q 'backoffLimit: 0' "$RENDERED"
  grep -A1 'name: VAULT_CLIENT_TIMEOUT' "$RENDERED" | grep -q 'value: "5s"'
  grep -q '^ *set -u$' "$script_file"
  grep -q 'image: hashicorp/vault:1.18.3' "$RENDERED"

  # Shard file content never appears in stdout/stderr in any scenario
  printf '1\n1\n2\n0\n' > "$STATUS_RESPONSES_FILE"
  run run_script
  [[ ! "$output" =~ "test-shard-content-secret123" ]]

  yes 1 | head -n 20 > "$STATUS_RESPONSES_FILE"
  DEFAULT_STATUS_RC=1
  run run_script
  [[ ! "$output" =~ "test-shard-content-secret123" ]]

  printf '0\n' > "$STATUS_RESPONSES_FILE"
  run run_script
  [[ ! "$output" =~ "test-shard-content-secret123" ]]

  printf '2\n0\n' > "$STATUS_RESPONSES_FILE"
  run run_script
  [ "$status" -eq 0 ]
  [[ "$output" =~ "replaying shard" ]]
  grep -q "vault operator unseal" "$CALLS_FILE"
  [[ ! "$output" =~ "test-shard-content-secret123" ]]
}

@test "N1: vault status returns 1 then 0 -> does not print skipping or exit before second call" {
  printf '1\n0\n' > "$STATUS_RESPONSES_FILE"
  run run_script
  [ "$status" -eq 0 ]
  local status_calls
  status_calls=$(grep -c "vault status" "$CALLS_FILE" || true)
  [ "$status_calls" -ge 2 ]
  [[ ! "$output" =~ "— skipping" ]]
}

@test "N2: vault status returns 1, 1, then 2 -> does not exit without calling operator unseal" {
  printf '1\n1\n2\n0\n' > "$STATUS_RESPONSES_FILE"
  run run_script
  [ "$status" -eq 0 ]
  local unseal_calls
  unseal_calls=$(grep -c "vault operator unseal" "$CALLS_FILE" || true)
  [ "$unseal_calls" -eq 1 ]
}
