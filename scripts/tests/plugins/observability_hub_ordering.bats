#!/usr/bin/env bats

REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"

setup() {
  export PLUGINS_DIR="${BATS_TEST_TMPDIR}/plugins"
  KUBECTL_LOG="${BATS_TEST_TMPDIR}/kubectl.log"
  HELM_LOG="${BATS_TEST_TMPDIR}/helm.log"
  : > "${KUBECTL_LOG}"
  : > "${HELM_LOG}"
  source "${REPO_ROOT}/scripts/plugins/observability.sh"

  _info() {
    printf '%s\n' "$*"
  }

  _warn() {
    printf '%s\n' "$*"
  }

  sleep() {
    printf '%s\n' "$*" >> "${BATS_TEST_TMPDIR}/sleep.log"
  }

  jq() {
    printf '%s\n' "$*" >> "${BATS_TEST_TMPDIR}/jq.log"
    if [[ "${HELM_LIST_RESULT:-present}" == "present" ]]; then
      printf '%s\n' '10.8.4'
    fi
  }

  yq() {
    printf '%s\n' "$*" >> "${BATS_TEST_TMPDIR}/yq.log"
    awk 'BEGIN { keep = 0 } /^kind: ServiceMonitor$/ { keep = 1 } /^kind: ConfigMap$/ { keep = 0 } keep { print }'
  }

  _helm() {
    printf '%s\n' "$*" >> "${HELM_LOG}"
    case "$*" in
      *" list "*)
        if [[ "${HELM_LIST_RESULT:-present}" == "present" ]]; then
          printf '%s\n' '[{"chart":"argo-cd-10.8.4"}]'
        else
          printf '%s\n' '[]'
        fi
        ;;
      *" get values "*)
        printf '%s\n' 'server:' '  metrics:' '    enabled: true'
        ;;
      template*)
        cat <<'EOF'
kind: ServiceMonitor
metadata:
  name: argocd-server-metrics
---
kind: ConfigMap
metadata:
  name: argocd-cm
EOF
        ;;
    esac
  }

  _kubectl() {
    printf '%s\n' "$*" >> "${KUBECTL_LOG}"
    case "$*" in
      *" get crd servicemonitors.monitoring.coreos.com")
        [[ "${CRD_PRESENT:-true}" == "true" ]]
        ;;
      *" apply -f -")
        cat > "${BATS_TEST_TMPDIR}/applied.yaml"
        ;;
    esac
  }
}

@test "observability ServiceMonitors: renders live release values and applies only ServiceMonitors" {
  run _observability_ensure_argocd_servicemonitors "hub-context"
  [ "${status}" -eq 0 ]

  run grep -q -- '--version 10.8.4' "${HELM_LOG}"
  [ "${status}" -eq 0 ]
  run grep -q -- '--api-versions monitoring.coreos.com/v1' "${HELM_LOG}"
  [ "${status}" -eq 0 ]
  run grep -q 'kind: ServiceMonitor' "${BATS_TEST_TMPDIR}/applied.yaml"
  [ "${status}" -eq 0 ]
  run grep -q 'kind: ConfigMap' "${BATS_TEST_TMPDIR}/applied.yaml"
  [ "${status}" -ne 0 ]
  run grep -q 'upgrade' "${HELM_LOG}"
  [ "${status}" -ne 0 ]
}

@test "observability ServiceMonitors: exits cleanly when the CRD never appears" {
  export CRD_PRESENT=false OBSERVABILITY_CRD_WAIT_SECONDS=20

  run _observability_ensure_argocd_servicemonitors "hub-context"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"NOT ensured"* ]]
  run grep -q 'template' "${HELM_LOG}"
  [ "${status}" -ne 0 ]
}

@test "observability ServiceMonitors: exits cleanly when the release is missing" {
  export HELM_LIST_RESULT=missing

  run _observability_ensure_argocd_servicemonitors "hub-context"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"not found"* ]]
  run grep -q 'apply' "${KUBECTL_LOG}"
  [ "${status}" -ne 0 ]
}

@test "deploy_observability: promotes credential-free hub setup before Vault reads" {
  run sed -n '/^function deploy_observability()/,/^}$/p' "${REPO_ROOT}/scripts/plugins/observability.sh"
  [ "${status}" -eq 0 ]

  local promtail_line vault_line promtail_count
  promtail_line="$(printf '%s\n' "${output}" | awk '/_deploy_promtail_acg/ { print NR; exit }')"
  vault_line="$(printf '%s\n' "${output}" | awk '/Reading Alertmanager credentials/ { print NR; exit }')"
  promtail_count="$(printf '%s\n' "${output}" | awk '/_deploy_promtail_acg/ { count++ } END { print count + 0 }')"
  [ "${promtail_line}" -lt "${vault_line}" ]
  [ "${promtail_count}" -eq 1 ]
}
