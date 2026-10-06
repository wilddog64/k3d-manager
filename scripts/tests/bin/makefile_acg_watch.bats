#!/usr/bin/env bats

MAKEFILE="${BATS_TEST_DIRNAME}/../../../Makefile"

setup() {
  WORK="${BATS_TEST_TMPDIR}/work"
  CALL_LOG="${BATS_TEST_TMPDIR}/calls.log"
  mkdir -p "${WORK}/scripts/lib/foundation/scripts/lib/acg/bin"
  cp "${MAKEFILE}" "${WORK}/Makefile"
  : > "${CALL_LOG}"
  cat > "${WORK}/scripts/k3d-manager" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'ARGS:' >> "${CALL_LOG}"
printf ' <%s>' "$@" >> "${CALL_LOG}"
printf '\n' >> "${CALL_LOG}"
EOF
  cat > "${WORK}/scripts/lib/foundation/scripts/lib/acg/bin/acg-extend-test" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'PWD:%s\n' "$PWD" >> "${CALL_LOG}"
printf 'ARGS:' >> "${CALL_LOG}"
printf ' <%s>' "$@" >> "${CALL_LOG}"
printf '\n' >> "${CALL_LOG}"
EOF
  chmod +x "${WORK}/scripts/k3d-manager" \
    "${WORK}/scripts/lib/foundation/scripts/lib/acg/bin/acg-extend-test"
}

_run_make() {
  run env -u ACG_SANDBOX_LIST_URL CALL_LOG="${CALL_LOG}" \
    make --no-print-directory -C "${WORK}" "$@"
}

@test "acg-watch uses the default URL argument" {
  _run_make acg-watch
  [ "${status}" -eq 0 ]
  grep -Fx 'ARGS: <acg_watch_start> <>' "${CALL_LOG}"
}

@test "acg-watch passes an explicit URL" {
  _run_make acg-watch URL=https://example.test/sb
  [ "${status}" -eq 0 ]
  grep -Fx 'ARGS: <acg_watch_start> <https://example.test/sb>' "${CALL_LOG}"
}

@test "acg-watch-stop uninstalls the watcher" {
  _run_make acg-watch-stop
  [ "${status}" -eq 0 ]
  grep -Fx 'ARGS: <acg_watch_stop>' "${CALL_LOG}"
}

@test "acg-watch-check uses the default sandbox list page" {
  _run_make acg-watch-check
  [ "${status}" -eq 0 ]
  grep -Fx 'ARGS: <https://app.pluralsight.com/hands-on/playground/cloud-sandboxes> <--check>' "${CALL_LOG}"
  grep -Eq 'PWD:.*/scripts/lib/foundation/scripts/lib/acg$' "${CALL_LOG}"
}

@test "acg-watch-check uses the environment URL" {
  run env ACG_SANDBOX_LIST_URL=https://env.test/list CALL_LOG="${CALL_LOG}" \
    make --no-print-directory -C "${WORK}" acg-watch-check
  [ "${status}" -eq 0 ]
  grep -Fx 'ARGS: <https://env.test/list> <--check>' "${CALL_LOG}"
}

@test "acg-watch-check URL overrides the environment URL" {
  run env ACG_SANDBOX_LIST_URL=https://env.test/list CALL_LOG="${CALL_LOG}" \
    make --no-print-directory -C "${WORK}" acg-watch-check URL=https://example.test/sb
  [ "${status}" -eq 0 ]
  grep -Fx 'ARGS: <https://example.test/sb> <--check>' "${CALL_LOG}"
}

@test "watcher targets are phony and listed in help" {
  run grep -E '^\.PHONY:.*acg-watch([[:space:]]|$).*acg-watch-stop([[:space:]]|$).*acg-watch-check([[:space:]]|$)' "${WORK}/Makefile"
  [ "${status}" -eq 0 ]
  _run_make help
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"make acg-watch"* ]]
  [[ "${output}" == *"make acg-watch-stop"* ]]
  [[ "${output}" == *"make acg-watch-check"* ]]
}
