#!/usr/bin/env bats

setup() {
  source "${BATS_TEST_DIRNAME}/../test_helpers.bash"
  init_test_env
  source "${BATS_TEST_DIRNAME}/../../plugins/argocd.sh"
}

_ownership_fixture() {
  cat <<'EOF'
{"items":[
 {"kind":"ConfigMap","metadata":{"name":"argocd-cm","annotations":{"meta.helm.sh/release-name":"argocd"},"labels":{"argocd.argoproj.io/instance":"ubuntu-k3s-platform","app.kubernetes.io/part-of":"argocd"},"managedFields":[{"manager":"helm"},{"manager":"argocd-controller"},{"manager":"kubectl-patch"}]}},
 {"kind":"Secret","metadata":{"name":"argocd-secret","annotations":{"meta.helm.sh/release-name":"argocd"},"managedFields":[{"manager":"argocd-controller"},{"manager":"helm"},{"manager":"argocd-controller"}]}},
 {"kind":"ConfigMap","metadata":{"name":"argocd-redis-health-configmap","annotations":{"meta.helm.sh/release-name":"argocd"},"managedFields":[{"manager":"helm"}]}},
 {"kind":"ServiceAccount","metadata":{"name":"argocd-dex-server","labels":{"argocd.argoproj.io/instance":"ubuntu-k3s-platform","app.kubernetes.io/part-of":"argocd"}}},
 {"kind":"Secret","metadata":{"name":"stale-notes","labels":{"argocd.argoproj.io/instance":"ubuntu-k3s-platform","app.kubernetes.io/part-of":"argocd"}}}
]}
EOF
}

_stub_objects() {
  printf '%s\n' "$*" >>"${BATS_TEST_TMPDIR}/calls"
  if [[ "$*" == *"get configmap,secret,serviceaccount"* ]]; then
    _ownership_fixture
  fi
}

@test "argocd reclaim ownership: plan strips foreign ownership from release objects" {
  local plan
  plan="$(_ownership_fixture | _argocd_foreign_ownership_plan argocd "")"
  [[ "${plan}" == *$'strip\tconfigmap\targocd-cm\t1\tubuntu-k3s-platform'* ]]
  [[ "${plan}" == *$'strip\tsecret\targocd-secret\t2,0\t-'* ]]
  [[ "${plan}" != *"argocd-redis-health-configmap"* ]]
}

@test "argocd reclaim ownership: plan separates removable and review-only orphans" {
  local plan known_plan
  plan="$(_ownership_fixture | _argocd_foreign_ownership_plan argocd "")"
  [[ "${plan}" == *$'orphan\tserviceaccount\targocd-dex-server'* ]]
  [[ "${plan}" == *$'review\tsecret\tstale-notes'* ]]

  known_plan="$(_ownership_fixture | _argocd_foreign_ownership_plan argocd "ubuntu-k3s-platform other-app")"
  [[ "${known_plan}" != *"argocd-dex-server"* ]]
  [[ "${known_plan}" != *"stale-notes"* ]]
}

@test "argocd reclaim ownership: dry run reports without changing objects" {
  _kubectl() { _stub_objects "$@"; }

  run argocd_reclaim_release_ownership
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"--confirm"* ]]
  run grep -Eq ' (patch|label|delete) ' "${BATS_TEST_TMPDIR}/calls"
  [ "$status" -ne 0 ]
}

@test "argocd reclaim ownership: confirm patches, removes tracking, and deletes only serviceaccounts" {
  _kubectl() { _stub_objects "$@"; }

  run argocd_reclaim_release_ownership --confirm
  [ "${status}" -eq 0 ]
  local configmap_patch secret_patch
  configmap_patch="$(grep -- 'patch configmap argocd-cm' "${BATS_TEST_TMPDIR}/calls")"
  secret_patch="$(grep -- 'patch secret argocd-secret' "${BATS_TEST_TMPDIR}/calls")"
  [[ "${configmap_patch}" == *"/metadata/managedFields/1/manager"* ]]
  [[ "${configmap_patch}" == *'"op":"test"'* ]]
  [[ "${secret_patch%%/metadata/managedFields/0*}" == *"/metadata/managedFields/2"* ]]
  grep -q -- 'label configmap argocd-cm.*argocd.argoproj.io/instance-' "${BATS_TEST_TMPDIR}/calls"
  grep -q -- 'delete serviceaccount argocd-dex-server' "${BATS_TEST_TMPDIR}/calls"
  run grep -q -- 'delete secret' "${BATS_TEST_TMPDIR}/calls"
  [ "$status" -ne 0 ]
}

@test "argocd reclaim ownership: failed patch leaves tracking label untouched" {
  _kubectl() {
    _stub_objects "$@"
    [[ "$*" == *" patch "* ]] && return 1
  }

  run argocd_reclaim_release_ownership --confirm
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"managedFields strip failed"* ]]
  run grep -q -- 'label configmap argocd-cm' "${BATS_TEST_TMPDIR}/calls"
  [ "$status" -ne 0 ]
}

@test "argocd reclaim ownership: unreadable objects return 2" {
  _kubectl() { :; }

  run argocd_reclaim_release_ownership
  [ "${status}" -eq 2 ]
  [[ "${output}" == *"Could not read"* ]]
}

@test "argocd reclaim ownership: unknown option returns 2" {
  run argocd_reclaim_release_ownership --bogus
  [ "${status}" -eq 2 ]
  [[ "${output}" == *"Unknown option"* ]]
}
