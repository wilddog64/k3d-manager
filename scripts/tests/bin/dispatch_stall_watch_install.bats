#!/usr/bin/env bats
setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home" PATH="$BATS_TEST_TMPDIR/bin:$PATH" CALLS="$BATS_TEST_TMPDIR/calls"
  mkdir -p "$HOME" "$BATS_TEST_TMPDIR/bin"
  [[ "$HOME" == "$BATS_TEST_TMPDIR/"* ]]
  printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "$CALLS"\n' > "$BATS_TEST_TMPDIR/bin/launchctl"
  chmod +x "$BATS_TEST_TMPDIR/bin/launchctl"
}
@test "E5: install renders only the watcher and uninstall removes it" {
  run make -s -C "$REPO" install-dispatch-stall-watch
  [ "$status" -eq 0 ]
  python3 - "$HOME/Library/LaunchAgents/com.k3d-manager.dispatch-stall-watch.plist" "$REPO" "$HOME" <<'PY'
import plistlib, sys
with open(sys.argv[1], 'rb') as f: p = plistlib.load(f)
assert p['Label'] == 'com.k3d-manager.dispatch-stall-watch'
assert p['StartInterval'] == 300 and p['RunAtLoad']
assert p['ProgramArguments'] == [sys.argv[2] + '/bin/k3dm-dispatch-stall-watch']
assert p['StandardOutPath'] == sys.argv[3] + '/.local/share/k3d-manager/logs/dispatch-stall-watch.log'
assert p['StandardErrorPath'] == p['StandardOutPath']
assert p['EnvironmentVariables']['PATH'].startswith(sys.argv[1].split('/Library/')[0] + '/.local/bin:')
assert set(p['EnvironmentVariables']) == {'PATH'}
PY
  [ "$(wc -l < "$CALLS" | tr -d ' ')" = 2 ]
  run make -s -C "$REPO" uninstall-dispatch-stall-watch
  [ "$status" -eq 0 ]
  grep -Fx "bootout gui/$(id -u)/com.k3d-manager.dispatch-stall-watch" "$CALLS"
  [ ! -e "$HOME/Library/LaunchAgents/com.k3d-manager.dispatch-stall-watch.plist" ]
}

@test "M15: documentation describes stall watch and detect-only operation" {
  local doc="$REPO/docs/howto/codex-dispatch.md" text
  for text in stalled K3DM_DISPATCH_STALL_SECONDS K3DM_DISPATCH_STALL_MAX_PROCS 'make install-dispatch-stall-watch' 'does not stop anything'; do
    grep -Fq "$text" "$doc"
  done
}
