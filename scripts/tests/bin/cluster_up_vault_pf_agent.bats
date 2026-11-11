#!/usr/bin/env bats
# docs/bugs/2026-11-11-cluster-up-vault-port-forward-reload-race-fails-and-unloads-hub-agent.md

setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  WORK="$(mktemp -d "$BATS_TEST_TMPDIR/vaultpf.XXXXXX")"
  mkdir -p "$WORK/stub" "$WORK/home" "$WORK/repo/bin" "$WORK/repo/scripts/etc/launchd"
  cp "$REPO/bin/launchd-reload" "$WORK/repo/bin/"
  cp "$REPO/scripts/etc/launchd/com.k3d-manager.vault-port-forward.plist.tmpl" "$WORK/repo/scripts/etc/launchd/"
  export HOME="$WORK/home" PATH="$WORK/stub:/usr/bin:/bin" CALLS="$WORK/calls" COUNT="$WORK/count" \
    LAUNCHD_RELOAD_WAIT=0 LAUNCHD_RELOAD_TRIES=4 REPO_ROOT="$WORK/repo"
  [[ "$HOME" == "$WORK/home" && "${PATH%%:*}" == "$WORK/stub" && "$REPO_ROOT" == "$WORK/repo" ]]
  # Captured on m4-air 2026-10-31 (launchd_reload.bats): unloaded bootout 3, print 113, lingering bootstrap 5.
  # Bootstrap exit 5 "Input/output error" also seen on m5-air 2026-11-10 18:34 PST, job c998511f.
  cat > "$WORK/stub/launchctl" <<'STUB'
#!/usr/bin/env bash
echo "$1" >> "$CALLS"
case "$1" in
 bootout) exit "${BOOTOUT_RC:-0}" ;;
 print) n=$(cat "$COUNT" 2>/dev/null || echo 0); echo $((n+1)) > "$COUNT"; (( n < ${LINGER:-0} )) && exit 0; exit 113 ;;
 bootstrap) n=$(cat "$COUNT" 2>/dev/null || echo 0); (( n >= ${LINGER:-0} )) || { echo "Bootstrap failed: 5: Input/output error" >&2; exit 5; } ;;
esac
STUB
  printf '#!/bin/sh\nexit 0\n' > "$WORK/stub/kubectl"
  chmod +x "$WORK/stub/launchctl" "$WORK/stub/kubectl"
  BLOCK="$WORK/step41.sh"
  {
    printf 'set -euo pipefail\n_info() { echo "INFO: $*"; }\n_err() { echo "ERROR: $*" >&2; exit 1; }\nif true; then\n'
    sed -n '/Step 4\.1\/12/,/^fi$/p' "$REPO/bin/cluster-up"
  } > "$BLOCK"
  grep -q 'Step 4.1/12' "$BLOCK"
}

@test "M1/N1: waits for a lingering agent before bootstrap and installs" {
  export LINGER=2
  run bash "$BLOCK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"LaunchAgent installed"* ]]
  [ "$(grep -c '^bootstrap$' "$CALLS")" -eq 1 ]
  [ "$(cat "$COUNT")" -eq 3 ]
  [ -f "$HOME/Library/LaunchAgents/com.k3d-manager.vault-port-forward.plist" ]
}

@test "M2: unloaded agent (bootout exit 3) bootstraps once" {
  export BOOTOUT_RC=3
  run bash "$BLOCK"
  [ "$status" -eq 0 ]
  [ "$(grep -c '^bootstrap$' "$CALLS")" -eq 1 ]
}

@test "M3: step 4.1 uses bin/launchd-reload and makes no direct bootstrap call" {
  run grep -c 'launchd-reload' "$BLOCK"
  [ "$output" -ge 1 ]
  run grep -c 'launchctl bootstrap' "$BLOCK"
  [ "$output" -eq 0 ]
}

@test "N2: an agent that never drops fails the step, names the reinstall, never claims installed" {
  export LINGER=99
  run bash "$BLOCK"
  [ "$status" -ne 0 ]
  [[ "$output" == *"make install-vault-port-forward"* ]]
  [[ "$output" != *"LaunchAgent installed"* ]]
  run grep -c '^bootstrap$' "$CALLS"
  [ "$output" -eq 0 ]
}
