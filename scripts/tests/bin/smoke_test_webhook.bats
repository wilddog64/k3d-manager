#!/usr/bin/env bats

setup() {
  SMOKE_SCRIPT="${BATS_TEST_DIRNAME}/../../../bin/smoke-test-webhook"
  CURL_CALL_LOG="${BATS_TEST_TMPDIR}/curl-calls"
  REAL_PYTHON3="$(command -v python3)"

  cat >"${BATS_TEST_TMPDIR}/python3" <<EOF
#!/usr/bin/env bash
for _a in "\$@"; do
  case "\${_a}" in
    *k3dm-webhook*) exec /bin/sleep 30 ;;
  esac
done
exec "${REAL_PYTHON3}" "\$@"
EOF

  cat >"${BATS_TEST_TMPDIR}/curl" <<'EOF'
#!/usr/bin/env bash
printf '%s ' "$@" >>"${CURL_CALL_LOG}"
printf '\n' >>"${CURL_CALL_LOG}"

_out=""
_authed=0
_prev=""
for _a in "$@"; do
  [[ "${_prev}" == "-o" ]] && _out="${_a}"
  [[ "${_a}" == Authorization:* ]] && _authed=1
  _prev="${_a}"
done

if (( _authed == 0 )); then
  exit 0
fi

if [[ "${CURL_STUB_MODE:-ok}" == "timeout" ]]; then
  exit 28
fi

cat >"${_out}" <<'JSON'
{"services": [{"name": "Prometheus", "ok": true, "detail": "HTTP 200"}]}
JSON
printf '200'
EOF

  chmod +x "${BATS_TEST_TMPDIR}/python3" "${BATS_TEST_TMPDIR}/curl"
  export PATH="${BATS_TEST_TMPDIR}:${PATH}"
  export CURL_CALL_LOG
  unset CLUSTER_PROVIDER CURL_STUB_MODE
}

@test "the gate requests the bounded quick health variant" {
  run "${SMOKE_SCRIPT}"

  [ "${status}" -eq 0 ]
  run grep -F -- 'quick=1' "${CURL_CALL_LOG}"
  [ "${status}" -eq 0 ]
}

@test "the provider is appended to the quick variant rather than replacing it" {
  export CLUSTER_PROVIDER=k3s-hostinger

  run "${SMOKE_SCRIPT}"

  [ "${status}" -eq 0 ]
  run grep -F -- 'quick=1&provider=k3s-hostinger' "${CURL_CALL_LOG}"
  [ "${status}" -eq 0 ]
}

@test "the unbounded full-sweep health path is never requested" {
  run "${SMOKE_SCRIPT}"

  [ "${status}" -eq 0 ]
  run grep -E -- 'health( |$)' "${CURL_CALL_LOG}"
  [ "${status}" -ne 0 ]
}

@test "a curl timeout reports its exit code instead of a doubled 000000" {
  export CURL_STUB_MODE=timeout

  run "${SMOKE_SCRIPT}"

  [ "${status}" -eq 1 ]
  [[ "${output}" == *"curl exit 28"* ]]
  [[ "${output}" != *"000000"* ]]
}
