#!/usr/bin/env bats
setup() {
  source "${BATS_TEST_DIRNAME}/../test_helpers.bash"
  init_test_env
  source "${BATS_TEST_DIRNAME}/../../plugins/argocd.sh"
  export HOME="$BATS_TEST_TMPDIR/home" CALLS="$BATS_TEST_TMPDIR/calls"
  mkdir -p "$HOME" "$BATS_TEST_TMPDIR/stubs"
  [[ "$HOME" == "$BATS_TEST_TMPDIR/"* && "$BATS_TEST_TMPDIR/stubs" == "$BATS_TEST_TMPDIR/"* ]]
  export PATH="$BATS_TEST_TMPDIR/stubs:$PATH"
  printf '#!/bin/sh\necho Darwin\n' > "$BATS_TEST_TMPDIR/stubs/uname"
  cat > "$BATS_TEST_TMPDIR/stubs/security" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >> "$CALLS"
case " $* " in *' -w '*) exit 1 ;; esac
[ -e "$CALLS.present" ]
SH
  chmod +x "$BATS_TEST_TMPDIR/stubs/"*
}

@test "argocd: empty Keychain reads distinguish present and absent items" {
  for fn in argocd_sync_git_writer_secret _argocd_sync_notifications_slack_secret_untraced argocd_sync_webhook_token_secret argocd_sync_app_rebuild_secret; do
    touch "$CALLS.present"
    run "$fn"
    [ "$status" -eq 0 ]
    [[ "$output" == *'present in Keychain but unreadable'* ]]
    rm "$CALLS.present"
    run "$fn"
    [ "$status" -eq 0 ]
    [[ "$output" == *'not in Keychain'* || "$output" == *'not found in Keychain'* || "$output" == *'MISSING from Keychain'* ]]
    [[ "$output" != *SECRETVALUE_LEAK* ]]
  done
  run grep -q unlock-keychain "$CALLS"
  [ "$status" -eq 1 ]
}
