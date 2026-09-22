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
  docker_stub() { echo docker >> "$calls"; }
  export HUB_RECOVERY_DOCKER_BIN=docker_stub
  export -f _kubectl security register_app_cluster docker_stub
  run hub_recovery_reconcile
  [ "$status" -eq 0 ]
  for step in {1..10}; do
    [[ "$output" == *"${step}."* ]]
  done
  [[ "$output" == *"k3d serverlb upstreams"* ]]
  [[ "$output" == *"ArgoCD admin Vault mirror"* ]]
  [ ! -s "$calls" ]
}

@test "_hub_recovery_render_serverlb_values: servers on 6443, servers then agents on 80/443" {
  local input expected
  input=$'agent k3d-c-agent-1\nloadbalancer k3d-c-serverlb\nserver k3d-c-server-0\nagent k3d-c-agent-0'
  expected=$(cat <<'YAML'
ports:
  6443.tcp:
  - k3d-c-server-0
  80.tcp:
  - k3d-c-server-0
  - k3d-c-agent-0
  - k3d-c-agent-1
  443.tcp:
  - k3d-c-server-0
  - k3d-c-agent-0
  - k3d-c-agent-1
settings:
  workerConnections: 1024
YAML
)
  run _hub_recovery_render_serverlb_values <<< "$input"
  [ "$status" -eq 0 ]
  [ "$output" = "$expected" ]
}

@test "_hub_recovery_render_serverlb_values: fails with no server container" {
  run _hub_recovery_render_serverlb_values <<< $'agent k3d-c-agent-0\nagent k3d-c-agent-1'
  [ "$status" -ne 0 ]
}

@test "_hub_recovery_serverlb_upstream_pairs: empty inline lists yield no pairs" {
  run _hub_recovery_serverlb_upstream_pairs <<'YAML'
ports:
  6443.tcp: []
  80.tcp: []
  443.tcp: []
YAML
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "_hub_recovery_ensure_serverlb_upstreams: matching upstreams do not restart the LB" {
  SERVERLB_CALLS="${BATS_TEST_TMPDIR}/serverlb-calls"
  : > "$SERVERLB_CALLS"
  docker_stub() {
    case "$1" in
      ps) printf '%s\n' 'agent k3d-c-agent-1' 'server k3d-c-server-0' 'agent k3d-c-agent-0' ;;
      exec) cat <<'YAML'
ports:
  6443.tcp:
  - k3d-c-server-0
  80.tcp:
  - k3d-c-agent-1
  - k3d-c-server-0
  - k3d-c-agent-0
  443.tcp:
  - k3d-c-agent-0
  - k3d-c-agent-1
  - k3d-c-server-0
settings:
  workerConnections: 1024
YAML
        ;;
      cp|restart) printf '%s\n' "$1" >> "$SERVERLB_CALLS" ;;
    esac
  }
  export HUB_RECOVERY_DOCKER_BIN=docker_stub SERVERLB_CALLS
  export -f docker_stub
  run _hub_recovery_ensure_serverlb_upstreams k3d-k3d-cluster c
  [ "$status" -eq 0 ]
  [ ! -s "$SERVERLB_CALLS" ]
}

@test "_hub_recovery_ensure_serverlb_upstreams: empty upstreams rewrite values and restart only the LB" {
  SERVERLB_CALLS="${BATS_TEST_TMPDIR}/serverlb-calls"
  SERVERLB_VALUES="${BATS_TEST_TMPDIR}/serverlb-values.yaml"
  : > "$SERVERLB_CALLS"
  docker_stub() {
    case "$1" in
      ps) printf '%s\n' 'agent k3d-c-agent-1' 'server k3d-c-server-0' 'agent k3d-c-agent-0' ;;
      exec) cat <<'YAML'
ports:
  6443.tcp: []
  80.tcp: []
  443.tcp: []
YAML
        ;;
      cp) cp "$2" "$SERVERLB_VALUES"; printf 'cp %s\n' "$3" >> "$SERVERLB_CALLS" ;;
      restart) printf '%s\n' "$2" >> "$SERVERLB_CALLS" ;;
    esac
  }
  _kubectl() { return 0; }
  export HUB_RECOVERY_DOCKER_BIN=docker_stub SERVERLB_CALLS SERVERLB_VALUES
  export -f docker_stub _kubectl
  run _hub_recovery_ensure_serverlb_upstreams k3d-k3d-cluster c
  [ "$status" -eq 0 ]
  grep -qx 'cp k3d-c-serverlb:/etc/confd/values.yaml' "$SERVERLB_CALLS"
  grep -A1 '^  6443.tcp:$' "$SERVERLB_VALUES" | grep -qx '  - k3d-c-server-0'
  [ "$(tail -n 1 "$SERVERLB_CALLS")" = "k3d-c-serverlb" ]
  [ "$(wc -l < "$SERVERLB_CALLS" | tr -d ' ')" -eq 2 ]
}

@test "_hub_recovery_ensure_serverlb_upstreams: fails when the host API never becomes ready" {
  SERVERLB_CALLS="${BATS_TEST_TMPDIR}/serverlb-calls"
  : > "$SERVERLB_CALLS"
  docker_stub() {
    case "$1" in
      ps) printf '%s\n' 'server k3d-c-server-0' ;;
      exec) cat <<'YAML'
ports:
  6443.tcp: []
  80.tcp: []
  443.tcp: []
YAML
        ;;
      cp) : ;;
      restart) printf '%s\n' "$2" >> "$SERVERLB_CALLS" ;;
    esac
  }
  _kubectl() { return 1; }
  export HUB_RECOVERY_DOCKER_BIN=docker_stub HUB_RECOVERY_SERVERLB_WAIT_SECONDS=0 SERVERLB_CALLS
  export -f docker_stub _kubectl
  run _hub_recovery_ensure_serverlb_upstreams k3d-k3d-cluster c
  [ "$status" -ne 0 ]
}

@test "_hub_recovery_ensure_serverlb_upstreams: unreadable LB values fail without restart" {
  SERVERLB_CALLS="${BATS_TEST_TMPDIR}/serverlb-calls"
  : > "$SERVERLB_CALLS"
  docker_stub() {
    case "$1" in
      ps) printf '%s\n' 'server k3d-c-server-0' ;;
      exec) return 1 ;;
      restart) printf '%s\n' "$2" >> "$SERVERLB_CALLS" ;;
    esac
  }
  export HUB_RECOVERY_DOCKER_BIN=docker_stub SERVERLB_CALLS
  export -f docker_stub
  run _hub_recovery_ensure_serverlb_upstreams k3d-k3d-cluster c
  [ "$status" -ne 0 ]
  [ ! -s "$SERVERLB_CALLS" ]
}

function _stub_argocd_admin_mirror_dependencies() {
  MIRROR_CALLS="${BATS_TEST_TMPDIR}/argocd-admin-mirror-calls"
  MIRROR_ROOT_TOKEN_B64="cm9vdC10b2tlbg=="
  MIRROR_PASSWORD="stub-argocd-password"
  MIRROR_PASSWORD_B64="c3R1Yi1hcmdvY2QtcGFzc3dvcmQ="
  MIRROR_KV_GET_STATUS=1
  MIRROR_CURL_CODE=200
  : > "$MIRROR_CALLS"
  export MIRROR_CALLS MIRROR_ROOT_TOKEN_B64 MIRROR_PASSWORD MIRROR_PASSWORD_B64 MIRROR_KV_GET_STATUS MIRROR_CURL_CODE
  _kubectl() {
    case "$*" in
      *"get secret vault-root"*) printf '%s' "$MIRROR_ROOT_TOKEN_B64" ;;
      *"get secret argocd-initial-admin-secret"*)
        local secret_attempt
        secret_attempt=$(grep -c '^get secret argocd-initial-admin-secret' "$MIRROR_CALLS" || true)
        printf 'get secret argocd-initial-admin-secret\n' >> "$MIRROR_CALLS"
        if [[ "${MIRROR_EMPTY_ATTEMPTS:-0}" -ge $((secret_attempt + 1)) ]]; then
          return 0
        fi
        printf '%s' "$MIRROR_PASSWORD_B64"
        ;;
      *"vault kv get"*) cat >/dev/null; printf 'kv get\n' >> "$MIRROR_CALLS"; return "$MIRROR_KV_GET_STATUS" ;;
      *"vault kv put"*)
        local stdin
        stdin=$(cat)
        printf '%s' "$stdin" | jq -e 'select(.username == "admin")' >/dev/null
        printf 'kv put argocd/admin username\n' >> "$MIRROR_CALLS"
        ;;
    esac
  }
  curl() { printf 'curl\n' >> "$MIRROR_CALLS"; printf '%s' "$MIRROR_CURL_CODE"; }
  _no_trace() { "$@"; }
  _info() { printf 'info\n' >> "$MIRROR_CALLS"; }
  _warn() { printf 'warn\n' >> "$MIRROR_CALLS"; }
  _err() { printf 'err\n' >> "$MIRROR_CALLS"; }
}

@test "_hub_recovery_mirror_argocd_admin: skips a Vault entry that already has a password" {
  _stub_argocd_admin_mirror_dependencies
  MIRROR_KV_GET_STATUS=0
  run _hub_recovery_mirror_argocd_admin hub-context
  [ "$status" -eq 0 ]
  run grep -Fq curl "$MIRROR_CALLS"
  [ "$status" -ne 0 ]
  run grep -Fq 'kv put' "$MIRROR_CALLS"
  [ "$status" -ne 0 ]
  run grep -Fq "$MIRROR_PASSWORD" "$MIRROR_CALLS"
  [ "$status" -ne 0 ]
}

@test "_hub_recovery_mirror_argocd_admin: stores an ArgoCD-verified initial password" {
  _stub_argocd_admin_mirror_dependencies
  run _hub_recovery_mirror_argocd_admin hub-context
  [ "$status" -eq 0 ]
  grep -Fq 'kv put' "$MIRROR_CALLS"
  grep -Fq argocd/admin "$MIRROR_CALLS"
  grep -Fq username "$MIRROR_CALLS"
  run grep -Fq "$MIRROR_PASSWORD" "$MIRROR_CALLS"
  [ "$status" -ne 0 ]
}

@test "_hub_recovery_mirror_argocd_admin: does not store a rejected initial password" {
  _stub_argocd_admin_mirror_dependencies
  MIRROR_CURL_CODE=401
  run _hub_recovery_mirror_argocd_admin hub-context
  [ "$status" -eq 0 ]
  grep -Fq curl "$MIRROR_CALLS"
  run grep -Fq 'kv put' "$MIRROR_CALLS"
  [ "$status" -ne 0 ]
  run grep -Fq "$MIRROR_PASSWORD" "$MIRROR_CALLS"
  [ "$status" -ne 0 ]
}

@test "_hub_recovery_mirror_argocd_admin: skips an absent initial secret" {
  _stub_argocd_admin_mirror_dependencies
  MIRROR_PASSWORD_B64=""
  HUB_RECOVERY_MIRROR_RETRY_DELAY=0
  export HUB_RECOVERY_MIRROR_RETRY_DELAY
  run _hub_recovery_mirror_argocd_admin hub-context
  [ "$status" -eq 0 ]
  run grep -Fq curl "$MIRROR_CALLS"
  [ "$status" -ne 0 ]
  run grep -Fq 'kv put' "$MIRROR_CALLS"
  [ "$status" -ne 0 ]
  run grep -Fq "$MIRROR_PASSWORD" "$MIRROR_CALLS"
  [ "$status" -ne 0 ]
}

@test "_hub_recovery_mirror_argocd_admin: retries until the initial secret appears" {
  _stub_argocd_admin_mirror_dependencies
  MIRROR_EMPTY_ATTEMPTS=2
  HUB_RECOVERY_MIRROR_RETRY_DELAY=0
  export MIRROR_EMPTY_ATTEMPTS HUB_RECOVERY_MIRROR_RETRY_DELAY
  run _hub_recovery_mirror_argocd_admin hub-context
  [ "$status" -eq 0 ]
  grep -Fq 'kv put' "$MIRROR_CALLS"
  [ "$(grep -c '^get secret argocd-initial-admin-secret' "$MIRROR_CALLS")" -eq 3 ]
  run grep -Fq "$MIRROR_PASSWORD" "$MIRROR_CALLS"
  [ "$status" -ne 0 ]
}

@test "_hub_recovery_mirror_argocd_admin: exhausted secret retry stays non-fatal" {
  _stub_argocd_admin_mirror_dependencies
  MIRROR_EMPTY_ATTEMPTS=10
  HUB_RECOVERY_MIRROR_RETRY_DELAY=0
  export MIRROR_EMPTY_ATTEMPTS HUB_RECOVERY_MIRROR_RETRY_DELAY
  run _hub_recovery_mirror_argocd_admin hub-context
  [ "$status" -eq 0 ]
  run grep -Fq curl "$MIRROR_CALLS"
  [ "$status" -ne 0 ]
  run grep -Fq 'kv put' "$MIRROR_CALLS"
  [ "$status" -ne 0 ]
  [ "$(grep -c '^get secret argocd-initial-admin-secret' "$MIRROR_CALLS")" -eq 10 ]
  [ "$(grep -c '^warn$' "$MIRROR_CALLS")" -eq 1 ]
  run grep -Fq "$MIRROR_PASSWORD" "$MIRROR_CALLS"
  [ "$status" -ne 0 ]
}

@test "_hub_recovery_mirror_argocd_admin: fails when the Vault root token is absent" {
  _stub_argocd_admin_mirror_dependencies
  MIRROR_ROOT_TOKEN_B64=""
  run _hub_recovery_mirror_argocd_admin hub-context
  [ "$status" -eq 1 ]
  run grep -Fq curl "$MIRROR_CALLS"
  [ "$status" -ne 0 ]
  run grep -Fq 'kv put' "$MIRROR_CALLS"
  [ "$status" -ne 0 ]
  run grep -Fq "$MIRROR_PASSWORD" "$MIRROR_CALLS"
  [ "$status" -ne 0 ]
}
