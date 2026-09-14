#!/usr/bin/env bats

SCAN_SCRIPT="${BATS_TEST_DIRNAME}/../../etc/argocd/platform-ops/cve-scan.sh"
RBAC_MANIFEST="${BATS_TEST_DIRNAME}/../../etc/argocd/platform-ops/rbac.yaml"

@test "cve scan reads the Hub chart label from argocd-server" {
  run grep -F -- "get deployment argocd-server" "${SCAN_SCRIPT}"
  [ "${status}" -eq 0 ]

  run grep -F -- "metadata.labels.helm\\.sh/chart" "${SCAN_SCRIPT}"
  [ "${status}" -eq 0 ]

  run grep -F -- 'argo-cd-*)' "${SCAN_SCRIPT}"
  [ "${status}" -eq 0 ]
}

@test "cve scan does not create or patch an infra cluster-secret stage" {
  run grep -F -- '_chart_label "infra"' "${SCAN_SCRIPT}"
  [ "${status}" -ne 0 ]

  run grep -F -- '_patch_stage "infra"' "${SCAN_SCRIPT}"
  [ "${status}" -ne 0 ]

  run grep -F -- 'Hub self-upgrade is external' "${SCAN_SCRIPT}"
  [ "${status}" -eq 0 ]
}

@test "cve scanner is authorized only to read the Hub deployment" {
  run grep -A2 -F 'resources: ["deployments"]' "${RBAC_MANIFEST}"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *'verbs: ["get"]'* ]]
}

@test "cve scan runs end-to-end with wget, kubectl and trivy" {
  mkdir -p "${BATS_TEST_TMPDIR}/bin"

  cat > "${BATS_TEST_TMPDIR}/bin/kubectl" <<'EOF'
#!/bin/sh
case " $* " in
  *"helm"*"chart"*) printf '%s' 'argo-cd-10.8.4' ;;
  *"containers[0].image"*) printf '%s' "${STUB_ARGOCD_IMAGE-quay.io/argoproj/argocd:v3.5.2}" ;;
  *) printf '%s\n' "$*" >> "${BATS_TEST_TMPDIR}/kubectl.log" ;;
esac
EOF
  cat > "${BATS_TEST_TMPDIR}/bin/wget" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "${BATS_TEST_TMPDIR}/wget.log"
EOF
  cat > "${BATS_TEST_TMPDIR}/bin/trivy" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "${BATS_TEST_TMPDIR}/trivy.log"
[ -z "${STUB_TRIVY_FAIL:-}" ] || { echo "FATAL image pull failed"; exit 1; }
exit 0
EOF
  cat > "${BATS_TEST_TMPDIR}/bin/curl" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "${BATS_TEST_TMPDIR}/curl.log"
exit 99
EOF
  chmod +x "${BATS_TEST_TMPDIR}/bin/kubectl" "${BATS_TEST_TMPDIR}/bin/wget" \
    "${BATS_TEST_TMPDIR}/bin/trivy" "${BATS_TEST_TMPDIR}/bin/curl"

  run env PATH="${BATS_TEST_TMPDIR}/bin:/usr/bin:/bin" \
    KUBECTL_BIN="${BATS_TEST_TMPDIR}/bin/kubectl" sh "${SCAN_SCRIPT}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Current chart: 10.8.4"* ]]
  [[ "${output}" == *"App version: v3.5.2"* ]]
  [[ "${output}" == *"No HIGH/CRITICAL CVEs"* ]]
  [ ! -e "${BATS_TEST_TMPDIR}/curl.log" ]
  run grep -c 'quay.io/argoproj/argocd:v3.5.2' "${BATS_TEST_TMPDIR}/trivy.log"
  [ "${output}" -eq 1 ]

  run env PATH="${BATS_TEST_TMPDIR}/bin:/usr/bin:/bin" STUB_TRIVY_FAIL=1 \
    KUBECTL_BIN="${BATS_TEST_TMPDIR}/bin/kubectl" sh "${SCAN_SCRIPT}"
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"trivy scan of quay.io/argoproj/argocd:v3.5.2 failed"* ]]

  run env PATH="${BATS_TEST_TMPDIR}/bin:/usr/bin:/bin" STUB_ARGOCD_IMAGE="" \
    KUBECTL_BIN="${BATS_TEST_TMPDIR}/bin/kubectl" sh "${SCAN_SCRIPT}"
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"cannot read the argocd-server image tag"* ]]
}

@test "cve scan downloads kubectl when absent" {
  if [ -x /usr/bin/kubectl ] || [ -x /bin/kubectl ]; then
    skip "host kubectl on PATH"
  fi
  mkdir -p "${BATS_TEST_TMPDIR}/bin"

  cat > "${BATS_TEST_TMPDIR}/bin/wget" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "${BATS_TEST_TMPDIR}/wget.log"
target=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -qO|-O) target="$2"; shift 2 ;;
    *) shift ;;
  esac
done
printf '%s\n' '#!/bin/sh' 'exit 0' > "${target}"
EOF
  chmod +x "${BATS_TEST_TMPDIR}/bin/wget"

  run env PATH="${BATS_TEST_TMPDIR}/bin:/usr/bin:/bin" KUBECTL_BIN="" sh "${SCAN_SCRIPT}"

  [ "${status}" -eq 1 ]
  [[ "${output}" == *"cannot read the Hub Argo CD chart label"* ]]
  run grep 'dl.k8s.io/release/v1.30.2/bin/linux/amd64/kubectl' "${BATS_TEST_TMPDIR}/wget.log"
  [ "${status}" -eq 0 ]
}

@test "cve scanner has no curl invocation" {
  run grep -c 'curl ' "${SCAN_SCRIPT}"
  [ "${output}" -eq 0 ]
}

@test "cve scan holds major chart upgrades but patches same-major ones" {
  mkdir -p "${BATS_TEST_TMPDIR}/bin"

  cat > "${BATS_TEST_TMPDIR}/bin/kubectl" <<'EOF2'
#!/bin/sh
case " $* " in
  *" patch "*) printf '%s\n' "$*" >> "${BATS_TEST_TMPDIR}/patch.log" ;;
  *"helm"*"chart"*) printf '%s' 'argo-cd-10.8.4' ;;
  *"containers[0].image"*) printf '%s' 'quay.io/argoproj/argocd:v3.5.2' ;;
  *"argocd-chart-version"*) printf '%s' "${STUB_DEV_CHART}" ;;
  *"metadata.name"*) printf '%s' 'cluster-ubuntu-hostinger' ;;
esac
EOF2
  cat > "${BATS_TEST_TMPDIR}/bin/wget" <<'EOF2'
#!/bin/sh
printf '%s' '{"version":"10.9.1","app_version":"v3.5.3"}'
EOF2
  cat > "${BATS_TEST_TMPDIR}/bin/trivy" <<'EOF2'
#!/bin/sh
echo "argocd  CVE-2026-0001  CRITICAL"
EOF2
  chmod +x "${BATS_TEST_TMPDIR}/bin/kubectl" "${BATS_TEST_TMPDIR}/bin/wget" \
    "${BATS_TEST_TMPDIR}/bin/trivy"

  run env PATH="${BATS_TEST_TMPDIR}/bin:/usr/bin:/bin" STUB_DEV_CHART=7.8.1 \
    KUBECTL_BIN="${BATS_TEST_TMPDIR}/bin/kubectl" sh "${SCAN_SCRIPT}"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"major upgrade 7.8.1 -> 10.9.1 held"* ]]
  [ ! -e "${BATS_TEST_TMPDIR}/patch.log" ]

  run env PATH="${BATS_TEST_TMPDIR}/bin:/usr/bin:/bin" STUB_DEV_CHART=10.8.4 \
    KUBECTL_BIN="${BATS_TEST_TMPDIR}/bin/kubectl" sh "${SCAN_SCRIPT}"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"patched cluster-ubuntu-hostinger to 10.9.1"* ]]
  [ -s "${BATS_TEST_TMPDIR}/patch.log" ]
}
