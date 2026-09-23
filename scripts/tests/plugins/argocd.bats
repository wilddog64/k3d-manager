#!/usr/bin/env bats

setup() {
  source "${BATS_TEST_DIRNAME}/../test_helpers.bash"
  init_test_env
  source "${BATS_TEST_DIRNAME}/../../plugins/argocd.sh"
}

@test "browser TLS defaults to the k3s-aws provider-scoped state dir" {
  export HOME="${BATS_TEST_TMPDIR}/home"
  unset ARGOCD_BROWSER_TLS_DIR ARGOCD_BROWSER_TLS_CERT_FILE ARGOCD_BROWSER_TLS_KEY_FILE ARGOCD_BROWSER_TLS_CA_FILE
  export CLUSTER_PROVIDER="k3s-aws"
  source "${BATS_TEST_DIRNAME}/../../plugins/argocd.sh"
  local expected_dir
  expected_dir="$(_acg_provider_state_dir "k3s-aws")/argocd-browser-https-tls"
  [ "$ARGOCD_BROWSER_TLS_DIR" = "$expected_dir" ]
}

@test "browser TLS dirs differ between k3s-aws and k3s-hostinger" {
  export HOME="${BATS_TEST_TMPDIR}/home"
  unset ARGOCD_BROWSER_TLS_DIR ARGOCD_BROWSER_TLS_CERT_FILE ARGOCD_BROWSER_TLS_KEY_FILE ARGOCD_BROWSER_TLS_CA_FILE
  export CLUSTER_PROVIDER="k3s-aws"
  source "${BATS_TEST_DIRNAME}/../../plugins/argocd.sh"
  local aws_dir="$ARGOCD_BROWSER_TLS_DIR"
  unset ARGOCD_BROWSER_TLS_DIR ARGOCD_BROWSER_TLS_CERT_FILE ARGOCD_BROWSER_TLS_KEY_FILE ARGOCD_BROWSER_TLS_CA_FILE
  export CLUSTER_PROVIDER="k3s-hostinger"
  source "${BATS_TEST_DIRNAME}/../../plugins/argocd.sh"
  [ "$ARGOCD_BROWSER_TLS_DIR" != "$aws_dir" ]
}

@test "explicit browser TLS dir overrides the provider-scoped default" {
  export HOME="${BATS_TEST_TMPDIR}/home"
  export CLUSTER_PROVIDER="k3s-aws"
  export ARGOCD_BROWSER_TLS_DIR="/tmp/custom"
  unset ARGOCD_BROWSER_TLS_CERT_FILE ARGOCD_BROWSER_TLS_KEY_FILE ARGOCD_BROWSER_TLS_CA_FILE
  source "${BATS_TEST_DIRNAME}/../../plugins/argocd.sh"
  [ "$ARGOCD_BROWSER_TLS_DIR" = "/tmp/custom" ]
}

@test "browser TLS files are inside the selected directory" {
  export HOME="${BATS_TEST_TMPDIR}/home"
  unset ARGOCD_BROWSER_TLS_DIR ARGOCD_BROWSER_TLS_CERT_FILE ARGOCD_BROWSER_TLS_KEY_FILE ARGOCD_BROWSER_TLS_CA_FILE
  export CLUSTER_PROVIDER="k3s-hostinger"
  source "${BATS_TEST_DIRNAME}/../../plugins/argocd.sh"
  [[ "$ARGOCD_BROWSER_TLS_CERT_FILE" == "$ARGOCD_BROWSER_TLS_DIR/"* ]]
  [[ "$ARGOCD_BROWSER_TLS_KEY_FILE" == "$ARGOCD_BROWSER_TLS_DIR/"* ]]
  [[ "$ARGOCD_BROWSER_TLS_CA_FILE" == "$ARGOCD_BROWSER_TLS_DIR/"* ]]
}

@test "deploy_argocd --help shows usage" {
  run deploy_argocd --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: deploy_argocd"* ]]
}

@test "ArgoCD credential rotator is namespaced and least privilege" {
  local manifest="${BATS_TEST_DIRNAME}/../../etc/argocd/platform-ops/argocd-credential-rotator.yaml"
  run grep -F -- 'kind: CronJob' "${manifest}"
  [ "$status" -eq 0 ]
  run grep -F -- 'namespace: cicd' "${manifest}"
  [ "$status" -eq 0 ]
  run grep -F -- 'resourceNames: ["argocd-secret"]' "${manifest}"
  [ "$status" -eq 0 ]
  run grep -F -- 'resourceNames: ["argocd-admin-secret"]' "${manifest}"
  [ "$status" -eq 0 ]
  run grep -F -- 'image: docker.io/alpine/k8s:1.31.4' "${manifest}"
  [ "$status" -eq 0 ]
  run grep -F -- 'schedule: "0 0 1 * *"' "${manifest}"
  [ "$status" -eq 0 ]
  run grep -F -- 'argocd account bcrypt' "${manifest}"
  [ "$status" -eq 0 ]
  run grep -F -- 'cluster-admin' "${manifest}"
  [ "$status" -ne 0 ]
}

@test "ArgoCD rotator bcrypt is runtime-correct and pod excludes istio sidecar" {
  local manifest="${BATS_TEST_DIRNAME}/../../etc/argocd/platform-ops/argocd-credential-rotator.yaml"
  # newline-fed stdin (no trailing newline → argocd account bcrypt fatal EOF)
  run grep -F -- "printf '%s\\n' \"\$new\"" "${manifest}"
  [ "$status" -eq 0 ]
  # strip the 'Password: ' prompt argocd prints to stdout (else the hash is malformed)
  run grep -F -- "sed 's/^Password: //'" "${manifest}"
  [ "$status" -eq 0 ]
  # never pass the password via argv (OWASP A02)
  run grep -F -- 'account bcrypt --password' "${manifest}"
  [ "$status" -ne 0 ]
  # CronJob in cicd (istio-injection=enabled) must opt the pod out of the sidecar mesh
  run grep -F -- 'sidecar.istio.io/inject: "false"' "${manifest}"
  [ "$status" -eq 0 ]
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

@test "deploy_argocd_applicationsets --help shows usage" {
  run deploy_argocd_applicationsets --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: deploy_argocd_applicationsets"* ]]
}

@test "deploy_argocd_applicationsets reapplies then verifies the values-branch pin" {
  _argocd_deploy_applicationsets() { echo "REAPPLY"; K3D_MANAGER_BRANCH="test-branch"; export K3D_MANAGER_BRANCH; }
  argocd_check_values_branch() { echo "VERIFY:$1"; }
  run deploy_argocd_applicationsets
  [ "$status" -eq 0 ]
  [[ "$output" == *"REAPPLY"* ]]
  [[ "$output" == *"VERIFY:test-branch"* ]]
}

@test "deploy_argocd_applicationsets --no-verify skips the values-branch check" {
  _argocd_deploy_applicationsets() { echo "REAPPLY"; }
  argocd_check_values_branch() { echo "VERIFY-SHOULD-NOT-RUN"; }
  run deploy_argocd_applicationsets --no-verify
  [ "$status" -eq 0 ]
  [[ "$output" == *"REAPPLY"* ]]
  [[ "$output" != *"VERIFY-SHOULD-NOT-RUN"* ]]
}

@test "deploy_argocd_applicationsets rejects unknown options" {
  run deploy_argocd_applicationsets --bogus
  [ "$status" -ne 0 ]
  [[ "$output" == *"Unknown option"* ]]
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
  curl() { return 1; }
  sleep() { :; }
  export -f curl sleep
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
  run declare -F _argocd_write_port_forward_wrapper
  [ "$status" -eq 0 ]
  run grep -Eq 'template_path=.*port-forward-wrapper\.sh\.tmpl' "$BATS_TEST_DIRNAME/../../plugins/argocd.sh"
  [ "$status" -eq 0 ]
  run grep -F 'healthz did not become reachable — restarting' "$BATS_TEST_DIRNAME/../../etc/argocd/port-forward-wrapper.sh.tmpl"
  [ "$status" -eq 0 ]
  run grep -F 'healthz lost — restarting' "$BATS_TEST_DIRNAME/../../etc/argocd/port-forward-wrapper.sh.tmpl"
  [ "$status" -eq 0 ]
  run grep -Fq -- 'still in use — clearing stale listener' "$BATS_TEST_DIRNAME/../../etc/argocd/port-forward-wrapper.sh.tmpl"
  [ "$status" -eq 0 ]
  run grep -F 'STARTUP_TIMEOUT=${STARTUP_TIMEOUT}' "$BATS_TEST_DIRNAME/../../etc/argocd/port-forward-wrapper.sh.tmpl"
  [ "$status" -eq 0 ]
  run grep -F 'HEALTH_FAILURE_THRESHOLD=6' "$BATS_TEST_DIRNAME/../../etc/argocd/port-forward-wrapper.sh.tmpl"
  [ "$status" -eq 0 ]
  run grep -F 'RESTART_DELAY=2' "$BATS_TEST_DIRNAME/../../etc/argocd/port-forward-wrapper.sh.tmpl"
  [ "$status" -eq 0 ]
  run grep -F 'ADDRESS=${ADDRESS}' "$BATS_TEST_DIRNAME/../../etc/argocd/port-forward-wrapper.sh.tmpl"
  [ "$status" -eq 0 ]
  run grep -F 'LOG_TAG=${LOG_TAG}' "$BATS_TEST_DIRNAME/../../etc/argocd/port-forward-wrapper.sh.tmpl"
  [ "$status" -eq 0 ]
  run grep -Fq -- 'healthz check failed' "$BATS_TEST_DIRNAME/../../etc/argocd/port-forward-wrapper.sh.tmpl"
  [ "$status" -eq 0 ]
  run grep -F 'KUBECONFIG_FILE=${KUBECONFIG_FILE}' "$BATS_TEST_DIRNAME/../../etc/argocd/port-forward-wrapper.sh.tmpl"
  [ "$status" -eq 0 ]
  run grep -Eq -- '-n "\$\{KUBECONFIG_FILE\}"' "$BATS_TEST_DIRNAME/../../etc/argocd/port-forward-wrapper.sh.tmpl"
  [ "$status" -eq 0 ]
}

@test "_argocd_write_port_forward_wrapper falls back when the requested context is missing" {
  run grep -Eq 'config get-contexts .*\$\{CONTEXT\}' "$BATS_TEST_DIRNAME/../../etc/argocd/port-forward-wrapper.sh.tmpl"
  [ "$status" -eq 0 ]
  run grep -Eq '_current_context=.*config current-context' "$BATS_TEST_DIRNAME/../../etc/argocd/port-forward-wrapper.sh.tmpl"
  [ "$status" -eq 0 ]
  run grep -F 'falling back to kubeconfig default' "$BATS_TEST_DIRNAME/../../etc/argocd/port-forward-wrapper.sh.tmpl"
  [ "$status" -eq 0 ]
  run grep -F '_kubectl_context_arg=""' "$BATS_TEST_DIRNAME/../../etc/argocd/port-forward-wrapper.sh.tmpl"
  [ "$status" -eq 0 ]
  run grep -Eq 'port-forward --address="\$\{ADDRESS\}" .*\$\{LOCAL_PORT\}:\$\{REMOTE_PORT\}' "$BATS_TEST_DIRNAME/../../etc/argocd/port-forward-wrapper.sh.tmpl"
  [ "$status" -eq 0 ]
}

@test "port-forward wrapper scopes listener sweeps and refreshes context" {
  local template="$BATS_TEST_DIRNAME/../../etc/argocd/port-forward-wrapper.sh.tmpl"
  run grep -F -c -- '-iTCP@"${ADDRESS}":"${LOCAL_PORT}"' "$template"
  [ "$status" -eq 0 ]
  [ "$output" -eq 2 ]
  run bash -c 'grep -c -- '\''-iTCP:"${LOCAL_PORT}"'\'' "$1" || true' _ "$template"
  [ "$status" -eq 0 ]
  [ "$output" -eq 0 ]
  run bash -c 'grep -cF '\''[argocd-pf]'\'' "$1" || true' _ "$template"
  [ "$status" -eq 0 ]
  [ "$output" -eq 0 ]
  run grep -F '_resolve_kubectl_context()' "$template"
  [ "$status" -eq 0 ]
  run grep -nF 'while true; do' "$template"
  [ "$status" -eq 0 ]
  local loop_line="${output%%:*}"
  run grep -nF '   _resolve_kubectl_context' "$template"
  [ "$status" -eq 0 ]
  local call_line="${output%%:*}"
  [ "$call_line" -gt "$loop_line" ]
  run grep -F 'using current-context' "$template"
  [ "$status" -eq 0 ]
  run grep -Eq 'local address=.*127\.0\.0\.1|local address=' scripts/plugins/argocd.sh
  [ "$status" -eq 0 ]
  run grep -F 'q_address' scripts/plugins/argocd.sh
  [ "$status" -eq 0 ]
  run grep -F 'q_log_tag' scripts/plugins/argocd.sh
  [ "$status" -eq 0 ]
  run grep -F 'ADDRESS="$q_address"' scripts/plugins/argocd.sh
  [ "$status" -eq 0 ]
  run grep -F 'LOG_TAG="$q_log_tag"' scripts/plugins/argocd.sh
  [ "$status" -eq 0 ]
}

@test "_argocd_write_browser_https_wrapper includes a canonical HTTPS listener" {
  run declare -F _argocd_write_browser_https_wrapper
  [ "$status" -eq 0 ]
  run declare -F _argocd_issue_browser_tls_material
  [ "$status" -eq 0 ]
  run grep -Eq 'template_path=.*browser-https-wrapper\.sh\.tmpl' "$BATS_TEST_DIRNAME/../../plugins/argocd.sh"
  [ "$status" -eq 0 ]
  run grep -Eq 'OPENSSL-LISTEN:.*cert=\$\{CERT_FILE\},key=\$\{KEY_FILE\},verify=0 TCP:' "$BATS_TEST_DIRNAME/../../etc/argocd/browser-https-wrapper.sh.tmpl"
  [ "$status" -eq 0 ]
  run grep -F 'healthz lost — restarting' "$BATS_TEST_DIRNAME/../../etc/argocd/browser-https-wrapper.sh.tmpl"
  [ "$status" -eq 0 ]
}

@test "_argocd_issue_browser_tls_material writes Vault-issued TLS files" {
  local tls_dir="${BATS_TEST_TMPDIR}/browser-tls"
  mkdir -p "$tls_dir"

  _vault_upsert_pki_role() {
    echo "role $*" >> "${BATS_TEST_TMPDIR}/vault.log"
    return 0
  }

  _vault_login() {
    echo "login $*" >> "${BATS_TEST_TMPDIR}/vault.log"
    return 0
  }

  _vault_exec() {
    cat <<'JSON'
{"data":{"certificate":"-----BEGIN CERTIFICATE-----\nMIIB\n-----END CERTIFICATE-----","private_key":"-----BEGIN PRIVATE KEY-----\nMIIE\n-----END PRIVATE KEY-----","issuing_ca":"-----BEGIN CERTIFICATE-----\nCA==\n-----END CERTIFICATE-----"}}
JSON
  }

  export -f _vault_login _vault_upsert_pki_role _vault_exec

  run _argocd_issue_browser_tls_material "$tls_dir" "vault" "argocd" "pki" "argocd-browser-tls" "argocd.shopping-cart.local" "24h"
  [ "$status" -eq 0 ]
  [ -s "${tls_dir}/fullchain.crt" ]
  [ -s "${tls_dir}/tls.crt" ]
  [ -s "${tls_dir}/tls.key" ]
  [ -s "${tls_dir}/ca.crt" ]
  run grep -F 'login vault argocd' "${BATS_TEST_TMPDIR}/vault.log"
  [ "$status" -eq 0 ]
  run grep -F 'role vault argocd pki argocd-browser-tls 24h shopping-cart.local true' "${BATS_TEST_TMPDIR}/vault.log"
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

@test "register_app_cluster: permits token-less in-cluster registration" {
  RENDERED_FILE="${BATS_TEST_TMPDIR}/in-cluster-secret.yaml"
  _kubectl() {
    if [[ "$1" == "apply" && "$2" == "-f" ]]; then
      cp "$3" "$RENDERED_FILE"
    fi
  }
  _argocd_set_active_app_cluster() { :; }
  export RENDERED_FILE
  export -f _kubectl _argocd_set_active_app_cluster
  unset ARGOCD_APP_CLUSTER_TOKEN
  ARGOCD_APP_CLUSTER_SERVER=https://kubernetes.default.svc \
    ARGOCD_APP_CLUSTER_NAME=ubuntu-k3s \
    ARGOCD_APP_CLUSTER_SECRET_NAME=ubuntu-k3s-app-cluster \
    ARGOCD_NAMESPACE=cicd run register_app_cluster
  [ "$status" -eq 0 ]
  run grep -A1 '^  config: |' "$RENDERED_FILE"
  [ "$status" -eq 0 ]
  [[ "$output" == *"    {}"* ]]
  run grep -F bearerToken "$RENDERED_FILE"
  [ "$status" -ne 0 ]
}

@test "register_app_cluster: in-cluster secret does not match platform-helm" {
  RENDERED_FILE="${BATS_TEST_TMPDIR}/in-cluster-platform-secret.yaml"
  _kubectl() {
    if [[ "$1" == "apply" && "$2" == "-f" ]]; then
      cp "$3" "$RENDERED_FILE"
    fi
  }
  _argocd_set_active_app_cluster() { :; }
  export RENDERED_FILE
  export -f _kubectl _argocd_set_active_app_cluster
  unset ARGOCD_APP_CLUSTER_TOKEN
  export ARGOCD_APP_CLUSTER_ENVIRONMENT=infra
  ARGOCD_APP_CLUSTER_SERVER=https://kubernetes.default.svc run register_app_cluster
  [ "$status" -eq 0 ]
  run grep -c '^    environment:' "$RENDERED_FILE"
  [ "$output" = "0" ]
  run grep -c 'argocd-chart-version' "$RENDERED_FILE"
  [ "$output" = "0" ]
  run grep -c 'argocd-replicas' "$RENDERED_FILE"
  [ "$output" = "0" ]
  run grep -c '^    k3d-manager/managed:' "$RENDERED_FILE"
  [ "$output" = "1" ]
  run grep -c 'argocd.argoproj.io/secret-type: cluster' "$RENDERED_FILE"
  [ "$output" = "1" ]
  if command -v python3 >/dev/null 2>&1 && python3 -c 'import yaml' >/dev/null 2>&1; then
    run python3 -c 'import sys,yaml; yaml.safe_load(open(sys.argv[1]))' "$RENDERED_FILE"
    [ "$status" -eq 0 ]
  fi
}

@test "register_app_cluster: remote secret keeps platform-helm labels" {
  RENDERED_FILE="${BATS_TEST_TMPDIR}/remote-platform-secret.yaml"
  _kubectl() {
    if [[ "$1" == "apply" && "$2" == "-f" ]]; then
      cp "$3" "$RENDERED_FILE"
    fi
  }
  _argocd_set_active_app_cluster() { :; }
  export RENDERED_FILE
  export -f _kubectl _argocd_set_active_app_cluster
  unset ARGOCD_APP_CLUSTER_ENVIRONMENT
  ARGOCD_APP_CLUSTER_SERVER=https://remote.example.invalid \
    ARGOCD_APP_CLUSTER_TOKEN=dummy-token \
    ARGOCD_CHART_VERSION=9.9.9 run register_app_cluster
  [ "$status" -eq 0 ]
  run grep -c '^    environment: "dev"' "$RENDERED_FILE"
  [ "$output" = "1" ]
  run grep -c '^    argocd-chart-version: "9.9.9"' "$RENDERED_FILE"
  [ "$output" = "1" ]
  run grep -c '^    argocd-replicas: "2"' "$RENDERED_FILE"
  [ "$output" = "1" ]
  run grep -c '^    k3d-manager/managed:' "$RENDERED_FILE"
  [ "$output" = "1" ]
}

@test "register_app_cluster: requires a token for remote registrations" {
  unset ARGOCD_APP_CLUSTER_TOKEN
  ARGOCD_APP_CLUSTER_SERVER=https://remote.example.invalid run register_app_cluster
  [ "$status" -eq 1 ]
}

@test "ArgoCD Helm values substitute Keycloak OIDC settings" {
  local render_vars='$ARGOCD_PUBLIC_URL $ARGOCD_VIRTUALSERVICE_HOST $ARGOCD_SERVER_INSECURE $ARGOCD_LDAP_HOST $ARGOCD_LDAP_PORT $ARGOCD_LDAP_BIND_DN $ARGOCD_LDAP_USER_SEARCH_BASE $ARGOCD_LDAP_BASE_DN $ARGOCD_LDAP_GROUP_SEARCH_BASE $ARGOCD_RBAC_DEFAULT_POLICY $ARGOCD_RBAC_ADMIN_GROUP $ARGOCD_KEYCLOAK_REALM_URL $ARGOCD_KEYCLOAK_CLIENT_ID $ARGOCD_SERVER_REPLICAS $ARGOCD_REPO_SERVER_REPLICAS $ARGOCD_APPLICATIONSET_REPLICAS'
  local rendered

  run grep -F -- "envsubst '${render_vars}'" "${BATS_TEST_DIRNAME}/../../plugins/argocd.sh"
  [ "$status" -eq 0 ]

  rendered="$(envsubst "$render_vars" < "${ARGOCD_CONFIG_DIR}/values.yaml.tmpl")"
  [[ "$rendered" == *"url: ${ARGOCD_PUBLIC_URL}"* ]]
  [[ "$rendered" == *"domain: ${ARGOCD_VIRTUALSERVICE_HOST}"* ]]
  [[ "$rendered" == *"issuer: ${ARGOCD_KEYCLOAK_REALM_URL}"* ]]
  [[ "$rendered" == *"clientID: ${ARGOCD_KEYCLOAK_CLIENT_ID}"* ]]
  [[ "$rendered" != *'${ARGOCD_KEYCLOAK_REALM_URL}'* ]]
  [[ "$rendered" != *'${ARGOCD_KEYCLOAK_CLIENT_ID}'* ]]
}

@test "ArgoCD public URL override is passed to Helm independently of routing host" {
  export ARGOCD_PUBLIC_URL=https://argo.example.invalid
  export ARGOCD_VIRTUALSERVICE_HOST=argo.internal.invalid
  _helm() { printf '%s\n' "$@"; }
  _argocd_ensure_servicemonitors() { :; }
  run _argocd_helm_deploy_release 0 1
  [ "$status" -eq 0 ]
  [[ "$output" == *"configs.cm.url=https://argo.example.invalid"* ]]
  [[ "$output" != *"configs.cm.url=https://argo.internal.invalid"* ]]
}

@test "register_app_cluster: shopping-cart label defaults to false" {
  RENDERED_FILE="${BATS_TEST_TMPDIR}/shopping-cart-default.yaml"
  _kubectl() {
    if [[ "$1" == "apply" && "$2" == "-f" ]]; then
      cp "$3" "$RENDERED_FILE"
    fi
  }
  _argocd_set_active_app_cluster() { :; }
  export RENDERED_FILE
  export -f _kubectl _argocd_set_active_app_cluster
  unset ARGOCD_APP_CLUSTER_TOKEN ARGOCD_APP_CLUSTER_SHOPPING_CART
  ARGOCD_APP_CLUSTER_SERVER=https://kubernetes.default.svc run register_app_cluster
  [ "$status" -eq 0 ]
  run grep -c -- 'k3d-manager/shopping-cart: "false"' "$RENDERED_FILE"
  [ "$output" = "1" ]
}

@test "register_app_cluster: shopping-cart label opts in when explicitly true" {
  RENDERED_FILE="${BATS_TEST_TMPDIR}/shopping-cart-optin.yaml"
  _kubectl() {
    if [[ "$1" == "apply" && "$2" == "-f" ]]; then
      cp "$3" "$RENDERED_FILE"
    fi
  }
  _argocd_set_active_app_cluster() { :; }
  export RENDERED_FILE
  export -f _kubectl _argocd_set_active_app_cluster
  unset ARGOCD_APP_CLUSTER_TOKEN
  ARGOCD_APP_CLUSTER_SERVER=https://kubernetes.default.svc \
    ARGOCD_APP_CLUSTER_SHOPPING_CART=true run register_app_cluster
  [ "$status" -eq 0 ]
  run grep -c -- 'k3d-manager/shopping-cart: "true"' "$RENDERED_FILE"
  [ "$output" = "1" ]
}

@test "register_app_cluster: rejects a non-boolean shopping-cart value" {
  _argocd_set_active_app_cluster() { :; }
  export -f _argocd_set_active_app_cluster
  unset ARGOCD_APP_CLUSTER_TOKEN
  ARGOCD_APP_CLUSTER_SERVER=https://kubernetes.default.svc \
    ARGOCD_APP_CLUSTER_SHOPPING_CART=yes run register_app_cluster
  [ "$status" -eq 1 ]
}
