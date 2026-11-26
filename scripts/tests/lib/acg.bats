#!/usr/bin/env bats
# shellcheck shell=bash disable=SC1091,SC2317
bats_require_minimum_version 1.5.0

setup() {
  export HOME="${BATS_TEST_TMPDIR}/home"
  mkdir -p "${HOME}"
  # shellcheck source=/dev/null
  source "${BATS_TEST_DIRNAME}/../../lib/acg/acg.sh"
}

_acg_credential_test_fixture() {
  local fixture_dir="${BATS_TEST_TMPDIR}/credential-test-fixture"
  mkdir -p "${fixture_dir}/bin" "${fixture_dir}/playwright"
  cp "${BATS_TEST_DIRNAME}/../../lib/acg/bin/acg-credential-test" "${fixture_dir}/bin/acg-credential-test"

  cat > "${fixture_dir}/cdp.sh" <<'EOF'
_browser_launch() { :; }
EOF

  cat > "${fixture_dir}/bin/node" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  */acg_credentials.js)
    printf 'AWS_ACCESS_KEY_ID=test-key\nAWS_SECRET_ACCESS_KEY=test-secret\n'
    ;;
  */acg_restart.js)
    printf 'restart\n' >> "${ACG_RESTART_SENTINEL}"
    ;;
esac
EOF
  chmod +x "${fixture_dir}/bin/node"

  cat > "${fixture_dir}/bin/aws" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  --version)
    if [[ "${AWS_STUB_SCENARIO}" == 'broken-cli' ]]; then
      printf 'dyld: Library not loaded\n' >&2
      exit 1
    fi
    printf 'aws-cli/2.test\n'
    ;;
  sts)
    case "${AWS_STUB_SCENARIO}" in
      invalid-credentials)
        printf 'An error occurred (InvalidClientTokenId)\n' >&2
        exit 1
        ;;
      network-error)
        printf 'Could not connect to the endpoint URL\n' >&2
        exit 1
        ;;
    esac
    ;;
esac
EOF
  chmod +x "${fixture_dir}/bin/aws"
  printf '%s\n' "${fixture_dir}"
}

@test "acg template emitter renders the requested agent fleet" {
  local rendered="${BATS_TEST_TMPDIR}/fleet.yaml"

  _acg_render_template 4 "${BATS_TEST_DIRNAME}/../../lib/acg/etc/acg-cluster.yaml" "${rendered}"

  [ "$(grep -c '^  Agent[0-9][0-9]*Instance:' "${rendered}")" -eq 4 ]
  [ "$(grep -c '^  Agent[0-9][0-9]*PublicIP:' "${rendered}")" -eq 4 ]
  [ "$(grep -c '^  ServerInstance:' "${rendered}")" -eq 1 ]
}

@test "acg template emitter preserves the two-agent default" {
  local rendered="${BATS_TEST_TMPDIR}/default.yaml"

  unset ACG_AGENT_COUNT
  _acg_validate_agent_count
  _acg_render_template "${_ACG_AGENT_COUNT}" "${BATS_TEST_DIRNAME}/../../lib/acg/etc/acg-cluster.yaml" "${rendered}"

  [ "$(grep -c '^  Agent[0-9][0-9]*Instance:' "${rendered}")" -eq 2 ]
  [ "$(grep -c '^  Agent[0-9][0-9]*PublicIP:' "${rendered}")" -eq 2 ]
}

@test "acg agent discovery collects every ordered stack output" {
  _run_command() {
    printf 'Agent1PublicIP\t%s\nAgent2PublicIP\t%s\nAgent3PublicIP\t%s\n' \
      10.0.0.11 10.0.0.12 10.0.0.13
  }
  _acg_discover_agent_ips

  [ "${#_ACG_AGENT_IPS[@]}" -eq 3 ]
  [ "${_ACG_AGENT_IPS[0]}" = "10.0.0.11" ]
  [ "${_ACG_AGENT_IPS[2]}" = "10.0.0.13" ]
}

@test "acg agent discovery orders agents numerically, not lexically" {
  # Deliberately out of order, with Agent10 present to expose a lexical sort
  # (lexically Agent10 sorts before Agent2 — must not happen here).
  _run_command() {
    printf 'Agent2PublicIP\t%s\nAgent10PublicIP\t%s\nAgent1PublicIP\t%s\n' \
      10.0.0.2 10.0.0.10 10.0.0.1
  }
  _acg_discover_agent_ips

  [ "${#_ACG_AGENT_IPS[@]}" -eq 3 ]
  [ "${_ACG_AGENT_IPS[0]}" = "10.0.0.1" ]
  [ "${_ACG_AGENT_IPS[1]}" = "10.0.0.2" ]
  [ "${_ACG_AGENT_IPS[2]}" = "10.0.0.10" ]
}

@test "acg agent discovery keeps two IPs when the default is used" {
  _run_command() {
    printf 'Agent1PublicIP\t%s\nAgent2PublicIP\t%s\n' 10.0.0.11 10.0.0.12
  }
  _acg_discover_agent_ips

  [ "${#_ACG_AGENT_IPS[@]}" -eq 2 ]
}

@test "_acg_update_ssh_config creates missing SSH config and server target idempotently" {
  _acg_update_ssh_config "44.247.81.210"
  [ -f "${HOME}/.ssh/config" ]
  run cat "${HOME}/.ssh/config"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Host ubuntu"* ]]
  [[ "$output" == *"HostName 44.247.81.210"* ]]

  _acg_update_ssh_config "44.247.81.210"
  run grep -c '^Host ubuntu$' "${HOME}/.ssh/config"
  [ "$output" -eq 1 ]
}

@test "_acg_update_ssh_config adds server stanza without changing agent aliases" {
  mkdir -p "${HOME}/.ssh"
  cat > "${HOME}/.ssh/config" <<'EOF'
Host ubuntu-1
  HostName 10.0.0.1
Host ubuntu-2
  HostName 10.0.0.2
EOF

  _acg_update_ssh_config "44.247.81.210"
  run cat "${HOME}/.ssh/config"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Host ubuntu-1
  HostName 10.0.0.1"* ]]
  [[ "$output" == *"Host ubuntu-2
  HostName 10.0.0.2"* ]]
  [[ "$output" == *"Host ubuntu
  HostName 44.247.81.210"* ]]
}

@test "_acg_update_ssh_config updates existing server and tunnel stanzas" {
  mkdir -p "${HOME}/.ssh"
  cat > "${HOME}/.ssh/config" <<'EOF'
Host ubuntu
  HostName 192.0.2.10
Host ubuntu-tunnel
  HostName 192.0.2.10
Host ubuntu-1
  HostName 10.0.0.1
EOF

  _acg_update_ssh_config "44.247.81.210"
  run cat "${HOME}/.ssh/config"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Host ubuntu
  HostName 44.247.81.210"* ]]
  [[ "$output" == *"Host ubuntu-tunnel
  HostName 44.247.81.210"* ]]
  [[ "$output" == *"Host ubuntu-1
  HostName 10.0.0.1"* ]]
}

@test "acg rejects malformed or zero agent counts before any aws call" {
  aws_calls="${BATS_TEST_TMPDIR}/aws.calls"
  _run_command() {
    printf '%s\n' "$*" >> "${aws_calls}"
    return 1
  }
  _err() { :; }
  export ACG_AGENT_COUNT="not-a-number"

  run acg_provision --confirm
  [ "${status}" -ne 0 ]
  [ ! -e "${aws_calls}" ]

  export ACG_AGENT_COUNT=0
  run acg_provision --confirm
  [ "${status}" -ne 0 ]
  [ ! -e "${aws_calls}" ]
}

@test "acg source has no hardcoded first or second agent names" {
  run grep -nE 'Agent[12]([^0-9]|$)|agent[12]_ip' "${BATS_TEST_DIRNAME}/../../lib/acg/acg.sh"
  [ "${status}" -ne 0 ]
}

@test "acg CDP plist uses the Playwright browser and active profile" {
  local browser_bin="${BATS_TEST_TMPDIR}/playwright-chromium"
  touch "${browser_bin}"
  chmod +x "${browser_bin}"
  _acg_resolve_cdp_browser_bin() {
    printf '%s\n' "${browser_bin}"
  }

  _acg_chrome_cdp_write_plist

  [ -f "${_ACG_CHROME_CDP_PLIST}" ]
  grep -F "<string>${browser_bin}</string>" "${_ACG_CHROME_CDP_PLIST}"
  run ! grep -F '/Applications/Google Chrome.app' "${_ACG_CHROME_CDP_PLIST}"
  grep -F -- "--user-data-dir=${PLAYWRIGHT_AUTH_DIR}" "${_ACG_CHROME_CDP_PLIST}"
  [[ "${PLAYWRIGHT_AUTH_DIR}" == */pw-profile ]]
}

@test "acg CDP plist is not written without a Playwright browser" {
  _acg_resolve_cdp_browser_bin() {
    return 1
  }

  run _acg_chrome_cdp_write_plist

  [ "${status}" -ne 0 ]
  [[ "${output}" == *'Playwright-managed Chromium not found'* ]]
  [ ! -e "${_ACG_CHROME_CDP_PLIST}" ]
}

@test "acg credential test does not restart when aws CLI cannot run" {
  local fixture_dir sentinel="${BATS_TEST_TMPDIR}/restart-sentinel"
  fixture_dir=$(_acg_credential_test_fixture)

  run env PATH="${fixture_dir}/bin:${PATH}" ACG_RESTART_SENTINEL="${sentinel}" AWS_STUB_SCENARIO=broken-cli \
    "${fixture_dir}/bin/acg-credential-test" 'https://example.test/sandbox' --provider aws

  [ "${status}" -ne 0 ]
  [[ "${output}" == *'the aws CLI is present but cannot run'* ]]
  [ ! -e "${sentinel}" ]
}

@test "acg credential test does not restart when aws CLI is missing" {
  local fixture_dir sentinel="${BATS_TEST_TMPDIR}/restart-sentinel"
  fixture_dir=$(_acg_credential_test_fixture)
  rm -f "${fixture_dir}/bin/aws"
  ln -s "$(command -v bash)" "${fixture_dir}/bin/bash"
  if env PATH="${fixture_dir}/bin:/usr/bin:/bin" bash -c 'command -v aws' >/dev/null 2>&1; then
    skip "aws is installed in /usr/bin or /bin; cannot exercise the missing-CLI branch on this host"
  fi

  run env PATH="${fixture_dir}/bin:/usr/bin:/bin" ACG_RESTART_SENTINEL="${sentinel}" \
    "${fixture_dir}/bin/acg-credential-test" 'https://example.test/sandbox' --provider aws

  [ "${status}" -ne 0 ]
  [[ "${output}" == *'the aws CLI is not installed or not on PATH'* ]]
  [[ "${output}" != *'present but cannot run'* ]]
  [ ! -e "${sentinel}" ]
}

@test "acg credential test restarts once for rejected AWS credentials" {
  local fixture_dir sentinel="${BATS_TEST_TMPDIR}/restart-sentinel"
  fixture_dir=$(_acg_credential_test_fixture)

  run env PATH="${fixture_dir}/bin:${PATH}" ACG_RESTART_SENTINEL="${sentinel}" AWS_STUB_SCENARIO=invalid-credentials \
    "${fixture_dir}/bin/acg-credential-test" 'https://example.test/sandbox' --provider aws

  [ "${status}" -ne 0 ]
  [ "$(wc -l < "${sentinel}")" -eq 1 ]
}

@test "acg credential test does not restart for an AWS network error" {
  local fixture_dir sentinel="${BATS_TEST_TMPDIR}/restart-sentinel"
  fixture_dir=$(_acg_credential_test_fixture)

  run env PATH="${fixture_dir}/bin:${PATH}" ACG_RESTART_SENTINEL="${sentinel}" AWS_STUB_SCENARIO=network-error \
    "${fixture_dir}/bin/acg-credential-test" 'https://example.test/sandbox' --provider aws

  [ "${status}" -ne 0 ]
  [[ "${output}" == *'Could not connect to the endpoint URL'* ]]
  [ ! -e "${sentinel}" ]
}

@test "acg_watch retries a failed extend and stops retrying on success" {
  local instance_calls="${BATS_TEST_TMPDIR}/instance-calls"
  local extend_calls="${BATS_TEST_TMPDIR}/extend-calls"
  : >"${instance_calls}"
  : >"${extend_calls}"
  sleep() { :; }
  _acg_get_instance_id() {
    local calls
    calls=$(wc -l <"${instance_calls}")
    printf 'call\n' >>"${instance_calls}"
    if [[ "${calls}" -eq 0 ]]; then
      printf 'i-a\n'
    else
      printf '\n'
    fi
  }
  _acg_extend_playwright() {
    local calls
    calls=$(wc -l <"${extend_calls}")
    printf 'call\n' >>"${extend_calls}"
    [[ "${calls}" -ge 2 ]]
  }

  run acg_watch 1

  [ "${status}" -eq 0 ]
  [ "$(wc -l <"${extend_calls}")" -eq 3 ]
  [[ "${output}" == *"attempt 1/3"* ]]
  [[ "${output}" == *"attempt 2/3"* ]]
  [[ "${output}" != *"extend manually"* ]]
}

@test "acg_watch gives up after 3 failed attempts" {
  local instance_calls="${BATS_TEST_TMPDIR}/instance-calls"
  local extend_calls="${BATS_TEST_TMPDIR}/extend-calls"
  : >"${instance_calls}"
  : >"${extend_calls}"
  sleep() { :; }
  _acg_get_instance_id() {
    local calls
    calls=$(wc -l <"${instance_calls}")
    printf 'call\n' >>"${instance_calls}"
    if [[ "${calls}" -eq 0 ]]; then
      printf 'i-a\n'
    else
      printf '\n'
    fi
  }
  _acg_extend_playwright() {
    printf 'call\n' >>"${extend_calls}"
    return 1
  }

  run acg_watch 1

  [ "${status}" -eq 0 ]
  [ "$(wc -l <"${extend_calls}")" -eq 3 ]
  [[ "${output}" == *"Extend failed 3 times"* ]]
}

@test "the launchd wrapper runs acg_extend.js with node found under a launchd PATH" {
  local node_dir="${BATS_TEST_TMPDIR}/nodebin"
  mkdir -p "${node_dir}"
  cat >"${node_dir}/node" <<NODE
#!/usr/bin/env bash
printf '%s\n' "\$@" > "${BATS_TEST_TMPDIR}/node-args"
NODE
  chmod +x "${node_dir}/node"

  PATH="${node_dir}:${PATH}" _acg_watch_write_wrapper 'https://example.test/sandbox'
  run env PATH=/usr/bin:/bin bash "${_ACG_WATCH_WRAPPER}"

  [ "${status}" -eq 0 ]
  grep -F 'playwright/acg_extend.js' "${BATS_TEST_TMPDIR}/node-args"
  grep -F 'https://example.test/sandbox' "${BATS_TEST_TMPDIR}/node-args"
  run grep -F '../../k3d-manager' "${_ACG_WATCH_WRAPPER}"
  [ "${status}" -ne 0 ]
}

@test "the wrapper writer refuses when node is absent" {
  if [[ -e /usr/bin/node || -e /bin/node ]]; then
    skip "node exists in /usr/bin or /bin on this runner"
  fi

  run env HOME="${HOME}" PATH=/usr/bin:/bin bash -c \
    'source "'"${BATS_TEST_DIRNAME}/../../lib/acg/acg.sh"'"; _acg_watch_write_wrapper https://example.test/sandbox'

  [ "${status}" -ne 0 ]
}

@test "the launchd watcher plist runs every 30 minutes" {
  _acg_watch_write_plist
  grep -F '<integer>1800</integer>' "${_ACG_WATCH_PLIST_PATH}"
  run grep -F '12600' "${_ACG_WATCH_PLIST_PATH}"
  [ "${status}" -ne 0 ]
}

@test "acg_watch defaults to a 30-minute interval" {
  sleep() { printf '%s\n' "$1" >>"${BATS_TEST_TMPDIR}/sleep-args"; }
  _acg_get_instance_id() { printf '\n'; }

  run acg_watch
  [ "${status}" -eq 0 ]
  [ "$(head -n1 "${BATS_TEST_TMPDIR}/sleep-args")" = "1800" ]
}

_acg_teardown_fixture() {
  local fixture_dir="${BATS_TEST_TMPDIR}/teardown-fixture"
  mkdir -p "${fixture_dir}"
  cat >"${fixture_dir}/aws" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${ACG_CALLS_FILE}"
case "$*" in
  *"describe-stacks"*)
    case "${ACG_TEARDOWN_SCENARIO}" in
      success|delete-fails|wait-fails) printf 'CREATE_COMPLETE\n' ;;
      missing) printf '%s\n' 'An error occurred (ValidationError) when calling the DescribeStacks operation: Stack with id k3d-manager-cluster does not exist' >&2; exit 255 ;;
      throttled) printf '%s\n' 'An error occurred (Throttling) when calling the DescribeStacks operation: Rate exceeded' >&2; exit 255 ;;
      denied) printf '%s\n' 'An error occurred (AccessDenied) when calling the DescribeStacks operation: User is not authorized' >&2; exit 255 ;;
    esac
    ;;
  *"delete-stack"*)
    if [[ "${ACG_TEARDOWN_SCENARIO}" == delete-fails ]]; then
      exit 1
    fi
    exit 0
    ;;
  *"stack-delete-complete"*)
    if [[ "${ACG_TEARDOWN_SCENARIO}" == wait-fails ]]; then
      exit 1
    fi
    exit 0
    ;;
esac
EOF
  cat >"${fixture_dir}/kubectl" <<'EOF'
#!/usr/bin/env bash
printf 'kubectl %s\n' "$*" >>"${ACG_CALLS_FILE}"
case "$*" in
  *"get-contexts"*) exit 0 ;;
  *"delete-context"*) exit 0 ;;
esac
EOF
  chmod +x "${fixture_dir}/aws" "${fixture_dir}/kubectl"
  printf '%s\n' "${fixture_dir}"
}

@test "acg_teardown deletes a found stack and reports success" {
  local fixture_dir calls
  fixture_dir=$(_acg_teardown_fixture)
  calls="${BATS_TEST_TMPDIR}/teardown-calls"
  : >"${calls}"

  run env PATH="${fixture_dir}:${PATH}" ACG_CALLS_FILE="${calls}" ACG_TEARDOWN_SCENARIO=success \
    bash -c 'source "${1}"; _acg_check_credentials() { return 0; }; acg_teardown --confirm' _ \
    "${BATS_TEST_DIRNAME}/../../lib/acg/acg.sh"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Stack deleted"* ]]
  grep -F 'cloudformation delete-stack' "${calls}"
  grep -F 'cloudformation wait stack-delete-complete' "${calls}"
  grep -F 'kubectl config delete-context' "${calls}"
}

@test "acg_teardown treats a missing stack as success" {
  local fixture_dir calls
  fixture_dir=$(_acg_teardown_fixture)
  calls="${BATS_TEST_TMPDIR}/teardown-calls"
  : >"${calls}"

  run env PATH="${fixture_dir}:${PATH}" ACG_CALLS_FILE="${calls}" ACG_TEARDOWN_SCENARIO=missing \
    bash -c 'source "${1}"; _acg_check_credentials() { return 0; }; acg_teardown --confirm' _ \
    "${BATS_TEST_DIRNAME}/../../lib/acg/acg.sh"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"nothing to tear down"* ]]
  [[ "${output}" != *"ValidationError"* ]]
  run ! grep -F 'cloudformation delete-stack' "${calls}"
}

@test "acg_teardown returns 2 on a throttled lookup without deleting" {
  local fixture_dir calls
  fixture_dir=$(_acg_teardown_fixture)
  calls="${BATS_TEST_TMPDIR}/teardown-calls"
  : >"${calls}"

  run env PATH="${fixture_dir}:${PATH}" ACG_CALLS_FILE="${calls}" ACG_TEARDOWN_SCENARIO=throttled \
    bash -c 'source "${1}"; _acg_check_credentials() { return 0; }; acg_teardown --confirm' _ \
    "${BATS_TEST_DIRNAME}/../../lib/acg/acg.sh"

  [ "${status}" -eq 2 ]
  [[ "${output}" != *"Throttling"* ]]
  run ! grep -F 'cloudformation delete-stack' "${calls}"
  run ! grep -F 'kubectl config delete-context' "${calls}"
}

@test "acg_teardown returns 2 on an access-denied lookup" {
  local fixture_dir calls
  fixture_dir=$(_acg_teardown_fixture)
  calls="${BATS_TEST_TMPDIR}/teardown-calls"
  : >"${calls}"

  run env PATH="${fixture_dir}:${PATH}" ACG_CALLS_FILE="${calls}" ACG_TEARDOWN_SCENARIO=denied \
    bash -c 'source "${1}"; _acg_check_credentials() { return 0; }; acg_teardown --confirm' _ \
    "${BATS_TEST_DIRNAME}/../../lib/acg/acg.sh"

  [ "${status}" -eq 2 ]
  [[ "${output}" != *"AccessDenied"* ]]
  run ! grep -F 'cloudformation delete-stack' "${calls}"
  run ! grep -F 'kubectl config delete-context' "${calls}"
}

@test "acg_teardown returns 3 and returns to the shell when delete fails" {
  local fixture_dir calls
  fixture_dir=$(_acg_teardown_fixture)
  calls="${BATS_TEST_TMPDIR}/teardown-calls"
  : >"${calls}"

  run env PATH="${fixture_dir}:${PATH}" ACG_CALLS_FILE="${calls}" ACG_TEARDOWN_SCENARIO=delete-fails \
    bash -c 'source "${1}"; _acg_check_credentials() { return 0; }; rc=0; acg_teardown --confirm || rc=$?; echo FUNCTION_RETURNED; exit "$rc"' _ \
    "${BATS_TEST_DIRNAME}/../../lib/acg/acg.sh"

  [ "${status}" -eq 3 ]
  [[ "${output}" == *"FUNCTION_RETURNED"* ]]
  run ! grep -F 'kubectl config delete-context' "${calls}"
}

@test "acg_teardown returns 3 and returns to the shell when delete wait fails" {
  local fixture_dir calls
  fixture_dir=$(_acg_teardown_fixture)
  calls="${BATS_TEST_TMPDIR}/teardown-calls"
  : >"${calls}"

  run env PATH="${fixture_dir}:${PATH}" ACG_CALLS_FILE="${calls}" ACG_TEARDOWN_SCENARIO=wait-fails \
    bash -c 'source "${1}"; _acg_check_credentials() { return 0; }; rc=0; acg_teardown --confirm || rc=$?; echo FUNCTION_RETURNED; exit "$rc"' _ \
    "${BATS_TEST_DIRNAME}/../../lib/acg/acg.sh"

  [ "${status}" -eq 3 ]
  [[ "${output}" == *"FUNCTION_RETURNED"* ]]
  run ! grep -F 'kubectl config delete-context' "${calls}"
}

_acg_key_fixture() {
  [ "${HOME}" = "${BATS_TEST_TMPDIR}/home" ]
  mkdir -p "${HOME}/.ssh" "${BATS_TEST_TMPDIR}/key-bin"
  export ACG_CALLS_FILE="${BATS_TEST_TMPDIR}/key-calls" ACG_KEY_SCENARIO="${1}"
  cat >"${BATS_TEST_TMPDIR}/key-bin/aws" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${ACG_CALLS_FILE}"
case "$*" in
  *import-key-pair*)
    # k3d-manager M5 read-only capture, 2026-11-01: DryRunOperation.
    case "${ACG_KEY_SCENARIO}" in denied) echo 'An error occurred (DryRunOperation)' >&2; exit 1;; duplicate|mismatch) echo 'An error occurred (InvalidKeyPair.Duplicate)' >&2; exit 1;; esac ;;
  *describe-key-pairs*)
    if [[ -n "${ACG_REMOTE_FP:-}" ]]; then printf '%s\n' "${ACG_REMOTE_FP}"; exit 0; fi
    case "${ACG_KEY_SCENARIO}" in missing) echo 'not found' >&2; exit 1;; mismatch) echo 'SHA256:bb:bb';; *) echo 'SHA256:aa:aa';; esac ;;
  *describe-images*) echo ami-test ;;
esac
STUB
  cat >"${BATS_TEST_TMPDIR}/key-bin/ssh-keygen" <<'STUB'
#!/usr/bin/env bash
printf 'ssh-keygen %s\n' "$*" >>"${ACG_CALLS_FILE}"
case "$1" in
  -y) [[ "${ACG_KEY_SCENARIO}" != derive-fails ]] || exit 1; echo 'ssh-ed25519 test-public-material' ;;
  -E) echo '256 SHA256:aa:aa comment (ED25519)' ;;
esac
STUB
  chmod +x "${BATS_TEST_TMPDIR}/key-bin/"{aws,ssh-keygen}
  export PATH="${BATS_TEST_TMPDIR}/key-bin:${PATH}"
  _acg_check_credentials() { :; }
  _run_command() { while [[ "$1" == --* ]]; do [[ "$1" == -- ]] && { shift; break; }; shift; done; "$@"; }
}

@test "acg provisioning rejects missing private key before AWS" {
  _acg_key_fixture success
  run acg_provision --confirm --recreate
  [ "$status" -ne 0 ]
  [[ "$output" == *"${_ACG_KEY_PEM}"* && "$output" == *'make machine-setup ROLE=hub'* ]]
  [ ! -e "${ACG_CALLS_FILE}" ]
}

@test "acg provisioning derives empty public key and imports it" {
  _acg_key_fixture success
  touch "${_ACG_KEY_PEM}" "${_ACG_KEY_PEM%.pem}.pub"
  run acg_provision --confirm
  [ "$status" -eq 0 ]
  grep -q 'ssh-keygen -y' "${ACG_CALLS_FILE}"
  grep -q 'import-key-pair' "${ACG_CALLS_FILE}"
  grep -q 'cloudformation deploy' "${ACG_CALLS_FILE}"
  [[ "$output" != *test-public-material* ]]
}

@test "acg provisioning removes failed public key derivation" {
  _acg_key_fixture derive-fails
  touch "${_ACG_KEY_PEM}" "${_ACG_KEY_PEM%.pem}.pub"
  run acg_provision --confirm
  [ "$status" -ne 0 ]
  [ ! -e "${_ACG_KEY_PEM%.pem}.pub" ]
  run ! grep -q 'import-key-pair' "${ACG_CALLS_FILE}"
}

@test "acg provisioning accepts matching duplicate and rejects mismatched fingerprint" {
  _acg_key_fixture duplicate
  touch "${_ACG_KEY_PEM}"
  run acg_provision --confirm
  [ "$status" -eq 0 ]
  grep -q 'cloudformation deploy' "${ACG_CALLS_FILE}"
  : >"${ACG_CALLS_FILE}"
  export ACG_KEY_SCENARIO=mismatch
  run acg_provision --confirm
  [ "$status" -ne 0 ]
  [[ "$output" == *'aa:aa'* && "$output" == *'bb:bb'* ]]
  [[ "$output" != *test-public-material* ]]
  run ! grep -q 'cloudformation deploy' "${ACG_CALLS_FILE}"
}

@test "acg provisioning stops when imported pair cannot be found" {
  _acg_key_fixture missing
  touch "${_ACG_KEY_PEM}"
  run acg_provision --confirm
  [ "$status" -ne 0 ]
  run ! grep -q 'cloudformation deploy' "${ACG_CALLS_FILE}"
}

@test "acg provisioning shows import errors and stops" {
  _acg_key_fixture denied
  touch "${_ACG_KEY_PEM}"
  run acg_provision --confirm
  [ "$status" -ne 0 ]
  [[ "$output" == *DryRunOperation* ]]
  [[ "$output" != *test-public-material* ]]
  run ! grep -q 'cloudformation deploy' "${ACG_CALLS_FILE}"
}

# Fingerprint commands follow AWS EC2 "Verify the fingerprint of your key pair"
# and DescribeKeyPairs documentation, retrieved 2026-11-01. Keys are ephemeral.
_acg_real_duplicate_key() {
  local kind="$1"
  local real_ssh real_openssl
  real_ssh="$(command -v ssh-keygen)"
  [[ "$HOME" == "$BATS_TEST_TMPDIR/"* ]]
  _acg_key_fixture duplicate
  "$real_ssh" -q -t "$kind" -N '' -f "$_ACG_KEY_PEM"
  mv "$_ACG_KEY_PEM.pub" "${_ACG_KEY_PEM%.pem}.pub"
  cat >"${BATS_TEST_TMPDIR}/key-bin/ssh-keygen" <<'STUB'
#!/usr/bin/env bash
exec "$REAL_SSH_KEYGEN" "$@"
STUB
  chmod +x "${BATS_TEST_TMPDIR}/key-bin/ssh-keygen"
  export REAL_SSH_KEYGEN="$real_ssh"
  if [[ "$kind" == ed25519 ]]; then
    # Captured on m5-air, 2026-11-03: AWS returns bare SHA-256 Base64 with padding.
    ACG_REMOTE_FP="$("$real_ssh" -E sha256 -lf "${_ACG_KEY_PEM%.pem}.pub" | awk '{sub(/^SHA256:/, "", $2); print $2"="}')"
  else
    real_openssl="$(command -v openssl)"
    ACG_REMOTE_FP="$("$real_ssh" -f "${_ACG_KEY_PEM%.pem}.pub" -e -m PKCS8 | "$real_openssl" pkey -pubin -outform DER | "$real_openssl" md5 -c | awk '{print $NF}')"
  fi
  export ACG_REMOTE_FP
}

@test "acg provisioning accepts matching imported Ed25519 fingerprint and rejects mismatch" {
  local local_fp
  _acg_real_duplicate_key ed25519
  local_fp="${ACG_REMOTE_FP%=}"
  run _acg_imported_key_fingerprint "${_ACG_KEY_PEM%.pem}.pub"
  [ "$status" -eq 0 ]
  [ "$output" = "$local_fp" ]
  run _acg_import_key
  [ "$status" -eq 0 ]
  export ACG_REMOTE_FP="$local_fp"
  run _acg_import_key
  [ "$status" -eq 0 ]
  export ACG_REMOTE_FP="SHA256:${local_fp}="
  run _acg_import_key
  [ "$status" -eq 0 ]
  export ACG_REMOTE_FP="${local_fp}=junk"
  run _acg_import_key
  [ "$status" -ne 0 ]
  export ACG_REMOTE_FP="${local_fp}=="
  run _acg_import_key
  [ "$status" -ne 0 ]
  export ACG_REMOTE_FP='wrong'
  run _acg_import_key
  [ "$status" -ne 0 ]
  [[ "$output" == *'fingerprint mismatch'* ]]
}

@test "acg provisioning accepts matching imported RSA fingerprint and rejects mismatch" {
  _acg_real_duplicate_key rsa
  run _acg_import_key
  [ "$status" -eq 0 ]
  export ACG_REMOTE_FP='00:00:00:00'
  run _acg_import_key
  [ "$status" -ne 0 ]
  [[ "$output" == *'fingerprint mismatch'* ]]
}

@test "acg imported key fingerprint refuses unsupported and malformed keys" {
  local public="${BATS_TEST_TMPDIR}/invalid.pub"
  [[ "$public" == "$BATS_TEST_TMPDIR/"* ]]
  printf 'ssh-dss fake\n' > "$public"
  run _acg_imported_key_fingerprint "$public"
  [ "$status" -ne 0 ]
  [[ "$output" == *'Unsupported public key type'* ]]
  printf 'ssh-rsa invalid\n' > "$public"
  run _acg_imported_key_fingerprint "$public"
  [ "$status" -ne 0 ]
}
