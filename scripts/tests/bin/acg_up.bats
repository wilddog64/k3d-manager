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

  run grep -nF 'Step 4c/12 — Installing ArgoCD browser HTTPS listener' bin/acg-up
  [ "$status" -eq 0 ]
  [[ "$output" == *"browser HTTPS listener"* ]]
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
