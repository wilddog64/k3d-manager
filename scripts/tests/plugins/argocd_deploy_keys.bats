#!/usr/bin/env bats

setup() {
  source "${BATS_TEST_DIRNAME}/../test_helpers.bash"
  RUNNER_SCRIPT="${BATS_TEST_TMPDIR}/run-configure.sh"
  cat <<'SH' > "$RUNNER_SCRIPT"
#!/usr/bin/env bash
source "${BATS_TEST_DIRNAME}/../test_helpers.bash"
init_test_env
source "${BATS_TEST_DIRNAME}/../../plugins/argocd.sh"
if [[ -n "${ARGOCD_DEPLOY_KEY_TEST_HOOK:-}" && -f "${ARGOCD_DEPLOY_KEY_TEST_HOOK}" ]]; then
  # shellcheck disable=SC1090
  source "${ARGOCD_DEPLOY_KEY_TEST_HOOK}"
fi
configure_vault_argocd_repos "$@"
SH
  chmod +x "$RUNNER_SCRIPT"

  POLICY_RUNNER="${BATS_TEST_TMPDIR}/run-policy.sh"
  cat <<'SH' > "$POLICY_RUNNER"
#!/usr/bin/env bash
source "${BATS_TEST_DIRNAME}/../test_helpers.bash"
init_test_env
source "${BATS_TEST_DIRNAME}/../../plugins/argocd.sh"
_argocd_deploy_key_policy_hcl
SH
  chmod +x "$POLICY_RUNNER"

  BASE_ENV=(
    "PATH=$PATH"
    "BATS_TEST_DIRNAME=$BATS_TEST_DIRNAME"
    "BATS_TEST_TMPDIR=$BATS_TEST_TMPDIR"
    "HOME=$HOME"
    "ARGOCD_NAMESPACE=cicd"
    "VAULT_NS_DEFAULT=vault"
    "VAULT_RELEASE_DEFAULT=vault"
  )

  KUBECTL_LOG_PATH="${BATS_TEST_TMPDIR}/kubectl.log"
}

run_policy_hcl() {
  run env -i "${BASE_ENV[@]}" "$POLICY_RUNNER"
}

run_configure() {
  local hook_file="$1"
  shift
  local -a env_args=("${BASE_ENV[@]}")
  if [[ -n "$hook_file" ]]; then
    env_args+=("ARGOCD_DEPLOY_KEY_TEST_HOOK=$hook_file")
  fi
  run env -i "${env_args[@]}" "$RUNNER_SCRIPT" "$@"
}

@test "_argocd_deploy_key_policy_hcl includes deploy key paths" {
  run_policy_hcl
  [ "$status" -eq 0 ]
  [[ "$output" == *"secret/data/argocd/deploy-keys/*"* ]]
}

@test "_argocd_deploy_key_policy_hcl uses read capability" {
  run_policy_hcl
  [ "$status" -eq 0 ]
  [[ "$output" == *'capabilities = ["read"]'* ]]
}

@test "_argocd_deploy_key_policy_hcl avoids write/delete" {
  run_policy_hcl
  [ "$status" -eq 0 ]
  [[ "$output" != *write* ]]
  [[ "$output" != *delete* ]]
}

@test "configure_vault_argocd_repos errors when namespace missing" {
  local hook="${BATS_TEST_TMPDIR}/hook-missing-ns.sh"
  cat <<'EOF' > "$hook"
KUBECTL_EXIT_CODES=(1 0 0 0 0)
EOF
  run_configure "$hook"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Namespace"* ]]
}

@test "configure_vault_argocd_repos errors when ESO CRDs missing" {
  local hook="${BATS_TEST_TMPDIR}/hook-missing-crd.sh"
  cat <<'EOF' > "$hook"
KUBECTL_EXIT_CODES=(0 0 1 0 0)
EOF
  run_configure "$hook"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Missing CRD"* ]]
}

@test "configure_vault_argocd_repos --dry-run makes no kubectl calls" {
  run_configure "" --dry-run
  [ "$status" -eq 0 ]
  [ ! -s "$KUBECTL_LOG_PATH" ]
}

@test "configure_vault_argocd_repos --seed-vault writes placeholders" {
  run_configure "" --seed-vault
  [ "$status" -eq 0 ]
  read_lines "$KUBECTL_LOG_PATH" calls
  local count=0
  for line in "${calls[@]}"; do
    if [[ "$line" == *"vault kv put secret/argocd/deploy-keys/"* ]]; then
      count=$((count + 1))
    fi
  done
  [ "$count" -eq 5 ]
}

@test "configure_vault_argocd_repos --dry-run --seed-vault prints actions only" {
  run_configure "" --dry-run --seed-vault
  [ "$status" -eq 0 ]
  [ ! -s "$KUBECTL_LOG_PATH" ]
  [[ "$output" == *"(dry-run) Would seed placeholder"* ]]
}
