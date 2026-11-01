#!/usr/bin/env bats

setup() {
  source "${BATS_TEST_DIRNAME}/../test_helpers.bash"
  init_test_env
  source "${SCRIPT_DIR}/plugins/argocd.sh"
  export TEST_ROOT="$BATS_TEST_TMPDIR/rotators"
  mkdir -p "$TEST_ROOT/bin" "$TEST_ROOT/plugins"
  export KUBECONFIG="$TEST_ROOT/kubeconfig"
  cat > "$KUBECONFIG" <<'CONFIG'
apiVersion: v1
kind: Config
clusters: []
contexts: []
current-context: ""
CONFIG
  export KUBECTL_LOG="$TEST_ROOT/kubectl.log" HELM_LOG="$TEST_ROOT/helm.log"
  : > "$KUBECTL_LOG"
  : > "$HELM_LOG"
  cat > "$TEST_ROOT/bin/kubectl" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$KUBECTL_LOG"
# Captured on m5-air.local, 2026-11-01T12:20:58Z: namespaces cicd,
# identity, and monitoring were Active; these hosted the three rotator CronJobs.
if [[ "$1 $2" == 'get namespace' ]]; then
  [[ "${ABSENT_NAMESPACE:-}" != "${3:-}" ]] || exit 1
  case "${3:-}" in cicd|monitoring|identity) printf 'NAME STATUS AGE\n%s Active 39h\n' "$3" ;; *) exit 1 ;; esac
fi
if [[ "$1 $2" == 'apply -f' && "${3:-}" == '-' ]]; then
  input=$(cat)
  if [[ "$input" == *'name: ldap-password-rotator'* ]]; then
    printf '%s\n' 'APPLIED ldap-password-rotator' >> "$KUBECTL_LOG"
    printf '%s\n' "$input" > "$TEST_ROOT/ldap-rendered.yaml"
  fi
fi
if [[ "$1 $2" == 'apply -f' && "${3:-}" == *"${FAIL_MANIFEST:-__no_failure__}"* ]]; then exit 1; fi
exit 0
STUB
  cat > "$TEST_ROOT/bin/helm" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$HELM_LOG"
STUB
  chmod +x "$TEST_ROOT/bin/kubectl" "$TEST_ROOT/bin/helm"
  export PATH="$TEST_ROOT/bin:$PATH"
  unset -f kubectl
  _kubectl() { while [[ "${1:-}" == --no-exit ]]; do shift; done; command kubectl "$@"; }
  _helm() { command helm "$@"; }
  [ "$(command -v kubectl)" = "$TEST_ROOT/bin/kubectl" ]
  [ "$(command -v helm)" = "$TEST_ROOT/bin/helm" ]
  grep -Fx 'clusters: []' "$KUBECONFIG"
  grep -Fx 'current-context: ""' "$KUBECONFIG"
  cp "$SCRIPT_DIR/plugins/observability.sh" "$TEST_ROOT/plugins/observability.sh"
  cp "$SCRIPT_DIR/plugins/ldap.sh" "$TEST_ROOT/plugins/ldap.sh"
  cp "$SCRIPT_DIR/plugins/vault.sh" "$TEST_ROOT/plugins/vault.sh"
  cp "$SCRIPT_DIR/plugins/eso.sh" "$TEST_ROOT/plugins/eso.sh"
  # Keep the actual apply functions while isolating Vault from all external state.
  cat >> "$TEST_ROOT/plugins/observability.sh" <<'STUB'
_vault_login() { :; }
_vault_exec() { :; }
_vault_configure_secret_writer_role() { :; }
STUB
  export PLUGINS_DIR="$TEST_ROOT/plugins"
  argocd_sync_webhook_token_secret() { :; }
  argocd_sync_app_rebuild_secret() { :; }
  argocd_sync_git_writer_secret() { :; }
  argocd_sync_notifications_slack_secret() { :; }
}

assert_no_rotation() {
  if grep -E '(^| )create (job|jobs)( |$)|(^| )delete (cronjob|cronjobs)( |/|$)' "$KUBECTL_LOG"; then return 1; fi
  if grep -E '(^| )(install|upgrade)( |$)' "$HELM_LOG"; then return 1; fi
}

@test "platform-ops rotators: applies all three checkout manifests without running rotations" {
  run deploy_argocd_platform_ops
  [ "$status" -eq 0 ]
  [[ "$output" == *'ArgoCD rotator: applied'* ]]
  [[ "$output" == *'Grafana rotator: applied'* ]]
  [[ "$output" == *'LDAP rotator: applied'* ]]
  grep -F 'apply -f ' "$KUBECTL_LOG" | grep -F '/argocd-credential-rotator.yaml'
  grep -F 'apply -f ' "$KUBECTL_LOG" | grep -F '/grafana-credential-rotator.yaml'
  grep -Fx 'APPLIED ldap-password-rotator' "$KUBECTL_LOG"
  assert_no_rotation
}

@test "platform-ops rotators: missing monitoring skips Grafana and continues with LDAP" {
  export ABSENT_NAMESPACE=monitoring
  run deploy_argocd_platform_ops
  [ "$status" -eq 0 ]
  [ "$(grep -c 'Grafana rotator: skipped (namespace monitoring absent)' <<< "$output")" -eq 1 ]
  [[ "$output" == *'LDAP rotator: applied'* ]]
  run grep -F '/grafana-credential-rotator.yaml' "$KUBECTL_LOG"
  [ "$status" -eq 1 ]
  grep -Fx 'APPLIED ldap-password-rotator' "$KUBECTL_LOG"
  assert_no_rotation
}

@test "platform-ops rotators: missing LDAP namespace or disabled LDAP skips only LDAP" {
  export ABSENT_NAMESPACE=identity
  run deploy_argocd_platform_ops
  [ "$status" -eq 0 ]
  [ "$(grep -c 'LDAP rotator: skipped (namespace identity absent)' <<< "$output")" -eq 1 ]
  [[ "$output" == *'Grafana rotator: applied'* ]]
  run grep -Fx 'APPLIED ldap-password-rotator' "$KUBECTL_LOG"
  [ "$status" -eq 1 ]
  export ABSENT_NAMESPACE='' LDAP_ROTATOR_ENABLED=0
  run deploy_argocd_platform_ops
  [ "$status" -eq 0 ]
  [ "$(grep -c 'LDAP rotator: skipped (disabled)' <<< "$output")" -eq 1 ]
  run grep -Fx 'APPLIED ldap-password-rotator' "$KUBECTL_LOG"
  [ "$status" -eq 1 ]
  assert_no_rotation
}

@test "platform-ops rotators: missing function after plugin load is an error" {
  printf '\nunset -f _observability_apply_grafana_rotator\n' >> "$PLUGINS_DIR/observability.sh"
  run deploy_argocd_platform_ops
  [ "$status" -ne 0 ]
  [[ "$output" == *'rotator apply function _observability_apply_grafana_rotator is not defined'* ]]
  [[ "$output" == *'Grafana rotator: failed'* ]]
  [[ "$output" == *'LDAP rotator: applied'* ]]
  assert_no_rotation
}

@test "platform-ops rotators: failed apply reports failure and continues" {
  export FAIL_MANIFEST=grafana-credential-rotator.yaml
  run deploy_argocd_platform_ops
  [ "$status" -ne 0 ]
  [[ "$output" == *'Grafana rotator: failed'* ]]
  [[ "$output" == *'LDAP rotator: applied'* ]]
  assert_no_rotation
}

@test "platform-ops rotators: Vault role failure reports failed rotators and continues" {
  printf '\n_vault_configure_secret_writer_role() { return 1; }\n' >> "$PLUGINS_DIR/observability.sh"
  run deploy_argocd_platform_ops
  [ "$status" -ne 0 ]
  [[ "$output" == *'ArgoCD rotator: failed'* ]]
  [[ "$output" == *'Grafana rotator: failed'* ]]
  [[ "$output" == *'LDAP rotator: applied'* ]]
  assert_no_rotation
}

@test "platform-ops rotators: LDAP CronJob is rendered with the hub Vault address" {
  # Live identity/ldap-password-rotator on m5-air.local, 2026-11-01: VAULT_NAMESPACE=secrets, VAULT_ADDR=http://vault.secrets.svc:8200
  unset VAULT_NS VAULT_ADDR VAULT_NAMESPACE
  run deploy_argocd_platform_ops
  [ "$status" -eq 0 ]
  grep -A1 -- '- name: VAULT_ADDR' "$TEST_ROOT/ldap-rendered.yaml" | grep -F 'http://vault.secrets.svc:8200'
  grep -A1 -- '- name: VAULT_NAMESPACE' "$TEST_ROOT/ldap-rendered.yaml" | grep -F '"secrets"'
}
