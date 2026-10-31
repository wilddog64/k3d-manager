#!/usr/bin/env bats

setup() {
  REPO="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
  WORK="$(mktemp -d "${BATS_TEST_TMPDIR}/hub-cutover.XXXXXX")"
  ROOT="$WORK/repo"
  mkdir -p "$WORK/stub" "$WORK/home/Library/LaunchAgents" "$ROOT/bin" "$ROOT/scripts/etc/machine"
  cp "${HUB_CUTOVER_SOURCE:-$REPO/bin/hub-cutover}" "$ROOT/bin/hub-cutover"
  cp "$REPO/scripts/etc/machine/hub-push-forwards.list" "$ROOT/scripts/etc/machine/"
  cp "$REPO/scripts/etc/machine/hub-singletons.list" "$ROOT/scripts/etc/machine/"
  export HOME="$WORK/home" PATH="$WORK/stub:/opt/homebrew/bin:/usr/bin:/bin" CALLS="$WORK/calls"
  export HUB_CUTOVER_STATE_DIR="$WORK/state" HUB_NEW_STATE_DIR="$WORK/new-state" HUB_OLD_HOST=m4-air.local HUB_NEW_HOST=m5-air.local
  [[ "$HOME" == "$WORK/home" && "$HUB_CUTOVER_STATE_DIR" == "$WORK/state" ]]
  export OLD_HOME="$WORK/old-home"
  mkdir -p "$OLD_HOME/Library/LaunchAgents"
  python3 - "$OLD_HOME" <<'PYCODE'
import os, plistlib, sys
for label in ("hub-pushgateway-port-forward", "hub-loki-port-forward"):
    with open(os.path.join(sys.argv[1], "Library/LaunchAgents/com.k3d-manager." + label + ".plist"), "wb") as f:
        plistlib.dump({"Label": "com.k3d-manager." + label, "ProgramArguments": ["kubectl"], "StandardOutPath": "/tmp/forward.log"}, f)
PYCODE
  export HUB_CUTOVER_CONTROLLER_WAIT_S=0
  export HUB_CUTOVER_TTY="$WORK/tty" HUB_CUTOVER_VERIFY_WAIT=0 HUB_CUTOVER_VERIFY_TRIES=3 HUB_CUTOVER_FORWARD_WAIT=0
  printf 'cutover\n' > "$HUB_CUTOVER_TTY"
  mkdir -p "$HUB_NEW_STATE_DIR"
  printf '{"status":"pass","timestamp":"%s","stages":[],"checks":{}}\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" > "$HUB_NEW_STATE_DIR/hub-new-report.json"
  cat > "$WORK/stub/launchctl" <<'STUB'
#!/usr/bin/env bash
if [[ "$HOME" == "$OLD_HOME" ]]; then
  printf 'remote-launchctl %s\n' "$*" >> "$CALLS"
  # Exit codes captured on m4-air 2026-10-31T11:57Z for an unloaded label: bootout 3, print 113.
  linger="$CALLS.linger"
  case "$1" in
    bootout) [[ "${STUB_REMOTE_NOT_LOADED:-0}" == 0 ]] || { echo 'Boot-out failed: 3: No such process' >&2; exit 3; }
      echo "${STUB_REMOTE_LINGER:-0}" > "$linger" ;;
    print) n="$(cat "$linger" 2>/dev/null || echo 0)"; (( n > 0 )) || exit 113; echo $((n - 1)) > "$linger" ;;
    bootstrap) n="$(cat "$linger" 2>/dev/null || echo 0)"; (( n == 0 )) || { echo 'Bootstrap failed: 5: Input/output error' >&2; exit 5; } ;;
  esac
  exit 0
fi
printf 'launchctl %s\n' "$*" >> "$CALLS"
label="${*: -1}"
label="${label##*/}"
if [[ "$1" == print ]]; then
  if [[ -f "$LOADED_FILE" ]] && grep -Fxq "$label" "$LOADED_FILE"; then
    echo 'state = running'; exit 0
  fi
  echo "Could not find service \"$label\" in domain for user gui: 501" >&2; exit 113
fi
if [[ "$1" == bootstrap ]]; then label="${label##*/com.k3d-manager.}"; printf '%s\n' "${label%.plist}" >> "$LOADED_FILE"; fi
if [[ "$1" == bootout ]]; then sed -i.bak "/^${label##*/com.k3d-manager.}$/d" "$LOADED_FILE"; rm -f "$LOADED_FILE.bak"; fi
exit 0
STUB
  cat > "$WORK/stub/ssh" <<'STUB'
#!/usr/bin/env bash
opts=""
while [[ "$1" == -o ]]; do opts+="$2 "; shift 2; done
[[ "$opts" == *BatchMode=yes* && "$opts" == *ClearAllForwardings=yes* ]] || { echo "ssh without BatchMode/ClearAllForwardings" >&2; exit 97; }
[[ "${STUB_SSH_DENIED:-0}" == 0 ]] || exit 255
printf 'ssh host=%s command=%s\n' "$1" "$2" >> "$CALLS"
if [[ "$2" == ssh\ -o* ]]; then exit "${STUB_FORWARD_SSH_DENIED:-0}"; fi
if [[ "$2" == python3\ -* ]]; then HOME="$OLD_HOME" bash -c "$2"; exit $?; fi
if [[ "$2" == curl\ -* ]]; then
  if [[ -n "${STUB_FORWARD_FAIL_FIRST:-}" ]]; then
    n=$(( $(cat "$CALLS.forward-probes" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$CALLS.forward-probes"
    (( n > STUB_FORWARD_FAIL_FIRST )) && echo OK || echo bad; exit 0
  fi
  echo "${STUB_FORWARD_BODY:-OK}"; exit 0
fi
if [[ "$2" == *'get statefulset'* ]]; then
  if [[ "$2" == *readyReplicas* ]]; then echo "${STUB_OLD_READY:-0}"; else cat "$WORK_OLD_REPLICAS"; fi
  exit 0
fi
if [[ "$2" == *'get pods'* ]]; then [[ "${STUB_OLD_POD:-0}" == 0 ]] || echo pod/controller; exit 0; fi
if [[ "$2" == *'scale statefulset'* ]]; then echo "${2##*--replicas=}" > "$WORK_OLD_REPLICAS"; exit 0; fi
if [[ "$2" == *'test -f'* ]]; then exit 0; fi
if [[ "$2" == *'launchctl print'* ]]; then
  label="${2##*com.k3d-manager.}"
  label="${label%\"*}"
  if [[ -f "$OLD_LOADED_FILE" ]] && grep -Fxq "$label" "$OLD_LOADED_FILE"; then echo 'state = running'; exit 0; fi
  exit 113
fi
if [[ "$2" == *'launchctl bootout'* ]]; then
  label="${2##*com.k3d-manager.}"; label="${label%\"*}"
  if [[ "${STUB_OLD_STUCK:-0}" != 1 ]]; then sed -i.bak "/^$label$/d" "$OLD_LOADED_FILE"; rm -f "$OLD_LOADED_FILE.bak"; fi
fi
exit 0
STUB
  export WORK_OLD_REPLICAS="$WORK/old-replicas"
  echo 1 > "$WORK_OLD_REPLICAS"
  mkdir -p "$ROOT/scripts" "$HOME/.kube"
  cat > "$WORK/stub/kubectl" <<'STUB'
#!/usr/bin/env bash
printf 'kubectl %s\n' "$*" >> "$CALLS"
case "$*" in
  *'config get-contexts'*) exit "${STUB_NO_CONTEXT:-0}" ;;
  *'get statefulset'*readyReplicas*) echo "${STUB_NEW_READY:-0}" ;;
  *'get statefulset'*) echo 0 ;;
  *'get pods'*) [[ "${STUB_NEW_POD:-0}" == 0 ]] || echo pod/controller ;;
  *'get application'*) [[ "${STUB_BAD_ESO:-0}" == 0 ]] || exit 1; echo '{"status":{"sync":{"status":"Synced"},"health":{"status":"Healthy"}}}' ;;
  # Real kubectl, M5 hub 2026-10-30 hub-cutover verify: a name together with -l is refused.
  *'get secret '[a-z]*' -l '*) echo 'error: name cannot be provided when a selector is specified' >&2; exit 1 ;;
  *'get secret'*) [[ "${STUB_NO_REGISTRATION:-0}" == 0 ]] || { echo secret/ubuntu-k3s-app-cluster; exit 0; }; printf '%s\n' secret/cluster-ubuntu-hostinger secret/ubuntu-k3s-app-cluster ;;
esac
STUB
  cat > "$WORK/stub/scp" <<'STUB'
#!/usr/bin/env bash
printf 'scp %s\n' "$*" >> "$CALLS"
: > "${@: -1}"
STUB
  cat > "$ROOT/scripts/k3d-manager" <<'STUB'
#!/usr/bin/env bash
printf 'refresh_registration %s %s\n' "$CLUSTER_PROVIDER" "$*" >> "$CALLS"
STUB
  chmod +x "$ROOT/scripts/k3d-manager"
  for cmd in make curl cloudflared; do
    cat > "$WORK/stub/$cmd" <<STUB
#!/usr/bin/env bash
printf '$cmd %s\\n' "\$*" >> "\$CALLS"
STUB
    if [[ "$cmd" == curl ]]; then cat >> "$WORK/stub/$cmd" <<'STUB'
if [[ "$*" == *frontend* ]]; then echo 200; else echo 401; fi
STUB
    elif [[ "$cmd" == cloudflared ]]; then cat >> "$WORK/stub/$cmd" <<'STUB'
n="$(grep -c '^cloudflared ' "$CALLS")"
echo 'NAME:     k3d-manager'
echo 'CONNECTOR ID                         CREATED              ARCHITECTURE VERSION   ORIGIN IP    EDGE'
echo '19340c68-85f8-4550-94a1-8b0012b69cd7 2026-10-30T01:32:57Z darwin_arm64 2026.10.3 216.9.31.189 1xsea01, 2xsea08, 1xsea10'
if (( n <= ${STUB_TWO_CONNECTORS_CALLS:-0} )); then
  echo '7a1c0e52-1111-4222-8333-944455556666 2026-10-30T20:01:02Z darwin_arm64 2026.10.6 10.0.0.2     1xsea02'
fi
echo '2026-10-30T19:56:45Z WRN Your version 2026.10.6 is outdated. We recommend upgrading it to 2026.10.7'
STUB
    fi
  done
  cat > "$ROOT/bin/k3dm-hermes" <<'STUB'
#!/usr/bin/env bash
printf 'hermes %s\n' "$*" >> "$CALLS"
exit 0
STUB
  chmod +x "$ROOT/bin/k3dm-hermes"
  cat > "$WORK/stub/hostname" <<'STUB'
#!/usr/bin/env bash
echo m5-air
STUB
  cat > "$WORK/stub/id" <<'STUB'
#!/usr/bin/env bash
echo 501
STUB
  for cmd in hostname id; do chmod +x "$WORK/stub/$cmd"; done
  chmod +x "$WORK/stub/"*
  export LOADED_FILE="$WORK/loaded" OLD_LOADED_FILE="$WORK/old-loaded"
  : > "$LOADED_FILE"; : > "$OLD_LOADED_FILE"
  while IFS='|' read -r label _; do
    [[ -n "$label" && "$label" != \#* ]] || continue
    : > "$HOME/Library/LaunchAgents/com.k3d-manager.$label.plist"
  done < "$ROOT/scripts/etc/machine/hub-singletons.list"
}

teardown() { rm -rf "$WORK"; }

@test "M7: dry run prints full plan and changes nothing" {
  run env DRY_RUN=1 "$ROOT/bin/hub-cutover"
  [ "$status" -eq 0 ]
  [[ "$output" == *cloudflare-tunnel* ]]
  run grep -Eq "scale statefulset|^scp |^refresh_registration |launchctl (bootout|bootstrap)" "$CALLS"
  [ "$status" -eq 1 ]
  [ ! -e "$HUB_CUTOVER_STATE_DIR" ]
}

@test "M7: wrong confirmation changes nothing" {
  printf 'nope\n' > "$HUB_CUTOVER_TTY"
  run "$ROOT/bin/hub-cutover"
  [ "$status" -eq 1 ]
  run grep -Eq "scale statefulset|^scp |^refresh_registration |launchctl (bootout|bootstrap)" "$CALLS"
  [ "$status" -eq 1 ]
  [ ! -e "$HUB_CUTOVER_STATE_DIR" ]
}

@test "M7: stale report refuses before changing anything" {
  printf '{"status":"pass","timestamp":"2000-01-01T00:00:00Z"}\n' > "$HUB_NEW_STATE_DIR/hub-new-report.json"
  run "$ROOT/bin/hub-cutover"
  [ "$status" -ne 0 ]
  [ ! -s "$CALLS" ]
}

@test "M8/N6: old host not quiet blocks all M5 loading and offers rollback" {
  export STUB_OLD_STUCK=1
  printf 'webhook\n' > "$OLD_LOADED_FILE"
  run "$ROOT/bin/hub-cutover"
  [ "$status" -ne 0 ]
  [[ "$output" == *'hub-cutover-rollback'* ]]
  run grep -q '^launchctl bootstrap' "$CALLS"
  [ "$status" -eq 1 ]
}

@test "M8: happy cutover records remote bootout, then loads M5 in list order" {
  printf 'webhook\ncloudflare-tunnel\n' > "$OLD_LOADED_FILE"
  run "$ROOT/bin/hub-cutover"
  [ "$status" -eq 0 ]
  grep -q '^ssh host=m4-air.local command=.*launchctl bootout' "$CALLS"
  [ "$(sed -n '1p' "$HUB_CUTOVER_STATE_DIR/stopped-on-old")" = com.k3d-manager.cloudflare-tunnel ]
  [ "$(sed -n '2p' "$HUB_CUTOVER_STATE_DIR/stopped-on-old")" = com.k3d-manager.webhook ]
  [ "$(grep '^ssh host=m4-air.local command=.*launchctl bootout' "$CALLS" | sed -n '1p' | grep -c cloudflare-tunnel)" -eq 1 ]
  [ "$(grep '^ssh host=m4-air.local command=.*launchctl bootout' "$CALLS" | sed -n '2p' | grep -c webhook)" -eq 1 ]
  expected="$(cut -d'|' -f1 "$ROOT/scripts/etc/machine/hub-singletons.list" | sed '/^#/d;/^$/d' | sed 's|^|com.k3d-manager.|')"
  actual="$(sed -n '/^launchctl bootstrap/p' "$CALLS" | sed -E 's|.*com.k3d-manager.([^/ ]+).plist$|com.k3d-manager.\1|')"
  [ "$actual" = "$expected" ]
  [ "$(grep -n 'launchctl bootout' "$CALLS" | head -1 | grep -c 'cloudflare-tunnel')" -eq 1 ]
}

@test "M9: rollback reloads exactly recorded old labels" {
  mkdir -p "$HUB_CUTOVER_STATE_DIR"
  printf 'com.k3d-manager.webhook\ncom.k3d-manager.cloudflare-tunnel\n' > "$HUB_CUTOVER_STATE_DIR/stopped-on-old"
  printf 'rollback\n' > "$HUB_CUTOVER_TTY"
  run "$ROOT/bin/hub-cutover" --rollback
  [ "$status" -eq 0 ]
  [ "$(grep -c '^ssh host=m4-air.local command=launchctl bootstrap' "$CALLS")" -eq 2 ]
  run grep -q '^launchctl bootstrap' "$CALLS"
  [ "$status" -eq 1 ]
  [[ "$(grep '^ssh .*bootstrap' "$CALLS" | tr '\n' ' ')" == *'com.k3d-manager.webhook'*'com.k3d-manager.cloudflare-tunnel'* ]]
}

@test "M9: rollback unloads the M5 singletons in reverse order before reloading the old host" {
  mkdir -p "$HUB_CUTOVER_STATE_DIR"
  printf 'com.k3d-manager.webhook\n' > "$HUB_CUTOVER_STATE_DIR/stopped-on-old"
  printf 'com.k3d-manager.ssh-tunnel\ncom.k3d-manager.ssh-tunnel-vault\ncom.k3d-manager.cloudflare-tunnel\n' > "$LOADED_FILE"
  printf 'rollback\n' > "$HUB_CUTOVER_TTY"
  run "$ROOT/bin/hub-cutover" --rollback
  [ "$status" -eq 0 ]
  [ ! -s "$LOADED_FILE" ]
  [ "$(grep '^launchctl bootout' "$CALLS" | head -1 | grep -c cloudflare-tunnel)" -eq 1 ]
  last_local="$(grep -n '^launchctl bootout' "$CALLS" | tail -1 | cut -d: -f1)"
  first_remote="$(grep -n '^ssh .*bootstrap' "$CALLS" | head -1 | cut -d: -f1)"
  [ "$last_local" -lt "$first_remote" ]
}

@test "verify: a second cloudflared connector that never clears fails and points at rollback" {
  export STUB_TWO_CONNECTORS_CALLS=99
  run "$ROOT/bin/hub-cutover"
  [ "$status" -eq 1 ]
  [[ "$output" == *'expected one cloudflared connector, found 2'* ]]
  [[ "$output" == *'hub-cutover-rollback'* ]]
  [ "$(grep -c '^cloudflared ' "$CALLS")" -eq 3 ]
  grep -q '"verify": "verify-failed"' "$HUB_CUTOVER_STATE_DIR/hub-cutover-report.json"
}

@test "verify: an old connector that clears within the retry window passes" {
  export STUB_TWO_CONNECTORS_CALLS=1
  run "$ROOT/bin/hub-cutover"
  [ "$status" -eq 0 ]
  [[ "$output" == *'verify attempt 1/3 failed'* ]]
  grep -q '"verify": "pass"' "$HUB_CUTOVER_STATE_DIR/hub-cutover-report.json"
}

@test "verify: a webhook that does not answer 401 fails" {
  cat > "$WORK/stub/curl" <<'STUB'
#!/usr/bin/env bash
printf 'curl %s\n' "$*" >> "$CALLS"
if [[ "$*" == *frontend* ]]; then echo 200; else echo 502; fi
STUB
  chmod +x "$WORK/stub/curl"
  run "$ROOT/bin/hub-cutover"
  [ "$status" -eq 1 ]
  [[ "$output" == *'webhook returned 502'* ]]
}

@test "N6: source never deletes plists or mutates a cluster" {
  run grep -Eq 'rm[[:space:]]+.*plist|kubectl[[:space:]]+(delete|apply|patch)|k3d[[:space:]]+(delete|cluster[[:space:]]+delete)' "$ROOT/bin/hub-cutover"
  [ "$status" -eq 1 ]
}

@test "N7: cutover source never runs sudo" {
  run grep -Eq '(^|[;&|[:space:]])sudo[[:space:]]' "$ROOT/bin/hub-cutover"
  [ "$status" -eq 1 ]
}


@test "N1: a running old controller pod blocks registration and singleton loading" {
  export STUB_OLD_POD=1
  run "$ROOT/bin/hub-cutover"
  [ "$status" -ne 0 ]
  run grep -Eq '^refresh_registration |^launchctl bootstrap' "$CALLS"
  [ "$status" -eq 1 ]
  grep -q '"verify": "old-controller-not-stopped"' "$HUB_CUTOVER_STATE_DIR/hub-cutover-report.json"
}

@test "N3: rollback cannot restore old controller while the new pod remains" {
  mkdir -p "$HUB_CUTOVER_STATE_DIR"
  : > "$HUB_CUTOVER_STATE_DIR/stopped-on-old"
  echo 1 > "$HUB_CUTOVER_STATE_DIR/old-argocd-controller-replicas"
  printf 'rollback\n' > "$HUB_CUTOVER_TTY"
  export STUB_NEW_POD=1
  run "$ROOT/bin/hub-cutover" --rollback
  [ "$status" -ne 0 ]
  run grep -q '^ssh .*scale statefulset.*--replicas=1' "$CALLS"
  [ "$status" -eq 1 ]
}

@test "M5: rollback stops the new controller before restoring the recorded old count" {
  mkdir -p "$HUB_CUTOVER_STATE_DIR"
  : > "$HUB_CUTOVER_STATE_DIR/stopped-on-old"
  echo 1 > "$HUB_CUTOVER_STATE_DIR/old-argocd-controller-replicas"
  printf 'rollback\n' > "$HUB_CUTOVER_TTY"
  run "$ROOT/bin/hub-cutover" --rollback
  [ "$status" -eq 0 ]
  new_stop="$(grep -n '^kubectl .*scale statefulset/argocd-application-controller --replicas=0' "$CALLS" | head -1 | cut -d: -f1)"
  old_start="$(grep -n '^ssh .*scale statefulset/argocd-application-controller --replicas=1' "$CALLS" | head -1 | cut -d: -f1)"
  [ -n "$new_stop" ] && [ -n "$old_start" ] && [ "$new_stop" -lt "$old_start" ]
}

@test "M5: rollback without a recorded handoff warns, leaves both controllers alone and still rolls back" {
  mkdir -p "$HUB_CUTOVER_STATE_DIR"
  : > "$HUB_CUTOVER_STATE_DIR/stopped-on-old"
  printf 'rollback\n' > "$HUB_CUTOVER_TTY"
  run "$ROOT/bin/hub-cutover" --rollback
  [ "$status" -eq 0 ]
  [[ "$output" == *'no recorded controller handoff'* ]]
  run grep -q 'scale statefulset' "$CALLS"
  [ "$status" -eq 1 ]
}

@test "M6/N5: dry run prints the handoff plan and makes no handoff change" {
  export STUB_NO_CONTEXT=1 DRY_RUN=1
  run "$ROOT/bin/hub-cutover"
  [ "$status" -eq 0 ]
  [[ "$output" == *'Old controller replicas: 1'* ]]
  [[ "$output" == *'Hostinger kubeconfig source: m4-air.local:'* ]]
  [[ "$output" == *'Handoff plan:'* ]]
  run grep -Eq 'scale statefulset|^scp |^refresh_registration |launchctl (bootstrap|bootout)' "$CALLS"
  [ "$status" -eq 1 ]
  [ ! -e "$HOME/.kube/hostinger.config" ]
}

@test "handoff scales and waits before copying and registration, then loads" {
  export STUB_NO_CONTEXT=1
  run "$ROOT/bin/hub-cutover"
  [ "$status" -eq 0 ]
  [ "$(cat "$HUB_CUTOVER_STATE_DIR/old-argocd-controller-replicas")" = 1 ]
  old_scale="$(grep -n 'ssh .*scale statefulset.*--replicas=0' "$CALLS" | head -1 | cut -d: -f1)"
  old_wait="$(grep -n 'ssh .*get pods' "$CALLS" | head -1 | cut -d: -f1)"
  copy="$(grep -n '^scp ' "$CALLS" | cut -d: -f1)"
  register="$(grep -n '^refresh_registration k3s-hostinger' "$CALLS" | cut -d: -f1)"
  load="$(grep -n '^launchctl bootstrap' "$CALLS" | head -1 | cut -d: -f1)"
  [ "$old_scale" -lt "$old_wait" ] && [ "$old_wait" -lt "$copy" ] && [ "$copy" -lt "$register" ] && [ "$register" -lt "$load" ]
  [ "$(stat -c %a "$HOME/.kube/hostinger.config" 2>/dev/null || stat -f %Lp "$HOME/.kube/hostinger.config")" = 600 ]
}

@test "verify mode: re-verifies a recorded cutover and unblocks forwards" {
  mkdir -p "$HUB_CUTOVER_STATE_DIR"
  printf 'forwards\n' > "$HUB_CUTOVER_TTY"
  run "$ROOT/bin/hub-cutover" --verify
  [ "$status" -eq 1 ]
  [[ "$output" == *'no recorded cutover'* ]]
  [ ! -s "$CALLS" ]
  : > "$HUB_CUTOVER_STATE_DIR/stopped-on-old"
  echo 0 > "$WORK_OLD_REPLICAS"
  printf '%s\n' com.k3d-manager.ssh-tunnel com.k3d-manager.ssh-tunnel-vault > "$LOADED_FILE"
  printf '[{"verify":"verify-failed"}]\n' > "$HUB_CUTOVER_STATE_DIR/hub-cutover-report.json"
  run "$ROOT/bin/hub-cutover" --forwards
  [ "$status" -eq 1 ]
  run "$ROOT/bin/hub-cutover" --verify
  [ "$status" -eq 0 ]
  grep -q '"verify": "pass"' "$HUB_CUTOVER_STATE_DIR/hub-cutover-report.json"
  run grep -q 'launchctl bootout\|launchctl bootstrap\|command=python3 -' "$CALLS"
  [ "$status" -eq 1 ]
  run "$ROOT/bin/hub-cutover" --forwards
  [ "$status" -eq 0 ]
  grep -q '"verify": "forwards-pass"' "$HUB_CUTOVER_STATE_DIR/hub-cutover-report.json"
}

@test "verify mode: a failing check records verify-failed and keeps forwards blocked" {
  mkdir -p "$HUB_CUTOVER_STATE_DIR"
  : > "$HUB_CUTOVER_STATE_DIR/stopped-on-old"
  echo 0 > "$WORK_OLD_REPLICAS"
  printf '%s\n' com.k3d-manager.ssh-tunnel com.k3d-manager.ssh-tunnel-vault > "$LOADED_FILE"
  export STUB_NO_REGISTRATION=1
  run "$ROOT/bin/hub-cutover" --verify
  [ "$status" -eq 1 ]
  [[ "$output" == *'verify attempt 1/3 failed'* ]]
  [[ "$output" == *'hub-cutover-rollback'* ]]
  grep -q '"verify": "verify-failed"' "$HUB_CUTOVER_STATE_DIR/hub-cutover-report.json"
  run grep -q 'bootout\|bootstrap\|scale statefulset' "$CALLS"
  [ "$status" -eq 1 ]
  run "$ROOT/bin/hub-cutover" --forwards
  [ "$status" -eq 1 ]
}

@test "verify requires the labeled registration and healthy ESO application" {
  export STUB_NO_REGISTRATION=1
  run "$ROOT/bin/hub-cutover"
  [ "$status" -ne 0 ]
  grep -q '"verify": "verify-failed"' "$HUB_CUTOVER_STATE_DIR/hub-cutover-report.json"
  export STUB_NO_REGISTRATION=0 STUB_BAD_ESO=1
  run "$ROOT/bin/hub-cutover"
  [ "$status" -ne 0 ]
}

@test "an old host that needs a password stops cutover and rollback before any change" {
  export STUB_SSH_DENIED=1
  : > "$CALLS"
  run "$ROOT/bin/hub-cutover"
  [ "$status" -ne 0 ]
  [[ "$output" == *'cannot ssh to m4-air.local without a password'* ]]
  run grep -Eq 'scale statefulset|^scp |^refresh_registration |launchctl (bootstrap|bootout)' "$CALLS"
  [ "$status" -eq 1 ]
  mkdir -p "$HUB_CUTOVER_STATE_DIR"
  : > "$HUB_CUTOVER_STATE_DIR/stopped-on-old"
  printf 'rollback\n' > "$HUB_CUTOVER_TTY"
  run "$ROOT/bin/hub-cutover" --rollback
  [ "$status" -ne 0 ]
  [[ "$output" == *'cannot ssh to m4-air.local without a password'* ]]
  run grep -q 'scale statefulset' "$CALLS"
  [ "$status" -eq 1 ]
}

@test "forwards: passing cutover installs both tunnels and preserves original backups" {
  run "$ROOT/bin/hub-cutover"
  [ "$status" -eq 0 ]
  python3 - "$OLD_HOME" <<'PYCODE'
import os, plistlib, sys
for label, port in (("hub-pushgateway-port-forward", "19094"), ("hub-loki-port-forward", "19100")):
    path = os.path.join(sys.argv[1], "Library/LaunchAgents/com.k3d-manager." + label + ".plist")
    with open(path, 'rb') as f: current = plistlib.load(f)
    with open(path + '.pre-cutover', 'rb') as f: original = plistlib.load(f)
    assert original['ProgramArguments'] == ['kubectl']
    assert current['ProgramArguments'] == ['/usr/bin/ssh', '-F', '/dev/null', '-N', '-o', 'BatchMode=yes', '-o', 'ExitOnForwardFailure=yes', '-o', 'ServerAliveInterval=30', '-o', 'ServerAliveCountMax=3', '-L', '127.0.0.1:' + port + ':127.0.0.1:' + port, 'm5-air.local']
    assert current['KeepAlive'] and current['StandardOutPath'] == '/tmp/forward.log'
PYCODE
  grep -q '"verify": "forwards-pass"' "$HUB_CUTOVER_STATE_DIR/hub-cutover-report.json"
}

@test "forwards: failed batch login skips changes after a passing cutover" {
  export STUB_FORWARD_SSH_DENIED=1
  run "$ROOT/bin/hub-cutover"
  [ "$status" -eq 1 ]
  grep -q '"verify": "forwards-skipped"' "$HUB_CUTOVER_STATE_DIR/hub-cutover-report.json"
  [ ! -e "$OLD_HOME/Library/LaunchAgents/com.k3d-manager.hub-loki-port-forward.plist.pre-cutover" ]
  run grep -q 'command=python3 -' "$CALLS"
  [ "$status" -eq 1 ]
}

@test "forwards: failed readiness reports failure without rollback" {
  export STUB_FORWARD_BODY=bad
  run "$ROOT/bin/hub-cutover"
  [ "$status" -eq 1 ]
  [[ "$output" == *'cutover itself passed'* ]]
  grep -q '"verify": "forwards-failed"' "$HUB_CUTOVER_STATE_DIR/hub-cutover-report.json"
  run grep -q '"verify": "rollback-pass"' "$HUB_CUTOVER_STATE_DIR/hub-cutover-report.json"
  [ "$status" -eq 1 ]
}

@test "forwards: a tunnel that needs a moment to connect passes after retrying" {
  export STUB_FORWARD_FAIL_FIRST=3
  run "$ROOT/bin/hub-cutover"
  [ "$status" -eq 0 ]
  grep -q '"verify": "forwards-pass"' "$HUB_CUTOVER_STATE_DIR/hub-cutover-report.json"
  [ "$(cat "$CALLS.forward-probes")" -gt 3 ]
}

@test "forwards: waits for a lingering job to unload before bootstrapping it" {
  export STUB_REMOTE_LINGER=2
  run "$ROOT/bin/hub-cutover"
  [ "$status" -eq 0 ]
  grep -q '"verify": "forwards-pass"' "$HUB_CUTOVER_STATE_DIR/hub-cutover-report.json"
  [ "$(grep -c '^remote-launchctl print' "$CALLS")" -ge 3 ]
}

@test "forwards: a forward that is not loaded is still installed" {
  export STUB_REMOTE_NOT_LOADED=1
  run "$ROOT/bin/hub-cutover"
  [ "$status" -eq 0 ]
  grep -q '"verify": "forwards-pass"' "$HUB_CUTOVER_STATE_DIR/hub-cutover-report.json"
  [ "$(grep -c '^remote-launchctl bootstrap' "$CALLS")" -ge 2 ]
}

@test "forwards: standalone gate, confirmation, retry and backup preservation" {
  mkdir -p "$HUB_CUTOVER_STATE_DIR"
  printf 'forwards\n' > "$HUB_CUTOVER_TTY"
  run "$ROOT/bin/hub-cutover" --forwards
  [ "$status" -eq 1 ]
  [ ! -s "$CALLS" ]
  printf '[{"verify":"verify-failed"}]\n' > "$HUB_CUTOVER_STATE_DIR/hub-cutover-report.json"
  run "$ROOT/bin/hub-cutover" --forwards
  [ "$status" -eq 1 ]
  [ ! -s "$CALLS" ]
  printf '[{"verify":"pass"}]\n' > "$HUB_CUTOVER_STATE_DIR/hub-cutover-report.json"
  printf 'wrong\n' > "$HUB_CUTOVER_TTY"
  run "$ROOT/bin/hub-cutover" --forwards
  [ "$status" -eq 1 ]
  run grep -q 'command=python3 -' "$CALLS"
  [ "$status" -eq 1 ]
  printf 'forwards\n' > "$HUB_CUTOVER_TTY"
  export STUB_FORWARD_BODY=bad
  run "$ROOT/bin/hub-cutover" --forwards
  [ "$status" -eq 1 ]
  export STUB_FORWARD_BODY=OK
  run "$ROOT/bin/hub-cutover" --forwards
  [ "$status" -eq 0 ]
  run grep -Eq 'scale statefulset|^launchctl bootout|^refresh_registration' "$CALLS"
  [ "$status" -eq 1 ]
  python3 - "$OLD_HOME/Library/LaunchAgents/com.k3d-manager.hub-loki-port-forward.plist.pre-cutover" <<'PYCODE'
import plistlib, sys
with open(sys.argv[1], 'rb') as f: assert plistlib.load(f)['ProgramArguments'] == ['kubectl']
PYCODE
}

@test "forwards: rollback restores backups before singleton reload" {
  printf 'webhook\n' > "$OLD_LOADED_FILE"
  run "$ROOT/bin/hub-cutover"
  [ "$status" -eq 0 ]
  printf 'rollback\n' > "$HUB_CUTOVER_TTY"
  : > "$CALLS"
  run "$ROOT/bin/hub-cutover" --rollback
  [ "$status" -eq 0 ]
  [ ! -e "$OLD_HOME/Library/LaunchAgents/com.k3d-manager.hub-loki-port-forward.plist.pre-cutover" ]
  python3 - "$OLD_HOME/Library/LaunchAgents/com.k3d-manager.hub-loki-port-forward.plist" <<'PYCODE'
import plistlib, sys
with open(sys.argv[1], 'rb') as f: assert plistlib.load(f)['ProgramArguments'] == ['kubectl']
PYCODE
  [ "$(grep -n 'command=python3 -.*restore' "$CALLS" | tail -1 | cut -d: -f1)" -lt "$(grep -n '^ssh .*command=launchctl bootstrap' "$CALLS" | head -1 | cut -d: -f1)" ]
}

@test "old host: report host is recorded and reused by recovery modes" {
  python3 - "$HUB_NEW_STATE_DIR/hub-new-report.json" <<'PY'
import json, sys
p = sys.argv[1]
r = json.load(open(p)); r['old_host'] = 'old.example'
open(p, 'w').write(json.dumps(r))
PY
  unset HUB_OLD_HOST
  run "$ROOT/bin/hub-cutover"
  [ "$status" -eq 0 ]; [ "$(cat "$HUB_CUTOVER_STATE_DIR/old-host")" = old.example ]
  for mode in --verify --forwards --rollback; do
    : > "$CALLS"
    run "$ROOT/bin/hub-cutover" "$mode"
    [[ "$output" != *'set HUB_OLD_HOST'* ]]
    grep -q '^ssh host=old.example ' "$CALLS"
    if grep -q '^ssh host=m4-air.local ' "$CALLS"; then false; fi
  done
}
@test "old host: absent host refuses before external commands" {
  unset HUB_OLD_HOST
  run "$ROOT/bin/hub-cutover"
  [ "$status" -eq 2 ]; [[ "$output" == *'set HUB_OLD_HOST'* ]]; [ ! -s "$CALLS" ]
  for mode in --verify --forwards --rollback; do
    run "$ROOT/bin/hub-cutover" "$mode"
    [ "$status" -eq 2 ]; [ ! -s "$CALLS" ]
  done
}
@test "old host: conflicting report refuses before external commands" {
  python3 - "$HUB_NEW_STATE_DIR/hub-new-report.json" <<'PY'
import json, sys
p = sys.argv[1]
r = json.load(open(p)); r['old_host'] = 'different.example'
open(p, 'w').write(json.dumps(r))
PY
  run "$ROOT/bin/hub-cutover"
  [ "$status" -eq 2 ]; [[ "$output" == *differs* ]]; [ ! -s "$CALLS" ]
}
