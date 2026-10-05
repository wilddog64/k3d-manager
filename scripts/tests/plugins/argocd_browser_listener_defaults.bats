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
