#!/usr/bin/env bats

@test "keycloak RETURN traps are self-clearing" {
  local old_traps
  old_traps=$(grep -c "rm -rf \"\$wd\"' RETURN" scripts/plugins/keycloak.sh || true)
  [ "$old_traps" -eq 0 ]

  run grep -c "trap - RETURN; rm -rf" scripts/plugins/keycloak.sh
  [ "$status" -eq 0 ]
  [ "$output" -eq 2 ]

  run bash -c '
    set -euo pipefail
    inner() {
      local wd
      wd=$(mktemp -d)
      trap '\''trap - RETURN; rm -rf "'"${wd}"'" 2>/dev/null || true'\'' RETURN
    }
    helper() { :; }
    outer() { inner; helper; }
    outer
    trap -p RETURN
  '
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
