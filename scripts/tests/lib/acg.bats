#!/usr/bin/env bats
# shellcheck shell=bash disable=SC1091,SC2317

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
  ! grep -F '/Applications/Google Chrome.app' "${_ACG_CHROME_CDP_PLIST}"
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
