#!/usr/bin/env bats
# shellcheck shell=bash

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
  FAKE_BIN="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "${FAKE_BIN}"
  : >"${BATS_TEST_TMPDIR}/calls.log"
  cat >"${FAKE_BIN}/argocd" <<'STUB'
#!/usr/bin/env bash
printf 'argocd %s\n' "$*" >> "${BATS_TEST_TMPDIR}/calls.log"
if [[ "$1 $2" == "account get-user-info" ]]; then
  if [[ "${PROBE_ERROR:-0}" == 1 ]]; then exit 1; fi
  if [[ -n "${PROBE_OUTPUT:-}" ]]; then
    printf '%s\n' "${PROBE_OUTPUT}"
  else
    printf '%s\n' '{"loggedIn": false}'
  fi
  exit 0
fi
if [[ "$1 $2" == "app sync" ]]; then
  [[ -n "${ARGOCD_AUTH_TOKEN:-}" ]] && echo 'token-set' >> "${BATS_TEST_TMPDIR}/calls.log"
fi
exit 0
STUB
  cat >"${FAKE_BIN}/curl" <<'STUB'
#!/usr/bin/env bash
printf 'curl %s\n' "$*" >> "${BATS_TEST_TMPDIR}/calls.log"
for arg in "$@"; do
  if [[ "$arg" == */healthz ]]; then
    if [[ "${HEALTH_FAIL_FIRST:-0}" == 1 ]]; then
      count_file="${BATS_TEST_TMPDIR}/health.count"
      n=0
      [[ -f "${count_file}" ]] && n="$(cat "${count_file}")"
      echo $((n + 1)) >"${count_file}"
      if [[ "$n" -eq 0 ]]; then exit 1; fi
    fi
    exit 0
  fi
done
if [[ "$*" == */api/v1/session* ]]; then
  cat >/dev/null
  printf '%s\n' '{"token":"fake-token"}'
fi
exit 0
STUB
  cat >"${FAKE_BIN}/kubectl" <<'STUB'
#!/usr/bin/env bash
printf 'kubectl %s\n' "$*" >> "${BATS_TEST_TMPDIR}/calls.log"
if [[ "$*" == *"port-forward"* ]]; then
  echo "$$" > "${BATS_TEST_TMPDIR}/pf.pid"
  trap 'rm -f "${BATS_TEST_TMPDIR}/pf.pid"; exit 0' TERM INT
  while true; do sleep 1; done
fi
exit 1
STUB
  chmod +x "${FAKE_BIN}"/*
  export PATH="${FAKE_BIN}:${PATH}" TMPDIR="${BATS_TEST_TMPDIR}"
}

run_sync() {
  run env ARGOCD_ADMIN_PASSWORD=s3cr3t-fixture-pw \
    "${REPO_ROOT}/bin/argocd-app-sync" "$@"
}

@test "stale session mints a token and syncs" {
  run_sync demo
  [ "${status}" -eq 0 ]
  grep -q '/api/v1/session' "${BATS_TEST_TMPDIR}/calls.log"
  grep -q 'token-set' "${BATS_TEST_TMPDIR}/calls.log"
}

@test "probe error mints a token" {
  run env ARGOCD_ADMIN_PASSWORD=s3cr3t-fixture-pw PROBE_ERROR=1 \
    "${REPO_ROOT}/bin/argocd-app-sync" demo
  [ "${status}" -eq 0 ]
  grep -q '/api/v1/session' "${BATS_TEST_TMPDIR}/calls.log"
}

@test "valid session does not mint a token" {
  run env PROBE_OUTPUT='{"loggedIn": true}' "${REPO_ROOT}/bin/argocd-app-sync" demo
  [ "${status}" -eq 0 ]
  run grep -q '/api/v1/session' "${BATS_TEST_TMPDIR}/calls.log"
  [ "$status" -ne 0 ]
}

@test "force and timeout reach app sync" {
  run env PROBE_OUTPUT='{"loggedIn": true}' "${REPO_ROOT}/bin/argocd-app-sync" demo --force --timeout 180
  [ "${status}" -eq 0 ]
  grep -q 'app sync demo --force --timeout 180' "${BATS_TEST_TMPDIR}/calls.log"
}

@test "password and token are absent from output and argv logs" {
  run_sync demo
  [ "${status}" -eq 0 ]
  [[ "${output}" != *s3cr3t-fixture-pw* ]]
  [[ "${output}" != *fake-token* ]]
  run grep -qE 's3cr3t-fixture-pw|fake-token' "${BATS_TEST_TMPDIR}/calls.log"
  [ "$status" -ne 0 ]
}

@test "port-forward lifecycle cleans its process and temporary files" {
  run env ARGOCD_ADMIN_PASSWORD=s3cr3t-fixture-pw HEALTH_FAIL_FIRST=1 \
    "${REPO_ROOT}/bin/argocd-app-sync" demo
  [ "${status}" -eq 0 ]
  [ ! -e "${BATS_TEST_TMPDIR}/pf.pid" ]
  [ -z "$(find "${BATS_TEST_TMPDIR}" -maxdepth 1 -type f -name 'argocd-app-sync.*' -print -quit)" ]
}

@test "environment password takes precedence over kubectl secrets" {
  run_sync demo
  [ "${status}" -eq 0 ]
  run grep -q kubectl "${BATS_TEST_TMPDIR}/calls.log"
  [ "$status" -ne 0 ]
}

@test "missing app prints usage and makes no ArgoCD call" {
  run "${REPO_ROOT}/bin/argocd-app-sync"
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"Usage: bin/argocd-app-sync"* ]]
  run grep -q argocd "${BATS_TEST_TMPDIR}/calls.log"
  [ "$status" -ne 0 ]
}
