#!/usr/bin/env bats

setup() {
  source "${BATS_TEST_DIRNAME}/../test_helpers.bash"
  init_test_env
  export HOME="${BATS_TEST_TMPDIR}/home"
  mkdir -p "$HOME"
  export VCLUSTER_KUBECONFIG_DIR="${BATS_TEST_TMPDIR}/kubeconfigs"
  mkdir -p "$VCLUSTER_KUBECONFIG_DIR"
  export PATH="${BATS_TEST_TMPDIR}/bin:$PATH"
  mkdir -p "${BATS_TEST_TMPDIR}/bin"
  VCLUSTER_STUB="${BATS_TEST_TMPDIR}/bin/vcluster"
  cat <<'STUB' > "$VCLUSTER_STUB"
#!/usr/bin/env bash
set -euo pipefail
cmd="${1:-}"
shift || true
case "$cmd" in
  list)
    if [[ -n "${VCLUSTER_LIST_OUTPUT:-}" ]]; then
      printf '%s\n' "$VCLUSTER_LIST_OUTPUT"
    else
      printf 'NAME   NAMESPACE   STATUS   AGE\n'
    fi
    ;;
  *)
    :
    ;;
esac
STUB
  chmod +x "$VCLUSTER_STUB"
  export VCLUSTER_LIST_OUTPUT=""
  unset KUBECONFIG
  source "${BATS_TEST_DIRNAME}/../../plugins/vcluster.sh"
}

@test "vcluster_create: fails without vcluster binary" {
  rm -f "$VCLUSTER_STUB"
  run vcluster_create demo
  [ "$status" -ne 0 ]
  [[ "$output" == *"vcluster CLI is not installed"* ]]
}

@test "vcluster_create: fails without active host context" {
  KUBECTL_EXIT_CODES=(1)
  run vcluster_create demo
  [ "$status" -ne 0 ]
  [[ "$output" == *"Host cluster context not available"* ]]
}

@test "vcluster_create: dry-run prints plan without executing" {
  DRY_RUN=1 run vcluster_create preview
  [ "$status" -eq 0 ]
  [[ "$output" == *"DRY_RUN: vcluster create preview"* ]]
  [[ "$output" == *"kubeconfig will be written"* ]]
  [ ! -s "$RUN_LOG" ]
}

@test "vcluster_destroy: dry-run prints plan without executing" {
  local kubeconfig="${VCLUSTER_KUBECONFIG_DIR}/demo.yaml"
  mkdir -p "${VCLUSTER_KUBECONFIG_DIR}"
  printf 'current-context: vc-demo\n' > "$kubeconfig"
  DRY_RUN=1 run vcluster_destroy demo
  [ "$status" -eq 0 ]
  [[ "$output" == *"kubeconfig ${kubeconfig} would be removed"* ]]
  [ ! -s "$RUN_LOG" ]
}

@test "vcluster_destroy: fails on unknown cluster name" {
  export VCLUSTER_LIST_OUTPUT=$'NAME   NAMESPACE\nalpha   vclusters'
  run vcluster_destroy ghost
  [ "$status" -ne 0 ]
  [[ "$output" == *"vCluster 'ghost' not found"* ]]
  local -a run_calls
  run_calls=()
  read_lines "$RUN_LOG" run_calls
  [ "${run_calls[0]}" = "vcluster list -n vclusters" ]
}

@test "vcluster_use: fails when kubeconfig file missing" {
  rm -f "${VCLUSTER_KUBECONFIG_DIR}/ghost.yaml"
  run vcluster_use ghost
  [ "$status" -ne 0 ]
  [[ "$output" == *"kubeconfig for vCluster 'ghost' not found"* ]]
}

@test "VCLUSTER_VERSION defaults to 0.32.1" {
  [ "$VCLUSTER_VERSION" = "0.32.1" ]
}

@test "VCLUSTER_NAMESPACE defaults to vclusters" {
  [ "$VCLUSTER_NAMESPACE" = "vclusters" ]
}
