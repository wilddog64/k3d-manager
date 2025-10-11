#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  source "${BATS_TEST_DIRNAME}/../test_helpers.bash"
  source "${BATS_TEST_DIRNAME}/../../lib/system.sh"
  init_test_env
  _ensure_jq() { return 0; }
  _ensure_lpass() { return 0; }
  export -f _ensure_jq
  export -f _ensure_lpass
}

_stub_kubectl_for_sync() {
  SYNC_KUBECTL_LOG="$1"
  SYNC_KUBECTL_PASS="$2"
  SYNC_KUBECTL_PAYLOAD="$3"
  export SYNC_KUBECTL_LOG SYNC_KUBECTL_PASS SYNC_KUBECTL_PAYLOAD
  _kubectl() {
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --quiet|--no-exit|--prefer-sudo|--require-sudo)
          shift
          ;;
        --)
          shift
          break
          ;;
        *)
          break
          ;;
      esac
    done
    local cmd="$*"
    if [[ -n "${SYNC_KUBECTL_LOG:-}" ]]; then
      printf '%s\n' "$cmd" >> "$SYNC_KUBECTL_LOG"
    fi
    if [[ "$cmd" == "-n vault exec vault-0 -i -- sh -c cat >/tmp/jenkins-ad.json && vault kv put secret/jenkins/ad-ldap @/tmp/jenkins-ad.json && rm -f /tmp/jenkins-ad.json" ]]; then
      if [[ -n "${SYNC_KUBECTL_PAYLOAD:-}" ]]; then
        cat >"$SYNC_KUBECTL_PAYLOAD"
      else
        cat >/dev/null
      fi
      return 0
    fi
    if [[ "$cmd" == "-n vault exec vault-0 -i -- vault kv get -format=json secret/jenkins/ad-ldap" ]]; then
      printf '{"data":{"data":{"password":"%s"}}}' "$SYNC_KUBECTL_PASS"
    fi
    return 0
  }
  export -f _kubectl
}

make_lpass_stub() {
  local path="$1"
  local password="$2"
  cat <<'EOF' >"$path"
#!/usr/bin/env bash
set -euo pipefail

LPASS_PASSWORD="${LPASS_PASSWORD:-}"
if [[ "$1" == "ls" ]]; then
  cat <<'LIST'
id: 4242 Name: svcADReader (PACIFIC)
LIST
  exit 0
fi

if [[ "$1" == "show" && "${2:-}" == "--id" && "${4:-}" == "--pass" ]]; then
  printf '%s' "$LPASS_PASSWORD"
  exit 0
fi

echo "unsupported call: $*" >&2
exit 1
EOF
  chmod +x "$path"
  (
    export LPASS_PASSWORD="$password"
    "$path" ls >/dev/null
    "$path" show --id 4242 --pass >/dev/null
  )
}

@test "_sync_lastpass_ad writes secret and verifies digest" {
  local kubectl_log="$BATS_TEST_TMPDIR/kubectl.log"
  : >"$kubectl_log"
  local payload_file="$BATS_TEST_TMPDIR/payload.json"
  _stub_kubectl_for_sync "$kubectl_log" "SuperSecret" "$payload_file"

  local lpass_stub="$BATS_TEST_TMPDIR/lpass-success"
  make_lpass_stub "$lpass_stub" "SuperSecret"

  LPASS_PASSWORD="SuperSecret" \
  LPASS_CMD="$lpass_stub" \
  run _sync_lastpass_ad
  [ "$status" -eq 0 ]
  [[ "$output" == *"Vault credential matches LastPass"* ]]

  read_lines "$kubectl_log" kubectl_cmds
  [ "${#kubectl_cmds[@]}" -eq 2 ]
  [ "${kubectl_cmds[0]}" = "-n vault exec vault-0 -i -- sh -c cat >/tmp/jenkins-ad.json && vault kv put secret/jenkins/ad-ldap @/tmp/jenkins-ad.json && rm -f /tmp/jenkins-ad.json" ]
  [ "${kubectl_cmds[1]}" = "-n vault exec vault-0 -i -- vault kv get -format=json secret/jenkins/ad-ldap" ]

  run env PAYLOAD_FILE="$payload_file" python3 - <<'PY'
import json, os
path = os.environ["PAYLOAD_FILE"]
with open(path, "r", encoding="utf-8") as fh:
    data = json.load(fh)
print(data["password"])
print(data["username"])
PY
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "SuperSecret" ]
  [[ "${lines[1]}" == CN=svcADReader,* ]]
}

@test "_sync_lastpass_ad fails when Vault password mismatch" {
  local kubectl_log="$BATS_TEST_TMPDIR/kubectl.log"
  : >"$kubectl_log"
  local payload_file="$BATS_TEST_TMPDIR/payload.json"
  _stub_kubectl_for_sync "$kubectl_log" "Different" "$payload_file"

  local lpass_stub="$BATS_TEST_TMPDIR/lpass-fail"
  make_lpass_stub "$lpass_stub" "Mismatch"

  LPASS_PASSWORD="Mismatch" \
  LPASS_CMD="$lpass_stub" \
  run _sync_lastpass_ad
  [ "$status" -eq 1 ]
  [[ "$output" == *"Vault credential mismatch"* ]]

  read_lines "$kubectl_log" kubectl_cmds
  [ "${#kubectl_cmds[@]}" -eq 2 ]
  [ "${kubectl_cmds[0]}" = "-n vault exec vault-0 -i -- sh -c cat >/tmp/jenkins-ad.json && vault kv put secret/jenkins/ad-ldap @/tmp/jenkins-ad.json && rm -f /tmp/jenkins-ad.json" ]
  [ "${kubectl_cmds[1]}" = "-n vault exec vault-0 -i -- vault kv get -format=json secret/jenkins/ad-ldap" ]
}
