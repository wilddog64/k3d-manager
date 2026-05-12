#!/usr/bin/env bats

setup() {
  source "${BATS_TEST_DIRNAME}/../test_helpers.bash"
  init_test_env
  source "${BATS_TEST_DIRNAME}/../../plugins/argocd.sh"
}

@test "deploy_argocd --help shows usage" {
  run deploy_argocd --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: deploy_argocd"* ]]
}

@test "deploy_argocd skips when CLUSTER_ROLE=app" {
  CLUSTER_ROLE=app run deploy_argocd
  [ "$status" -eq 0 ]
  [[ "$output" == *"CLUSTER_ROLE=app"* ]]
}

@test "deploy_argocd_bootstrap --help shows usage" {
  run deploy_argocd_bootstrap -h
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: deploy_argocd_bootstrap"* ]]
}

@test "deploy_argocd_bootstrap no-ops when skipping all resources" {
  : > "$KUBECTL_LOG"
  run deploy_argocd_bootstrap --skip-applicationsets --skip-appproject
  [ "$status" -eq 0 ]
  read_lines "$KUBECTL_LOG" calls
  [ "${calls[0]}" = "get ns cicd" ]
  [ "${calls[1]}" = "-n cicd get deployment argocd-server" ]
}

@test "_argocd_bootstrap_is_ready returns 0 when AppProject and ApplicationSets exist" {
  : > "$KUBECTL_LOG"
  KUBECTL_EXIT_CODES=()
  run _argocd_bootstrap_is_ready
  [ "$status" -eq 0 ]
  read_lines "$KUBECTL_LOG" calls
  [ "${calls[0]}" = "-n cicd get appproject/platform" ]
  [ "${calls[1]}" = "-n cicd get applicationset/demo-rollout" ]
  [ "${calls[2]}" = "-n cicd get applicationset/platform-helm" ]
  [ "${calls[3]}" = "-n cicd get applicationset/services-git" ]
}

@test "_argocd_bootstrap_is_ready returns 1 when an ApplicationSet is missing" {
  : > "$KUBECTL_LOG"
  KUBECTL_EXIT_CODES=(0 0 0 1)
  run _argocd_bootstrap_is_ready
  [ "$status" -eq 1 ]
  read_lines "$KUBECTL_LOG" calls
  [ "${calls[0]}" = "-n cicd get appproject/platform" ]
  [ "${calls[1]}" = "-n cicd get applicationset/demo-rollout" ]
  [ "${calls[2]}" = "-n cicd get applicationset/platform-helm" ]
  [ "${calls[3]}" = "-n cicd get applicationset/services-git" ]
}

@test "_argocd_ensure_logged_in uses plaintext non-interactive login" {
  : > "$KUBECTL_LOG"
  : > "$ARGOCD_LOG"
  run _argocd_ensure_logged_in
  [ "$status" -eq 0 ]
  read_lines "$KUBECTL_LOG" kubectl_calls
  [ "${kubectl_calls[0]}" = "get secret argocd-initial-admin-secret -n cicd -o jsonpath={.data.password}" ]
  [ "${kubectl_calls[1]}" = "port-forward svc/argocd-server -n cicd 8080:443" ]
  read_lines "$ARGOCD_LOG" argocd_calls
  [[ "${argocd_calls[0]}" == "account get-context --server localhost:8080" ]]
  [[ "${argocd_calls[1]}" == *"login localhost:8080 --username admin --stdin --plaintext --skip-test-tls --insecure --grpc-web"* ]]
}

@test "_argocd_wait_for_local_port_forward returns 0 when healthz is reachable" {
  local port_forward_log="${BATS_TEST_TMPDIR}/argocd-pf.log"
  : > "$port_forward_log"
  curl() { return 0; }
  sleep() { return 0; }
  export -f curl sleep
  run _argocd_wait_for_local_port_forward "$port_forward_log" 1
  [ "$status" -eq 0 ]
}

@test "_argocd_wait_for_local_port_forward returns 1 when healthz never becomes reachable" {
  local port_forward_log="${BATS_TEST_TMPDIR}/argocd-pf.log"
  printf 'port-forward boom\n' > "$port_forward_log"
  curl() { return 1; }
  sleep() { return 0; }
  export -f curl sleep
  run _argocd_wait_for_local_port_forward "$port_forward_log" 1
  [ "$status" -eq 1 ]
  [[ "$output" == *"Argo CD did not become reachable on localhost:8080"* ]]
  [[ "$output" == *"port-forward boom"* ]]
}

@test "_argocd_write_port_forward_wrapper includes a self-healing loop" {
  run grep -F 'function _argocd_write_port_forward_wrapper()' "$BATS_TEST_DIRNAME/../../plugins/argocd.sh"
  [ "$status" -eq 0 ]
  run grep -F 'template_path="${SCRIPT_DIR}/etc/argocd/port-forward-wrapper.sh.tmpl"' "$BATS_TEST_DIRNAME/../../plugins/argocd.sh"
  [ "$status" -eq 0 ]
  run grep -F 'healthz did not become reachable — restarting' "$BATS_TEST_DIRNAME/../../etc/argocd/port-forward-wrapper.sh.tmpl"
  [ "$status" -eq 0 ]
  run grep -F 'healthz lost — restarting' "$BATS_TEST_DIRNAME/../../etc/argocd/port-forward-wrapper.sh.tmpl"
  [ "$status" -eq 0 ]
  run grep -F 'STARTUP_TIMEOUT=${STARTUP_TIMEOUT}' "$BATS_TEST_DIRNAME/../../etc/argocd/port-forward-wrapper.sh.tmpl"
  [ "$status" -eq 0 ]
}

@test "_argocd_write_browser_https_wrapper includes a canonical HTTPS listener" {
  run grep -F 'function _argocd_write_browser_https_wrapper()' "$BATS_TEST_DIRNAME/../../plugins/argocd.sh"
  [ "$status" -eq 0 ]
  run grep -F 'template_path="${SCRIPT_DIR}/etc/argocd/browser-https-wrapper.sh.tmpl"' "$BATS_TEST_DIRNAME/../../plugins/argocd.sh"
  [ "$status" -eq 0 ]
  run grep -F 'TCP-LISTEN:${LOCAL_PORT},fork,reuseaddr,bind=${LOCAL_HOST} TCP:${UPSTREAM_HOST}:${UPSTREAM_PORT}' "$BATS_TEST_DIRNAME/../../etc/argocd/browser-https-wrapper.sh.tmpl"
  [ "$status" -eq 0 ]
  run grep -F 'healthz lost — restarting' "$BATS_TEST_DIRNAME/../../etc/argocd/browser-https-wrapper.sh.tmpl"
  [ "$status" -eq 0 ]
}

@test "_argocd_deploy_appproject fails when template missing" {
  local original_config="$ARGOCD_CONFIG_DIR"
  ARGOCD_CONFIG_DIR="$BATS_TEST_TMPDIR/argocd-empty"
  mkdir -p "$ARGOCD_CONFIG_DIR/projects"
  trap 'ARGOCD_CONFIG_DIR="$original_config"' RETURN
  run _argocd_deploy_appproject
  [ "$status" -ne 0 ]
  [[ "$output" == *"AppProject file not found"* ]]
}

@test "ARGOCD_NAMESPACE defaults to cicd" {
  [ "$ARGOCD_NAMESPACE" = "cicd" ]
}
