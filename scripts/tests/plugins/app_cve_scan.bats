#!/usr/bin/env bats

setup() {
  export TEST_BIN_DIR="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "${TEST_BIN_DIR}" "${BATS_TEST_TMPDIR}/scripts"
  export PATH="${TEST_BIN_DIR}:$PATH"

  export TRIVY_LOG="${BATS_TEST_TMPDIR}/trivy.log"
  export CURL_LOG="${BATS_TEST_TMPDIR}/curl.log"
  export NOTIFY_LOG="${BATS_TEST_TMPDIR}/notify.log"
  : >"${TRIVY_LOG}"
  : >"${CURL_LOG}"
  : >"${NOTIFY_LOG}"

  cat >"${TEST_BIN_DIR}/trivy" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"${TRIVY_LOG}"
_last=""
for _arg in "$@"; do
  _last="${_arg}"
done
case "${_last}" in
  *shopping-cart-basket:latest)
    [ "${TEST_CVES_shopping_cart_basket:-0}" -eq 0 ] || i=0
    while [ "${i:-0}" -lt "${TEST_CVES_shopping_cart_basket:-0}" ]; do
      printf 'HIGH\n'
      i=$((i + 1))
    done
    ;;
  *shopping-cart-order:latest)
    [ "${TEST_CVES_shopping_cart_order:-0}" -eq 0 ] || i=0
    while [ "${i:-0}" -lt "${TEST_CVES_shopping_cart_order:-0}" ]; do
      printf 'CRITICAL\n'
      i=$((i + 1))
    done
    ;;
  *shopping-cart-product-catalog:latest)
    [ "${TEST_CVES_shopping_cart_product_catalog:-0}" -eq 0 ] || i=0
    while [ "${i:-0}" -lt "${TEST_CVES_shopping_cart_product_catalog:-0}" ]; do
      printf 'HIGH\n'
      i=$((i + 1))
    done
    ;;
esac
EOF
  chmod +x "${TEST_BIN_DIR}/trivy"

  cat >"${TEST_BIN_DIR}/curl" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"${CURL_LOG}"
exit 0
EOF
  chmod +x "${TEST_BIN_DIR}/curl"

  cat >"${BATS_TEST_TMPDIR}/scripts/notify.sh" <<'EOF'
#!/bin/sh
printf '%s|%s|%s\n' "$1" "$2" "$3" >>"${NOTIFY_LOG}"
EOF
  chmod +x "${BATS_TEST_TMPDIR}/scripts/notify.sh"

  export SCAN_SCRIPT="${BATS_TEST_DIRNAME}/../../etc/argocd/platform-ops/app-cve-scan.sh"
  export TEST_SCAN_SCRIPT="${BATS_TEST_TMPDIR}/app-cve-scan.sh"
  sed "s|/scripts/notify.sh|${BATS_TEST_TMPDIR}/scripts/notify.sh|g" "${SCAN_SCRIPT}" >"${TEST_SCAN_SCRIPT}"
  chmod +x "${TEST_SCAN_SCRIPT}"
}

@test "clean image does not dispatch rebuild and exits 0" {
  export TEST_CVES_shopping_cart_basket=0
  export APP_SERVICES="shopping-cart-basket"

  run env -i \
    PATH="${PATH}" \
    TRIVY_LOG="${TRIVY_LOG}" \
    CURL_LOG="${CURL_LOG}" \
    NOTIFY_LOG="${NOTIFY_LOG}" \
    APP_SERVICES="${APP_SERVICES}" \
    TEST_CVES_shopping_cart_basket="${TEST_CVES_shopping_cart_basket}" \
    /bin/sh "${TEST_SCAN_SCRIPT}"

  [ "$status" -eq 0 ]
  [ ! -s "${CURL_LOG}" ]
  [ ! -s "${NOTIFY_LOG}" ]
}

@test "vulnerable latest notifies and dispatches rebuild per service" {
  export TEST_CVES_shopping_cart_order=2
  export APP_SERVICES="shopping-cart-order"
  export GH_TOKEN="test-token"

  run env -i \
    PATH="${PATH}" \
    TRIVY_LOG="${TRIVY_LOG}" \
    CURL_LOG="${CURL_LOG}" \
    NOTIFY_LOG="${NOTIFY_LOG}" \
    APP_SERVICES="${APP_SERVICES}" \
    GH_TOKEN="${GH_TOKEN}" \
    TEST_CVES_shopping_cart_order="${TEST_CVES_shopping_cart_order}" \
    /bin/sh "${TEST_SCAN_SCRIPT}"

  [ "$status" -eq 0 ]
  grep -q 'warning|App CVE: shopping-cart-order|2 HIGH/CRITICAL CVE(s) in ghcr.io/wilddog64/shopping-cart-order:latest; triggering rebuild' "${NOTIFY_LOG}"
  grep -q 'shopping-cart-order/actions/workflows/ci.yml/dispatches' "${CURL_LOG}"
}

@test "dispatch failure without token returns non-zero and still scans other services" {
  export TEST_CVES_shopping_cart_basket=1
  export TEST_CVES_shopping_cart_order=0
  export APP_SERVICES="shopping-cart-basket shopping-cart-order"

  run env -i \
    PATH="${PATH}" \
    TRIVY_LOG="${TRIVY_LOG}" \
    CURL_LOG="${CURL_LOG}" \
    NOTIFY_LOG="${NOTIFY_LOG}" \
    APP_SERVICES="${APP_SERVICES}" \
    TEST_CVES_shopping_cart_basket="${TEST_CVES_shopping_cart_basket}" \
    TEST_CVES_shopping_cart_order="${TEST_CVES_shopping_cart_order}" \
    /bin/sh "${TEST_SCAN_SCRIPT}"

  [ "$status" -eq 1 ]
  grep -q 'shopping-cart-basket:latest' "${TRIVY_LOG}"
  grep -q 'shopping-cart-order:latest' "${TRIVY_LOG}"
  [ ! -s "${CURL_LOG}" ]
}

@test "multiple services are iterated and each vulnerable service dispatches" {
  export TEST_CVES_shopping_cart_basket=1
  export TEST_CVES_shopping_cart_order=2
  export TEST_CVES_shopping_cart_product_catalog=0
  export APP_SERVICES="shopping-cart-basket shopping-cart-order shopping-cart-product-catalog"
  export GH_TOKEN="test-token"

  run env -i \
    PATH="${PATH}" \
    TRIVY_LOG="${TRIVY_LOG}" \
    CURL_LOG="${CURL_LOG}" \
    NOTIFY_LOG="${NOTIFY_LOG}" \
    APP_SERVICES="${APP_SERVICES}" \
    GH_TOKEN="${GH_TOKEN}" \
    TEST_CVES_shopping_cart_basket="${TEST_CVES_shopping_cart_basket}" \
    TEST_CVES_shopping_cart_order="${TEST_CVES_shopping_cart_order}" \
    TEST_CVES_shopping_cart_product_catalog="${TEST_CVES_shopping_cart_product_catalog}" \
    /bin/sh "${TEST_SCAN_SCRIPT}"

  [ "$status" -eq 0 ]
  grep -q 'shopping-cart-basket/actions/workflows/ci.yml/dispatches' "${CURL_LOG}"
  grep -q 'shopping-cart-order/actions/workflows/ci.yml/dispatches' "${CURL_LOG}"
  ! grep -q 'shopping-cart-product-catalog/actions/workflows/ci.yml/dispatches' "${CURL_LOG}"
}
