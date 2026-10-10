#!/usr/bin/env bats
# shellcheck disable=SC2155,SC2030,SC2031

setup() {
  export HARNESS_DIR="$(mktemp -d "${BATS_TEST_TMPDIR}/hub-up.XXXXXX")"
  export STUB_DIR="${HARNESS_DIR}/stubs"
  export FAKE_HOME="${HARNESS_DIR}/home"
  export CALL_LOG="${HARNESS_DIR}/calls.log"
  mkdir -p "${STUB_DIR}" "${FAKE_HOME}"
  : > "${CALL_LOG}"

  for command_name in k3d kubectl docker aws launchctl ssh; do
    cat > "${STUB_DIR}/${command_name}" <<'EOF'
#!/usr/bin/env bash
printf '%s %s\n' "$(basename "$0")" "$*" >> "${CALL_LOG}"
if [[ "$(basename "$0")" == "k3d" && "${HUB_STATE:-missing}" == "existing" ]]; then
  printf 'k3d-cluster\tservers:1\tagents:1\n'
fi
if [[ "$(basename "$0")" == "kubectl" && "$*" == *"config current-context"* ]]; then
  printf '%s\n' "${KUBE_CONTEXT:-k3d-k3d-cluster}"
  exit 0
fi
if [[ "$(basename "$0")" == "kubectl" && "$*" == *"config use-context"* ]]; then
  exit 99
fi
if [[ "$(basename "$0")" == "kubectl" && "$*" == *"get endpoints kubernetes"* ]]; then
  printf '%s\n' "${DR_TEST_API_ENDPOINT-192.168.117.2 6443}"
  exit 0
fi
if [[ "$(basename "$0")" == "kubectl" && "$*" == *"apply -f -"* ]]; then
  cat >> "${CALL_LOG}.stdin"
  exit 0
fi
exit 0
EOF
    chmod +x "${STUB_DIR}/${command_name}"
  done

  cat > "${STUB_DIR}/dispatcher" <<'EOF'
#!/usr/bin/env bash
printf 'dispatcher %s\n' "$*" >> "${CALL_LOG}"
if [[ "${FAIL_STEP:-}" == "${1:-}" ]]; then
  exit 17
fi
exit 0
EOF
  chmod +x "${STUB_DIR}/dispatcher"

  export PATH="${STUB_DIR}:/usr/bin:/bin"
  export HOME="${FAKE_HOME}"
  export K3DM_DISPATCHER="${STUB_DIR}/dispatcher"
  export DRY_RUN=1
}

teardown() {
  rm -rf "${HARNESS_DIR}"
}

@test "hub-up harness proves all cluster tools resolve to stubs" {
  command -v k3d
  command -v docker
  command -v kubectl
}

@test "hub-up creates a missing hub and deploys bootstrap components in order" {
  run bash -c 'command -v k3d docker kubectl; bin/hub-up'
  [ "$status" -eq 0 ]
  [[ "$output" == *"${STUB_DIR}/k3d"* ]]
  [[ "$output" == *"${STUB_DIR}/docker"* ]]
  [[ "$output" == *"${STUB_DIR}/kubectl"* ]]
  run cat "${CALL_LOG}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"dispatcher deploy_cluster --provider k3d k3d-cluster"* ]]
  [[ "$output" == *"dispatcher deploy_vault --confirm"* ]]
  [[ "$output" == *"dispatcher deploy_ldap --confirm"* ]]
  [[ "$output" == *"dispatcher deploy_argocd --confirm"* ]]
}

@test "hub-up skips creation for an existing hub and never changes context" {
  export HUB_STATE=existing
  run bin/hub-up
  [ "$status" -eq 0 ]
  [[ "$output" == *"hub exists — skipping create"* ]]
  run cat "${CALL_LOG}"
  [[ "$output" != *"dispatcher deploy_cluster"* ]]
  [[ "$output" != *"config use-context"* ]]
  [[ "$output" == *"dispatcher deploy_vault --confirm"* ]]
  [[ "$output" == *"dispatcher deploy_ldap --confirm"* ]]
  [[ "$output" == *"dispatcher deploy_argocd --confirm"* ]]
}

@test "hub-up stops when Vault deployment fails" {
  export FAIL_STEP=deploy_vault
  run bin/hub-up
  [ "$status" -ne 0 ]
  [[ "$output" == *"Step 3/5 failed: deploying Vault"* ]]
  run cat "${CALL_LOG}"
  [[ "$output" != *"dispatcher deploy_ldap"* ]]
  [[ "$output" != *"dispatcher deploy_argocd"* ]]
}

@test "hub-up refuses deployment when the current context is not the hub" {
  export KUBE_CONTEXT=ubuntu-hostinger
  run bin/hub-up
  [ "$status" -ne 0 ]
  [[ "$output" == *"ubuntu-hostinger"* ]]
  [[ "$output" == *"k3d-k3d-cluster"* ]]
  run cat "${CALL_LOG}"
  [[ "$output" != *"dispatcher deploy_vault"* ]]
  [[ "$output" != *"dispatcher deploy_ldap"* ]]
  [[ "$output" != *"dispatcher deploy_argocd"* ]]
}

@test "Makefile routes k3d and preserves k3s-aws routing" {
  run grep -A8 '^up:' Makefile
  [ "$status" -eq 0 ]
  [[ "$output" == *"k3d) bin/hub-up"* ]]
  [[ "$output" == *"bin/cluster-up"* ]]
}

@test "hub-up target is phony, documented, and forwards to k3d up" {
  run grep '^\.PHONY:' Makefile
  [ "$status" -eq 0 ]
  [[ "$output" == *"hub-up"* ]]
  run make help
  [ "$status" -eq 0 ]
  [[ "$output" == *"make hub-up        Rebuild the local hub only (no AWS, no sandbox)"* ]]
  run grep -A2 '^hub-up:' Makefile
  [ "$status" -eq 0 ]
  [[ "$output" == *"up CLUSTER_PROVIDER=k3d"* ]]
}

@test "hub-up: DR drill mode stops before ArgoCD" {
  export DR_DRILL_MODE=1
  export KUBE_CONTEXT=k3d-dr-drill
  export HUB_CLUSTER_NAME=dr-drill
  export KUBECONFIG="${FAKE_HOME}/dr-drill/kubeconfig"
  run bin/hub-up
  [ "$status" -eq 0 ]
  run cat "$CALL_LOG"
  [[ "$output" == *"dispatcher deploy_vault --confirm"* ]]
  [[ "$output" == *"dispatcher deploy_ldap --confirm"* ]]
  [[ "$output" != *"dispatcher deploy_argocd"* ]]
  while IFS= read -r line; do
    [[ "$line" != kubectl\ * ]] || { [[ "$line" == *"--kubeconfig $KUBECONFIG"* ]] && [[ "$line" == *"--context k3d-dr-drill"* ]]; }
  done < "$CALL_LOG"
  [[ "$output" != *"deploy_argocd_bootstrap"* ]]
  [[ "$output" != *"deploy_argocd_platform_ops"* ]]
  [[ "$output" != *"_argocd_deploy_image_updater"* ]]
}

@test "hub-up: DR namespaces exist before egress policy and workloads" {
  export DR_DRILL_MODE=1
  export KUBE_CONTEXT=k3d-dr-drill
  export HUB_CLUSTER_NAME=dr-drill
  export KUBECONFIG="${FAKE_HOME}/dr-drill/kubeconfig"
  run bin/hub-up
  [ "$status" -eq 0 ]
  run awk '/kubectl/ {print}' "$CALL_LOG"
  create_line="$(printf '%s\n' "$output" | grep -n 'create namespace secrets' | head -1 | cut -d: -f1)"
  policy_line="$(printf '%s\n' "$output" | grep -n 'egress-deny.yaml' | head -1 | cut -d: -f1)"
  vault_line="$(grep -n 'dispatcher deploy_vault' "$CALL_LOG" | head -1 | cut -d: -f1)"
  [ "$create_line" -lt "$policy_line" ]
  [ "$policy_line" -lt "$vault_line" ]
}

@test "hub-up: DR mode lets drill pods reach only the drill API server" {
  export DR_DRILL_MODE=1 KUBE_CONTEXT=k3d-dr-drill HUB_CLUSTER_NAME=dr-drill
  export KUBECONFIG="${FAKE_HOME}/dr-drill/kubeconfig"
  run bin/hub-up
  [ "$status" -eq 0 ]
  [ "$(grep -c 'name: dr-allow-apiserver-egress' "${CALL_LOG}.stdin")" -eq 2 ]
  grep -q 'namespace: secrets' "${CALL_LOG}.stdin"; grep -q 'namespace: identity' "${CALL_LOG}.stdin"
  [ "$(grep -c 'cidr: 192.168.117.2/32' "${CALL_LOG}.stdin")" -eq 2 ]
  [ "$(grep -c 'port: 6443' "${CALL_LOG}.stdin")" -eq 2 ]
  [ "$(grep -c 'cidr:' "${CALL_LOG}.stdin")" -eq 2 ]
  allow_line="$(grep -n 'apply -f -' "$CALL_LOG" | head -1 | cut -d: -f1)"
  vault_line="$(grep -n 'dispatcher deploy_vault' "$CALL_LOG" | head -1 | cut -d: -f1)"
  [ "$allow_line" -lt "$vault_line" ]
}

@test "hub-up: DR mode stops when the API server endpoint is unreadable" {
  export DR_DRILL_MODE=1 KUBE_CONTEXT=k3d-dr-drill HUB_CLUSTER_NAME=dr-drill DR_TEST_API_ENDPOINT='0.0.0.0/0 6443'
  export KUBECONFIG="${FAKE_HOME}/dr-drill/kubeconfig"
  run bin/hub-up
  [ "$status" -ne 0 ]
  [[ "$output" == *"cannot read the drill API server endpoint"* ]]
  [ "$(grep -c 'dispatcher deploy_vault' "$CALL_LOG" || true)" -eq 0 ]
}
