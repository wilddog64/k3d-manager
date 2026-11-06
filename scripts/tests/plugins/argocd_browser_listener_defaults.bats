#!/usr/bin/env bats

@test "argocd.sh has no shared browser listener log default" {
  run grep -F 'ARGOCD_BROWSER_LISTENER_LOG:=' scripts/plugins/argocd.sh
  [ "${status}" -eq 1 ]
}

@test "argocd.sh has no shared browser listener wrapper default" {
  run grep -F 'ARGOCD_BROWSER_LISTENER_WRAPPER:=' scripts/plugins/argocd.sh
  [ "${status}" -eq 1 ]
}

@test "cluster-up keeps the per-provider browser listener log fallback" {
  run grep -F '${ARGOCD_BROWSER_LISTENER_LOG:-${_ACG_STATE_DIR}/logs/argocd-browser-https.log}' bin/cluster-up
  [ "${status}" -eq 0 ]
}

_source_argocd_like_cluster_up() {
  local plugin="${1:-scripts/plugins/argocd.sh}"
  /opt/homebrew/bin/bash -c '
    SCRIPT_DIR="$PWD/scripts"
    source scripts/lib/core.sh >/dev/null 2>&1
    source scripts/lib/provider.sh >/dev/null 2>&1
    source scripts/plugins/acg.sh >/dev/null 2>&1
    source "$1" || exit 99
    printf "label=%s\nplist=%s\n" "${ARGOCD_BROWSER_LISTENER_LABEL-unset}" "${ARGOCD_BROWSER_LISTENER_PLIST-unset}"
  ' _ "$plugin"
}

@test "sourcing argocd.sh leaves the browser listener label and plist unset" {
  [ -f scripts/plugins/argocd.sh ]
  [ -f bin/cluster-up ]
  unset ARGOCD_BROWSER_LISTENER_LABEL ARGOCD_BROWSER_LISTENER_PLIST
  run _source_argocd_like_cluster_up
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"label=unset"* ]]
  [[ "${output}" == *"plist=unset"* ]]
  [[ "${output}" != *"/Library/LaunchDaemons"* ]]
}

@test "cluster-up falls back to the user LaunchAgent label and plist" {
  run grep -F '_argocd_browser_plist="${ARGOCD_BROWSER_LISTENER_PLIST:-${HOME}/Library/LaunchAgents/${_argocd_browser_label}.plist}"' bin/cluster-up
  [ "${status}" -eq 0 ]
  run grep -F '_argocd_browser_label="${ARGOCD_BROWSER_LISTENER_LABEL:-com.k3d-manager.browser.argocd-https}"' bin/cluster-up
  [ "${status}" -eq 0 ]
}
