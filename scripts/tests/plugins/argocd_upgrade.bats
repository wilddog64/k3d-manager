#!/usr/bin/env bats

setup() {
  bats_require_minimum_version 1.5.0
  source "${BATS_TEST_DIRNAME}/../test_helpers.bash"
  init_test_env
  source "${BATS_TEST_DIRNAME}/../../plugins/argocd.sh"
  export K3DM_STATE_DIR="$BATS_TEST_TMPDIR/state"
  export CALLS="$BATS_TEST_TMPDIR/calls"
  : >"$CALLS"
  _kubectl() {
    printf 'kubectl %s\n' "$*" >>"$CALLS"
    case "$*" in
      *config\ current-context*) printf '%s\n' "${STUB_CONTEXT:-k3d-k3d-cluster}" ;;
      *get\ --raw=/readyz*) return 0 ;;
      *get\ applications.argoproj.io*)
        printf 'app-get\n' >>"$CALLS"
        if [[ "${DROP_APPS:-0}" == 1 && "$(grep -c '^app-get$' "$CALLS")" -gt 1 ]]; then
          printf '{"items":[]}'
        elif [[ "${DEGRADE_APPS:-0}" == 1 && "$(grep -c '^app-get$' "$CALLS")" -gt 1 ]]; then
          printf '{"items":[{"metadata":{"name":"demo"},"status":{"sync":{"status":"OutOfSync"},"health":{"status":"Degraded"}}}]}'
        else
          printf '{"items":[{"metadata":{"name":"demo"},"status":{"sync":{"status":"Synced"},"health":{"status":"Healthy"}}}]}'
        fi ;;
      *rollout\ status*) return 0 ;;
      *) return 0 ;;
    esac
  }
  _helm() {
    printf 'helm %s\n' "$*" >>"$CALLS"
    case "$*" in
      status*) printf '{"info":{"status":"deployed"},"chart":"argo-cd-10.10.4","version":7}' ;;
      show\ chart*) return 0 ;;
      repo\ update*) return 0 ;;
      upgrade*) return 0 ;;
    esac
  }
  _argocd_ensure_servicemonitors() { :; }
  export ARGOCD_HELM_CHART_VERSION=10.10.5 ARGOCD_UPGRADE_SETTLE_SECONDS=0
}

@test "pin is nonempty and deploy path pins chart" {
  run grep -F 'ARGOCD_HELM_CHART_VERSION="10.10.5"' "${BATS_TEST_DIRNAME}/../../etc/argocd/vars.sh"
  [ "$status" -eq 0 ]
}

@test "dry run snapshots baseline without upgrade or apply" {
  run argocd_upgrade --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"helm upgrade --install"* ]]
  run grep -E 'helm upgrade|kubectl .*apply' "$CALLS"
  [ "$status" -eq 1 ]
  [ -n "$(find "$K3DM_STATE_DIR" -name before.json -type f -print -quit)" ]
}

@test "equal target exits without helm upgrade" {
  _helm() {
    case "$*" in status*) printf '{"info":{"status":"deployed"},"chart":"argo-cd-10.10.5","version":8}' ;; show\ chart*|repo\ update*) return 0 ;; esac
  }
  run argocd_upgrade
  [ "$status" -eq 0 ]
  [[ "$output" == *"already at 10.10.5"* ]]
}

@test "unknown version and unreachable context stop before upgrade" {
  _helm() { case "$*" in status*) printf '{"info":{"status":"deployed"},"chart":"argo-cd-10.10.4","version":7}' ;; repo\ update*) return 0 ;; show\ chart*) return 1 ;; esac; }
  run argocd_upgrade
  [ "$status" -ne 0 ]
  _kubectl() { return 1; }
  run argocd_upgrade
  [ "$status" -ne 0 ]
}

@test "older target is refused without downgrade flag" {
  _helm() { case "$*" in status*) printf '{"info":{"status":"deployed"},"chart":"argo-cd-10.10.6","version":7}' ;; show\ chart*|repo\ update*) return 0 ;; esac; }
  run argocd_upgrade --to 10.10.5
  [ "$status" -ne 0 ]
  run grep -E 'helm upgrade|kubectl .*apply' "$CALLS"
  [ "$status" -eq 1 ]
}

@test "upgrade writes after snapshot and invokes chart deploy helper" {
  run argocd_upgrade
  [ "$status" -eq 0 ]
  grep -q '^helm upgrade' "$CALLS"
  [ -n "$(find "$K3DM_STATE_DIR" -name after.json -type f -print -quit)" ]
  [ -n "$(find "$K3DM_STATE_DIR" -name metadata.json -type f -print -quit)" ]
}

@test "degraded baseline Application fails postcheck and prints rollback hint" {
  export DEGRADE_APPS=1
  run argocd_upgrade
  [ "$status" -ne 0 ]
  [[ "$output" == *"helm rollback argocd 7 -n cicd"* ]]
  [[ "$output" == *"demo"* ]]
  [ -n "$(find "$K3DM_STATE_DIR" -name after.json -type f -print -quit)" ]
}

@test "a context other than the hub stops before any helm call" {
  STUB_CONTEXT=sandbox-acg run argocd_upgrade
  [ "$status" -ne 0 ]
  [[ "$output" == *"is not the hub"* ]]
  run grep -E '^helm ' "$CALLS"
  [ "$status" -eq 1 ]
}

@test "an Application missing after the upgrade fails the postcheck" {
  DROP_APPS=1 run argocd_upgrade
  [ "$status" -ne 0 ]
  [[ "$output" == *'"name": "demo"'* ]]
  [[ "$output" == *"Missing"* ]]
  [[ "$output" == *"helm rollback argocd 7 -n cicd"* ]]
}

@test "dry run prints the deploy helper's values and set flags" {
  run argocd_upgrade --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"--set-string configs.cm.url="* ]]
  [[ "$output" == *"values.yaml.tmpl"* ]]
  [[ "$output" == *"--version 10.10.5"* ]]
}
