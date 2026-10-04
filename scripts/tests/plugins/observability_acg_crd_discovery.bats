#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  source "${BATS_TEST_DIRNAME}/../test_helpers.bash"
  export SCRIPT_DIR="${BATS_TEST_DIRNAME}/../.."
  export PLUGINS_DIR="${SCRIPT_DIR}/plugins"
  source "${PLUGINS_DIR}/observability.sh"
  export K3DM_ACG_RULES_CRD_ATTEMPTS=2
  export K3DM_ACG_RULES_CRD_INTERVAL=0
  export K3DM_ACG_PROM_DISCOVERY_ATTEMPTS=2
  export K3DM_ACG_PROM_DISCOVERY_INTERVAL=0
}

@test "ACG PrometheusRule CRD wait reads Established condition" {
  _kubectl() { printf '%s' "${CRD_STATUS:-}"; }
  export -f _kubectl

  CRD_STATUS=True run _observability_wait_for_prometheusrule_crd ubuntu-k3s
  [ "$status" -eq 0 ]

  CRD_STATUS=False run _observability_wait_for_prometheusrule_crd ubuntu-k3s
  [ "$status" -eq 1 ]

  CRD_STATUS= run _observability_wait_for_prometheusrule_crd ubuntu-k3s
  [ "$status" -eq 1 ]
}

@test "ACG PrometheusRule CRD wait no longer invokes kubectl wait" {
  local body
  body="$(sed -n '/^function _observability_wait_for_prometheusrule_crd()/,/^}$/p' scripts/plugins/observability.sh)"
  run grep -E '(^|[[:space:]])(_kubectl[[:space:]]+.*)?wait([[:space:]]|$)' <<<"$body"
  [ "$status" -ne 0 ]
}

@test "ACG discovery check accepts a served Prometheus kind" {
  _kubectl() { printf '%s\n' 'prometheuses.monitoring.coreos.com'; }
  export -f _kubectl
  run _observability_warn_if_prometheus_kind_unserved ubuntu-k3s
  [ "$status" -eq 0 ]
}

@test "ACG discovery check warns when Prometheus kind is unserved" {
  _kubectl() { return 0; }
  export -f _kubectl
  run _observability_warn_if_prometheus_kind_unserved ubuntu-k3s
  [ "$status" -eq 1 ]
  [[ "$output" == *"restart k3s"* ]]
  [[ "$output" == *"fix-sync"* ]]
}

@test "ACG Step 14b recovery hint escapes the port-forward PID" {
  run grep -F 'echo \$! >' bin/cluster-up
  [ "$status" -eq 0 ]
  [[ "$output" == *"prometheus-operated not found"* ]]
}

@test "ACG discovery warning follows successful PrometheusRule apply" {
  local block apply_line warn_line
  block="$(sed -n '/^    if \! _observability_wait_for_prometheusrule_crd/,/^  fi$/p' scripts/plugins/observability.sh)"
  apply_line="$(printf '%s\n' "$block" | grep -n '_kubectl apply.*_acg_rules_dir' | cut -d: -f1)"
  warn_line="$(printf '%s\n' "$block" | grep -n '_observability_warn_if_prometheus_kind_unserved.*|| true' | cut -d: -f1)"
  [ -n "$apply_line" ]
  [ -n "$warn_line" ]
  [ "$warn_line" -gt "$apply_line" ]
}

@test "ACG Step 14b puts Prometheus port-forward inside the Service guard" {
  local if_line fi_line pf_line
  if_line="$(grep -n '^if \[\[ "\${_acg_prom_svc_ready}"' bin/cluster-up | cut -d: -f1)"
  fi_line="$(awk -v start="$if_line" 'NR > start && /^fi$/ { print NR; exit }' bin/cluster-up)"
  pf_line="$(grep -n 'kubectl port-forward svc/prometheus-operated' bin/cluster-up | head -1 | cut -d: -f1)"
  [ -n "$if_line" ] && [ -n "$fi_line" ] && [ -n "$pf_line" ]
  [ "$pf_line" -gt "$if_line" ] && [ "$pf_line" -lt "$fi_line" ]
}
