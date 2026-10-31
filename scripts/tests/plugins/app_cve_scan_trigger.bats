#!/usr/bin/env bats

setup() {
  source "${BATS_TEST_DIRNAME}/../test_helpers.bash"
  init_test_env
  source "${BATS_TEST_DIRNAME}/../../plugins/observability.sh"
  CALLS="${BATS_TEST_TMPDIR}/calls"
  : >"${CALLS}"
  export CALLS
  _kubectl() {
    printf 'kubectl %s\n' "$*" >>"${CALLS}"
    if [[ "${1:-}" == "-n" && "${3:-}" == get && "${4:-}" == cronjob/* && "${CRONJOB_ABSENT:-0}" -eq 1 ]]; then
      return 1
    fi
    if [[ "${1:-}" == "-n" && "${3:-}" == wait && "${WAIT_FAIL:-0}" -eq 1 ]]; then
      return 1
    fi
    return 0
  }
  _info() { printf 'info %s\n' "$*" >>"${CALLS}"; }
  _err() { printf 'err %s\n' "$*" >>"${CALLS}"; }
}

@test "app_cve_scan_trigger rejects an unsupported cronjob name" {
  run app_cve_scan_trigger evil-job
  [ "${status}" -ne 0 ]
  [ "$(grep -cE '(^| )create( |$)' "${CALLS}" || true)" -eq 0 ]
}

@test "app_cve_scan_trigger fails when the cronjob is absent" {
  CRONJOB_ABSENT=1 run app_cve_scan_trigger app-cve-scan
  [ "${status}" -ne 0 ]
  [ "$(grep -cE '(^| )create( |$)' "${CALLS}" || true)" -eq 0 ]
}

@test "app_cve_scan_trigger creates a job from the cronjob" {
  run app_cve_scan_trigger app-cve-scan
  [ "${status}" -eq 0 ]
  grep -Eq '(^| )--from=cronjob/app-cve-scan( |$)' "${CALLS}"
  grep -Eq '(^| )app-cve-scan-manual-[0-9]{10,}( |$)' "${CALLS}"
}

@test "app_cve_scan_trigger defaults to app-cve-scan with no argument" {
  run app_cve_scan_trigger
  [ "${status}" -eq 0 ]
  grep -Eq '(^| )--from=cronjob/app-cve-scan( |$)' "${CALLS}"
}

@test "app_cve_scan_trigger returns non-zero when the wait times out" {
  WAIT_FAIL=1 run app_cve_scan_trigger app-cve-scan
  [ "${status}" -ne 0 ]
  grep -Eq '(^| )get job/app-cve-scan-manual-[0-9]{10,}( |$)' "${CALLS}"
}

@test "app_cve_scan_trigger honours K3DM_CVE_SCAN_WAIT" {
  K3DM_CVE_SCAN_WAIT=42 run app_cve_scan_trigger app-cve-scan
  [ "${status}" -eq 0 ]
  grep -Eq '(^| )--timeout=42s( |$)' "${CALLS}"
}

@test "app_cve_scan: clears only build caches across pages before dispatch, even on delete failure" {
  sed '/^# === MAIN ===/,$d' "${BATS_TEST_DIRNAME}/../../etc/argocd/platform-ops/app-cve-scan.sh" >"${BATS_TEST_TMPDIR}/scan.sh"
  cat >"${BATS_TEST_TMPDIR}/curl" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" >>"${CALLS}.argv"
for arg do config="$arg"; done
python3 -c 'import os, sys; sys.exit((os.stat(sys.argv[1]).st_mode & 0o777) != 0o600)' "$config" || exit 7
url=$(sed -n 's/^url = "\(.*\)"/\1/p' "$config")
printf '%s\n' "$url" >>"${CALLS}.urls"
# Key shapes captured from GET repos/wilddog64/shopping-cart-product-catalog/actions/caches (m4-air, 2026-10-31):
# buildkit-blob-1-sha256:<hex>, index-buildkit-1-f921bd05#N, cache-trivy-<date>, trivy-binary-v0.69.3-Linux-X64.
case "$url" in
  *'page=1') jq -n '{actions_caches: ([{"id":1,"key":"buildkit-blob-1-sha256:0b6f1c9e2d4a"},{"id":2,"key":"cache-trivy-2026-10-31"}] + [range(3;101) | {id: ., key: "trivy-binary-v0.69.3-Linux-X64"}])}' ;;
  *'page=2') printf '%s\n' '{"actions_caches":[{"id":101,"key":"index-buildkit-1-f921bd05#1"},{"id":102,"key":"cache-trivy-2026-10-30"}]}' ;;
  */caches/1) exit 22 ;;
  */caches/101|*/dispatches) exit 0 ;;
  *) exit 8 ;;
esac
STUB
  chmod +x "${BATS_TEST_TMPDIR}/curl"
  export GH_TOKEN='secret-token' GH_OWNER=wilddog64
  run sh -c '. "$1"; _CURL_BIN="$2"; _dispatch_rebuild shopping-cart-product-catalog ci.yaml' sh "${BATS_TEST_TMPDIR}/scan.sh" "${BATS_TEST_TMPDIR}/curl"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [[ "$output" == *'warning: could not delete build cache 1'* ]]
  [[ "$output" == *'cleared 1 build cache entries'* ]]
  [ "$(wc -l <"${CALLS}.urls" | tr -d ' ')" -eq 5 ]
  grep -q 'page=2' "${CALLS}.urls"
  grep -q '/caches/1$' "${CALLS}.urls"
  grep -q '/caches/101$' "${CALLS}.urls"
  tail -1 "${CALLS}.urls" | grep -q '/dispatches$'
  run ! grep -q 'secret-token' "${CALLS}.argv"
}
