#!/usr/bin/env bats

setup() {
  source "${BATS_TEST_DIRNAME}/../test_helpers.bash"
  init_test_env
  export SCRIPT_DIR="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  source "${SCRIPT_DIR}/plugins/signing.sh"
  export SIGNING_TEST_VAULT_KEY=0 SIGNING_TEST_PUB=0
  export SIGNING_TEST_LOG="${BATS_TEST_TMPDIR}/signing.log"
  : > "${SIGNING_TEST_LOG}"

  _vault_login() {
    printf 'vault_login %s\n' "$*" >> "${SIGNING_TEST_LOG}"
    return 0
  }
  _vault_exec() {
    printf 'vault_exec %s\n' "$*" >> "${SIGNING_TEST_LOG}"
    [[ "${SIGNING_TEST_VAULT_KEY}" == "1" ]] && return 0
    return 1
  }
  _vault_exec_stream() {
    printf 'vault_stream %s\n' "$*" >> "${SIGNING_TEST_LOG}"
    cat >/dev/null
  }
  _run_command() {
    printf 'run %s\n' "$*" >> "${SIGNING_TEST_LOG}"
    if [[ "${*: -1}" == "cosign"* || "$*" == *"cosign generate-key-pair"* ]]; then
      printf 'PRIVATE-KEY\n' > cosign.key
      printf 'PUBLIC-KEY\n' > cosign.pub
    fi
  }
  _secret_store_data() {
    printf 'keychain %s %s\n' "$1" "$2" >> "${SIGNING_TEST_LOG}"
  }
  _secret_load_data() {
    [[ "${SIGNING_TEST_KEYCHAIN:-0}" == "1" ]]
  }
  _kubectl() {
    if [[ "$*" == *"apply -f -"* ]]; then
      cat > "${BATS_TEST_TMPDIR}/eso.yaml"
      printf 'kubectl apply\n' >> "${SIGNING_TEST_LOG}"
      return 0
    fi
    [[ "${SIGNING_TEST_PUB}" == "1" ]]
  }
  export -f _vault_login _vault_exec _vault_exec_stream
  export -f _run_command _secret_store_data _secret_load_data _kubectl
}

@test "signing_init is idempotent when Vault already has the key" {
  SIGNING_TEST_VAULT_KEY=1
  run signing_init
  [ "$status" -eq 0 ]
  [[ "$output" == *"already present"* ]]
  ! grep -q 'generate-key-pair' "${SIGNING_TEST_LOG}"
  ! grep -q 'vault_stream' "${SIGNING_TEST_LOG}"
}

@test "fresh signing_init seeds Vault, backs up both values, and applies manifests" {
  SIGNING_TEST_KEYCHAIN=1
  run signing_init
  [ "$status" -eq 0 ]
  grep -q 'generate-key-pair' "${SIGNING_TEST_LOG}"
  grep -q 'vault_stream' "${SIGNING_TEST_LOG}"
  grep -q 'keychain .*k3dm-cosign-key' "${SIGNING_TEST_LOG}"
  grep -q 'keychain .*k3dm-cosign-password' "${SIGNING_TEST_LOG}"
  grep -q 'kubectl apply' "${SIGNING_TEST_LOG}"
  grep -q 'vault_stream.*policy write' "${SIGNING_TEST_LOG}"
}

@test "cosign key material is not placed in command text and env key syntax is documented" {
  SIGNING_TEST_KEYCHAIN=1
  run signing_init
  [ "$status" -eq 0 ]
  ! grep -q 'PRIVATE-KEY\|PUBLIC-KEY' "${SIGNING_TEST_LOG}"
  grep -q -- '--key env://COSIGN_KEY' "${SCRIPT_DIR}/plugins/signing.sh"
}

@test "Vault verifier policy is read-only on the signing data path" {
  run cat "${SCRIPT_DIR}/etc/signing/cosign-verify-policy.hcl"
  [ "$status" -eq 0 ]
  [[ "$output" == *'path "secret/data/cosign/signing"'* ]]
  [[ "$output" == *'capabilities = ["read"]'* ]]
  [[ "$output" != *create* && "$output" != *update* && "$output" != *delete* ]]
}

@test "ESO template projects only cosign.pub" {
  run cat "${SCRIPT_DIR}/etc/signing/externalsecret-cosign-pub.yaml.tmpl"
  [ "$status" -eq 0 ]
  [[ "$output" == *'property: cosign.pub'* ]]
  [[ "$output" != *'cosign.key'* ]]
  [[ "$output" != *'cosign.password'* ]]
}

@test "signing_status reports absent state and returns non-zero" {
  SIGNING_TEST_KEYCHAIN=0 SIGNING_TEST_VAULT_KEY=0 SIGNING_TEST_PUB=0
  run signing_status
  [ "$status" -ne 0 ]
  [[ "$output" == *'vault_key=absent'* ]]
  [[ "$output" == *'keychain_backup=absent'* ]]
  [[ "$output" == *'eso_public_secret=absent'* ]]
}
