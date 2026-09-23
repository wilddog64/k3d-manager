#!/usr/bin/env bats

setup() {
  source "${BATS_TEST_DIRNAME}/../test_helpers.bash"
  init_test_env
  export HOME="${BATS_TEST_TMPDIR}/home"
  mkdir -p "$HOME"
  export VCLUSTER_KUBECONFIG_DIR="${BATS_TEST_TMPDIR}/kubeconfigs"
  mkdir -p "$VCLUSTER_KUBECONFIG_DIR"
  export VCLUSTER_HOST_CONTEXT="ubuntu-hostinger"
  unset VCLUSTER_VALUES_FILE
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
  foundation_ensure_vcluster_cli() {
    printf '%s\n' "$VCLUSTER_STUB"
  }
  _VCLUSTER_BIN="$VCLUSTER_STUB"
  _vcluster_wait_ready() { :; }
}

@test "vcluster_create: uses foundation-managed CLI path" {
  run vcluster_create demo
  [ "$status" -eq 0 ]
  run grep -F -- "$VCLUSTER_STUB create demo -n vclusters --chart-version 0.32.1 --connect=false -f ${SCRIPT_DIR}/etc/vcluster/values.yaml" "$RUN_LOG"
  [ "$status" -eq 0 ]
}

@test "_vcluster_check_prerequisites: stores the contract path" {
  local managed_path="${BATS_TEST_TMPDIR}/managed-vcluster"
  foundation_ensure_vcluster_cli() { printf '%s\n' "$managed_path"; }
  _vcluster_check_prerequisites
  [ "$_VCLUSTER_BIN" = "$managed_path" ]
}

@test "foundation contract failure stops before lifecycle work" {
  foundation_ensure_vcluster_cli() { return 1; }
  run vcluster_create demo
  [ "$status" -ne 0 ]
  [[ "$output" == *"Unable to resolve the vCluster CLI"* ]]
  run grep -qE 'create|connect|delete' "$RUN_LOG"
  [ "$status" -ne 0 ]
}

@test "empty foundation contract path stops before lifecycle work" {
  foundation_ensure_vcluster_cli() { printf '\n'; }
  run vcluster_create demo
  [ "$status" -ne 0 ]
  [[ "$output" == *"Unable to resolve the vCluster CLI"* ]]
  run grep -qE 'create|connect|delete' "$RUN_LOG"
  [ "$status" -ne 0 ]
}

@test "vcluster_create: honors VCLUSTER_VALUES_FILE override" {
  local override_values="${BATS_TEST_TMPDIR}/values-preflight.yaml"
  printf 'controlPlane:\n  service:\n    spec:\n      type: NodePort\n' > "$override_values"
  VCLUSTER_VALUES_FILE="$override_values" run vcluster_create demo
  [ "$status" -eq 0 ]
  run grep -F -- "$VCLUSTER_STUB create demo -n vclusters --chart-version 0.32.1 --connect=false -f ${override_values}" "$RUN_LOG"
  [ "$status" -eq 0 ]
}

@test "vcluster_create: fails without active host context" {
  unset VCLUSTER_HOST_CONTEXT
  # shellcheck disable=SC2034
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
  [[ "$output" == *"deregister demo from hub ArgoCD (cluster-demo + demo-preflight-* appsets/apps)"* ]]
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
  [ "${run_calls[0]}" = "$VCLUSTER_STUB list -n vclusters" ]
}

# A stale kubeconfig is all that is left of a teardown that never ran, and six of them
# sit on the m2 runner. Accepting one as proof of existence made the predicate claim a
# vCluster that is gone, so vcluster list has to be the source of truth.
@test "vcluster_destroy: a stale kubeconfig is not proof the vCluster exists" {
  _stub_run_command_executing
  printf 'current-context: vc-ghost\n' > "${VCLUSTER_KUBECONFIG_DIR}/ghost.yaml"
  export VCLUSTER_LIST_OUTPUT=$'NAME   NAMESPACE\nalpha   vclusters'
  run vcluster_destroy ghost
  [ "$status" -ne 0 ]
  [[ "$output" == *"vCluster 'ghost' not found"* ]]
  run grep -F -- "$VCLUSTER_STUB delete ghost" "$RUN_LOG"
  [ "$status" -ne 0 ]
}

# Regression guard, same class as the leak fixed in 7338a238: _e2e_teardown guards this
# call with `|| _warn` and then does its own proxy, kubeconfig and log cleanup, none of
# which an exit can be caught by. The absence path must return, not exit. Asserting a
# non-zero status is not enough — an exit 1 satisfies that too — so the marker after the
# call is what actually separates the two.
@test "vcluster_destroy: a missing vCluster returns instead of exiting its caller" {
  _stub_run_command_executing
  export VCLUSTER_LIST_OUTPUT=$'NAME   NAMESPACE\nalpha   vclusters'
  _caller() {
    vcluster_destroy ghost || true
    printf 'caller-survived\n'
  }
  run _caller
  [[ "$output" == *"caller-survived"* ]]
}

@test "vcluster_list: uses the contract-returned CLI path" {
  run vcluster_list
  [ "$status" -eq 0 ]
  run grep -F -- "$VCLUSTER_STUB list -n vclusters" "$RUN_LOG"
  [ "$status" -eq 0 ]
}

@test "vcluster_destroy: uses the contract-returned CLI path" {
  local kubeconfig="${VCLUSTER_KUBECONFIG_DIR}/demo.yaml"
  printf 'current-context: vc-demo\n' > "$kubeconfig"
  _stub_run_command_executing
  export VCLUSTER_LIST_OUTPUT=$'NAME   NAMESPACE\ndemo   vclusters'
  _vcluster_deregister_from_hub() { :; }
  run vcluster_destroy demo
  [ "$status" -eq 0 ]
  run grep -F -- "$VCLUSTER_STUB delete demo -n vclusters --wait" "$RUN_LOG"
  [ "$status" -eq 0 ]
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

@test "VCLUSTER_LOCAL_PORT defaults to 11443" {
  [ "$VCLUSTER_LOCAL_PORT" = "11443" ]
}

@test "_vcluster_export_kubeconfig pins --local-port so the kubeconfig port survives proxy re-creation" {
  _write_sensitive_file() { :; }
  run _vcluster_export_kubeconfig demo
  [ "$status" -eq 0 ]
  run grep -F -- "$VCLUSTER_STUB connect demo -n vclusters --local-port 11443 --print" "$RUN_LOG"
  [ "$status" -eq 0 ]
}

@test "_vcluster_export_kubeconfig honours VCLUSTER_LOCAL_PORT override" {
  _write_sensitive_file() { :; }
  VCLUSTER_LOCAL_PORT=22443 run _vcluster_export_kubeconfig demo
  [ "$status" -eq 0 ]
  run grep -F -- "--local-port 22443 --print" "$RUN_LOG"
  [ "$status" -eq 0 ]
}

@test "_vcluster_refresh_connection requires a name" {
  run _vcluster_refresh_connection
  [ "$status" -ne 0 ]
}

@test "_vcluster_refresh_connection removes the stale proxy and reconnects on the pinned port" {
  _run_command() {
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --probe) shift 2 ;;
        --*) shift ;;
        --) shift; break ;;
        *) break ;;
      esac
    done
    echo "$*" >> "$RUN_LOG"
    case "$*" in
      docker\ ps*) printf '%s\n' "vcluster_demo_vclusters_k3d-k3d-cluster_background_proxy" ;;
    esac
    return 0
  }
  run _vcluster_refresh_connection demo
  [ "$status" -eq 0 ]
  run grep -F -- "docker rm -f vcluster_demo_vclusters_k3d-k3d-cluster_background_proxy" "$RUN_LOG"
  [ "$status" -eq 0 ]
  run grep -F -- "$VCLUSTER_STUB connect demo -n vclusters --local-port 11443 --print" "$RUN_LOG"
  [ "$status" -eq 0 ]
}

@test "_vcluster_deregister_from_hub: deletes hub cluster secret and preflight resources" {
  _argocd_hub_kubectl_cmd() {
    printf '%s\n' "kubectl --context k3d-k3d-cluster"
  }
  _vcluster_load_argocd_plugin() {
    :
  }
  kubectl() {
    printf '%s\n' "$*" >> "${BATS_TEST_TMPDIR}/kubectl.log"
    case "$*" in
      --context\ k3d-k3d-cluster\ -n\ cicd\ get\ applicationset\ -o\ name)
        printf '%s\n' 'applicationset/green1-preflight-services-git'
        ;;
      --context\ k3d-k3d-cluster\ -n\ cicd\ get\ application\ -o\ name)
        printf '%s\n' 'application/green1-preflight-data-layer'
        ;;
      *)
        return 0
        ;;
    esac
  }
  _info() {
    :
  }

  run _vcluster_deregister_from_hub green1
  [ "$status" -eq 0 ]

  run cat "${BATS_TEST_TMPDIR}/kubectl.log"
  [ "$status" -eq 0 ]
  [[ "$output" == *"--context k3d-k3d-cluster -n cicd delete applicationset -l k3d-manager/preflight-cluster=green1 --ignore-not-found"* ]]
  [[ "$output" == *"--context k3d-k3d-cluster -n cicd delete applicationset/green1-preflight-services-git --ignore-not-found"* ]]
  [[ "$output" == *"--context k3d-k3d-cluster -n cicd patch application/green1-preflight-data-layer --type=merge -p {\"metadata\":{\"finalizers\":null}}"* ]]
  [[ "$output" == *"--context k3d-k3d-cluster -n cicd delete application/green1-preflight-data-layer --ignore-not-found"* ]]
  [[ "$output" == *"--context k3d-k3d-cluster -n cicd delete secret cluster-green1 --ignore-not-found"* ]]
}

# The shared _run_command stub logs its arguments without executing them, so a function that
# parses a command's stdout cannot be exercised through it. These orphan-reconcile tests
# install a stub that actually runs the vcluster stub binary, and intercepts helm (which is
# not installed in the harness) so the fallback path is still observable.
_stub_run_command_executing() {
  _run_command() {
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --probe) shift 2 ;;
        --*) shift ;;
        --) shift; break ;;
        *) break ;;
      esac
    done
    echo "$*" >> "$RUN_LOG"
    case "$1" in
      helm|docker) return 0 ;;
    esac
    if [[ "${2:-}" == "delete" && -n "${VCLUSTER_DELETE_FAILS:-}" ]]; then
      return 1
    fi
    "$@"
  }
}

_seed_orphan_listing() {
  export VCLUSTER_LIST_OUTPUT="NAME                  NAMESPACE   STATUS    AGE
${1} vclusters   Running   131m"
}

@test "vcluster_create deletes an orphan occupying the shared namespace" {
  _stub_run_command_executing
  _seed_orphan_listing e2e-1790154235-20
  run vcluster_create e2e-new-run
  [ "$status" -eq 0 ]
  run grep -F -- "$VCLUSTER_STUB delete e2e-1790154235-20 -n vclusters --wait" "$RUN_LOG"
  [ "$status" -eq 0 ]
}

@test "vcluster_create deletes the orphan before creating the new vCluster" {
  _stub_run_command_executing
  _seed_orphan_listing e2e-1790154235-20
  run vcluster_create e2e-new-run
  [ "$status" -eq 0 ]
  local delete_line create_line
  delete_line="$(grep -nF -- "delete e2e-1790154235-20" "$RUN_LOG" | head -1 | cut -d: -f1)"
  create_line="$(grep -nF -- "create e2e-new-run" "$RUN_LOG" | head -1 | cut -d: -f1)"
  [ -n "$delete_line" ]
  [ -n "$create_line" ]
  [ "$delete_line" -lt "$create_line" ]
}

@test "vcluster_create warns when it clears an orphan so a teardown regression stays visible" {
  _stub_run_command_executing
  _seed_orphan_listing e2e-1790154235-20
  run vcluster_create e2e-new-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"orphan"* ]]
  [[ "$output" == *"e2e-1790154235-20"* ]]
}

@test "vcluster_create does not delete a vCluster matching the name being created" {
  _stub_run_command_executing
  _seed_orphan_listing e2e-new-run
  run vcluster_create e2e-new-run
  [ "$status" -eq 0 ]
  run grep -F -- "delete e2e-new-run" "$RUN_LOG"
  [ "$status" -ne 0 ]
}

@test "vcluster_create issues no delete when the namespace holds no vCluster" {
  _stub_run_command_executing
  export VCLUSTER_LIST_OUTPUT=""
  run vcluster_create demo
  [ "$status" -eq 0 ]
  run grep -F -- "$VCLUSTER_STUB delete" "$RUN_LOG"
  [ "$status" -ne 0 ]
}

@test "vcluster_create dry-run clears no orphan" {
  _stub_run_command_executing
  _seed_orphan_listing e2e-1790154235-20
  DRY_RUN=1 run vcluster_create e2e-new-run
  [ "$status" -eq 0 ]
  run grep -F -- "delete e2e-1790154235-20" "$RUN_LOG"
  [ "$status" -ne 0 ]
}

@test "orphan cleanup falls back to helm uninstall when vcluster delete fails" {
  _stub_run_command_executing
  _seed_orphan_listing e2e-orphan
  export VCLUSTER_DELETE_FAILS=1
  run vcluster_create e2e-new-run
  [ "$status" -eq 0 ]
  run grep -F -- "helm -n vclusters uninstall e2e-orphan --wait" "$RUN_LOG"
  [ "$status" -eq 0 ]
}
