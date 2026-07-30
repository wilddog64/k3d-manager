#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  export TEST_BIN_DIR="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "${TEST_BIN_DIR}" "${BATS_TEST_TMPDIR}/scripts"
  export PATH="${TEST_BIN_DIR}:$PATH"

  export TRIVY_LOG="${BATS_TEST_TMPDIR}/trivy.log"
  export WGET_LOG="${BATS_TEST_TMPDIR}/wget.log"
  export NOTIFY_LOG="${BATS_TEST_TMPDIR}/notify.log"
  export KUBECTL_LOG="${BATS_TEST_TMPDIR}/kubectl.log"
  : >"${TRIVY_LOG}"
  : >"${WGET_LOG}"
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
  *shopping-cart-frontend:sha-*)
    _count="${TEST_LATEST_CVES_shopping_cart_frontend:-0}"
    ;;
  *shopping-cart-order:sha-*)
    _count="${TEST_LATEST_CVES_shopping_cart_order:-0}"
    ;;
  *shopping-cart-payment:sha-*)
    _count="${TEST_LATEST_CVES_shopping_cart_payment:-0}"
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

  cat >"${TEST_BIN_DIR}/wget" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"${WGET_LOG}"

_out_mode=""
_out_file=""
_post_data=""
_spider="false"
_url=""
_auth_header=""
_accept_header=""
_content_type_header=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    -qO)
      _out_mode="file"
      shift
      _out_file="$1"
      ;;
    -qO-)
      _out_mode="stdout"
      ;;
    -S)
      ;;
    --spider)
      _spider="true"
      ;;
    --post-data=*)
      _post_data="${1#--post-data=}"
      ;;
    --header=Authorization:*)
      _auth_header="${1#--header=}"
      ;;
    --config=*)
      _wgetrc_file="${1#--config=}"
      if [ -f "${_wgetrc_file}" ]; then
        _auth_header="$(sed -n 's/^header = //p' "${_wgetrc_file}")"
      fi
      ;;
    --header=Accept:*)
      _accept_header="${1#--header=}"
      ;;
    --header=Content-Type:*)
      _content_type_header="${1#--header=}"
      ;;
    http*)
      _url="$1"
      ;;
  esac
  shift
done

case "${_url}" in
  https://ghcr.io/token*)
    [ "${_out_mode}" = "file" ] || exit 1
    printf '{"token":"registry-token"}' >"${_out_file}"
    exit 0
    ;;
  https://ghcr.io/v2/*/tags/list)
    [ "${_out_mode}" = "file" ] || exit 1
    if [ "${TEST_NO_CANDIDATE:-0}" = "1" ]; then
      printf '{"name":"repo","tags":["latest"]}\n' >"${_out_file}"
      exit 0
    fi
    printf '{"name":"repo","tags":["latest","%s","sha-old"]}\n' "${TEST_SHA_TAG:-sha-new}" >"${_out_file}"
    exit 0
    ;;
  https://ghcr.io/v2/*/manifests/latest|https://ghcr.io/v2/*/manifests/sha-*)
    [ "${_spider}" = "true" ] || exit 1
    case "${_url}" in
      *"/manifests/latest")
        _digest="${TEST_LATEST_DIGEST:-sha256:testdigest}"
        ;;
      *"/manifests/${TEST_SHA_TAG:-sha-new}")
        _digest="${TEST_LATEST_DIGEST:-sha256:testdigest}"
        ;;
      *)
        _digest="sha256:olderdigest"
        ;;
    esac
    printf '  docker-content-digest: %s\r\n' "${_digest}" >&2
    printf '  HTTP/1.1 200 OK\r\n' >&2
    exit 0
    ;;
  *actions/workflows/*/dispatches)
    [ "${_out_mode}" = "stdout" ] || exit 1
    [ "${_post_data}" = '{"ref":"main"}' ] || exit 1
    [ "${_accept_header}" = 'Accept: application/vnd.github+json' ] || exit 1
    [ "${_content_type_header}" = 'Content-Type: application/json' ] || exit 1
    [ "${_auth_header}" = "Authorization: Bearer ${GH_TOKEN}" ] || exit 1
    exit 0
    ;;
esac

exit 1
EOF
  chmod +x "${TEST_BIN_DIR}/wget"

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
  "-n shopping-cart-apps get vulnerabilityreport.aquasecurity.github.io frontend-report -o go-template={{range .report.vulnerabilities}}{{if or (eq .severity \"CRITICAL\") (eq .severity \"HIGH\")}}{{.severity}}|{{.vulnerabilityID}}|{{.fixedVersion}}{{\"\\n\"}}{{end}}{{end}}")
    printf '%s' "${TEST_REPORT_DETAILS_frontend_report:-}"
    exit 0
    ;;
  "-n shopping-cart-apps get vulnerabilityreport.aquasecurity.github.io order-report -o go-template={{range .report.vulnerabilities}}{{if or (eq .severity \"CRITICAL\") (eq .severity \"HIGH\")}}{{.severity}}|{{.vulnerabilityID}}|{{.fixedVersion}}{{\"\\n\"}}{{end}}{{end}}")
    printf '%s' "${TEST_REPORT_DETAILS_order_report:-}"
    exit 0
    ;;
  "-n shopping-cart-apps get vulnerabilityreport.aquasecurity.github.io payment-report -o go-template={{range .report.vulnerabilities}}{{if or (eq .severity \"CRITICAL\") (eq .severity \"HIGH\")}}{{.severity}}|{{.vulnerabilityID}}|{{.fixedVersion}}{{\"\\n\"}}{{end}}{{end}}")
    printf '%s' "${TEST_REPORT_DETAILS_payment_report:-}"
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

@test "all-skipped run exits 1 with the fatal zero-match diagnostic" {
  export APP_SERVICES="shopping-cart-basket"
  export TEST_REPORT_ROWS=""

  run env -i \
    PATH="${PATH}" \
    TRIVY_LOG="${TRIVY_LOG}" \
    WGET_LOG="${WGET_LOG}" \
    NOTIFY_LOG="${NOTIFY_LOG}" \
    KUBECTL_LOG="${KUBECTL_LOG}" \
    TEST_SECRET_SERVER_B64="${TEST_SECRET_SERVER_B64}" \
    TEST_SECRET_CONFIG_B64="${TEST_SECRET_CONFIG_B64}" \
    APP_SERVICES="${APP_SERVICES}" \
    /bin/sh "${TEST_SCAN_SCRIPT}"

  [ "${status}" -eq 1 ]
  [[ "${output}" == *"no VulnerabilityReport found for ghcr.io/wilddog64/shopping-cart-basket"* ]]
  [[ "${output}" == *"ZERO VulnerabilityReports matched"* ]]
  [ ! -s "${WGET_LOG}" ]
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
    WGET_LOG="${WGET_LOG}" \
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
  grep -q 'shopping-cart-order/actions/workflows/ci.yml/dispatches' "${WGET_LOG}"
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
    WGET_LOG="${WGET_LOG}" \
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

@test "registry-less trivy-operator repository form still matches and promotes" {
  export APP_SERVICES="shopping-cart-basket"
  export TEST_SHA_TAG="sha-basket-new"
  export TEST_REPORT_ROWS="shopping-cart-apps basket-report wilddog64/shopping-cart-basket sha-old 1 0"
  export TEST_REPORT_DETAILS_basket_report="HIGH|CVE-2|1.4.0"
  export TEST_LATEST_CVES_shopping_cart_basket=0
  export TEST_LATEST_DIGEST="sha256:feedbeef"

  run env -i \
    PATH="${PATH}" \
    TRIVY_LOG="${TRIVY_LOG}" \
    WGET_LOG="${WGET_LOG}" \
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
}

@test "digest resolution reads busybox-style indented lowercase headers" {
  export APP_SERVICES="shopping-cart-basket"
  export TEST_LATEST_DIGEST="sha256:feedbeef"

  run env -i \
    PATH="${PATH}" \
    WGET_LOG="${WGET_LOG}" \
    TEST_LATEST_DIGEST="${TEST_LATEST_DIGEST}" \
    /bin/sh -c 'tmp="$(mktemp)"; awk '"'"'/^# === MAIN ===/ { exit } { print }'"'"' "$1" >"$tmp"; . "$tmp"; rm -f "$tmp"; _resolve_tag_digest ghcr.io/wilddog64/shopping-cart-basket latest' _ "${TEST_SCAN_SCRIPT}"

  [ "${status}" -eq 0 ]
  [ "${output}" = "${TEST_LATEST_DIGEST}" ]
}

@test "clean frontend image is scanned and skipped" {
  export APP_SERVICES="shopping-cart-frontend"
  export TEST_REPORT_ROWS="shopping-cart-apps frontend-report ghcr.io/wilddog64/shopping-cart-frontend sha-old 0 0"
  export TEST_REPORT_DETAILS_frontend_report=""
  export TEST_LATEST_CVES_shopping_cart_frontend=0

  run env -i \
    PATH="${PATH}" \
    TRIVY_LOG="${TRIVY_LOG}" \
    WGET_LOG="${WGET_LOG}" \
    NOTIFY_LOG="${NOTIFY_LOG}" \
    KUBECTL_LOG="${KUBECTL_LOG}" \
    TEST_SECRET_SERVER_B64="${TEST_SECRET_SERVER_B64}" \
    TEST_SECRET_CONFIG_B64="${TEST_SECRET_CONFIG_B64}" \
    APP_SERVICES="${APP_SERVICES}" \
    TEST_REPORT_ROWS="${TEST_REPORT_ROWS}" \
    TEST_REPORT_DETAILS_frontend_report="${TEST_REPORT_DETAILS_frontend_report}" \
    TEST_LATEST_CVES_shopping_cart_frontend="${TEST_LATEST_CVES_shopping_cart_frontend}" \
  /bin/sh "${TEST_SCAN_SCRIPT}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"deployed image ghcr.io/wilddog64/shopping-cart-frontend:sha-old has no HIGH/CRITICAL findings"* ]]
  run ! grep -q 'actions/workflows' "${WGET_LOG}"
}

@test "clean payment image is scanned and skipped" {
  export APP_SERVICES="shopping-cart-payment"
  export TEST_REPORT_ROWS="shopping-cart-apps payment-report ghcr.io/wilddog64/shopping-cart-payment sha-old 0 0"
  export TEST_REPORT_DETAILS_payment_report=""
  export TEST_LATEST_CVES_shopping_cart_payment=0

  run env -i \
    PATH="${PATH}" \
    TRIVY_LOG="${TRIVY_LOG}" \
    WGET_LOG="${WGET_LOG}" \
    NOTIFY_LOG="${NOTIFY_LOG}" \
    KUBECTL_LOG="${KUBECTL_LOG}" \
    TEST_SECRET_SERVER_B64="${TEST_SECRET_SERVER_B64}" \
    TEST_SECRET_CONFIG_B64="${TEST_SECRET_CONFIG_B64}" \
    APP_SERVICES="${APP_SERVICES}" \
    TEST_REPORT_ROWS="${TEST_REPORT_ROWS}" \
    TEST_REPORT_DETAILS_payment_report="${TEST_REPORT_DETAILS_payment_report}" \
    TEST_LATEST_CVES_shopping_cart_payment="${TEST_LATEST_CVES_shopping_cart_payment}" \
  /bin/sh "${TEST_SCAN_SCRIPT}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"deployed image ghcr.io/wilddog64/shopping-cart-payment:sha-old has no HIGH/CRITICAL findings"* ]]
  run ! grep -q 'actions/workflows' "${WGET_LOG}"
}

@test "missing immutable candidate notifies without failing the batch" {
  export APP_SERVICES="shopping-cart-payment"
  export TEST_NO_CANDIDATE=1
  export TEST_REPORT_ROWS="shopping-cart-apps payment-report ghcr.io/wilddog64/shopping-cart-payment sha-old 1 0"
  export TEST_REPORT_DETAILS_payment_report="CRITICAL|CVE-1|2.0.0"

  run env -i \
    PATH="${PATH}" \
    TRIVY_LOG="${TRIVY_LOG}" \
    WGET_LOG="${WGET_LOG}" \
    NOTIFY_LOG="${NOTIFY_LOG}" \
    KUBECTL_LOG="${KUBECTL_LOG}" \
    TEST_SECRET_SERVER_B64="${TEST_SECRET_SERVER_B64}" \
    TEST_SECRET_CONFIG_B64="${TEST_SECRET_CONFIG_B64}" \
    APP_SERVICES="${APP_SERVICES}" \
    TEST_NO_CANDIDATE="${TEST_NO_CANDIDATE}" \
    TEST_REPORT_ROWS="${TEST_REPORT_ROWS}" \
    TEST_REPORT_DETAILS_payment_report="${TEST_REPORT_DETAILS_payment_report}" \
    /bin/sh "${TEST_SCAN_SCRIPT}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"failed to resolve immutable sha-* candidate for ghcr.io/wilddog64/shopping-cart-payment — promotion skipped"* ]]
  grep -q 'warning|App CVE Candidate Missing: shopping-cart-payment|' "${NOTIFY_LOG}"
  run ! grep -q 'actions/workflows' "${WGET_LOG}"
  run ! grep -q 'patch application shopping-cart-payment' "${KUBECTL_LOG}"
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
    WGET_LOG="${WGET_LOG}" \
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

@test "missing immutable sha candidate notifies without retrying the batch" {
  export APP_SERVICES="shopping-cart-product-catalog"
  export TEST_SHA_TAG="sha-catalog-new"
  export TEST_LATEST_DIGEST="sha256:feedbeef"
  export TEST_REPORT_ROWS="shopping-cart-apps product-catalog-report ghcr.io/wilddog64/shopping-cart-product-catalog sha-old 0 1"
  export TEST_REPORT_DETAILS_product_catalog_report="HIGH|CVE-4|9.9.9"

  cat >"${TEST_BIN_DIR}/wget" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"${WGET_LOG}"

_out_mode=""
_out_file=""
_spider="false"
_url=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    -qO)
      _out_mode="file"
      shift
      _out_file="$1"
      ;;
    -S)
      ;;
    --spider)
      _spider="true"
      ;;
    http*)
      _url="$1"
      ;;
  esac
  shift
done

case "${_url}" in
  https://ghcr.io/token*)
    printf '{"token":"registry-token"}' >"${_out_file}"
    exit 0
    ;;
  https://ghcr.io/v2/*/tags/list)
    printf '{"name":"repo","tags":["latest","sha-other"]}\n' >"${_out_file}"
    exit 0
    ;;
  https://ghcr.io/v2/*/manifests/latest)
    [ "${_spider}" = "true" ] || exit 1
    printf '  docker-content-digest: sha256:feedbeef\r\n' >&2
    printf '  HTTP/1.1 200 OK\r\n' >&2
    exit 0
    ;;
  https://ghcr.io/v2/*/manifests/sha-*)
    [ "${_spider}" = "true" ] || exit 1
    printf '  docker-content-digest: sha256:olderdigest\r\n' >&2
    printf '  HTTP/1.1 200 OK\r\n' >&2
    exit 0
    ;;
esac

exit 1
EOF
  chmod +x "${TEST_BIN_DIR}/wget"

  run env -i \
    PATH="${PATH}" \
    TRIVY_LOG="${TRIVY_LOG}" \
    WGET_LOG="${WGET_LOG}" \
    NOTIFY_LOG="${NOTIFY_LOG}" \
    KUBECTL_LOG="${KUBECTL_LOG}" \
    TEST_SECRET_SERVER_B64="${TEST_SECRET_SERVER_B64}" \
    TEST_SECRET_CONFIG_B64="${TEST_SECRET_CONFIG_B64}" \
    APP_SERVICES="${APP_SERVICES}" \
    TEST_REPORT_ROWS="${TEST_REPORT_ROWS}" \
    TEST_REPORT_DETAILS_product_catalog_report="${TEST_REPORT_DETAILS_product_catalog_report}" \
    /bin/sh "${TEST_SCAN_SCRIPT}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"failed to resolve immutable sha-* candidate"* ]]
  grep -q 'warning|App CVE Candidate Missing: shopping-cart-product-catalog|' "${NOTIFY_LOG}"
  run ! grep -q 'patch application shopping-cart-product-catalog' "${KUBECTL_LOG}"
}
