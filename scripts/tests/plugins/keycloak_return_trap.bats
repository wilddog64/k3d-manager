#!/usr/bin/env bats

@test "keycloak RETURN traps are self-clearing" {
  local old_traps
  old_traps=$(grep -c "rm -rf \"\$wd\"' RETURN" scripts/plugins/keycloak.sh || true)
  [ "$old_traps" -eq 0 ]

  local wd_traps self_clearing
  wd_traps=$(grep -cF "rm -rf \"'\"\${wd}\"'\"" scripts/plugins/keycloak.sh || true)
  self_clearing=$(grep -cF "trap 'trap - RETURN; rm -rf \"'\"\${wd}\"'\"" scripts/plugins/keycloak.sh || true)
  [ "$wd_traps" -ge 2 ]
  [ "$self_clearing" -eq "$wd_traps" ]

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
