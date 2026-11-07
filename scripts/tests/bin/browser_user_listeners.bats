#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
  export HOME="${BATS_TEST_TMPDIR}/home"
  mkdir -p "${HOME}/Library/LaunchAgents"
  [ "${HOME}" != "${BATS_TEST_DIRNAME}/../../../../.." ]
  export PATH="${BATS_TEST_TMPDIR}/bin:${PATH}"
  mkdir -p "${BATS_TEST_TMPDIR}/bin"
}

@test "browser listeners are user agents and bind their assigned high ports" {
  run grep -En 'com.k3d-manager.browser.(argocd-https|keycloak-http|sandbox-frontend-http)|18443|18080|18083|Library/LaunchAgents' "${REPO_ROOT}/bin/cluster-up"
  [ "$status" -eq 0 ]
  run grep -En 'com.k3d-manager.browser.hostinger-frontend-http|18082|Library/LaunchAgents' "${REPO_ROOT}/scripts/lib/providers/k3s-hostinger.sh"
  [ "$status" -eq 0 ]
  run grep -En 'ifconfig lo0 alias|_acg_has_launchdaemon_sudo|LaunchDaemons/com.k3d-manager.(argocd-browser|keycloak-browser|sandbox.frontend|frontend-browser)' "${REPO_ROOT}/bin/cluster-up" "${REPO_ROOT}/bin/cluster-down" "${REPO_ROOT}/scripts/lib/providers/k3s-hostinger.sh"
  [ "$status" -ne 0 ]
}

@test "missing relay path warns and browser listener setup never uses sudo" {
  run grep -En 'make install-browser-relays|K3DM_LAUNCHD_DIR' "${REPO_ROOT}/bin/cluster-up"
  [ "$status" -eq 0 ]
  run grep -En 'sudo|interactive-sudo|prefer-sudo' "${REPO_ROOT}/bin/cluster-up"
  run bash -c 'grep -En "sudo|interactive-sudo|prefer-sudo" "$1" | grep -En "browser|LaunchDaemon|ifconfig"' _ "${REPO_ROOT}/bin/cluster-up"
  [ "$status" -ne 0 ]
}

@test "all Hostinger frontend origins use port 18082" {
  run grep -En '127\.0\.0\.2:80([^0-9]|$)' "${REPO_ROOT}/scripts/etc/cloudflared/origins.tsv" "${REPO_ROOT}/scripts/etc/cloudflared-config.yml.tmpl" "${REPO_ROOT}/scripts/etc/cloudflared/config.yml"
  [ "$status" -ne 0 ]
  [ "$(grep -Ec '127\.0\.0\.2:18082' "${REPO_ROOT}/scripts/etc/cloudflared/origins.tsv")" -eq 2 ]
}
