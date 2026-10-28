#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  ROOT="${ORBSTACK_UPGRADE_REPO_ROOT:-${BATS_TEST_DIRNAME}/../../..}"
  export ORBSTACK_UPGRADE_REPO_ROOT="$ROOT"
  SCRIPT="${ORBSTACK_UPGRADE_SCRIPT:-$ROOT/bin/k3dm-orbstack-upgrade}"
  export HOME="$BATS_TEST_TMPDIR/home"
  export K3DM_ORBSTACK_PUSHGATEWAY_URL=http://127.0.0.1:9
  export ORBSTACK_UPGRADE_WATCHDOG_WAIT=0
  export ORBSTACK_UPGRADE_POLL_INTERVAL=0
  export ORBSTACK_UPGRADE_READY_TIMEOUT=1
  export TEST_CALLS="$HOME/calls"
  mkdir -p "$HOME/bin" "$HOME/.k3dm/hub-data" "$HOME/Library/LaunchAgents"
  date -u +%Y%m%dT%H%M%SZ > "$HOME/.k3dm/hub-data/last-success"
  export PATH="$HOME/bin:/usr/bin:/bin"

  cat >"$HOME/bin/orbctl" <<'SH'
#!/usr/bin/env bash
printf 'orbctl %s\n' "$*" >> "$TEST_CALLS"
case "$*" in
  'update --check') exit "${ORB_CHECK_RC:-3}" ;;
  update) exit "${ORB_UPDATE_RC:-0}" ;;
  *) exit 90 ;;
esac
SH
  cat >"$HOME/bin/docker" <<'SH'
#!/usr/bin/env bash
printf 'docker %s\n' "$*" >> "$TEST_CALLS"
exit 0
SH
  cat >"$HOME/bin/kubectl" <<'SH'
#!/usr/bin/env bash
printf 'kubectl %s\n' "$*" >> "$TEST_CALLS"
case "$*" in
  'config current-context') echo "${KUBE_CONTEXT:-k3d-k3d-cluster}" ;;
  *'metadata.uid'*)
    n=0; [[ -f "$TEST_CALLS.uid" ]] && n="$(<"$TEST_CALLS.uid")"
    n=$((n + 1)); printf '%s\n' "$n" > "$TEST_CALLS.uid"
    if (( n == 1 )); then echo uid-before; else echo "${UID_AFTER:-uid-before}"; fi
    ;;
  *'get nodes -o json'*)
    n=0; [[ -f "$TEST_CALLS.nodes" ]] && n="$(<"$TEST_CALLS.nodes")"
    n=$((n + 1)); printf '%s\n' "$n" > "$TEST_CALLS.nodes"
    count="${NODE_AFTER:-1}"; (( n == 1 )) && count="${NODE_BEFORE:-1}"
    python3 - "$count" <<'PY'
import json,sys
n=int(sys.argv[1])
print(json.dumps({"items":[{"metadata":{"name":f"node-{i}"},"status":{"conditions":[{"type":"Ready","status":"True"}]}} for i in range(n)]}))
PY
    ;;
  *'get secretstores,clustersecretstores -A -o json'*)
    n=0; [[ -f "$TEST_CALLS.stores" ]] && n="$(<"$TEST_CALLS.stores")"
    n=$((n + 1)); printf '%s\n' "$n" > "$TEST_CALLS.stores"
    ready="${STORE_AFTER:-1}"
    (( n == 1 )) && ready="${STORE_BEFORE:-1}"
    (( n == 2 )) && ready=$(( ${STORE_INVALID:-0} == 0 ? 1 : 0 ))
    python3 - "$ready" <<'PY'
import json,sys
ready=sys.argv[1] == "1"
print(json.dumps({"items":[{"status":{"conditions":[{"type":"Ready","status":"True" if ready else "False"}]}}]}))
PY
    ;;
  *'get externalsecrets -A -o json'*)
    n=0; [[ -f "$TEST_CALLS.es" ]] && n="$(<"$TEST_CALLS.es")"
    n=$((n + 1)); printf '%s\n' "$n" > "$TEST_CALLS.es"
    count="${ES_AFTER:-1}"; (( n == 1 )) && count="${ES_BEFORE:-1}"
    python3 - "$count" <<'PY'
import json,sys
n=int(sys.argv[1]); print(json.dumps({"items":[{"status":{"conditions":[{"type":"Ready","status":"True"}]}} for _ in range(n)]}))
PY
    ;;
  *'get applications.argoproj.io -o json'*)
    n=0; [[ -f "$TEST_CALLS.apps" ]] && n="$(<"$TEST_CALLS.apps")"
    n=$((n + 1)); printf '%s\n' "$n" > "$TEST_CALLS.apps"
    count="${APP_AFTER:-1}"; (( n == 1 )) && count="${APP_BEFORE:-1}"
    python3 - "$count" <<'PY'
import json,sys
n=int(sys.argv[1]); print(json.dumps({"items":[{"status":{"health":{"status":"Healthy"}}} for _ in range(n)]}))
PY
    ;;
  *'get pods -A -o json'*) echo '{"items":[]}' ;;
  *'vault status -format=json'*)
    n=0; [[ -f "$TEST_CALLS.vault" ]] && n="$(<"$TEST_CALLS.vault")"
    n=$((n + 1)); printf '%s\n' "$n" > "$TEST_CALLS.vault"
    case "$n" in
      1) sealed="${VAULT_INITIAL_SEALED:-0}" ;;
      2) sealed="${VAULT_AFTER_WATCHDOG_SEALED:-0}" ;;
      *) sealed="${VAULT_VERIFY_SEALED:-0}" ;;
    esac
    printf '{"sealed":%s}\n' "$([[ "$sealed" == 1 ]] && echo true || echo false)"
    [[ "$sealed" != 1 ]] || exit 2
    ;;
  *'get --raw=/readyz'*) echo ok ;;
  *) exit 0 ;;
esac
SH
  cat >"$HOME/bin/security" <<'SH'
#!/usr/bin/env bash
printf 'security %s\n' "$*" >> "$TEST_CALLS"
[[ "${DR_COPY_AVAILABLE:-1}" == 1 && "$*" == 'find-generic-password -s k3dm-vault-unseal-dr -a secrets/vault:count' ]]
SH
  cat >"$HOME/bin/ps" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "${PS_OUTPUT:-}"
SH
  cat >"$HOME/bin/dispatch" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "${DISPATCH_STATUS:-idle}"
SH
  cat >"$HOME/bin/launchctl" <<'SH'
#!/usr/bin/env bash
printf 'launchctl %s\n' "$*" >> "$TEST_CALLS"
exit 0
SH
  cat >"$HOME/bin/nc" <<'SH'
#!/usr/bin/env bash
port="${@: -1}"
case ",${LISTENING_PORTS:-}," in *",$port,"*) exit 0 ;; *) exit 1 ;; esac
SH
  cat >"$HOME/bin/make" <<'SH'
#!/usr/bin/env bash
printf 'make %s\n' "$*" >> "$TEST_CALLS"
exit 0
SH
  cat >"$HOME/bin/curl" <<'SH'
#!/usr/bin/env bash
set -e
printf 'curl %s\n' "$*" >> "$TEST_CALLS.curl-args"
if [[ "$*" == *'/metrics/job/k3dm-orbstack-upgrade' ]]; then
  cat >> "$TEST_CALLS.curl-body"
  exit 0
fi
printf 'k3dm_release_forecast{release="v1.43.9"} 1\n'
for ((i=0; i<${ORBSTACK_TEST_METRICS_LINES:-0}; i++)); do
  printf 'fixture_metric{index="%s"} 1\n' "$i"
done
printf 'complete\n' > "$TEST_CALLS.metrics-complete"
SH
  cat >"$HOME/bin/manager" <<'SH'
#!/usr/bin/env bash
printf 'manager %s\n' "$*" >> "$TEST_CALLS"
exit "${UNSEAL_RC:-0}"
SH
  cat >"$HOME/bin/hostnet" <<'SH'
#!/usr/bin/env bash
printf 'hostnet %s\n' "$*" >> "$TEST_CALLS"
exit 0
SH
  export ORBSTACK_DISPATCH_BIN="$HOME/bin/dispatch"
  export ORBSTACK_UPGRADE_MANAGER_BIN="$HOME/bin/manager"
  export ORBSTACK_UPGRADE_HOSTNET_BIN="$HOME/bin/hostnet"
  chmod +x "$HOME/bin/"*
}

_fresh_stamp_ago() {
  if date -j -v-25H +%Y%m%dT%H%M%SZ >/dev/null 2>&1; then
    date -u -j -v-25H +%Y%m%dT%H%M%SZ
  else
    date -u -d '25 hours ago' +%Y%m%dT%H%M%SZ
  fi
}

_run_bounded() {
  run python3 - "$@" <<'PY'
import os
import signal
import subprocess
import sys

child = subprocess.Popen(sys.argv[1:], stdin=subprocess.DEVNULL,
                         stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                         start_new_session=True)
try:
    output, _ = child.communicate(timeout=float(os.environ.get("ORBSTACK_TEST_TIMEOUT_SECONDS", "30")))
except subprocess.TimeoutExpired:
    try:
        os.killpg(child.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    try:
        output, _ = child.communicate(timeout=2)
    except subprocess.TimeoutExpired as error:
        output = error.output or b""
        child.stdout.close()
        child.wait(timeout=2)
    sys.stdout.buffer.write(output)
    print("fixture command timed out", flush=True)
    raise SystemExit(124)
sys.stdout.buffer.write(output)
raise SystemExit(child.returncode)
PY
}

_run_tty() {
  local answer="$1"
  if ! command -v script >/dev/null 2>&1; then
    skip "pseudo-terminal utility 'script' is unavailable"
  fi
  local done_file="$BATS_TEST_TMPDIR/tty-done"
  rm -f "$done_file"
  local feed='{ printf "%s\n" "$1"; for _ in $(seq 600); do [[ -e "$3" ]] && break; sleep 0.1; done; }'
  local child='"$0"; rc=$?; : > "$1"; exit "$rc"'
  if [[ "$(uname -s)" == Darwin ]]; then
    _run_bounded bash -c "$feed"' | script -q /dev/null bash -c '"'$child'"' "$2" "$3"' _ "$answer" "$SCRIPT" "$done_file"
  else
    _run_bounded bash -c "$feed"' | script -q -e -c "bash -c '"'$child'"' \"$2\" \"$3\"" /dev/null' _ "$answer" "$SCRIPT" "$done_file"
  fi
}

_report() { find "$HOME/.k3dm/orbstack-upgrade" -type f -name '*.json' -print -quit; }

@test "orbstack upgrade: fresh compact last-success timestamp passes preflight" {
  run env DRY_RUN=1 "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *'preflight: passed'* ]]
  report="$(_report)"
  jq -e '.preflight | has("vault_0_uid") and has("host_network_pods")' "$report"
}

@test "orbstack upgrade: refuses a compact last-success timestamp older than 24 hours" {
  _fresh_stamp_ago > "$HOME/.k3dm/hub-data/last-success"
  run env DRY_RUN=1 "$SCRIPT"
  [ "$status" -eq 2 ]
  [[ "$output" == *'older than 24 hours'* ]]
}

@test "orbstack upgrade: refuses a missing or malformed last-success marker" {
  rm "$HOME/.k3dm/hub-data/last-success"
  run env DRY_RUN=1 "$SCRIPT"
  [ "$status" -eq 2 ]
  [[ "$output" == *'timestamp is missing'* ]]
  printf 'not-a-timestamp\n' > "$HOME/.k3dm/hub-data/last-success"
  run env DRY_RUN=1 "$SCRIPT"
  [ "$status" -eq 2 ]
  [[ "$output" == *'timestamp is invalid'* ]]
}

@test "orbstack upgrade: FORCE overrides only no-update status" {
  run env ORB_CHECK_RC=0 FORCE=1 DRY_RUN=1 "$SCRIPT"
  [ "$status" -eq 0 ]
  run env ORB_CHECK_RC=1 FORCE=1 DRY_RUN=1 "$SCRIPT"
  [ "$status" -eq 2 ]
  [[ "$output" == *'orbctl update --check failed'* ]]
}

@test "orbstack upgrade: refuses active dispatch and lifecycle work" {
  run env DISPATCH_STATUS='state: running' DRY_RUN=1 "$SCRIPT"
  [ "$status" -eq 2 ]
  [[ "$output" == *'Codex dispatch task is running'* ]]
  run env PS_OUTPUT='make platform-ops' DRY_RUN=1 "$SCRIPT"
  [ "$status" -eq 2 ]
  [[ "$output" == *'lifecycle or platform-ops command is running'* ]]
}

@test "orbstack upgrade: refuses wrong context or absent DR copy" {
  run env KUBE_CONTEXT=other-cluster DRY_RUN=1 "$SCRIPT"
  [ "$status" -eq 2 ]
  [[ "$output" == *'expected k3d-k3d-cluster'* ]]
  run env DR_COPY_AVAILABLE=0 DRY_RUN=1 "$SCRIPT"
  [ "$status" -eq 2 ]
  [[ "$output" == *'DR unseal copy is absent'* ]]
}

@test "orbstack upgrade: refuses a real run without a TTY" {
  _run_bounded "$SCRIPT"
  [ "$status" -eq 2 ]
  [[ "$output" == *'interactive TTY required'* ]]
  [[ "$output" != *'Type yes to continue'* ]]
  [[ "$output" != *'confirmation was not yes'* ]]
  run grep '^orbctl update$' "$TEST_CALLS"
  [ "$status" -ne 0 ]
}

@test "orbstack upgrade: bounded fixture runner stops a stalled fake command" {
  cat > "$HOME/bin/stall" <<'SH'
#!/usr/bin/env bash
printf 'started\n' > "$TEST_CALLS.stalled"
sleep 60
SH
  chmod +x "$HOME/bin/stall"
  export ORBSTACK_TEST_TIMEOUT_SECONDS=1
  _run_bounded "$HOME/bin/stall"
  [ "$status" -eq 124 ]
  [[ "$output" == *'fixture command timed out'* ]]
  [ -f "$TEST_CALLS.stalled" ]
}

@test "orbstack upgrade: typed no refuses without running orbctl update" {
  _run_tty no
  [ "$status" -eq 2 ]
  [[ "$output" == *'confirmation was not yes'* ]]
  run grep '^orbctl update$' "$TEST_CALLS"
  [ "$status" -ne 0 ]
}

@test "orbstack upgrade: watchdog unseals when Vault stays sealed and skips DR when it unseals" {
  export VAULT_INITIAL_SEALED=1 VAULT_AFTER_WATCHDOG_SEALED=1 VAULT_VERIFY_SEALED=0
  _run_tty yes
  [ "$status" -eq 0 ]
  grep -q '^manager hub_data_unseal_dr$' "$TEST_CALLS"
  export VAULT_INITIAL_SEALED=1 VAULT_AFTER_WATCHDOG_SEALED=0 VAULT_VERIFY_SEALED=0
  rm -f "$TEST_CALLS" "$TEST_CALLS".*
  _run_tty yes
  [ "$status" -eq 0 ]
  [[ "$output" == *'vault-unseal: skipped-watchdog'* ]]
  run ! grep -q '^manager hub_data_unseal_dr$' "$TEST_CALLS"
}

@test "orbstack upgrade: repoints only after UID change and an invalid SecretStore" {
  export UID_AFTER=uid-after STORE_INVALID=1
  _run_tty yes
  [ "$status" -eq 0 ]
  grep -q '^manager hub_data_repoint_vault k3d-k3d-cluster$' "$TEST_CALLS"
  rm -f "$TEST_CALLS" "$TEST_CALLS".*
  export UID_AFTER=uid-before STORE_INVALID=1
  _run_tty yes
  [ "$status" -eq 0 ]
  run grep '^manager hub_data_repoint_vault' "$TEST_CALLS"
  [ "$status" -ne 0 ]
  rm -f "$TEST_CALLS" "$TEST_CALLS".*
  export UID_AFTER=uid-after STORE_INVALID=0
  _run_tty yes
  [ "$status" -eq 0 ]
  run grep '^manager hub_data_repoint_vault' "$TEST_CALLS"
  [ "$status" -ne 0 ]
}

@test "orbstack upgrade: repairs drift, republishes metrics, and kicks only dead port-forwards once" {
  mkdir -p "$HOME/Library/LaunchAgents"
  for pair in 'hub-pushgateway 19094:9091' 'prometheus 19091:9090'; do
    read -r name mapping <<< "$pair"
    cat > "$HOME/Library/LaunchAgents/com.k3d-manager.${name}-port-forward.plist" <<PLIST
<?xml version="1.0"?><plist version="1.0"><dict><key>ProgramArguments</key><array><string>kubectl</string><string>port-forward</string><string>${mapping}</string></array></dict></plist>
PLIST
  done
  export LISTENING_PORTS=19091
  _run_tty yes
  [ "$status" -eq 0 ]
  grep -q '^hostnet --fix$' "$TEST_CALLS"
  grep -q '^make dispatch-metrics$' "$TEST_CALLS"
  grep -q '^launchctl kickstart -k gui/.*/com.k3d-manager.hermes$' "$TEST_CALLS"
  [ "$(grep -c 'com.k3d-manager.hub-pushgateway-port-forward$' "$TEST_CALLS")" -eq 1 ]
  run grep 'com.k3d-manager.prometheus-port-forward$' "$TEST_CALLS"
  [ "$status" -ne 0 ]
  grep -q 'http://127.0.0.1:9/metrics/job/k3dm-orbstack-upgrade' "$TEST_CALLS.curl-args"
  grep -q '^k3dm_orbstack_upgrade_last_success 1$' "$TEST_CALLS.curl-body"
  grep -q '^k3dm_orbstack_upgrade_last_timestamp_seconds ' "$TEST_CALLS.curl-body"
}

@test "orbstack upgrade: a hub that is ready when the deadline passes is not a failed upgrade" {
  export ORBSTACK_UPGRADE_READY_TIMEOUT=0
  _run_tty yes
  [ "$status" -eq 0 ]
  [[ "$output" != *'upgrade failed'* ]]
}

@test "orbstack upgrade: forecast probe drains large metrics producer to completion" {
  export ORBSTACK_TEST_METRICS_LINES=20000
  _run_tty yes
  [ -f "$TEST_CALLS.metrics-complete" ]
  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_CALLS.metrics-complete")" = complete ]
  jq -e '.result == "success" and .verify.release_forecast_present == true and
    (.verify.regressions | index("release-forecast")) == null' "$(_report)"
}

@test "orbstack upgrade: reports empty regressions for equal counts and names a count drop" {
  _run_tty yes
  [ "$status" -eq 0 ]
  report="$(_report)"
  jq -e '.result == "success" and .verify.regressions == []' "$report"
  grep -q '^k3dm_orbstack_upgrade_last_success 1$' "$TEST_CALLS.curl-body"

  rm -f "$TEST_CALLS" "$TEST_CALLS".* "$HOME/.k3dm/orbstack-upgrade/"*.json
  export NODE_BEFORE=2 NODE_AFTER=1
  _run_tty yes
  [ "$status" -eq 1 ]
  [[ "$output" == *'failed:nodes-ready'* ]]
  report="$(_report)"
  jq -e '.result == "failed" and (.verify.regressions | index("nodes-ready")) != null' "$report"
  grep -q '^k3dm_orbstack_upgrade_last_success 0$' "$TEST_CALLS.curl-body"
  unset NODE_BEFORE NODE_AFTER

  for pair in STORE:1:0:secretstores-valid ES:2:1:externalsecrets-synced APP:2:1:argocd-healthy; do
    IFS=: read -r kind before after check <<< "$pair"
    rm -f "$TEST_CALLS" "$TEST_CALLS".* "$HOME/.k3dm/orbstack-upgrade/"*.json
    export "${kind}_BEFORE=$before" "${kind}_AFTER=$after"
    _run_tty yes
    [ "$status" -eq 1 ]
    [[ "$output" == *"failed:${check}"* ]]
    unset "${kind}_BEFORE" "${kind}_AFTER"
  done
}

@test "orbstack upgrade: failed unseal does not stop later recovery and verification" {
  export VAULT_INITIAL_SEALED=1 VAULT_AFTER_WATCHDOG_SEALED=1 VAULT_VERIFY_SEALED=0 UNSEAL_RC=1
  _run_tty yes
  [ "$status" -eq 1 ]
  [[ "$output" == *'vault-unseal: failed'* ]]
  grep -q '^hostnet --fix$' "$TEST_CALLS"
  grep -q '^make dispatch-metrics$' "$TEST_CALLS"
  grep -q '^launchctl kickstart -k gui/.*/com.k3d-manager.hermes$' "$TEST_CALLS"
  grep -q '^k3dm_orbstack_upgrade_last_success 0$' "$TEST_CALLS.curl-body"
  jq -e '.result == "failed" and .verify.recovery_failures == 1' "$(_report)"
}

@test "orbstack upgrade: never deletes Kubernetes objects or reads Keychain values" {
  _run_tty yes
  [ "$status" -eq 0 ]
  run grep '^kubectl .* delete ' "$TEST_CALLS"
  [ "$status" -ne 0 ]
  run grep '^security .* -w' "$TEST_CALLS"
  [ "$status" -ne 0 ]
}

@test "orbstack upgrade: destructive and credential guard assertions are effective" {
  run grep -Eq 'deploy_vault|security .* -w|kubectl .* delete (pod|secret)' "$SCRIPT"
  [ "$status" -ne 0 ]
}
