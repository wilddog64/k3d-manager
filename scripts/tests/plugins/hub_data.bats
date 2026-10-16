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
  *'kv list -format=json secret/') printf '%s' "${DR_TEST_KV_LIST:-[\"app/\",\"shared\"]}" ;;
  *'kv list'*) printf '["leaf"]' ;;
  *'kv metadata get'*) printf '{"data":{"current_version":1}}' ;;
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
elif [[ "$args" == *"apply"* && "$args" == *"-f -"* ]]; then cat > "$TEST_ROOT/applied-$RANDOM.yaml"
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

freeze_clock() {
  export DR_TEST_NOW="$1"
  date() { if [[ "$*" == '-u +%s' ]]; then printf '%s\n' "$DR_TEST_NOW"; else command date "$@"; fi; }
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
  _fake_vault_tree
  _hub_data_inventory_images() { printf '%s\n' '{"secrets/vault-0":"vault:1.0","identity/postgres-keycloak":"postgres:1.0","identity/openldap-0":"openldap:1.0"}'; }
  _hub_data_vault_revoke() { :; }
}

_fake_vault_tree() {
  _hub_data_vault_kv_list() {
    printf '%s\n' "$4" >> "$TEST_ROOT/kv-list.log"
    case "$4" in
      secret/) printf '["app/","shared"]' ;;
      secret/app/) printf '["db","deep/"]' ;;
      secret/app/deep/) printf '["key"]' ;;
      *) return 1 ;;
    esac
  }
  _hub_data_vault_kv_metadata() { printf '{"data":{"current_version":1}}'; }
}

@test "hub data inventory: walks nested Vault folders by their full path" {
  source_plugin; _fake_identity_pod
  run _hub_data_inventory "$TEST_ROOT"; [ "$status" -eq 0 ]
  [ "$(jq -c '.vault_keys | keys' "$TEST_ROOT/inventory.json")" = '["app/db","app/deep/key","shared"]' ]
  [ "$(cat "$TEST_ROOT/kv-list.log")" = "$(printf 'secret/\nsecret/\nsecret/app/\nsecret/app/deep/')" ]
}

@test "hub data inventory: a failed nested list names the path instead of failing silently" {
  source_plugin; _fake_identity_pod
  _hub_data_vault_kv_list() { [[ "$4" == secret/ ]] && printf '["app/"]' || return 1; }
  run --separate-stderr _hub_data_inventory "$TEST_ROOT"; [ "$status" -ne 0 ]
  [[ "$stderr" == *"vault kv list secret/app/ failed"* ]]; [ ! -e "$TEST_ROOT/inventory.json" ]
}

@test "hub data inventory: a zero LDAP count names LDAP" {
  source_plugin; _fake_identity_pod
  _hub_data_ldap_entry_count() { printf 0; }
  run --separate-stderr _hub_data_inventory "$TEST_ROOT"; [ "$status" -ne 0 ]
  [[ "$stderr" == *"LDAP entry count is not a positive number"* ]]
}

@test "hub data export setup: the policy grants list below secret/metadata so nested folders can be walked" {
  source_plugin; _vault_login() { :; }; _vault_exec() { :; }; _hub_data_vault_revoke() { :; }
  eval "$(declare -f _vault_exec_stream | sed '1s/_vault_exec_stream/_orig_vault_exec_stream/')"
  _vault_exec_stream() { if [[ "$*" == *"policy write"* ]]; then cat >> "$TEST_ROOT/policy.hcl"; else _orig_vault_exec_stream "$@"; fi; }
  run hub_data_export_setup; [ "$status" -eq 0 ]
  grep -q 'path "secret/metadata/\*" { capabilities = \["read", "list"\] }' "$TEST_ROOT/policy.hcl"
  _hub_data_vault_kv_list() { [[ "$4" == secret/ ]] && printf '["app/"]' || return 1; }
  run --separate-stderr hub_data_export_setup; [ "$status" -ne 0 ]
  [[ "$stderr" == *"vault kv list secret/app/ failed"* ]]
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
  source_plugin; _hub_data_vault_kv_metadata() { printf '{"data":{"current_version":1}}'; }; run _hub_data_inventory "$TEST_ROOT"; [ "$status" -eq 0 ]
  [ "$(grep -c JWT-SENTINEL "$VLOG" || true)" -eq 0 ]; grep -q JWT-SENTINEL "$STDIN_LOG"; grep -q 'auth/kubernetes/login' "$VLOG"; grep -q 'jwt=-' "$VLOG"
}

@test "2 export never loads DR shards or generate-root" {
  make_fixture; source_plugin; printf recipient > "$TEST_ROOT/recipient"; export K3DM_HUB_DATA_AGE_RECIPIENT="$TEST_ROOT/recipient"
  _hub_data_inventory() { printf '%s\n' '{"vault_paths":["secret/app"],"keycloak_realm_user_count":3,"ldap_entry_count":2}' > "$1/inventory.json"; }
  _hub_data_remote_verify() { :; }; run hub_data_export; [ "$status" -eq 0 ]; run grep -q 'generate-root\|k3dm-vault-unseal-dr' "$VLOG" "$CALL_LOG"; [ "$status" -eq 1 ]
}

@test "3 empty login fails with setup guidance and pushes nothing" {
  make_fixture; source_plugin; printf recipient > "$TEST_ROOT/recipient"; export K3DM_HUB_DATA_AGE_RECIPIENT="$TEST_ROOT/recipient"
  _hub_data_inventory_token() { _err '[hub-data] Vault login as hub-data-export failed; run make hub-data-export-setup'; return 1; }
  run hub_data_export; [ "$status" -ne 0 ]; [[ "$output" == *make\ hub-data-export-setup* ]]; run grep -q 'git commit\|git push' "$CALL_LOG"; [ "$status" -eq 1 ]
}

@test "4 missing pinned context fails before docker or git clone" {
  source_plugin; export K3DM_HUB_DATA_CONTEXT=missing; _kubectl() { [[ "$1" == config ]] && return 1; kubectl "$@"; }
  printf recipient > "$TEST_ROOT/recipient"; export K3DM_HUB_DATA_AGE_RECIPIENT="$TEST_ROOT/recipient"
  run hub_data_export; [ "$status" -ne 0 ]; [[ "$output" == *'hub context missing not found'* ]]; run grep -q 'docker\|git clone' "$CALL_LOG"; [ "$status" -eq 1 ]
}

@test "5 prune keeps recent exports and the last passing export" {
  make_prune_fixture 20261009T120000Z 20261007T120000Z 20261004T120000Z 20261002T120000Z 20260928T120000Z
  source_plugin; freeze_clock 1791590400; export DR_TEST_RESULT_EXPORT=20261002T120000Z
  run hub_data_prune
  printf 'status=%s\n%s\n' "$status" "$output"
  [ "$status" -eq 0 ]
  [[ "$output" == *'keep: 20261009T120000Z'* ]]
  [[ "$output" == *'keep: 20261007T120000Z'* ]]
  [[ "$output" == *'keep: 20261002T120000Z'* ]]
  [[ "$output" == *'prune: 20261004T120000Z'* ]]
  [[ "$output" == *'prune: 20260928T120000Z'* ]]
}

@test "5b prune retention boundary follows the clock, not the calendar" {
  make_prune_fixture 20261009T120000Z 20261007T120000Z
  source_plugin; freeze_clock 1791806400
  run hub_data_prune
  printf 'status=%s\n%s\n' "$status" "$output"
  [ "$status" -eq 0 ]
  [[ "$output" == *'keep: 20261007T120000Z'* ]]
  freeze_clock 1791806401
  run hub_data_prune
  printf 'status=%s\n%s\n' "$status" "$output"
  [ "$status" -eq 0 ]
  [[ "$output" == *'prune: 20261007T120000Z'* ]]
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
  run hub_data_prune; [ "$status" -eq 0 ]; grep -q -- '--force-with-lease=snapshots:' "$TEST_ROOT/push.log"; grep -q 'refs/heads/snapshots' "$TEST_ROOT/push.log"; run grep -q 'refs/heads/results' "$TEST_ROOT/push.log"; [ "$status" -eq 1 ]
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
  [ "$status" -eq 0 ]; [[ "$output" == *hub_data_export_scheduled* && "$output" == *'<integer>3</integer>'* && "$output" == *'<integer>30</integer>'* ]]; [[ "$output" != *'{{'* ]]
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
  _hub_data_vault_kv_list() { [[ -z "${_VAULT_SESSION_TOKENS[secrets/vault]:-}" ]] || { printf 'admin session still set\n' >&2; return 1; }; [[ "$4" == secret/ ]] && printf '["app/"]' || printf '["leaf"]'; }
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

@test "hub-data: repo file defaults resolve from the plugin, not the caller's directory" {
  local plugin="$PLUGINS_DIR/hub_data.sh" root
  root="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
  run env -u REPO_ROOT -u K3DM_HUB_DATA_AGE_RECIPIENT PLUGINS_DIR="$PLUGINS_DIR" SCRIPT_DIR="$root/scripts" bash -c 'cd / && source "$1" && printf "%s\n" "$K3DM_HUB_DATA_AGE_RECIPIENT"' _ "$plugin"
  [ "$status" -eq 0 ]
  [ "$output" = "$root/scripts/etc/dr/age-recipient.txt" ]
  [ -r "$output" ]
  run grep -c 'REPO_ROOT:-\.' "$plugin"
  [ "$output" = "0" ]
}

@test "recover B4-13: approval is typed and mismatches are refused" {
  source_plugin
  export K3DM_HUB_DATA_TEST_TTY=1 K3DM_HUB_DATA_TTY_DEVICE="$TEST_ROOT/tty"
  printf '%s\n' 20261010T000000Z > "$K3DM_HUB_DATA_TTY_DEVICE"
  run _hub_data_recover_approval 20261011T120000Z
  [ "$status" -eq 2 ]
  [[ "$output" == *'did not match'* ]]
  printf '%s\n' 20261011T120000Z > "$K3DM_HUB_DATA_TTY_DEVICE"
  run _hub_data_recover_approval 20261011T120000Z
  [ "$status" -eq 0 ]
}

@test "recover B4-13a: target validation checks the local serverlb and server-0" {
  source_plugin; _kubectl() { [[ "$*" == *'config view'* ]] && printf 'https://127.0.0.1:6443'; }
  docker() { printf 'k3d-test-serverlb 0.0.0.0:6443->6443/tcp\nk3d-test-server-0\n'; }
  run _hub_data_validate_target ctx test; [ "$status" -ne 0 ]
}

@test "recover B4-13b: destructive checkpoints require explicit redo on resume" {
  source_plugin
  local steps="$TEST_ROOT/steps.jsonl"
  printf '%s\n' '{"step":6,"started":"now"}' > "$steps"
  _hub_data_argocd_assert_paused() { :; }
  _hub_data_repoint_vault() { printf 'repoint\n' >> "$CALL_LOG"; }
  run _hub_data_recover_step6 "$steps" ctx "$TEST_ROOT/run"
  [ "$status" -ne 0 ]
  [[ "$output" == *'REDO_STEP=6'* ]]
  run grep -q repoint "$CALL_LOG"
  [ "$status" -eq 1 ]
  REDO_STEP=6 run _hub_data_recover_step6 "$steps" ctx "$TEST_ROOT/run"
  [ "$status" -eq 0 ]
  grep -q repoint "$CALL_LOG"
}

@test "recover B4-13c: compatibility requires format 2 and all claims" {
  source_plugin; local dir="$TEST_ROOT/compat"; mkdir -p "$dir"; printf '%s\n' '{"format":1}' > "$dir/inventory.json"; printf 'name: data-vault-0\nname: postgres-keycloak-pvc\nname: data-openldap-0\n' > "$dir/pv-pvc.yaml"
  run _hub_data_check_compatibility "$dir"; [ "$status" -ne 0 ]
}

@test "recover B4-13d: verification uses metadata proof fields" {
  source_plugin; printf '%s\n' '{"vault_paths":["app/"],"vault_keys":{"app":{"current_version":2}}}' > "$TEST_ROOT/inventory.json"; _hub_data_generate_root() { printf root; }; _hub_data_vault_kv_list() { printf '["app/"]'; }; _hub_data_vault_kv_metadata() { printf '{"data":{"current_version":1}}'; }; _hub_data_vault_revoke() { :; }
  run hub_data_verify_vault_paths secrets vault "$TEST_ROOT/inventory.json"; [ "$status" -ne 0 ]; run grep -q 'vault kv get' "$VLOG"; [ "$status" -eq 1 ]
}

@test "recover B4-13e: drill delegates verification to hub_data" {
  source_plugin
  run grep -Eq '^_dr_drill_v[1-5][[:space:]]*\(' "$PWD/bin/dr-drill"
  [ "$status" -eq 1 ]
  eval "$(sed -n '/^_dr_drill_verify_keycloak()/,/^}/p' "$PWD/bin/dr-drill")"
  _dr_drill_inventory() { printf '%s\n' inventory; }
  DR_DRILL_CONTEXT=ctx
  hub_data_verify_keycloak() { printf called >> "$CALL_LOG"; }
  _dr_drill_verify_keycloak
  grep -q called "$CALL_LOG"
}

@test "recover B4-15: hub mode skips the drill postgres manifest" {
  make_fixture; source_plugin
  export DR_DRILL_CONTEXT=ctx DR_DRILL_CLUSTER=test DR_DRILL_RESTORE_STAGE="$TEST_ROOT/stage" HUB_DATA_RESTORE_TARGET=hub
  _hub_data_verify_export() { :; }
  _hub_data_prepare_claim() { :; }
  _hub_data_copy_claim() { :; }
  _hub_data_scale() { :; }
  _hub_data_apply_keycloak() { printf applied >> "$CALL_LOG"; return 1; }
  run hub_data_restore
  [ "$status" -eq 0 ]
  run grep -q applied "$CALL_LOG"
  [ "$status" -eq 1 ]
  run grep -q 'scripts/etc/dr/postgres-keycloak.yaml' "$CALL_LOG"
  [ "$status" -eq 1 ]
}

@test "recover B4-17: ArgoCD resume patches the child before the parent with the recorded values" {
  source_plugin; mkdir -p "$TEST_ROOT/run"
  printf '%s' '{"prune":true}' > "$TEST_ROOT/run/$K3DM_HUB_DATA_ARGOCD_APP.automated"
  printf '%s' '{"selfHeal":true}' > "$TEST_ROOT/run/$K3DM_HUB_DATA_ARGOCD_PARENT.automated"
  _kubectl() { printf '%s\n' "$*" >> "$CALL_LOG"; return 0; }
  run _hub_data_argocd_resume ctx "$TEST_ROOT/run"
  [ "$status" -eq 0 ]
  mapfile -t calls < "$CALL_LOG"
  [ "${#calls[@]}" -eq 2 ]
  [[ "${calls[0]}" == *"patch application $K3DM_HUB_DATA_ARGOCD_APP "*'"automated":{"prune":true}'* ]]
  [[ "${calls[1]}" == *"patch application $K3DM_HUB_DATA_ARGOCD_PARENT "*'"automated":{"selfHeal":true}'* ]]
  : > "$CALL_LOG"
  : > "$TEST_ROOT/run/$K3DM_HUB_DATA_ARGOCD_APP.automated"
  rm -f "$TEST_ROOT/run/$K3DM_HUB_DATA_ARGOCD_PARENT.automated"
  run _hub_data_argocd_resume ctx "$TEST_ROOT/run"
  [ "$status" -eq 0 ]
  [ ! -s "$CALL_LOG" ]
}

@test "recover K2: a drill target skips the Keycloak and ESO refresh; the hub runs it" {
  source_plugin; _kubectl() { printf '%s\n' "$*" >> "$CALL_LOG"; }
  run --separate-stderr _hub_data_refresh_dependents k3d-dr-drill; [ "$status" -eq 0 ]
  [ "$(wc -c < "$CALL_LOG")" -eq 0 ]; [[ "$stderr" == *"no Keycloak or ESO to refresh"* ]]
  K3DM_HUB_DATA_RECOVER_ALLOW_DRILL=1 run _hub_data_refresh_dependents other-ctx; [ "$status" -eq 0 ]; [ "$(wc -c < "$CALL_LOG")" -eq 0 ]
  run _hub_data_refresh_dependents k3d-k3d-cluster; [ "$status" -eq 0 ]
  grep -q 'rollout restart deployment/keycloak' "$CALL_LOG"; grep -q 'annotate externalsecret --all' "$CALL_LOG"
}

@test "recover D1: credential guard security shim survives its installer function" {
  source_plugin; local run_dir="$TEST_ROOT/guard"; mkdir -p "$run_dir"
  cat > "$TEST_ROOT/real-security" <<'STUB'
#!/usr/bin/env bash
printf 'real-security %s\n' "$*" >> "$CALL_LOG"
STUB
  chmod +x "$TEST_ROOT/real-security"
  export DR_SECURITY_REAL="$TEST_ROOT/real-security" DR_DRILL_CREDENTIAL_POLICY=audit
  install_guard_and_return() { _hub_data_install_credential_guard "$run_dir" ctx; }
  install_guard_and_return; set -u
  run --separate-stderr security show-keychain-info
  set +u
  [ "$status" -eq 0 ]
  [[ "$stderr" != *"unbound variable"* ]]
  grep -q 'real-security show-keychain-info' "$CALL_LOG"
}

@test "recover D2: refresh force-syncs, waits, discovers Keycloak, then restarts dependents" {
  source_plugin; local calls=()
  _kubectl() {
    calls+=("$*")
    [[ "$*" == *"get deployment/keycloak"* ]] && return 0
    return 0
  }
  K3DM_HUB_DATA_KEYCLOAK_POLL_S=0 _hub_data_refresh_dependents ctx
  [[ "${calls[0]}" == *"annotate externalsecret --all"* ]]
  [[ "${calls[1]}" == *"wait externalsecret --all --for=condition=Ready"* ]]
  [[ "${calls[2]}" == *"get deployment/keycloak"* ]]
  [[ "${calls[3]}" == *"rollout restart deployment/keycloak"* ]]
  [[ "${calls[4]}" == *"rollout restart deployment/kube-prometheus-stack-grafana"* ]]
  [[ "${calls[5]}" == *"rollout restart deployment/argocd-server"* ]]
}

@test "recover D2: waits for ArgoCD to create Keycloak before restarting it" {
  source_plugin; local get_count=0
  _kubectl() {
    if [[ "$*" == *"get deployment/keycloak"* ]]; then
      get_count=$((get_count + 1)); (( get_count >= 3 )) || return 1
    fi
  }
  K3DM_HUB_DATA_KEYCLOAK_POLL_S=0 _hub_data_refresh_dependents ctx
  [ "$get_count" -eq 3 ]
}

@test "recover D2: missing Keycloak reports the bounded ArgoCD timeout" {
  source_plugin
  _kubectl() { [[ "$*" == *"get deployment/keycloak"* ]] && return 1; return 0; }
  export K3DM_HUB_DATA_KEYCLOAK_WAIT_S=0 K3DM_HUB_DATA_KEYCLOAK_POLL_S=0
  run --separate-stderr _hub_data_refresh_dependents ctx
  unset K3DM_HUB_DATA_KEYCLOAK_WAIT_S K3DM_HUB_DATA_KEYCLOAK_POLL_S
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"not created by ArgoCD"* ]]
}

@test "recover D2: Grafana restart failure is a warning" {
  source_plugin
  _kubectl() {
    [[ "$*" == *"kube-prometheus-stack-grafana"* ]] && return 1
    [[ "$*" == *"get deployment/keycloak"* ]] && return 0
    return 0
  }
  run --separate-stderr _hub_data_refresh_dependents ctx
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"could not restart Grafana"* ]]
}

@test "recover D3: restored claims use server-side hub-restore field ownership" {
  make_fixture; source_plugin; _hub_data_scale() { :; }; _hub_data_target_context() { printf ctx; }
  _kubectl() {
    printf '%s\n' "$*" >> "$CALL_LOG"
    case "$*" in
      *" apply "*) cat >/dev/null ;;
      *"get pvc"*"volumeName"*) printf 'pv-data-vault-0\n' ;;
      *"get pv"*"hostname"*) printf 'node-a\n' ;;
      *"get pv"*"local.path"*) printf '/var/lib/k3s/data-vault-0\n' ;;
    esac
  }
  _hub_data_prepare_claim "$DR_TEST_REPO_FIXTURE/snapshots/20261009T120000Z" secrets data-vault-0 ignored
  run grep -F -- '--server-side --field-manager=k3dm-hub-restore -f -' "$CALL_LOG"
  [ "$status" -eq 0 ]
}

@test "recover F4: Step 9 reminds the operator to recreate the export ServiceAccount" {
  source_plugin; _hub_data_step_finished() { return 1; }; _hub_data_run_step() { :; }
  run _hub_data_recover_step9 "$TEST_ROOT/steps"
  [ "$status" -eq 0 ]
  [[ "$output" == *"make hub-data-export-setup"* ]]
}

@test "recover F5: restore-hub allows finding the unseal-key cache" {
  run awk -F '\t' '$1 == "restore-hub" && $2 == "find" && $3 == "k3d-manager-vault-unseal" && $4 == "secrets/vault:*" { found=1 } END { exit !found }' scripts/etc/dr/credential-allowlist.tsv
  [ "$status" -eq 0 ]
}

@test "recover K3: a missing ArgoCD Application is skipped, not a fatal kubectl exit" {
  source_plugin; mkdir -p "$TEST_ROOT/run"
  _kubectl() { [[ "$1" == --no-exit ]] && return 1; printf 'fatal kubectl exit\n' >&2; exit 1; }
  run --separate-stderr _hub_data_argocd_pause k3d-dr-drill "$TEST_ROOT/run"; [ "$status" -eq 0 ]
  [[ "$stderr" != *"fatal kubectl exit"* ]]
}

@test "recover K4: the Keychain age identity is drill-only and never prompts" {
  source_plugin; local tty="$TEST_ROOT/tty"; printf 'AGE-SECRET-KEY-1TYPED\n' > "$tty"; export K3DM_HUB_DATA_TTY_DEVICE="$tty"
  _secret_load_data() { printf '%s\n' "$*" >> "$CALL_LOG"; printf 'AGE-SECRET-KEY-1KEYCHAIN\r'; }
  _hub_data_run_step() { :; }
  K3DM_HUB_DATA_AGE_IDENTITY_FROM_KEYCHAIN=1 run --separate-stderr _hub_data_recover_step2 "$TEST_ROOT/steps"; [ "$status" -eq 1 ]
  [[ "$stderr" == *"drill rehearsals only"* ]]; [ "$(wc -c < "$CALL_LOG")" -eq 0 ]
  export K3DM_HUB_DATA_AGE_IDENTITY_FROM_KEYCHAIN=1 K3DM_HUB_DATA_RECOVER_ALLOW_DRILL=1
  _hub_data_recover_step2 "$TEST_ROOT/steps" 2>/dev/null
  [ "$K3DM_HUB_DATA_AGE_IDENTITY" = AGE-SECRET-KEY-1KEYCHAIN ]; grep -q 'k3dm-hub-data-age identity age' "$CALL_LOG"
  unset K3DM_HUB_DATA_AGE_IDENTITY_FROM_KEYCHAIN; _hub_data_recover_step2 "$TEST_ROOT/steps" 2>/dev/null
  [ "$K3DM_HUB_DATA_AGE_IDENTITY" = AGE-SECRET-KEY-1TYPED ]
}

@test "recover K5: V5 reads pv-pvc.yaml from the recovery's export dir, and names a missing one" {
  source_plugin; unset DR_DRILL_METADATA DR_DRILL_RESTORE_STAGE
  run --separate-stderr hub_data_verify_placement "$TEST_ROOT/inventory.json" ctx; [ "$status" -eq 1 ]
  [[ "$stderr" == *"V5: no readable pv-pvc.yaml"* ]]
  mkdir -p "$TEST_ROOT/export"; : > "$TEST_ROOT/export/pv-pvc.yaml"; export K3DM_HUB_DATA_EXPORT_DIR="$TEST_ROOT/export"
  _hub_data_meta_field() { printf '%s\n' "$1" >> "$CALL_LOG"; printf agent-0; }
  _kubectl() { case "$*" in *"get pods -l"*) printf postgres-0 ;; *"get pod"*) printf k3d-dr-drill-agent-0 ;; esac; }
  _hub_recovery_logical_node() { printf agent-0; }
  run hub_data_verify_placement "$TEST_ROOT/inventory.json" ctx; [ "$status" -eq 0 ]
  [ "$(sort -u "$CALL_LOG")" = "$TEST_ROOT/export/pv-pvc.yaml" ]
}

@test "recover K6: RTO runs from approval across resumes, not from the last resume" {
  source_plugin; mkdir -p "$TEST_ROOT/run"
  printf '%s\n' "$(( $(date +%s) - 600 ))" > "$TEST_ROOT/run/approval_epoch"
  _hub_data_record_rto "$TEST_ROOT/run" 13
  [ "$(cat "$TEST_ROOT/run/rto_seconds")" -ge 600 ]; [ "$(cat "$TEST_ROOT/run/rto_seconds")" -lt 700 ]
  rm "$TEST_ROOT/run/approval_epoch"; _hub_data_record_rto "$TEST_ROOT/run" 13; [ "$(cat "$TEST_ROOT/run/rto_seconds")" -eq 13 ]
}

@test "recover K1: a drill target never caches unseal keys in the Keychain; the hub does" {
  source_plugin; _hub_data_generate_root() { printf ROOT; }; _vault_exec_stream() { :; }; _secret_load_data() { [[ "$2" == *:count ]] && printf 1 || printf SHARD; }; _vault_dr_shard_valid() { return 0; }
  _vault_cache_unseal_keys() { printf 'cache\n' >> "$CALL_LOG"; }; _hub_recovery_sync_vault_root_token() { :; }; _kubectl() { cat >/dev/null; }
  mkdir -p "$TEST_ROOT/run"
  run --separate-stderr _hub_data_repoint_vault k3d-dr-drill "$TEST_ROOT/run"; [ "$status" -eq 0 ]
  [ "$(grep -c cache "$CALL_LOG" || true)" -eq 0 ]; [ "$(cat "$TEST_ROOT/run/unseal_keys_cache")" = skipped ]; [[ "$stderr" == *"not caching unseal keys"* ]]
  K3DM_HUB_DATA_RECOVER_ALLOW_DRILL=1 run _hub_data_repoint_vault other-ctx "$TEST_ROOT/run"; [ "$status" -eq 0 ]; [ "$(grep -c cache "$CALL_LOG" || true)" -eq 0 ]
  run _hub_data_repoint_vault k3d-hub "$TEST_ROOT/run"; [ "$status" -eq 0 ]
  [ "$(grep -c cache "$CALL_LOG")" -eq 1 ]; [ "$(cat "$TEST_ROOT/run/unseal_keys_cache")" = cached ]
}

@test "recover B4-18: Vault re-point order is config, shards, vault-root, root" {
  source_plugin; _hub_data_generate_root() { printf ROOT; }; _vault_exec_stream() { printf 'config\n' >> "$CALL_LOG"; }; _secret_load_data() { [[ "$2" == *:count ]] && printf 1 || printf SHARD; }; _vault_dr_shard_valid() { return 0; }; _vault_cache_unseal_keys() { printf 'shards\n' >> "$CALL_LOG"; }; _hub_recovery_sync_vault_root_token() { printf 'root\n' >> "$CALL_LOG"; }; _kubectl() { cat >/dev/null; printf 'vault-root\n' >> "$CALL_LOG"; }
  run _hub_data_repoint_vault ctx; [ "$status" -eq 0 ]; mapfile -t order < "$CALL_LOG"; [ "${order[*]}" = 'config shards vault-root root' ]
}

@test "recover B4-20: refused preflight prevents hub-recover" {
  local fakebin="$TEST_ROOT/fakebin" script="$TEST_ROOT/fake-k3d-manager" copy="$TEST_ROOT/repo"
  mkdir -p "$fakebin"
  cat > "$script" <<'STUB'
#!/usr/bin/env bash
if [[ "$1" == hub_data_recover_preflight ]]; then
  printf 'refused\n'
  exit 2
fi
printf '%s\n' "$1" >> "$CALL_LOG"
STUB
  chmod +x "$script"
  cp -R "$PWD" "$copy"
  cp "$script" "$copy/scripts/k3d-manager"
  cat > "$copy/bin/hub-restore" <<'STUB'
#!/usr/bin/env bash
printf 'hub-restore %s\n' "$*" >> "$CALL_LOG"
exit 0
STUB
  chmod +x "$copy/bin/hub-restore"
  run env PATH="$fakebin:$PATH" K3DM_HUB_DATA_RECOVER_RUN_ROOT="$TEST_ROOT/run" make -C "$copy" hub-recover-all
  [ "$status" -eq 2 ]
  run grep -q hub-recover "$CALL_LOG"
  [ "$status" -eq 1 ]
  run grep -q hub_data_recover_teardown "$CALL_LOG"
  [ "$status" -eq 1 ]
}

@test "recover preflight: present hub is marked and approval warns before deletion" {
  make_fixture; source_plugin
  jq '. + {format:2,images:{}}' "$DR_TEST_REPO_FIXTURE/snapshots/20261009T120000Z/inventory.json" > "$TEST_ROOT/inventory.json"; mv "$TEST_ROOT/inventory.json" "$DR_TEST_REPO_FIXTURE/snapshots/20261009T120000Z/inventory.json"
  (cd "$DR_TEST_REPO_FIXTURE/snapshots/20261009T120000Z" && sha256sum *.age pv-pvc.yaml inventory.json > SHA256SUMS)
  export K3DM_HUB_DATA_RECOVER_RUN_ROOT="$TEST_ROOT/run" K3DM_HUB_DATA_TEST_TTY=1 K3DM_HUB_DATA_TTY_DEVICE="$TEST_ROOT/approval"
  printf '20261009T120000Z\n' > "$TEST_ROOT/approval"
  cat > "$STUB_BIN/k3d" <<'STUB'
#!/usr/bin/env bash
printf 'k3d-cluster  running\n'
STUB
  chmod +x "$STUB_BIN/k3d"
  _hub_data_validate_target() { printf called >> "$CALL_LOG"; }
  run --separate-stderr hub_data_recover_preflight
  [ "$status" -eq 0 ]; [[ "$output" == RUN_ID=* ]]; [ "$(cat "$TEST_ROOT/run/"*/hub_present)" = 1 ]
  grep -q called "$CALL_LOG"; [[ "$stderr" == *"DELETES the local hub"* ]]; [[ "$stderr" == *"Type export timestamp"* ]]
}

@test "recover preflight: absent hub skips validation and still asks approval" {
  make_fixture; source_plugin
  jq '. + {format:2,images:{}}' "$DR_TEST_REPO_FIXTURE/snapshots/20261009T120000Z/inventory.json" > "$TEST_ROOT/inventory.json"; mv "$TEST_ROOT/inventory.json" "$DR_TEST_REPO_FIXTURE/snapshots/20261009T120000Z/inventory.json"
  (cd "$DR_TEST_REPO_FIXTURE/snapshots/20261009T120000Z" && sha256sum *.age pv-pvc.yaml inventory.json > SHA256SUMS)
  export K3DM_HUB_DATA_RECOVER_RUN_ROOT="$TEST_ROOT/run" K3DM_HUB_DATA_TEST_TTY=1 K3DM_HUB_DATA_TTY_DEVICE="$TEST_ROOT/approval"
  printf '20261009T120000Z\n' > "$TEST_ROOT/approval"
  cat > "$STUB_BIN/k3d" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
  chmod +x "$STUB_BIN/k3d"
  _hub_data_validate_target() { printf called >> "$CALL_LOG"; return 1; }
  run --separate-stderr hub_data_recover_preflight
  [ "$status" -eq 0 ]; [[ "$output" == RUN_ID=* ]]; [ "$(cat "$TEST_ROOT/run/"*/hub_present)" = 0 ]
  preflight_stderr="$stderr"; run grep -q called "$CALL_LOG"; [ "$status" -eq 1 ]; [[ "$preflight_stderr" == *"built from scratch"* ]]; [[ "$preflight_stderr" == *"Type export timestamp"* ]]
  [ "$(jq -c '.server_url,.nodes' "$TEST_ROOT/run/"*/target.json)" = $'""\n[]' ]
}

@test "recover teardown: present removes only exact k3d leftovers" {
  source_plugin; export K3DM_HUB_DATA_RECOVER_RUN_ROOT="$TEST_ROOT/run"; mkdir -p "$TEST_ROOT/run/t1"; printf 1 > "$TEST_ROOT/run/t1/hub_present"
  cluster_exists=1
  k3d() { [[ "$cluster_exists" == 1 ]] && printf 'k3d-cluster  running\n'; return 0; }
  _hub_data_cluster_down() { [ "$1" = k3d-cluster ]; cluster_exists=0; printf 'down %s\n' "$*" >> "$CALL_LOG"; }
  docker() {
    { printf 'docker'; printf ' %s' "$@"; printf '\n'; } >> "$CALL_LOG"
    case "$1 $2" in
      'ps -a') [[ "$*" == *'--format'* ]] && { [[ "${removed:-0}" == 0 ]] && printf 'k3d-k3d-cluster-agent-1\n'; return; } ;;
      'network ls') printf 'k3d-k3d-cluster\n';;
      'volume ls') printf 'k3d-k3d-cluster-images\nk3d-k3d-cluster-recovery-server-data\n';;
      'rm -f') removed=1;;
      'network rm'|'volume rm') :;;
    esac
  }
  run hub_data_recover_teardown t1
  [ "$status" -eq 0 ]; grep -Fq 'docker rm -f -- k3d-k3d-cluster-agent-1' "$CALL_LOG"; grep -Fq 'docker network rm -- k3d-k3d-cluster' "$CALL_LOG"; grep -Fq 'docker volume rm -- k3d-k3d-cluster-images' "$CALL_LOG"; ! grep -Fq recovery-server-data "$CALL_LOG"
}

@test "recover teardown: cluster-down wrapper deletes the hub and never discards hub data" {
  source_plugin; local root="$TEST_ROOT/root"; mkdir -p "$root/bin"
  cat > "$root/bin/cluster-down" <<'STUB'
#!/usr/bin/env bash
printf '%s|%s|%s\n' "$CLUSTER_PROVIDER" "$HUB_CLUSTER_NAME" "$*" >> "$CALL_LOG"
STUB
  chmod +x "$root/bin/cluster-down"
  _HUB_DATA_ROOT="$root" _hub_data_cluster_down k3d-cluster
  [ "$(cat "$CALL_LOG")" = 'k3d|k3d-cluster|--confirm --delete-hub' ]
}

@test "recover teardown: absent hub checks leftovers without cluster-down" {
  source_plugin; export K3DM_HUB_DATA_RECOVER_RUN_ROOT="$TEST_ROOT/run"; mkdir -p "$TEST_ROOT/run/t1"; printf 0 > "$TEST_ROOT/run/t1/hub_present"
  k3d() { :; }; _hub_data_cluster_down() { printf called >> "$CALL_LOG"; return 1; }; docker() { printf 'docker %s\n' "$*" >> "$CALL_LOG"; }
  run hub_data_recover_teardown t1
  [ "$status" -eq 0 ]; [[ "$output" == *"no hub to delete"* ]]; run grep -q called "$CALL_LOG"; [ "$status" -eq 1 ]
}

@test "recover teardown: snapshot guard refusal stops before docker cleanup" {
  source_plugin; export K3DM_HUB_DATA_RECOVER_RUN_ROOT="$TEST_ROOT/run"; mkdir -p "$TEST_ROOT/run/t1"; printf 1 > "$TEST_ROOT/run/t1/hub_present"
  _hub_data_cluster_down() { return 2; }; docker() { printf called >> "$CALL_LOG"; }
  run hub_data_recover_teardown t1
  [ "$status" -eq 2 ]; [ ! -s "$CALL_LOG" ]
}

@test "recover teardown: surviving cluster stops before docker cleanup" {
  source_plugin; export K3DM_HUB_DATA_RECOVER_RUN_ROOT="$TEST_ROOT/run"; mkdir -p "$TEST_ROOT/run/t1"; printf 1 > "$TEST_ROOT/run/t1/hub_present"
  k3d() { printf 'k3d-cluster  running\n'; }; _hub_data_cluster_down() { :; }; docker() { printf called >> "$CALL_LOG"; }
  run hub_data_recover_teardown t1
  [ "$status" -eq 1 ]; run grep -q called "$CALL_LOG"; [ "$status" -eq 1 ]
}

@test "recover preflight: a failed k3d listing refuses instead of treating the hub as absent" {
  make_fixture; source_plugin
  jq '. + {format:2,images:{}}' "$DR_TEST_REPO_FIXTURE/snapshots/20261009T120000Z/inventory.json" > "$TEST_ROOT/inventory.json"; mv "$TEST_ROOT/inventory.json" "$DR_TEST_REPO_FIXTURE/snapshots/20261009T120000Z/inventory.json"
  (cd "$DR_TEST_REPO_FIXTURE/snapshots/20261009T120000Z" && sha256sum *.age pv-pvc.yaml inventory.json > SHA256SUMS)
  export K3DM_HUB_DATA_RECOVER_RUN_ROOT="$TEST_ROOT/run" K3DM_HUB_DATA_TEST_TTY=1 K3DM_HUB_DATA_TTY_DEVICE="$TEST_ROOT/approval"
  printf '20261009T120000Z\n' > "$TEST_ROOT/approval"
  k3d() { return 1; }
  _hub_data_recover_approval() { printf approval >> "$CALL_LOG"; }
  run --separate-stderr hub_data_recover_preflight
  [ "$status" -eq 1 ]; [ -z "$output" ]; [[ "$stderr" == *"cannot list k3d clusters"* ]]
  run grep -q approval "$CALL_LOG"; [ "$status" -eq 1 ]
  run compgen -G "$TEST_ROOT/run/*/hub_present"; [ "$status" -ne 0 ]
}

@test "recover teardown: a failed k3d listing stops before docker cleanup" {
  source_plugin; export K3DM_HUB_DATA_RECOVER_RUN_ROOT="$TEST_ROOT/run"; mkdir -p "$TEST_ROOT/run/t1"; printf 0 > "$TEST_ROOT/run/t1/hub_present"
  k3d() { return 1; }; _hub_data_cluster_down() { :; }; docker() { printf called >> "$CALL_LOG"; }
  run hub_data_recover_teardown t1
  [ "$status" -eq 1 ]; run grep -q called "$CALL_LOG"; [ "$status" -eq 1 ]
}

@test "recover teardown: missing hub_present fails before cluster-down" {
  source_plugin; export K3DM_HUB_DATA_RECOVER_RUN_ROOT="$TEST_ROOT/run"; mkdir -p "$TEST_ROOT/run/t1"
  _hub_data_cluster_down() { printf called >> "$CALL_LOG"; }
  run hub_data_recover_teardown t1
  [ "$status" -eq 1 ]; [ ! -s "$CALL_LOG" ]
}

@test "recover B4-21: teardown precedes rebuild and resume" {
  local script="$TEST_ROOT/k3d-manager" copy="$TEST_ROOT/repo" fake_make="$TEST_ROOT/make"
  cat > "$script" <<'STUB'
#!/usr/bin/env bash
if [[ "$1" == hub_data_recover_preflight ]]; then printf 'RUN_ID=t1\n'; exit 0; fi
printf '%s\n' "$1" >> "$CALL_LOG"
STUB
  cat > "$fake_make" <<'STUB'
#!/usr/bin/env bash
printf 'make %s\n' "$*" >> "$CALL_LOG"
STUB
  chmod +x "$script" "$fake_make"; cp -R "$PWD" "$copy"; cp "$script" "$copy/scripts/k3d-manager"
  cat > "$copy/bin/hub-restore" <<'STUB'
#!/usr/bin/env bash
printf 'hub-restore %s\n' "$*" >> "$CALL_LOG"
exit 0
STUB
  chmod +x "$copy/bin/hub-restore"
  run env CALL_LOG="$CALL_LOG" K3DM_HUB_DATA_RECOVER_RUN_ROOT="$TEST_ROOT/run" MAKE="$fake_make" make -C "$copy" hub-recover-all
  [ "$status" -eq 0 ]; [ "$(cat "$CALL_LOG")" = $'hub-restore --preflight-only\nhub_data_recover_teardown\nmake --no-print-directory hub-recover\nhub_data_recover' ]
}

@test "recover B4-21: hub-recover-all preserves DR shards during hub rebuild" {
  local recipe
  recipe="$(awk '/^hub-recover-all:/{found=1; next} found && /^$/{exit} found' Makefile)"
  [[ "$recipe" == *'K3DM_DR_SHARDS_PRESERVE=1 $(MAKE) --no-print-directory hub-recover;'* ]]
}

@test "recover B4-22: teardown failure prevents rebuild and resume" {
  local script="$TEST_ROOT/k3d-manager" copy="$TEST_ROOT/repo"
  cat > "$script" <<'STUB'
#!/usr/bin/env bash
if [[ "$1" == hub_data_recover_preflight ]]; then printf 'RUN_ID=t1\n'; exit 0; fi
printf '%s\n' "$1" >> "$CALL_LOG"
[[ "$1" == hub_data_recover_teardown ]] && exit 2
STUB
  chmod +x "$script"; cp -R "$PWD" "$copy"; cp "$script" "$copy/scripts/k3d-manager"
  cat > "$copy/bin/hub-restore" <<'STUB'
#!/usr/bin/env bash
printf 'hub-restore %s\n' "$*" >> "$CALL_LOG"
exit 0
STUB
  chmod +x "$copy/bin/hub-restore"
  run env CALL_LOG="$CALL_LOG" K3DM_HUB_DATA_RECOVER_RUN_ROOT="$TEST_ROOT/run" MAKE=true make -C "$copy" hub-recover-all
  [ "$status" -ne 0 ]; [ "$(cat "$CALL_LOG")" = $'hub-restore --preflight-only\nhub_data_recover_teardown' ]
}

@test "recover B4-23: keychain preflight refusal stops hub-recover-all before teardown" {
  local script="$TEST_ROOT/k3d-manager" copy="$TEST_ROOT/repo"
  cat > "$script" <<'STUB'
#!/usr/bin/env bash
if [[ "$1" == hub_data_recover_preflight ]]; then printf 'RUN_ID=t1\n'; exit 0; fi
printf '%s\n' "$1" >> "$CALL_LOG"
STUB
  chmod +x "$script"; cp -R "$PWD" "$copy"; cp "$script" "$copy/scripts/k3d-manager"
  cat > "$copy/bin/hub-restore" <<'STUB'
#!/usr/bin/env bash
printf 'hub-restore %s\n' "$*" >> "$CALL_LOG"
exit 2
STUB
  chmod +x "$copy/bin/hub-restore"
  run env CALL_LOG="$CALL_LOG" K3DM_HUB_DATA_RECOVER_RUN_ROOT="$TEST_ROOT/run" MAKE=true make -C "$copy" hub-recover-all
  [ "$status" -eq 2 ]
  grep -Fxq 'hub-restore --preflight-only' "$CALL_LOG"
  [[ "$output" == *"nothing was deleted"* ]]
  run ! grep -Eq 'hub_data_recover_teardown|hub-recover|hub_data_recover$' "$CALL_LOG"
}

@test "recover B4-D1: a failed step records its rc and does not run the next step" {
  source_plugin; local steps="$TEST_ROOT/steps.jsonl"; _hub_data_run_step "$steps" 4 false || rc=$?; [ "${rc:-0}" -ne 0 ]
  run _hub_data_step_finished 4 "$steps"
  [ "$status" -ne 0 ]
  grep -q '"step":4,"finished".*"rc":1' "$steps"
  run grep -q '"step":5' "$steps"
  [ "$status" -eq 1 ]
  make_fixture
  export K3DM_HUB_DATA_RECOVER_RUN_ROOT="$TEST_ROOT/recover" RESUME=d1
  mkdir -p "$K3DM_HUB_DATA_RECOVER_RUN_ROOT/d1"
  printf '%s\n' "$DR_TEST_REPO_FIXTURE/snapshots/20261009T120000Z" > "$K3DM_HUB_DATA_RECOVER_RUN_ROOT/d1/export_dir"
  : > "$K3DM_HUB_DATA_RECOVER_RUN_ROOT/d1/approval_time"
  _hub_data_verify_export() { :; }
  _hub_data_check_compatibility() { :; }
  _hub_data_validate_target() { :; }
  _hub_data_argocd_resume() { :; }
  _hub_data_recover_step2() { :; }
  _hub_data_recover_step3() { :; }
  _hub_data_recover_step4() { _hub_data_run_step "$K3DM_HUB_DATA_RECOVER_RUN_ROOT/d1/steps.jsonl" 4 false; }
  _hub_data_recover_step5() { printf ran >> "$CALL_LOG"; }
  run hub_data_recover
  [ "$status" -ne 0 ]
  run grep -q ran "$CALL_LOG"
  [ "$status" -eq 1 ]
  grep -q '"step":4,"finished".*"rc":1' "$K3DM_HUB_DATA_RECOVER_RUN_ROOT/d1/steps.jsonl"
  [ -s "$K3DM_HUB_DATA_RECOVER_RUN_ROOT/d1/report.json" ]
}

@test "recover B4-D2: empty ArgoCD jsonpath is paused and auto-sync is rejected" {
  source_plugin; mkdir -p "$TEST_ROOT/argo"; : > "$TEST_ROOT/argo/$K3DM_HUB_DATA_ARGOCD_APP.automated"; _kubectl() { [[ "${ARGO_AUTO:-0}" == 1 ]] && printf '{"selfHeal":true}' || printf ''; }
  run _hub_data_argocd_assert_paused ctx "$TEST_ROOT/argo"; [ "$status" -eq 0 ]; ARGO_AUTO=1 run _hub_data_argocd_assert_paused ctx "$TEST_ROOT/argo"; [ "$status" -ne 0 ]
}

@test "recover B4-D3: vault-root is JSON from stdin and no literal dash is used" {
  source_plugin; _hub_data_generate_root() { printf ROOT-TOKEN; }; _vault_exec_stream() { :; }; _secret_load_data() { [[ "$2" == *:count ]] && printf 1 || printf SHARD; }; _vault_dr_shard_valid() { return 0; }; _vault_cache_unseal_keys() { :; }; _hub_recovery_sync_vault_root_token() { :; }; _kubectl() { printf '%s\n' "$*" >> "$CALL_LOG"; cat > "$TEST_ROOT/payload.json"; }
  run _hub_data_repoint_vault ctx; [ "$status" -eq 0 ]; jq -e '.stringData.root_token == "ROOT-TOKEN"' "$TEST_ROOT/payload.json"
  run grep -q -- '--from-literal' "$CALL_LOG"
  [ "$status" -eq 1 ]
  run grep -q ROOT-TOKEN "$CALL_LOG"
  [ "$status" -eq 1 ]
}

@test "recover B4-R1: finished steps are skipped and unfinished step 4 needs redo" {
  source_plugin
  local steps="$TEST_ROOT/steps.jsonl"
  printf '%s\n' '{"step":5,"started":"now"}' '{"step":5,"finished":"now","rc":0}' > "$steps"
  hub_data_unseal_dr() { printf ran >> "$CALL_LOG"; }
  run _hub_data_recover_step5 "$steps"
  [ "$status" -eq 0 ]
  run grep -q ran "$CALL_LOG"
  [ "$status" -eq 1 ]
  printf '%s\n' '{"step":4,"started":"now"}' > "$steps"
  _hub_data_argocd_assert_paused() { :; }
  hub_data_restore() { printf restored >> "$CALL_LOG"; }
  run _hub_data_recover_step4 "$steps" ctx "$TEST_ROOT/run"
  [ "$status" -ne 0 ]
  REDO_STEP=4 run _hub_data_recover_step4 "$steps" ctx "$TEST_ROOT/run"
  [ "$status" -eq 0 ]
  grep -q restored "$CALL_LOG"
}

@test "recover B4-R2: restore uses the recorded export and never clones" {
  make_fixture; source_plugin
  export DR_DRILL_CONTEXT=ctx DR_DRILL_CLUSTER=test DR_DRILL_RESTORE_STAGE="$TEST_ROOT/stage"
  export HUB_DATA_RESTORE_EXPORT_DIR="$DR_TEST_REPO_FIXTURE/snapshots/20261009T120000Z"
  _hub_data_verify_export() { :; }
  _hub_data_prepare_claim() { :; }
  _hub_data_copy_claim() { :; }
  _hub_data_scale() { :; }
  run hub_data_restore
  [ "$status" -eq 0 ]
  run grep -q clone "$CALL_LOG"
  [ "$status" -eq 1 ]
}

@test "recover B4-R3: verification passes context to kubectl" {
  source_plugin
  printf '%s\n' '{"keycloak_realm_user_count":3,"ldap_entry_count":2}' > "$TEST_ROOT/inventory.json"
  _hub_data_keycloak_user_count() { printf '%s\n' "$*" >> "$CALL_LOG"; printf 3; }
  _hub_data_ldap_entry_count() { printf '%s\n' "$*" >> "$CALL_LOG"; printf 2; }
  run hub_data_verify_keycloak "$TEST_ROOT/inventory.json" target-context
  [ "$status" -eq 0 ]
  run hub_data_verify_ldap "$TEST_ROOT/inventory.json" target-context
  [ "$status" -eq 0 ]
  grep -q -- '--context target-context' "$CALL_LOG"
}

@test "recover B4-R4: resume failure is logged and report records false" {
  source_plugin; mkdir -p "$TEST_ROOT/run"
  printf '%s' '{"prune":true}' > "$TEST_ROOT/run/$K3DM_HUB_DATA_ARGOCD_APP.automated"
  _kubectl() { return 1; }
  run --separate-stderr _hub_data_argocd_resume ctx "$TEST_ROOT/run"
  [ "$status" -eq 0 ]
  [[ "$stderr" == *'failed to resume'* ]]
  [ "$(cat "$TEST_ROOT/run/argocd_resume")" = false ]
  _hub_data_report "$TEST_ROOT/run" 1
  [ "$(jq -r .argocd_resume "$TEST_ROOT/run/report.json")" = false ]
}

@test "recover B4-14: without a TTY approval is refused before the prompt" {
  run env PLUGINS_DIR="$PLUGINS_DIR" SCRIPT_DIR="$PWD/scripts" bash -c 'source "$PLUGINS_DIR/hub_data.sh"; unset K3DM_HUB_DATA_TEST_TTY; _hub_data_recover_approval 20261011T120000Z </dev/null'
  [ "$status" -eq 2 ]
}

@test "recover B4-16: age identity is not sent in command argv" {
  source_plugin
  export HUB_DATA_RESTORE_TARGET=hub
  K3DM_HUB_DATA_AGE_IDENTITY=AGE-SECRET-KEY-1SENTINELVALUE
  age() { printf 'age %s\n' "$*" >> "$CALL_LOG"; cat "$3" > "$TEST_ROOT/identity-seen"; }
  docker() { printf 'docker %s\n' "$*" >> "$CALL_LOG"; cat >/dev/null; }
  _secret_load_data() { printf 'keychain\n' >> "$CALL_LOG"; }
  : > "$TEST_ROOT/claim.tar.age"
  run _hub_data_restore_one identity c "$TEST_ROOT/claim.tar.age" agent-0 /data
  [ "$status" -eq 0 ]
  grep -q '^age -d -i /dev/fd/' "$CALL_LOG"
  grep -q SENTINELVALUE "$TEST_ROOT/identity-seen"
  run grep -q SENTINELVALUE "$CALL_LOG"
  [ "$status" -eq 1 ]
  run grep -q keychain "$CALL_LOG"
  [ "$status" -eq 1 ]
}

@test "recover B4-17a: ArgoCD read-back stops before destructive work" {
  source_plugin; mkdir -p "$TEST_ROOT/argo"
  printf '%s' '{"prune":true}' > "$TEST_ROOT/argo/$K3DM_HUB_DATA_ARGOCD_PARENT.automated"
  printf '%s' '{"prune":true}' > "$TEST_ROOT/argo/$K3DM_HUB_DATA_ARGOCD_APP.automated"
  _kubectl() { [[ "$*" == *'get application'* ]] && printf '{"selfHeal":true}'; }
  run _hub_data_argocd_assert_paused ctx "$TEST_ROOT/argo"
  [ "$status" -ne 0 ]
  run grep -q 'scale ' "$CALL_LOG"
  [ "$status" -eq 1 ]
}

@test "recover B4-19: V8 records SecretSyncedError as false" {
  source_plugin; export K3DM_HUB_DATA_V8_WAIT_S=0
  _kubectl() { printf '%s\n' '{"items":[{"status":{"conditions":[{"type":"Ready","reason":"SecretSyncedError"}]}}]}'; }
  run hub_data_verify_externalsecrets ctx
  [ "$status" -ne 0 ]
}

@test "recover B4-21: drill unseal uses the moved hub function" {
  source_plugin
  grep -q 'hub_data_unseal_dr' "$PWD/bin/dr-drill"
  run grep -Eq '^_dr_drill_v[1-5][[:space:]]*\(' "$PWD/bin/dr-drill"
  [ "$status" -eq 1 ]
}

@test "dr credential shim: stdin is recorded and forwarded byte-for-byte without -w value" {
  local run_dir="$TEST_ROOT/credential-run" real="$TEST_ROOT/real-security"
  mkdir -p "$run_dir"
  cat > "$real" <<'STUB'
#!/usr/bin/env bash
cat > "$REAL_STDIN_LOG"
STUB
  chmod +x "$real"
  export REAL_STDIN_LOG="$TEST_ROOT/real-stdin.log" DR_SECURITY_CREDENTIALS_FILE="$run_dir/credentials.tsv" DR_SECURITY_UNEXPECTED_FILE="$run_dir/unexpected.tsv" DR_SECURITY_ALLOWLIST="$PWD/scripts/etc/dr/credential-allowlist.tsv" DR_SECURITY_SCOPES="restore restore-hub" DR_SECURITY_CONTEXT=k3d-k3d-cluster DR_SECURITY_REAL="$real"
  printf 'add-generic-password -s k3dm-vault-root-token -a k3d-k3d-cluster -w VALUE-ONE\nfind-generic-password -s k3dm-vault-unseal-dr -a secrets/vault:shard1\n' | "$PWD/scripts/etc/dr/security-shim" -i
  grep -qx $'add\tk3dm-vault-root-token\tk3d-k3d-cluster' "$run_dir/credentials.tsv"
  grep -qx $'find\tk3dm-vault-unseal-dr\tsecrets/vault:shard1' "$run_dir/credentials.tsv"
  grep -q VALUE-ONE "$REAL_STDIN_LOG"
  run grep -R -q -- '-w VALUE-ONE' "$run_dir"
  [ "$status" -eq 1 ]
}

@test "dr credential shim: argv -w is skipped and never written under the run directory" {
  local run_dir="$TEST_ROOT/credential-argv"
  mkdir -p "$run_dir"
  export DR_SECURITY_CREDENTIALS_FILE="$run_dir/credentials.tsv" DR_SECURITY_UNEXPECTED_FILE="$run_dir/unexpected.tsv" DR_SECURITY_ALLOWLIST="$PWD/scripts/etc/dr/credential-allowlist.tsv" DR_SECURITY_SCOPES="restore restore-hub" DR_SECURITY_CONTEXT=k3d-k3d-cluster DR_SECURITY_REAL="$(command -v true)"
  "$PWD/scripts/etc/dr/security-shim" add-generic-password -s k3dm-vault-root-token -a k3d-k3d-cluster -w SENTINEL
  grep -qx $'add\tk3dm-vault-root-token\tk3d-k3d-cluster' "$run_dir/credentials.tsv"
  run grep -R -q SENTINEL "$run_dir"
  [ "$status" -eq 1 ]
}

@test "dr credential shim: enforce exits 44 and does not reach real security" {
  local run_dir="$TEST_ROOT/credential-enforce"
  mkdir -p "$run_dir"
  cat > "$TEST_ROOT/real-security" <<'STUB'
#!/usr/bin/env bash
touch "$TEST_ROOT/real-security-reached"
STUB
  chmod +x "$TEST_ROOT/real-security"
  export DR_DRILL_CREDENTIAL_POLICY=enforce DR_SECURITY_CREDENTIALS_FILE="$run_dir/credentials.tsv" DR_SECURITY_UNEXPECTED_FILE="$run_dir/unexpected.tsv" DR_SECURITY_ALLOWLIST="$PWD/scripts/etc/dr/credential-allowlist.tsv" DR_SECURITY_SCOPES="restore restore-hub" DR_SECURITY_CONTEXT=k3d-k3d-cluster DR_SECURITY_REAL="$TEST_ROOT/real-security"
  run "$PWD/scripts/etc/dr/security-shim" find-generic-password -s hidden -a account -w
  [ "$status" -eq 44 ]
  [ ! -e "$TEST_ROOT/real-security-reached" ]
}

_shim_env() {
  local run_dir="$TEST_ROOT/shim-$1"; mkdir -p "$run_dir"
  export DR_SECURITY_CREDENTIALS_FILE="$run_dir/credentials.tsv" DR_SECURITY_UNEXPECTED_FILE="$run_dir/unexpected.tsv" DR_SECURITY_ALLOWLIST="$PWD/scripts/etc/dr/credential-allowlist.tsv" DR_SECURITY_REAL="$(command -v true)"
  export DR_SECURITY_SCOPES="$2" DR_SECURITY_CONTEXT="$3"
}

@test "dr credential scope: a drill may not touch the unseal-key cache or another context's root token" {
  _shim_env drill drill k3d-dr-drill
  export DR_DRILL_CREDENTIAL_POLICY=enforce
  run "$PWD/scripts/etc/dr/security-shim" add-generic-password -s k3d-manager-vault-unseal -a secrets/vault:shard1 -w X
  [ "$status" -eq 44 ]
  "$PWD/scripts/etc/dr/security-shim" add-generic-password -s k3dm-vault-unseal-drill -a secrets/vault:count -w X
  [ "$(wc -l < "$DR_SECURITY_UNEXPECTED_FILE")" -eq 1 ]
  run "$PWD/scripts/etc/dr/security-shim" find-generic-password -s k3dm-vault-root-token -a k3d-k3d-cluster -w
  [ "$status" -eq 44 ]
  run "$PWD/scripts/etc/dr/security-shim" delete-generic-password -s k3d-manager-vault-unseal -a secrets/vault:shard1
  [ "$status" -eq 44 ]
}

@test "dr credential scope: a hub restore may cache unseal keys; a drill rehearsal may not; root token only for the target context" {
  export DR_DRILL_CREDENTIAL_POLICY=enforce
  _shim_env hub "restore restore-hub" k3d-k3d-cluster
  "$PWD/scripts/etc/dr/security-shim" add-generic-password -s k3d-manager-vault-unseal -a secrets/vault:shard1 -w X
  "$PWD/scripts/etc/dr/security-shim" add-generic-password -s k3dm-vault-root-token -a k3d-k3d-cluster -w X
  [ ! -s "$DR_SECURITY_UNEXPECTED_FILE" ]
  _shim_env rehearsal "restore restore-drill" k3d-dr-drill
  run "$PWD/scripts/etc/dr/security-shim" add-generic-password -s k3d-manager-vault-unseal -a secrets/vault:shard1 -w X; [ "$status" -eq 44 ]
  run "$PWD/scripts/etc/dr/security-shim" add-generic-password -s k3dm-vault-root-token -a k3d-k3d-cluster -w X; [ "$status" -eq 44 ]
  "$PWD/scripts/etc/dr/security-shim" add-generic-password -s k3dm-vault-root-token -a k3d-dr-drill -w X
  "$PWD/scripts/etc/dr/security-shim" find-generic-password -s k3dm-hub-data-age -a identity -w
}

@test "dr credential guard: hub_data_recover records in its own process, also on RESUME, and scopes by target" {
  make_fixture; source_plugin
  export K3DM_HUB_DATA_RECOVER_RUN_ROOT="$TEST_ROOT/recover" RESUME=g1 K3DM_HUB_DATA_CONTEXT=k3d-dr-drill K3DM_HUB_DATA_RECOVER_ALLOW_DRILL=1
  mkdir -p "$K3DM_HUB_DATA_RECOVER_RUN_ROOT/g1"
  printf '%s\n' "$DR_TEST_REPO_FIXTURE/snapshots/20261009T120000Z" > "$K3DM_HUB_DATA_RECOVER_RUN_ROOT/g1/export_dir"
  : > "$K3DM_HUB_DATA_RECOVER_RUN_ROOT/g1/approval_time"
  _hub_data_verify_export() { :; }; _hub_data_check_compatibility() { :; }; _hub_data_validate_target() { :; }; _hub_data_argocd_resume() { :; }
  _hub_data_recover_step2() { printf '%s|%s|%s|%s\n' "${PATH%%:*}" "$(type -t security)" "$DR_SECURITY_SCOPES" "$DR_SECURITY_CONTEXT" > "$TEST_ROOT/guard.txt"; return 1; }
  run hub_data_recover; [ "$status" -ne 0 ]
  [ "$(cat "$TEST_ROOT/guard.txt")" = "$K3DM_HUB_DATA_RECOVER_RUN_ROOT/g1/bin|function|restore restore-drill|k3d-dr-drill" ]
  [ "$(readlink "$K3DM_HUB_DATA_RECOVER_RUN_ROOT/g1/bin/security")" = "$PWD/scripts/etc/dr/security-shim" ]
  [ -e "$K3DM_HUB_DATA_RECOVER_RUN_ROOT/g1/credentials.tsv" ]
}

@test "dr restore: an out-of-cluster docker target is refused before exec" {
  source_plugin
  local encrypted="$TEST_ROOT/claim.tar.age"
  : > "$encrypted"
  export DR_DRILL_MODE=1 DR_DRILL_CONTEXT=k3d-dr-drill DR_DRILL_CLUSTER=k3d-cluster
  docker() { printf 'docker %s\n' "$*" >> "$CALL_LOG"; }
  run _hub_data_restore_one identity c "$encrypted" agent-0 /data
  [ "$status" -ne 0 ]
  [[ "$output" == *"target is not the drill cluster"* ]]
  run grep -q 'docker exec' "$CALL_LOG"
  [ "$status" -eq 1 ]
}

@test "recover F1: the preflight summary is on stderr so it shows before the approval; stdout is only RUN_ID" {
  make_fixture; source_plugin
  export K3DM_HUB_DATA_RECOVER_RUN_ROOT="$TEST_ROOT/recover"
  git() { cp -R "$DR_TEST_REPO_FIXTURE" "${@: -1}"; }
  _hub_data_verify_export() { :; }
  _hub_data_check_compatibility() { :; }
  _hub_data_validate_target() { :; }
  _hub_data_keycloak_user_count() { printf 6; }
  _hub_data_ldap_entry_count() { printf 12; }
  _kubectl() { printf 'value'; }
  k3d() { printf 'k3d-cluster  running\n'; }
  _hub_data_recover_approval() { printf 'approval\n' >> "$CALL_LOG"; }
  run --separate-stderr hub_data_recover_preflight
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^RUN_ID=[0-9]{8}T[0-9]{6}Z$ ]]
  [[ "$stderr" == *'Target context: ctx'* ]]
  [[ "$stderr" == *'Export: 20261009T120000Z'* ]]
  grep -q approval "$CALL_LOG"
}

@test "recover F2: a resumed run pauses ArgoCD again and keeps the value recorded before the first pause" {
  source_plugin
  local steps="$TEST_ROOT/steps.jsonl" dir="$TEST_ROOT/run"
  mkdir -p "$dir"
  printf '%s\n' '{"step":3,"started":"now"}' '{"step":3,"finished":"now","rc":0}' > "$steps"
  printf '%s' '{"prune":true}' > "$dir/$K3DM_HUB_DATA_ARGOCD_APP.automated"
  _kubectl() {
    printf '%s\n' "$*" >> "$CALL_LOG"
    [[ "$*" == *'-o jsonpath'* ]] && return 0
    return 0
  }
  run _hub_data_recover_step3 "$steps" ctx "$dir"
  [ "$status" -eq 0 ]
  grep -q "patch application $K3DM_HUB_DATA_ARGOCD_APP" "$CALL_LOG"
  [ "$(cat "$dir/$K3DM_HUB_DATA_ARGOCD_APP.automated")" = '{"prune":true}' ]
}

@test "recover F3: step 2 prompts on every run and hub mode never reads the age identity from the Keychain" {
  source_plugin
  local steps="$TEST_ROOT/steps.jsonl"
  printf '%s\n' '{"step":2,"started":"now"}' '{"step":2,"finished":"now","rc":0}' > "$steps"
  export K3DM_HUB_DATA_TTY_DEVICE="$TEST_ROOT/tty"
  : > "$K3DM_HUB_DATA_TTY_DEVICE"
  read() { printf 'prompted\n' >> "$CALL_LOG"; K3DM_HUB_DATA_AGE_IDENTITY=AGE-SECRET-KEY-1TEST; }
  run _hub_data_recover_step2 "$steps"
  [ "$status" -eq 0 ]
  grep -q prompted "$CALL_LOG"
  unset -f read
  unset K3DM_HUB_DATA_AGE_IDENTITY
  : > "$CALL_LOG"
  _secret_load_data() { printf 'keychain\n' >> "$CALL_LOG"; printf AGE-SECRET-KEY-1KEYCHAIN; }
  age() { printf 'age\n' >> "$CALL_LOG"; }
  docker() { cat >/dev/null; }
  : > "$TEST_ROOT/claim.tar.age"
  HUB_DATA_RESTORE_TARGET=hub run _hub_data_restore_one identity c "$TEST_ROOT/claim.tar.age" agent-0 /data
  [ "$status" -ne 0 ]
  run grep -Eq 'keychain|age' "$CALL_LOG"
  [ "$status" -eq 1 ]
  HUB_DATA_RESTORE_TARGET=drill run _hub_data_restore_one identity c "$TEST_ROOT/claim.tar.age" agent-0 /data
  [ "$status" -eq 0 ]
  grep -q keychain "$CALL_LOG"
}
