#!/usr/bin/env bats

APPSET="${BATS_TEST_DIRNAME}/../../etc/argocd/applicationsets/vectordb.yaml"
MANIFEST_DIR="${BATS_TEST_DIRNAME}/../../etc/argocd/vectordb"

@test "vectordb ApplicationSet is hub-scoped without an app-cluster selector" {
  run rg -n 'k3d-manager/role:[[:space:]]*app-cluster|role:[[:space:]]*app-cluster' "${APPSET}"
  [ "${status}" -eq 1 ]
  run rg -n 'name:[[:space:]]*hub|namespace:[[:space:]]*vectordb' "${APPSET}"
  [ "${status}" -eq 0 ]
}

@test "vectordb uses the pinned pgvector pg17 image and not latest" {
  run rg -n 'image:[[:space:]]*pgvector/pgvector:pg17([[:space:]]*)$' "${MANIFEST_DIR}"
  [ "${status}" -eq 0 ]
  run rg -n 'image:[^#]*:latest([[:space:]]*)$' "${MANIFEST_DIR}"
  [ "${status}" -eq 1 ]
}

@test "vectordb defines no Role, RoleBinding, or ClusterRole" {
  run rg -n '^[[:space:]]*kind:[[:space:]]*(Role|RoleBinding|ClusterRole)[[:space:]]*$' "${MANIFEST_DIR}"
  [ "${status}" -eq 1 ]
}

@test "vectordb destination and manifests use namespace vectordb, never default" {
  run rg -n 'namespace:[[:space:]]*vectordb' "${APPSET}" "${MANIFEST_DIR}"
  [ "${status}" -eq 0 ]
  run rg -n 'namespace:[[:space:]]*default' "${APPSET}" "${MANIFEST_DIR}"
  [ "${status}" -eq 1 ]
}

@test "vectordb credentials use secretKeyRef and never plaintext trust auth" {
  run awk '
    /name:[[:space:]]*POSTGRES_(USER|PASSWORD)/ { in_credential=1; has_ref=0; has_value=0; next }
    in_credential && /^[[:space:]]*-[[:space:]]*name:/ {
      if (has_ref == 0 || has_value == 1) exit 1
      in_credential=0
    }
    in_credential && /secretKeyRef:/ { has_ref=1 }
    in_credential && /^[[:space:]]*value:/ { has_value=1 }
    END { if (in_credential && (has_ref == 0 || has_value == 1)) exit 1 }
  ' "${MANIFEST_DIR}/statefulset.yaml"
  [ "${status}" -eq 0 ]
  run rg -n 'POSTGRES_HOST_AUTH_METHOD:[[:space:]]*trust' "${MANIFEST_DIR}"
  [ "${status}" -eq 1 ]
}

@test "vectordb ExternalSecret uses vault-backend and vectordb/postgres" {
  run rg -n -A2 'secretStoreRef:' "${MANIFEST_DIR}/externalsecret.yaml"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"name: vault-backend"* ]]
  [[ "${output}" == *"kind: ClusterSecretStore"* ]]
  run rg -n 'key:[[:space:]]*vectordb/postgres' "${MANIFEST_DIR}/externalsecret.yaml"
  [ "${status}" -eq 0 ]
}

@test "vectordb destination is permitted by the platform AppProject" {
  run rg -n -A1 'namespace: vectordb' "${BATS_TEST_DIRNAME}/../../etc/argocd/projects/platform.yaml.tmpl"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"server: https://kubernetes.default.svc"* ]]
}

@test "vectordb Application template enables server-side diff" {
  run awk '
    /^  template:/ { in_template = 1; next }
    in_template && /^    metadata:/ { in_metadata = 1; next }
    in_metadata && /^    spec:/ { exit }
    in_metadata { print }
  ' "${BATS_TEST_DIRNAME}/../../etc/argocd/applicationsets/vectordb.yaml"
  [ "$status" -eq 0 ]
  [[ "$output" == *"argocd.argoproj.io/compare-options"* ]]
  [[ "$output" == *"ServerSideDiff=true"* ]]
}

@test "vectordb ApplicationSet retains server-side apply and masks no differences" {
  run grep -F 'ServerSideApply=true' "${BATS_TEST_DIRNAME}/../../etc/argocd/applicationsets/vectordb.yaml"
  [ "$status" -eq 0 ]

  run grep -c 'ignoreDifferences' "${BATS_TEST_DIRNAME}/../../etc/argocd/applicationsets/vectordb.yaml"
  [ "$output" = "0" ]
}

@test "the ESO Vault policy grants the prefix the vectordb ExternalSecret reads" {
  local _vars="${BATS_TEST_DIRNAME}/../../etc/ldap/vars.sh"
  local _es="${BATS_TEST_DIRNAME}/../../etc/argocd/vectordb/externalsecret.yaml"

  run awk -F'"' '/^export LDAP_VAULT_POLICY_PREFIX=/ { print $2 }' "${_vars}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"vectordb"* ]]

  run awk '/remoteRef:/,0' "${_es}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"key: vectordb/postgres"* ]]
}

@test "vectordb Vault seed function is defined" {
  run rg -n '^function _argocd_seed_vectordb_postgres\(\)' "${BATS_TEST_DIRNAME}/../../plugins/argocd.sh"
  [ "$status" -eq 0 ]
}

@test "bootstrap seeds vectordb before deploying the AppProject" {
  local _argocd="${BATS_TEST_DIRNAME}/../../plugins/argocd.sh"
  local _seed_line _project_line

  _seed_line=$(rg -nF '_argocd_seed_vectordb_postgres || _warn' "${_argocd}" | cut -d: -f1)
  _project_line=$(rg -n '^[[:space:]]*_argocd_deploy_appproject$' "${_argocd}" | tail -1 | cut -d: -f1)
  [ -n "${_seed_line}" ]
  [ -n "${_project_line}" ]
  [ "${_seed_line}" -lt "${_project_line}" ]
}

@test "vectordb Vault seed checks for an existing secret before putting" {
  local _argocd="${BATS_TEST_DIRNAME}/../../plugins/argocd.sh"
  local _body _get_line _put_line

  _body=$(awk '/^function _argocd_seed_vectordb_postgres\(\)/ { in_function=1 } in_function { print } in_function && /^}/ { exit }' "${_argocd}")
  _get_line=$(printf '%s\n' "${_body}" | rg -n 'vault kv get -mount=secret "\$secret_path"' | cut -d: -f1)
  _put_line=$(printf '%s\n' "${_body}" | rg -n 'vault kv put -mount=secret vectordb/postgres' | cut -d: -f1)
  [ -n "${_get_line}" ]
  [ -n "${_put_line}" ]
  [ "${_get_line}" -lt "${_put_line}" ]
}

@test "vectordb Vault seed sends generated credentials on stdin, not argv" {
  local _argocd="${BATS_TEST_DIRNAME}/../../plugins/argocd.sh"
  local _body _argv_count

  _body=$(awk '/^function _argocd_seed_vectordb_postgres\(\)/ { in_function=1 } in_function { print } in_function && /^}/ { exit }' "${_argocd}")
  run rg -nF "vault kv put -mount=secret vectordb/postgres -'" <<< "${_body}"
  [ "$status" -eq 0 ]
  _argv_count=$(printf '%s\n' "${_body}" | rg -c 'vault kv put[^\n]*(password=|password[^[:space:]]*=)' || true)
  _argv_count=${_argv_count:-0}
  [ "${_argv_count}" = "0" ]
}

@test "vectordb Vault seed generates the value from urandom inside remote sh" {
  local _argocd="${BATS_TEST_DIRNAME}/../../plugins/argocd.sh"
  local _body

  _body=$(awk '/^function _argocd_seed_vectordb_postgres\(\)/ { in_function=1 } in_function { print } in_function && /^}/ { exit }' "${_argocd}")
  run rg -n "sh -c 'P=.*tr -dc.*< /dev/urandom" <<< "${_body}"
  [ "$status" -eq 0 ]
}

@test "vectordb Vault seed pins the secret KV mount on get and put" {
  local _argocd="${BATS_TEST_DIRNAME}/../../plugins/argocd.sh"
  local _get_count _put_count

  _get_count=$(awk '/^function _argocd_seed_vectordb_postgres\(\)/ { in_function=1 } in_function && /vault kv get -mount=secret/ { count++ } in_function && /^function / && !/^function _argocd_seed_vectordb_postgres/ { exit } END { print count + 0 }' "${_argocd}")
  _put_count=$(awk '/^function _argocd_seed_vectordb_postgres\(\)/ { in_function=1 } in_function && /vault kv put -mount=secret/ { count++ } in_function && /^function / && !/^function _argocd_seed_vectordb_postgres/ { exit } END { print count + 0 }' "${_argocd}")
  [ "${_get_count}" = "1" ]
  [ "${_put_count}" = "1" ]
}
