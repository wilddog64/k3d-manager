#!/usr/bin/env bats

setup() {
  source "${BATS_TEST_DIRNAME}/../test_helpers.bash"
  init_test_env
  source "${BATS_TEST_DIRNAME}/../../plugins/jenkins.sh"
  export_stubs
}

@test "Namespace creation" {
  KUBECTL_EXIT_CODES=(1 0)
  run _create_jenkins_namespace test-ns
  [ "$status" -eq 0 ]
  read_lines "$KUBECTL_LOG" kubectl_calls
  [[ "${kubectl_calls[1]}" == apply* ]]
  [[ "$output" == *"Namespace test-ns created"* ]]
}

@test "PV/PVC setup" {
  KUBECTL_EXIT_CODES=(1 0)
  jhp="$SCRIPT_DIR/storage/jenkins_home"
  echo "JENKINS_HOME_PATH=$jhp"
  rm -rf "$jhp"
  run _create_jenkins_pv_pvc test-ns
  [ "$status" -eq 0 ]
  [[ -d "$jhp" ]]
  read_lines "$KUBECTL_LOG" kubectl_calls
  [[ "${kubectl_calls[1]}" == apply* ]]
}

@test "_create_jenkins_admin_vault_policy stores secret without logging password" {
  _vault_policy_exists() { return 1; }
  _kubectl() {
    local cmd="$*"
    if [[ "$cmd" == *"vault read -field=password sys/policies/password/jenkins-admin/generate"* ]]; then
      echo "$cmd" >> "$KUBECTL_LOG"
      echo "s3cr3t"
      return 0
    fi
    if [[ "$cmd" == *password=* ]]; then
      cmd="${cmd%%password=*}password=***"
    fi
    echo "$cmd" >> "$KUBECTL_LOG"
    return 0
  }
  export -f _vault_policy_exists
  export -f _kubectl
  _no_trace() {
    local cmd="$*"
    local script
    script=$(cat)
    if [[ "$script" == *password=* ]]; then
      script="${script/password=*/password=***}"
    fi
    echo "$cmd" >> "$KUBECTL_LOG"
    echo "$script" >> "$KUBECTL_LOG"
    echo "$script" | _kubectl "$@"
  }
  export -f _no_trace
  _cleanup_on_success() { rm -f "$1"; }
  export -f _cleanup_on_success

  run _create_jenkins_admin_vault_policy vault
  [ "$status" -eq 0 ]
  grep -q 'vault kv put secret/eso/jenkins-admin' "$KUBECTL_LOG"
  grep -q 'username=jenkins-admin' "$KUBECTL_LOG"
  grep -Fq 'password=***' "$KUBECTL_LOG"
  ! grep -q 's3cr3t' "$KUBECTL_LOG"
  [[ ! -f jenkins-admin.hcl ]]
}

@test "_create_jenkins_vault_ad_policy creates policies" {
  _vault_policy_exists() { return 1; }
  _vault_policy() { return 1; }
  _kubectl() {
    echo "$*" >> "$KUBECTL_LOG"
    return 0
  }
  export -f _vault_policy_exists
  export -f _vault_policy
  export -f _kubectl

  run _create_jenkins_vault_ad_policy vault jenkins
  [ "$status" -eq 0 ]
  grep -q 'vault policy write jenkins-jcasc-read' "$KUBECTL_LOG"
  grep -q 'vault write auth/kubernetes/role/jenkins-jcasc-reader' "$KUBECTL_LOG"
  grep -q 'vault policy write jenkins-jcasc-write' "$KUBECTL_LOG"
  grep -q 'vault write auth/kubernetes/role/jenkins-jcasc-writer' "$KUBECTL_LOG"
  ! grep -q 'vault kv put' "$KUBECTL_LOG"
  ! grep -q 'password=' "$KUBECTL_LOG"
}

@test "_ensure_jenkins_cert sets up PKI and TLS secret" {
  _kubectl() {
    local cmd="$*"
    echo "$cmd" >> "$KUBECTL_LOG"
    if [[ "$cmd" == *"get secret jenkins-cert"* ]]; then
      return 1
    fi
    if [[ "$cmd" == *"vault secrets list"* ]]; then
      return 1
    fi
    if [[ "$cmd" == *"vault write -format=json pki/issue/jenkins"* ]]; then
      cat <<'JSON'
{"data":{"certificate":"CERT","private_key":"KEY"}}
JSON
      return 0
    fi
    return 0
  }
  export -f _kubectl

  run _ensure_jenkins_cert vault
  [ "$status" -eq 0 ]
  grep -q 'vault secrets enable pki' "$KUBECTL_LOG"
  grep -q 'vault write pki/roles/jenkins' "$KUBECTL_LOG"
  grep -q 'vault write -format=json pki/issue/jenkins' "$KUBECTL_LOG"
  grep -q 'create secret tls jenkins-cert' "$KUBECTL_LOG"
}

@test "Full deployment" {
  CALLS_LOG="$BATS_TEST_TMPDIR/calls.log"
  : > "$CALLS_LOG"
  deploy_vault() { :; }
  _create_jenkins_admin_vault_policy() { :; }
  _create_jenkins_vault_ad_policy() { :; }
  _create_jenkins_namespace() { echo "_create_jenkins_namespace" >> "$CALLS_LOG"; }
  _ensure_jenkins_cert() { echo "_ensure_jenkins_cert" >> "$CALLS_LOG"; }
  _deploy_jenkins() { echo "_deploy_jenkins" >> "$CALLS_LOG"; }
  run deploy_jenkins sample-ns
  [ "$status" -eq 0 ]
  read_lines "$CALLS_LOG" calls
  [ "${#calls[@]}" -eq 3 ]
  [ "${calls[0]}" = "_create_jenkins_namespace" ]
  [ "${calls[1]}" = "_ensure_jenkins_cert" ]
  [ "${calls[2]}" = "_deploy_jenkins" ]
}

@test "VirtualService references Jenkins gateway" {
  run grep -q 'istio-system/jenkins-gw' "$SCRIPT_DIR/etc/jenkins/virtualservice.yaml"
  [ "$status" -eq 0 ]
}

@test "_deploy_jenkins applies Istio resources" {
  run _deploy_jenkins sample-ns
  [ "$status" -eq 0 ]
  read_lines "$KUBECTL_LOG" kubectl_calls
  expected_gw="apply -n istio-system --dry-run=client -f $SCRIPT_DIR/etc/jenkins/gateway.yaml"
  expected_gw_apply="apply -n istio-system -f -"
  expected_vs="apply -n sample-ns --dry-run=client -f $SCRIPT_DIR/etc/jenkins/virtualservice.yaml"
  expected_vs_apply="apply -n sample-ns -f -"
  expected_dr="apply -n sample-ns --dry-run=client -f $SCRIPT_DIR/etc/jenkins/destinationrule.yaml"
  expected_dr_apply="apply -n sample-ns -f -"
  [ "${kubectl_calls[0]}" = "$expected_gw" ]
  [ "${kubectl_calls[1]}" = "$expected_gw_apply" ]
  [ "${kubectl_calls[2]}" = "$expected_vs" ]
  [ "${kubectl_calls[3]}" = "$expected_vs_apply" ]
  [ "${kubectl_calls[4]}" = "$expected_dr" ]
  [ "${kubectl_calls[5]}" = "$expected_dr_apply" ]
}
