#!/usr/bin/env bats
# shellcheck disable=SC2016

setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home" PATH="$BATS_TEST_TMPDIR/bin:$PATH" CALLS="$BATS_TEST_TMPDIR/calls"
  mkdir -p "$HOME" "$BATS_TEST_TMPDIR/bin"
  [[ "$HOME" == "$BATS_TEST_TMPDIR/"* ]]
  printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "$CALLS"\n' > "$BATS_TEST_TMPDIR/bin/launchctl"
  chmod +x "$BATS_TEST_TMPDIR/bin/launchctl"
}

@test "E3: install renders dispatch-metrics plist and uninstall removes it" {
  run make -s -C "$REPO" install-dispatch-metrics
  [ "$status" -eq 0 ]
  python3 - "$HOME/Library/LaunchAgents/com.k3d-manager.dispatch-metrics.plist" "$REPO" "$HOME" <<'PY'
import plistlib, sys
with open(sys.argv[1], 'rb') as f: p = plistlib.load(f)
assert p['Label'] == 'com.k3d-manager.dispatch-metrics'
assert p['StartInterval'] == 900 and p['RunAtLoad'] is True
assert p['AbandonProcessGroup'] is True
assert p['ProgramArguments'] == [sys.argv[2] + '/bin/k3dm-codex-dispatch', 'schedule-metrics']
assert p['StandardOutPath'] == sys.argv[3] + '/.local/share/k3d-manager/logs/dispatch-metrics.log'
assert p['StandardErrorPath'] == p['StandardOutPath']
assert p['EnvironmentVariables']['PATH'].startswith(sys.argv[1].split('/Library/')[0] + '/.local/bin:')
assert set(p['EnvironmentVariables']) == {'PATH'}
PY
  [ "$(wc -l < "$CALLS" | tr -d ' ')" = 2 ]
  run make -s -C "$REPO" uninstall-dispatch-metrics
  [ "$status" -eq 0 ]
  grep -Fx "bootout gui/$(id -u)/com.k3d-manager.dispatch-metrics" "$CALLS"
  [ ! -e "$HOME/Library/LaunchAgents/com.k3d-manager.dispatch-metrics.plist" ]
}

@test "M6: K3DM_AGENT_LOAD=0 writes plist without loading" {
  rm -f "$CALLS"
  run make -s -C "$REPO" install-dispatch-metrics K3DM_AGENT_LOAD=0
  [ "$status" -eq 0 ]
  [[ "$output" == *"plist written, agent not loaded (K3DM_AGENT_LOAD=0)"* ]]
  [ ! -e "$CALLS" ]
  [ -f "$HOME/Library/LaunchAgents/com.k3d-manager.dispatch-metrics.plist" ]
}
