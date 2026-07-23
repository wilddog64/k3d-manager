#!/usr/bin/env bats

setup() {
  source "${BATS_TEST_DIRNAME}/../test_helpers.bash"
  init_test_env
  source "${BATS_TEST_DIRNAME}/../../plugins/argocd.sh"
}

@test "_argocd_ensure_servicemonitors renders with api-versions and applies only ServiceMonitors" {
  : > "$HELM_LOG"
  : > "$KUBECTL_LOG"
  local applied="${BATS_TEST_TMPDIR}/applied-servicemonitors.yaml"
  local values_file="${BATS_TEST_TMPDIR}/argocd-values.yaml"
  printf 'server:\n  insecure: false\n' > "$values_file"

  _helm() {
    echo "$*" >> "$HELM_LOG"
    cat <<'EOF'
kind: ServiceMonitor
metadata:
  name: argocd-server-metrics
---
kind: ConfigMap
metadata:
  name: argocd-cm
---
kind: ServiceMonitor
metadata:
  name: argocd-repo-server-metrics
EOF
  }

  _kubectl() {
    echo "$*" >> "$KUBECTL_LOG"
    if [[ "$*" == "get crd servicemonitors.monitoring.coreos.com" ]]; then
      return 0
    fi
    if [[ "$*" == "apply -f -" ]]; then
      cat > "$applied"
      return 0
    fi
    return 0
  }

  export -f _helm _kubectl

  run _argocd_ensure_servicemonitors "$values_file"
  [ "$status" -eq 0 ]

  local -a helm_calls=()
  read_lines "$HELM_LOG" helm_calls
  [ "${#helm_calls[@]}" -eq 1 ]
  [[ "${helm_calls[0]}" == *"template argocd argo/argo-cd -n cicd --api-versions monitoring.coreos.com/v1"* ]]
  [[ "${helm_calls[0]}" == *"--values $values_file"* ]]
  [[ "${helm_calls[0]}" != *"--version 7.8.1"* ]]

  local -a kubectl_calls=()
  read_lines "$KUBECTL_LOG" kubectl_calls
  [ "${kubectl_calls[0]}" = "get crd servicemonitors.monitoring.coreos.com" ]
  [ "${kubectl_calls[1]}" = "apply -f -" ]

  run grep -c '^kind: ServiceMonitor$' "$applied"
  [ "$status" -eq 0 ]
  [ "$output" -eq 2 ]

  run grep -F 'kind: ConfigMap' "$applied"
  [ "$status" -ne 0 ]
}

@test "_argocd_ensure_servicemonitors is a no-op when the ServiceMonitor CRD is absent" {
  : > "$HELM_LOG"
  : > "$KUBECTL_LOG"

  _helm() {
    echo "$*" >> "$HELM_LOG"
    return 0
  }

  _kubectl() {
    echo "$*" >> "$KUBECTL_LOG"
    if [[ "$*" == "get crd servicemonitors.monitoring.coreos.com" ]]; then
      return 1
    fi
    return 0
  }

  export -f _helm _kubectl

  run _argocd_ensure_servicemonitors
  [ "$status" -eq 0 ]
  [[ "$output" == *"ServiceMonitor CRD absent"* ]]

  local -a helm_calls=()
  read_lines "$HELM_LOG" helm_calls
  [ "${#helm_calls[@]}" -eq 0 ]

  local -a kubectl_calls=()
  read_lines "$KUBECTL_LOG" kubectl_calls
  [ "${#kubectl_calls[@]}" -eq 1 ]
  [ "${kubectl_calls[0]}" = "get crd servicemonitors.monitoring.coreos.com" ]
}
