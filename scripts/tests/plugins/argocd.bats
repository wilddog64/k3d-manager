#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  source "${BATS_TEST_DIRNAME}/../test_helpers.bash"
  init_test_env
  source "${BATS_TEST_DIRNAME}/../../plugins/argocd.sh"
  export_stubs

  # Create log files for command tracking
  KUBECTL_LOG="$BATS_TEST_TMPDIR/kubectl.log"
  HELM_LOG="$BATS_TEST_TMPDIR/helm.log"
  : > "$KUBECTL_LOG"
  : > "$HELM_LOG"

  # Export log paths
  export KUBECTL_LOG
  export HELM_LOG

  # Set default ArgoCD configuration
  export ARGOCD_NAMESPACE="argocd"
  export ARGOCD_HELM_RELEASE="argocd"
  export ARGOCD_HELM_REPO_NAME="argo"
  export ARGOCD_HELM_REPO_URL="https://argoproj.github.io/argo-helm"
  export ARGOCD_HELM_CHART_REF="argo/argo-cd"
  export ARGOCD_VIRTUALSERVICE_HOST="argocd.dev.local.me"
  export ARGOCD_ADMIN_SECRET_NAME="argocd-admin-secret"
  export ARGOCD_LDAP_SECRET_NAME="argocd-ldap-secret"

  # Set up ArgoCD config directory for templates
  export ARGOCD_CONFIG_DIR="${BATS_TEST_DIRNAME}/../../etc/argocd"
}

@test "deploy_argocd -h shows usage" {
  run deploy_argocd -h
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: deploy_argocd"* ]]
  [[ "$output" == *"--enable-ldap"* ]]
  [[ "$output" == *"--enable-vault"* ]]
  [[ "$output" == *"--skip-istio"* ]]
}

@test "deploy_argocd --help shows usage" {
  run deploy_argocd --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: deploy_argocd"* ]]
}

@test "deploy_argocd rejects unknown options" {
  run deploy_argocd --unknown-flag
  [ "$status" -eq 1 ]
  [[ "$output" == *"Unknown option"* ]]
}

@test "deploy_argocd adds Helm repository" {
  run deploy_argocd
  [ "$status" -eq 0 ]
  read_lines "$HELM_LOG" helm_calls

  # Check that repo add was called
  local found_repo_add=0
  for call in "${helm_calls[@]}"; do
    if [[ "$call" == *"repo add argo"* ]]; then
      found_repo_add=1
      break
    fi
  done
  [ "$found_repo_add" -eq 1 ]
}

@test "deploy_argocd skips Helm repo operations for local chart" {
  export ARGOCD_HELM_CHART_REF="/local/path/to/chart"
  run deploy_argocd
  [ "$status" -eq 0 ]
  read_lines "$HELM_LOG" helm_calls

  # Verify no repo add command
  local found_repo_add=0
  for call in "${helm_calls[@]}"; do
    if [[ "$call" == *"repo add"* ]]; then
      found_repo_add=1
      break
    fi
  done
  [ "$found_repo_add" -eq 0 ]
}

@test "deploy_argocd installs Argo CD via Helm" {
  run deploy_argocd
  [ "$status" -eq 0 ]
  read_lines "$HELM_LOG" helm_calls

  # Check for helm upgrade --install command
  local found_install=0
  for call in "${helm_calls[@]}"; do
    if [[ "$call" == *"upgrade --install"* && "$call" == *"argocd"* ]]; then
      found_install=1
      break
    fi
  done
  [ "$found_install" -eq 1 ]
}

@test "deploy_argocd creates namespace" {
  run deploy_argocd
  [ "$status" -eq 0 ]
  read_lines "$HELM_LOG" helm_calls

  # Check for --create-namespace flag
  local found_create_ns=0
  for call in "${helm_calls[@]}"; do
    if [[ "$call" == *"--create-namespace"* ]]; then
      found_create_ns=1
      break
    fi
  done
  [ "$found_create_ns" -eq 1 ]
}

@test "deploy_argocd waits for server deployment" {
  run deploy_argocd
  [ "$status" -eq 0 ]
  read_lines "$KUBECTL_LOG" kubectl_calls

  # Check for wait command on argocd-server deployment
  local found_wait=0
  for call in "${kubectl_calls[@]}"; do
    if [[ "$call" == *"wait"* && "$call" == *"deployment/argocd-server"* ]]; then
      found_wait=1
      break
    fi
  done
  [ "$found_wait" -eq 1 ]
}

@test "deploy_argocd waits for repo-server deployment" {
  run deploy_argocd
  [ "$status" -eq 0 ]
  read_lines "$KUBECTL_LOG" kubectl_calls

  # Check for wait command on argocd-repo-server deployment
  local found_wait=0
  for call in "${kubectl_calls[@]}"; do
    if [[ "$call" == *"wait"* && "$call" == *"deployment/argocd-repo-server"* ]]; then
      found_wait=1
      break
    fi
  done
  [ "$found_wait" -eq 1 ]
}

@test "deploy_argocd with --enable-vault creates admin ExternalSecret" {
  run deploy_argocd --enable-vault
  [ "$status" -eq 0 ]
  read_lines "$KUBECTL_LOG" kubectl_calls

  # Check for apply command (ExternalSecret creation)
  local found_externalsecret=0
  for call in "${kubectl_calls[@]}"; do
    if [[ "$call" == *"apply"* ]]; then
      found_externalsecret=1
      break
    fi
  done
  [ "$found_externalsecret" -eq 1 ]
}

@test "deploy_argocd with --enable-vault waits for admin ExternalSecret" {
  run deploy_argocd --enable-vault
  [ "$status" -eq 0 ]
  read_lines "$KUBECTL_LOG" kubectl_calls

  # Check for wait on admin ExternalSecret
  local found_wait=0
  for call in "${kubectl_calls[@]}"; do
    if [[ "$call" == *"wait"* && "$call" == *"externalsecret/$ARGOCD_ADMIN_SECRET_NAME"* ]]; then
      found_wait=1
      break
    fi
  done
  [ "$found_wait" -eq 1 ]
}

@test "deploy_argocd with --enable-ldap and --enable-vault creates LDAP ExternalSecret" {
  run deploy_argocd --enable-ldap --enable-vault
  [ "$status" -eq 0 ]
  read_lines "$KUBECTL_LOG" kubectl_calls

  # Check for wait on LDAP ExternalSecret
  local found_ldap_wait=0
  for call in "${kubectl_calls[@]}"; do
    if [[ "$call" == *"wait"* && "$call" == *"externalsecret/$ARGOCD_LDAP_SECRET_NAME"* ]]; then
      found_ldap_wait=1
      break
    fi
  done
  [ "$found_ldap_wait" -eq 1 ]
}

@test "deploy_argocd without --skip-istio creates VirtualService" {
  run deploy_argocd
  [ "$status" -eq 0 ]
  read_lines "$KUBECTL_LOG" kubectl_calls

  # Check for apply command (VirtualService creation happens after deployment)
  local found_apply=0
  for call in "${kubectl_calls[@]}"; do
    if [[ "$call" == *"apply"* ]]; then
      found_apply=1
      break
    fi
  done
  [ "$found_apply" -eq 1 ]
}

@test "deploy_argocd displays UI URL in output" {
  run deploy_argocd
  [ "$status" -eq 0 ]
  [[ "$output" == *"$ARGOCD_VIRTUALSERVICE_HOST"* ]]
}

@test "deploy_argocd shows admin password retrieval command with --enable-vault" {
  run deploy_argocd --enable-vault
  [ "$status" -eq 0 ]
  [[ "$output" == *"$ARGOCD_ADMIN_SECRET_NAME"* ]]
  [[ "$output" == *"Retrieve admin password"* ]]
}

@test "deploy_argocd shows initial admin password retrieval without --enable-vault" {
  run deploy_argocd
  [ "$status" -eq 0 ]
  [[ "$output" == *"argocd-initial-admin-secret"* ]]
}

@test "deploy_argocd supports version specification" {
  export ARGOCD_HELM_CHART_VERSION="5.46.0"
  run deploy_argocd
  [ "$status" -eq 0 ]
  read_lines "$HELM_LOG" helm_calls

  # Check for --version flag
  local found_version=0
  for call in "${helm_calls[@]}"; do
    if [[ "$call" == *"--version $ARGOCD_HELM_CHART_VERSION"* ]]; then
      found_version=1
      break
    fi
  done
  [ "$found_version" -eq 1 ]
}

@test "deploy_argocd handles existing release upgrade" {
  # Simulate existing release by making helm status succeed
  HELM_EXIT_CODES=(0)
  run deploy_argocd
  [ "$status" -eq 0 ]
  [[ "$output" == *"Existing release found"* ]] || [[ "$output" == *"will upgrade"* ]]
}

@test "deploy_argocd uses insecure mode for basic deployment" {
  run deploy_argocd
  [ "$status" -eq 0 ]
  read_lines "$HELM_LOG" helm_calls

  # Check for insecure setting
  local found_insecure=0
  for call in "${helm_calls[@]}"; do
    if [[ "$call" == *"server.insecure=true"* ]]; then
      found_insecure=1
      break
    fi
  done
  [ "$found_insecure" -eq 1 ]
}

@test "_argocd_check_dependencies detects missing Istio" {
  # Override kubectl to simulate missing istio-system namespace
  _kubectl() {
    if [[ "$*" == *"get ns istio-system"* ]]; then
      return 1
    fi
    return 0
  }
  export -f _kubectl

  run _argocd_check_dependencies
  [ "$status" -eq 0 ]
  [[ "$output" == *"Missing optional dependencies"* ]]
  [[ "$output" == *"Istio"* ]]
}

@test "_argocd_check_dependencies passes when Istio exists" {
  # Override kubectl to simulate existing istio-system namespace
  _kubectl() {
    if [[ "$*" == *"get ns istio-system"* ]]; then
      return 0
    fi
    return 0
  }
  export -f _kubectl

  run _argocd_check_dependencies
  [ "$status" -eq 0 ]
  [[ "$output" != *"Missing optional dependencies"* ]]
}

@test "deploy_argocd reports deployment completion" {
  run deploy_argocd
  [ "$status" -eq 0 ]
  [[ "$output" == *"Deployment complete"* ]] || [[ "$output" == *"deployed successfully"* ]]
}

@test "deploy_argocd with all flags combines features correctly" {
  run deploy_argocd --enable-ldap --enable-vault
  [ "$status" -eq 0 ]

  # Should include LDAP configuration
  # Should include Vault integration
  # Should include Istio VirtualService (no --skip-istio)
  read_lines "$KUBECTL_LOG" kubectl_calls

  # Count wait operations - should have multiple for different resources
  local wait_count=0
  for call in "${kubectl_calls[@]}"; do
    if [[ "$call" == *"wait"* ]]; then
      ((wait_count++)) || true
    fi
  done
  [ "$wait_count" -ge 3 ]  # At least: server, repo-server, admin externalsecret, ldap externalsecret
}
