#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

TEST_SYSTEM_CURL_BIN="$(command -v curl 2>/dev/null || true)"

setup() {
  export TEST_BIN_DIR="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "${TEST_BIN_DIR}" "${BATS_TEST_TMPDIR}/scripts"
  export PATH="${TEST_BIN_DIR}:$PATH"

  export TRIVY_LOG="${BATS_TEST_TMPDIR}/trivy.log"
  export WGET_LOG="${BATS_TEST_TMPDIR}/wget.log"
  export CURL_LOG="${BATS_TEST_TMPDIR}/curl.log"
  export METRIC_LOG="${BATS_TEST_TMPDIR}/metrics.log"
  export METRIC_STATE="${BATS_TEST_TMPDIR}/metric-state.log"
  export NOTIFY_LOG="${BATS_TEST_TMPDIR}/notify.log"
  export KUBECTL_LOG="${BATS_TEST_TMPDIR}/kubectl.log"
  : >"${TRIVY_LOG}"
  : >"${WGET_LOG}"
  : >"${CURL_LOG}"
  : >"${METRIC_LOG}"
  : >"${METRIC_STATE}"
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
    case "${_accept_header}" in
      *application/vnd.oci.image.index.v1+json*) ;;
      *) exit 1 ;;
    esac
    case "${_url}" in
      *"/manifests/latest")
        _digest="${TEST_LATEST_DIGEST:-sha256:deadbeef}"
        ;;
      *"/manifests/${TEST_SHA_TAG:-sha-new}")
        _digest="${TEST_LATEST_DIGEST:-sha256:deadbeef}"
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

  cat >"${TEST_BIN_DIR}/curl" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"${CURL_LOG:-/dev/null}"
_config=""
_post_file=""
_arg_url=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --config) shift; _config="$1" ;;
    --data-binary) shift; _post_file="${1#@}" ;;
    --connect-timeout|--max-time) shift ;;
    http*) _arg_url="$1" ;;
  esac
  shift
done
_url="$(sed -n 's/^url = "\(.*\)"$/\1/p' "${_config}" 2>/dev/null | head -n1)"
[ -n "${_url}" ] || _url="${_arg_url}"
_body="$(sed -n 's/^output = "\(.*\)"$/\1/p' "${_config}" 2>/dev/null | head -n1)"
_headers="$(sed -n 's/^dump-header = "\(.*\)"$/\1/p' "${_config}" 2>/dev/null | head -n1)"
if [ -n "${_url}" ]; then printf '%s\n' "${_url}" >>"${CURL_LOG:-/dev/null}"; fi
case "${_url}" in
  */metrics/job/*)
    _payload="$(cat "${_post_file}")"
    _metric_line="$(printf '%s\n' "${_payload}" | sed -n '/^k3dm_app_cve_candidate_resolution{/p')"
    printf '%s|%s\n' "${_url}" "${_metric_line}" >>"${METRIC_LOG:-/dev/null}"
    _state_tmp="${METRIC_STATE:-/dev/null}.tmp"
    if [ -f "${METRIC_STATE:-}" ]; then awk -F'|' -v url="${_url}" '$1 != url' "${METRIC_STATE}" >"${_state_tmp}"; else : >"${_state_tmp}"; fi
    printf '%s|%s\n' "${_url}" "${_metric_line}" >>"${_state_tmp}"
    mv "${_state_tmp}" "${METRIC_STATE}"
    printf 202
    ;;
  https://ghcr.io/token*)
    if [ "${TEST_TOKEN_EMPTY:-0}" = 1 ]; then : >"${_body}"; printf 401
    else printf '{"token":"registry-token"}' >"${_body}"; printf 200; fi
    ;;
  https://ghcr.io/v2/*/tags/list)
    if [ "${TEST_TAGS_401:-0}" = 1 ]; then printf 401
    elif [ "${TEST_TAGS_503:-0}" = 1 ]; then printf 503
    elif [ "${TEST_NO_CANDIDATE:-0}" = 1 ]; then printf '{"name":"repo","tags":["latest"]}' >"${_body}"; printf 200
    else printf '{"name":"repo","tags":["latest","%s","sha-old"]}' "${TEST_SHA_TAG:-sha-new}" >"${_body}"; printf 200; fi
    ;;
  https://ghcr.io/v2/*/manifests/*)
    _tag="${_url##*/}"
    if [ "${TEST_MANIFEST_401:-0}" = 1 ]; then printf 401
    elif [ "${TEST_MANIFEST_404_WITH_DIGEST:-0}" = 1 ] && [ "${_tag}" = latest ]; then
      printf 'HTTP/1.1 404 Not Found\r\nDocker-Content-Digest: sha256:deadbeef\r\n\r\n' >"${_headers}"
      printf 404
    elif [ "${TEST_NO_LATEST_DIGEST:-0}" = 1 ] && [ "${_tag}" = latest ]; then printf 404
    else
      if [ "${_tag}" = latest ] || [ "${_tag}" = "${TEST_SHA_TAG:-sha-new}" ]; then _digest="${TEST_LATEST_DIGEST:-sha256:deadbeef}"; else _digest=sha256:abad1dea; fi
      printf 'HTTP/1.1 200 OK\r\nDocker-Content-Digest: %s\r\n\r\n' "${_digest}" >"${_headers}"
      printf 200
    fi
    ;;
  https://api.github.com/repos/*/actions/workflows/*/dispatches)
    grep -q '^request = "POST"$' "${_config}" || exit 1
    grep -q '^header = "Authorization: Bearer ' "${_config}" || exit 1
    printf 204
    ;;
  *)
    if [ -n "${_post_file}" ] && [ -f "${_post_file}" ]; then cat "${_post_file}" >>"${CURL_LOG:-/dev/null}"; fi
    printf 200
    ;;
esac
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
  -n\ platform-ops\ get\ configmap\ app-cve-scan-rebuild-state\ *)
    [ -n "${TEST_REBUILD_LAST_DISPATCH:-}" ] || exit 1
    printf '%s' "${TEST_REBUILD_LAST_DISPATCH}"
    exit 0
    ;;
  -n\ platform-ops\ patch\ configmap\ app-cve-scan-rebuild-state\ *)
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

  export COSIGN_LOG="${BATS_TEST_TMPDIR}/cosign.log"
  : >"${COSIGN_LOG}"
  cat >"${TEST_BIN_DIR}/cosign" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"${COSIGN_LOG}"
case "$1" in
  verify-attestation) exit "${TEST_COSIGN_ATTEST_EXIT:-${TEST_COSIGN_EXIT:-0}}" ;;
  *) exit "${TEST_COSIGN_EXIT:-0}" ;;
esac
EOF
  chmod +x "${TEST_BIN_DIR}/cosign"

  export TEST_COSIGN_PUB="${BATS_TEST_TMPDIR}/cosign.pub"
  printf -- '-----BEGIN PUBLIC KEY-----\nTESTKEY\n-----END PUBLIC KEY-----\n' >"${TEST_COSIGN_PUB}"

  cat >"${BATS_TEST_TMPDIR}/scripts/notify.sh" <<'EOF'
#!/bin/sh
printf '%s|%s|%s\n' "$1" "$2" "$3" >>"${NOTIFY_LOG}"
EOF
  chmod +x "${BATS_TEST_TMPDIR}/scripts/notify.sh"

  export TEST_SECRET_SERVER_B64
  TEST_SECRET_SERVER_B64="$(printf '%s' 'https://2.25.146.252:6443' | base64)"
  export TEST_SECRET_CONFIG_B64
  TEST_SECRET_CONFIG_B64="$(printf '%s' '{"bearerToken":"remote-token","tlsClientConfig":{"insecure":true}}' | base64)"

  export SCAN_SCRIPT="${SCAN_SCRIPT:-${BATS_TEST_DIRNAME}/../../etc/argocd/platform-ops/app-cve-scan.sh}"
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
    CURL_LOG="${CURL_LOG}" \
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
  run grep -qF "${GH_TOKEN}" "${CURL_LOG}" "${WGET_LOG}"
  [ "$status" -eq 1 ]
  run ! grep -q 'patch application ubuntu-hostinger-shopping-cart-order' "${KUBECTL_LOG}"
  grep -q 'warning|App CVE: shopping-cart-order|' "${NOTIFY_LOG}"
}

@test "rebuild dispatched within the cooldown is skipped without notifying" {
  run env -i \
    PATH="${PATH}" \
    TRIVY_LOG="${TRIVY_LOG}" \
    WGET_LOG="${WGET_LOG}" \
    CURL_LOG="${CURL_LOG}" \
    NOTIFY_LOG="${NOTIFY_LOG}" \
    KUBECTL_LOG="${KUBECTL_LOG}" \
    TEST_SECRET_SERVER_B64="${TEST_SECRET_SERVER_B64}" \
    TEST_SECRET_CONFIG_B64="${TEST_SECRET_CONFIG_B64}" \
    APP_SERVICES="shopping-cart-order" \
    GH_TOKEN="test-token" \
    TEST_SHA_TAG="sha-order-new" \
    TEST_LATEST_DIGEST="sha256:deadbeef" \
    TEST_REPORT_ROWS="shopping-cart-apps order-report ghcr.io/wilddog64/shopping-cart-order sha-old 1 1" \
    TEST_REPORT_DETAILS_order_report="CRITICAL|CVE-1|2.0.0" \
    TEST_LATEST_CVES_shopping_cart_order=2 \
    TEST_REBUILD_LAST_DISPATCH="$(( $(date -u +%s) - 3600 ))" \
    /bin/sh "${TEST_SCAN_SCRIPT}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"within cooldown"* ]]
  run grep -c 'dispatches' "${CURL_LOG}"
  [ "${output}" = "0" ]
  run grep -c 'App CVE: shopping-cart-order' "${NOTIFY_LOG}"
  [ "${output}" = "0" ]
}

@test "rebuild dispatched after the cooldown expires dispatches and records the time" {
  run env -i \
    PATH="${PATH}" \
    TRIVY_LOG="${TRIVY_LOG}" \
    WGET_LOG="${WGET_LOG}" \
    CURL_LOG="${CURL_LOG}" \
    NOTIFY_LOG="${NOTIFY_LOG}" \
    KUBECTL_LOG="${KUBECTL_LOG}" \
    TEST_SECRET_SERVER_B64="${TEST_SECRET_SERVER_B64}" \
    TEST_SECRET_CONFIG_B64="${TEST_SECRET_CONFIG_B64}" \
    APP_SERVICES="shopping-cart-order" \
    GH_TOKEN="test-token" \
    TEST_SHA_TAG="sha-order-new" \
    TEST_LATEST_DIGEST="sha256:deadbeef" \
    TEST_REPORT_ROWS="shopping-cart-apps order-report ghcr.io/wilddog64/shopping-cart-order sha-old 1 1" \
    TEST_REPORT_DETAILS_order_report="CRITICAL|CVE-1|2.0.0" \
    TEST_LATEST_CVES_shopping_cart_order=2 \
    TEST_REBUILD_LAST_DISPATCH="$(( $(date -u +%s) - 300000 ))" \
    /bin/sh "${TEST_SCAN_SCRIPT}"

  [ "${status}" -eq 0 ]
  [[ "${output}" != *"within cooldown"* ]]
  run grep -c 'shopping-cart-order/actions/workflows/ci.yml/dispatches' "${CURL_LOG}"
  [ "${output}" -ge 1 ]
  run grep -c 'patch configmap app-cve-scan-rebuild-state' "${KUBECTL_LOG}"
  [ "${output}" -ge 1 ]
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
  grep -q 'patch application ubuntu-hostinger-shopping-cart-basket' "${KUBECTL_LOG}"
  grep -q 'annotate application ubuntu-hostinger-shopping-cart-basket argocd.argoproj.io/refresh=hard --overwrite' "${KUBECTL_LOG}"
  grep -q 'warning|App CVE Promotion: shopping-cart-basket|' "${NOTIFY_LOG}"
}

@test "COSIGN_VERIFY=1: signed clean candidate is cosign-verified then promoted" {
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
    COSIGN_LOG="${COSIGN_LOG}" \
    TEST_SECRET_SERVER_B64="${TEST_SECRET_SERVER_B64}" \
    TEST_SECRET_CONFIG_B64="${TEST_SECRET_CONFIG_B64}" \
    APP_SERVICES="${APP_SERVICES}" \
    TEST_SHA_TAG="${TEST_SHA_TAG}" \
    TEST_REPORT_ROWS="${TEST_REPORT_ROWS}" \
    TEST_REPORT_DETAILS_basket_report="${TEST_REPORT_DETAILS_basket_report}" \
    TEST_LATEST_CVES_shopping_cart_basket="${TEST_LATEST_CVES_shopping_cart_basket}" \
    TEST_LATEST_DIGEST="${TEST_LATEST_DIGEST}" \
    COSIGN_VERIFY=1 \
    COSIGN_PUBLIC_KEY_FILE="${TEST_COSIGN_PUB}" \
    TEST_COSIGN_EXIT=0 \
    /bin/sh "${TEST_SCAN_SCRIPT}"

  [ "${status}" -eq 0 ]
  grep -q 'verify --key .* --insecure-ignore-tlog=true ghcr.io/wilddog64/shopping-cart-basket@sha256:feedbeef' "${COSIGN_LOG}"
  [[ "${output}" == *"SIGGATE shopping-cart-basket: candidate ghcr.io/wilddog64/shopping-cart-basket:sha-basket-new@sha256:feedbeef cosign-verified"* ]]
  grep -q 'patch application ubuntu-hostinger-shopping-cart-basket' "${KUBECTL_LOG}"
}

@test "COSIGN_VERIFY=1: unsigned clean candidate is refused (no promotion)" {
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
    COSIGN_LOG="${COSIGN_LOG}" \
    TEST_SECRET_SERVER_B64="${TEST_SECRET_SERVER_B64}" \
    TEST_SECRET_CONFIG_B64="${TEST_SECRET_CONFIG_B64}" \
    APP_SERVICES="${APP_SERVICES}" \
    TEST_SHA_TAG="${TEST_SHA_TAG}" \
    TEST_REPORT_ROWS="${TEST_REPORT_ROWS}" \
    TEST_REPORT_DETAILS_basket_report="${TEST_REPORT_DETAILS_basket_report}" \
    TEST_LATEST_CVES_shopping_cart_basket="${TEST_LATEST_CVES_shopping_cart_basket}" \
    TEST_LATEST_DIGEST="${TEST_LATEST_DIGEST}" \
    COSIGN_VERIFY=1 \
    COSIGN_PUBLIC_KEY_FILE="${TEST_COSIGN_PUB}" \
    TEST_COSIGN_EXIT=1 \
    /bin/sh "${TEST_SCAN_SCRIPT}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"FAILED cosign verify — refusing to promote"* ]]
  grep -q 'warning|App CVE Promotion Blocked (unsigned): shopping-cart-basket|' "${NOTIFY_LOG}"
  run ! grep -q 'patch application ubuntu-hostinger-shopping-cart-basket' "${KUBECTL_LOG}"
}

@test "COSIGN_VERIFY_ATTESTATION=1: signed + attested clean candidate is promoted" {
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
    COSIGN_LOG="${COSIGN_LOG}" \
    TEST_SECRET_SERVER_B64="${TEST_SECRET_SERVER_B64}" \
    TEST_SECRET_CONFIG_B64="${TEST_SECRET_CONFIG_B64}" \
    APP_SERVICES="${APP_SERVICES}" \
    TEST_SHA_TAG="${TEST_SHA_TAG}" \
    TEST_REPORT_ROWS="${TEST_REPORT_ROWS}" \
    TEST_REPORT_DETAILS_basket_report="${TEST_REPORT_DETAILS_basket_report}" \
    TEST_LATEST_CVES_shopping_cart_basket="${TEST_LATEST_CVES_shopping_cart_basket}" \
    TEST_LATEST_DIGEST="${TEST_LATEST_DIGEST}" \
    COSIGN_VERIFY=1 \
    COSIGN_VERIFY_ATTESTATION=1 \
    COSIGN_PUBLIC_KEY_FILE="${TEST_COSIGN_PUB}" \
    TEST_COSIGN_EXIT=0 \
    /bin/sh "${TEST_SCAN_SCRIPT}"

  [ "${status}" -eq 0 ]
  grep -q 'verify-attestation --type vuln --key .* --insecure-ignore-tlog=true ghcr.io/wilddog64/shopping-cart-basket@sha256:feedbeef' "${COSIGN_LOG}"
  [[ "${output}" == *"ATTESTGATE shopping-cart-basket: candidate ghcr.io/wilddog64/shopping-cart-basket:sha-basket-new@sha256:feedbeef vuln-attestation verified"* ]]
  grep -q 'patch application ubuntu-hostinger-shopping-cart-basket' "${KUBECTL_LOG}"
}

@test "COSIGN_VERIFY_ATTESTATION=1: signed but unattested candidate is refused (no promotion)" {
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
    COSIGN_LOG="${COSIGN_LOG}" \
    TEST_SECRET_SERVER_B64="${TEST_SECRET_SERVER_B64}" \
    TEST_SECRET_CONFIG_B64="${TEST_SECRET_CONFIG_B64}" \
    APP_SERVICES="${APP_SERVICES}" \
    TEST_SHA_TAG="${TEST_SHA_TAG}" \
    TEST_REPORT_ROWS="${TEST_REPORT_ROWS}" \
    TEST_REPORT_DETAILS_basket_report="${TEST_REPORT_DETAILS_basket_report}" \
    TEST_LATEST_CVES_shopping_cart_basket="${TEST_LATEST_CVES_shopping_cart_basket}" \
    TEST_LATEST_DIGEST="${TEST_LATEST_DIGEST}" \
    COSIGN_VERIFY=1 \
    COSIGN_VERIFY_ATTESTATION=1 \
    COSIGN_PUBLIC_KEY_FILE="${TEST_COSIGN_PUB}" \
    TEST_COSIGN_EXIT=0 \
    TEST_COSIGN_ATTEST_EXIT=1 \
    /bin/sh "${TEST_SCAN_SCRIPT}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"FAILED vuln-attestation verify — refusing to promote unattested image"* ]]
  grep -q 'warning|App CVE Promotion Blocked (unattested): shopping-cart-basket|' "${NOTIFY_LOG}"
  run ! grep -q 'patch application ubuntu-hostinger-shopping-cart-basket' "${KUBECTL_LOG}"
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
  grep -q 'patch application ubuntu-hostinger-shopping-cart-basket' "${KUBECTL_LOG}"
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
    CURL_LOG="${CURL_LOG}" \
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
  [[ "${output}" == *"failed to resolve immutable sha-* candidate for ghcr.io/wilddog64/shopping-cart-payment; reason=no-match — promotion skipped"* ]]
  grep -q 'warning|App CVE Candidate Missing: shopping-cart-payment|' "${NOTIFY_LOG}"
  run ! grep -q 'actions/workflows' "${WGET_LOG}"
  run ! grep -q 'patch application ubuntu-hostinger-shopping-cart-payment' "${KUBECTL_LOG}"
}

@test "rebuild dispatch failure notifies without failing the batch" {
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

  [ "${status}" -eq 0 ]
  grep -q 'warning|App CVE Rebuild Dispatch Failed: shopping-cart-order|' "${NOTIFY_LOG}"
  run ! grep -q 'patch application ubuntu-hostinger-shopping-cart-order' "${KUBECTL_LOG}"
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
    CURL_LOG="${CURL_LOG}" \
    NOTIFY_LOG="${NOTIFY_LOG}" \
    KUBECTL_LOG="${KUBECTL_LOG}" \
    TEST_SECRET_SERVER_B64="${TEST_SECRET_SERVER_B64}" \
    TEST_SECRET_CONFIG_B64="${TEST_SECRET_CONFIG_B64}" \
    APP_SERVICES="${APP_SERVICES}" \
    TEST_NO_CANDIDATE=1 \
    TEST_REPORT_ROWS="${TEST_REPORT_ROWS}" \
    TEST_REPORT_DETAILS_product_catalog_report="${TEST_REPORT_DETAILS_product_catalog_report}" \
    /bin/sh "${TEST_SCAN_SCRIPT}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"failed to resolve immutable sha-* candidate"* ]]
  [[ "${output}" == *"reason=no-match"* ]]
  grep -q 'warning|App CVE Candidate Missing: shopping-cart-product-catalog|' "${NOTIFY_LOG}"
  run ! grep -q 'patch application ubuntu-hostinger-shopping-cart-product-catalog' "${KUBECTL_LOG}"
}

@test "GHCR credential failure is classified and reported without exposing the token" {
  export APP_SERVICES="shopping-cart-payment"
  export GH_TOKEN="sentinel-ghcr-secret-value"
  export TEST_TOKEN_EMPTY=1
  if [ "${K3DM_APP_CVE_SCAN_PUSHGATEWAY_URL+x}" != x ]; then
    export K3DM_APP_CVE_SCAN_PUSHGATEWAY_URL="http://pushgateway.test/metrics/job/test"
  fi
  export TEST_REPORT_ROWS="shopping-cart-apps payment-report ghcr.io/wilddog64/shopping-cart-payment sha-old 1 0"
  export TEST_REPORT_DETAILS_payment_report="CRITICAL|CVE-1|2.0.0"

  run /bin/sh "${TEST_SCAN_SCRIPT}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"reason=auth"* ]]
  grep -q 'platform-ops-app-rebuild' "${NOTIFY_LOG}"
  grep -q 'read:packages' "${NOTIFY_LOG}"
  grep -q 'reason=auth' "${NOTIFY_LOG}"
  if [ -n "${K3DM_APP_CVE_SCAN_PUSHGATEWAY_URL:-}" ]; then
    grep -q 'k3dm_app_cve_candidate_resolution{service="shopping-cart-payment",reason="auth"} 1' "${METRIC_LOG}"
  fi
  run grep -qF "${GH_TOKEN}" <<<"${output}$(cat "${NOTIFY_LOG}")$(cat "${CURL_LOG}")"
  [ "$status" -eq 1 ]
  run grep -qF "${GH_TOKEN}" "${WGET_LOG}"
  [ "$status" -eq 1 ]
  run ! grep -q 'patch application ubuntu-hostinger-shopping-cart-payment' "${KUBECTL_LOG}"
}

@test "latest without a digest is classified no-latest" {
  export APP_SERVICES="shopping-cart-payment"
  export TEST_NO_LATEST_DIGEST=1
  export TEST_REPORT_ROWS="shopping-cart-apps payment-report ghcr.io/wilddog64/shopping-cart-payment sha-old 1 0"
  export TEST_REPORT_DETAILS_payment_report="CRITICAL|CVE-1|2.0.0"
  run /bin/sh "${TEST_SCAN_SCRIPT}"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"reason=no-latest"* ]]
}

@test "unavailable tags endpoint is not classified as a genuine no-match" {
  export APP_SERVICES="shopping-cart-payment"
  export TEST_TAGS_503=1
  export TEST_REPORT_ROWS="shopping-cart-apps payment-report ghcr.io/wilddog64/shopping-cart-payment sha-old 1 0"
  export TEST_REPORT_DETAILS_payment_report="CRITICAL|CVE-1|2.0.0"
  run /bin/sh "${TEST_SCAN_SCRIPT}"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"reason=no-latest"* ]]
  [[ "${output}" != *"reason=no-match"* ]]
}

@test "manifest 404 is rejected even when it includes a digest header" {
  export APP_SERVICES="shopping-cart-payment"
  export TEST_MANIFEST_404_WITH_DIGEST=1
  export TEST_REPORT_ROWS="shopping-cart-apps payment-report ghcr.io/wilddog64/shopping-cart-payment sha-old 1 0"
  export TEST_REPORT_DETAILS_payment_report="CRITICAL|CVE-1|2.0.0"
  run /bin/sh "${TEST_SCAN_SCRIPT}"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"reason=no-latest"* ]]
  [[ "${output}" != *"immutable candidate ghcr.io/wilddog64/shopping-cart-payment:sha-new"* ]]
}

@test "manifest 401 with GH_TOKEN is classified auth instead of no-match" {
  export APP_SERVICES="shopping-cart-payment"
  export GH_TOKEN="sentinel-manifest-auth"
  export TEST_MANIFEST_401=1
  export TEST_REPORT_ROWS="shopping-cart-apps payment-report ghcr.io/wilddog64/shopping-cart-payment sha-old 1 0"
  export TEST_REPORT_DETAILS_payment_report="CRITICAL|CVE-1|2.0.0"
  run /bin/sh "${TEST_SCAN_SCRIPT}"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"reason=auth"* ]]
  grep -q 'read:packages' "${NOTIFY_LOG}"
  run grep -qF "${GH_TOKEN}" "${CURL_LOG}"
  [ "$status" -eq 1 ]
}

@test "tags list 401 with GH_TOKEN is classified auth instead of no-match" {
  export APP_SERVICES="shopping-cart-payment"
  export GH_TOKEN="sentinel-tags-auth"
  export TEST_TAGS_401=1
  export TEST_REPORT_ROWS="shopping-cart-apps payment-report ghcr.io/wilddog64/shopping-cart-payment sha-old 1 0"
  export TEST_REPORT_DETAILS_payment_report="CRITICAL|CVE-1|2.0.0"
  run /bin/sh "${TEST_SCAN_SCRIPT}"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"reason=auth"* ]]
  run grep -qF "${GH_TOKEN}" "${CURL_LOG}"
  [ "$status" -eq 1 ]
}

@test "registry transport keeps credentials in a private curl config and scanner image contract is pinned" {
  export GH_TOKEN="sentinel-ghcr-secret-value"
  _resolved="$(awk '/^# === MAIN ===/ { exit } { print }' "${TEST_SCAN_SCRIPT}")"
  [[ "${_resolved}" == *'"${_CURL_BIN}" --connect-timeout 5 --max-time 30 --config "${_config}"'* ]]
  [[ "${_resolved}" != *'wget'* ]]
  grep -q 'chmod 600 "${_config}"' <<<"${_resolved}"
  grep -q -- '--connect-timeout 5 --max-time 30' <<<"${_resolved}"
  grep -q -- '--connect-timeout 5 --max-time 15' <<<"${_resolved}"
  run grep -qF "${GH_TOKEN}" "${CURL_LOG}"
  [ "$status" -eq 1 ]
  grep -q 'image: docker.io/alpine/k8s:1.31.4' "${BATS_TEST_DIRNAME}/../../etc/argocd/platform-ops/app-cve-scan-cronjob.yaml"
  grep -q 'name: install-trivy' "${BATS_TEST_DIRNAME}/../../etc/argocd/platform-ops/app-cve-scan-cronjob.yaml"
  grep -q 'mountPath: /tools' "${BATS_TEST_DIRNAME}/../../etc/argocd/platform-ops/app-cve-scan-cronjob.yaml"
  grep -q 'cp /usr/local/bin/trivy /tools/trivy' "${BATS_TEST_DIRNAME}/../../etc/argocd/platform-ops/app-cve-scan-cronjob.yaml"
  grep -q 'PATH' "${BATS_TEST_DIRNAME}/../../etc/argocd/platform-ops/app-cve-scan-cronjob.yaml"
  grep -q 'runAsUser: 65534' "${BATS_TEST_DIRNAME}/../../etc/argocd/platform-ops/app-cve-scan-cronjob.yaml"
  grep -q 'fsGroup: 65534' "${BATS_TEST_DIRNAME}/../../etc/argocd/platform-ops/app-cve-scan-cronjob.yaml"
  grep -A6 'name: install-trivy' "${BATS_TEST_DIRNAME}/../../etc/argocd/platform-ops/app-cve-scan-cronjob.yaml" | grep 'runAsNonRoot: true' >/dev/null
}

@test "candidate metric groups preserve two services and replace auth with ok per service" {
  export APP_SERVICES="shopping-cart-payment shopping-cart-product-catalog"
  export GH_TOKEN="sentinel-metric-secret"
  export TEST_TOKEN_EMPTY=1
  if [ "${K3DM_APP_CVE_SCAN_PUSHGATEWAY_URL+x}" != x ]; then
    export K3DM_APP_CVE_SCAN_PUSHGATEWAY_URL="http://pushgateway.test/metrics/job/k3dm-app-cve-scan"
  fi
  [ -n "${K3DM_APP_CVE_SCAN_PUSHGATEWAY_URL:-}" ] || skip "task Pushgateway URL is empty"
  export TEST_REPORT_ROWS=$'shopping-cart-apps payment-report ghcr.io/wilddog64/shopping-cart-payment sha-old 1 0\nshopping-cart-apps product-catalog-report ghcr.io/wilddog64/shopping-cart-product-catalog sha-old 1 0'
  export TEST_REPORT_DETAILS_payment_report="CRITICAL|CVE-1|2.0.0"
  export TEST_REPORT_DETAILS_product_catalog_report="CRITICAL|CVE-2|2.0.0"

  run /bin/sh "${TEST_SCAN_SCRIPT}"
  [ "${status}" -eq 0 ]
  [ "$(wc -l <"${METRIC_STATE}" | tr -d ' ')" -eq 2 ]
  grep -q '/instance/shopping-cart-payment|k3dm_app_cve_candidate_resolution{service="shopping-cart-payment",reason="auth"} 1' "${METRIC_STATE}"
  grep -q '/instance/shopping-cart-product-catalog|k3dm_app_cve_candidate_resolution{service="shopping-cart-product-catalog",reason="auth"} 1' "${METRIC_STATE}"

  unset TEST_TOKEN_EMPTY
  run /bin/sh "${TEST_SCAN_SCRIPT}"
  [ "${status}" -eq 0 ]
  [ "$(wc -l <"${METRIC_STATE}" | tr -d ' ')" -eq 2 ]
  [ "$(grep -c 'reason="ok"' "${METRIC_STATE}")" -eq 2 ]
  run grep -q 'reason="auth"' "${METRIC_STATE}"
  [ "$status" -eq 1 ]
  [ "$(wc -l <"${METRIC_LOG}" | tr -d ' ')" -eq 4 ]

  export TEST_REPORT_ROWS="shopping-cart-apps payment-report ghcr.io/wilddog64/shopping-cart-payment sha-old 1 0"
  run /bin/sh "${TEST_SCAN_SCRIPT}"
  [ "${status}" -eq 0 ]
  [ "$(wc -l <"${METRIC_STATE}" | tr -d ' ')" -eq 2 ]
  grep -q '/instance/shopping-cart-product-catalog|k3dm_app_cve_candidate_resolution{service="shopping-cart-product-catalog",reason="ok"} 1' "${METRIC_STATE}"
  [ "$(grep -c '/instance/shopping-cart-product-catalog' "${METRIC_LOG}")" -eq 2 ]
  [ "$(wc -l <"${METRIC_LOG}" | tr -d ' ')" -eq 5 ]
  run grep -qF "${GH_TOKEN}" "${CURL_LOG}" "${METRIC_LOG}" "${METRIC_STATE}"
  [ "$status" -eq 1 ]
}

@test "real curl HEAD returns only the status and writes digest headers separately" {
  [ -n "${TEST_SYSTEM_CURL_BIN}" ] || skip "curl binary unavailable"
  command -v python3 >/dev/null 2>&1 || skip "python3 unavailable for loopback HTTP fixture"
  _fixture="${BATS_TEST_TMPDIR}/head-fixture.py"
  _port_file="${BATS_TEST_TMPDIR}/head-fixture.port"
  _headers_file="${BATS_TEST_TMPDIR}/head-fixture.headers"
  cat >"${_fixture}" <<'PY'
from http.server import BaseHTTPRequestHandler, HTTPServer
import sys

class Handler(BaseHTTPRequestHandler):
    def do_HEAD(self):
        self.send_response(200)
        self.send_header("Docker-Content-Digest", "sha256:deadbeef")
        self.end_headers()

    def log_message(self, *_args):
        pass

try:
    server = HTTPServer(("127.0.0.1", 0), Handler)
except OSError as exc:
    print(f"BIND_UNAVAILABLE:{exc}", flush=True)
    sys.exit(77)
print(server.server_port, flush=True)
server.timeout = 5
server.handle_request()
server.server_close()
PY
  python3 "${_fixture}" >"${_port_file}" 2>"${BATS_TEST_TMPDIR}/head-fixture.err" &
  _server_pid=$!
  for _attempt in $(seq 1 50); do
    [ -s "${_port_file}" ] && break
    sleep 0.1
  done
  if [ ! -s "${_port_file}" ]; then
    wait "${_server_pid}" || true
    fail "loopback fixture did not start: $(cat "${BATS_TEST_TMPDIR}/head-fixture.err")"
  fi
  _port="$(cat "${_port_file}")"
  case "${_port}" in
    BIND_UNAVAILABLE:*) wait "${_server_pid}" || true; skip "sandbox cannot bind loopback: ${_port#BIND_UNAVAILABLE:}" ;;
  esac

  run /bin/sh -c '
    _functions="$(mktemp)"
    awk "/^# === MAIN ===/ { exit } { print }" "$1" >"${_functions}"
    . "${_functions}"
    _CURL_BIN="$2"
    _ghcr_request "$3" "" "$4" head ""
    _rc=$?
    rm -f "${_functions}"
    exit "${_rc}"
  ' _ "${SCAN_SCRIPT}" "${TEST_SYSTEM_CURL_BIN}" "http://127.0.0.1:${_port}/manifest" "${_headers_file}"
  wait "${_server_pid}"
  [ "${status}" -eq 0 ]
  [ "${output}" = "200" ]
  grep -q '^Docker-Content-Digest: sha256:deadbeef' "${_headers_file}"
}
