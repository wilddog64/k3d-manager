#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  export TEST_BIN_DIR="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "${TEST_BIN_DIR}" "${BATS_TEST_TMPDIR}/scripts"
  export PATH="${TEST_BIN_DIR}:$PATH"

  export TRIVY_LOG="${BATS_TEST_TMPDIR}/trivy.log"
  export CURL_LOG="${BATS_TEST_TMPDIR}/curl.log"
  export NOTIFY_LOG="${BATS_TEST_TMPDIR}/notify.log"
  export KUBECTL_LOG="${BATS_TEST_TMPDIR}/kubectl.log"
  : >"${TRIVY_LOG}"
  : >"${CURL_LOG}"
  : >"${NOTIFY_LOG}"
  : >"${KUBECTL_LOG}"

  cat >"${TEST_BIN_DIR}/trivy" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"${TRIVY_LOG}"
_last=""
for _arg in "$@"; do
  _last="${_arg}"
done
case "${_last}" in
  *shopping-cart-basket:sha-*)
    _count="${TEST_LATEST_CVES_shopping_cart_basket:-0}"
    ;;
  *shopping-cart-order:sha-*)
    _count="${TEST_LATEST_CVES_shopping_cart_order:-0}"
    ;;
  *shopping-cart-product-catalog:sha-*)
    _count="${TEST_LATEST_CVES_shopping_cart_product_catalog:-0}"
    ;;
  *)
    _count=0
    ;;
esac
_i=0
while [ "${_i}" -lt "${_count}" ]; do
  printf 'HIGH\n'
  _i=$((_i + 1))
done
EOF
  chmod +x "${TEST_BIN_DIR}/trivy"

  cat >"${TEST_BIN_DIR}/curl" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"${CURL_LOG}"
_last=""
for _arg in "$@"; do
  _last="${_arg}"
done
case "${_last}" in
  https://ghcr.io/token*)
    printf '{"token":"registry-token"}'
    exit 0
    ;;
  https://ghcr.io/v2/*/tags/list)
    printf '{"name":"repo","tags":["latest","%s","sha-old"]}\n' "${TEST_SHA_TAG:-sha-new}"
    exit 0
    ;;
  https://ghcr.io/v2/*/manifests/latest)
    printf 'HTTP/1.1 200 OK\r\nDocker-Content-Digest: %s\r\n' "${TEST_LATEST_DIGEST:-sha256:testdigest}"
    exit 0
    ;;
  https://ghcr.io/v2/*/manifests/sha-*)
    case "${_last}" in
      *"${TEST_SHA_TAG:-sha-new}")
        printf 'HTTP/1.1 200 OK\r\nDocker-Content-Digest: %s\r\n' "${TEST_LATEST_DIGEST:-sha256:testdigest}"
        ;;
      *)
        printf 'HTTP/1.1 200 OK\r\nDocker-Content-Digest: sha256:olderdigest\r\n'
        ;;
    esac
    exit 0
    ;;
  *actions/workflows/*/dispatches)
    exit 0
    ;;
esac
exit 0
EOF
  chmod +x "${TEST_BIN_DIR}/curl"

  cat >"${TEST_BIN_DIR}/kubectl" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"${KUBECTL_LOG}"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --server|--token|--certificate-authority)
      shift 2
      ;;
    --insecure-skip-tls-verify=true)
      shift
      ;;
    *)
      break
      ;;
  esac
done

case "$*" in
  "-n cicd get secret cluster-ubuntu-hostinger -o jsonpath={.data.server}")
    printf '%s' "${TEST_SECRET_SERVER_B64}"
    exit 0
    ;;
  "-n cicd get secret cluster-ubuntu-hostinger -o jsonpath={.data.config}")
    printf '%s' "${TEST_SECRET_CONFIG_B64}"
    exit 0
    ;;
  "get vulnerabilityreports.aquasecurity.github.io -A --no-headers -o custom-columns=NS:.metadata.namespace,NAME:.metadata.name,REPO:.report.artifact.repository,TAG:.report.artifact.tag,CRITICAL:.report.summary.criticalCount,HIGH:.report.summary.highCount")
    printf '%s\n' "${TEST_REPORT_ROWS:-}"
    exit 0
    ;;
  "-n shopping-cart-apps get vulnerabilityreport.aquasecurity.github.io basket-report -o go-template={{range .report.vulnerabilities}}{{if or (eq .severity \"CRITICAL\") (eq .severity \"HIGH\")}}{{.severity}}|{{.vulnerabilityID}}|{{.fixedVersion}}{{\"\\n\"}}{{end}}{{end}}")
    printf '%s' "${TEST_REPORT_DETAILS_basket_report:-}"
    exit 0
    ;;
  "-n shopping-cart-apps get vulnerabilityreport.aquasecurity.github.io order-report -o go-template={{range .report.vulnerabilities}}{{if or (eq .severity \"CRITICAL\") (eq .severity \"HIGH\")}}{{.severity}}|{{.vulnerabilityID}}|{{.fixedVersion}}{{\"\\n\"}}{{end}}{{end}}")
    printf '%s' "${TEST_REPORT_DETAILS_order_report:-}"
    exit 0
    ;;
  "-n shopping-cart-apps get vulnerabilityreport.aquasecurity.github.io product-catalog-report -o go-template={{range .report.vulnerabilities}}{{if or (eq .severity \"CRITICAL\") (eq .severity \"HIGH\")}}{{.severity}}|{{.vulnerabilityID}}|{{.fixedVersion}}{{\"\\n\"}}{{end}}{{end}}")
    printf '%s' "${TEST_REPORT_DETAILS_product_catalog_report:-}"
    exit 0
    ;;
  -n\ cicd\ patch\ application\ *\ --type\ merge\ -p\ *)
    exit 0
    ;;
  -n\ cicd\ annotate\ application\ *\ argocd.argoproj.io/refresh=hard\ --overwrite)
    exit 0
    ;;
esac

exit 1
EOF
  chmod +x "${TEST_BIN_DIR}/kubectl"

  cat >"${BATS_TEST_TMPDIR}/scripts/notify.sh" <<'EOF'
#!/bin/sh
printf '%s|%s|%s\n' "$1" "$2" "$3" >>"${NOTIFY_LOG}"
EOF
  chmod +x "${BATS_TEST_TMPDIR}/scripts/notify.sh"

  export TEST_SECRET_SERVER_B64
  TEST_SECRET_SERVER_B64="$(printf '%s' 'https://2.25.146.252:6443' | base64)"
  export TEST_SECRET_CONFIG_B64
  TEST_SECRET_CONFIG_B64="$(printf '%s' '{"bearerToken":"remote-token","tlsClientConfig":{"insecure":true}}' | base64)"

  export SCAN_SCRIPT="${BATS_TEST_DIRNAME}/../../etc/argocd/platform-ops/app-cve-scan.sh"
  export TEST_SCAN_SCRIPT="${BATS_TEST_TMPDIR}/app-cve-scan.sh"
  sed "s|/scripts/notify.sh|${BATS_TEST_TMPDIR}/scripts/notify.sh|g" "${SCAN_SCRIPT}" >"${TEST_SCAN_SCRIPT}"
  chmod +x "${TEST_SCAN_SCRIPT}"
}

@test "no vulnerability report skips service and exits 0" {
  export APP_SERVICES="shopping-cart-basket"
  export TEST_REPORT_ROWS=""

  run env -i \
    PATH="${PATH}" \
    TRIVY_LOG="${TRIVY_LOG}" \
    CURL_LOG="${CURL_LOG}" \
    NOTIFY_LOG="${NOTIFY_LOG}" \
    KUBECTL_LOG="${KUBECTL_LOG}" \
    TEST_SECRET_SERVER_B64="${TEST_SECRET_SERVER_B64}" \
    TEST_SECRET_CONFIG_B64="${TEST_SECRET_CONFIG_B64}" \
    APP_SERVICES="${APP_SERVICES}" \
    /bin/sh "${TEST_SCAN_SCRIPT}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"no VulnerabilityReport found"* ]]
  [ ! -s "${CURL_LOG}" ]
}

@test "vulnerable deployed image with vulnerable latest dispatches rebuild instead of promotion" {
  export APP_SERVICES="shopping-cart-order"
  export GH_TOKEN="test-token"
  export TEST_SHA_TAG="sha-order-new"
  export TEST_LATEST_DIGEST="sha256:deadbeef"
  export TEST_REPORT_ROWS="shopping-cart-apps order-report ghcr.io/wilddog64/shopping-cart-order sha-old 1 1"
  export TEST_REPORT_DETAILS_order_report="CRITICAL|CVE-1|2.0.0"
  export TEST_LATEST_CVES_shopping_cart_order=2

  run env -i \
    PATH="${PATH}" \
    TRIVY_LOG="${TRIVY_LOG}" \
    CURL_LOG="${CURL_LOG}" \
    NOTIFY_LOG="${NOTIFY_LOG}" \
    KUBECTL_LOG="${KUBECTL_LOG}" \
    TEST_SECRET_SERVER_B64="${TEST_SECRET_SERVER_B64}" \
    TEST_SECRET_CONFIG_B64="${TEST_SECRET_CONFIG_B64}" \
    APP_SERVICES="${APP_SERVICES}" \
    GH_TOKEN="${GH_TOKEN}" \
    TEST_SHA_TAG="${TEST_SHA_TAG}" \
    TEST_LATEST_DIGEST="${TEST_LATEST_DIGEST}" \
    TEST_REPORT_ROWS="${TEST_REPORT_ROWS}" \
    TEST_REPORT_DETAILS_order_report="${TEST_REPORT_DETAILS_order_report}" \
    TEST_LATEST_CVES_shopping_cart_order="${TEST_LATEST_CVES_shopping_cart_order}" \
    /bin/sh "${TEST_SCAN_SCRIPT}"

  [ "${status}" -eq 0 ]
  grep -q 'shopping-cart-order/actions/workflows/ci.yml/dispatches' "${CURL_LOG}"
  run ! grep -q 'patch application shopping-cart-order' "${KUBECTL_LOG}"
  grep -q 'warning|App CVE: shopping-cart-order|' "${NOTIFY_LOG}"
}

@test "vulnerable deployed image with clean latest promotes exact digest via application patch" {
  export APP_SERVICES="shopping-cart-basket"
  export TEST_SHA_TAG="sha-basket-new"
  export TEST_REPORT_ROWS="shopping-cart-apps basket-report ghcr.io/wilddog64/shopping-cart-basket sha-old 1 0"
  export TEST_REPORT_DETAILS_basket_report="HIGH|CVE-2|1.4.0"
  export TEST_LATEST_CVES_shopping_cart_basket=0
  export TEST_LATEST_DIGEST="sha256:feedbeef"

  run env -i \
    PATH="${PATH}" \
    TRIVY_LOG="${TRIVY_LOG}" \
    CURL_LOG="${CURL_LOG}" \
    NOTIFY_LOG="${NOTIFY_LOG}" \
    KUBECTL_LOG="${KUBECTL_LOG}" \
    TEST_SECRET_SERVER_B64="${TEST_SECRET_SERVER_B64}" \
    TEST_SECRET_CONFIG_B64="${TEST_SECRET_CONFIG_B64}" \
    APP_SERVICES="${APP_SERVICES}" \
    TEST_SHA_TAG="${TEST_SHA_TAG}" \
    TEST_REPORT_ROWS="${TEST_REPORT_ROWS}" \
    TEST_REPORT_DETAILS_basket_report="${TEST_REPORT_DETAILS_basket_report}" \
    TEST_LATEST_CVES_shopping_cart_basket="${TEST_LATEST_CVES_shopping_cart_basket}" \
    TEST_LATEST_DIGEST="${TEST_LATEST_DIGEST}" \
    /bin/sh "${TEST_SCAN_SCRIPT}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"PROMOTION shopping-cart-basket: from ghcr.io/wilddog64/shopping-cart-basket:sha-old to ghcr.io/wilddog64/shopping-cart-basket:sha-basket-new@sha256:feedbeef"* ]]
  grep -q 'patch application shopping-cart-basket' "${KUBECTL_LOG}"
  grep -q 'annotate application shopping-cart-basket argocd.argoproj.io/refresh=hard --overwrite' "${KUBECTL_LOG}"
  grep -q 'warning|App CVE Promotion: shopping-cart-basket|' "${NOTIFY_LOG}"
}

@test "rebuild path without GH token returns non-zero" {
  export APP_SERVICES="shopping-cart-order"
  export TEST_SHA_TAG="sha-order-new"
  export TEST_LATEST_DIGEST="sha256:deadbeef"
  export TEST_REPORT_ROWS="shopping-cart-apps order-report ghcr.io/wilddog64/shopping-cart-order sha-old 0 2"
  export TEST_REPORT_DETAILS_order_report="HIGH|CVE-3|3.1.4"
  export TEST_LATEST_CVES_shopping_cart_order=1

  run env -i \
    PATH="${PATH}" \
    TRIVY_LOG="${TRIVY_LOG}" \
    CURL_LOG="${CURL_LOG}" \
    NOTIFY_LOG="${NOTIFY_LOG}" \
    KUBECTL_LOG="${KUBECTL_LOG}" \
    TEST_SECRET_SERVER_B64="${TEST_SECRET_SERVER_B64}" \
    TEST_SECRET_CONFIG_B64="${TEST_SECRET_CONFIG_B64}" \
    APP_SERVICES="${APP_SERVICES}" \
    TEST_SHA_TAG="${TEST_SHA_TAG}" \
    TEST_LATEST_DIGEST="${TEST_LATEST_DIGEST}" \
    TEST_REPORT_ROWS="${TEST_REPORT_ROWS}" \
    TEST_REPORT_DETAILS_order_report="${TEST_REPORT_DETAILS_order_report}" \
    TEST_LATEST_CVES_shopping_cart_order="${TEST_LATEST_CVES_shopping_cart_order}" \
    /bin/sh "${TEST_SCAN_SCRIPT}"

  [ "${status}" -eq 1 ]
  run ! grep -q 'patch application shopping-cart-order' "${KUBECTL_LOG}"
}

@test "missing immutable sha candidate skips promotion instead of falling back to latest" {
  export APP_SERVICES="shopping-cart-product-catalog"
  export TEST_SHA_TAG="sha-catalog-new"
  export TEST_LATEST_DIGEST="sha256:feedbeef"
  export TEST_REPORT_ROWS="shopping-cart-apps product-catalog-report ghcr.io/wilddog64/shopping-cart-product-catalog sha-old 0 1"
  export TEST_REPORT_DETAILS_product_catalog_report="HIGH|CVE-4|9.9.9"

  cat >"${TEST_BIN_DIR}/curl" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"${CURL_LOG}"
_last=""
for _arg in "$@"; do
  _last="${_arg}"
done
case "${_last}" in
  https://ghcr.io/token*)
    printf '{"token":"registry-token"}'
    exit 0
    ;;
  https://ghcr.io/v2/*/tags/list)
    printf '{"name":"repo","tags":["latest","sha-other"]}\n'
    exit 0
    ;;
  https://ghcr.io/v2/*/manifests/latest)
    printf 'HTTP/1.1 200 OK\r\nDocker-Content-Digest: sha256:feedbeef\r\n'
    exit 0
    ;;
  https://ghcr.io/v2/*/manifests/sha-*)
    printf 'HTTP/1.1 200 OK\r\nDocker-Content-Digest: sha256:olderdigest\r\n'
    exit 0
    ;;
esac
exit 0
EOF
  chmod +x "${TEST_BIN_DIR}/curl"

  run env -i \
    PATH="${PATH}" \
    TRIVY_LOG="${TRIVY_LOG}" \
    CURL_LOG="${CURL_LOG}" \
    NOTIFY_LOG="${NOTIFY_LOG}" \
    KUBECTL_LOG="${KUBECTL_LOG}" \
    TEST_SECRET_SERVER_B64="${TEST_SECRET_SERVER_B64}" \
    TEST_SECRET_CONFIG_B64="${TEST_SECRET_CONFIG_B64}" \
    APP_SERVICES="${APP_SERVICES}" \
    TEST_REPORT_ROWS="${TEST_REPORT_ROWS}" \
    TEST_REPORT_DETAILS_product_catalog_report="${TEST_REPORT_DETAILS_product_catalog_report}" \
    /bin/sh "${TEST_SCAN_SCRIPT}"

  [ "${status}" -eq 1 ]
  [[ "${output}" == *"failed to resolve immutable sha-* candidate"* ]]
  run ! grep -q 'patch application shopping-cart-product-catalog' "${KUBECTL_LOG}"
}
