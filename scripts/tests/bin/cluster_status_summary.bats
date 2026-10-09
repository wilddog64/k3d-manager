#!/usr/bin/env bats

setup() {
  STATUS_SCRIPT="${BATS_TEST_DIRNAME}/../../../bin/cluster-status-summary"
  TMP_DIR="$(mktemp -d)"
  cat >"${TMP_DIR}/curl" <<'EOF'
#!/bin/sh
cat <<'JSON'
{"services":[{"name":"shopping-cart-order","ok":false,"detail":"HTTP 503; readiness 0/1"},{"name":"Pushgateway","ok":false,"detail":"connection refused"},{"name":"Grafana","ok":true,"detail":"HTTP 200"}]}
JSON
EOF
  chmod +x "${TMP_DIR}/curl"
  cat >"${TMP_DIR}/kubectl" <<'EOF'
#!/bin/sh
exit 1
EOF
  chmod +x "${TMP_DIR}/kubectl"
  export PATH="${TMP_DIR}:${PATH}" K3DM_WEBHOOK_TOKEN=test STATUS_COLOR=never K3DM_SNAPSHOT_STAMP="${TMP_DIR}/hub-snapshot-last"
}

teardown() { rm -rf "${TMP_DIR}"; }

stamp_hours_ago() {
  python3 - "$1" <<'PY'
import datetime, sys
print((datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(hours=int(sys.argv[1]))).strftime("%Y%m%dT%H%M%SZ"))
PY
}

@test "summary reports failed services before healthy checks" {
  run "${STATUS_SCRIPT}" --mode summary
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"shopping-cart-order: HTTP 503; readiness 0/1"* ]]
  [[ "${output}" == *"Grafana: HTTP 200"* ]]
  [[ "${output}" == *"Overall: FAIL"* ]]
  [[ "${output}" == *"Pushgateway: connection refused"* ]]
}

@test "focused service mode excludes unrelated services" {
  run "${STATUS_SCRIPT}" --mode summary --service shopping-cart-order
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"shopping-cart-order"* ]]
  [[ "${output}" != *"Grafana"* ]]
}

@test "json mode contains structured statuses and no ANSI" {
  run "${STATUS_SCRIPT}" --mode json
  [ "${status}" -eq 1 ]
  [[ "${output}" == *'"http_code"'* ]]
  [[ "${output}" != *$'\033['* ]]
  python3 -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["overall"] == "fail"; failed={e["service"] for e in d["errors"]}; assert failed == {"shopping-cart-order","Pushgateway"}, failed; assert d["counts"]["services_failed"] == len(failed), d["counts"]' "${output}"
}

@test "text status reports a fresh hub snapshot" {
  printf '%s\n' "$(stamp_hours_ago 2)" > "$K3DM_SNAPSHOT_STAMP"
  run "${STATUS_SCRIPT}" --mode summary
  [ "$status" -eq 1 ]
  [[ "$output" == *"✓ Hub snapshot"* ]]
}

@test "text status marks an old hub snapshot" {
  printf '%s\n' "$(stamp_hours_ago 192)" > "$K3DM_SNAPSHOT_STAMP"
  run "${STATUS_SCRIPT}" --mode summary
  [ "$status" -eq 1 ]
  [[ "$output" == *"! Hub snapshot"* ]]
}

@test "text status reports no recorded hub snapshot" {
  run "${STATUS_SCRIPT}" --mode summary
  [ "$status" -eq 1 ]
  [[ "$output" == *"none recorded"* ]]
}

@test "unknown service returns usage error" {
  run "${STATUS_SCRIPT}" --mode summary --service not-a-service
  [ "${status}" -eq 3 ]
  [[ "${output}" == *"unknown service"* ]]
}

@test "json mode follows the active provider when no provider is explicit" {
  mkdir -p "${TMP_DIR}/.local/share/k3d-manager"
  printf '%s\n' k3s-hostinger >"${TMP_DIR}/.local/share/k3d-manager/active-provider"
  HOME="${TMP_DIR}" run "${STATUS_SCRIPT}" --mode json
  [ "${status}" -eq 1 ]
  python3 -c 'import json,sys; assert json.loads(sys.argv[1])["provider"] == "k3s-hostinger"' "${output}"
}

@test "summary honours an explicit k3s-aws over the marker" {
  mkdir -p "${TMP_DIR}/.local/share/k3d-manager"
  printf '%s\n' k3s-hostinger >"${TMP_DIR}/.local/share/k3d-manager/active-provider"
  CLUSTER_PROVIDER=k3s-aws HOME="${TMP_DIR}" run "${STATUS_SCRIPT}" --mode json
  [ "${status}" -eq 1 ]
  python3 -c 'import json,sys; assert json.loads(sys.argv[1])["provider"] == "k3s-aws"' "${output}"
}

@test "summary skips a marker whose context is dead" {
  mkdir -p "${TMP_DIR}/.local/share/k3d-manager/active-providers"
  printf '%s\n' k3s-aws >"${TMP_DIR}/.local/share/k3d-manager/active-provider"
  : >"${TMP_DIR}/.local/share/k3d-manager/active-providers/k3s-aws"
  cat >"${TMP_DIR}/kubectl" <<'EOF'
#!/bin/sh
case " $* " in *" ubuntu-hostinger "*) exit 0;; *) exit 1;; esac
EOF
  chmod +x "${TMP_DIR}/kubectl"
  unset CLUSTER_PROVIDER
  HOME="${TMP_DIR}" run "${STATUS_SCRIPT}" --mode json
  [ "${status}" -eq 1 ]
  python3 -c 'import json,sys; assert json.loads(sys.argv[1])["provider"] == "k3s-hostinger"' "${output}"
}

@test "status recipe does not read the active-provider marker" {
  run sed -n '/^status:/,/^status-full:/p' Makefile
  [ "${status}" -eq 0 ]
  [[ "${output}" != *active-provider* ]]
}

@test "hostinger edge-down 530s suggest refresh-edge" {
  cat >"${TMP_DIR}/curl" <<'EOF'
#!/bin/sh
cat <<'JSON'
{"services":[{"name":"ArgoCD","ok":false,"detail":"HTTP 530"},{"name":"Frontend","ok":false,"detail":"HTTP 530"},{"name":"Grafana","ok":true,"detail":"HTTP 200"}]}
JSON
EOF
  chmod +x "${TMP_DIR}/curl"
  mkdir -p "${TMP_DIR}/.local/share/k3d-manager"
  printf '%s\n' k3s-hostinger >"${TMP_DIR}/.local/share/k3d-manager/active-provider"
  unset CLUSTER_PROVIDER
  HOME="${TMP_DIR}" run "${STATUS_SCRIPT}" --mode summary
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"Overall: FAIL"* ]]
  [[ "${output}" == *"make refresh-edge CLUSTER_PROVIDER=k3s-hostinger"* ]]
}

@test "single hostinger 530 does not suggest refresh-edge" {
  cat >"${TMP_DIR}/curl" <<'EOF'
#!/bin/sh
cat <<'JSON'
{"services":[{"name":"ArgoCD","ok":false,"detail":"HTTP 530"},{"name":"Frontend","ok":false,"detail":"HTTP 503"},{"name":"Grafana","ok":true,"detail":"HTTP 200"}]}
JSON
EOF
  chmod +x "${TMP_DIR}/curl"
  mkdir -p "${TMP_DIR}/.local/share/k3d-manager"
  printf '%s\n' k3s-hostinger >"${TMP_DIR}/.local/share/k3d-manager/active-provider"
  unset CLUSTER_PROVIDER
  HOME="${TMP_DIR}" run "${STATUS_SCRIPT}" --mode summary
  [ "${status}" -eq 1 ]
  [[ "${output}" != *"refresh-edge"* ]]
}

@test "non-hostinger provider does not suggest refresh-edge for multiple 530s" {
  cat >"${TMP_DIR}/curl" <<'EOF'
#!/bin/sh
cat <<'JSON'
{"services":[{"name":"ArgoCD","ok":false,"detail":"HTTP 530"},{"name":"Frontend","ok":false,"detail":"HTTP 530"},{"name":"Grafana","ok":true,"detail":"HTTP 200"}]}
JSON
EOF
  chmod +x "${TMP_DIR}/curl"
  CLUSTER_PROVIDER=k3d run "${STATUS_SCRIPT}" --mode summary
  [ "${status}" -eq 1 ]
  [[ "${output}" != *"refresh-edge"* ]]
}
