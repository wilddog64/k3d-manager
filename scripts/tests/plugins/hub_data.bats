#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  export TEST_ROOT="$BATS_TEST_TMPDIR/root" STUB_BIN="$BATS_TEST_TMPDIR/root/bin"
  export CALL_LOG="$TEST_ROOT/calls.log" STDIN_LOG="$TEST_ROOT/stdin.log" VLOG="$TEST_ROOT/vault.log"
  mkdir -p "$STUB_BIN" "$TEST_ROOT"; : > "$CALL_LOG"; : > "$STDIN_LOG"; : > "$VLOG"
  cat > "$STUB_BIN/git" <<'STUB'
#!/usr/bin/env bash
printf 'git %q\n' "$*" >> "$CALL_LOG"
if [[ "$*" == *clone* ]]; then dest="${@: -1}"; mkdir -p "$dest"; cp -R "$DR_TEST_REPO_FIXTURE/snapshots" "$dest/"; fi
if [[ "$*" == *commit* ]]; then rm -rf "$TEST_ROOT/last-snapshots"; cp -R snapshots "$TEST_ROOT/last-snapshots"; fi
if [[ "$*" == *rev-parse* ]]; then printf 'SHA-SENTINEL\n'; fi
if [[ "$*" == *ls-remote* && "${DR_TEST_REMOTE_MISMATCH:-0}" != 1 ]]; then printf 'SHA-SENTINEL\trefs/heads/snapshots\n'; fi
if [[ "$*" == *ls-tree* ]]; then printf 'results/20261010T182508Z.json\n'; fi
if [[ "$*" == *show* ]]; then printf '{"success":true,"export":"%s"}\n' "${DR_TEST_RESULT_EXPORT:-20261009T120000Z}"; fi
if [[ "$*" == *config* ]]; then printf 'apiVersion: v1\nkind: Config\n' ; fi
if [[ "$*" == *fetch* && "${DR_TEST_FETCH_FAIL:-0}" == 1 ]]; then exit 1; fi
if [[ "$*" == *ls-remote* && "${DR_TEST_REMOTE_MISMATCH:-0}" == 1 ]]; then printf 'OTHER-SHA\trefs/heads/snapshots\n'; fi
if [[ "$*" == *push* ]]; then printf 'push %s\n' "$*" >> "$TEST_ROOT/push.log"; fi
if [[ "$*" == *rm\ * ]]; then printf 'rm %s\n' "$*" >> "$TEST_ROOT/git.log"; fi
if [[ "$*" == *write-tree* || "$*" == *commit-tree* ]]; then printf 'NEW-SHA\n'; fi
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
  *'auth/kubernetes/login'*) printf 'INVENTORY-TOKEN' ;;
  *'kv list'*) printf '%s' "${DR_TEST_KV_LIST:-[\"app/\",\"shared\"]}" ;;
  *'generate-root'*'-format=json -'*) [[ "${DR_TEST_KEY_FAIL:-0}" == 1 ]] && exit 1; cat >> "$STDIN_LOG"; printf '{"encoded_token":"ENCODED-SENTINEL"}' ;;
esac
STUB
  cat > "$STUB_BIN/kubectl" <<'STUB'
#!/usr/bin/env bash
printf 'kubectl' >> "$CALL_LOG"; printf ' %q' "$@" >> "$CALL_LOG"; printf '\n' >> "$CALL_LOG"; args="$*"
if [[ "$args" == *"config view"* ]]; then printf 'apiVersion: v1\nkind: Config\n'
elif [[ "$args" == *"create token hub-data-export"* ]]; then printf 'JWT-SENTINEL\n'
elif [[ "$args" == *"exec deployment/postgres-keycloak"* ]]; then printf '3\n'
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
elif [[ -n "${DR_TEST_SCALE_FAIL:-}" && "$args" == *"scale ${DR_TEST_SCALE_FAIL} "* ]]; then printf 'Error from server (NotFound): %s\n' "$DR_TEST_SCALE_FAIL" >&2; exit 1
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
  if [[ "$1" == -r ]]; then out=""; next=0; for arg in "$@"; do [[ "$arg" == -o ]] && next=1 && continue; [[ "$next" == 1 ]] && out="$arg" && next=0; done; ls -1 "$(dirname "$out")" >> "$TEST_ROOT/age-stage.log"; cat >/dev/null; [[ "${DR_TEST_LARGE:-0}" == 1 ]] && { printf 'age-encryption.org/v1\n' > "$out"; truncate -s 99614720 "$out"; } || printf 'age-encryption.org/v1\nencrypted\n' > "$out"
else identity=""; input="-"; idx=1; while (( idx <= $# )); do case "${!idx}" in -i) idx=$((idx+1)); identity="${!idx}";; -) input=-;; *) input="${!idx}";; esac; idx=$((idx+1)); done; [[ -r "$identity" ]] && cat "$identity" >> "$STDIN_LOG"; printf 'decrypt %s\n' "$input" >> "$TEST_ROOT/decrypt.log"; [[ "$input" == - ]] && cat >/dev/null; printf tar-stream; fi
STUB
  chmod +x "$STUB_BIN"/*; export PATH="$STUB_BIN:$PATH" PLUGINS_DIR="$PWD/scripts/plugins"
  cat > "$STUB_BIN/curl" <<'STUB'
#!/usr/bin/env bash
for arg in "$@"; do [[ "$arg" == @* ]] && cp "${arg#@}" "$TEST_ROOT/metrics-body"; done
STUB
  chmod +x "$STUB_BIN/curl"
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
  printf 'age-encryption.org/v1\nencrypted\n' > "$root/secrets-data-vault-0.tar.age"; printf 'age-encryption.org/v1\nencrypted\n' > "$root/identity-postgres-keycloak-pvc.tar.age"; printf 'age-encryption.org/v1\nencrypted\n' > "$root/identity-data-openldap-0.tar.age"
  (cd "$root" && sha256sum *.age pv-pvc.yaml inventory.json > SHA256SUMS)
}

source_plugin() {
  export SCRIPT_DIR="$PWD/scripts"
  # Like lib-foundation's _err, this exits: a warning sent through _err must fail a test here too.
  _err() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
  _warn() { printf '%s\n' "$*" >&2; }
  _no_trace() { "$@"; }
  source "$PLUGINS_DIR/hub_data.sh"
  _kubectl() { kubectl "$@"; }
  export K3DM_HUB_DATA_CONTEXT=ctx
  export K3DM_HUB_DATA_DIR="$TEST_ROOT/hub-data"
  _hub_recovery_logical_node() { printf '%s\n' "$1"; }
  _hub_snapshot_claim_node() { case "$1/$2" in secrets/data-vault-0) printf node-a;; identity/postgres-keycloak-pvc) printf node-b;; identity/data-openldap-0) printf node-c;; esac; }
  _hub_snapshot_claim_pv() { printf 'pv-%s\n' "$2"; }
  _hub_snapshot_claim_path() { printf '/var/lib/k3s/%s\n' "${1#pv-}"; }
  _hub_snapshot_node_container() { printf 'k3d-test-%s\n' "$1"; }
  [[ "${DR_TEST_REAL_APPLY:-0}" == 1 ]] || _hub_data_apply_keycloak() { :; }
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
      [[ "${command[*]}" == *auth/kubernetes/login* ]] && cat >> "$STDIN_LOG"
      "${command[@]}" </dev/null
    else
      return 1
    fi
  }
  : > "$CALL_LOG"; : > "$STDIN_LOG"; : > "$VLOG"
}

make_export_dir() {
  local dir="$1" mode="${2:-full}"
  mkdir -p "$dir"
  printf 'age-encryption.org/v1\nencrypted\n' > "$dir/x.tar.age"
  printf '{}\n' > "$dir/inventory.json"
  printf 'metadata\n' > "$dir/pv-pvc.yaml"
  if [[ "$mode" == legacy ]]; then
    (cd "$dir" && sha256sum x.tar.age > SHA256SUMS)
  else
    (cd "$dir" && sha256sum x.tar.age pv-pvc.yaml inventory.json > SHA256SUMS)
  fi
}

make_prune_fixture() {
  local root="$TEST_ROOT/fixture/snapshots" stamp
  rm -rf "$TEST_ROOT/fixture"; mkdir -p "$root"
  for stamp in "$@"; do make_export_dir "$root/$stamp"; done
  export DR_TEST_REPO_FIXTURE="$TEST_ROOT/fixture" K3DM_HUB_DATA_DIR="$TEST_ROOT/prune-state"
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

@test "hub data restore: applies the drill postgres before scaling any claim down" {
  make_fixture; export DR_TEST_REAL_APPLY=1 REPO_ROOT="$PWD"; source_plugin; export DR_DRILL_CONTEXT=ctx DR_DRILL_CLUSTER=test DR_DRILL_RESTORE_STAGE="$TEST_ROOT/stage"
  run hub_data_restore; [ "$status" -eq 0 ]
  apply_line="$(grep -n -F -- "apply -f ${PWD}/scripts/etc/dr/postgres-keycloak.yaml" "$CALL_LOG" | head -1 | cut -d: -f1)"
  first_scale="$(grep -n -- '--replicas=0' "$CALL_LOG" | head -1 | cut -d: -f1)"
  [ -n "$apply_line" ]; [ -n "$first_scale" ]; [ "$apply_line" -lt "$first_scale" ]
}

@test "hub data restore: drill postgres starts at zero replicas and carries no password" {
  local manifest="$PWD/scripts/etc/dr/postgres-keycloak.yaml"
  grep -q '^  replicas: 0$' "$manifest"
  grep -q 'image: postgres:16-alpine$' "$manifest"
  grep -q 'claimName: postgres-keycloak-pvc$' "$manifest"
  [ "$(grep -v '^#' "$manifest" | grep -c -i -E 'password|secretKeyRef|secretRef|ExternalSecret' || true)" -eq 0 ]
}

@test "hub data restore: a workload that cannot be scaled stops the restore with its name" {
  make_fixture; source_plugin; export DR_DRILL_CONTEXT=ctx DR_DRILL_CLUSTER=test DR_DRILL_RESTORE_STAGE="$TEST_ROOT/stage" DR_TEST_SCALE_FAIL=deployment/postgres-keycloak
  _err() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
  run hub_data_restore; [ "$status" -ne 0 ]
  [[ "$output" == *"unable to scale deployment/postgres-keycloak"* ]]
  [ "$(grep -c docker "$CALL_LOG" || true)" -eq 0 ]
}

@test "hub data export: streams each claim from its own node and path" {
  make_fixture; source_plugin; printf recipient > "$TEST_ROOT/recipient"; export K3DM_HUB_DATA_AGE_RECIPIENT="$TEST_ROOT/recipient" K3DM_HUB_DATA_TIMESTAMP=20261009T120000Z
  _hub_data_inventory() { printf '%s\n' '{"vault_paths":["secret/app"],"keycloak_realm_user_count":3,"ldap_entry_count":2}' > "$1/inventory.json"; }
  run hub_data_export; [ "$status" -eq 0 ]; [ "$(find "${TMPDIR:-/tmp}" -name '*.tar' -print | wc -l)" -eq 0 ]; [ "$(grep -Ec '\.tar$' "$TEST_ROOT/age-stage.log" || true)" -eq 0 ]
  grep -Fq 'docker exec k3d-test-node-a tar -C /var/lib/k3s/data-vault-0 -cf - .' "$CALL_LOG"; grep -Fq 'docker exec k3d-test-node-b tar -C /var/lib/k3s/postgres-keycloak-pvc -cf - .' "$CALL_LOG"; grep -Fq 'docker exec k3d-test-node-c tar -C /var/lib/k3s/data-openldap-0 -cf - .' "$CALL_LOG"
}

@test "hub data export: encrypted contents, checksums, and split limit" {
  make_fixture; source_plugin; printf recipient > "$TEST_ROOT/recipient"; export K3DM_HUB_DATA_AGE_RECIPIENT="$TEST_ROOT/recipient" K3DM_HUB_DATA_TIMESTAMP=20261009T120000Z DR_TEST_LARGE=1
  _hub_data_inventory() { printf '%s\n' '{"vault_paths":["secret/app"],"keycloak_realm_user_count":3,"ldap_entry_count":2}' > "$1/inventory.json"; }
  run hub_data_export; [ "$status" -eq 0 ]; [ "$(grep -R -c 'state.db\|kind: Secret' "$TEST_ROOT/last-snapshots" | awk -F: '{s += $NF} END {print s+0}')" -eq 0 ]
  while read -r sum file; do [[ "$file" == *.age || "$file" == *.age.part-* || "$file" == pv-pvc.yaml || "$file" == inventory.json ]]; done < "$TEST_ROOT/last-snapshots/20261009T120000Z/SHA256SUMS"
  [ "$(find "$TEST_ROOT/last-snapshots" -type f -size +95M -print | wc -l)" -eq 0 ]
}

@test "hub data vault: executing stub proves order, stdin hygiene, and cancel" {
  source_plugin; export DR_TEST_SHARD=SHARD-SENTINEL
  _secret_load_data() { [[ "$2" == *:count ]] && printf 1 || printf '%s\n' "$DR_TEST_SHARD"; }
  printf '%s\n' '{"vault_paths":["app/"]}' > "$TEST_ROOT/inventory.json"
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
  source_plugin; printf '%s\n' '{"vault_paths":["app/"]}' > "$TEST_ROOT/inventory.json"; _hub_data_generate_root() { printf root-token; }; _hub_data_vault_kv_list() { return 1; }; _hub_data_vault_revoke() { printf revoke >> "$VLOG"; }
  run hub_data_verify_vault_paths secrets vault "$TEST_ROOT/inventory.json"; [ "$status" -ne 0 ]; grep -q revoke "$VLOG"
}

@test "hub data vault: invalid path is rejected before any exec" {
  source_plugin; printf '%s\n' '{"vault_paths":["app; bad"]}' > "$TEST_ROOT/inventory.json"; _hub_data_generate_root() { printf root-token; }
  run hub_data_verify_vault_paths secrets vault "$TEST_ROOT/inventory.json"; [ "$status" -ne 0 ]; [ "$(grep -c kubectl "$CALL_LOG" || true)" -eq 0 ]; [ "$(wc -c < "$VLOG")" -eq 0 ]
  _vault_exec_stream() { printf '%s\n' "$*" >> "$VLOG"; printf '{"data":[]}' ; }
  _hub_data_vault_kv_list token secrets vault secret/app >/dev/null
  [ "$(grep -c eval "$VLOG" || true)" -eq 0 ]
}

@test "hub-data: the dispatcher finds every public hub_data function" {
  local dispatcher="${BATS_TEST_DIRNAME}/../../k3d-manager"
  run env -u DR_DRILL_CONTEXT -u DR_DRILL_CLUSTER "$dispatcher" hub_data_restore
  [[ "$output" != *"not found in plugins"* ]]
  [[ "$output" == *"DR_DRILL_CONTEXT and DR_DRILL_CLUSTER are required"* ]]
  run env K3DM_HUB_DATA_AGE_RECIPIENT="$TEST_ROOT/no-recipient" "$dispatcher" hub_data_export
  [[ "$output" != *"not found in plugins"* ]]
  [[ "$output" == *"missing age recipient"* ]]
  run "$dispatcher" hub_data_verify_vault_paths
  [[ "$output" != *"not found in plugins"* ]]
  [[ "$output" == *"inventory path required"* ]]
}

_fake_identity_pod() {
  export POD_BIN="$BATS_TEST_TMPDIR/pod-bin"; mkdir -p "$POD_BIN"
  cat > "$POD_BIN/psql" <<'STUB'
#!/usr/bin/env bash
[[ " $* " == *" -U keycloak -d keycloak "* ]] || { echo 'psql: FATAL: role does not exist' >&2; exit 2; }
printf '6\n'
STUB
  cat > "$POD_BIN/ldapsearch" <<'STUB'
#!/usr/bin/env bash
[[ " $* " == *" -Y EXTERNAL -H ldapi:/// "* && " $* " == *" -b dc=home,dc=org "* ]] || { echo "ldap_sasl_bind(SIMPLE): Can't contact LDAP server (-1)" >&2; exit 255; }
for i in $(seq 1 12); do printf 'dn: cn=e%s,dc=home,dc=org\n\n' "$i"; done
STUB
  chmod +x "$POD_BIN/psql" "$POD_BIN/ldapsearch"
  _kubectl() {
    while (( $# )) && [[ "$1" != -- ]]; do shift; done; shift
    POSTGRES_USER=keycloak POSTGRES_DB=keycloak LDAP_ROOT=dc=home,dc=org PATH="$POD_BIN:$PATH" "$@"
  }
  _hub_data_generate_root() { printf root-token; }
  _hub_data_vault_kv_list() { printf '["app/","shared"]'; }
  _hub_data_vault_revoke() { :; }
}

@test "hub data inventory: counts Keycloak users and LDAP entries with the pod's own credentials" {
  source_plugin; _fake_identity_pod
  run _hub_data_inventory "$TEST_ROOT"; [ "$status" -eq 0 ]
  [ "$(jq -r .keycloak_realm_user_count "$TEST_ROOT/inventory.json")" = 6 ]
  [ "$(jq -r .ldap_entry_count "$TEST_ROOT/inventory.json")" = 12 ]
}

@test "hub data inventory: records the bare array vault kv list prints" {
  source_plugin; _fake_identity_pod
  run _hub_data_inventory "$TEST_ROOT"; [ "$status" -eq 0 ]
  [ "$(jq -c .vault_paths "$TEST_ROOT/inventory.json")" = '["app/","shared"]' ]
}

@test "hub data inventory: an empty Vault listing or no root token fails instead of recording null" {
  source_plugin; _fake_identity_pod
  _hub_data_vault_kv_list() { printf ''; }
  run --separate-stderr _hub_data_inventory "$TEST_ROOT"; [ "$status" -ne 0 ]; [[ "$stderr" == *"returned no paths"* ]]; [ ! -e "$TEST_ROOT/inventory.json" ]
  _hub_data_vault_kv_list() { printf '["app/"]'; }; _hub_data_inventory_token() { return 1; }
  run --separate-stderr _hub_data_inventory "$TEST_ROOT"; [ "$status" -ne 0 ]; [ ! -e "$TEST_ROOT/inventory.json" ]
}

@test "hub data vault: an inventory without Vault paths fails before any Vault call" {
  source_plugin; printf '%s\n' '{"vault_paths":null}' > "$TEST_ROOT/inventory.json"
  run --separate-stderr hub_data_verify_vault_paths secrets vault "$TEST_ROOT/inventory.json"; [ "$status" -ne 0 ]
  [[ "$stderr" == *"records no Vault paths"* ]]; [ "$(wc -c < "$VLOG")" -eq 0 ]
}

@test "hub data vault: a recorded path missing from the restored Vault fails and names it" {
  source_plugin; export DR_TEST_SHARD=SHARD-SENTINEL DR_TEST_KV_LIST='["shared"]'
  _secret_load_data() { [[ "$2" == *:count ]] && printf 1 || printf '%s\n' "$DR_TEST_SHARD"; }
  printf '%s\n' '{"vault_paths":["app/","shared"]}' > "$TEST_ROOT/inventory.json"
  run --separate-stderr hub_data_verify_vault_paths secrets vault "$TEST_ROOT/inventory.json"; [ "$status" -ne 0 ]
  [[ "$stderr" == *"missing after restore: secret/app/"* ]]; grep -q 'token revoke -self' "$VLOG"
}

@test "hub data vault: an empty root token fails before listing" {
  source_plugin; printf '%s\n' '{"vault_paths":["app/"]}' > "$TEST_ROOT/inventory.json"; _hub_data_generate_root() { printf ''; }
  run --separate-stderr hub_data_verify_vault_paths secrets vault "$TEST_ROOT/inventory.json"; [ "$status" -ne 0 ]
  [[ "$stderr" == *"could not generate a Vault root token"* ]]; [ "$(grep -c 'kv list' "$VLOG" || true)" -eq 0 ]
}

@test "hub data export: an inventory failure stops the export before anything is pushed" {
  make_fixture; source_plugin; printf recipient > "$TEST_ROOT/recipient"; export K3DM_HUB_DATA_AGE_RECIPIENT="$TEST_ROOT/recipient" K3DM_HUB_DATA_TIMESTAMP=20261009T120000Z
  _hub_data_inventory() { return 1; }
  run hub_data_export; [ "$status" -ne 0 ]
  [[ "$output" == *"could not record the inventory"* ]]
  [ "$(grep -c '^git commit\|^git push' "$CALL_LOG" || true)" -eq 0 ]
}

@test "1 inventory uses Kubernetes login JWT on stdin only" {
  source_plugin; run _hub_data_inventory "$TEST_ROOT"; [ "$status" -eq 0 ]
  [ "$(grep -c JWT-SENTINEL "$VLOG" || true)" -eq 0 ]; grep -q JWT-SENTINEL "$STDIN_LOG"; grep -q 'auth/kubernetes/login' "$VLOG"; grep -q 'jwt=-' "$VLOG"
}

@test "2 export never loads DR shards or generate-root" {
  make_fixture; source_plugin; printf recipient > "$TEST_ROOT/recipient"; export K3DM_HUB_DATA_AGE_RECIPIENT="$TEST_ROOT/recipient"
  _hub_data_inventory() { printf '%s\n' '{"vault_paths":["secret/app"],"keycloak_realm_user_count":3,"ldap_entry_count":2}' > "$1/inventory.json"; }
  _hub_data_remote_verify() { :; }; run hub_data_export; [ "$status" -eq 0 ]; ! grep -q 'generate-root\|k3dm-vault-unseal-dr' "$VLOG" "$CALL_LOG"
}

@test "3 empty login fails with setup guidance and pushes nothing" {
  make_fixture; source_plugin; printf recipient > "$TEST_ROOT/recipient"; export K3DM_HUB_DATA_AGE_RECIPIENT="$TEST_ROOT/recipient"
  _hub_data_inventory_token() { _err '[hub-data] Vault login as hub-data-export failed; run make hub-data-export-setup'; return 1; }
  run hub_data_export; [ "$status" -ne 0 ]; [[ "$output" == *make\ hub-data-export-setup* ]]; ! grep -q 'git commit\|git push' "$CALL_LOG"
}

@test "4 missing pinned context fails before docker or git clone" {
  source_plugin; export K3DM_HUB_DATA_CONTEXT=missing; _kubectl() { [[ "$1" == config ]] && return 1; kubectl "$@"; }
  printf recipient > "$TEST_ROOT/recipient"; export K3DM_HUB_DATA_AGE_RECIPIENT="$TEST_ROOT/recipient"
  run hub_data_export; [ "$status" -ne 0 ]; [[ "$output" == *'hub context missing not found'* ]]; ! grep -q 'docker\|git clone' "$CALL_LOG"
}

@test "5 prune keeps recent exports and the last passing export" {
  make_prune_fixture 20261009T120000Z 20261007T120000Z 20261004T120000Z 20261002T120000Z 20260928T120000Z
  source_plugin; export DR_TEST_RESULT_EXPORT=20261002T120000Z; run hub_data_prune; [ "$status" -eq 0 ]; [[ "$output" == *'keep: 20261009T120000Z'* ]]; [[ "$output" == *'keep: 20261007T120000Z'* ]]; [[ "$output" == *'keep: 20261002T120000Z'* ]]; [[ "$output" == *'prune: 20261004T120000Z'* ]]; [[ "$output" == *'prune: 20260928T120000Z'* ]]
}

@test "6 prune keeps the newest when all exports are old" {
  make_prune_fixture 20261004T120000Z 20261002T120000Z; source_plugin; export K3DM_HUB_DATA_RETAIN_DAYS=1
  run hub_data_prune; [ "$status" -eq 0 ]; [[ "$output" == *'keep: 20261004T120000Z'* ]]; [[ "$output" == *'prune: 20261002T120000Z'* ]]
}

@test "7 results fetch failure is nonzero and does not push" {
  make_prune_fixture 20261009T120000Z; source_plugin; export DR_TEST_FETCH_FAIL=1
  run hub_data_prune; [ "$status" -ne 0 ]; [[ "$output" == *'cannot read drill results'* ]]; [ ! -s "$TEST_ROOT/push.log" ]
}

@test "8 prune force-pushes snapshots only" {
  make_prune_fixture 20261004T120000Z 20261002T120000Z; source_plugin; export K3DM_HUB_DATA_RETAIN_DAYS=1
  run hub_data_prune; [ "$status" -eq 0 ]; grep -q -- '--force-with-lease=snapshots:' "$TEST_ROOT/push.log"; grep -q 'refs/heads/snapshots' "$TEST_ROOT/push.log"; ! grep -q 'refs/heads/results' "$TEST_ROOT/push.log"
}

@test "8b export passes its existing clone to prune" {
  make_fixture; source_plugin; printf recipient > "$TEST_ROOT/recipient"; export K3DM_HUB_DATA_AGE_RECIPIENT="$TEST_ROOT/recipient"; _hub_data_inventory() { printf '%s\n' '{"vault_paths":["secret/app"],"keycloak_realm_user_count":3,"ldap_entry_count":2}' > "$1/inventory.json"; }; _hub_data_remote_verify() { :; }
  run hub_data_export; [ "$status" -eq 0 ]; [ "$(grep -c 'git .*clone' "$CALL_LOG")" -eq 1 ]
}

@test "9a manifest detects edited, extra, missing, and bad-age files" {
  source_plugin; local dir="$TEST_ROOT/export"; make_export_dir "$dir"; printf changed > "$dir/pv-pvc.yaml"; run _hub_data_verify_export "$dir"; [ "$status" -ne 0 ]
  make_export_dir "$dir"; printf 'age-encryption.org/v1\nextra\n' > "$dir/extra.age"; run _hub_data_verify_export "$dir"; [ "$status" -ne 0 ]
  make_export_dir "$dir"; sed -i.bak '/inventory.json/d' "$dir/SHA256SUMS"; run _hub_data_verify_export "$dir"; [ "$status" -ne 0 ]
  make_export_dir "$dir"; printf not-age > "$dir/x.tar.age"; (cd "$dir" && sha256sum x.tar.age pv-pvc.yaml inventory.json > SHA256SUMS); run _hub_data_verify_export "$dir"; [ "$status" -ne 0 ]
}

@test "9b remote mismatch writes no success metric and does not prune" {
  source_plugin; export DR_TEST_REMOTE_MISMATCH=1; _hub_data_verify_export() { :; }; run _hub_data_remote_verify "$TEST_ROOT/repo" 20261009T120000Z; [ "$status" -ne 0 ]; [[ "$output" == *'ls-remote mismatch'* ]]
}

@test "9c prune refuses a kept export with a bad manifest" {
  make_prune_fixture 20261009T120000Z; printf bad > "$TEST_ROOT/fixture/snapshots/20261009T120000Z/pv-pvc.yaml"; source_plugin
  run hub_data_prune; [ "$status" -ne 0 ]; [[ "$output" == *'cannot verify kept export'* ]]; [ ! -s "$TEST_ROOT/push.log" ]
}

@test "9 dry-run prune prints keep and prune without pushing" {
  make_prune_fixture 20261004T120000Z 20261002T120000Z; source_plugin; export K3DM_HUB_DATA_RETAIN_DAYS=1 K3DM_HUB_DATA_PRUNE_DRY_RUN=1
  run hub_data_prune; [ "$status" -eq 0 ]; [[ "$output" == *'keep:'* && "$output" == *'prune:'* ]]; [ ! -e "$TEST_ROOT/prune-state/last-kept" ]; [ ! -s "$TEST_ROOT/push.log" ]
}

@test "11 rendered plist has scheduled command and calendar" {
  run sed -e "s|{{K3D_MANAGER_PATH}}|$PWD/scripts/k3d-manager|g" -e "s|{{HOME}}|$HOME|g" scripts/etc/launchd/com.k3d-manager.hub-data-export.plist.tmpl
  [ "$status" -eq 0 ]; [[ "$output" == *hub_data_export_scheduled* && "$output" == *'<integer>3</integer>'* && "$output" == *'<integer>30</integer>'* ]]; ! [[ "$output" == *'{{'* ]]
}

@test "12 alert manifest contains all three export alerts" {
  grep -q 'HubDataExportFailed' "$PWD/scripts/etc/argocd/platform-ops/prometheusrule.yaml"; grep -q 'HubDataExportStale' "$PWD/scripts/etc/argocd/platform-ops/prometheusrule.yaml"; grep -q 'HubDataExportNeverRan' "$PWD/scripts/etc/argocd/platform-ops/prometheusrule.yaml"
}

@test "13 legacy export verifies and one-sided metadata listing fails" {
  source_plugin; local dir="$TEST_ROOT/export"; make_export_dir "$dir" legacy; run _hub_data_verify_export "$dir"; [ "$status" -eq 0 ]; [[ "$output" == *'legacy export'* ]]
  (cd "$dir" && sha256sum x.tar.age inventory.json > SHA256SUMS); run _hub_data_verify_export "$dir"; [ "$status" -ne 0 ]
}

@test "14 split export first part must have an age header" {
  source_plugin; local dir="$TEST_ROOT/export"; mkdir -p "$dir"; printf bad > "$dir/x.tar.age.part-aa"; printf 'age-encryption.org/v1\nrest' > "$dir/x.tar.age.part-ab"; printf '{}\n' > "$dir/inventory.json"; printf metadata > "$dir/pv-pvc.yaml"; (cd "$dir" && sha256sum x.tar.age.part-aa x.tar.age.part-ab pv-pvc.yaml inventory.json > SHA256SUMS)
  run _hub_data_verify_export "$dir"; [ "$status" -ne 0 ]
}

@test "15 unparseable export timestamp stops prune without push" {
  make_prune_fixture 20261009T120000Z 2026BADT120000Z; source_plugin; run hub_data_prune; [ "$status" -ne 0 ]; [[ "$output" == *'cannot parse export timestamp 2026BADT120000Z'* ]]; [ ! -s "$TEST_ROOT/push.log" ]
}

@test "10 scheduled run posts newline-delimited metrics and kept count" {
  source_plugin; export K3DM_HUB_DATA_DIR="$TEST_ROOT/scheduled" K3DM_HUB_DATA_PUSHGATEWAY_URL=http://push; mkdir -p "$K3DM_HUB_DATA_DIR"; hub_data_export() { printf 7 > "$K3DM_HUB_DATA_DIR/last-kept"; printf 123 > "$K3DM_HUB_DATA_DIR/last-bytes"; return 0; }; run hub_data_export_scheduled; [ "$status" -eq 0 ]; [ "$(wc -l < "$TEST_ROOT/metrics-body")" -eq 5 ]; tail -c 1 "$TEST_ROOT/metrics-body" | od -An -t x1 | grep -q 0a; grep -q 'exports_kept 7' "$TEST_ROOT/metrics-body"
  [ ! -e "$K3DM_HUB_DATA_DIR/export.lock" ]
  hub_data_export() { return 1; }; run hub_data_export_scheduled; [ "$status" -ne 0 ]; [ ! -e "$K3DM_HUB_DATA_DIR/export.lock" ]
  run hub_data_export_scheduled; [ "$status" -ne 0 ]; grep -q 'last_run_success 0' "$TEST_ROOT/metrics-body"
}

@test "19 a lock left by a dead run is taken over; a live owner's lock is not" {
  source_plugin; export K3DM_HUB_DATA_DIR="$TEST_ROOT/stale" K3DM_HUB_DATA_PUSHGATEWAY_URL=http://push; mkdir -p "$K3DM_HUB_DATA_DIR/export.lock"
  ( exit 0 ) & dead=$!; wait "$dead"; printf '%s\n' "$dead" > "$K3DM_HUB_DATA_DIR/export.lock/pid"
  hub_data_export() { printf ran > "$TEST_ROOT/export-ran"; printf 1 > "$K3DM_HUB_DATA_DIR/last-kept"; return 0; }
  run hub_data_export_scheduled; [ "$status" -eq 0 ]; [ -e "$TEST_ROOT/export-ran" ]; [[ "$output" == *'removing stale export lock'* ]]; [ ! -e "$K3DM_HUB_DATA_DIR/export.lock" ]
  rm -f "$TEST_ROOT/export-ran"; mkdir -p "$K3DM_HUB_DATA_DIR/export.lock"; printf '%s\n' "$$" > "$K3DM_HUB_DATA_DIR/export.lock/pid"
  run hub_data_export_scheduled; [ "$status" -eq 0 ]; [ ! -e "$TEST_ROOT/export-ran" ]; [ -d "$K3DM_HUB_DATA_DIR/export.lock" ]
}

@test "17 setup self-test passes and revokes its single token" {
  source_plugin; _vault_login() { :; }; _vault_exec() { :; }; _hub_data_vault_revoke() { printf 'token revoke -self\n' >> "$VLOG"; }; run hub_data_export_setup; [ "$status" -eq 0 ]; grep -q 'token revoke -self' "$VLOG"; [ "$(grep -c 'auth/kubernetes/login' "$VLOG")" -eq 1 ]
  declare -gA _VAULT_SESSION_TOKENS=(); _vault_login() { _VAULT_SESSION_TOKENS[secrets/vault]=admin; }
  _hub_data_vault_kv_list() { [[ -z "${_VAULT_SESSION_TOKENS[secrets/vault]:-}" ]] || { printf 'admin session still set\n' >&2; return 1; }; printf '["app/"]'; }
  run hub_data_export_setup; [ "$status" -eq 0 ]
}

@test "17b setup binds the role to the API server audience (required from Vault 1.21)" {
  source_plugin; _vault_login() { :; }; _vault_exec() { printf '%s\n' "$2" >> "$VLOG"; }; _hub_data_vault_revoke() { :; }
  run hub_data_export_setup; [ "$status" -eq 0 ]
  grep -q 'auth/kubernetes/role/hub-data-inventory .*audience=https://kubernetes.default.svc.cluster.local' "$VLOG"
  K8S_TOKEN_AUDIENCE='x;rm' run hub_data_export_setup; [ "$status" -ne 0 ]
}

@test "18 lock semantics distinguish manual, scheduled, and delegated ownership" {
  source_plugin; export K3DM_HUB_DATA_DIR="$TEST_ROOT/lock-state"; mkdir -p "$K3DM_HUB_DATA_DIR/export.lock"; printf '%s\n' "$$" > "$K3DM_HUB_DATA_DIR/export.lock/pid"
  run hub_data_export; [ "$status" -eq 1 ]; [[ "$output" == *'another export is running'* ]]
  run hub_data_export_scheduled; [ "$status" -eq 0 ]; [ ! -e "$TEST_ROOT/metrics-body" ]
  [ "$(cat "$K3DM_HUB_DATA_DIR/export.lock/pid")" = "$$" ]
  rm -rf "$K3DM_HUB_DATA_DIR/export.lock"; mkdir -p "$K3DM_HUB_DATA_DIR/export.lock"; printf '%s\n' "$$" > "$K3DM_HUB_DATA_DIR/export.lock/pid"
  make_fixture; printf recipient > "$TEST_ROOT/recipient"; export K3DM_HUB_DATA_AGE_RECIPIENT="$TEST_ROOT/recipient"; _hub_data_inventory() { return 1; }
  HUB_DATA_LOCK_HELD=1 run hub_data_export; [ "$status" -ne 0 ]
  [ -d "$K3DM_HUB_DATA_DIR/export.lock" ]; [ "$(cat "$K3DM_HUB_DATA_DIR/export.lock/pid")" = "$$" ]
}
