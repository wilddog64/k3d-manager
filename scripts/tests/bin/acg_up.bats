#!/usr/bin/env bats

@test "acg-up sources the Argo CD plugin before readiness checks" {
  run grep -nF 'PLUGINS_DIR="${SCRIPT_DIR}/plugins"' bin/acg-up
  [ "$status" -eq 0 ]
  [[ "$output" == *'PLUGINS_DIR="${SCRIPT_DIR}/plugins"'* ]]

  run grep -nF 'source "${REPO_ROOT}/scripts/plugins/argocd.sh"' bin/acg-up
  [ "$status" -eq 0 ]
  [[ "$output" == *"scripts/plugins/argocd.sh"* ]]

  run grep -nF 'source "${REPO_ROOT}/scripts/plugins/keycloak.sh"' bin/acg-up
  [ "$status" -eq 0 ]
  [[ "$output" == *"scripts/plugins/keycloak.sh"* ]]

  run grep -nF '_argocd_write_port_forward_wrapper "${_argocd_pf_wrapper}" "${_argocd_pf_log}"' bin/acg-up
  [ "$status" -eq 0 ]
  [[ "$output" == *"_argocd_write_port_forward_wrapper"* ]]

  run grep -nF '_argocd_write_browser_https_wrapper "${_argocd_browser_wrapper}" "${_argocd_browser_log}"' bin/acg-up
  [ "$status" -eq 0 ]
  [[ "$output" == *"_argocd_write_browser_https_wrapper"* ]]

  run grep -nF '_argocd_issue_browser_tls_material "${_argocd_browser_tls_dir}"' bin/acg-up
  [ "$status" -eq 0 ]
  [[ "$output" == *"_argocd_issue_browser_tls_material"* ]]

  run grep -nF '_argocd_browser_https_is_ready "https://${ARGOCD_BROWSER_HOST:-argocd.shopping-cart.local}:${ARGOCD_BROWSER_PORT:-443}/healthz"' bin/acg-up
  [ "$status" -eq 0 ]
  [[ "$output" == *"_argocd_browser_https_is_ready"* ]]

  run grep -nF '_argocd_write_port_forward_wrapper "${_keycloak_browser_wrapper}" "${_keycloak_browser_log}"' bin/acg-up
  [ "$status" -eq 0 ]
  [[ "$output" == *"_argocd_write_port_forward_wrapper"* ]]

  run grep -nF 'svc/keycloak" "80" "80" "http://127.0.0.1/health/ready"' bin/acg-up
  [ "$status" -eq 0 ]
  [[ "$output" == *"health/ready"* ]]

  run grep -nF '_keycloak_browser_label="com.k3d-manager.keycloak-browser-http"' bin/acg-up
  [ "$status" -eq 0 ]
  [[ "$output" == *"keycloak-browser-http"* ]]

  run grep -nF '_keycloak_browser_plist="${KEYCLOAK_BROWSER_LISTENER_PLIST:-/Library/LaunchDaemons/${_keycloak_browser_label}.plist}"' bin/acg-up
  [ "$status" -eq 0 ]
  [[ "$output" == *"/Library/LaunchDaemons/"* ]]

  run grep -nF '_argocd_browser_launchctl_log="${ARGOCD_BROWSER_LISTENER_LAUNCHCTL_LOG:-${HOME}/.local/share/k3d-manager/argocd-browser-https-launchctl.log}"' bin/acg-up
  [ "$status" -eq 0 ]
  [[ "$output" == *"argocd-browser-https-launchctl.log"* ]]

  run grep -nF '_run_command --interactive-sudo --quiet --soft -- launchctl bootout system "${_argocd_browser_plist}"' bin/acg-up
  [ "$status" -eq 0 ]
  [[ "$output" == *"launchctl bootout system"* ]]

  run grep -nF '_run_command --interactive-sudo --quiet -- launchctl bootstrap system "${_argocd_browser_plist}"' bin/acg-up
  [ "$status" -eq 0 ]
  [[ "$output" == *"launchctl bootstrap system"* ]]

  run grep -nF 'ArgoCD port-forward ready at http://localhost:8080 (terminal-only; browser login uses https://${ARGOCD_BROWSER_HOST:-argocd.shopping-cart.local})' bin/acg-up
  [ "$status" -eq 0 ]
  [[ "$output" == *'terminal-only; browser login uses https://${ARGOCD_BROWSER_HOST:-argocd.shopping-cart.local}'* ]]

  run grep -nF 'ArgoCD browser HTTPS listener already healthy at https://${ARGOCD_BROWSER_HOST:-argocd.shopping-cart.local}:${ARGOCD_BROWSER_PORT:-443} — skipping launchd reinstall' bin/acg-up
  [ "$status" -eq 0 ]
  [[ "$output" == *"skipping launchd reinstall"* ]]

  run grep -nF 'Opening canonical ArgoCD browser URL: ${_argocd_browser_url}' bin/acg-up
  [ "$status" -eq 0 ]
  [[ "$output" == *"Opening canonical ArgoCD browser URL"* ]]

  run grep -nF '_keycloak_browser_kubeconfig="${HOME}/.kube/config"' bin/acg-up
  [ "$status" -eq 0 ]
  [[ "$output" == *".kube/config"* ]]

  run grep -nF '_kc_browser_ip="127.0.0.1"' bin/acg-up
  [ "$status" -eq 0 ]
  [[ "$output" == *'_kc_browser_ip="127.0.0.1"'* ]]

  run grep -nF 'Step 10e/14 — Installing Keycloak browser HTTP listener' bin/acg-up
  [ "$status" -eq 0 ]
  [[ "$output" == *"Keycloak browser HTTP listener"* ]]

  run grep -nF 'Step 10f/14 — Wiring ArgoCD SSO' bin/acg-up
  [ "$status" -eq 0 ]
  [[ "$output" == *"Wiring ArgoCD SSO"* ]]
}

@test "acg-up preserves existing Vault identity secrets on rebuild" {
  run grep -nF '_vault_kv_exists "keycloak/admin"' bin/acg-up
  [ "$status" -eq 0 ]
  [[ "$output" == *'_vault_kv_exists "keycloak/admin"'* ]]

  run grep -nF '_vault_kv_exists "keycloak/clients"' bin/acg-up
  [ "$status" -eq 0 ]
  [[ "$output" == *'_vault_kv_exists "keycloak/clients"'* ]]

  run grep -nF '_vault_kv_exists "ldap/admin"' bin/acg-up
  [ "$status" -eq 0 ]
  [[ "$output" == *'_vault_kv_exists "ldap/admin"'* ]]
}
