#!/usr/bin/env bats
setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  WORK="$(mktemp -d "$BATS_TEST_TMPDIR/reload.XXXXXX")"
  mkdir -p "$WORK/stub" "$WORK/home"
  export HOME="$WORK/home" PATH="$WORK/stub:/usr/bin:/bin" CALLS="$WORK/calls" COUNT="$WORK/count" LAUNCHD_RELOAD_WAIT=0 LAUNCHD_RELOAD_TRIES=3
  [[ "$HOME" == "$WORK/home" && "${PATH%%:*}" == "$WORK/stub" ]]
  # Captured on m4-air 2026-10-31: unloaded bootout 3, print 113, lingering bootstrap 5.
  cat > "$WORK/stub/launchctl" <<'STUB'
#!/usr/bin/env bash
echo "$1" >> "$CALLS"
case "$1" in
 bootout) exit "${BOOTOUT_RC:-0}" ;;
 print) n=$(cat "$COUNT" 2>/dev/null || echo 0); echo $((n+1)) > "$COUNT"; (( n < ${LINGER:-0} )) && exit 0; exit 113 ;;
 bootstrap) n=$(cat "$COUNT"); (( n > ${LINGER:-0} )) || exit 5 ;;
esac
STUB
  chmod +x "$WORK/stub/launchctl"
}
@test "reload: waits for lingering job before bootstrap" {
  export LINGER=2
  run "$REPO/bin/launchd-reload" label "$WORK/plist"
  [ "$status" -eq 0 ]; [ "$(cat "$COUNT")" -eq 3 ]; grep -q bootstrap "$CALLS"
}
@test "reload: never bootstraps a job that stays loaded" {
  export LINGER=9
  run "$REPO/bin/launchd-reload" label "$WORK/plist"
  [ "$status" -eq 1 ]; [[ "$output" == *'still loaded after bootout'* ]]; ! grep -q bootstrap "$CALLS"
}
@test "reload: unloaded bootout exit 3 succeeds" {
  export BOOTOUT_RC=3
  run "$REPO/bin/launchd-reload" label "$WORK/plist"
  [ "$status" -eq 0 ]; grep -q bootstrap "$CALLS"
}
@test "reload: unexpected bootout failure stops" {
  export BOOTOUT_RC=5
  run "$REPO/bin/launchd-reload" label "$WORK/plist"
  [ "$status" -eq 1 ]; ! grep -q bootstrap "$CALLS"
}
