#!/usr/bin/env bats
# shellcheck shell=bash

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
  TESTS_ROOT="${REPO_ROOT}/scripts/tests"
}

@test "every BATS suite lives in a directory some target globs" {
  local -a _orphans=()
  local _file _rel

  while IFS= read -r _file; do
    _rel="${_file#"${TESTS_ROOT}"/}"
    case "${_rel}" in
      lib/*/*|core/*/*|plugins/*/*|etc/*/*|bin/*/*) _orphans+=("${_rel}") ;;
      lib/*|core/*|plugins/*|etc/*|bin/*) ;;
      *) _orphans+=("${_rel}") ;;
    esac
  done < <(find "${TESTS_ROOT}" -type f -name '*.bats' | sort)

  if [ "${#_orphans[@]}" -gt 0 ]; then
    printf 'BATS suites no target collects:\n' >&2
    printf '  scripts/tests/%s\n' "${_orphans[@]}" >&2
    printf 'make test globs scripts/tests/{lib,core,plugins,etc} at -maxdepth 1;\n' >&2
    printf 'make test-bin globs scripts/tests/bin. Move the file into one of those.\n' >&2
    return 1
  fi
}
