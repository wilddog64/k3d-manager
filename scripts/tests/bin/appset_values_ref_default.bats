#!/usr/bin/env bats
# shellcheck shell=bash

setup() {
  local source_root
  source_root="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
  export TEST_ROOT="${BATS_TEST_TMPDIR}/repo"
  export HOME="${BATS_TEST_TMPDIR}/home"
  export CAPTURE="${BATS_TEST_TMPDIR}/applied.yaml"
  mkdir -p "${TEST_ROOT}" "${HOME}" "${BATS_TEST_TMPDIR}/bin"
  cp -R "${source_root}/bin" "${TEST_ROOT}/bin"
  cp -R "${source_root}/scripts" "${TEST_ROOT}/scripts"
  mkdir -p "${BATS_TEST_TMPDIR}/shopping-carts/shopping-cart-infra/argocd/applications"
  cat > "${BATS_TEST_TMPDIR}/shopping-carts/shopping-cart-infra/argocd/applications/data-layer.yaml" <<'YAML'
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: data-layer
spec:
  destination:
    name: ubuntu-k3s
YAML
  git -C "${TEST_ROOT}" init -q -b k3d-manager-v9.9.9
  git -C "${TEST_ROOT}" config user.name "AppSet Test"
  git -C "${TEST_ROOT}" config user.email "appset-test@example.invalid"
  git -C "${TEST_ROOT}" add bin scripts
  git -C "${TEST_ROOT}" commit -qm "fixture checkout"
  cat > "${BATS_TEST_TMPDIR}/bin/kubectl" <<'STUB'
#!/usr/bin/env bash
set -u
case "$*" in
  *"apply -f -"*)
    cat >> "${CAPTURE}"
    printf '\n---\n' >> "${CAPTURE}"
    ;;
  *"apply -f "*)
    for arg in "$@"; do
      if [[ -f "$arg" ]]; then cat "$arg" >> "${CAPTURE}"; printf '\n---\n' >> "${CAPTURE}"; fi
    done
    ;;
  *"current-context"*) printf '%s\n' "${HOST_CONTEXT:-ubuntu-hostinger}" ;;
  *"get-contexts"*) : ;;
  *"get svc"*"nodePort"*) printf '32000' ;;
  *"get applications.argoproj.io"*) printf '{"items":[{"metadata":{"name":"fixture-preflight-platform"}}]}' ;;
  *"get application "*"jsonpath"*) printf 'Synced Healthy' ;;
  *"get secret vault-root"*) printf 'dG9rZW4=' ;;
  *"get crd prometheusrules"*) printf 'True' ;;
  *"api-resources --api-group=monitoring.coreos.com"*) printf 'prometheuses.monitoring.coreos.com\n' ;;
  *"create namespace"*) printf 'apiVersion: v1\nkind: Namespace\nmetadata:\n  name: monitoring\n' ;;
  *) : ;;
esac
exit 0
STUB
  cat > "${BATS_TEST_TMPDIR}/bin/helm" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
  cat > "${BATS_TEST_TMPDIR}/bin/curl" <<'STUB'
#!/usr/bin/env bash
case "$*" in *healthz*) exit 0 ;; *) exit 0 ;; esac
STUB
  cat > "${BATS_TEST_TMPDIR}/bin/launchctl" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
  chmod +x "${BATS_TEST_TMPDIR}/bin/kubectl" "${BATS_TEST_TMPDIR}/bin/helm" "${BATS_TEST_TMPDIR}/bin/curl" "${BATS_TEST_TMPDIR}/bin/launchctl"
  export PATH="${BATS_TEST_TMPDIR}/bin:${PATH}"
  export HOST_CONTEXT=ubuntu-hostinger HOSTINGER_HOST=127.0.0.1
  export VCLUSTER_KUBECONFIG_DIR="${BATS_TEST_TMPDIR}/kubeconfig"
  mkdir -p "${VCLUSTER_KUBECONFIG_DIR}"
  : > "${CAPTURE}"
}

assert_fixture() {
  [ "$(git -C "${TEST_ROOT}" rev-parse --abbrev-ref HEAD)" = "k3d-manager-v9.9.9" ]
  [ "$(command -v kubectl)" = "${BATS_TEST_TMPDIR}/bin/kubectl" ]
  [ "${HOME}" = "${BATS_TEST_TMPDIR}/home" ]
}

assert_rendered_ref() {
  local expected="$1"
  [ -s "${CAPTURE}" ]
  grep -Eq "(targetRevision|revision):[[:space:]]*['\"]?${expected}['\"]?([[:space:]]|$)" "${CAPTURE}"
  if [[ "${expected}" == deploy/hub ]]; then
    if grep -Fq 'k3d-manager-v9.9.9' "${CAPTURE}"; then return 1; fi
  fi
}

run_preflight() {
  local branch_mode="$1"
  : > "${CAPTURE}"
  touch "${VCLUSTER_KUBECONFIG_DIR}/fixture.yaml"
  if [[ -n "${branch_mode}" ]]; then
    env KUBECONFIG="${BATS_TEST_TMPDIR}/config" PREFLIGHT_WAIT_TIMEOUT=1 K3D_MANAGER_BRANCH="${branch_mode}" \
      "${TEST_ROOT}/bin/cluster-preflight" fixture --reuse < /dev/null
  else
    env -u K3D_MANAGER_BRANCH KUBECONFIG="${BATS_TEST_TMPDIR}/config" PREFLIGHT_WAIT_TIMEOUT=1 \
      "${TEST_ROOT}/bin/cluster-preflight" fixture --reuse < /dev/null
  fi
}

run_observability() {
  local branch_mode="$1"
  : > "${CAPTURE}"
  if [[ -n "${branch_mode}" ]]; then
    (cd "${TEST_ROOT}" && env K3D_MANAGER_BRANCH="${branch_mode}" ./scripts/k3d-manager deploy_observability --confirm < /dev/null)
  else
    (cd "${TEST_ROOT}" && env -u K3D_MANAGER_BRANCH ./scripts/k3d-manager deploy_observability --confirm < /dev/null)
  fi
}

run_observability_acg() {
  local branch_mode="$1"
  : > "${CAPTURE}"
  if [[ -n "${branch_mode}" ]]; then
    (cd "${TEST_ROOT}" && env K3D_MANAGER_BRANCH="${branch_mode}" ./scripts/k3d-manager deploy_observability_acg --confirm < /dev/null)
  else
    (cd "${TEST_ROOT}" && env -u K3D_MANAGER_BRANCH ./scripts/k3d-manager deploy_observability_acg --confirm < /dev/null)
  fi
}

run_hostinger() {
  local branch_mode="$1"
  : > "${CAPTURE}"
  if [[ -n "${branch_mode}" ]]; then
    # shellcheck disable=SC2016
    (cd "${TEST_ROOT}" && env K3D_MANAGER_BRANCH="${branch_mode}" bash -c '
    SCRIPT_DIR="$PWD/scripts"
    REPO_ROOT="$PWD"
    source scripts/lib/providers/k3s-hostinger.sh
    _hostinger_load_argocd_plugin() { :; }
    _argocd_hub_kubectl_cmd() { printf "%s\n" kubectl; }
    _info() { :; }
    _hostinger_reapply_gitops_applicationsets
    ' < /dev/null)
  else
    # shellcheck disable=SC2016
    (cd "${TEST_ROOT}" && env -u K3D_MANAGER_BRANCH bash -c '
    SCRIPT_DIR="$PWD/scripts"
    REPO_ROOT="$PWD"
    source scripts/lib/providers/k3s-hostinger.sh
    _hostinger_load_argocd_plugin() { :; }
    _argocd_hub_kubectl_cmd() { printf "%s\n" kubectl; }
    _info() { :; }
    _hostinger_reapply_gitops_applicationsets
    ' < /dev/null)
  fi
}

@test "cluster-preflight renders deploy/hub by default from a release checkout" {
  assert_fixture
  unset K3D_MANAGER_BRANCH
  run run_preflight ""
  assert_rendered_ref deploy/hub
}

@test "cluster-preflight honors an explicit values ref" {
  assert_fixture
  run run_preflight feature/intentional
  assert_rendered_ref feature/intentional
}

@test "deploy_observability renders deploy/hub by default from a release checkout" {
  assert_fixture
  unset K3D_MANAGER_BRANCH
  run run_observability ""
  [ "$status" -eq 0 ]
  assert_rendered_ref deploy/hub
}

@test "deploy_observability honors an explicit values ref" {
  assert_fixture
  run run_observability feature/intentional
  [ "$status" -eq 0 ]
  assert_rendered_ref feature/intentional
}

@test "deploy_observability_acg renders deploy/hub by default from a release checkout" {
  assert_fixture
  unset K3D_MANAGER_BRANCH
  run run_observability_acg ""
  [ "$status" -eq 0 ]
  assert_rendered_ref deploy/hub
}

@test "deploy_observability_acg honors an explicit values ref" {
  assert_fixture
  run run_observability_acg feature/intentional
  [ "$status" -eq 0 ]
  assert_rendered_ref feature/intentional
}

@test "Hostinger ApplicationSet reapply renders deploy/hub by default from a release checkout" {
  assert_fixture
  unset K3D_MANAGER_BRANCH
  run run_hostinger ""
  [ "$status" -eq 0 ]
  assert_rendered_ref deploy/hub
}

@test "Hostinger ApplicationSet reapply honors an explicit values ref" {
  assert_fixture
  run run_hostinger feature/intentional
  [ "$status" -eq 0 ]
  assert_rendered_ref feature/intentional
}
