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
