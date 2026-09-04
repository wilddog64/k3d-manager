#!/usr/bin/env bats
# shellcheck shell=bash disable=SC1091,SC2317

setup() {
  export HOME="${BATS_TEST_TMPDIR}/home"
  mkdir -p "${HOME}"
  # shellcheck source=/dev/null
  source "${BATS_TEST_DIRNAME}/../../lib/acg/acg.sh"
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
