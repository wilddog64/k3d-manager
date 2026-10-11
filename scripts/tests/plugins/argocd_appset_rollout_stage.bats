#!/usr/bin/env bats

setup() {
  source "${BATS_TEST_DIRNAME}/../test_helpers.bash"
  init_test_env
  source "${BATS_TEST_DIRNAME}/../../plugins/argocd.sh"
  export K3D_MANAGER_BRANCH=k3d-manager-v1.43.0
  export ARGOCD_NAMESPACE=cicd
}

_stage_config() {
  ARGOCD_CONFIG_DIR="${BATS_TEST_TMPDIR}/argocd"
  mkdir -p "${ARGOCD_CONFIG_DIR}/applicationsets"
  printf '%s\n' 'metadata:' '  name: hub-set' '  labels:' '    k3dm.k3d.io/rollout-stage: hub' > "${ARGOCD_CONFIG_DIR}/applicationsets/hub.yaml"
  printf '%s\n' 'metadata:' '  name: app-set' '  labels:' '    k3dm.k3d.io/rollout-stage: app-cluster' > "${ARGOCD_CONFIG_DIR}/applicationsets/app.yaml"
  export ARGOCD_CONFIG_DIR
}

_mixed_app_fixture() {
  cat <<'EOF'
{"items":[
 {"metadata":{"name":"hub-app","ownerReferences":[{"kind":"ApplicationSet","name":"hub-set"}]},"spec":{"sources":[{"ref":"values","repoURL":"https://github.com/wilddog64/k3d-manager","targetRevision":"k3d-manager-v1.43.0"}]}},
 {"metadata":{"name":"app-app","ownerReferences":[{"kind":"ApplicationSet","name":"app-set"}]},"spec":{"sources":[{"ref":"values","repoURL":"https://github.com/wilddog64/k3d-manager","targetRevision":"k3d-manager-v1.42.0"}]}}
]}
EOF
}

@test "appset rollout stage: every manifest has a valid stage label" {
  local file stage
  for file in "${BATS_TEST_DIRNAME}/../../etc/argocd/applicationsets"/*.yaml; do
    stage="$(sed -n 's/^    k3dm\.k3d\.io\/rollout-stage: *//p' "$file" | head -1)"
    [[ "$stage" == hub || "$stage" == app-cluster ]]
  done
}

@test "appset rollout stage: hub applies before app-cluster" {
  ARGOCD_CONFIG_DIR="${BATS_TEST_TMPDIR}/argocd"
  mkdir -p "${ARGOCD_CONFIG_DIR}/applicationsets"
  printf '%s\n' 'kind: ApplicationSet' 'metadata:' '  name: app-cluster-set' '  labels:' '    k3dm.k3d.io/rollout-stage: app-cluster' > "${ARGOCD_CONFIG_DIR}/applicationsets/01-app.yaml"
  printf '%s\n' 'kind: ApplicationSet' 'metadata:' '  name: hub-set' '  labels:' '    k3dm.k3d.io/rollout-stage: hub' > "${ARGOCD_CONFIG_DIR}/applicationsets/02-hub.yaml"
  events="${BATS_TEST_TMPDIR}/events"
  prepares="${BATS_TEST_TMPDIR}/prepares"
  : > "$events"
  : > "$prepares"
  _argocd_set_active_app_cluster() { printf x >> "$prepares"; }
  _argocd_appset_live_overrides() { :; }
  _kubectl() {
    if [[ "$1" == apply ]]; then
      local content
      content="$(cat)"
      sed -n 's/^  name: /APPLY:/p' <<< "$content" >> "$events"
    fi
    return 0
  }
  export events prepares
  export -f _argocd_set_active_app_cluster _argocd_appset_live_overrides _kubectl
  K3DM_APPSETS_STAGE=all ARGOCD_CONFIG_DIR="$ARGOCD_CONFIG_DIR" run deploy_argocd_applicationsets --no-verify
  [ "$status" -eq 0 ]
  [[ "$(cat "$events")" == $'APPLY:hub-set\nAPPLY:app-cluster-set' ]]
  [ "$(wc -c < "$prepares")" -eq 1 ]
  [ "$(grep -c 'Preparing ApplicationSets' <<< "$output")" -eq 1 ]
}

@test "appset rollout stage: direct deploy prepares when no stage is supplied" {
  _stage_config
  applies="${BATS_TEST_TMPDIR}/applies"
  prepares="${BATS_TEST_TMPDIR}/prepares"
  : > "$applies"
  : > "$prepares"
  _argocd_set_active_app_cluster() { printf x >> "$prepares"; }
  _argocd_appset_live_overrides() { :; }
  _kubectl() {
    if [[ "$1" == apply ]]; then
      sed -n 's/^  name: /APPLY:/p' >> "$applies"
    fi
    return 0
  }
  export applies prepares
  export -f _argocd_set_active_app_cluster _argocd_appset_live_overrides _kubectl

  run _argocd_deploy_applicationsets
  [ "$status" -eq 0 ]
  [ "$(wc -c < "$prepares")" -eq 1 ]
  [ "$(grep -c '^APPLY:' "$applies")" -eq 2 ]
  grep -qx 'APPLY:hub-set' <(cat "$applies")
  grep -qx 'APPLY:app-set' <(cat "$applies")
}

@test "appset rollout stage: failed hub confirmation prevents app-cluster apply" {
  stages="${BATS_TEST_TMPDIR}/stages"
  : > "$stages"
  _argocd_deploy_applicationsets() { printf '%s\n' "$1" >> "$stages"; }
  argocd_check_values_branch() { return 1; }
  sleep() { :; }
  export -f _argocd_deploy_applicationsets argocd_check_values_branch sleep
  K3DM_APPSETS_STAGE=all K3DM_APPSET_CONFIRM_TIMEOUT=0 run deploy_argocd_applicationsets
  [ "$status" -eq 1 ]
  [ "$(cat "$stages")" = hub ]
  [[ "$output" == *"app-cluster ApplicationSets NOT applied"* ]]
}

@test "appset rollout stage: hub applies only the hub stage" {
  stages="${BATS_TEST_TMPDIR}/stages"
  : > "$stages"
  _argocd_deploy_applicationsets() { printf '%s\n' "$1" >> "$stages"; }
  export -f _argocd_deploy_applicationsets
  K3DM_APPSETS_STAGE=hub run deploy_argocd_applicationsets --no-verify
  [ "$status" -eq 0 ]
  [ "$(cat "$stages")" = hub ]
}

@test "appset rollout stage: unlabelled manifest aborts before apply" {
  ARGOCD_CONFIG_DIR="${BATS_TEST_TMPDIR}/argocd"
  mkdir -p "${ARGOCD_CONFIG_DIR}/applicationsets"
  printf '%s\n' 'kind: ApplicationSet' 'metadata:' '  name: unlabelled' > "${ARGOCD_CONFIG_DIR}/applicationsets/unlabelled.yaml"
  applies="${BATS_TEST_TMPDIR}/applies"
  : > "$applies"
  _argocd_set_active_app_cluster() { :; }
  _kubectl() { [[ "$1" != apply ]] || printf x >> "$applies"; }
  export -f _argocd_set_active_app_cluster _kubectl
  ARGOCD_CONFIG_DIR="$ARGOCD_CONFIG_DIR" run deploy_argocd_applicationsets --no-verify
  [ "$status" -eq 1 ]
  [ ! -s "$applies" ]
  [[ "$output" == *"missing or unknown"* ]]
}

@test "appset rollout stage: confirmation checks only its owners" {
  _stage_config
  _kubectl() { _mixed_app_fixture; }
  export -f _kubectl

  run _argocd_confirm_applicationset_stage hub
  [ "$status" -eq 0 ]

  K3DM_APPSET_CONFIRM_TIMEOUT=0 run _argocd_confirm_applicationset_stage app-cluster
  [ "$status" -ne 0 ]
  [[ "$output" == *"app-app"* ]]
}

@test "appset rollout stage: Degraded owned Application fails hub confirmation" {
  _stage_config
  _kubectl() {
    cat <<'EOF'
{"items":[{"metadata":{"name":"hub-app","ownerReferences":[{"kind":"ApplicationSet","name":"hub-set"}]},"spec":{"sources":[{"repoURL":"https://github.com/wilddog64/k3d-manager","targetRevision":"k3d-manager-v1.43.0"}]},"status":{"health":{"status":"Degraded"}}}]}
EOF
  }
  export -f _kubectl

  K3DM_APPSET_CONFIRM_TIMEOUT=0 run _argocd_confirm_applicationset_stage hub
  [ "$status" -ne 0 ]
  [[ "$output" == *"hub-app health Degraded"* ]]
}

@test "appset rollout stage: all confirms and applies app-cluster after hub" {
  _stage_config
  events="${BATS_TEST_TMPDIR}/events"
  : > "$events"
  state="${BATS_TEST_TMPDIR}/state"
  printf 'hub\n' > "$state"
  _kubectl() {
    if [[ "$1" == apply ]]; then
      local content name
      content="$(cat)"
      name="$(sed -n 's/^  name: //p' <<< "$content" | head -1)"
      printf '%s\n' "$name" >> "$events"
      [[ "$name" == app-set ]] && printf 'app\n' > "$state"
      return 0
    fi
    if [[ "$1" == get && "$2" == application ]]; then
      if [[ -s "$state" && "$(cat "$state")" == app ]]; then
        _mixed_app_fixture | sed 's/k3d-manager-v1.42.0/k3d-manager-v1.43.0/'
      else
        _mixed_app_fixture
      fi
    fi
  }
  _argocd_set_active_app_cluster() { :; }
  export events state
  export -f _kubectl _argocd_set_active_app_cluster

  K3DM_APPSETS_STAGE=all ARGOCD_APPSET_IGNORE_LIVE=1 run deploy_argocd_applicationsets
  [ "$status" -eq 0 ]
  [ "$(cat "$events")" = $'hub-set\napp-set' ]
}

@test "appset rollout stage: owners matching nothing fails closed" {
  _stage_config
  _kubectl() { _mixed_app_fixture; }
  export -f _kubectl

  run argocd_check_values_branch k3d-manager-v1.43.0 k3d-k3d-cluster nosuchset
  [ "$status" -eq 2 ]
  [[ "$output" == *"inspected 0 references"* ]]
}

@test "appset rollout stage: a stage with no manifests fails instead of checking every Application" {
  ARGOCD_CONFIG_DIR="${BATS_TEST_TMPDIR}/argocd"
  mkdir -p "${ARGOCD_CONFIG_DIR}/applicationsets"
  printf '%s\n' 'kind: ApplicationSet' 'metadata:' '  name: hub-set' '  labels:' '    k3dm.k3d.io/rollout-stage: hub' > "${ARGOCD_CONFIG_DIR}/applicationsets/hub.yaml"
  checks="${BATS_TEST_TMPDIR}/checks"
  : > "$checks"
  argocd_check_values_branch() { printf x >> "$checks"; return 0; }
  K3DM_APPSET_CONFIRM_TIMEOUT=0 run _argocd_confirm_applicationset_stage app-cluster
  [ "$status" -ne 0 ]
  [[ "$output" == *"no ApplicationSet manifests carry rollout stage app-cluster"* ]]
  [ ! -s "$checks" ]
}

@test "appset rollout stage: an unknown stage refuses before preparing" {
  _stage_config
  prepares="${BATS_TEST_TMPDIR}/prepares"
  : > "$prepares"
  _argocd_set_active_app_cluster() { printf x >> "$prepares"; }
  export prepares
  export -f _argocd_set_active_app_cluster
  K3DM_APPSETS_STAGE=bogus run deploy_argocd_applicationsets --no-verify
  [ "$status" -eq 1 ]
  [[ "$output" == *"must be hub or all"* ]]
  [ ! -s "$prepares" ]
}
