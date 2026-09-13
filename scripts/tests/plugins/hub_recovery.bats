#!/usr/bin/env bats

setup() {
  source "${BATS_TEST_DIRNAME}/../test_helpers.bash"
  init_test_env
  source "${BATS_TEST_DIRNAME}/../../plugins/hub_recovery.sh"
  RECOVERY_ROOT="${BATS_TEST_TMPDIR}/recovery"
  mkdir -p "$RECOVERY_ROOT/server-db"
  : > "$RECOVERY_ROOT/server-db/state.db"
  : > "$RECOVERY_ROOT/server-token"
  cat > "$RECOVERY_ROOT/pv-pvc.yaml" <<'YAML'
kind: PersistentVolumeClaim
metadata:
  name: data-vault-0
YAML
  local record node namespace claim storage
  while IFS='|' read -r node namespace claim storage; do
    mkdir -p "$RECOVERY_ROOT/$storage/pvc-00000000-0000-0000-0000-000000000000_${namespace}_${claim}"
    printf '%s\n' "  name: $claim" >> "$RECOVERY_ROOT/pv-pvc.yaml"
  done < <(_hub_recovery_records)
  TARGET_ROOT="${BATS_TEST_TMPDIR}/targets"
  export HUB_RECOVERY_LOCAL_PATH_ROOT="$TARGET_ROOT"
  TARGETS_FILE="${BATS_TEST_TMPDIR}/targets.tsv"
  PV_JSON='{"items":['
  local separator=""
  while IFS='|' read -r node namespace claim storage; do
    PV_JSON+="${separator}{\"spec\":{\"claimRef\":{\"namespace\":\"${namespace}\",\"name\":\"${claim}\"},\"local\":{\"path\":\"${TARGET_ROOT}/pvc-00000000-0000-0000-0000-000000000001_${namespace}_${claim}\"},\"nodeAffinity\":{\"required\":{\"nodeSelectorTerms\":[{\"matchExpressions\":[{\"key\":\"kubernetes.io/hostname\",\"values\":[\"k3d-k3d-cluster-${node}\"]}]}]}}}}"
    separator=','
  done < <(_hub_recovery_records)
  PV_JSON+=']}'
  _kubectl() { printf '%s\n' "$PV_JSON"; }
  local uuid
  while IFS='|' read -r node namespace claim storage; do
    uuid="00000000-0000-0000-0000-000000000001"
    mkdir -p "$TARGET_ROOT/pvc-${uuid}_${namespace}_${claim}"
    printf '%s|%s|%s|k3d-k3d-cluster-%s|%s/pvc-%s_%s_%s\n' "$node" "$namespace" "$claim" "$node" "$TARGET_ROOT" "$uuid" "$namespace" "$claim" >> "$TARGETS_FILE"
  done < <(_hub_recovery_records)
}

@test "hub_recovery_validate: accepts the complete seven-claim source map" {
  run hub_recovery_validate "$RECOVERY_ROOT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"seven logical claims"* ]]
}

@test "hub_recovery_plan: emits the dependency map by logical claim" {
  run hub_recovery_plan "$RECOVERY_ROOT"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c '^RESTORE ' )" -eq 7 ]
  [[ "$output" == *"node=server-0 claim=secrets/data-vault-0"* ]]
  [[ "$output" == *"node=agent-1 claim=identity/postgres-keycloak-pvc"* ]]
}

@test "hub_recovery_validate: rejects a missing captured claim" {
  rm -rf "$RECOVERY_ROOT/node-agent-2-storage"
  run hub_recovery_validate "$RECOVERY_ROOT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"trivy-system/data-trivy-server-0"* ]]
}

@test "hub_recovery_validate: rejects a duplicate captured claim" {
  mkdir -p "$RECOVERY_ROOT/node-agent-2-storage/pvc-11111111-1111-1111-1111-111111111111_trivy-system_data-trivy-server-0"
  run hub_recovery_validate "$RECOVERY_ROOT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Expected exactly one source tree"* ]]
}

@test "hub_recovery_validate: rejects an unexpected PVC tree" {
  mkdir -p "$RECOVERY_ROOT/node-agent-0-storage/pvc-22222222-2222-2222-2222-222222222222_extra_unknown"
  run hub_recovery_validate "$RECOVERY_ROOT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"expected 7"* ]]
}

@test "hub_recovery_validate: ignores files below a mapped PVC root" {
  mkdir -p "$RECOVERY_ROOT/node-agent-0-storage/pvc-00000000-0000-0000-0000-000000000000_identity_ldap-data-pvc/database"
  run hub_recovery_validate "$RECOVERY_ROOT"
  [ "$status" -eq 0 ]
}

@test "hub_recovery_restore: plans all mapped claims by default" {
  run hub_recovery_restore "$RECOVERY_ROOT" "$TARGETS_FILE"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c '^RESTORE ' )" -eq 7 ]
  [[ "$output" == *"Dry-run only"* ]]
}

@test "hub_recovery_restore: rejects a target with the wrong logical claim" {
  sed -i.bak 's/data-vault-0$/other-claim/' "$TARGETS_FILE"
  run hub_recovery_restore "$RECOVERY_ROOT" "$TARGETS_FILE"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Invalid or absent target for secrets/data-vault-0"* ]]
}

@test "hub_recovery_targets: renders exactly one current PV target per claim" {
  run hub_recovery_targets
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c '^agent\|^server' )" -eq 7 ]
  [[ "$output" == *"server-0|secrets|data-vault-0|k3d-k3d-cluster-server-0|${TARGET_ROOT}/pvc-"* ]]
}

@test "hub_recovery_targets: rejects a PV assigned to the wrong node" {
  PV_JSON="${PV_JSON/k3d-k3d-cluster-agent-1/k3d-k3d-cluster-agent-2}"
  run hub_recovery_targets
  [ "$status" -ne 0 ]
  [[ "$output" == *"PV target node mismatch"* ]]
}

@test "_hub_recovery_render_cloudflared_config: k3d overrides only the frontend origin" {
  local config="${BATS_TEST_DIRNAME}/../../etc/cloudflared/config.yml"
  local table="${BATS_TEST_DIRNAME}/../../etc/cloudflared/origins.tsv"
  run _hub_recovery_render_cloudflared_config k3d "$config" "$table"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | wc -l | tr -d ' ')" -eq "$(wc -l < "$config" | tr -d ' ')" ]
  [[ "$output" == *"service: http://127.0.0.1:8000"* ]]
  [[ "$output" != *"frontend.3ai-talk.org"$'\n'"    service: http://127.0.0.2:80"* ]]
}

@test "_hub_recovery_render_cloudflared_config: hostinger and unknown providers preserve config" {
  local config="${BATS_TEST_DIRNAME}/../../etc/cloudflared/config.yml"
  local table="${BATS_TEST_DIRNAME}/../../etc/cloudflared/origins.tsv"
  local expected
  expected=$(<"$config")
  run _hub_recovery_render_cloudflared_config k3s-hostinger "$config" "$table"
  [ "$status" -eq 0 ]
  [ "$output" = "$expected" ]
  run _hub_recovery_render_cloudflared_config unknown "$config" "$table"
  [ "$status" -eq 0 ]
  [ "$output" = "$expected" ]
}

@test "hub_recovery_reconcile: dry run prints steps and invokes no operations" {
  local calls="${BATS_TEST_TMPDIR}/reconcile-calls"
  : > "$calls"
  _kubectl() { echo kubectl >> "$calls"; }
  security() { echo security >> "$calls"; }
  register_app_cluster() { echo register >> "$calls"; }
  export -f _kubectl security register_app_cluster
  run hub_recovery_reconcile
  [ "$status" -eq 0 ]
  for step in {1..8}; do
    [[ "$output" == *"${step}."* ]]
  done
  [ ! -s "$calls" ]
}
