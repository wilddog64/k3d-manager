#!/usr/bin/env bats

@test "acg-up sources the Argo CD plugin before readiness checks" {
  run grep -nF 'NODE_PATH="${_ACG_DIR}/node_modules" node -e "require('\''playwright'\'')"' bin/cluster-up
  [ "$status" -eq 0 ]
  [[ "$output" == *"require('playwright')"* ]]

  run grep -nF 'npm --prefix "${_ACG_DIR}" ci' bin/cluster-up
  [ "$status" -eq 0 ]
  [[ "$output" == *'npm --prefix "${_ACG_DIR}" ci'* ]]

  run grep -nF 'PLUGINS_DIR="${SCRIPT_DIR}/plugins"' bin/cluster-up
  [ "$status" -eq 0 ]
  [[ "$output" == *'PLUGINS_DIR="${SCRIPT_DIR}/plugins"'* ]]

  run grep -nF 'source "${REPO_ROOT}/scripts/plugins/argocd.sh"' bin/cluster-up
  [ "$status" -eq 0 ]
  [[ "$output" == *"scripts/plugins/argocd.sh"* ]]

  run grep -nF 'source "${REPO_ROOT}/scripts/plugins/keycloak.sh"' bin/cluster-up
  [ "$status" -eq 0 ]
  [[ "$output" == *"scripts/plugins/keycloak.sh"* ]]

  run grep -nF 'shopping_cart_prepare_infra_bootstrap' bin/cluster-up
  [ "$status" -eq 0 ]
  [[ "$output" == *"shopping_cart_prepare_infra_bootstrap"* ]]

  run grep -nF 'shopping_cart_prepare_cluster_secrets_and_seed' bin/cluster-up
  [ "$status" -eq 0 ]

  run grep -nF 'register_app_cluster' bin/cluster-up
  [ "$status" -eq 0 ]
  [[ "$output" == *"register_app_cluster"* ]]

  run grep -nF 'deploy_shopping_cart_data' bin/cluster-up
  [ "$status" -eq 0 ]
  [[ "$output" == *"deploy_shopping_cart_data"* ]]

  run grep -nF 'shopping_cart_reconcile_product_catalog' bin/cluster-up
  [ "$status" -eq 0 ]
  [[ "$output" == *"shopping_cart_reconcile_product_catalog"* ]]

  run grep -nF '_argocd_write_port_forward_wrapper "${_argocd_pf_wrapper}" "${_argocd_pf_log}"' bin/cluster-up
  [ "$status" -eq 0 ]
  [[ "$output" == *"_argocd_write_port_forward_wrapper"* ]]

  run grep -nF '_argocd_write_browser_https_wrapper "${_argocd_browser_wrapper}" "${_argocd_browser_log}"' bin/cluster-up
  [ "$status" -eq 0 ]
  [[ "$output" == *"_argocd_write_browser_https_wrapper"* ]]

  run grep -nF '_argocd_issue_browser_tls_material "${_argocd_browser_tls_dir}"' bin/cluster-up
  [ "$status" -eq 0 ]
  [[ "$output" == *"_argocd_issue_browser_tls_material"* ]]

  run grep -nF 'security add-trusted-cert -d -r trustRoot' bin/cluster-up
  [ "$status" -eq 0 ]
  [[ "$output" == *"security add-trusted-cert"* ]]

  run grep -nF '_argocd_browser_https_is_ready "https://${ARGOCD_BROWSER_HOST:-argocd.shopping-cart.local}:${ARGOCD_BROWSER_PORT:-443}/healthz"' bin/cluster-up
  [ "$status" -eq 0 ]
  [[ "$output" == *"_argocd_browser_https_is_ready"* ]]

  run grep -nF '_argocd_write_port_forward_wrapper "${_keycloak_browser_wrapper}" "${_keycloak_browser_log}"' bin/cluster-up
  [ "$status" -eq 0 ]
  [[ "$output" == *"_argocd_write_port_forward_wrapper"* ]]

  run grep -nF 'Step 10e/14 — Installing Istio ingress HTTP listener' bin/cluster-up
  [ "$status" -eq 0 ]
  [[ "$output" == *"Istio ingress HTTP listener"* ]]

  run grep -nF 'Step 10f/14 — Wiring ArgoCD SSO' bin/cluster-up
  [ "$status" -eq 0 ]
  [[ "$output" == *"Wiring ArgoCD SSO"* ]]



  run grep -nF 'realm import is required for SSO and cannot be skipped' bin/cluster-up
  [ "$status" -eq 0 ]
  [[ "$output" == *"realm import is required for SSO and cannot be skipped"* ]]

  run grep -nF 'kubectl --context k3d-k3d-cluster -n cicd get app shopping-cart-identity -o wide || true' bin/cluster-up
  [ "$status" -eq 0 ]
  [[ "$output" == *"shopping-cart-identity"* ]]

  run grep -nF '_import_status=$(curl -sS -o /dev/null -w "%{http_code}"' bin/cluster-up
  [ "$status" -eq 0 ]
  [[ "$output" == *'_import_status=$(curl -sS -o /dev/null -w "%{http_code}"'* ]]
}

@test "acg-up preserves existing Vault identity secrets on rebuild" {
  run grep -nF '_vault_kv_exists "keycloak/admin"' scripts/plugins/shopping_cart.sh
  [ "$status" -eq 0 ]
  [[ "$output" == *'_vault_kv_exists "keycloak/admin"'* ]]

  run grep -nF '_vault_kv_exists "keycloak/clients"' scripts/plugins/shopping_cart.sh
  [ "$status" -eq 0 ]
  [[ "$output" == *'_vault_kv_exists "keycloak/clients"'* ]]

  run grep -nF '_vault_kv_exists "ldap/admin"' scripts/plugins/shopping_cart.sh
  [ "$status" -eq 0 ]
  [[ "$output" == *'_vault_kv_exists "ldap/admin"'* ]]
}
