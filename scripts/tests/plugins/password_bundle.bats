#!/usr/bin/env bats

setup() {
  export HOME="$BATS_TEST_TMPDIR/home" K3DM_PASSWORD_BUNDLE_STATE_DIR="$BATS_TEST_TMPDIR/state" K3DM_PASSWORD_BUNDLE_DIR="$BATS_TEST_TMPDIR/delivery" K3DM_PASSWORD_BUNDLE_PUSHGATEWAY_URL=http://127.0.0.1:9
  [[ "$HOME" == "$BATS_TEST_TMPDIR/"* && "$K3DM_PASSWORD_BUNDLE_STATE_DIR" == "$BATS_TEST_TMPDIR/"* && "$K3DM_PASSWORD_BUNDLE_DIR" == "$BATS_TEST_TMPDIR/"* && "$K3DM_PASSWORD_BUNDLE_PUSHGATEWAY_URL" == http://127.0.0.1:9 ]]
  mkdir -p "$HOME" "$K3DM_PASSWORD_BUNDLE_STATE_DIR" "$K3DM_PASSWORD_BUNDLE_DIR" "$BATS_TEST_TMPDIR/bin"
  export REAL_MAKE="$(command -v make)" REAL_AGE="$(command -v age)" REAL_AGE_KEYGEN="$(command -v age-keygen)" REAL_MV="$(command -v mv)" TEST_ARGV_LOG="$BATS_TEST_TMPDIR/home/argv.log"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH" SCRIPT_DIR="$BATS_TEST_DIRNAME/../.."
  export TEST_ID="$(age-keygen 2>/dev/null | tail -1)" TEST_ID2="$(age-keygen 2>/dev/null | tail -1)"
  KEY1="$(printf '%s\n' "$TEST_ID" | age-keygen -y)"; KEY2="$(printf '%s\n' "$TEST_ID2" | age-keygen -y)"
  cat > "$BATS_TEST_TMPDIR/bin/make" <<'STUB'
#!/bin/bash
[[ "${TEST_FAIL:-0}" != 1 ]] || exit 1
printf '%s\n' "${TEST_PASSWORD:-password-sentinel}"
STUB
  export TEST_REQUEST="$BATS_TEST_TMPDIR/request" TEST_RESPONSE="$BATS_TEST_TMPDIR/response"
  mkfifo "$TEST_REQUEST" "$TEST_RESPONSE"
  (
    identity="$TEST_ID"
    while IFS= read -r request < "$TEST_REQUEST"; do
      case "$request" in
        WRITE\ *) identity="${request##* }"; printf 'ok\n' > "$TEST_RESPONSE" ;;
        READ) printf '%s\n' "$identity" > "$TEST_RESPONSE" ;;
      esac
    done
  ) >/dev/null 2>&1 &
  TEST_SERVER_PID=$!
  for command_name in age age-keygen mv; do
    cat > "$BATS_TEST_TMPDIR/bin/$command_name" <<'STUB'
#!/bin/bash
printf '%s' "${0##*/}" >> "$TEST_ARGV_LOG"
printf ' <%s>' "$@" >> "$TEST_ARGV_LOG"
printf '\n' >> "$TEST_ARGV_LOG"
case "${0##*/}" in
  age) exec "$REAL_AGE" "$@" ;;
  age-keygen) exec "$REAL_AGE_KEYGEN" "$@" ;;
  mv) exec "$REAL_MV" "$@" ;;
esac
STUB
  done
  cat > "$BATS_TEST_TMPDIR/bin/security" <<'STUB' 
#!/bin/bash
printf 'security' >> "$TEST_ARGV_LOG"; printf ' <%s>' "$@" >> "$TEST_ARGV_LOG"; printf '\n' >> "$TEST_ARGV_LOG"
# Real read-only capture: m4-air, 2026-11-18, macOS 26.5.2, exit 44.
if [[ "$1" == -i ]]; then
  IFS= read -r line
  printf 'WRITE %s\n' "$line" > "$TEST_REQUEST"
  IFS= read -r reply < "$TEST_RESPONSE"
else
  printf 'READ\n' > "$TEST_REQUEST"
  IFS= read -r reply < "$TEST_RESPONSE"
  if [[ -n "$reply" ]]; then printf '%s\n' "$reply"; else
    echo 'security: SecKeychainSearchCopyNext: The specified item could not be found in the keychain.' >&2; exit 44
  fi
fi
STUB
  chmod +x "$BATS_TEST_TMPDIR/bin/"*
  source "$SCRIPT_DIR/lib/system.sh"
  [[ ! -f "$SCRIPT_DIR/plugins/password_bundle.sh" ]] || source "$SCRIPT_DIR/plugins/password_bundle.sh"
}

teardown() { kill "$TEST_SERVER_PID" 2>/dev/null || true; wait "$TEST_SERVER_PID" 2>/dev/null || true; }

add() { NAME="$1" KEY="$2" password_bundle_add_recipient; }
seed() { add one "$KEY1" && add two "$KEY2" && password_bundle_publish; }

@test 'N1 plaintext stays out of files; show is the positive control' {
  seed
  run password_bundle_show
  [ "$status" -eq 0 ]; [[ "$output" == *password-sentinel* ]]
  run rg -l --fixed-strings password-sentinel "$HOME" "$K3DM_PASSWORD_BUNDLE_STATE_DIR" "$K3DM_PASSWORD_BUNDLE_DIR"
  [ "$status" -eq 1 ]
}
@test 'N2 removed identity cannot decrypt; it can decrypt before removal' {
  seed
  printf '%s\n' "$TEST_ID2" | age -d -i /dev/stdin "$K3DM_PASSWORD_BUNDLE_DIR/service-passwords.age" >/dev/null
  NAME=two password_bundle_remove_recipient
  run rg -q 'two' "$K3DM_PASSWORD_BUNDLE_DIR/service-passwords.meta"
  [ "$status" -eq 1 ]
  run bash -c 'printf "%s\n" "$TEST_ID2" | age -d -i /dev/stdin "$K3DM_PASSWORD_BUNDLE_DIR/service-passwords.age"'
  [ "$status" -ne 0 ]
}
@test 'N3 failures and git delivery keep previous bundle' {
  seed
  before="$(shasum -a 256 "$K3DM_PASSWORD_BUNDLE_DIR/service-passwords.age")"
  run env TEST_FAIL=1 bash -c 'source "$SCRIPT_DIR/lib/system.sh"; source "$SCRIPT_DIR/plugins/password_bundle.sh"; password_bundle_publish'; [ "$status" -ne 0 ]
  [ "$before" = "$(shasum -a 256 "$K3DM_PASSWORD_BUNDLE_DIR/service-passwords.age")" ]
  : > "$K3DM_PASSWORD_BUNDLE_STATE_DIR/recipients"
  run password_bundle_publish; [ "$status" -ne 0 ]
  [ "$before" = "$(shasum -a 256 "$K3DM_PASSWORD_BUNDLE_DIR/service-passwords.age")" ]
  add one "$KEY1"
  git -C "$K3DM_PASSWORD_BUNDLE_DIR" init -q
  run password_bundle_publish; [ "$status" -ne 0 ]
  [ "$before" = "$(shasum -a 256 "$K3DM_PASSWORD_BUNDLE_DIR/service-passwords.age")" ]
}
@test 'N4 malformed recipients leave file unchanged; valid recipient is accepted' {
  add one "$KEY1"; before="$(cat "$K3DM_PASSWORD_BUNDLE_STATE_DIR/recipients")"
  run add BAD "$KEY1"; [ "$status" -ne 0 ]
  run add two bad; [ "$status" -ne 0 ]
  [ "$before" = "$(cat "$K3DM_PASSWORD_BUNDLE_STATE_DIR/recipients")" ]
}
@test 'N5 existing identity is protected; force permits enrolment' {
  run password_bundle_enroll; [ "$status" -ne 0 ]
  run env FORCE=1 bash -c 'source "$SCRIPT_DIR/lib/system.sh"; source "$SCRIPT_DIR/plugins/password_bundle.sh"; password_bundle_enroll'; [ "$status" -eq 0 ]
  enrolled_id="$(security find-generic-password -a identity -s k3dm-password-bundle-age -w)"
  [ "$enrolled_id" != "$TEST_ID" ]
  run rg -l --fixed-strings "$enrolled_id" "$HOME" "$K3DM_PASSWORD_BUNDLE_DIR"
  [ "$status" -eq 1 ]
  run rg -l --fixed-strings "$TEST_ID" "$HOME" "$K3DM_PASSWORD_BUNDLE_STATE_DIR" "$K3DM_PASSWORD_BUNDLE_DIR"
  [ "$status" -eq 1 ]
}

@test 'M3 unchanged output preserves bundle and change time; force and changes replace it' {
  seed
  before="$(shasum -a 256 "$K3DM_PASSWORD_BUNDLE_DIR/service-passwords.age")"
  change="$(cat "$K3DM_PASSWORD_BUNDLE_STATE_DIR/last-change")"
  sleep 1
  password_bundle_publish
  [ "$before" = "$(shasum -a 256 "$K3DM_PASSWORD_BUNDLE_DIR/service-passwords.age")" ]
  [ "$change" = "$(cat "$K3DM_PASSWORD_BUNDLE_STATE_DIR/last-change")" ]
  [ "$(cat "$K3DM_PASSWORD_BUNDLE_STATE_DIR/last-publish")" -gt "$change" ]
  FORCE=1 password_bundle_publish
  [ "$before" != "$(shasum -a 256 "$K3DM_PASSWORD_BUNDLE_DIR/service-passwords.age")" ]
  before="$(shasum -a 256 "$K3DM_PASSWORD_BUNDLE_DIR/service-passwords.age")"
  TEST_PASSWORD=changed password_bundle_publish
  [ "$before" != "$(shasum -a 256 "$K3DM_PASSWORD_BUNDLE_DIR/service-passwords.age")" ]
  [ "$(stat -c %a "$K3DM_PASSWORD_BUNDLE_DIR/service-passwords.age" 2>/dev/null || stat -f %Lp "$K3DM_PASSWORD_BUNDLE_DIR/service-passwords.age")" = 600 ]
  [ "$(stat -c %a "$K3DM_PASSWORD_BUNDLE_STATE_DIR/recipients" 2>/dev/null || stat -f %Lp "$K3DM_PASSWORD_BUNDLE_STATE_DIR/recipients")" = 600 ]
  rg -q --fixed-strings "<$K3DM_PASSWORD_BUNDLE_DIR/.service-passwords.age." "$TEST_ARGV_LOG"
  rg -q --fixed-strings "<$K3DM_PASSWORD_BUNDLE_DIR/service-passwords.age>" "$TEST_ARGV_LOG"
}


@test 'M1 enrolment stores an identity that shows the exact published output' {
  printf 'WRITE \n' > "$TEST_REQUEST"
  IFS= read -r reply < "$TEST_RESPONSE"
  [ "$reply" = ok ]
  run env FORCE=0 bash -c 'source "$SCRIPT_DIR/lib/system.sh"; source "$SCRIPT_DIR/plugins/password_bundle.sh"; password_bundle_enroll'
  [ "$status" -eq 0 ]
  enrolled_key="${lines[0]}"
  add enrolled "$enrolled_key"
  password_bundle_publish
  run password_bundle_show
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == generated_at:* ]]
  [ "${lines[1]}" = password-sentinel ]
}

@test 'make targets dispatch to the bundle plugin' {
  add one "$KEY1"
  password_bundle_publish
  run "$REAL_MAKE" -s -C "$SCRIPT_DIR/.." password-bundle-show
  [ "$status" -eq 0 ]
  [[ "$output" == *password-sentinel* ]]
}
