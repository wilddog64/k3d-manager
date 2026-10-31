#!/usr/bin/env bats

setup() {
  REPO="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
  WORK="$(mktemp -d "${BATS_TEST_TMPDIR}/hub-cutover.XXXXXX")"
  ROOT="$WORK/repo"
  mkdir -p "$WORK/stub" "$WORK/home/Library/LaunchAgents" "$ROOT/bin" "$ROOT/scripts/etc/machine"
  cp "${HUB_CUTOVER_SOURCE:-$REPO/bin/hub-cutover}" "$ROOT/bin/hub-cutover"
  cp "$REPO/scripts/etc/machine/hub-singletons.list" "$ROOT/scripts/etc/machine/"
  export HOME="$WORK/home" PATH="$WORK/stub:/opt/homebrew/bin:/usr/bin:/bin" CALLS="$WORK/calls"
  export HUB_CUTOVER_STATE_DIR="$WORK/state" HUB_NEW_STATE_DIR="$WORK/new-state" HUB_OLD_HOST=m4-air.local
  [[ "$HOME" == "$WORK/home" ]]
  export HUB_CUTOVER_CONTROLLER_WAIT_S=0
  export HUB_CUTOVER_TTY="$WORK/tty" HUB_CUTOVER_VERIFY_WAIT=0 HUB_CUTOVER_VERIFY_TRIES=3
  printf 'cutover\n' > "$HUB_CUTOVER_TTY"
  mkdir -p "$HUB_NEW_STATE_DIR"
  printf '{"status":"pass","timestamp":"%s","stages":[],"checks":{}}\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" > "$HUB_NEW_STATE_DIR/hub-new-report.json"
  cat > "$WORK/stub/launchctl" <<'STUB'
#!/usr/bin/env bash
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
  *'get secret'*) [[ "${STUB_NO_REGISTRATION:-0}" == 0 ]] || exit 1; echo secret/cluster-ubuntu-hostinger ;;
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
  ! grep -Eq "scale statefulset|^scp |^refresh_registration |launchctl (bootout|bootstrap)" "$CALLS"
  [ ! -e "$HUB_CUTOVER_STATE_DIR" ]
}

@test "M7: wrong confirmation changes nothing" {
  printf 'nope\n' > "$HUB_CUTOVER_TTY"
  run "$ROOT/bin/hub-cutover"
  [ "$status" -eq 1 ]
  ! grep -Eq "scale statefulset|^scp |^refresh_registration |launchctl (bootout|bootstrap)" "$CALLS"
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
  [ "$(stat -f %Lp "$HOME/.kube/hostinger.config")" = 600 ]
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
