#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  export REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../.." && pwd)"
  export STUB_BIN="${BATS_TEST_TMPDIR}/bin"
  export CALL_LOG="${BATS_TEST_TMPDIR}/kubectl.log"
  mkdir -p "${STUB_BIN}"
  : > "${CALL_LOG}"

  cat > "${STUB_BIN}/kubectl" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "${CALL_LOG}"
case "$*" in
  *"get secret cluster-ubuntu-k3s"*)
    printf '%s' 'https://host.k3d.internal:6443' | base64
    ;;
  *"get applications -o jsonpath"*)
    printf '%s\n' 'application/ubuntu-k3s-order'
    ;;
  *"get applications -o json"*)
    printf '%s\n' '{"items":['
    printf '%s\n' '{"metadata":{"name":"ubuntu-k3s-order"},"spec":{"destination":{"name":"ubuntu-k3s"}}},'
    printf '%s\n' '{"metadata":{"name":"ubuntu-k3s-eso"},"spec":{"destination":{"server":"https://host.k3d.internal:6443"}}},'
    printf '%s\n' '{"metadata":{"name":"k3d-cluster-eso"},"spec":{"destination":{"server":"https://kubernetes.default.svc"}}},'
    printf '%s\n' '{"metadata":{"name":"ubuntu-hostinger-platform"},"spec":{"destination":{"name":"ubuntu-hostinger"}}}'
    printf '%s\n' ']}'
    ;;
esac
STUB
  chmod +x "${STUB_BIN}/kubectl"
}

_run_deregister() {
  PATH="${STUB_BIN}:${PATH}" SCRIPT_DIR="${REPO_ROOT}/scripts" \
    CALL_LOG="${CALL_LOG}" bash -c '
      source "${SCRIPT_DIR}/lib/providers/k3s-aws.sh"
      _argocd_hub_kubectl_cmd() { printf "kubectl"; }
      _k3s_aws_deregister_cluster
    '
}

@test "name- and server-matched apps are both deleted; others are not" {
  run _run_deregister
  [ "${status}" -eq 0 ]
  grep -q 'delete application/ubuntu-k3s-order' "${CALL_LOG}"
  grep -q 'delete application/ubuntu-k3s-eso' "${CALL_LOG}"
  ! grep -q 'delete application/k3d-cluster-eso' "${CALL_LOG}"
  ! grep -q 'delete application/ubuntu-hostinger-platform' "${CALL_LOG}"
}

@test "Secret is deleted before the first Application" {
  run _run_deregister
  [ "${status}" -eq 0 ]
  secret_line="$(grep -n 'delete secret cluster-ubuntu-k3s' "${CALL_LOG}" | cut -d: -f1)"
  app_line="$(grep -n 'delete application/' "${CALL_LOG}" | head -1 | cut -d: -f1)"
  [ "${secret_line}" -lt "${app_line}" ]
}

@test "in-cluster server is never used" {
  cat > "${STUB_BIN}/kubectl" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "${CALL_LOG}"
case "$*" in
  *"get secret cluster-ubuntu-k3s"*)
    printf '%s' 'https://kubernetes.default.svc' | base64
    ;;
  *"get applications -o json"*)
    printf '%s\n' '{"items":[{"metadata":{"name":"k3d-cluster-eso"},"spec":{"destination":{"server":"https://kubernetes.default.svc"}}}]}'
    ;;
esac
STUB
  chmod +x "${STUB_BIN}/kubectl"
  run _run_deregister
  [ "${status}" -eq 0 ]
  ! grep -q 'delete application/k3d-cluster-eso' "${CALL_LOG}"
}

@test "cluster-down keep-hub guard protects the Vault LaunchAgent" {
  vault_line="$(grep -n '_vault_pf_label="com.k3d-manager.vault-port-forward"' "${REPO_ROOT}/bin/cluster-down" | cut -d: -f1)"
  [ -n "${vault_line}" ]
  sed -n "$((vault_line - 1))p" "${REPO_ROOT}/bin/cluster-down" | grep -q '_keep_hub'
}
