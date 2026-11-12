#!/usr/bin/env bats

setup() {
  ROOT="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
  REAL_PYTHON="$(command -v python3)"
  FIXHOME="${BATS_TEST_TMPDIR}/home"
  STUBS="${BATS_TEST_TMPDIR}/stubs"
  XDG_FIX="${BATS_TEST_TMPDIR}/data"
  VENV="${XDG_FIX}/k3d-manager/venv/bin"
  YAMLDIR="${BATS_TEST_TMPDIR}/yaml"
  mkdir -p "${FIXHOME}" "${STUBS}" "${VENV}" "${YAMLDIR}"
  export REAL_PYTHON FIXHOME STUBS XDG_FIX VENV YAMLDIR
  export PATH_YAML_DIR=""
  # The fixture YAML module parses only the synthetic generated configuration.
  cat > "${YAMLDIR}/yaml.py" <<'PYMODULE'
def safe_load(raw):
    assert b"synthetic@example.invalid" in raw
    return {"route": {"receiver": "test"}, "receivers": [{"name": "test", "email_configs": [{}]}]}
PYMODULE
  export CALLS="${BATS_TEST_TMPDIR}/calls"
  : > "${CALLS}"
  # Context and Alertmanager name from m5-air.local read-only capture, 2026-11-08.
  cat > "${STUBS}/kubectl" <<'STUB'
#!/bin/bash
case " $* " in
  *' config get-contexts '*) printf '%s\n' "${K3DM_HUB_CONTEXT:-k3d-k3d-cluster}" ;;
  *' get alertmanager '*) printf '%s\n' '{"items":[{"metadata":{"name":"kube-prometheus-stack-alertmanager"},"spec":{"configSecret":"alertmanager-smtp-secret"}}]}' ;;
  *' get secret alertmanager-smtp-secret '*) exit 0 ;;
  *' get secret alertmanager-kube-prometheus-stack-alertmanager-generated '*) cat "${FIXHOME}/generated.json" ;;
  *) exit 1 ;;
esac
STUB
  cat > "${STUBS}/python3" <<'STUB'
#!/bin/bash
printf 'path\n' >> "${CALLS}"
case "${PATH}" in "${VENV}:"*) : > "${BATS_TEST_TMPDIR}/unexpected-path" ;; esac
if [[ -n "${EXPECTED_PATH:-}" && "${PATH}" != "${EXPECTED_PATH}" ]]; then : > "${BATS_TEST_TMPDIR}/unexpected-path"; fi
export PYTHONPATH="${PATH_YAML_DIR:-}"
exec "${REAL_PYTHON}" -S "$@"
STUB
  cat > "${VENV}/python3" <<'STUB'
#!/bin/bash
printf 'venv\n' >> "${CALLS}"
export PYTHONPATH="${YAMLDIR}"
exec "${REAL_PYTHON}" -S "$@"
STUB
  chmod +x "${STUBS}/kubectl" "${STUBS}/python3" "${VENV}/python3"
  "${REAL_PYTHON}" - "${FIXHOME}/generated.json" <<'PY'
import base64, gzip, json, sys
payload = b'route:\n  receiver: test\nreceivers:\n  - name: test\n    email_configs:\n      - to: synthetic@example.invalid\n'
with open(sys.argv[1], 'w') as f:
    json.dump({'data': {'alertmanager.yaml.gz': base64.b64encode(gzip.compress(payload)).decode()}}, f)
PY
}

assert_path_python_has_no_yaml() {
  [[ "${FIXHOME}" == "${BATS_TEST_TMPDIR}/home" && "${FIXHOME}" != "${HOME}" ]]
  [[ "${STUBS}" == "${BATS_TEST_TMPDIR}/stubs" ]]
  run env HOME="${FIXHOME}" "${STUBS}/python3" -c "import yaml"
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"No module named 'yaml'"* ]]
  : > "${CALLS}"
}

run_probe() {
  [[ "${FIXHOME}" == "${BATS_TEST_TMPDIR}/home" && "${FIXHOME}" != "${HOME}" ]]
  [[ "${STUBS}" == "${BATS_TEST_TMPDIR}/stubs" ]]
  run env HOME="${FIXHOME}" XDG_DATA_HOME="${XDG_FIX}" PATH="${STUBS}:${PATH}" "${ROOT}/bin/k3dm-alert-delivery-status" --json
  [ "${status}" -eq 0 ] || { printf '%s\n' "${output}"; return 1; }
  [[ "${output}" == *'"available": true'* && "${output}" == *'"child_routes": 0'* ]]
}

@test "M1/N1: executable XDG venv handles every Python call" {
  assert_path_python_has_no_yaml
  run_probe
  [ "$(grep -c '^venv$' "${CALLS}")" -eq 8 ]
  [ "$(grep -c '^path$' "${CALLS}" || true)" -eq 0 ]
}

@test "M2: absent venv uses PATH Python" {
  rm "${VENV}/python3"
  export PATH_YAML_DIR="${YAMLDIR}"
  run_probe
  [ "$(grep -c '^path$' "${CALLS}")" -eq 8 ]
  [ "$(grep -c '^venv$' "${CALLS}" || true)" -eq 0 ]
}

@test "N2: non-executable venv leaves PATH unchanged and uses PATH Python" {
  chmod -x "${VENV}/python3"
  export PATH_YAML_DIR="${YAMLDIR}"
  run_probe
  [ "$(grep -c '^path$' "${CALLS}")" -eq 8 ]
  [ "$(grep -c '^venv$' "${CALLS}" || true)" -eq 0 ]
  # A PATH recording stub sees whether the unusable venv was prepended.
  [ ! -e "${BATS_TEST_TMPDIR}/unexpected-path" ]
}

@test "M3: unset XDG uses the HOME venv" {
  assert_path_python_has_no_yaml
  mkdir -p "${FIXHOME}/.local/share/k3d-manager/venv/bin"
  cp "${VENV}/python3" "${FIXHOME}/.local/share/k3d-manager/venv/bin/python3"
  [[ "${FIXHOME}" == "${BATS_TEST_TMPDIR}/home" && "${FIXHOME}" != "${HOME}" ]]
  run env -u XDG_DATA_HOME HOME="${FIXHOME}" PATH="${STUBS}:${PATH}" "${ROOT}/bin/k3dm-alert-delivery-status" --json
  [ "${status}" -eq 0 ] || { printf '%s\n' "${output}"; return 1; }
  [[ "${output}" == *'"available": true'* && "${output}" == *'"child_routes": 0'* ]]
  [ "$(grep -c '^venv$' "${CALLS}")" -eq 8 ]
  [ "$(grep -c '^path$' "${CALLS}" || true)" -eq 0 ]
}

@test "unset HOME and XDG leaves PATH unchanged" {
  [[ "${FIXHOME}" == "${BATS_TEST_TMPDIR}/home" && "${FIXHOME}" != "${HOME}" ]]
  [[ "${STUBS}" == "${BATS_TEST_TMPDIR}/stubs" ]]
  export EXPECTED_PATH="${STUBS}:${PATH}" PATH_YAML_DIR="${YAMLDIR}"
  run env -u HOME -u XDG_DATA_HOME PATH="${EXPECTED_PATH}" "${ROOT}/bin/k3dm-alert-delivery-status" --json
  [ "${status}" -eq 0 ] || { printf '%s\n' "${output}"; return 1; }
  [[ "${output}" == *'"available": true'* && "${output}" == *'"child_routes": 0'* ]]
  [ "$(grep -c '^path$' "${CALLS}")" -eq 8 ]
  [ ! -e "${BATS_TEST_TMPDIR}/unexpected-path" ]
}
