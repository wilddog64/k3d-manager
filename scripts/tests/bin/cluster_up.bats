#!/usr/bin/env bats

@test "acg-up identity Application uses server-side apply with server-side diff" {
  local manifest="${BATS_TEST_TMPDIR}/shopping-cart-identity.yaml"
  sed -n "/^kubectl apply --context k3d-k3d-cluster -f - <<'IDEOF'$/,/^IDEOF$/p" bin/cluster-up \
    | sed '1d;$d' > "${manifest}"

  run yq -r '.spec.syncPolicy.syncOptions | join("|")' "${manifest}"
  [ "${status}" -eq 0 ]
  [ "${output}" = "CreateNamespace=true|ServerSideApply=true" ]

  run yq -r '.metadata.annotations."argocd.argoproj.io/compare-options"' "${manifest}"
  [ "${status}" -eq 0 ]
  [ "${output}" = "ServerSideDiff=true" ]

  run yq -r '.. | select(tag == "!!str") | select(test("Replace=true"))' "${manifest}"
  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
}

@test "acg-up preseeds smoke-user Vault before the identity Application apply" {
  local preseed_line apply_line
  preseed_line=$(grep -nF 'keycloak_smoke_vault_preseed' bin/cluster-up | cut -d: -f1)
  apply_line=$(grep -nF 'kubectl apply --context k3d-k3d-cluster -f - <<'"'"'IDEOF'"'"'' bin/cluster-up | cut -d: -f1)
  [ "$preseed_line" -lt "$apply_line" ]
}

@test "acg-up leaves the hub Grafana port-forward wrapper path untouched" {
  run grep -c 'grafana-port-forward.sh" ]]; then' bin/cluster-up
  [ "$status" -eq 0 ]
  [ "$output" -eq 1 ]
}

@test "acg-up forwards Keycloak to the named http Service port" {
  local line
  line=$(grep -F '_argocd_write_port_forward_wrapper "${_kc_pf_wrapper}"' bin/cluster-up)
  [[ "$line" == *'"8880" "http"'* ]]
  [[ "$line" != *'"8880" "8080"'* ]]
}

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

@test "acg-up uses the shared host resolver and fails when it cannot resolve the host" {
  run grep -nF 'source "${REPO_ROOT}/scripts/lib/hub_host_ip.sh"' bin/cluster-up
  [ "$status" -eq 0 ]
  run grep -nF 'source "${REPO_ROOT}/scripts/lib/hub_host_ip.sh"' bin/cluster-refresh
  [ "$status" -eq 0 ]
  run grep -nF 'getent hosts host.docker.internal' bin/cluster-up
  [ "$status" -ne 0 ]
  run grep -nF 'getent hosts host.docker.internal' bin/cluster-refresh
  [ "$status" -ne 0 ]
  run bash -c '
    set -e
    body=$(sed -n "/function _acg_repair_hub_host_alias/,/^}/p" bin/cluster-up)
    grep -q "_host_ip=\$(_hub_docker_host_ip)" <<<"$body"
    grep -q "_err" <<<"$body"
    grep -q "_err \"\[acg-up\] Could not resolve host.docker.internal" <<<"$body"
    if grep -q "_warn \"\[acg-up\] Could not detect host IP" <<<"$body"; then exit 1; fi
  '
  [ "$status" -eq 0 ]
}

@test "acg-up reconciles other app-cluster registrations after registering the hub" {
  run bash -c "awk '/register_app_cluster/{print NR; found=1} found && /argocd_reconcile_app_cluster_registrations/{print NR; exit}' bin/cluster-up"
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
  cat > "${stub_bin}/aws" <<'STUB'
#!/usr/bin/env bash
printf 'arn:aws:iam::000000000000:user/test\n'
STUB
  cat > "${stub_bin}/node" <<'STUB'
#!/usr/bin/env bash
exit 1
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
  run grep -q 'MUTATION:' "${stub_log}"
  [ "$status" -ne 0 ]
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
  local wrapper_line="${output%%:*}"

  run grep -nF 'Step 10e/14 — Installing Istio ingress HTTP listener' bin/cluster-up
  [ "$status" -eq 0 ]
  [[ "$output" == *"Istio ingress HTTP listener"* ]]
  run grep -nF 'Istio ingress HTTP listener already healthy' bin/cluster-up
  [ "$status" -eq 0 ]
  local health_line="${output%%:*}"
  [ "$wrapper_line" -lt "$health_line" ]

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

@test "acg-up restores cosign signing only for a newly created Hub" {
  run grep -nF '_dry_guard "restore cosign signing"' bin/cluster-up
  [ "$status" -eq 0 ]
  local restore_line="${output%%:*}"
  run grep -nF 'elif ! _argocd_bootstrap_is_ready' bin/cluster-up
  [ "$status" -eq 0 ]
  local existing_line="${output%%:*}"
  [ "$restore_line" -lt "$existing_line" ]
  run grep -nF '_dry_guard "deploy ArgoCD"' bin/cluster-up
  [ "$status" -eq 0 ]
  local argocd_line="${output%%:*}"
  [ "$argocd_line" -lt "$restore_line" ]
}

@test "acg-up never references signing_init or signing_rotate_key" {
  run grep -nE 'signing_(init|rotate_key)' bin/cluster-up
  [ "$status" -ne 0 ]
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
  run grep -nF 'ldapwhoami -x -H ldap://localhost:1389' bin/cluster-up
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
  run grep -nF 'ldappasswd -x -H ldap://localhost:1389' bin/cluster-up
  [ "$status" -eq 0 ]

  run grep -nF -- "-S \"uid=\$1,ou=users,dc=home,dc=org\"" bin/cluster-up
  [ "$status" -eq 0 ]

  run grep -nF -- '-y "${_ldap_password_file}"' bin/cluster-up
  [ "$status" -eq 0 ]

  run grep -nF -- '-s "${_ldap_user_pass}"' bin/cluster-up
  [ "$status" -ne 0 ]

  run grep -nF -- '-w "${_ldap_user_pass}"' bin/cluster-up
  [ "$status" -ne 0 ]
}

@test "acg-up selects the LDAP provider by type and keeps its password off argv" {
  local helper="${BATS_TEST_TMPDIR}/ldap-provider-helper.sh"
  local argv_log="${BATS_TEST_TMPDIR}/kubectl-argv.log"
  local stdin_log="${BATS_TEST_TMPDIR}/kubectl-stdin.log"
  sed -n '/function _acg_keycloak_ldap_provider_id/,/^}/p' bin/cluster-up > "${helper}"
  export KUBECTL_ARGV_LOG="${argv_log}" KUBECTL_STDIN_LOG="${stdin_log}"

  run bash -c '
    source "$1"
    kubectl() {
      printf "%s\n" "$*" >> "$KUBECTL_ARGV_LOG"
      cat > "$KUBECTL_STDIN_LOG"
      printf "%s\n" "398e5ed4,full-name-ldap-mapper" "a5a37610,ldap"
    }
    _acg_keycloak_ldap_provider_id keycloak-0 secret-pass
  ' bash "${helper}"
  [ "${status}" -eq 0 ]
  [ "${output}" = "a5a37610" ]
  run grep -qF 'secret-pass' "${argv_log}"
  [ "$status" -ne 0 ]
  [ "$(cat "${stdin_log}")" = "secret-pass" ]
}

@test "acg-up reads the LDAP bind password from openldap-admin" {
  local helper="${BATS_TEST_TMPDIR}/ldap-bind-helper.sh"
  local argv_log="${BATS_TEST_TMPDIR}/kubectl-argv.log"
  sed -n '/function _acg_ldap_bind_pass/,/^}/p' bin/cluster-up > "${helper}"
  export KUBECTL_ARGV_LOG="${argv_log}"

  run bash -c '
    source "$1"
    kubectl() {
      printf "%s\n" "$*" >> "$KUBECTL_ARGV_LOG"
      printf "p/w&x+y" | base64
    }
    _acg_ldap_bind_pass
  ' bash "${helper}"
  [ "${status}" -eq 0 ]
  [ "${output}" = "p/w&x+y" ]
  grep -qF "openldap-admin" "${argv_log}"
  grep -qF "LDAP_ADMIN_PASSWORD" "${argv_log}"
}

@test "acg-up uses the LDAP provider helper and removes the substring lookup" {
  run grep -nF "grep -B1 'ldap'" bin/cluster-up
  [ "${status}" -ne 0 ]
  run grep -nF -- "--password '\${_kc_admin_pass}'" bin/cluster-up
  [ "${status}" -ne 0 ]
  run grep -nF 'bindCredential=[\"${_ldap_admin_pass}' bin/cluster-up
  [ "${status}" -ne 0 ]
  run bash -c '
    block=$(sed -n "/Step 10d.7\\/14/,/step-10d7-group-mapper/p" bin/cluster-up)
    grep -q '\''"\$parent" != "\$1"'\'' <<<"$block"
    grep -q "group-ldap-mapper" <<<"$block"
    grep -q '\''delete "components/\$id"'\'' <<<"$block"
  '
  [ "${status}" -eq 0 ]
  run bash -c '
    block=$(sed -n "/Step 10d\\/14/,/kill \"\${_kc_pf_pid}\"/p" bin/cluster-up)
    grep -q _keycloak_smoke_ensure_realm <<<"$block"
    if grep -q '\''{\\"frontendUrl\\"'\'' <<<"$block"; then exit 1; fi
  '
  [ "${status}" -eq 0 ]
}

@test "acg-up restarts the argocd browser listener when only the wrapper changed" {
  run grep -nF 'if [[ -f "${_argocd_browser_plist}" ]] && [[ "${_argocd_browser_wrapper_changed}" -eq 0 ]] && diff -q' bin/cluster-up
  [ "$status" -eq 0 ]

  run grep -cF '_argocd_browser_wrapper_changed=1' bin/cluster-up
  [ "$status" -eq 0 ]
  [ "$output" -eq 1 ]

  run bash -c "awk '/_argocd_browser_wrapper_before=\"\"/{print NR} /_argocd_write_browser_https_wrapper \"/{print NR} /_argocd_browser_wrapper_changed=0/{print NR}' bin/cluster-up"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | sed -n '1p')" -lt "$(printf '%s\n' "$output" | sed -n '2p')" ]
  [ "$(printf '%s\n' "$output" | sed -n '2p')" -lt "$(printf '%s\n' "$output" | sed -n '3p')" ]
}

@test "acg-up registers the app cluster with a real provider and the shopping-cart label" {
  run grep -nF 'ARGOCD_APP_CLUSTER_PROVIDER="${ARGOCD_APP_CLUSTER_PROVIDER:-${_cluster_provider}}"' bin/cluster-up
  [ "$status" -eq 0 ]

  run grep -nF 'ARGOCD_APP_CLUSTER_SHOPPING_CART="${ARGOCD_APP_CLUSTER_SHOPPING_CART:-true}"' bin/cluster-up
  [ "$status" -eq 0 ]

  run bash -c "awk '/ARGOCD_APP_CLUSTER_SHOPPING_CART=/{print NR; found=1} found && /^  register_app_cluster\$/{print NR; exit}' bin/cluster-up"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | sed -n '1p')" -lt "$(printf '%s\n' "$output" | sed -n '2p')" ]
}

_load_image_pull_helpers() {
  sed -n '/^function _acg_image_pull_blocked()/,/^}$/p' bin/cluster-up > "${BATS_TEST_TMPDIR}/a.sh"
  sed -n '/^function _acg_data_layer_abort_on_image_pull()/,/^}$/p' bin/cluster-up > "${BATS_TEST_TMPDIR}/b.sh"
  source scripts/lib/system.sh
  source "${BATS_TEST_TMPDIR}/a.sh"
  source "${BATS_TEST_TMPDIR}/b.sh"
}

_load_data_layer_explain() {
  sed -n '/^function _acg_data_layer_explain()/,/^}$/p' bin/cluster-up > "${BATS_TEST_TMPDIR}/data-layer-explain.sh"
  source scripts/lib/system.sh
  source "${BATS_TEST_TMPDIR}/data-layer-explain.sh"
}

@test "acg-up data-layer explanation reports sync cause and NotReady node" {
  run bash -c '
    '"$(declare -f _load_data_layer_explain)"'
    _load_data_layer_explain
    kubectl() {
      case "$*" in
        *"get application"*) printf "%s\n" "failed calling webhook validate.externalsecret.external-secrets.io: no endpoints available" ;;
        *"get nodes"*) printf "%s\n" "ip-a Ready  control-plane 1h 1.32.0" "ip-b NotReady  <none> 1h 1.32.0" ;;
      esac
    }
    _acg_data_layer_explain data-layer
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"no endpoints available"* ]]
  [[ "$output" == *"app-cluster node not Ready: ip-b NotReady"* ]]
  [[ "$output" != *"ip-a"* ]]
  run grep -c '_acg_data_layer_explain "${_dl_app_name}"' bin/cluster-up
  [ "$status" -eq 0 ]
  [ "$output" -eq 2 ]
}

@test "acg-up data-layer explanation stays silent when healthy" {
  run bash -c '
    '"$(declare -f _load_data_layer_explain)"'
    _load_data_layer_explain
    kubectl() {
      case "$*" in
        *"get application"*) : ;;
        *"get nodes"*) printf "%s\n" "ip-a Ready  control-plane 1h 1.32.0" ;;
      esac
    }
    _acg_data_layer_explain data-layer
  '
  [ "$status" -eq 0 ]
  [[ "$output" != *"last sync operation"* ]]
  [[ "$output" != *"not Ready"* ]]
}

@test "acg-up data-layer explanation truncates long operation messages" {
  run bash -c '
    '"$(declare -f _load_data_layer_explain)"'
    _load_data_layer_explain
    message=$(printf "x%.0s" {1..1000})
    kubectl() {
      case "$*" in
        *"get application"*) printf "%s\n" "$message" ;;
        *"get nodes"*) : ;;
      esac
    }
    _acg_data_layer_explain data-layer
    x_count=$(printf "%s\n" "$output" | tr -cd x | wc -c)
    [ "$x_count" -le 400 ]
  '
  [ "$status" -eq 0 ]
}

@test "acg-up data-layer explanation survives kubectl failure" {
  run bash -c '
    '"$(declare -f _load_data_layer_explain)"'
    _load_data_layer_explain
    kubectl() { return 1; }
    _acg_data_layer_explain data-layer
  '
  [ "$status" -eq 0 ]
}

@test "acg-up reconnect timeout does not claim the controller connected" {
  run bash -c '
    sed -n "/^_argocd_conn_deadline=/,/^[[:space:]]*_info.*ArgoCD controller connected.*proceeding/p" bin/cluster-up > "${BATS_TEST_TMPDIR}/reconnect.sh"
    printf "fi\n" >> "${BATS_TEST_TMPDIR}/reconnect.sh"
    source scripts/lib/system.sh
    _info() { printf "%s\n" "$*"; }
    _warn() { printf "%s\n" "$*"; }
    argocd() { printf "[]\n"; }
    python3() { printf "Unknown\n"; }
    sleep() { :; }
    date_state="${BATS_TEST_TMPDIR}/date.calls"
    date() {
      if [[ -e "${date_state}" ]]; then
        printf "999\n"
      else
        : > "${date_state}"
        printf "0\n"
      fi
    }
    source "${BATS_TEST_TMPDIR}/reconnect.sh"
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"did not reconnect"* ]]
  [[ "$output" != *"connected to ubuntu-k3s — proceeding"* ]]
}

_pods_json_imagepullbackoff() {
  cat <<'JSON'
{"items":[{"metadata":{"name":"minio-0"},"status":{"containerStatuses":[
 {"name":"minio","state":{"waiting":{"reason":"ImagePullBackOff","message":"Back-off pulling image \"quay.io/minio/minio:X\": 401 UNAUTHORIZED"}}}]}},
 {"metadata":{"name":"redis-cart-0"},"status":{"containerStatuses":[{"name":"redis","state":{"running":{}}}]}}]}
JSON
}

@test "acg-up image-pull probe reports a blocked container with pod, container and reason" {
  run bash -c '
    '"$(declare -f _load_image_pull_helpers _pods_json_imagepullbackoff)"'
    _load_image_pull_helpers
    kubectl() { _pods_json_imagepullbackoff; }
    _acg_image_pull_blocked shopping-cart-data ubuntu-k3s
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"pod/minio-0 minio ImagePullBackOff"* ]]
  [[ "$output" == *"401 UNAUTHORIZED"* ]]
  [[ "$output" != *"redis-cart-0"* ]]
}

@test "acg-up image-pull probe stays quiet when every container is running" {
  run bash -c '
    '"$(declare -f _load_image_pull_helpers)"'
    _load_image_pull_helpers
    kubectl() { echo "{\"items\":[{\"metadata\":{\"name\":\"redis-cart-0\"},\"status\":{\"containerStatuses\":[{\"name\":\"redis\",\"state\":{\"running\":{}}}]}}]}"; }
    _acg_image_pull_blocked shopping-cart-data ubuntu-k3s
  '
  [ "$status" -ne 0 ]
  [ -z "$output" ]
}

@test "acg-up image-pull probe ignores a non-fatal waiting reason" {
  run bash -c '
    '"$(declare -f _load_image_pull_helpers)"'
    _load_image_pull_helpers
    kubectl() { echo "{\"items\":[{\"metadata\":{\"name\":\"minio-0\"},\"status\":{\"containerStatuses\":[{\"name\":\"minio\",\"state\":{\"waiting\":{\"reason\":\"ContainerCreating\"}}}]}}]}"; }
    _acg_image_pull_blocked shopping-cart-data ubuntu-k3s
  '
  [ "$status" -ne 0 ]
}

@test "acg-up data-layer abort waits three polls before giving up" {
  run bash -c '
    '"$(declare -f _load_image_pull_helpers _pods_json_imagepullbackoff)"'
    _load_image_pull_helpers
    kubectl() { _pods_json_imagepullbackoff; }
    for i in 1 2 3; do
      if _acg_data_layer_abort_on_image_pull; then echo "ABORT_AT=$i"; break; fi
    done
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"not settled (1/3)"* ]]
  [[ "$output" == *"not settled (2/3)"* ]]
  [[ "$output" == *"blocked on an image pull, not on a slow sync"* ]]
  [[ "$output" == *"ABORT_AT=3"* ]]
}

@test "acg-up data-layer abort resets its strike count when the pull recovers" {
  run bash -c '
    '"$(declare -f _load_image_pull_helpers _pods_json_imagepullbackoff)"'
    _load_image_pull_helpers
    kubectl() { _pods_json_imagepullbackoff; }
    _acg_data_layer_abort_on_image_pull || true
    _acg_data_layer_abort_on_image_pull || true
    kubectl() { echo "{\"items\":[]}"; }
    _acg_data_layer_abort_on_image_pull || true
    echo "strikes=${_DL_IMAGE_STRIKES}"
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"strikes=0"* ]]
}

@test "acg-up checks for a blocked image pull inside both data-layer sync waits" {
  run grep -c '_acg_data_layer_abort_on_image_pull' bin/cluster-up
  [ "$status" -eq 0 ]
  [ "$output" -eq 3 ]
}

_load_acg_up_cleanup() {
  sed -n '/^function _acg_up_cleanup()/,/^}$/p' bin/cluster-up > "${BATS_TEST_TMPDIR}/c.sh"
  source scripts/lib/system.sh
  source "${BATS_TEST_TMPDIR}/c.sh"
}

@test "acg-up failure cleanup leaves a port-forward owned by another run" {
  run bash -c '
    '"$(declare -f _load_acg_up_cleanup)"'
    export _ACG_STATE_DIR="${BATS_TEST_TMPDIR}/state"
    mkdir -p "${_ACG_STATE_DIR}/run"
    printf "93911\n" > "${_ACG_STATE_DIR}/run/acg-prom-pf.pid"
    kill() { echo "KILL_CALLED $*"; }
    _ACG_UP_OWNED_PIDS=" 12345"
    _load_acg_up_cleanup
    ( exit 1 ); _acg_up_cleanup
    [[ -f "${_ACG_STATE_DIR}/run/acg-prom-pf.pid" ]]
  '
  [ "$status" -eq 0 ]
  [[ "$output" != *"KILL_CALLED"* ]]
}

@test "acg-up failure cleanup kills and removes a port-forward owned by this run" {
  run bash -c '
    '"$(declare -f _load_acg_up_cleanup)"'
    export _ACG_STATE_DIR="${BATS_TEST_TMPDIR}/state"
    mkdir -p "${_ACG_STATE_DIR}/run"
    printf "93911\n" > "${_ACG_STATE_DIR}/run/acg-prom-pf.pid"
    kill() { echo "KILL_CALLED $*"; }
    _ACG_UP_OWNED_PIDS=" 93911"
    _load_acg_up_cleanup
    ( exit 1 ); _acg_up_cleanup
    [[ ! -f "${_ACG_STATE_DIR}/run/acg-prom-pf.pid" ]]
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"KILL_CALLED 93911"* ]]
}

@test "acg-up records Vault and Prometheus port-forward ownership" {
  local vault_line prom_line
  vault_line="$(grep -n '_vault_pf_pid=\$!' bin/cluster-up | cut -d: -f1)"
  prom_line="$(grep -n '_acg_prom_pf_pid=\$!' bin/cluster-up | cut -d: -f1)"
  [ "$(sed -n "$((vault_line + 1))p" bin/cluster-up | grep -c '_ACG_UP_OWNED_PIDS+=')" -eq 1 ]
  [ "$(sed -n "$((prom_line + 1))p" bin/cluster-up | grep -c '_ACG_UP_OWNED_PIDS+=')" -eq 1 ]
}

_load_acg_up_marker_clear() {
  sed -n '/^function _acg_up_clear_stack_marker()/,/^}$/p' bin/cluster-up > "${BATS_TEST_TMPDIR}/c.sh"
  source scripts/lib/system.sh
  source "${BATS_TEST_TMPDIR}/c.sh"
}

@test "acg-up failure cleanup warns for a stack created by this run" {
  run bash -c '
    '"$(declare -f _load_acg_up_cleanup)"'
    export _ACG_STATE_DIR="${BATS_TEST_TMPDIR}/state"
    mkdir -p "${_ACG_STATE_DIR}/run"
    printf "stack_name=k3d-manager-cluster\nregion=us-west-2\n" > "${_ACG_STATE_DIR}/run/cf-stack-created"
    _load_acg_up_cleanup
    ( exit 1 ); _acg_up_cleanup
  '
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"CloudFormation stack 'k3d-manager-cluster' (us-west-2) was created by this run"* ]]
  [[ "${output}" == *"make down"* ]]
}

@test "acg-up failure cleanup does not warn for a reused stack" {
  run bash -c '
    '"$(declare -f _load_acg_up_cleanup)"'
    export _ACG_STATE_DIR="${BATS_TEST_TMPDIR}/state"
    mkdir -p "${_ACG_STATE_DIR}/run"
    _load_acg_up_cleanup
    ( exit 1 ); _acg_up_cleanup
  '
  [ "${status}" -eq 0 ]
  [[ "${output}" != *"CloudFormation stack"* ]]
}

@test "acg-up success clears the CloudFormation ownership marker" {
  run bash -c '
    '"$(declare -f _load_acg_up_marker_clear)"'
    export _ACG_STATE_DIR="${BATS_TEST_TMPDIR}/state"
    mkdir -p "${_ACG_STATE_DIR}/run"
    : > "${_ACG_STATE_DIR}/run/cf-stack-created"
    _load_acg_up_marker_clear
    _acg_up_clear_stack_marker
    if [[ -e "${_ACG_STATE_DIR}/run/cf-stack-created" ]]; then
      exit 1
    fi
  '
  [ "${status}" -eq 0 ]
}

@test "acg-up clears a stale ownership marker at start and after success" {
  local _trap _start _state _done
  _trap="$(grep -n '^trap _acg_up_cleanup EXIT$' bin/cluster-up | cut -d: -f1)"
  _start="$(grep -n '^_acg_up_clear_stack_marker$' bin/cluster-up | head -1 | cut -d: -f1)"
  _state="$(grep -n 'acg-state.json"$' bin/cluster-up | tail -1 | cut -d: -f1)"
  _done="$(grep -n '^_acg_up_clear_stack_marker$' bin/cluster-up | tail -1 | cut -d: -f1)"
  [ -n "${_trap}" ] && [ -n "${_start}" ] && [ -n "${_state}" ]
  [ "${_start}" -eq $((_trap + 1)) ]
  [ "${_done}" -gt "${_state}" ]
}

@test "acg-up failure cleanup tolerates a missing or unreadable marker" {
  run bash -c '
    '"$(declare -f _load_acg_up_cleanup)"'
    export _ACG_STATE_DIR="${BATS_TEST_TMPDIR}/state"
    mkdir -p "${_ACG_STATE_DIR}/run"
    : > "${_ACG_STATE_DIR}/run/cf-stack-created"
    chmod 000 "${_ACG_STATE_DIR}/run/cf-stack-created"
    _load_acg_up_cleanup
    ( exit 1 ); _acg_up_cleanup
  '
  [ "${status}" -eq 0 ]
}

@test "acg-up failure cleanup leaves a pre-existing cloudflare tunnel running" {
  run bash -c '
    '"$(declare -f _load_acg_up_cleanup)"'
    export _ACG_STATE_DIR="${BATS_TEST_TMPDIR}/state"
    mkdir -p "${_ACG_STATE_DIR}/run"
    _load_acg_up_cleanup
    launchctl() { echo "LAUNCHCTL_CALLED $*"; }
    ( exit 1 ); _acg_up_cleanup
  '
  [ "$status" -eq 0 ]
  [[ "$output" != *"LAUNCHCTL_CALLED"* ]]
  [[ "$output" == *"leaving the cloudflare tunnel up"* ]]
}

@test "acg-up failure cleanup removes only a tunnel it created itself" {
  run bash -c '
    '"$(declare -f _load_acg_up_cleanup)"'
    export _ACG_STATE_DIR="${BATS_TEST_TMPDIR}/state"
    mkdir -p "${_ACG_STATE_DIR}/run"
    _load_acg_up_cleanup
    launchctl() { echo "LAUNCHCTL_CALLED $1"; }
    _ACG_TUNNEL_PLIST_CREATED=1
    ( exit 1 ); _acg_up_cleanup
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"LAUNCHCTL_CALLED bootout"* ]]
  [[ "$output" == *"removing the cloudflare tunnel this run created"* ]]
}

@test "acg-up marks the tunnel plist as created only when none existed" {
  local lib=scripts/lib/cloudflare_tunnel.sh
  run grep -c '_ACG_TUNNEL_PLIST_CREATED=1' "$lib"
  [ "$status" -eq 0 ]
  [ "$output" -eq 1 ]
  run grep -c '\[\[ -f "${_named_tunnel_plist}" \]\] || _ACG_TUNNEL_PLIST_CREATED=1' "$lib"
  [ "$output" -eq 1 ]
  marker_line=$(awk '/_ACG_TUNNEL_PLIST_CREATED=1/{print NR; exit}' "$lib")
  install_line=$(awk '/install -m 644 "\$\{_named_tunnel_plist_tmp\}"/{print NR; exit}' "$lib")
  [ -n "$marker_line" ]
  [ -n "$install_line" ]
  [ "$marker_line" -lt "$install_line" ]
  run grep -c 'source "${REPO_ROOT}/scripts/lib/cloudflare_tunnel.sh"' bin/cluster-up
  [ "$output" -ge 1 ]
}

@test "acg-up failure cleanup never boots out the tunnel unconditionally" {
  run bash -c "sed -n '/^function _acg_up_cleanup()/,/^}\$/p' bin/cluster-up | grep -c 'launchctl bootout'"
  [ "$output" -eq 1 ]
  run bash -c "sed -n '/^function _acg_up_cleanup()/,/^}\$/p' bin/cluster-up | grep -n '_ACG_TUNNEL_PLIST_CREATED'"
  [ "$status" -eq 0 ]
}

@test "acg-up puts ~/.local/bin on PATH before anything reads it" {
  run bash -c "awk '/^set -euo pipefail/{print NR; found=1} found && /HOME\}\/\.local\/bin/{print NR; exit}' bin/cluster-up"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | wc -l | tr -d ' ')" -eq 2 ]
  run bash -c "awk '/HOME\}\/\.local\/bin:\\\$\{PATH\}/{print NR; found=1} found && /_command_exist k3d/{print NR; exit}' bin/cluster-up"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | sed -n '1p')" -lt "$(printf '%s\n' "$output" | sed -n '2p')" ]
}

@test "acg-up guards the PATH prepend so it cannot duplicate an existing entry" {
  local block="${BATS_TEST_TMPDIR}/path-block.sh"
  awk '/^# launchd starts this script/{found=1} found{print} found && /^fi$/{exit}' \
    bin/cluster-up > "${block}"
  run grep -c 'local/bin' "${block}"
  [ "$status" -eq 0 ]
  [ "$output" -ge 2 ]

  run bash -c "PATH=\"\${HOME}/.local/bin:/usr/bin:/bin\" bash -c 'source \"${block}\"; printf %s \"\${PATH}\"'"
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | tr ':' '\n' | grep -c 'local/bin')" -eq 1 ]

  run bash -c "PATH=\"/usr/bin:/bin\" bash -c 'source \"${block}\"; printf %s \"\${PATH}\"'"
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | tr ':' '\n' | grep -c 'local/bin')" -eq 1 ]
}

@test "acg-up Keycloak reverse tunnel helper accepts a non-zero HTTP status" {
  local stub_bin="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "${stub_bin}"
  cat > "${stub_bin}/ssh" <<'STUB'
#!/usr/bin/env bash
printf '%s' "${STUB_CODE}"
exit "${STUB_RC:-0}"
STUB
  chmod +x "${stub_bin}/ssh"
  export PATH="${stub_bin}:${PATH}" STUB_CODE=404 STUB_RC=0

  run bash -c 'source <(sed -n "/function _acg_keycloak_reverse_tunnel_up/,/^}/p" bin/cluster-up); _acg_keycloak_reverse_tunnel_up'
  [ "${status}" -eq 0 ]
}

@test "acg-up Keycloak reverse tunnel helper rejects curl status 000" {
  local stub_bin="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "${stub_bin}"
  cat > "${stub_bin}/ssh" <<'STUB'
#!/usr/bin/env bash
printf '%s' "${STUB_CODE}"
exit "${STUB_RC:-0}"
STUB
  chmod +x "${stub_bin}/ssh"
  export PATH="${stub_bin}:${PATH}" STUB_CODE=000 STUB_RC=7

  run bash -c 'source <(sed -n "/function _acg_keycloak_reverse_tunnel_up/,/^}/p" bin/cluster-up); _acg_keycloak_reverse_tunnel_up'
  [ "${status}" -ne 0 ]
}

@test "acg-up Keycloak reverse tunnel helper rejects an empty curl status" {
  local stub_bin="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "${stub_bin}"
  cat > "${stub_bin}/ssh" <<'STUB'
#!/usr/bin/env bash
printf '%s' "${STUB_CODE}"
exit "${STUB_RC:-0}"
STUB
  chmod +x "${stub_bin}/ssh"
  export PATH="${stub_bin}:${PATH}" STUB_CODE= STUB_RC=255

  run bash -c 'source <(sed -n "/function _acg_keycloak_reverse_tunnel_up/,/^}/p" bin/cluster-up); _acg_keycloak_reverse_tunnel_up'
  [ "${status}" -ne 0 ]
}

@test "acg-up Step 10g.5 reuses or replaces the Keycloak reverse tunnel" {
  local block before_ssh
  block="$(sed -n "/Step 10g.5\\/14/,/Step 10e\\/14/p" bin/cluster-up)"
  [[ "${block}" == *"_acg_keycloak_reverse_tunnel_up"* ]]
  [[ "${block}" == *"already active on ubuntu:18080"* ]]
  [[ "${block}" == *"pkill -f"* ]]
  before_ssh="${block%%ssh -f -N*}"
  [[ "${before_ssh}" == *"_acg_keycloak_reverse_tunnel_up"* ]]
}

@test "acg-up root-owned state preflight is before launchd sudo" {
  local root_line sudo_line state_line
  root_line="$(grep -n -m1 -- '-user root' bin/cluster-up | cut -d: -f1)"
  sudo_line="$(grep -n -m1 -- '--interactive-sudo' bin/cluster-up | cut -d: -f1)"
  state_line="$(grep -n -m1 'create local state directories' bin/cluster-up | cut -d: -f1)"
  [ "${root_line}" -lt "${sudo_line}" ]
  [ "${root_line}" -gt "${state_line}" ]
}

@test "acg-up root-owned state preflight passes with no root-owned folders" {
  local block="${BATS_TEST_TMPDIR}/state-preflight.sh"
  sed -n '/^_acg_state_root=/,/^fi$/p' bin/cluster-up > "${block}"
  run env _ACG_STATE_BASE="${BATS_TEST_TMPDIR}/state" bash "${block}"
  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
}

@test "acg-up root-owned state preflight stops with repair guidance" {
  local block="${BATS_TEST_TMPDIR}/state-preflight.sh"
  local stub_bin="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "${stub_bin}"
  cat > "${stub_bin}/find" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "${BATS_TEST_TMPDIR}/state/logs"
STUB
  chmod +x "${stub_bin}/find"
  sed -n '/^_acg_state_root=/,/^fi$/p' bin/cluster-up > "${block}"
  run env _ACG_STATE_BASE="${BATS_TEST_TMPDIR}/state" PATH="${stub_bin}:${PATH}" bash "${block}"
  [ "${status}" -eq 2 ]
  [[ "${output}" == *"root-owned state folders found"* ]]
  [[ "${output}" == *"sudo chown -R"* ]]
}
