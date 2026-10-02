#!/usr/bin/env bats

MAKEFILE="${BATS_TEST_DIRNAME}/../../../Makefile"
REPO_ROOT="${BATS_TEST_DIRNAME}/../../.."

@test "e2e records the vcluster harness" {
  run make --no-print-directory -C "${REPO_ROOT}" -n e2e
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"script -q"* ]]
  [[ "${output}" == *".k3dm/e2e/make-e2e-"* ]]
  [[ "${output}" == *"e2e_verify_vcluster"* ]]
  [[ "${output}" != *"tee"* ]]
}

@test "e2e-sandbox records the sandbox harness" {
  run make --no-print-directory -C "${REPO_ROOT}" -n e2e-sandbox
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"script -q"* ]]
  [[ "${output}" == *".k3dm/e2e/make-e2e-sandbox-"* ]]
  [[ "${output}" == *"e2e_verify_sandbox"* ]]
}

@test "e2e passes DIGEST through to the vcluster harness" {
  run make --no-print-directory -C "${REPO_ROOT}" -n e2e DIGEST=sha256:abc
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"e2e_verify_vcluster sha256:abc"* ]]
}

@test "recorded output preserves exit status and is mode 600" {
  minimal="${BATS_TEST_TMPDIR}/Makefile"
  awk '/^define _e2e_recorded$/{copy=1} copy{print} /^endef$/{exit}' "${MAKEFILE}" > "${minimal}"
  printf '\nprobe:\n\t@$(call _e2e_recorded,probe,/bin/sh -c '\''exit 7'\'')\n' >> "${minimal}"

  run env HOME="${BATS_TEST_TMPDIR}/home" make --no-print-directory -f "${minimal}" probe
  if [ "${status}" -ne 7 ]; then
    [ "${status}" -eq 2 ]
    [[ "${output}" == *"Error 7"* ]]
  fi
  logs=("${BATS_TEST_TMPDIR}/home/.k3dm/e2e"/make-*.log)
  [ "${#logs[@]}" -eq 1 ]
  mode=$(stat -c %a "${logs[0]}" 2>/dev/null || stat -f %Lp "${logs[0]}")
  [ "${mode}" = 600 ]
}

@test "help lists e2e targets but not the recording macro" {
  run make --no-print-directory -C "${REPO_ROOT}" help
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"make e2e "* ]]
  [[ "${output}" == *"make e2e-sandbox "* ]]
  [[ "${output}" != *"_e2e_recorded"* ]]
}
