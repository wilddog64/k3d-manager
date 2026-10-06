#!/usr/bin/env bats

MAKEFILE="${BATS_TEST_DIRNAME}/../../../Makefile"

setup() {
  WORK="${BATS_TEST_TMPDIR}/work"
  mkdir -p "${WORK}"
  cp "${MAKEFILE}" "${WORK}/Makefile"
}

@test "make help shows the current default URL" {
  run env -u URL make --no-print-directory -C "${WORK}" help
  [ "${status}" -eq 0 ]
  printf '%s\n' "${output}" | grep -Fx '  Default URL: https://app.pluralsight.com/hands-on/playground/cloud-sandboxes'
}

@test "the retired URL is absent from the Makefile copy" {
  run grep -c 'cloud-playground' "${WORK}/Makefile"
  [ "${status}" -eq 1 ]
  [ "${output}" = "0" ]
}

@test "a command-line URL override still wins" {
  run env -u URL make --no-print-directory -C "${WORK}" help URL=https://example.test/sb
  [ "${status}" -eq 0 ]
  printf '%s\n' "${output}" | grep -Fx '  Default URL: https://example.test/sb'
}
