#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
export BATS_TEST_TIMEOUT=30

setup() {
  export HOME="$BATS_TEST_TMPDIR/home" K3DM_PASSWORD_BUNDLE_STATE_DIR="$BATS_TEST_TMPDIR/state" K3DM_PASSWORD_BUNDLE_DIR="$BATS_TEST_TMPDIR/delivery" K3DM_PASSWORD_BUNDLE_PUSHGATEWAY_URL=http://127.0.0.1:9
  [[ "$HOME" == "$BATS_TEST_TMPDIR/"* && "$K3DM_PASSWORD_BUNDLE_STATE_DIR" == "$BATS_TEST_TMPDIR/"* && "$K3DM_PASSWORD_BUNDLE_DIR" == "$BATS_TEST_TMPDIR/"* && "$K3DM_PASSWORD_BUNDLE_PUSHGATEWAY_URL" == http://127.0.0.1:9 ]]
  mkdir -p "$HOME" "$K3DM_PASSWORD_BUNDLE_STATE_DIR" "$K3DM_PASSWORD_BUNDLE_DIR" "$BATS_TEST_TMPDIR/bin"
  export REAL_MAKE="$(command -v make)" REAL_CURL="$(command -v curl)" REAL_AGE="$(command -v age)" REAL_AGE_KEYGEN="$(command -v age-keygen)" REAL_MV="$(command -v mv)" TEST_ARGV_LOG="$BATS_TEST_TMPDIR/home/argv.log"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH" SCRIPT_DIR="$BATS_TEST_DIRNAME/../.."
  export TEST_ID="$(age-keygen 2>/dev/null | tail -1)" TEST_ID2="$(age-keygen 2>/dev/null | tail -1)"
  KEY1="$(printf '%s\n' "$TEST_ID" | age-keygen -y)"; KEY2="$(printf '%s\n' "$TEST_ID2" | age-keygen -y)"
  cat > "$BATS_TEST_TMPDIR/bin/make" <<'STUB'
#!/bin/bash
[[ "${TEST_FAIL:-0}" != 1 ]] || exit 1
printf '%s\n' "${TEST_PASSWORD:-password-sentinel}"
STUB
  cat > "$BATS_TEST_TMPDIR/bin/curl" <<'STUB'
#!/bin/bash
[[ "$*" == *"--max-time 10"* ]] || exit 92
[[ "${TEST_REAL_CURL:-0}" != 1 ]] || exec "$REAL_CURL" "$@"
cat > "$TEST_PUSH_BODY"
exit 0
STUB
  export TEST_PUSH_BODY="$BATS_TEST_TMPDIR/push-body"
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
# Read-only capture: m4-air over SSH, 2026-11-08 (locked / unlocked).
case "$1" in
  show-keychain-info)
    [[ "$2" == "${K3DM_PASSWORD_BUNDLE_KEYCHAIN:-$HOME/Library/Keychains/login.keychain-db}" ]] || exit 1
    if [[ "${TEST_LOCKED:-0}" == 1 && ! -f "$HOME/unlocked" ]]; then
      echo 'security: SecKeychainCopySettings: User interaction is not allowed.' >&2; exit 36
    fi
    echo 'no-timeout' >&2; exit 0 ;;
  unlock-keychain)
    [[ "$#" == 2 && "$2" == "${K3DM_PASSWORD_BUNDLE_KEYCHAIN:-$HOME/Library/Keychains/login.keychain-db}" ]] || exit 1
    IFS= read -r supplied && [[ "$supplied" == "$TEST_UNLOCK_PASSWORD" ]] || exit 1
    [[ "${TEST_REJECT_UNLOCK:-0}" == 0 ]] || exit 1
    touch "$HOME/unlocked"; exit 0 ;;
  find-generic-password)
    if [[ -f "$HOME/unlocked" ]]; then
      [[ "${TEST_RETRY_RC:-0}" == 0 ]] || exit "$TEST_RETRY_RC"
    elif [[ "${TEST_READ_RC:-0}" != 0 ]]; then exit "$TEST_READ_RC"; fi ;;
  -i) ;;
  *) exit 1 ;;
esac
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
  [[ "$(command -v security)" == "$BATS_TEST_TMPDIR/bin/security" ]]
  source "$SCRIPT_DIR/lib/system.sh"
  [[ ! -f "$SCRIPT_DIR/plugins/password_bundle.sh" ]] || source "$SCRIPT_DIR/plugins/password_bundle.sh"
}

teardown() {
  kill "$TEST_SERVER_PID" 2>/dev/null || true
  wait "$TEST_SERVER_PID" 2>/dev/null || true
  for pid_file in "${TEST_CHILD_TERM:-}" "${TEST_CHILD_NORMAL:-}"; do
    if [[ -n "$pid_file" && -r "$pid_file" ]]; then
      read -r child_pid < "$pid_file"
      kill -KILL "$child_pid" 2>/dev/null || true
    fi
  done
}

add() { NAME="$1" KEY="$2" password_bundle_add_recipient; }
as_mac_host() {
  [[ "$BATS_TEST_TMPDIR/bin" == "${PATH%%:*}" ]]
  printf '#!/bin/sh\necho Darwin\n' > "$BATS_TEST_TMPDIR/bin/uname"
  printf '#!/bin/sh\necho "$*" >> "%s/launchctl-hits"\nexit 97\n' "$BATS_TEST_TMPDIR" > "$BATS_TEST_TMPDIR/bin/launchctl"
  chmod +x "$BATS_TEST_TMPDIR/bin/uname" "$BATS_TEST_TMPDIR/bin/launchctl"
}
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
  run add BAD "$KEY1"; [ "$status" -ne 0 ]; [[ "$output" == *"Invalid NAME"* ]]
  [ "$before" = "$(cat "$K3DM_PASSWORD_BUNDLE_STATE_DIR/recipients")" ]
  for key in "" "${KEY2%?}" bad; do
    run add two "$key"; [ "$status" -ne 0 ]; [[ "$output" == *"Invalid KEY"* ]]
    [ "$before" = "$(cat "$K3DM_PASSWORD_BUNDLE_STATE_DIR/recipients")" ]
  done
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
  [[ "${lines[${#lines[@]}-1]}" == "On the hub: make password-bundle-add-laptop NAME=<laptop> KEY=$enrolled_key" ]]
  [[ "$output" != *password-bundle-add-recipient* ]]
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

@test 'M6 add-laptop forces publication for the new identity and installs the schedule' {
  as_mac_host
  add one "$KEY1"
  password_bundle_publish
  export K3DM_AGENT_LOAD=0
  run "$REAL_MAKE" -s -C "$SCRIPT_DIR/.." password-bundle-add-laptop NAME=two KEY="$KEY2"
  [ "$status" -eq 0 ]
  rg -q "^two $KEY2$" "$K3DM_PASSWORD_BUNDLE_STATE_DIR/recipients"
  run bash -c 'printf "%s\n" "$TEST_ID2" | age -d -i /dev/stdin "$K3DM_PASSWORD_BUNDLE_DIR/service-passwords.age"'
  [ "$status" -eq 0 ]; [ "$output" = password-sentinel ]
  [ -f "$HOME/Library/LaunchAgents/com.k3d-manager.password-bundle.plist" ]
  [ ! -e "$BATS_TEST_TMPDIR/launchctl-hits" ]
}

@test 'N6 failed publication does not install the schedule' {
  as_mac_host
  add one "$KEY1"
  export K3DM_AGENT_LOAD=0 TEST_FAIL=1
  run "$REAL_MAKE" -s -C "$SCRIPT_DIR/.." password-bundle-add-laptop NAME=two KEY="$KEY2"
  [ "$status" -ne 0 ]
  rg -q "^two $KEY2$" "$K3DM_PASSWORD_BUNDLE_STATE_DIR/recipients"
  [ ! -e "$HOME/Library/LaunchAgents/com.k3d-manager.password-bundle.plist" ]
}

@test 'N7 invalid name or key changes nothing and does not install the schedule' {
  as_mac_host
  add one "$KEY1"
  password_bundle_publish
  before="$(shasum -a 256 "$K3DM_PASSWORD_BUNDLE_DIR/service-passwords.age")"
  recipients="$(cat "$K3DM_PASSWORD_BUNDLE_STATE_DIR/recipients")"
  export K3DM_AGENT_LOAD=0
  for pair in "BAD:$KEY2" 'two:bad'; do
    run "$REAL_MAKE" -s -C "$SCRIPT_DIR/.." password-bundle-add-laptop NAME="${pair%%:*}" KEY="${pair#*:}"
    [ "$status" -ne 0 ]
    if [[ "$pair" == BAD:* ]]; then expected="Invalid NAME"; else expected="Invalid KEY"; fi
    [[ "$output" == *"$expected"* ]]
    [ "$recipients" = "$(cat "$K3DM_PASSWORD_BUNDLE_STATE_DIR/recipients")" ]
    [ "$before" = "$(shasum -a 256 "$K3DM_PASSWORD_BUNDLE_DIR/service-passwords.age")" ]
    [ ! -e "$HOME/Library/LaunchAgents/com.k3d-manager.password-bundle.plist" ]
  done
}

@test 'Keychain non-terminal locked read gives the manual unlock command' {
  export TEST_READ_RC=36 TEST_LOCKED=1
  for action in password_bundle_show password_bundle_enroll; do
    : > "$TEST_ARGV_LOG"
    run --separate-stderr "$action" </dev/null
    [ "$status" -eq 1 ]
    [[ "$stderr" == *'Login Keychain is locked; run: security unlock-keychain ~/Library/Keychains/login.keychain-db, then retry.'* ]]
    rg -q '^security <show-keychain-info>' "$TEST_ARGV_LOG"
    run rg -q '^security <unlock-keychain>' "$TEST_ARGV_LOG"
    [ "$status" -eq 1 ]
  done
}

@test 'Keychain item access denial directs the operator to Always Allow' {
  export TEST_READ_RC=36
  for action in password_bundle_show password_bundle_enroll; do
    run --separate-stderr "$action" </dev/null
    [ "$status" -eq 1 ]
    [[ "$stderr" == *"run this command once in Terminal on this Mac's screen and choose Always Allow."* ]]
    run rg -q '^security <unlock-keychain>' "$TEST_ARGV_LOG"
    [ "$status" -eq 1 ]
  done
}

@test 'Keychain only diagnoses rc 36' {
  export TEST_LOCKED=1 TEST_READ_RC=36
  run password_bundle_show </dev/null
  rg -q '^security <show-keychain-info>' "$TEST_ARGV_LOG"
  for TEST_READ_RC in 44 1; do
    : > "$TEST_ARGV_LOG"
    run password_bundle_show </dev/null
    [ "$status" -eq 1 ]; [[ "$output" != *'unlock'* ]]
    run password_bundle_enroll </dev/null
    if [[ "$TEST_READ_RC" == 44 ]]; then [ "$status" -eq 0 ]; else
      [ "$status" -eq 1 ]; [[ "$output" == *'Unable to read Keychain identity.'* ]]
    fi
    [[ "$output" != *'unlock'* ]]
    run rg -q '^security <(show-keychain-info|unlock-keychain)>' "$TEST_ARGV_LOG"
    [ "$status" -eq 1 ]
  done
}

run_on_terminal() {
  python3 - "$1" <<'PY'
import errno
import os
import pty
import select
import signal
import sys
import time

pid, terminal = pty.fork()
if pid == 0:
    os.execlp("bash", "bash", "-c", 'source "$SCRIPT_DIR/lib/system.sh"; '
              'source "$SCRIPT_DIR/plugins/password_bundle.sh"; "$1"', "bash", sys.argv[1])

deadline = time.monotonic() + 10
transcript = bytearray()
sent = False
try:
    while True:
        timeout = max(0, deadline - time.monotonic())
        if not select.select([terminal], [], [], timeout)[0]:
            raise TimeoutError("Keychain command timed out")
        try:
            data = os.read(terminal, 4096)
        except OSError as exc:
            if exc.errno != errno.EIO:
                raise
            break
        if not data:
            break
        transcript.extend(data)
        if not sent and b"Login password for this Mac's keychain: " in transcript:
            os.write(terminal, os.environ["TEST_UNLOCK_PASSWORD"].encode() + b"\n")
            sent = True
finally:
    os.close(terminal)
    if time.monotonic() >= deadline:
        os.kill(pid, signal.SIGKILL)
    _, status = os.waitpid(pid, 0)
sys.stdout.buffer.write(transcript)
sys.exit(os.waitstatus_to_exitcode(status))
PY
}

@test 'Keychain terminal unlock retries once and keeps secrets off argv and terminal' {
  seed
  export TEST_READ_RC=36 TEST_LOCKED=1 TEST_UNLOCK_PASSWORD=' fixture passphrase '
  for action in password_bundle_show password_bundle_enroll; do
    : > "$TEST_ARGV_LOG"
    rm -f "$HOME/unlocked"
    run run_on_terminal "$action"
    log="$(cat "$TEST_ARGV_LOG")"
    [[ "$output$log" != *"$TEST_UNLOCK_PASSWORD"* && "$output$log" != *"$TEST_ID"* ]]
    if [[ "$action" == password_bundle_show ]]; then
      [ "$status" -eq 0 ]; [[ "$output" == *password-sentinel* ]]
    else
      [ "$status" -eq 1 ]; [[ "$output" == *'Identity already exists'* ]]
    fi
    [[ "$output" == *'Login Keychain is locked; unlocking it.'* ]]
    [ "$(rg -c '^security <unlock-keychain>' "$TEST_ARGV_LOG")" = 1 ]
    [ "$(rg -c '^security <find-generic-password>' "$TEST_ARGV_LOG")" = 2 ]
  done

  rm -f "$HOME/unlocked"
  : > "$TEST_ARGV_LOG"
  export TEST_RETRY_RC=36
  run run_on_terminal password_bundle_show
  [ "$status" -eq 1 ]; [[ "$output" == *'choose Always Allow.'* ]]
  [ "$(rg -c '^security <unlock-keychain>' "$TEST_ARGV_LOG")" = 1 ]
  [ "$(rg -c '^security <find-generic-password>' "$TEST_ARGV_LOG")" = 2 ]

  rm -f "$HOME/unlocked"
  : > "$TEST_ARGV_LOG"
  export TEST_REJECT_UNLOCK=1
  run run_on_terminal password_bundle_show
  [ "$status" -eq 1 ]; [[ "$output" == *'Could not unlock the login Keychain.'* ]]
  [ "$(rg -c '^security <unlock-keychain>' "$TEST_ARGV_LOG")" = 1 ]
  [ "$(rg -c '^security <find-generic-password>' "$TEST_ARGV_LOG")" = 1 ]
}


@test 'M1 M2 N1 N2 N3 a hanging payload is bounded, reported, private, and reaped' {
  add one "$KEY1"
  printf 'unchanged-hash\n' > "$K3DM_PASSWORD_BUNDLE_STATE_DIR/last.sha256"
  printf '12345\n' > "$K3DM_PASSWORD_BUNDLE_STATE_DIR/last-publish"
  cat > "$BATS_TEST_TMPDIR/bin/make" <<'STUB'
#!/bin/bash
printf 'unique-payload-secret-marker\n'
(trap '' TERM; exec sleep 3600) & echo "$!" > "$TEST_CHILD_TERM"
(exec sleep 3600) & echo "$!" > "$TEST_CHILD_NORMAL"
sleep 3600
STUB
  chmod +x "$BATS_TEST_TMPDIR/bin/make"
  export TEST_CHILD_TERM="$BATS_TEST_TMPDIR/term-child.pid" TEST_CHILD_NORMAL="$BATS_TEST_TMPDIR/normal-child.pid" K3DM_PASSWORD_BUNDLE_TIMEOUT=2
  before="$(cat "$K3DM_PASSWORD_BUNDLE_STATE_DIR/last-publish")"
  start="$SECONDS"
  perl - "$SCRIPT_DIR" <<'PERL' > "$BATS_TEST_TMPDIR/publish.stdout" 2> "$BATS_TEST_TMPDIR/publish.stderr" &
use strict; use warnings; use POSIX qw(:sys_wait_h);
my ($script_dir) = @ARGV;
my $pid = fork(); die "fork: $!" unless defined $pid;
if ($pid == 0) {
  setpgrp(0, 0) or die "setpgrp: $!";
  exec "bash", "-c", 'source "$1/lib/system.sh"; source "$1/plugins/password_bundle.sh"; password_bundle_publish', "publish-harness", $script_dir;
  die "exec: $!";
}
my $timed_out = 0;
local $SIG{ALRM} = sub { $timed_out = 1; kill "KILL", -$pid; };
alarm 20;
while (waitpid($pid, 0) < 0 && $!{EINTR}) { }
my $status = $?;
alarm 0;
if ($timed_out) { kill "KILL", -$pid; waitpid($pid, 0); exit 124; }
exit($status >> 8) if WIFEXITED($status);
exit(128 + WTERMSIG($status)) if WIFSIGNALED($status);
exit 1;
PERL
  publish_pid=$!
  for _ in {1..20}; do
    [ -s "$TEST_CHILD_TERM" ] && [ -s "$TEST_CHILD_NORMAL" ] && break
    sleep 0.05
  done
  [ -s "$TEST_CHILD_TERM" ] && [ -s "$TEST_CHILD_NORMAL" ]
  term_pid="$(cat "$TEST_CHILD_TERM")"; normal_pid="$(cat "$TEST_CHILD_NORMAL")"
  kill -0 "$term_pid" 2>/dev/null && kill -0 "$normal_pid" 2>/dev/null
  sleep 0.1
  kill -0 "$term_pid" 2>/dev/null && kill -0 "$normal_pid" 2>/dev/null
  if wait "$publish_pid"; then publish_status=0; else publish_status=$?; fi
  elapsed=$((SECONDS - start))
  [ "$publish_status" -ne 0 ] && [ "$elapsed" -le "$((K3DM_PASSWORD_BUNDLE_TIMEOUT + 13))" ] || { echo "publish rc=$publish_status elapsed=${elapsed}s" >&2; false; }
  [ -s "$TEST_PUSH_BODY" ] && rg -q '^k3dm_password_bundle_publish_success 0$' "$TEST_PUSH_BODY"
  [ "$(cat "$K3DM_PASSWORD_BUNDLE_STATE_DIR/last-publish")" = "$before" ]
  [ "$(cat "$K3DM_PASSWORD_BUNDLE_STATE_DIR/last.sha256")" = unchanged-hash ]
  for pid in "$term_pid" "$normal_pid"; do
    for _ in {1..20}; do
      state="$(ps -o stat= -p "$pid" 2>/dev/null || true)"
      [[ -z "$state" || "$state" == Z* ]] && break
      sleep 0.1
    done
    [[ -z "$state" || "$state" == Z* ]]
  done
  [[ "$(cat "$BATS_TEST_TMPDIR/publish.stdout" "$BATS_TEST_TMPDIR/publish.stderr")" != *unique-payload-secret-marker* ]]
  run rg -l --fixed-strings unique-payload-secret-marker "$K3DM_PASSWORD_BUNDLE_DIR" "$K3DM_PASSWORD_BUNDLE_STATE_DIR"
  [ "$status" -eq 1 ]
}

@test 'E2 a hanging delivery git check is bounded and reported' {
  add one "$KEY1"
  cat > "$BATS_TEST_TMPDIR/bin/git" <<'STUB'
#!/bin/bash
sleep 3600
STUB
  chmod +x "$BATS_TEST_TMPDIR/bin/git"
  export K3DM_PASSWORD_BUNDLE_TIMEOUT=2
  start="$SECONDS"
  run password_bundle_publish
  [ "$status" -ne 0 ] && [ "$((SECONDS - start))" -le 22 ]
  rg -q '^k3dm_password_bundle_publish_success 0$' "$TEST_PUSH_BODY"
}

@test 'M4 bounded publish works without timeout or gtimeout in PATH' {
  add one "$KEY1"
  export K3DM_PASSWORD_BUNDLE_TIMEOUT=2
  cat > "$BATS_TEST_TMPDIR/bin/make" <<'STUB'
#!/bin/bash
sleep 3600
STUB
  chmod +x "$BATS_TEST_TMPDIR/bin/make"
  mkdir "$BATS_TEST_TMPDIR/limited-bin"
  for tool in bash cat chmod date git make mkdir mktemp mv perl rm shasum sleep; do
    path="$(command -v "$tool")"
    [[ -n "$path" ]] && ln -s "$path" "$BATS_TEST_TMPDIR/limited-bin/$tool"
  done
  ln -s "$BATS_TEST_TMPDIR/bin/curl" "$BATS_TEST_TMPDIR/limited-bin/curl"
  run env PATH="$BATS_TEST_TMPDIR/limited-bin" bash -c 'command -v timeout >/dev/null 2>&1 || command -v gtimeout >/dev/null 2>&1'
  [ "$status" -ne 0 ]
  run env PATH="$BATS_TEST_TMPDIR/limited-bin" bash -c 'source "$SCRIPT_DIR/lib/system.sh"; source "$SCRIPT_DIR/plugins/password_bundle.sh"; password_bundle_publish'
  [ "$status" -ne 0 ]
}

@test 'M3 metrics push has a fixed curl deadline' {
  add one "$KEY1"
  cat > "$BATS_TEST_TMPDIR/listener.py" <<'PY'
import socket, sys, time
listener = socket.socket()
listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
listener.bind(("127.0.0.1", 0))
listener.listen(1)
open(sys.argv[1], "w").write(str(listener.getsockname()[1]))
connection, _ = listener.accept()
open(sys.argv[2], "w").write("accepted")
time.sleep(20)
connection.close()
PY
  python3 "$BATS_TEST_TMPDIR/listener.py" "$BATS_TEST_TMPDIR/port" "$BATS_TEST_TMPDIR/accepted" &
  listener_pid=$!
  for _ in {1..50}; do [ -s "$BATS_TEST_TMPDIR/port" ] && break; sleep 0.1; done
  port="$(cat "$BATS_TEST_TMPDIR/port")"
  export K3DM_PASSWORD_BUNDLE_PUSHGATEWAY_URL="http://127.0.0.1:$port/metrics" TEST_REAL_CURL=1
  start="$SECONDS"
  run password_bundle_publish
  elapsed=$((SECONDS - start))
  kill "$listener_pid" 2>/dev/null || true
  wait "$listener_pid" 2>/dev/null || true
  [ "$status" -eq 0 ] && [ "$elapsed" -le 15 ]
  [ -f "$BATS_TEST_TMPDIR/accepted" ]
}

@test 'M5 M6 fast publish keeps default limit and leaves no watchdog' {
  add one "$KEY1"
  start="$SECONDS"
  password_bundle_publish
  [ "$((SECONDS - start))" -le 10 ]
  rg -q '^k3dm_password_bundle_publish_success 1$' "$TEST_PUSH_BODY"
  [ -s "$K3DM_PASSWORD_BUNDLE_DIR/service-passwords.age" ]
  [ -s "$K3DM_PASSWORD_BUNDLE_DIR/service-passwords.meta" ]
}

@test 'invalid timeout falls back to 300 seconds with one stderr line' {
  add one "$KEY1"
  export K3DM_PASSWORD_BUNDLE_TIMEOUT=0
  run --separate-stderr password_bundle_publish
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$stderr" | rg -c '^Invalid K3DM_PASSWORD_BUNDLE_TIMEOUT; using 300 seconds\.$')" = 1 ]
}


@test 'N3 payload stays private when encryption hangs after capture' {
  add one "$KEY1"
  export K3DM_PASSWORD_BUNDLE_TIMEOUT=2
  cat > "$BATS_TEST_TMPDIR/bin/make" <<'STUB'
#!/bin/bash
printf 'captured-payload-secret-marker\n'
STUB
  cat > "$BATS_TEST_TMPDIR/bin/age" <<'STUB'
#!/bin/bash
sleep 3600
STUB
  chmod +x "$BATS_TEST_TMPDIR/bin/make" "$BATS_TEST_TMPDIR/bin/age"
  run --separate-stderr password_bundle_publish
  [ "$status" -ne 0 ]
  rg -q '^k3dm_password_bundle_publish_success 0$' "$TEST_PUSH_BODY"
  [[ "$output$stderr" != *captured-payload-secret-marker* ]]
  run rg -l --fixed-strings captured-payload-secret-marker "$K3DM_PASSWORD_BUNDLE_DIR" "$K3DM_PASSWORD_BUNDLE_STATE_DIR"
  [ "$status" -eq 1 ]
}
