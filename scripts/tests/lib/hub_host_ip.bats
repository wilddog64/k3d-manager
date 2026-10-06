#!/usr/bin/env bats

setup() {
  source "${BATS_TEST_DIRNAME}/../../lib/hub_host_ip.sh"
}

@test "hub host resolver selects the IPv4 answer after Name" {
  run grep -F 'seen && /^Address/' "${BATS_TEST_DIRNAME}/../../lib/hub_host_ip.sh"
  [ "${status}" -eq 0 ]
  docker() {
    cat <<'EOF'
Server: 192.168.97.1
Address: 192.168.97.1:53

Non-authoritative answer:

Name: host.docker.internal
Address: 0.250.250.254
EOF
  }
  run _hub_docker_host_ip
  [ "${status}" -eq 0 ]
  [ "${output}" = "0.250.250.254" ]
}

@test "hub host resolver returns empty for NXDOMAIN" {
  docker() {
    cat <<'EOF'
Server: 192.168.97.1
Address: 192.168.97.1:53
** server can't find host.docker.internal: NXDOMAIN
EOF
  }
  run _hub_docker_host_ip
  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
}

@test "hub host resolver returns empty when docker fails" {
  docker() { return 1; }
  run _hub_docker_host_ip
  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
}

@test "hub host resolver skips IPv6 and selects IPv4" {
  docker() {
    cat <<'EOF'
Name: host.docker.internal
Address: fe80::1
Address: 0.250.250.254
EOF
  }
  run _hub_docker_host_ip
  [ "${status}" -eq 0 ]
  [ "${output}" = "0.250.250.254" ]
}

@test "hub host resolver source contains no getent" {
  run bash -c 'set +e; grep -c getent "${1}"; test $? -eq 1' _ "${BATS_TEST_DIRNAME}/../../lib/hub_host_ip.sh"
  [ "${status}" -eq 0 ]
  [ "${output}" -eq 0 ]
}
