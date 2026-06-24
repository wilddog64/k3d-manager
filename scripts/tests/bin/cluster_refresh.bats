#!/usr/bin/env bats

@test "cluster-refresh regenerates browser wrappers before bootstrapping launchd" {
  run grep -nF '_argocd_write_browser_https_wrapper "${_argocd_browser_wrapper}" "${_argocd_browser_log}"' bin/cluster-refresh
  [ "$status" -eq 0 ]
  [[ "$output" == *"_argocd_write_browser_https_wrapper"* ]]

  run grep -nF 'regenerating argocd-browser-https wrapper' bin/cluster-refresh
  [ "$status" -eq 0 ]
  [[ "$output" == *"regenerating argocd-browser-https wrapper"* ]]

  run grep -nF '_frontend_browser_wrapper="${_ACG_STATE_DIR}/bin/frontend-browser-http.sh"' bin/cluster-refresh
  [ "$status" -eq 0 ]
  [[ "$output" == *"frontend-browser-http.sh"* ]]

  run grep -nF 'starting frontend port-forward: svc/frontend → 127.0.0.2:80' bin/cluster-refresh
  [ "$status" -eq 0 ]
  [[ "$output" == *"starting frontend port-forward"* ]]
}
