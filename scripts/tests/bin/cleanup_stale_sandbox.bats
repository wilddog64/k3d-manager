#!/usr/bin/env bats

setup() {
  unset CONFIRM INFRA_CONTEXT ARGOCD_HUB_CONTEXT ARGOCD_NAMESPACE ARGOCD_APP_CLUSTER_NAME FAIL_ARGO_GET FAIL_ARGO_DELETE READYZ_OK
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
  FAKE_BIN="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "${FAKE_BIN}" "${BATS_TEST_TMPDIR}/home/Library/LaunchAgents"
  cat > "${FAKE_BIN}/launchctl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${BATS_TEST_TMPDIR}/launchctl.log"
if [[ "${FAIL_AGENT:-0}" == 1 ]]; then exit 1; fi
exit 0
EOF
  cat > "${FAKE_BIN}/kubectl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${BATS_TEST_TMPDIR}/kubectl.log"
if [[ "${FAIL_KUBECTL:-0}" == 1 ]]; then exit 1; fi
if [[ "$*" == "config get-contexts -o name" ]]; then
  printf '%s\n' "${ACG_KUBE_CONTEXT:-ubuntu-k3s}"
  exit 0
fi
if [[ "$*" == "config delete-context "* ]]; then
  printf 'deleted %s\n' "${ACG_KUBE_CONTEXT:-ubuntu-k3s}"
  exit 0
fi
case " $* " in
  *" get --raw=/readyz "*) [[ "${READYZ_OK:-0}" == 1 ]] && exit 0 || exit 1 ;;
esac
if [[ " $* " == *" get "* ]]; then
  kind=''
  case " $* " in
    *" applicationsets.argoproj.io "*) kind=appsets ;;
    *" applications.argoproj.io "*) kind=apps ;;
    *" secrets "*) kind=secrets ;;
  esac
  if [[ -n "${kind}" ]]; then
    [[ "${FAIL_ARGO_GET:-}" == "${kind}" ]] && exit 1
    fixture="${BATS_TEST_TMPDIR}/fx/${kind}.json"
    [[ -f "${fixture}" ]] && cat "${fixture}" || printf '{"items":[]}\n'
    exit 0
  fi
fi
if [[ " $* " == *" delete "* ]]; then
  [[ "${FAIL_ARGO_DELETE:-}" == "${!#}" ]] && exit 1
  exit 0
fi
exit 1
EOF
  chmod +x "${FAKE_BIN}/launchctl" "${FAKE_BIN}/kubectl"
  export HOME="${BATS_TEST_TMPDIR}/home" PATH="${FAKE_BIN}:${PATH}" CLUSTER_PROVIDER=k3s-aws ACG_KUBE_CONTEXT=ubuntu-k3s
  [[ "$(command -v kubectl)" == "${FAKE_BIN}/kubectl" ]]
  [[ "$(command -v launchctl)" == "${FAKE_BIN}/launchctl" ]]
}

_write_argocd_fixtures() {
  mkdir -p "${BATS_TEST_TMPDIR}/fx"
  cat > "${BATS_TEST_TMPDIR}/fx/appsets.json" <<'EOF'
{"items":[{"metadata":{"name":"istio-ambient"},"spec":{"template":{"spec":{"destination":{"name":"ubuntu-k3s"}}}}},{"metadata":{"name":"sbx2"},"spec":{"template":{"spec":{"destination":{"name":"ubuntu-k3s-2"}}}}},{"metadata":{"name":"data-git"},"spec":{"template":{"spec":{"destination":{"name":"{{.name}}"}}}}},{"metadata":{"name":"observability"},"spec":{"template":{"spec":{"destination":{"server":"https://kubernetes.default.svc"}}}}},{"metadata":{"name":"odd"},"spec":{"template":{"spec":{"destination":{"name":"ubuntu-k3s","server":"https://other"}}}}}]}
EOF
  cat > "${BATS_TEST_TMPDIR}/fx/apps.json" <<'EOF'
{"items":[{"metadata":{"name":"istio-base"},"spec":{"destination":{"name":"ubuntu-k3s"}}},{"metadata":{"name":"other-sbx"},"spec":{"destination":{"name":"ubuntu-k3s-2"}}},{"metadata":{"name":"frontend"},"spec":{"destination":{"name":"ubuntu-hostinger"}}},{"metadata":{"name":"hub-app"},"spec":{"destination":{"name":"k3d-cluster"}}},{"metadata":{"name":"hub-infra"},"spec":{"destination":{"server":"https://kubernetes.default.svc"}}},{"metadata":{"name":"hub-in"},"spec":{"destination":{"name":"in-cluster"}}}]}
EOF
  cat > "${BATS_TEST_TMPDIR}/fx/secrets.json" <<'EOF'
{"items":[{"metadata":{"name":"cluster-ubuntu-hostinger"},"data":{"name":"dWJ1bnR1LWhvc3Rpbmdlcg==","server":"aHR0cHM6Ly9ob3N0aW5nZXI="}},{"metadata":{"name":"ubuntu-k3s-app-cluster"},"data":{"name":"azNkLWNsdXN0ZXI=","server":"aHR0cHM6Ly9rdWJlcm5ldGVzLmRlZmF1bHQuc3Zj"}},{"metadata":{"name":"cluster-ubuntu-k3s"},"data":{"name":"dWJ1bnR1LWszcw==","server":"aHR0cHM6Ly9vdGhlcg=="}},{"metadata":{"name":"cluster-ubuntu-k3s-2"},"data":{"name":"dWJ1bnR1LWszcy0y","server":"aHR0cHM6Ly9vdGhlcg=="}}]}
EOF
}

@test "dry run reports the sole matching candidate and listed-only resources" {
  _write_argocd_fixtures
  run "${REPO_ROOT}/bin/cleanup-stale-sandbox" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"ArgoCD ApplicationSet targeting ubuntu-k3s: istio-ambient"* ]]
  [[ "$output" == *"ArgoCD Application targeting ubuntu-k3s: istio-base"* ]]
  [[ "$output" == *"ArgoCD cluster secret targeting ubuntu-k3s: cluster-ubuntu-k3s"* ]]
  cleanup_output="$output"
  run grep -F 'ArgoCD cluster secret targeting ubuntu-k3s: cluster-ubuntu-k3s-2' <<< "$cleanup_output"
  [ "$status" -ne 0 ]
  [[ "$cleanup_output" == *"DRY RUN: no changes made"* ]]
  run grep -q ' delete ' "${BATS_TEST_TMPDIR}/kubectl.log"
  [ "$status" -ne 0 ]
}

@test "confirm deletes only the dead sandbox candidate with bounded kubectl calls" {
  _write_argocd_fixtures
  run "${REPO_ROOT}/bin/cleanup-stale-sandbox" --confirm
  [ "$status" -eq 0 ]
  [ "$(grep -c ' delete ' "${BATS_TEST_TMPDIR}/kubectl.log")" -eq 1 ]
  grep -F -- 'delete applicationset.argoproj.io --wait=false -- istio-ambient' "${BATS_TEST_TMPDIR}/kubectl.log"
  run grep -E 'delete.*(sbx2|odd|istio-base|cluster-ubuntu)' "${BATS_TEST_TMPDIR}/kubectl.log"
  [ "$status" -ne 0 ]
  argo_calls="$(grep -E -- '--context .* -n cicd .* (get|delete)' "${BATS_TEST_TMPDIR}/kubectl.log")"
  run grep -v -- '--request-timeout=5s' <<< "${argo_calls}"
  [ "$status" -ne 0 ]
  grep -F 'secret-type=cluster' "${BATS_TEST_TMPDIR}/kubectl.log"
}

@test "environment CONFIRM alone never authorizes ArgoCD deletion" {
  _write_argocd_fixtures
  run env CONFIRM=1 "${REPO_ROOT}/bin/cleanup-stale-sandbox" --dry-run
  [ "$status" -eq 0 ]
  run env CONFIRM=1 "${REPO_ROOT}/bin/cleanup-stale-sandbox"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ArgoCD deletes need --confirm (CONFIRM env is not enough)"* ]]
  run grep -q ' delete ' "${BATS_TEST_TMPDIR}/kubectl.log"
  [ "$status" -ne 0 ]
}

@test "refused sandbox names make no ArgoCD calls" {
  for name in '' ubuntu-hostinger k3d-cluster in-cluster ubuntu-gcp ubuntu-azure k3s-oci --all ubuntu_k3s; do
    : > "${BATS_TEST_TMPDIR}/kubectl.log"
    run env ARGOCD_APP_CLUSTER_NAME="${name}" "${REPO_ROOT}/bin/cleanup-stale-sandbox" --dry-run
    [ "$status" -eq 1 ]
    [[ "$output" == *"refusing sandbox name '${name}'"* ]]
    [[ "$output" == *"DRY RUN: no changes made"* ]]
    run grep -q -- '--context k3d-k3d-cluster' "${BATS_TEST_TMPDIR}/kubectl.log"
    [ "$status" -ne 0 ]

    : > "${BATS_TEST_TMPDIR}/kubectl.log"
    run env ARGOCD_APP_CLUSTER_NAME="${name}" "${REPO_ROOT}/bin/cleanup-stale-sandbox" --confirm
    [ "$status" -eq 1 ]
    [[ "$output" == *"refusing sandbox name '${name}'"* ]]
    run grep -q -- '--context k3d-k3d-cluster' "${BATS_TEST_TMPDIR}/kubectl.log"
    [ "$status" -ne 0 ]
  done
}

@test "reachable sandbox and cross-cluster owned applications prevent deletion" {
  _write_argocd_fixtures
  run env READYZ_OK=1 "${REPO_ROOT}/bin/cleanup-stale-sandbox" --confirm
  [ "$status" -eq 0 ]
  [[ "$output" == *"sandbox API is reachable; not deleting ArgoCD objects"* ]]
  run grep -q ' delete ' "${BATS_TEST_TMPDIR}/kubectl.log"
  [ "$status" -ne 0 ]

  jq '.items[0].metadata.ownerReferences=[{"kind":"ApplicationSet","name":"istio-ambient"}] | .items[0].spec.destination.name="ubuntu-hostinger"' "${BATS_TEST_TMPDIR}/fx/apps.json" > "${BATS_TEST_TMPDIR}/fx/apps2.json"
  mv "${BATS_TEST_TMPDIR}/fx/apps2.json" "${BATS_TEST_TMPDIR}/fx/apps.json"
  : > "${BATS_TEST_TMPDIR}/kubectl.log"
  run "${REPO_ROOT}/bin/cleanup-stale-sandbox" --confirm
  [ "$status" -eq 1 ]
  [[ "$output" == *"owns Applications on other clusters; not deleting"* ]]
  run grep -q ' delete ' "${BATS_TEST_TMPDIR}/kubectl.log"
  [ "$status" -ne 0 ]
}

@test "discovery failure stops later reads and is informational only in dry run" {
  run env FAIL_ARGO_GET=apps "${REPO_ROOT}/bin/cleanup-stale-sandbox" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"could not inspect ArgoCD Application"* ]]
  : > "${BATS_TEST_TMPDIR}/kubectl.log"
  run env FAIL_ARGO_GET=apps "${REPO_ROOT}/bin/cleanup-stale-sandbox" --confirm
  [ "$status" -eq 1 ]
  [[ "$output" == *"Cleanup incomplete"* ]]
  run grep -q 'get secrets' "${BATS_TEST_TMPDIR}/kubectl.log"
  [ "$status" -ne 0 ]
  run grep -q ' delete ' "${BATS_TEST_TMPDIR}/kubectl.log"
  [ "$status" -ne 0 ]
}

@test "delete failures are reported and hub context and namespace are applied" {
  _write_argocd_fixtures
  run env FAIL_ARGO_DELETE=istio-ambient ARGOCD_HUB_CONTEXT=custom-hub ARGOCD_NAMESPACE=custom-ns "${REPO_ROOT}/bin/cleanup-stale-sandbox" --confirm
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAILED: could not delete ArgoCD ApplicationSet: istio-ambient"* ]]
  run grep -E 'get applicationsets|applications.argoproj.io|get secrets|delete applicationset.argoproj.io' "${BATS_TEST_TMPDIR}/kubectl.log"
  [ "$status" -eq 0 ]
  run grep -v -- '--context custom-hub -n custom-ns --request-timeout=5s' <<< "$output"
  [ "$status" -ne 0 ]
}

@test "cleanup-stale-sandbox preview makes no changes" {
  run "${REPO_ROOT}/bin/cleanup-stale-sandbox" --dry-run
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"DRY RUN: no changes made"* ]]
  [ ! -e "${HOME}/Library/LaunchAgents/com.k3d-manager.frontend-port-forward.plist" ]
}

@test "cleanup-stale-sandbox reports successful removals" {
  touch "${HOME}/Library/LaunchAgents/com.k3d-manager.frontend-port-forward.plist"
  run "${REPO_ROOT}/bin/cleanup-stale-sandbox" --apply
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"stopped launchd agent: com.k3d-manager.frontend-port-forward"* ]]
  [[ "${output}" == *"removed kube context: ubuntu-k3s"* ]]
  [[ "${output}" == *"Cleanup complete"* ]]
  [ ! -e "${HOME}/Library/LaunchAgents/com.k3d-manager.frontend-port-forward.plist" ]
}

@test "cleanup-stale-sandbox never touches the Hostinger pushgateway agent" {
  touch "${HOME}/Library/LaunchAgents/com.k3d-manager.pushgateway-port-forward.plist"
  touch "${HOME}/Library/LaunchAgents/com.k3d-manager.sandbox.pushgateway-port-forward.plist"
  run "${REPO_ROOT}/bin/cleanup-stale-sandbox" --apply
  [ "${status}" -eq 0 ]
  [ -e "${HOME}/Library/LaunchAgents/com.k3d-manager.pushgateway-port-forward.plist" ]
  [ ! -e "${HOME}/Library/LaunchAgents/com.k3d-manager.sandbox.pushgateway-port-forward.plist" ]
  [[ "$(<"${BATS_TEST_TMPDIR}/launchctl.log")" == *"bootout gui/"*"com.k3d-manager.sandbox.pushgateway-port-forward"* ]]
  run grep -F "/com.k3d-manager.pushgateway-port-forward" "${BATS_TEST_TMPDIR}/launchctl.log"
  [ "${status}" -ne 0 ]
}

@test "cleanup-stale-sandbox removes the sandbox Prometheus agent" {
  touch "${HOME}/Library/LaunchAgents/com.k3d-manager.sandbox.prometheus-port-forward.plist"
  touch "${HOME}/Library/LaunchAgents/com.k3d-manager.prometheus-port-forward.plist"
  run "${REPO_ROOT}/bin/cleanup-stale-sandbox" --apply
  [ "${status}" -eq 0 ]
  [ ! -e "${HOME}/Library/LaunchAgents/com.k3d-manager.sandbox.prometheus-port-forward.plist" ]
  [ -e "${HOME}/Library/LaunchAgents/com.k3d-manager.prometheus-port-forward.plist" ]
  [[ "$(<"${BATS_TEST_TMPDIR}/launchctl.log")" == *"com.k3d-manager.sandbox.prometheus-port-forward"* ]]
  run grep -F "com.k3d-manager.prometheus-port-forward" "${BATS_TEST_TMPDIR}/launchctl.log"
  [ "${status}" -ne 0 ]
}

@test "cleanup-stale-sandbox returns failure for an agent operation" {
  touch "${HOME}/Library/LaunchAgents/com.k3d-manager.frontend-port-forward.plist"
  run env FAIL_AGENT=1 "${REPO_ROOT}/bin/cleanup-stale-sandbox" --confirm
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"FAILED: could not stop launchd agent"* ]]
  [[ "${output}" == *"Cleanup incomplete"* ]]
}

@test "cleanup-stale-sandbox returns failure when kubeconfig cannot be inspected" {
  run env FAIL_KUBECTL=1 "${REPO_ROOT}/bin/cleanup-stale-sandbox" --confirm
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"FAILED: could not inspect kube contexts"* ]]
  [[ "${output}" == *"Cleanup incomplete"* ]]
}
