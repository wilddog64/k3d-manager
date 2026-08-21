#!/usr/bin/env bats

@test "acg-up sources overrides and exits at the dry-run Step 4 seam" {
  run grep -nF 'source "${REPO_ROOT}/scripts/lib/system_overrides.sh"' bin/cluster-up
  [ "$status" -eq 0 ]
  run grep -nF 'DRY_RUN: provisioning plan complete' bin/cluster-up
  [ "$status" -eq 0 ]
  run grep -nF 'DRY_RUN: no changes were made.' bin/cluster-up
  [ "$status" -eq 0 ]
}

@test "acg-up repairs the Hub host alias before ArgoCD registration" {
  run grep -nF '_acg_repair_hub_host_alias' bin/cluster-up
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | wc -l | tr -d ' ')" -ge 2 ]
  run bash -c "awk '/_acg_repair_hub_host_alias/{print NR; found=1} found && /register_app_cluster/{print NR; exit}' bin/cluster-up"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | sed -n '1p')" -lt "$(printf '%s\n' "$output" | sed -n '2p')" ]
}

@test "acg-up does not capture the dry-run wrapper as its own base" {
  run grep -nF 'unset -f __k3dm_base_run_command' bin/cluster-up
  [ "$status" -ne 0 ]
  run grep -cF 'source "${REPO_ROOT}/scripts/lib/system_overrides.sh"' bin/cluster-up
  [ "$status" -eq 0 ]
  [ "$output" -eq 1 ]
}

@test "acg-up dry-run previews core and never crosses the Step 4 seam" {
  local stub_bin="${BATS_TEST_TMPDIR}/bin"
  local stub_log="${BATS_TEST_TMPDIR}/stub.log"
  export HOME="${BATS_TEST_TMPDIR}/home"
  mkdir -p "${stub_bin}" "${HOME}/.ssh"
  : > "${stub_log}"

  cat > "${stub_bin}/k3d" <<'STUB'
#!/usr/bin/env bash
printf 'k3d %s\n' "$*" >> "${STUB_LOG}"
if [[ "$*" == "cluster list" ]]; then
  exit 0
fi
printf 'MUTATION: k3d %s\n' "$*" >> "${STUB_LOG}"
exit 0
STUB
  cat > "${stub_bin}/kubectl" <<'STUB'
#!/usr/bin/env bash
printf 'kubectl %s\n' "$*" >> "${STUB_LOG}"
if [[ "$*" == *" apply "* || "$*" == apply\ * || "$*" == *"patch"* || "$*" == *"delete"* ]]; then
  printf 'MUTATION: kubectl %s\n' "$*" >> "${STUB_LOG}"
fi
exit 0
STUB
  cat > "${stub_bin}/launchctl" <<'STUB'
#!/usr/bin/env bash
printf 'MUTATION: launchctl %s\n' "$*" >> "${STUB_LOG}"
exit 0
STUB
  cat > "${stub_bin}/deploy_cluster" <<'STUB'
#!/usr/bin/env bash
printf 'MUTATION: deploy_cluster %s\n' "$*" >> "${STUB_LOG}"
exit 0
STUB
  cat > "${stub_bin}/deploy_vault" <<'STUB'
#!/usr/bin/env bash
printf 'MUTATION: deploy_vault %s\n' "$*" >> "${STUB_LOG}"
exit 0
STUB
  chmod +x "${stub_bin}"/*

  export HOME STUB_LOG="${stub_log}"
  export PATH="${stub_bin}:$PATH"
  run env DRY_RUN=1 CLUSTER_PROVIDER=k3s-aws bin/cluster-up

  [ "$status" -eq 0 ]
  [[ "$output" == *"DRY_RUN: would provision k3s-aws cluster"* ]]
  [[ "$output" == *"DRY_RUN: would start autossh tunnel"* ]]
  [[ "$output" == *"DRY_RUN: would create local Hub cluster"* ]]
  [[ "$output" == *"DRY_RUN: provisioning plan complete"* ]]
  [[ "$output" == *"DRY_RUN: no changes were made."* ]]
  ! grep -q 'MUTATION:' "${stub_log}"
}

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

@test "acg-up verifies every LDAP password before checkpointing the seed" {
  run grep -nF 'ldapwhoami -x -H ldap://localhost:389' bin/cluster-up
  [ "$status" -eq 0 ]

  run grep -nF 'LDAP password seed failed verification; checkpoint not written' bin/cluster-up
  [ "$status" -eq 0 ]

  run bash -c '
    seed_block=$(sed -n "/Step 10d.5\/14/,/Step 10d.6\/14/p" bin/cluster-up)
    test "$(printf "%s" "$seed_block" | grep -c "_cp_write \\\"step-10d5-ldap-passwords\\\"")" -eq 1
    printf "%s" "$seed_block" | grep -q "LDAP password seed failed verification; checkpoint not written"
  '
  [ "$status" -eq 0 ]
}

@test "acg-up keeps LDAP user passwords out of command arguments" {
  run grep -nF 'ldappasswd -x -H ldap://localhost:389' bin/cluster-up
  [ "$status" -eq 0 ]

  run grep -nF -- "-S \"uid=\$1,ou=users,dc=shopping-cart,dc=local\"" bin/cluster-up
  [ "$status" -eq 0 ]

  run grep -nF -- '-y "${_ldap_password_file}"' bin/cluster-up
  [ "$status" -eq 0 ]

  run grep -nF -- '-s "${_ldap_user_pass}"' bin/cluster-up
  [ "$status" -ne 0 ]

  run grep -nF -- '-w "${_ldap_user_pass}"' bin/cluster-up
  [ "$status" -ne 0 ]
}
