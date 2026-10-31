#!/usr/bin/env bats
setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  WORK="$(mktemp -d "$BATS_TEST_TMPDIR/make-forward.XXXXXX")"
  mkdir -p "$WORK/stub" "$WORK/home/Library/LaunchAgents" "$WORK/repo/bin" "$WORK/repo/scripts/etc"
  cp "$REPO/Makefile" "$WORK/repo/Makefile"
  cp "$REPO/bin/launchd-reload" "$WORK/repo/bin/"
  ln -s "$REPO/scripts/etc/launchd" "$WORK/repo/scripts/etc/launchd"
  export HOME="$WORK/home" PATH="$WORK/stub:/usr/bin:/bin" CALLS="$WORK/calls"
  [[ "$HOME" == "$WORK/home" && "${PATH%%:*}" == "$WORK/stub" ]]
  cat > "$WORK/stub/launchctl" <<'STUB'
#!/usr/bin/env bash
echo "$1 $*" >> "$CALLS"
[[ "$1" != print ]] || exit 113
STUB
  printf '#!/usr/bin/env bash\nexit 0\n' > "$WORK/stub/kubectl"
  chmod +x "$WORK/stub/launchctl" "$WORK/stub/kubectl"
}
@test "install: all five targets reload through launchctl" {
  for name in vault prometheus hub-pushgateway hub-loki alertmanager; do
    run make -C "$WORK/repo" "install-$name-port-forward"
    [ "$status" -eq 0 ]; grep -q "bootstrap .*com.k3d-manager.$name-port-forward.plist" "$CALLS"
  done
}
@test "install: cutover backup prevents overwrite unless explicitly allowed" {
  for name in hub-pushgateway hub-loki; do
    plist="$HOME/Library/LaunchAgents/com.k3d-manager.$name-port-forward.plist"
    echo tunnel > "$plist"; echo backup > "$plist.pre-cutover"
    run make -C "$WORK/repo" "install-$name-port-forward"
    [ "$status" -ne 0 ]; [ "$(cat "$plist")" = tunnel ]; [ "$(cat "$plist.pre-cutover")" = backup ]
    run make -C "$WORK/repo" "install-$name-port-forward" HUB_FORWARD_OVERWRITE=1
    [ "$status" -eq 0 ]; [ "$(cat "$plist")" != tunnel ]; [ "$(cat "$plist.pre-cutover")" = backup ]
  done
}
@test "migration: recipe orders stages and stops on failure" {
  for script in hub-new hub-cutover; do
    printf '#!/usr/bin/env bash\necho "%s $HUB_OLD_HOST" >> "$CALLS"\n[[ "%s" != hub-new || "${FAIL_NEW:-0}" != 1 ]]\n' "$script" "$script" > "$WORK/repo/bin/$script"
    chmod +x "$WORK/repo/bin/$script"
  done
  run make -C "$WORK/repo" hub-migrate HUB_OLD_HOST=old.example
  [ "$status" -eq 0 ]; [ "$(cat "$CALLS")" = "$(printf 'hub-new old.example\nhub-cutover old.example')" ]
  : > "$CALLS"; export FAIL_NEW=1
  run make -C "$WORK/repo" hub-migrate HUB_OLD_HOST=old.example
  [ "$status" -ne 0 ]; [ "$(cat "$CALLS")" = 'hub-new old.example' ]
  run make -C "$WORK/repo" -np hub-cutover
  [[ "$output" == *$'hub-cutover:\n'* ]]
}
