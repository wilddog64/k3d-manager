#!/usr/bin/env bats
# Finding 2b: dispatcher guard strips --confirm before deploy_app_cluster re-checks it.
# Fix: guard publishes K3DM_DEPLOY_CONFIRMED; deploy_app_cluster honors it.
# See docs/bugs/2026-08-29-dispatcher-confirm-flag-deploy-app-cluster.md

setup() {
  source "${BATS_TEST_DIRNAME}/../test_helpers.bash"
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
  export REPO_ROOT
  MANAGER="${REPO_ROOT}/scripts/k3d-manager"

  STUB_DIR="$(mktemp -d)"
  printf '#!/usr/bin/env bash\nexit 0\n' > "${STUB_DIR}/k3sup"
  chmod +x "${STUB_DIR}/k3sup"
  printf '#!/usr/bin/env bash\necho "stub: ssh must not be called" >&2\nexit 97\n' > "${STUB_DIR}/ssh"
  printf '#!/usr/bin/env bash\necho "stub: scp must not be called" >&2\nexit 97\n' > "${STUB_DIR}/scp"
  chmod +x "${STUB_DIR}/ssh" "${STUB_DIR}/scp"
  printf '#!/usr/bin/env bash\nexit 0\n' > "${STUB_DIR}/kubectl"
  chmod +x "${STUB_DIR}/kubectl"
}

teardown() {
  [[ -n "${STUB_DIR:-}" ]] && rm -rf "${STUB_DIR}"
}

@test "deploy_app_cluster --help passes through the guard" {
  run "$MANAGER" deploy_app_cluster --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: deploy_app_cluster"* ]]
}

@test "deploy_app_cluster without --confirm is blocked by the guard safety gate" {
  run "$MANAGER" deploy_app_cluster
  [ "$status" -eq 1 ]
  [[ "$output" == *"Safety gate"* ]]
  [[ "$output" != *"SSH key not found"* ]]
}

@test "deploy_app_cluster --confirm reaches the confirmed path (Finding 2b)" {
  run env \
    K3S_AWS_SSM_ENABLED=false \
    UBUNTU_K3S_SSH_KEY=/nonexistent/k3d-manager-key.pem \
    UBUNTU_K3S_LOCAL_KUBECONFIG="${STUB_DIR}/absent-kubeconfig.yaml" \
    KUBECONFIG=/dev/null \
    PATH="${STUB_DIR}:${PATH}" \
    "$MANAGER" deploy_app_cluster --confirm
  [ "$status" -eq 1 ]
  [[ "$output" != *"requires --confirm"* ]]
  [[ "$output" == *"SSH key not found"* ]]
  [[ "$output" != *"Merging ubuntu-k3s context"* ]]
  [[ "$output" != *"Installing socat"* ]]
  [[ "$output" != *"stub: ssh must not be called"* ]]
}
