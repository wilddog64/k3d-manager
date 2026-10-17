#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
  FAKE_BIN="${BATS_TEST_TMPDIR}/bin"
  SERVICES_DIR="${BATS_TEST_TMPDIR}/services"
  mkdir -p "${FAKE_BIN}" "${SERVICES_DIR}/demo"
  CURL_LOG="${BATS_TEST_TMPDIR}/curl-argv.log"

  cat > "${FAKE_BIN}/gh" <<'EOF'
#!/usr/bin/env bash
if [[ "${FAIL_GH:-0}" == 1 ]]; then
  exit 1
fi
printf '%s\n' 'gho_FAKE_SECRET'
EOF
  cat > "${FAKE_BIN}/curl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${CURL_LOG}"
url="${!#}"
if [[ "${url}" == https://ghcr.io/token\?* ]]; then
  printf '%s\n' '{"token":"t"}'
elif [[ "${NO_DIGEST:-0}" != 1 ]]; then
  printf 'docker-content-digest: sha256:%s\r\n' "${LATEST_DIGEST}"
fi
EOF
  chmod +x "${FAKE_BIN}/gh" "${FAKE_BIN}/curl"
  export PATH="${FAKE_BIN}:${PATH}" CURL_LOG SERVICES_DIR
}

write_service() {
  local digest="${1:-}"
  if [[ -n "${digest}" ]]; then
    cat > "${SERVICES_DIR}/demo/kustomization.yaml" <<EOF
images:
  - name: ghcr.io/wilddog64/demo
    digest: sha256:${digest}
EOF
  else
    cat > "${SERVICES_DIR}/demo/kustomization.yaml" <<'EOF'
resources:
  - deployment.yaml
EOF
  fi
}

run_checker() {
  run env LATEST_DIGEST="${LATEST_DIGEST:-}" NO_DIGEST="${NO_DIGEST:-0}" FAIL_GH="${FAIL_GH:-0}" \
    "${REPO_ROOT}/bin/k3dm-image-pin-drift" --services-dir "${SERVICES_DIR}"
}

@test "image pin drift: matching digest is current" {
  LATEST_DIGEST=aaaaaaaaaaaa1111111111111111111111111111111111111111111111111111
  write_service "${LATEST_DIGEST}"
  run_checker
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"current"* ]]
  [[ "${output}" == *"pinned=aaaaaaaaaaaa"* ]]
  [[ "${output}" == *"latest=aaaaaaaaaaaa"* ]]
}

@test "image pin drift: differing digest is DRIFT" {
  LATEST_DIGEST=bbbbbbbbbbbb1111111111111111111111111111111111111111111111111111
  write_service aaaaaaaaaaaa1111111111111111111111111111111111111111111111111111
  run_checker
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"DRIFT"* ]]
  [[ "${output}" == *"pinned=aaaaaaaaaaaa"* ]]
  [[ "${output}" == *"latest=bbbbbbbbbbbb"* ]]
}

@test "image pin drift: digests sharing the displayed prefix still DRIFT" {
  LATEST_DIGEST=aaaaaaaaaaaa2222222222222222222222222222222222222222222222222222
  write_service aaaaaaaaaaaa1111111111111111111111111111111111111111111111111111
  run_checker
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"DRIFT"* ]]
}

@test "image pin drift: service without images is unpinned" {
  write_service
  run_checker
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"unpinned"* ]]
}

@test "image pin drift: missing manifest digest is unknown" {
  LATEST_DIGEST=aaaaaaaaaaaa1111111111111111111111111111111111111111111111111111
  write_service "${LATEST_DIGEST}"
  NO_DIGEST=1
  run_checker
  [ "${status}" -eq 2 ]
  [[ "${output}" == *"unknown"* ]]
}

@test "image pin drift: missing gh token names read:packages" {
  write_service
  FAIL_GH=1
  run_checker
  [ "${status}" -eq 2 ]
  [[ "${output}" == *"read:packages"* ]]
}

@test "image pin drift: gh token is absent from output and curl argv" {
  LATEST_DIGEST=aaaaaaaaaaaa1111111111111111111111111111111111111111111111111111
  write_service "${LATEST_DIGEST}"
  run_checker
  [ "${status}" -eq 0 ]
  [[ "${output}" != *"gho_FAKE_SECRET"* ]]
  run grep -Fq 'gho_FAKE_SECRET' "${CURL_LOG}"
  [ "${status}" -eq 1 ]
}

@test "image pin drift: unknown option is rejected" {
  run "${REPO_ROOT}/bin/k3dm-image-pin-drift" --not-an-option
  [ "${status}" -eq 2 ]
  [[ "${output}" == *"ERROR: unknown option: --not-an-option"* ]]
}
