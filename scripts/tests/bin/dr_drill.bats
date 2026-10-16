#!/usr/bin/env bats
bats_require_minimum_version 1.5.0

setup() {
  unset DR_DRILL_CLUSTER DR_DRILL_CONTEXT DR_TEST_CLUSTER_LIST DR_TEST_HOST DR_TEST_NOT_READY DR_TEST_CURL_RC DR_TEST_EXEC_FAIL DR_TEST_UNSEAL_FAIL DR_TEST_RESTORE_FAIL DR_TEST_VAULT_STATUS_FAIL DR_TEST_VAULT_LIST_FAIL
  export TEST_ROOT="$BATS_TEST_TMPDIR/root" STUB_BIN="$BATS_TEST_TMPDIR/root/bin" HOME="$BATS_TEST_TMPDIR/home"
  export KLOG="$TEST_ROOT/kubectl.log" VLOG="$TEST_ROOT/vault.log" SHARD_LOG="$TEST_ROOT/phase.log" PHASE_LOG="$TEST_ROOT/phase.log" RESTORE_LOG="$TEST_ROOT/restore.log"
  mkdir -p "$STUB_BIN" "$TEST_ROOT" "$HOME"
  : > "$KLOG"; : > "$VLOG"; : > "$PHASE_LOG"; : > "$RESTORE_LOG"
  export DR_DRILL_TEST_TTY=1 DR_DRILL_ALLOW_HOST=1 DR_DRILL_DOCKER_FREE_GB=20 DR_DRILL_EGRESS_WAIT_S=0 DR_TEST_EXPORT_TS="$(date -u +%Y%m%dT%H%M%SZ)"
  export JQ_REAL="$(command -v jq)"
  cat > "$STUB_BIN/hostname" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "${DR_TEST_HOST:-m2-air.local}"
STUB
  cat > "$TEST_ROOT/hub-up" <<'STUB'
#!/usr/bin/env bash
printf 'hub-up %s\n' "${DR_DRILL_CONTEXT}|${DR_DRILL_CLUSTER}|${KUBECONFIG}|${DR_DRILL_MODE}|${VAULT_UNSEAL_CACHE_SERVICE:-}" >> "$PHASE_LOG"
[[ "${DR_TEST_HUB_UP_FAIL:-0}" == 1 ]] && exit 1
exit 0
STUB
  cat > "$TEST_ROOT/restore" <<'STUB'
#!/usr/bin/env bash
printf '%s|%s|%s\n' "$DR_DRILL_CONTEXT" "$DR_DRILL_CLUSTER" "$DR_DRILL_RESTORE_STAGE" >> "$RESTORE_LOG"
[[ "${DR_TEST_RESTORE_FAIL:-0}" == 1 ]] && exit 1
if [[ "${DR_TEST_EXTRA_CREDENTIAL:-0}" == 1 ]]; then
  security find-generic-password -s hidden-service -a hidden-account -w || exit $?
fi
mkdir -p "$DR_DRILL_RESTORE_STAGE"
printf '%s\n' '{"vault_paths":["app/"],"keycloak_realm_user_count":1,"ldap_entry_count":2}' > "$DR_DRILL_RESTORE_STAGE/inventory.json"
cat > "$DR_DRILL_RESTORE_STAGE/pv-pvc.yaml" <<'YAML'
metadata:
  name: data-vault-0
  namespace: secrets
  spec:
  logicalNode: server-0
---
metadata:
  name: postgres-keycloak-pvc
  namespace: identity
spec:
  logicalNode: agent-0
---
metadata:
  name: data-openldap-0
  namespace: identity
spec:
  logicalNode: agent-1
---
YAML
exit 0
STUB
cat > "$STUB_BIN/k3d" <<'STUB'
#!/usr/bin/env bash
{ printf 'k3d'; printf ' %q' "$@"; printf '\n'; } >> "$PHASE_LOG"
if [[ "$1 $2" == 'cluster list' && -n "${DR_TEST_CLUSTER_LIST:-}" ]]; then printf '%s\n' "$DR_TEST_CLUSTER_LIST"; fi
STUB
  cat > "$STUB_BIN/docker" <<'STUB'
#!/usr/bin/env bash
{ printf 'docker'; printf ' %q' "$@"; printf '\n'; } >> "$PHASE_LOG"
if [[ "$1" == ps ]]; then printf 'k3d-dr-drill-serverlb 0.0.0.0:%s->6443/tcp\n' "${DR_TEST_SERVERLB_PORT:-6445}"; fi
STUB
  cat > "$STUB_BIN/git" <<'STUB'
#!/usr/bin/env bash
printf 'git'; printf ' %q' "$@"; printf '\n' >> "$PHASE_LOG"
  if [[ "$1" == clone ]]; then dest="${@: -1}"; mkdir -p "$dest/snapshots/${DR_TEST_EXPORT_TS:-20261009T120000Z}"; fi
STUB
cat > "$STUB_BIN/security" <<'STUB'
#!/usr/bin/env bash
{ printf 'security'; printf ' %q' "$@"; printf '\n'; } >> "$PHASE_LOG"
case "$*" in
  *'secrets/vault:count'*) printf '%s' "${DR_TEST_SHARD_COUNT-1}" ;;
  *'secrets/vault:shard1'*) printf '%s' "${DR_TEST_SHARD:-SHARDSENTINEL}" ;;
  *'secrets/vault:shard'*) [[ "${DR_TEST_SHARD_MISSING:-0}" == 1 ]] || printf '%s' "${DR_TEST_SHARD:-SHARDSENTINEL}" ;;
  *) printf '%s' "${DR_TEST_SHARD:-SHARDSENTINEL}" ;;
esac
STUB
  cat > "$STUB_BIN/secret-tool" <<'STUB'
#!/usr/bin/env bash
case "$*" in
  *'name secrets/vault:count'*) printf '%s' "${DR_TEST_SHARD_COUNT-1}" ;;
  *'name secrets/vault:shard1'*) printf '%s' "${DR_TEST_SHARD:-SHARDSENTINEL}" ;;
  *'name secrets/vault:shard'*) [[ "${DR_TEST_SHARD_MISSING:-0}" == 1 ]] || printf '%s' "${DR_TEST_SHARD:-SHARDSENTINEL}" ;;
  *) printf '%s' "${DR_TEST_SHARD:-SHARDSENTINEL}" ;;
esac
STUB
cat > "$STUB_BIN/kubectl" <<'STUB'
#!/usr/bin/env bash
for arg in "$@"; do
  case "$arg" in
    --quiet|--no-exit|--prefer-sudo|--require-sudo)
      printf 'Error: unknown flag: %s\n' "$arg" >&2
      exit 1
      ;;
  esac
done
{ printf 'kubectl'; printf ' %q' "$@"; printf '\n'; } >> "$KLOG"
args="$*"
if [[ "$args" == *'config get-contexts'* ]]; then printf '%b' "${DR_TEST_CONTEXTS:-k3d-dr-drill}"; printf '\n'; exit 0
elif [[ "$args" == *'config view'* ]]; then printf 'https://127.0.0.1:%s\n' "${DR_TEST_SERVER_PORT:-6445}"; exit 0
elif [[ "$args" == *' run dr-egress-check-'* ]]; then exit 0
elif [[ "$args" == *'wait --for=condition=Ready pod/dr-egress-check-'* ]]; then [[ "${DR_TEST_NOT_READY:-0}" == 1 ]] && exit 1; exit 0
elif [[ "$args" == *'exec dr-egress-check-'* ]]; then [[ "${DR_TEST_EXEC_FAIL:-0}" == 1 ]] && { printf 'rc=7\n'; exit 1; }; printf 'rc=%s\n' "${DR_TEST_CURL_RC:-7}"; exit 0
elif [[ "$args" == *'delete pod dr-egress-check-'* ]]; then exit 0
elif [[ "$args" == *'exec deployment/postgres-keycloak'* ]]; then printf '1\n'; exit 0
elif [[ "$args" == *'exec statefulset/openldap'* ]]; then printf 'dn: a\ndn: b\n'; exit 0
elif [[ "$args" == *'get pods'*'app.kubernetes.io/name=postgres-keycloak'* ]]; then printf 'postgres-keycloak-abc\n'; exit 0
elif [[ "$args" == *'get pod vault-0'*'status.phase'* ]]; then
  n=$(( $(cat "$HOME/vault-phase-polls" 2>/dev/null || echo 0) + 1 )); printf '%s' "$n" > "$HOME/vault-phase-polls"
  if (( n <= ${DR_TEST_VAULT_PENDING_POLLS:-0} )); then printf Pending; else printf Running; fi; exit 0
elif [[ "$args" == *'get pod vault-0'*'nodeName'* ]]; then printf 'dr-drill-server-0\n'; exit 0
elif [[ "$args" == *'get pod postgres-keycloak-abc'*'nodeName'* ]]; then printf 'dr-drill-agent-0\n'; exit 0
elif [[ "$args" == *'get pod openldap-0'*'nodeName'* ]]; then printf 'dr-drill-agent-1\n'; exit 0
elif [[ "$args" == *'get pod'*'containers[0].name'* ]]; then exit 0
elif [[ "$args" == *' exec '* ]]; then
  command=(); marker=0
  for arg in "$@"; do [[ "$arg" == -- ]] && marker=1 && continue; (( marker == 1 )) || continue; command+=("$arg"); done
  [[ "${command[0]:-}" == sh ]] && bash -c "${command[2]}" "${command[3]:-sh}" || "${command[@]}"
fi
STUB
cat > "$STUB_BIN/jq" <<'STUB'
#!/usr/bin/env bash
{ printf 'jq'; printf ' %q' "$@"; printf '\n'; } >> "$PHASE_LOG"; exec "$JQ_REAL" "$@"
STUB
  cat > "$STUB_BIN/vault" <<'STUB'
#!/usr/bin/env bash
{ printf 'vault'; printf ' %q' "$@"; printf '\n'; } >> "$VLOG"
{ printf 'vault'; printf ' %q' "$@"; printf '\n'; } >> "$PHASE_LOG"
[[ "$*" == *SHARDSENTINEL* || "$*" == *ENCODED-SENTINEL* ]] && exit 97
case "$*" in
  *'operator unseal'*) printf "Error unsealing: Error making API request.\nCode: 400. Errors:\n* 'key' must be a valid hex or base64 string\n" >&2; exit 2 ;;
  *'write -format=json sys/unseal key=-'*) key="$(cat)"; printf '%s\n' "$key" >> "$SHARD_LOG"; if [[ "${DR_TEST_UNSEAL_FAIL:-0}" == 1 ]]; then printf 'Error unsealing: bad key %s\n* cipher: message authentication failed\n' "$key" >&2; exit 2; fi; exit 0 ;;
  *'-generate-otp'*) printf '{"otp":"OTP-SENTINEL"}' ;;
  *'-init'*) printf '{"nonce":"NONCE"}' ;;
  *'-decode=-'*) [[ "$*" == *OTP-SENTINEL* || "$*" == *ENCODED-SENTINEL* ]] && exit 97; cat >> "$SHARD_LOG"; printf ROOT-TOKEN ;;
  *'generate-root'*'-format=json -'*) [[ "${DR_TEST_KEY_FAIL:-0}" == 1 ]] && exit 1; cat >> "$SHARD_LOG"; printf '{"encoded_token":"ENCODED-SENTINEL"}' ;;
  *'generate-root -cancel'*) : > "${HOME}/cancel-seen" ;;
  *'status'*)
    status_polls=$(( $(cat "$HOME/vault-status-polls" 2>/dev/null || echo 0) + 1 )); printf '%s' "$status_polls" > "$HOME/vault-status-polls"
    [[ "${DR_TEST_VAULT_STATUS_FAIL:-0}" == 1 && "$status_polls" -gt 1 ]] && exit 1
    printf '{"sealed":false}'
    ;;
  *'kv list'*) [[ "${DR_TEST_VAULT_LIST_FAIL:-0}" == 1 ]] && exit 1; printf '["app/"]' ;;
  *'token revoke -self'*) : ;;
esac
STUB
  chmod +x "$STUB_BIN"/*
  chmod +x "$STUB_BIN"/* "$TEST_ROOT/hub-up" "$TEST_ROOT/restore"
  export PATH="$STUB_BIN:$PATH" DR_SECURITY_REAL="$STUB_BIN/security" DR_DRILL_HUB_UP_CMD="$TEST_ROOT/hub-up" DR_DRILL_RESTORE_CMD="$TEST_ROOT/restore"
}

run_drill() { run "$PWD/bin/dr-drill" || true; }

@test "dr drill: full green run follows phases and writes success" {
  run_drill
  [ "$status" -eq 0 ]
  for pair in "1 2" "2 3" "3 4" "4 5" "5 6"; do read -r before after <<<"$pair"; [ "$(grep -n "Phase $before/6" <<<"$output" | cut -d: -f1)" -lt "$(grep -n "Phase $after/6" <<<"$output" | cut -d: -f1)" ]; done
  result="$(find "$HOME/.k3dm/dr-drill" -type f -name '*.json' -print | head -1)"
  [ "$(jq -r .success "$result")" = true ]
}

@test "dr drill: hub-up inherits its dedicated Vault cache service and teardown purges it" {
  cat > "$STUB_BIN/secret-tool" <<'STUB'
#!/usr/bin/env bash
{ printf 'secret-tool'; printf ' %q' "$@"; printf '\n'; } >> "$PHASE_LOG"
[[ "$1" == lookup ]] || exit 0
exec "$DR_SECURITY_REAL" find-generic-password -s "$3" -a "$5" -w
STUB
  chmod +x "$STUB_BIN/secret-tool"
  run_drill
  [ "$status" -eq 0 ]
  grep -q 'hub-up k3d-dr-drill|dr-drill|.*|1|k3dm-vault-unseal-drill' "$PHASE_LOG"
  grep -Eq '(security|secret-tool) .*k3dm-vault-unseal-drill' "$PHASE_LOG"
  [ "$(grep -Ec '(security|secret-tool) .*k3d-manager-vault-unseal' "$PHASE_LOG" || true)" -eq 0 ]
}

@test "dr drill: teardown uses the drill service even when its environment is unset" {
  local harness="$TEST_ROOT/teardown-only"
  sed '/^if _dr_drill_run; then/,$d' "$PWD/bin/dr-drill" | sed "s#^REPO_ROOT=.*#REPO_ROOT=\"$PWD\"#" > "$harness"
  cat >> "$harness" <<'STUB'
_vault_purge_unseal_cache() { printf '%s\n' "${VAULT_UNSEAL_CACHE_SERVICE:-unset}" > "$PURGE_LOG"; }
_dr_drill_started=1
_dr_drill_preflight_refused=0
DR_DRILL_KEEP=1
unset VAULT_UNSEAL_CACHE_SERVICE
_dr_drill_teardown 0
STUB
  chmod +x "$harness"
  export PURGE_LOG="$TEST_ROOT/purge.log"
  run "$harness"
  [ "$status" -eq 0 ]
  [ "$(cat "$PURGE_LOG")" = k3dm-vault-unseal-drill ]
}

@test "dr drill: KEEP preserves kubeconfig and removes staging data" {
  local harness="$TEST_ROOT/teardown-keep"
  local kubeconfig="$TEST_ROOT/dr-drill-kubeconfig" stage="$TEST_ROOT/stage"
  sed '/^if _dr_drill_run; then/,$d' "$PWD/bin/dr-drill" | sed "s#^REPO_ROOT=.*#REPO_ROOT=\"$PWD\"#" > "$harness"
  cat >> "$harness" <<STUB
_vault_purge_unseal_cache() { :; }
_dr_drill_started=1
_dr_drill_preflight_refused=0
DR_DRILL_KEEP=1
DR_DRILL_KUBECONFIG="$kubeconfig"
DR_DRILL_STAGE="$stage"
mkdir -p "\$DR_DRILL_STAGE"
: > "\$DR_DRILL_KUBECONFIG"
_dr_drill_teardown 0
STUB
  chmod +x "$harness"
  run "$harness"
  [ "$status" -eq 0 ]
  [[ "$output" == *"kubeconfig kept: $kubeconfig; use: kubectl --kubeconfig $kubeconfig --context k3d-dr-drill"* ]]
  [ -f "$kubeconfig" ]
  [ ! -e "$stage" ]
  [ "$(grep -c '^k3d cluster delete' "$PHASE_LOG" || true)" -eq 0 ]
}

@test "dr drill: deleting cluster removes kubeconfig" {
  local harness="$TEST_ROOT/teardown-delete"
  local kubeconfig="$TEST_ROOT/dr-drill-kubeconfig" stage="$TEST_ROOT/stage"
  sed '/^if _dr_drill_run; then/,$d' "$PWD/bin/dr-drill" | sed "s#^REPO_ROOT=.*#REPO_ROOT=\"$PWD\"#" > "$harness"
  cat >> "$harness" <<STUB
_vault_purge_unseal_cache() { :; }
_dr_drill_started=1
_dr_drill_preflight_refused=0
DR_DRILL_KEEP=0
DR_DRILL_KUBECONFIG="$kubeconfig"
DR_DRILL_STAGE="$stage"
mkdir -p "\$DR_DRILL_STAGE"
: > "\$DR_DRILL_KUBECONFIG"
_dr_drill_teardown 0
STUB
  chmod +x "$harness"
  run "$harness"
  [ "$status" -eq 0 ]
  [ ! -e "$kubeconfig" ]
  [ ! -e "$stage" ]
  [ "$(grep -c 'cluster delete dr-drill' "$PHASE_LOG" || true)" -ge 1 ]
}

@test "dr drill: name and host guards refuse before k3d" {
  export DR_DRILL_CLUSTER=k3d-cluster
  run_drill; [ "$status" -eq 2 ]; [ "$(grep -c k3d "$PHASE_LOG" || true)" -eq 0 ]
  : > "$PHASE_LOG"; unset DR_DRILL_CLUSTER; export DR_TEST_HOST=not-m2 DR_DRILL_ALLOW_HOST=0
  run_drill; [ "$status" -eq 2 ]; [ "$(grep -c k3d "$PHASE_LOG" || true)" -eq 0 ]
  : > "$PHASE_LOG"; : > "$KLOG"; unset DR_TEST_HOST; export DR_DRILL_ALLOW_HOST=1 DR_DRILL_CONTEXT=k3d-k3d-cluster
  run_drill; [ "$status" -eq 2 ]; [ "$(grep -c k3d "$PHASE_LOG" || true)" -eq 0 ]; [ "$(grep -c kubectl "$KLOG" || true)" -eq 0 ]
}

@test "dr drill: clean preflight passes and a leftover cluster refuses" {
  run_drill; [ "$status" -eq 0 ]
  : > "$PHASE_LOG"; export DR_TEST_CLUSTER_LIST=dr-drill
  run_drill
  [ "$status" -eq 2 ]
  [ "$(grep -c 'hub-up' "$PHASE_LOG" || true)" -eq 0 ]
}

@test "dr drill: restore child receives drill identity" {
  run_drill; [ "$status" -eq 0 ]; [ "$(cut -d'|' -f1 "$RESTORE_LOG")" = k3d-dr-drill ]; [ "$(cut -d'|' -f2 "$RESTORE_LOG")" = dr-drill ]; [ -n "$(cut -d'|' -f3 "$RESTORE_LOG")" ]
}

@test "dr drill: V0 handles readiness, curl codes, deletion, and exact image" {
  export DR_TEST_NOT_READY=1
  : > "$KLOG"; : > "$VLOG"
  run_drill; [ "$status" -ne 0 ]; [ "$(grep -c 'sys/unseal' "$VLOG" || true)" -eq 0 ]; [ "$(grep -c 'delete pod dr-egress-check-secrets' "$KLOG" || true)" -eq 1 ]; [ "$(grep -c 'delete pod dr-egress-check-identity' "$KLOG" || true)" -eq 1 ]
  unset DR_TEST_NOT_READY; export DR_TEST_CURL_RC=7
  : > "$KLOG"; : > "$VLOG"
  run_drill; [ "$status" -eq 0 ]; [ "$(grep -c 'image=curlimages/curl:8.10.1' "$KLOG" || true)" -eq 2 ]; [ "$(grep -c 'delete pod dr-egress-check-secrets' "$KLOG" || true)" -eq 1 ]; [ "$(grep -c 'delete pod dr-egress-check-identity' "$KLOG" || true)" -eq 1 ]
  : > "$KLOG"; : > "$VLOG"; export DR_TEST_EXEC_FAIL=1
  run_drill; [ "$status" -ne 0 ]; [ "$(grep -c 'sys/unseal' "$VLOG" || true)" -eq 0 ]; [ "$(grep -c 'delete pod dr-egress-check-secrets' "$KLOG" || true)" -eq 1 ]; [ "$(grep -c 'delete pod dr-egress-check-identity' "$KLOG" || true)" -eq 1 ]
}

@test "dr drill: unseal and restore failures report and tear down" {
  export DR_TEST_UNSEAL_FAIL=1
  run_drill; result="$(find "$HOME/.k3dm/dr-drill" -type f -name '*.json' -print | head -1)"; [ "$status" -ne 0 ]; [ "$(jq -r .success "$result")" = false ]; grep -q unseal "$result"; grep -q 'cluster delete dr-drill' "$PHASE_LOG"
  : > "$PHASE_LOG"; rm -rf "$HOME/.k3dm/dr-drill"; unset DR_TEST_UNSEAL_FAIL; export DR_TEST_RESTORE_FAIL=1
  run_drill; result="$(find "$HOME/.k3dm/dr-drill" -type f -name '*.json' -print | head -1)"; [ "$status" -ne 0 ]; [ "$(jq -r .success "$result")" = false ]; grep -q phase3 "$result"; grep -q 'cluster delete dr-drill' "$PHASE_LOG"
}

@test "dr drill: V2 uses the fixed restored inventory" {
  run_drill; [ "$status" -eq 0 ]; grep -q 'inventory.json' "$PHASE_LOG"
}

@test "dr drill: Vault checks run under nounset and retain true and false results" {
  run grep -c 'set +u' "$PWD/bin/dr-drill"
  [ "$status" -eq 1 ]; [ "$output" = 0 ]

  run_drill
  [ "$status" -eq 0 ]
  result="$(find "$HOME/.k3dm/dr-drill" -type f -name '*.json' -print | head -1)"
  [ "$(jq -r '.checks.V1' "$result")" = true ]
  [ "$(jq -r '.checks.V2' "$result")" = true ]

  rm -rf "$HOME/.k3dm/dr-drill" "$HOME/vault-status-polls"
  export DR_TEST_VAULT_STATUS_FAIL=1 DR_TEST_VAULT_LIST_FAIL=1
  run_drill
  [ "$status" -ne 0 ]
  result="$(find "$HOME/.k3dm/dr-drill" -type f -name '*.json' -print | head -1)"
  [ "$(jq -r '.checks.V1' "$result")" = false ]
  [ "$(jq -r '.checks.V2' "$result")" = false ]
}

@test "dr drill: V3-V5 use live workload names and label lookup" {
  run_drill; [ "$status" -eq 0 ]; grep -q 'exec deployment/postgres-keycloak' "$KLOG"; grep -q 'exec statefulset/openldap' "$KLOG"; grep -q 'app.kubernetes.io/name=postgres-keycloak' "$KLOG"; [ "$(grep -c postgres-keycloak-0 "$KLOG" || true)" -eq 0 ]; [ "$(grep -c data-openldap "$KLOG" || true)" -eq 0 ]; [ "$(grep -c 'get keycloak' "$KLOG" || true)" -eq 0 ]
}

@test "dr drill: every kubectl call is isolated to the drill context" {
  run_drill; [ "$status" -eq 0 ]
  while IFS= read -r line; do [[ "$line" == *'--kubeconfig '* && "$line" == *'--context k3d-dr-drill'* ]]; done < "$KLOG"
  [ "$(grep -c use-context "$KLOG" || true)" -eq 0 ]
}

@test "dr drill: unseal waits until the restored vault-0 is Running" {
  export DR_TEST_VAULT_PENDING_POLLS=2 DR_DRILL_POLL_S=0
  run_drill; [ "$status" -eq 0 ]
  [ "$(cat "$HOME/vault-phase-polls")" -eq 3 ]
  [ "$(grep -c 'sys/unseal' "$VLOG")" -eq 1 ]
}

@test "dr drill: a vault-0 that never runs fails unseal with a reason and no unseal call" {
  export DR_TEST_VAULT_PENDING_POLLS=1000 DR_DRILL_POLL_S=0 DR_DRILL_VAULT_START_S=1
  run_drill; [ "$status" -ne 0 ]
  [[ "$output" == *"vault-0 is not Running after 1s (phase: Pending)"* ]]
  [ "$(grep -c 'sys/unseal' "$VLOG" || true)" -eq 0 ]
  result="$(find "$HOME/.k3dm/dr-drill" -type f -name '*.json' -print | head -1)"; [ "$(jq -r .failed "$result")" = unseal ]
}

@test "dr drill: an empty Keychain shard count fails unseal and says so" {
  export DR_TEST_SHARD_COUNT=
  run_drill; [ "$status" -ne 0 ]
  [[ "$output" == *"no DR shard count in Keychain service k3dm-vault-unseal-dr"* ]]
  [ "$(grep -c 'sys/unseal' "$VLOG" || true)" -eq 0 ]
}

@test "dr drill: a non-numeric shard count fails unseal and says so" {
  export DR_TEST_SHARD_COUNT=abc
  run_drill; [ "$status" -ne 0 ]
  [[ "$output" == *"is not a positive number"* ]]
  [ "$(grep -c 'sys/unseal' "$VLOG" || true)" -eq 0 ]
}

@test "dr drill: a missing shard is named without printing any shard" {
  export DR_TEST_SHARD_COUNT=2 DR_TEST_SHARD_MISSING=1
  run_drill; [ "$status" -ne 0 ]
  [[ "$output" == *"DR shard 2 of 2 is missing or empty"* ]]
  [[ "$output" != *SHARDSENTINEL* ]]
}

@test "dr drill: a rejected shard names the unseal step" {
  export DR_TEST_UNSEAL_FAIL=1
  run_drill; [ "$status" -ne 0 ]
  [[ "$output" == *"vault operator unseal failed for shard 1 of 1"* ]]
  [[ "$output" == *"cipher: message authentication failed"* ]]
  [[ "$output" != *SHARDSENTINEL* ]]
}

@test "dr drill: a malformed Keychain shard is refused before Vault sees it" {
  export DR_TEST_SHARD='SHARD"SENTINEL'
  run_drill; [ "$status" -ne 0 ]
  [[ "$output" == *"DR shard 1 of 1 in Keychain is not a base64 or hex unseal key"* ]]
  [[ "$output" != *'SHARD"SENTINEL'* ]]
  [ "$(grep -c 'sys/unseal' "$VLOG" || true)" -eq 0 ]
}

@test "dr drill: a trailing CR on a Keychain shard is stripped before unseal" {
  export DR_TEST_SHARD=$'SHARDSENTINEL\r'
  run_drill; [ "$status" -eq 0 ]
  grep -qx SHARDSENTINEL "$SHARD_LOG"
}

@test "dr drill: unseal shard is executed through stdin only" {
  export DR_TEST_SHARD=SHARDSENTINEL
  run_drill; [ "$status" -eq 0 ]
}

@test "dr drill: generate-root order and cancel are exercised" {
  run_drill; [ "$status" -eq 0 ]
  otp_line="$(grep -n -m1 -- '-generate-otp' "$VLOG" | cut -d: -f1)"
  init_line="$(grep -n -m1 -- ' -init ' "$VLOG" | cut -d: -f1)"
  key_line="$(grep -n -m1 -- ' -nonce ' "$VLOG" | cut -d: -f1)"
  decode_line="$(grep -n -m1 -- '-decode=-' "$VLOG" | cut -d: -f1)"
  revoke_line="$(grep -n -m1 -- 'token revoke -self' "$VLOG" | cut -d: -f1)"
  [ "$otp_line" -lt "$init_line" ]; [ "$init_line" -lt "$key_line" ]; [ "$key_line" -lt "$decode_line" ]; [ "$decode_line" -lt "$revoke_line" ]
}

@test "dr drill: generate-root key failure cancels" {
  export DR_TEST_KEY_FAIL=1
  run_drill
  cancel_found=0
  for cancel_file in /tmp/bats-run-*/test/*/home/cancel-seen; do
    if [[ -f "$cancel_file" ]]; then cancel_found=1; break; fi
  done
  [ "$cancel_found" -eq 1 ]
}

@test "dr drill: deny-list remains absent" {
  run grep -En 'hub-restore|hub_recovery_reconcile|install-.*port-forward|launchctl|cloudflared' bin/dr-drill
  [ "$status" -eq 1 ]
}

@test "dr drill: free disk is measured inside Docker, not on the host" {
  unset DR_DRILL_DOCKER_FREE_GB
  cat > "$STUB_BIN/docker" <<'STUB'
#!/usr/bin/env bash
{ printf 'docker'; printf ' %q' "$@"; printf '\n'; } >> "$PHASE_LOG"
if [[ "$1" == run && " $* " == *" --entrypoint df "* ]]; then
  printf 'Filesystem 1024-blocks Used Available Capacity Mounted on\n'
  printf 'overlay 382205952 23533724 %s 6%% /\n' "$DR_TEST_DOCKER_AVAIL_KB"
fi
if [[ "$1" == ps ]]; then printf 'k3d-dr-drill-serverlb 0.0.0.0:6445->6443/tcp\n'; fi
STUB
  chmod +x "$STUB_BIN/docker"
  DR_TEST_DOCKER_AVAIL_KB=358672228 run_drill
  [ "$status" -eq 0 ]
  DR_TEST_DOCKER_AVAIL_KB=5242880 run_drill
  [ "$status" -eq 2 ]
  [[ "$output" == *"Docker free disk is below 10 GB"* ]]
}

@test "dr drill: a failed clone of the data repo says so" {
  cat > "$STUB_BIN/git" <<'STUB'
#!/usr/bin/env bash
printf 'git'; printf ' %q' "$@"; printf '\n' >> "$PHASE_LOG"
[[ "$1" == clone ]] && exit 128
exit 0
STUB
  chmod +x "$STUB_BIN/git"
  run_drill
  [ "$status" -eq 2 ]
  [[ "$output" == *"cannot clone the snapshots branch"* ]]
  [[ "$output" != *"older than 26h"* ]]
}

@test "dr drill: audit records an unexpected credential and still succeeds" {
  export DR_TEST_EXTRA_CREDENTIAL=1 DR_DRILL_CREDENTIAL_POLICY=audit
  run_drill
  [ "$status" -eq 0 ]
  result="$(find "$HOME/.k3dm/dr-drill" -type f -name '*.json' -print | head -1)"
  jq -e '.credentials_unexpected[] | select(.service == "hidden-service" and .account == "hidden-account")' "$result" >/dev/null
}

@test "dr drill: enforce rejects an unexpected credential before the real security" {
  export DR_TEST_EXTRA_CREDENTIAL=1 DR_DRILL_CREDENTIAL_POLICY=enforce
  run_drill
  [ "$status" -ne 0 ]
  [ "$(grep -c '^security .*hidden-service' "$PHASE_LOG" || true)" -eq 0 ]
  [[ "$output" != *"hidden-service"* ]]
}

@test "dr drill: the credential policy defaults to enforce" {
  unset DR_DRILL_CREDENTIAL_POLICY
  export DR_TEST_EXTRA_CREDENTIAL=1
  run_drill
  [ "$status" -ne 0 ]
  [ "$(grep -c '^security .*hidden-service' "$PHASE_LOG" || true)" -eq 0 ]
}

@test "dr drill: target guard refuses bad contexts and ports before restore or delete" {
  export DR_TEST_CONTEXTS=$'k3d-dr-drill\nk3d-cluster'
  run_drill
  [ "$status" -eq 2 ]; [[ "$output" == *"target is not the drill cluster"* ]]
  [ "$(grep -c '^k3d cluster delete' "$PHASE_LOG" || true)" -eq 0 ]
  : > "$PHASE_LOG"; unset DR_TEST_CONTEXTS; export DR_TEST_SERVER_PORT=6446
  run_drill
  [ "$status" -eq 2 ]; [[ "$output" == *"target is not the drill cluster"* ]]
  [ "$(grep -c '^k3d cluster delete' "$PHASE_LOG" || true)" -eq 0 ]
}
