#!/usr/bin/env bats

setup() {
  export TEST_ROOT="$BATS_TEST_TMPDIR/root" STUB_BIN="$BATS_TEST_TMPDIR/root/bin"
  export CALL_LOG="$TEST_ROOT/calls.log" STDIN_LOG="$TEST_ROOT/stdin.log" VLOG="$TEST_ROOT/vault.log"
  mkdir -p "$STUB_BIN" "$TEST_ROOT"; : > "$CALL_LOG"; : > "$STDIN_LOG"; : > "$VLOG"
  cat > "$STUB_BIN/git" <<'STUB'
#!/usr/bin/env bash
printf 'git %q\n' "$*" >> "$CALL_LOG"
if [[ "$1" == clone ]]; then dest="${@: -1}"; mkdir -p "$dest"; cp -R "$DR_TEST_REPO_FIXTURE/snapshots" "$dest/"; fi
if [[ "$1" == commit ]]; then rm -rf "$TEST_ROOT/last-snapshots"; cp -R snapshots "$TEST_ROOT/last-snapshots"; fi
STUB
  cat > "$STUB_BIN/vault" <<'STUB'
#!/usr/bin/env bash
printf 'vault' >> "$VLOG"; printf ' %q' "$@" >> "$VLOG"; printf '\n' >> "$VLOG"
case "$*" in
  *-generate-otp*) printf '{"otp":"OTP-SENTINEL"}' ;;
  *-init*) printf '{"nonce":"NONCE"}' ;;
  *-decode=-*) cat >> "$STDIN_LOG"; printf 'ROOT-TOKEN' ;;
  *-cancel*) : ;;
  *'token revoke -self'*) : ;;
  *'kv list'*) printf '{"data":["secret/app"]}' ;;
  *'generate-root'*'-format=json -'*) [[ "${DR_TEST_KEY_FAIL:-0}" == 1 ]] && exit 1; cat >> "$STDIN_LOG"; printf '{"encoded_token":"ENCODED-SENTINEL"}' ;;
esac
STUB
  cat > "$STUB_BIN/kubectl" <<'STUB'
#!/usr/bin/env bash
printf 'kubectl' >> "$CALL_LOG"; printf ' %q' "$@" >> "$CALL_LOG"; printf '\n' >> "$CALL_LOG"; args="$*"
if [[ "$args" == *"exec deployment/postgres-keycloak"* ]]; then printf '3\n'
elif [[ "$args" == *"exec statefulset/openldap"* ]]; then printf 'dn: a\ndn: b\n'
elif [[ "$args" == *"get pvc"* && "$args" == *"volumeName"* ]]; then claim="${args#*get pvc }"; claim="${claim%% *}"; printf 'pv-%s\n' "$claim"
elif [[ "$args" == *"get pvc"* && "$args" == *"-o json"* ]]; then
  claim="${args#*get pvc }"; claim="${claim%% *}"
  case "$claim" in
    data-vault-0) printf '%s\n' '{"spec":{"resources":{"requests":{"storage":"2Gi"}},"storageClassName":"local-path","accessModes":["ReadWriteOnce"]}}' ;;
    postgres-keycloak-pvc) printf '%s\n' '{"spec":{"resources":{"requests":{"storage":"8Gi"}},"storageClassName":"fast","accessModes":["ReadWriteOnce","ReadWriteMany"]}}' ;;
    data-openldap-0) printf '%s\n' '{"spec":{"resources":{"requests":{"storage":"3Gi"}},"storageClassName":"local-path","accessModes":["ReadWriteOnce"]}}' ;;
  esac
elif [[ "$args" == *"get pv"* && "$args" == *"hostname"* ]]; then
  pv="${args#*get pv }"; pv="${pv%% *}"
  if [[ "${DR_TEST_MISMATCH:-0}" == 1 ]]; then printf node-z; else case "$pv" in pv-data-vault-0) printf node-a;; pv-postgres-keycloak-pvc) printf node-b;; pv-data-openldap-0) printf node-c;; esac; fi
elif [[ "$args" == *"get pv"* && "$args" == *"local.path"* ]]; then pv="${args#*get pv }"; pv="${pv%% *}"; printf '/var/lib/k3s/%s\n' "${pv#pv-}"
elif [[ "$args" == *"apply -f -"* ]]; then cat > "$TEST_ROOT/applied-$RANDOM.yaml"
elif [[ "$args" == *"get pods"* ]]; then printf 'postgres-keycloak-abc\n'; fi
STUB
  cat > "$STUB_BIN/docker" <<'STUB'
#!/usr/bin/env bash
printf 'docker' >> "$CALL_LOG"; printf ' %q' "$@" >> "$CALL_LOG"; printf '\n' >> "$CALL_LOG"
[[ "$*" == *" -cf - "* ]] && printf tar-stream || cat >/dev/null
STUB
  cat > "$STUB_BIN/age" <<'STUB'
#!/usr/bin/env bash
printf 'age' >> "$CALL_LOG"; printf ' %q' "$@" >> "$CALL_LOG"; printf '\n' >> "$CALL_LOG"
  if [[ "$1" == -r ]]; then out=""; next=0; for arg in "$@"; do [[ "$arg" == -o ]] && next=1 && continue; [[ "$next" == 1 ]] && out="$arg" && next=0; done; ls -1 "$(dirname "$out")" >> "$TEST_ROOT/age-stage.log"; cat >/dev/null; [[ "${DR_TEST_LARGE:-0}" == 1 ]] && truncate -s 99614720 "$out" || printf encrypted > "$out"
else identity=""; input="-"; idx=1; while (( idx <= $# )); do case "${!idx}" in -i) idx=$((idx+1)); identity="${!idx}";; -) input=-;; *) input="${!idx}";; esac; idx=$((idx+1)); done; [[ -r "$identity" ]] && cat "$identity" >> "$STDIN_LOG"; printf 'decrypt %s\n' "$input" >> "$TEST_ROOT/decrypt.log"; [[ "$input" == - ]] && cat >/dev/null; printf tar-stream; fi
STUB
  chmod +x "$STUB_BIN"/*; export PATH="$STUB_BIN:$PATH" PLUGINS_DIR="$PWD/scripts/plugins"
}

make_fixture() {
  export DR_TEST_REPO_FIXTURE="$TEST_ROOT/fixture"; local root="$DR_TEST_REPO_FIXTURE/snapshots/20261009T120000Z"; mkdir -p "$root"
  cat > "$root/pv-pvc.yaml" <<'YAML'
apiVersion: dr.k3d-manager/v1
kind: HubClaimMetadata
metadata:
  name: data-vault-0
  namespace: secrets
spec:
  size: 2Gi
  storageClass: local-path
  accessModes:
    - ReadWriteOnce
  logicalNode: node-a
---
apiVersion: dr.k3d-manager/v1
kind: HubClaimMetadata
metadata:
  name: postgres-keycloak-pvc
  namespace: identity
spec:
  size: 8Gi
  storageClass: fast
  accessModes:
    - ReadWriteOnce
    - ReadWriteMany
  logicalNode: node-b
---
apiVersion: dr.k3d-manager/v1
kind: HubClaimMetadata
metadata:
  name: data-openldap-0
  namespace: identity
spec:
  size: 3Gi
  storageClass: local-path
  accessModes:
    - ReadWriteOnce
  logicalNode: node-c
---
YAML
  printf '%s\n' '{"vault_paths":["secret/app"],"keycloak_realm_user_count":3,"ldap_entry_count":2}' > "$root/inventory.json"
  printf encrypted > "$root/secrets-data-vault-0.tar.age"; printf encrypted > "$root/identity-postgres-keycloak-pvc.tar.age"; printf encrypted > "$root/identity-data-openldap-0.tar.age"
  (cd "$root" && sha256sum *.age > SHA256SUMS)
}

source_plugin() {
  export SCRIPT_DIR="$PWD/scripts"
  _err() { printf '%s\n' "$*" >&2; }
  _warn() { printf '%s\n' "$*" >&2; }
  source "$PLUGINS_DIR/hub_data.sh"
  _kubectl() { kubectl "$@"; }
  _hub_recovery_logical_node() { printf '%s\n' "$1"; }
  _hub_snapshot_claim_node() { case "$1/$2" in secrets/data-vault-0) printf node-a;; identity/postgres-keycloak-pvc) printf node-b;; identity/data-openldap-0) printf node-c;; esac; }
  _hub_snapshot_claim_pv() { printf 'pv-%s\n' "$2"; }
  _hub_snapshot_claim_path() { printf '/var/lib/k3s/%s\n' "${1#pv-}"; }
  _hub_snapshot_node_container() { printf 'k3d-test-%s\n' "$1"; }
  _hub_data_apply_keycloak() { :; }
  _secret_load_data() { [[ "$2" == identity ]] && printf '%s\n' "${DR_TEST_IDENTITY:-AGE-IDENTITY}" || printf '%s\n' "${DR_TEST_SHARD:-SHARD-SENTINEL}"; }
  _vault_exec_stream() {
    local index=1 input command_name
    local -a command=()
    while (( index <= $# )); do
      if [[ "${!index}" == -- ]]; then index=$((index + 1)); command=("${@:index}"); break; fi
      index=$((index + 1))
    done
    command_name="${command[0]:-}"
    if [[ "$command_name" == sh ]]; then
      input="$(cat)"
      printf '%s' "$input" >> "$STDIN_LOG"
      printf '%s' "$input" | bash -c "${command[2]}" "${command[3]:-sh}"
    elif [[ "$command_name" == vault ]]; then
      "${command[@]}" </dev/null
    else
      return 1
    fi
  }
  : > "$CALL_LOG"; : > "$STDIN_LOG"; : > "$VLOG"
}

@test "hub data restore: decrypts every claim and uses metadata" {
  make_fixture; source_plugin; export DR_DRILL_CONTEXT=ctx DR_DRILL_CLUSTER=test DR_DRILL_RESTORE_STAGE="$TEST_ROOT/stage"; printf recipient > "$TEST_ROOT/recipient"; export K3DM_HUB_DATA_AGE_RECIPIENT="$TEST_ROOT/recipient"
  export DR_TEST_IDENTITY=IDENTITY-SENTINEL
  run hub_data_restore; [ "$status" -eq 0 ]
  for pair in "secrets data-vault-0 node-a 2Gi local-path ReadWriteOnce" "identity postgres-keycloak-pvc node-b 8Gi fast ReadWriteMany" "identity data-openldap-0 node-c 3Gi local-path ReadWriteOnce"; do
    read -r ns claim node size storage mode <<<"$pair"
    grep -Fq "tar -C /var/lib/k3s/${claim} -xpf -" "$CALL_LOG"
    grep -Fq "${ns}-${claim}.tar.age" "$TEST_ROOT/decrypt.log"
    grep -Fq "storageClassName: ${storage}" "$TEST_ROOT"/applied-*.yaml; grep -Fq "storage: ${size}" "$TEST_ROOT"/applied-*.yaml; grep -Fq -- "- ${mode}" "$TEST_ROOT"/applied-*.yaml; grep -Fq "selected-node: k3d-test-${node}" "$TEST_ROOT"/applied-*.yaml
  done
  [ -s "$TEST_ROOT/stage/pv-pvc.yaml" ]; [ -s "$TEST_ROOT/stage/inventory.json" ]
  [ "$(grep -c IDENTITY-SENTINEL "$VLOG" || true)" -eq 0 ]; [ "$(printf '%s' "$output" | grep -c IDENTITY-SENTINEL || true)" -eq 0 ]; grep -q IDENTITY-SENTINEL "$STDIN_LOG"
}

@test "hub data restore: node mismatch stops before extraction" {
  make_fixture; source_plugin; export DR_DRILL_CONTEXT=ctx DR_DRILL_CLUSTER=test DR_DRILL_RESTORE_STAGE="$TEST_ROOT/stage" DR_TEST_MISMATCH=1
  run hub_data_restore; [ "$status" -ne 0 ]; [ "$(grep -c docker "$CALL_LOG" || true)" -eq 0 ]
}

@test "hub data restore: automatic stage is removed and caller stage survives" {
  make_fixture; source_plugin; export DR_DRILL_CONTEXT=ctx DR_DRILL_CLUSTER=test DR_DRILL_RESTORE_STAGE="$TEST_ROOT/stage"; hub_data_restore; [ -f "$TEST_ROOT/stage/pv-pvc.yaml" ]; [ -f "$TEST_ROOT/stage/inventory.json" ]
  unset DR_DRILL_RESTORE_STAGE; export TMPDIR="$TEST_ROOT/tmp"; mkdir -p "$TMPDIR"; hub_data_restore; [ "$(find "$TMPDIR" -mindepth 1 -print | wc -l)" -eq 0 ]
}

@test "hub data restore: empty context returns 2 without kubectl" {
  make_fixture; source_plugin; unset DR_DRILL_CONTEXT; export DR_DRILL_CLUSTER=test; run hub_data_restore; [ "$status" -eq 2 ]; [ "$(grep -c kubectl "$CALL_LOG" || true)" -eq 0 ]
}

@test "hub data restore: scales live workloads down and up" {
  make_fixture; source_plugin; export DR_DRILL_CONTEXT=ctx DR_DRILL_CLUSTER=test DR_DRILL_RESTORE_STAGE="$TEST_ROOT/stage"; hub_data_restore
  for workload in statefulset/vault deployment/postgres-keycloak statefulset/openldap; do [ "$(grep -c "scale ${workload} --replicas=0" "$CALL_LOG")" -eq 1 ]; [ "$(grep -c "scale ${workload} --replicas=1" "$CALL_LOG")" -eq 1 ]; done
}

@test "hub data export: streams each claim from its own node and path" {
  source_plugin; printf recipient > "$TEST_ROOT/recipient"; export K3DM_HUB_DATA_AGE_RECIPIENT="$TEST_ROOT/recipient" K3DM_HUB_DATA_TIMESTAMP=20261009T120000Z
  _hub_data_inventory() { printf '%s\n' '{"vault_paths":["secret/app"],"keycloak_realm_user_count":3,"ldap_entry_count":2}' > "$1/inventory.json"; }
  run hub_data_export; [ "$status" -eq 0 ]; [ "$(find "${TMPDIR:-/tmp}" -name '*.tar' -print | wc -l)" -eq 0 ]; [ "$(grep -Ec '\.tar$' "$TEST_ROOT/age-stage.log" || true)" -eq 0 ]
  grep -Fq 'docker exec k3d-test-node-a tar -C /var/lib/k3s/data-vault-0 -cf - .' "$CALL_LOG"; grep -Fq 'docker exec k3d-test-node-b tar -C /var/lib/k3s/postgres-keycloak-pvc -cf - .' "$CALL_LOG"; grep -Fq 'docker exec k3d-test-node-c tar -C /var/lib/k3s/data-openldap-0 -cf - .' "$CALL_LOG"
}

@test "hub data export: encrypted contents, checksums, and split limit" {
  source_plugin; printf recipient > "$TEST_ROOT/recipient"; export K3DM_HUB_DATA_AGE_RECIPIENT="$TEST_ROOT/recipient" K3DM_HUB_DATA_TIMESTAMP=20261009T120000Z DR_TEST_LARGE=1
  _hub_data_inventory() { printf '%s\n' '{"vault_paths":["secret/app"],"keycloak_realm_user_count":3,"ldap_entry_count":2}' > "$1/inventory.json"; }
  run hub_data_export; [ "$status" -eq 0 ]; [ "$(grep -R -c 'state.db\|kind: Secret' "$TEST_ROOT/last-snapshots" | awk -F: '{s += $NF} END {print s+0}')" -eq 0 ]
  while read -r sum file; do [[ "$file" == *.age || "$file" == *.age.part-* ]]; done < "$TEST_ROOT/last-snapshots/20261009T120000Z/SHA256SUMS"
  [ "$(find "$TEST_ROOT/last-snapshots" -type f -size +95M -print | wc -l)" -eq 0 ]
}

@test "hub data vault: executing stub proves order, stdin hygiene, and cancel" {
  source_plugin; export DR_TEST_SHARD=SHARD-SENTINEL
  _secret_load_data() { [[ "$2" == *:count ]] && printf 1 || printf '%s\n' "$DR_TEST_SHARD"; }
  printf '%s\n' '{"vault_paths":["secret/app"]}' > "$TEST_ROOT/inventory.json"
  run hub_data_verify_vault_paths secrets vault "$TEST_ROOT/inventory.json"; [ "$status" -eq 0 ]
  [ "$(grep -n -- '-generate-otp' "$VLOG" | cut -d: -f1)" -lt "$(grep -n -- '-init' "$VLOG" | cut -d: -f1)" ]
  [ "$(grep -c 'generate-root -nonce' "$VLOG" || true)" -eq 1 ]
  [ "$(grep -c 'decode=-' "$VLOG" || true)" -eq 1 ]
  [ "$(grep -n 'generate-root -nonce' "$VLOG" | cut -d: -f1)" -lt "$(grep -n 'decode=-' "$VLOG" | cut -d: -f1)" ]; [ "$(grep -n 'token revoke -self' "$VLOG" | cut -d: -f1)" -gt "$(grep -n 'decode=-' "$VLOG" | cut -d: -f1)" ]
  [ "$(grep -c SHARD-SENTINEL "$VLOG" || true)" -eq 0 ]; [ "$(grep -F OTP-SENTINEL "$VLOG" | grep -v -- '-otp=OTP-SENTINEL' | wc -l)" -eq 0 ]
  grep -q SHARD-SENTINEL "$STDIN_LOG"; grep -q OTP-SENTINEL "$STDIN_LOG"; grep -q ENCODED-SENTINEL "$STDIN_LOG"
  export DR_TEST_KEY_FAIL=1
  run _hub_data_generate_root secrets vault; [ "$status" -ne 0 ]; grep -q -- '-cancel' "$VLOG"
}

@test "hub data vault: revoke runs after a post-root KV failure" {
  source_plugin; printf '%s\n' '{"vault_paths":["secret/app"]}' > "$TEST_ROOT/inventory.json"; _hub_data_generate_root() { printf root-token; }; _hub_data_vault_kv_list() { return 1; }; _hub_data_vault_revoke() { printf revoke >> "$VLOG"; }
  run hub_data_verify_vault_paths secrets vault "$TEST_ROOT/inventory.json"; [ "$status" -ne 0 ]; grep -q revoke "$VLOG"
}

@test "hub data vault: invalid path is rejected before any exec" {
  source_plugin; printf '%s\n' '{"vault_paths":["secret/app; bad"]}' > "$TEST_ROOT/inventory.json"; _hub_data_generate_root() { printf root-token; }
  run hub_data_verify_vault_paths secrets vault "$TEST_ROOT/inventory.json"; [ "$status" -ne 0 ]; [ "$(grep -c kubectl "$CALL_LOG" || true)" -eq 0 ]; [ "$(wc -c < "$VLOG")" -eq 0 ]
  _vault_exec_stream() { printf '%s\n' "$*" >> "$VLOG"; printf '{"data":[]}' ; }
  _hub_data_vault_kv_list token secrets vault secret/app >/dev/null
  [ "$(grep -c eval "$VLOG" || true)" -eq 0 ]
}
