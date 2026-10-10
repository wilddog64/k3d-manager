#!/usr/bin/env bats
bats_require_minimum_version 1.5.0

setup() {
  unset DR_DRILL_CLUSTER DR_DRILL_CONTEXT DR_TEST_CLUSTER_LIST DR_TEST_HOST DR_TEST_NOT_READY DR_TEST_CURL_RC DR_TEST_EXEC_FAIL DR_TEST_UNSEAL_FAIL DR_TEST_RESTORE_FAIL
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
printf 'hub-up %s\n' "${DR_DRILL_CONTEXT}|${DR_DRILL_CLUSTER}|${KUBECONFIG}|${DR_DRILL_MODE}" >> "$PHASE_LOG"
[[ "${DR_TEST_HUB_UP_FAIL:-0}" == 1 ]] && exit 1
exit 0
STUB
  cat > "$TEST_ROOT/restore" <<'STUB'
#!/usr/bin/env bash
printf '%s|%s|%s\n' "$DR_DRILL_CONTEXT" "$DR_DRILL_CLUSTER" "$DR_DRILL_RESTORE_STAGE" >> "$RESTORE_LOG"
[[ "${DR_TEST_RESTORE_FAIL:-0}" == 1 ]] && exit 1
mkdir -p "$DR_DRILL_RESTORE_STAGE"
printf '%s\n' '{"vault_paths":["secret/app"],"keycloak_realm_user_count":1,"ldap_entry_count":2}' > "$DR_DRILL_RESTORE_STAGE/inventory.json"
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
printf 'docker'; printf ' %q' "$@"; printf '\n' >> "$PHASE_LOG"
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
  *'secrets/vault:count'*) printf '1' ;;
  *'secrets/vault:shard1'*) printf '%s' "${DR_TEST_SHARD:-SHARD-SENTINEL}" ;;
  *) printf '%s' "${DR_TEST_SHARD:-SHARD-SENTINEL}" ;;
esac
STUB
  cat > "$STUB_BIN/secret-tool" <<'STUB'
#!/usr/bin/env bash
case "$*" in
  *'name secrets/vault:count'*) printf 1 ;;
  *'name secrets/vault:shard1'*) printf '%s' "${DR_TEST_SHARD:-SHARD-SENTINEL}" ;;
  *) printf '%s' "${DR_TEST_SHARD:-SHARD-SENTINEL}" ;;
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
if [[ "$args" == *' run dr-egress-check-'* ]]; then exit 0
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
[[ "$*" == *SHARD-SENTINEL* || "$*" == *ENCODED-SENTINEL* ]] && exit 97
case "$*" in
  *'operator unseal -'*) [[ "$*" == *SHARD-SENTINEL* ]] && exit 97; cat >> "$SHARD_LOG"; [[ "${DR_TEST_UNSEAL_FAIL:-0}" == 1 ]] && exit 1; exit 0 ;;
  *'-generate-otp'*) printf '{"otp":"OTP-SENTINEL"}' ;;
  *'-init'*) printf '{"nonce":"NONCE"}' ;;
  *'-decode=-'*) [[ "$*" == *OTP-SENTINEL* || "$*" == *ENCODED-SENTINEL* ]] && exit 97; cat >> "$SHARD_LOG"; printf ROOT-TOKEN ;;
  *'generate-root'*'-format=json -'*) [[ "${DR_TEST_KEY_FAIL:-0}" == 1 ]] && exit 1; cat >> "$SHARD_LOG"; printf '{"encoded_token":"ENCODED-SENTINEL"}' ;;
  *'generate-root -cancel'*) : > "${HOME}/cancel-seen" ;;
  *'status'*) printf '{"sealed":false}' ;;
  *'kv list'*) printf '{"data":["secret/app"]}' ;;
  *'token revoke -self'*) : ;;
esac
STUB
  chmod +x "$STUB_BIN"/*
  chmod +x "$STUB_BIN"/* "$TEST_ROOT/hub-up" "$TEST_ROOT/restore"
  export PATH="$STUB_BIN:$PATH" DR_DRILL_HUB_UP_CMD="$TEST_ROOT/hub-up" DR_DRILL_RESTORE_CMD="$TEST_ROOT/restore"
}

run_drill() { run "$PWD/bin/dr-drill" || true; }

@test "dr drill: full green run follows phases and writes success" {
  run_drill
  [ "$status" -eq 0 ]
  for pair in "1 2" "2 3" "3 4" "4 5" "5 6"; do read -r before after <<<"$pair"; [ "$(grep -n "Phase $before/6" <<<"$output" | cut -d: -f1)" -lt "$(grep -n "Phase $after/6" <<<"$output" | cut -d: -f1)" ]; done
  result="$(find "$HOME/.k3dm/dr-drill" -type f -name '*.json' -print | head -1)"
  [ "$(jq -r .success "$result")" = true ]
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
  run_drill; [ "$status" -ne 0 ]; [ "$(grep -c 'operator unseal' "$VLOG" || true)" -eq 0 ]; [ "$(grep -c 'delete pod dr-egress-check-secrets' "$KLOG" || true)" -eq 1 ]; [ "$(grep -c 'delete pod dr-egress-check-identity' "$KLOG" || true)" -eq 1 ]
  unset DR_TEST_NOT_READY; export DR_TEST_CURL_RC=7
  : > "$KLOG"; : > "$VLOG"
  run_drill; [ "$status" -eq 0 ]; [ "$(grep -c 'image=curlimages/curl:8.10.1' "$KLOG" || true)" -eq 2 ]; [ "$(grep -c 'delete pod dr-egress-check-secrets' "$KLOG" || true)" -eq 1 ]; [ "$(grep -c 'delete pod dr-egress-check-identity' "$KLOG" || true)" -eq 1 ]
  : > "$KLOG"; : > "$VLOG"; export DR_TEST_EXEC_FAIL=1
  run_drill; [ "$status" -ne 0 ]; [ "$(grep -c 'operator unseal' "$VLOG" || true)" -eq 0 ]; [ "$(grep -c 'delete pod dr-egress-check-secrets' "$KLOG" || true)" -eq 1 ]; [ "$(grep -c 'delete pod dr-egress-check-identity' "$KLOG" || true)" -eq 1 ]
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
  [ "$(grep -c 'operator unseal' "$VLOG")" -eq 1 ]
}

@test "dr drill: a vault-0 that never runs fails unseal with a reason and no unseal call" {
  export DR_TEST_VAULT_PENDING_POLLS=1000 DR_DRILL_POLL_S=0 DR_DRILL_VAULT_START_S=1
  run_drill; [ "$status" -ne 0 ]
  [[ "$output" == *"vault-0 is not Running after 1s (phase: Pending)"* ]]
  [ "$(grep -c 'operator unseal' "$VLOG" || true)" -eq 0 ]
  result="$(find "$HOME/.k3dm/dr-drill" -type f -name '*.json' -print | head -1)"; [ "$(jq -r .failed "$result")" = unseal ]
}

@test "dr drill: unseal shard is executed through stdin only" {
  export DR_TEST_SHARD=SHARD-SENTINEL
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
  run ! grep -En 'hub-restore|hub_recovery_reconcile|install-.*port-forward|launchctl|cloudflared' bin/dr-drill
}

@test "dr drill: free disk is measured inside Docker, not on the host" {
  unset DR_DRILL_DOCKER_FREE_GB
  cat > "$STUB_BIN/docker" <<'STUB'
#!/usr/bin/env bash
printf 'docker'; printf ' %q' "$@"; printf '\n' >> "$PHASE_LOG"
if [[ "$1" == run && " $* " == *" --entrypoint df "* ]]; then
  printf 'Filesystem 1024-blocks Used Available Capacity Mounted on\n'
  printf 'overlay 382205952 23533724 %s 6%% /\n' "$DR_TEST_DOCKER_AVAIL_KB"
fi
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
