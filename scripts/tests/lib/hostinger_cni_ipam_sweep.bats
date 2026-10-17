#!/usr/bin/env bats

setup() {
  SCRIPT_DIR="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  export SCRIPT_DIR
  SWEEP="${SWEEP:-${SCRIPT_DIR}/etc/hostinger/k3dm-cni-ipam-sweep.sh}"
  export SWEEP
  ipam_dir="${BATS_TEST_TMPDIR}/cbr0"
  state_file="${BATS_TEST_TMPDIR}/state"
  subnet_file="${BATS_TEST_TMPDIR}/subnet.env"
  stub_dir="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "${ipam_dir}" "${stub_dir}"
  printf 'FLANNEL_SUBNET=10.42.0.1/24\n' > "${subnet_file}"
  printf 'live-sandbox\n' > "${BATS_TEST_TMPDIR}/live"
  printf '10.42.0.2\n10.42.0.3\n' > "${BATS_TEST_TMPDIR}/running-ips"
  cat > "${stub_dir}/k3s" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${K3DM_K3S_FAIL:-0}" == 1 ]]; then exit 7; fi
if [[ "${1:-}" == "crictl" ]]; then cat "${K3DM_LIVE_FILE}"; else cat "${K3DM_RUNNING_IPS_FILE}"; fi
STUB
  cat > "${stub_dir}/flock" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
  cat > "${stub_dir}/journalctl" <<'STUB'
#!/usr/bin/env bash
cat "${K3DM_JOURNAL_FILE}"
STUB
  chmod +x "${stub_dir}"/*
  export PATH="${stub_dir}:${PATH}"
  export CNI_IPAM_DIR="${ipam_dir}" K3DM_CNI_IPAM_STATE="${state_file}" FLANNEL_SUBNET_ENV="${subnet_file}"
  export K3DM_LIVE_FILE="${BATS_TEST_TMPDIR}/live" K3DM_RUNNING_IPS_FILE="${BATS_TEST_TMPDIR}/running-ips"
  export K3DM_JOURNAL_FILE="${BATS_TEST_TMPDIR}/journal"
  printf 'no IP addresses available\nother\nno IP addresses available\n' > "${K3DM_JOURNAL_FILE}"
}

make_reservation() {
  printf '%s\n' "$2" > "${ipam_dir}/$1"
  touch -t "${3:-202001010000}" "${ipam_dir}/$1"
}

@test "sweep: dry-run counts stale without removing it" {
  make_reservation 10.42.0.10 stale-id
  run "${SWEEP}" --dry-run
  [ "$status" -eq 0 ]
  [ -f "${ipam_dir}/10.42.0.10" ]
  [[ "$output" == *"mode=dry-run"*"stale=1"*"range_size=254"*"alloc_errors_1h=2"* ]]
}

@test "sweep: apply removes stale and keeps live, reported, young and metadata files" {
  make_reservation 10.42.0.10 stale-id
  make_reservation 10.42.0.11 live-sandbox
  make_reservation 10.42.0.2 reported-id
  make_reservation 10.42.0.12 young-id "$(date +%Y%m%d%H%M)"
  : > "${ipam_dir}/lock"
  : > "${ipam_dir}/last_reserved_ip.0"
  run "${SWEEP}" --apply
  [ "$status" -eq 0 ]
  [ ! -e "${ipam_dir}/10.42.0.10" ]
  [ -e "${ipam_dir}/10.42.0.11" ]
  [ -e "${ipam_dir}/10.42.0.2" ]
  [ -e "${ipam_dir}/10.42.0.12" ]
  [ -e "${ipam_dir}/lock" ]
  [ -e "${ipam_dir}/last_reserved_ip.0" ]
  [[ "$output" == *"SKIP 10.42.0.2"* ]]
  grep -q '^young=1$' "${state_file}"
}

@test "sweep: empty sandbox list refuses to remove" {
  : > "${BATS_TEST_TMPDIR}/live"
  make_reservation 10.42.0.10 stale-id
  run "${SWEEP}" --apply
  [ "$status" -eq 1 ]
  [ -e "${ipam_dir}/10.42.0.10" ]
}

@test "sweep: empty pod IP list refuses to remove" {
  : > "${BATS_TEST_TMPDIR}/running-ips"
  make_reservation 10.42.0.10 stale-id
  run "${SWEEP}" --apply
  [ "$status" -eq 1 ]
  [ -e "${ipam_dir}/10.42.0.10" ]
}

@test "sweep: crictl failure refuses to remove" {
  export K3DM_K3S_FAIL=1
  make_reservation 10.42.0.10 stale-id
  run "${SWEEP}" --apply
  [ "$status" -ne 0 ]
  [ -e "${ipam_dir}/10.42.0.10" ]
}

@test "sweep: bad argument is rejected" {
  run "${SWEEP}" --bad
  [ "$status" -eq 2 ]
}

@test "N1: pre-fix sweep must fail the empty-list safety case" {
  [ "${SWEEP}" = "${SCRIPT_DIR}/tests/fixtures/cni-ipam/pre-fix-sweep.sh" ] || skip
  : > "${BATS_TEST_TMPDIR}/live"
  make_reservation 10.42.0.10 stale-id
  run "${SWEEP}" --apply
  [ "$status" -eq 1 ]
  [ -e "${ipam_dir}/10.42.0.10" ]
}

@test "N2: pre-fix sweep must fail the young-file safety case" {
  [ "${SWEEP}" = "${SCRIPT_DIR}/tests/fixtures/cni-ipam/pre-fix-sweep.sh" ] || skip
  make_reservation 10.42.0.10 young-id "$(date +%Y%m%d%H%M)"
  run "${SWEEP}" --apply
  [ "$status" -eq 0 ]
  [ -e "${ipam_dir}/10.42.0.10" ]
}
