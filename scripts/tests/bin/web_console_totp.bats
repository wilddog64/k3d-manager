#!/usr/bin/env bats
# Bats sources the system library at runtime.
# shellcheck disable=SC1090,SC1091,SC2329,SC2030,SC2031

_assert_guard_path() {
  local path="$1" resolved
  resolved=$(PATH="$path" /bin/sh -c 'command -v sudo; command -v launchctl') || return 1
  [ "$resolved" = "$GUARD_BIN/sudo
$GUARD_BIN/launchctl" ]
}

setup() {
  REPO="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
  SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/wct-test.XXXXXX")"
  [ -d "$SCRATCH" ]
  GUARD_BIN="$SCRATCH/guard-bin"
  GUARD_HITS="$SCRATCH/guard-hits"
  mkdir "$GUARD_BIN"
  : > "$GUARD_HITS"
  printf '#!/bin/sh\nprintf "sudo %%s\\n" "$*" >> %q\nexit 97\n' "$GUARD_HITS" > "$GUARD_BIN/sudo"
  printf '#!/bin/sh\nprintf "launchctl %%s\\n" "$*" >> %q\nexit 97\n' "$GUARD_HITS" > "$GUARD_BIN/launchctl"
  chmod 755 "$GUARD_BIN/sudo" "$GUARD_BIN/launchctl"
  export GUARD_BIN GUARD_HITS PATH="$GUARD_BIN:$PATH"
  [ "$(command -v sudo)" = "$GUARD_BIN/sudo" ]
  [ "$(command -v launchctl)" = "$GUARD_BIN/launchctl" ]
  export HOME="$SCRATCH"
  [ "$HOME" = "$SCRATCH" ]
}

teardown() {
  local rc=0
  if [ -s "$GUARD_HITS" ]; then
    cat "$GUARD_HITS"
    rc=1
  fi
  rm -rf -- "$SCRATCH"
  [ "$rc" = 0 ]
}

@test "[M11] docs/howto/web-console-totp.md covers all required topics and named residuals" {
  local doc="$REPO/docs/howto/web-console-totp.md"
  [ -f "$doc" ]
  grep -qi 'enrolment refused under tmux' "$doc"
  grep -qi 'exact lockout rule' "$doc"
  grep -qi 'guess rate' "$doc"
  grep -qi 'second login in the same 30 s step waits for the next code' "$doc"
  grep -q 'TMUX_TMPDIR' "$doc"
  grep -qi 'repair by uninstall --purge-secret and enrol' "$doc"
  grep -qi 'rotate for a lost phone' "$doc"
  for r in R-INSIDER R-ACTIVITY R-DENIAL R-TTY R-SUSPEND R-REVOKE-CODE R-ENROL R-INSTALL R-SUDO; do
    grep -q "$r" "$doc"
  done
  grep -qi 'a program running as the operator can inject wrong codes into a live genuine gate, that they count as failures and can reach the lockout, and that recovery is rotate or the local console' "$doc"
  grep -qi 'that a flooded verifier closes a login, which is then repeated' "$doc"
  # shellcheck disable=SC2016
  grep -Fqi 'Run `make install-web-console-totp` again after a Command Line Tools update to re-verify the new binaries' "$doc"
  grep -qi 'if a login fails after the update, the gate cannot start and console logins fail closed until installation succeeds' "$doc"
  grep -qi 'commit not confirmed; run web-console-totp-status' "$doc"
  grep -Fqi "a rotate attempt refused during that pending window may print \`state damaged\`; wait for the same five-minute expiry and retry rotate" "$doc"
  grep -qi 'a missing framework component may only produce the general refusal' "$doc"
  grep -qi 'SIP not relied on' "$doc"
  grep -qi 'deviation from tmux locking' "$doc"
  grep -qi 'login shell must be zsh' "$doc"
}

@test "[M8] [N5] enroll and rotate wrapper refusals" {
  local bin="$REPO/bin/k3dm-web-console-totp"
  [ -x "$bin" ]
  run env TMUX=1 "$bin" enroll
  [ "$status" -eq 2 ]
  [[ "$output" =~ "refusing to show a secret here" ]]

  run env TMUX_PANE=%1 "$bin" enroll
  [ "$status" -eq 2 ]
  [[ "$output" =~ "refusing to show a secret here" ]]

  run env STY=123 "$bin" enroll
  [ "$status" -eq 2 ]
  [[ "$output" =~ "refusing to show a secret here" ]]

  run env SSH_CONNECTION="1.2.3.4 5678" "$bin" enroll
  [ "$status" -eq 2 ]
  [[ "$output" =~ "refusing to show a secret here" ]]

  run env SSH_TTY="/dev/ttys001" "$bin" enroll
  [ "$status" -eq 2 ]
  [[ "$output" =~ "refusing to show a secret here" ]]

  run "$bin" enroll </dev/null
  [ "$status" -eq 2 ]
  [[ "$output" =~ "refusing to show a secret here" ]]
}

@test "[N11] install refuses when forced-command has unrecognised hash" {
  wct_fixture
  wct_seed_part_a
  printf 'unknown\n' > "$helper/forced-command"
  run "$bin" install
  [ "$status" = 8 ]
  run grep -q 'priv /bin/mv ' "$log"
  [ "$status" = 1 ]
  cp "$helper/forced-command.stub" "$helper/forced-command"
  run "$bin" install
  [ "$status" = 0 ] || { echo "$output"; return 1; }

}

@test "[M9] [N7] [N11] not-installed list contains part C targets" {
  local list="$REPO/scripts/etc/machine/not-installed.list"
  grep -q '^install-web-console-totp|' "$list"
  grep -q '^web-console-totp|' "$list"
}

@test "[M9] Makefile contains install and uninstall totp targets" {
  grep -q '^install-web-console-totp:' "$REPO/Makefile"
  grep -q '^uninstall-web-console-totp:' "$REPO/Makefile"
  grep -q '^web-console-totp-enroll:' "$REPO/Makefile"
  grep -q '^web-console-totp-rotate:' "$REPO/Makefile"
  grep -q '^web-console-totp-status:' "$REPO/Makefile"
}

@test "[N11] gate first line matches CommandLineTools interpreter with -IS" {
  local gate="$REPO/scripts/libexec/k3dm-console-gate.py"
  [ -f "$gate" ]
  local first
  first="$(head -n 1 "$gate")"
  [ "$first" = '#!/Library/Developer/CommandLineTools/usr/bin/python3 -IS' ]
}

@test "[N7] totpd and totpctl first line matches CommandLineTools interpreter with -IS" {
  local totpd="$REPO/scripts/libexec/k3dm-console-totpd.py"
  local totpctl="$REPO/scripts/libexec/k3dm-console-totpctl.py"
  [ -f "$totpd" ]
  [ -f "$totpctl" ]
  [ "$(head -n 1 "$totpd")" = '#!/Library/Developer/CommandLineTools/usr/bin/python3 -IS' ]
  [ "$(head -n 1 "$totpctl")" = '#!/Library/Developer/CommandLineTools/usr/bin/python3 -IS' ]
}

wct_fixture() {
  # Part A embeds its captured shims in its Bats file. Load its two helpers
  # without registering that suite's tests or modifying its fixture.
  local fixture="$SCRATCH/part-a-fixture.bash"
  sed -n '/^wc_fixture() {/,/^}/p; /^wc_pty_run() {/,/^}/p' "$BATS_TEST_DIRNAME/web_console_sshd.bats" > "$fixture"
  source "$fixture"
  wc_fixture
  [ "$K3DM_WC_ROOT" = "$SCRATCH/root" ]
  [ -f "$K3DM_WC_ROOT/.k3dm-wc-fixture" ]
  root="$K3DM_WC_ROOT"
  conf="$root/etc/k3dm-web-console"
  helper="$root/Library/PrivilegedHelperTools/k3dm-web-console"
  log="$root/calls.log"
  bin="$REPO/bin/k3dm-web-console-totp"
  source "$bin"
  mkdir -p "$root${_WCT_PY%/*}" "$root${_WCT_PYAPP%/*}" "$root/opt/homebrew/bin"
  touch "$root$_WCT_PY" "$root$_WCT_PYAPP" "$root$_WCT_PYDYLIB" "$root/opt/homebrew/bin/tmux"
  chmod 755 "$root$_WCT_PY" "$root$_WCT_PYAPP" "$root$_WCT_PYDYLIB" "$root/opt/homebrew/bin/tmux"
  cat > "$root/bin/python3" <<'SH'
#!/bin/bash
[[ -f "$K3DM_WC_ROOT/.k3dm-wc-fixture" ]] || exit 99
case "$2" in
  -c) /usr/bin/python3 "$@" ;;
  *) case "$3" in
       status) /bin/cat "$K3DM_WC_ROOT/wire" ;;
       enroll|rotate) exit 0 ;;
       *) exit 2 ;;
     esac ;;
esac
SH
  chmod +x "$root/bin/python3"
  rm "$root/bin/launchctl"
  # Keep the executable name used by the captured Part A shim.
  mkdir "$root/a-tools"
  ln -s ../shim "$root/a-tools/launchctl"
  cat > "$root/bin/launchctl" <<'SH'
#!/bin/bash
[[ -f "$K3DM_WC_ROOT/.k3dm-wc-fixture" ]] || exit 99
case "$*" in
  *web-console-totp*) ;;
  *) exec "$K3DM_WC_ROOT/a-tools/launchctl" "$@" ;;
esac
case "$1" in
  print)
    if [[ -e "$K3DM_WC_ROOT/totp-job" ]]; then exit 0; fi
    # m4-air, Nov 19 2026: c12-absent.txt, with the fixture label substituted.
    /usr/bin/sed -n '/Could not find service/s/capture-sshd/web-console-totp/p' "$WC_CAPTURE_DIR/c12-absent.txt" >&2
    exit 113 ;;
  bootout)
    [[ -e "$K3DM_WC_ROOT/job-stays" ]] || /bin/rm -f "$K3DM_WC_ROOT/totp-job" ;;
  bootstrap)
    [[ ! -e "$K3DM_WC_ROOT/fail-bootstrap" ]] || exit 1
    /usr/bin/touch "$K3DM_WC_ROOT/totp-job" ;;
esac
SH
  chmod +x "$root/bin/launchctl"
  printf 'NOT_ENROLLED\n' > "$root/wire"
  : > "$log"
}

wct_seed_part_a() {
  run "$WC_BIN" install --ca-file "$HOME/ca.pub"
  [ "$status" = 0 ] || { echo "$output"; return 1; }
  [ "$(awk '$3=="A" {n++} END {print n}' "$conf/manifest")" = 6 ]
  : > "$log"
}

@test "[M9] [N11] incomplete part A refuses and complete pair repeats without moves" {
  wct_fixture
  run "$WC_BIN" install
  [ "$status" = 3 ]
  [ -f "$conf/launchd.plist.pending" ]
  : > "$log"
  run "$bin" install
  [ "$status" = 2 ]
  [[ "$output" = *'part A incomplete (CA missing or daemon not loaded); finish make install-web-console-sshd first'* ]]
  run grep -q 'priv /bin/mv ' "$log"
  [ "$status" = 1 ]
  wct_seed_part_a
  run "$bin" install
  [ "$status" = 0 ] || { echo "$output"; return 1; }
  [ "$(awk '$3=="C"{n++} END{print n}' "$conf/manifest")" = 5 ]
  grep -Fxq 'console_port=42722' "$conf/totp.conf"
  grep -Fxq 'tmux=/opt/homebrew/bin/tmux' "$conf/totp.conf"
  awk '/totpctl status --wire/ && !ready {ready=NR} /priv \/bin\/mv .*\/forced-command$/{move=NR} END{exit !(ready && move>ready)}' "$log"
  : > "$log"
  run "$bin" install
  [ "$status" = 0 ] && [[ "$output" = *'already installed'* ]]
  run grep -Eq 'priv /bin/mv |bootout' "$log"
  [ "$status" = 1 ]
  printf 'UNAVAILABLE\n' > "$root/wire"
  run "$bin" install
  [ "$status" = 5 ]
  [[ "$output" = *'verifier state damaged;'* ]]
  run grep -q 'priv /bin/mv ' "$log"
  [ "$status" = 1 ]
}

@test "[M9] home tmux refused before staging" {
  wct_fixture
  wct_seed_part_a
  mkdir -p "$root$HOME"
  touch "$root$HOME/tmux"
  chmod 755 "$root$HOME/tmux"
  run "$bin" install --tmux "$HOME"
  [ "$status" = 2 ]
  run "$bin" install --tmux ""
  [ "$status" = 2 ]
  run "$bin" install --tmux "$HOME/tmux"
  [ "$status" = 2 ]
  run grep -q 'priv /bin/mv ' "$log"
  [ "$status" = 1 ]
  run "$bin" install --dry-run --tmux /opt/homebrew/bin/tmux
  [ "$status" = 0 ]
}

@test "[M9] partially removed verifier retried after part A is gone" {
  wct_fixture
  [ ! -e "$conf/manifest" ] && [ ! -d "$helper" ]
  mkdir "$root$_WCT_RUN_DIR"
  touch "$root$_WCT_LOG" "$root/totp-job" "$root/job-stays"
  run "$bin" uninstall
  [ "$status" = 1 ]
  [[ "$output" != *'not installed'* ]]
  [ ! -e "$root$_WCT_LOG" ] && [ ! -e "$root$_WCT_RUN_DIR" ]
  run "$bin" uninstall
  [ "$status" = 1 ]
  rm "$root/job-stays"
  run "$bin" uninstall
  [ "$status" = 0 ]
  [ ! -e "$root/totp-job" ] && [ ! -d "$helper" ] && [ ! -e "$conf/manifest" ]
  run "$bin" uninstall
  [ "$status" = 0 ] && [[ "$output" = *'web-console-totp: not installed'* ]]
}

@test "[M8] [N5] wrapper refuses every unsafe terminal before opening privilege" {
  wct_fixture
  rm "$root/bin/id"
  cat > "$root/bin/id" <<'SH'
#!/bin/bash
[[ -f "$K3DM_WC_ROOT/.k3dm-wc-fixture" ]] || exit 99
if [[ -t 0 ]]; then /bin/cat "$K3DM_WC_ROOT/uid"; else echo 0; fi
SH
  chmod 755 "$root/bin/id"
  local verb key reason
  wc_pty_run /bin/bash -c 'test -t 0 && test -t 1'
  unset TMUX TMUX_PANE STY SSH_CONNECTION SSH_TTY
  for verb in enroll rotate; do
    printf '501\n' > "$root/uid"
    for key in TMUX TMUX_PANE STY SSH_CONNECTION SSH_TTY; do
      : > "$log"
      case "$key" in SSH*) reason='over SSH' ;; *) reason='inside tmux or screen' ;; esac
      run wc_pty_run env "$key=1" "$bin" "$verb"
      [ "$status" = 2 ]
      [[ "$output" = *"web-console-totp: refusing to show a secret here: $reason"* ]]
      run grep -Eq 'priv_open|^priv ' "$log"
      [ "$status" = 1 ]
    done
    # Arguments expand in the child shell.
    # shellcheck disable=SC2016
    run wc_pty_run /bin/bash -c '"$1" "$2" </dev/null' _ "$bin" "$verb"
    [ "$status" = 2 ] && [[ "$output" = *'stdin or stdout is not a tty'* ]]
    # Arguments expand in the child shell.
    # shellcheck disable=SC2016
    run wc_pty_run /bin/bash -c 'set -o pipefail; "$1" "$2" | /bin/cat' _ "$bin" "$verb"
    [ "$status" = 2 ] && [[ "$output" = *'stdin or stdout is not a tty'* ]]
    run wc_pty_run python3 -c 'import subprocess,sys; sys.exit(subprocess.call(sys.argv[1:],start_new_session=True))' "$bin" "$verb"
    [ "$status" = 2 ] && [[ "$output" = *'/dev/tty not accessible'* ]]
    echo 0 > "$root/uid"
    run wc_pty_run "$bin" "$verb"
    [ "$status" = 2 ] && [[ "$output" = *'running as root'* ]] || {
      echo "root refusal failed for $verb: status=$status output=$output"
      return 1
    }
    run grep -Eq 'priv_open|^priv ' "$log"
    [ "$status" = 1 ]
    echo 501 > "$root/uid"
    run wc_pty_run "$bin" "$verb"
    [ "$status" = 0 ] || { echo "$output"; return 1; }
    grep -Fxq priv_open "$log"
    [ "$(grep -c "totpctl $verb$" "$log")" = 1 ]
  done
}

@test "[M9] [M12] [N11] install recovers unfinished part A before refusing it" {
  wct_fixture
  mkdir "$conf"
  printf '1 created /etc/k3dm-web-console -\n' > "$root/var/db/k3dm-web-console.txn"
  run "$bin" install
  [ "$status" = 2 ]
  [[ "$output" = *'rolled back an interrupted install'*'part A is not installed'* ]]
  [ ! -e "$root/var/db/k3dm-web-console.txn" ]
  [ ! -e "$conf" ]
}

@test "[M9] [M12] [N11] install recovers a moved C manifest before custody and respects revoke" {
  wct_fixture
  wct_seed_part_a
  cp "$conf/manifest" "$conf/.prev/manifest"
  printf 'partial C generation\n' > "$conf/manifest"
  printf '1 moved /etc/k3dm-web-console/manifest /etc/k3dm-web-console/.prev/manifest\n' > "$root/var/db/k3dm-web-console.txn"
  run "$bin" install
  [ "$status" = 0 ] || { echo "$output"; return 1; }
  [[ "$output" = *'rolled back an interrupted install'* ]]
  run "$WC_BIN" install
  [ "$status" = 0 ]
  cmp "$helper/forced-command" "$REPO/scripts/libexec/k3dm-console-gate.py"
  run env WEB_CONSOLE_SSH_PORT=42723 "$WC_BIN" install
  [ "$status" = 2 ]
  run "$WC_BIN" uninstall
  [ "$status" = 6 ]
  : > "$log"
  run "$bin" uninstall
  [ "$status" = 0 ] || { echo "$output"; return 1; }
  cmp "$helper/forced-command" "$helper/forced-command.stub"
  [ "$(awk '$3=="A"{n++} END{print n}' "$conf/manifest")" = 6 ]
  awk '/priv \/bin\/mv .*\/forced-command$/ {stub=NR} /priv \/bin\/mv .*\/manifest$/ {manifest=NR}
       /priv .*bootout/ {stop=NR} /priv \/bin\/rm .*\/totpd$/ {remove=NR}
       END{exit !(stub && manifest>stub && stop>manifest && remove>stop)}' "$log"
  [ "$(awk -v journal="$_WCT_JOURNAL" 'index($0,"priv /usr/bin/install -o root -g wheel -m 0600") && index($0,journal) {n++} END{print n+0}' "$log")" = 1 ]
  [ -d "$root$_WCT_STATE_DIR" ]
  run "$WC_BIN" check
  [[ "$output" = *'PASS C1 '* ]]
  run "$bin" uninstall --purge-secret
  [ "$status" = 0 ]
  [ ! -d "$root$_WCT_STATE_DIR" ]
  run "$WC_BIN" uninstall
  [ "$status" = 0 ]
}

@test "[M9] [N7] [N11] trust and source failures precede moves" {
  wct_fixture
  wct_seed_part_a
  local ancestor="$root${_WCT_PYDYLIB%/*}"
  chmod 0775 "$ancestor"
  run "$bin" install
  [ "$status" = 8 ]
  chmod 0755 "$ancestor"
  touch "$root/fail.acl.k3dm-web-console"
  run "$bin" install
  [ "$status" = 8 ]
  rm "$root/fail.acl.k3dm-web-console"
  chmod 0775 "$root/Library/PrivilegedHelperTools"
  run "$bin" install
  [ "$status" = 8 ]
  chmod 0755 "$root/Library/PrivilegedHelperTools"
  echo scripts/lib/web_console_common.sh > "$root/changed-source"
  run "$bin" install
  [ "$status" = 9 ]
  rm "$root/changed-source"
  touch "$root/fail.rehash"
  run "$bin" install
  [ "$status" = 8 ]
  rm "$root/fail.rehash"
  run grep 'priv /bin/mv ' "$log"
  [ "$status" = 1 ]
  run "$bin" install
  [ "$status" = 0 ] || { echo "$output"; return 1; }
}

@test "[M9] [N11] unavailable or lowercase status keeps the first-install stub" {
  wct_fixture
  wct_seed_part_a
  local answer
  for answer in UNAVAILABLE enrolled; do
    echo "$answer" > "$root/wire"
    run "$bin" install
    [ "$status" = 5 ] || { echo "$output"; return 1; }
    cmp "$helper/forced-command" "$helper/forced-command.stub"
    [ ! -e "$root/totp-job" ]
    [ "$(awk '$3=="A"{n++} END{print n}' "$conf/manifest")" = 6 ]
  done
  echo ENROLLED > "$root/wire"
  run "$bin" install
  [ "$status" = 0 ]
  cmp "$helper/forced-command" "$REPO/scripts/libexec/k3dm-console-gate.py"
}

@test "[N7] [M9] part C stays out of machine installation and secret lists" {
  local lists="$REPO/scripts/etc/machine" file
  grep -q '^web-console-totp|' "$lists/not-installed.list"
  for file in "$lists"/agents.*.list "$lists"/secrets.*.list "$lists"/hub-{local,singletons}.list; do
    [ -f "$file" ] || continue
    run grep -F web-console "$file"
    [ "$status" = 1 ]
  done
}

@test "[M9] [N11] repair installed bytes and restore previous generation after failed upgrade" {
  wct_fixture
  wct_seed_part_a
  run "$bin" install
  [ "$status" = 0 ]
  printf 'replacement\n' >> "$helper/totpd"
  : > "$log"
  run "$bin" install
  [ "$status" = 0 ]
  cmp "$REPO/scripts/libexec/k3dm-console-totpd.py" "$helper/totpd"
  grep -q 'priv /bin/launchctl bootout' "$log"
  cp "$conf/manifest" "$SCRATCH/before"
  cp "$helper/forced-command" "$SCRATCH/gate"
  mkdir -p "$root/usr/local/bin"
  touch "$root/usr/local/bin/tmux" "$root/fail-bootstrap"
  chmod 755 "$root/usr/local/bin/tmux"
  : > "$log"
  run "$bin" install --tmux /usr/local/bin/tmux
  [ "$status" = 5 ]
  cmp "$conf/manifest" "$SCRATCH/before"
  cmp "$helper/forced-command" "$SCRATCH/gate"
  grep -Fxq 'tmux=/opt/homebrew/bin/tmux' "$conf/totp.conf"
  [ "$(grep -c 'priv /bin/launchctl bootstrap' "$log")" = 2 ]
}

@test "[M9] [N7] tmux resolution, syntax validation, modes and wire readiness" {
  wct_fixture
  wct_seed_part_a
  rm "$root/opt/homebrew/bin/tmux"
  mkdir -p "$root/usr/local/bin"
  touch "$root/usr/local/bin/tmux"
  run "$bin" install --dry-run --tmux /usr/local/bin/tmux
  [ "$status" = 2 ]
  run "$bin" install
  [ "$status" = 2 ]
  mkdir -p "$SCRATCH/early"
  touch "$SCRATCH/early/tmux"
  chmod 755 "$SCRATCH/early/tmux" "$root/usr/local/bin/tmux"
  _assert_guard_path "$GUARD_BIN:$SCRATCH/early:$PATH"
  run env PATH="$GUARD_BIN:$SCRATCH/early:$PATH" "$bin" install --dry-run
  [ "$status" = 0 ]
  [[ "$output" = *'using /usr/local/bin/tmux'* ]]
  touch "$root/fail.plutil"
  run "$bin" install
  [ "$status" = 4 ]
  rm "$root/fail.plutil"
  # The shims' git reader treats this scratch tree as its HEAD.
  cp -R "$REPO/scripts/libexec" "$SCRATCH/source"
  mkdir -p "$SCRATCH/blobs/scripts/etc/launchd"
  mv "$SCRATCH/source" "$SCRATCH/blobs/scripts/libexec"
  cp "$REPO/$_WCT_PLIST_TEMPLATE" "$SCRATCH/blobs/$_WCT_PLIST_TEMPLATE"
  ln -s "$REPO/bin" "$SCRATCH/blobs/bin"
  ln -s "$REPO/scripts/lib" "$SCRATCH/blobs/scripts/lib"
  export WC_FIXTURE_REPO="$SCRATCH/blobs"
  echo 'if (' >> "$WC_FIXTURE_REPO/$_WCT_GATE_SOURCE"
  run "$bin" install
  [ "$status" = 4 ]
  { echo '#!/bin/false'; tail -n +2 "$REPO/$_WCT_GATE_SOURCE"; } > "$WC_FIXTURE_REPO/$_WCT_GATE_SOURCE"
  run "$bin" install
  [ "$status" = 4 ]
  run grep 'priv /bin/mv ' "$log"
  [ "$status" = 1 ]
  cp "$REPO/$_WCT_GATE_SOURCE" "$WC_FIXTURE_REPO/$_WCT_GATE_SOURCE"
  run "$bin" install
  [ "$status" = 0 ]
  grep -Fxq 'tmux=/usr/local/bin/tmux' "$conf/totp.conf"
  python3 - "$root" <<'PY'
import os, plistlib, stat, sys
from pathlib import Path
root = Path(sys.argv[1])
assert (root / ".k3dm-wc-fixture").is_file()
helper = root / "Library/PrivilegedHelperTools/k3dm-web-console"
conf = root / "etc/k3dm-web-console/totp.conf"
assert {s.split("=")[0] for s in conf.read_text().splitlines()} == {"uid","tmux","idle_seconds","console_port"}
plist = root / "Library/LaunchDaemons/com.k3d-manager.web-console-totp.plist"
spec = plistlib.loads(plist.read_bytes())
for location in (str(root), os.environ["WC_FIXTURE_REPO"], os.environ["HOME"]):
    assert location not in plist.read_text() and location not in conf.read_text()
assert "/opt/homebrew" not in plist.read_text()
calls = (root / "calls.log").read_text().splitlines()
installs = [line for line in calls if line.startswith("priv /usr/bin/install ")]
for name in ("totpd", "totpctl", "forced-command", "totp.conf", plist.name, "manifest",
             "k3dm-web-console-run", "k3dm-web-console", "k3dm-web-console-totp.log"):
    assert any(line.endswith("/" + name) and "-o root -g wheel" in line for line in installs), name
assert spec["KeepAlive"] and spec["RunAtLoad"] and spec["ThrottleInterval"] == 10
assert spec["ProgramArguments"] == ["/Library/Developer/CommandLineTools/usr/bin/python3", "-IS",
                                    "/Library/PrivilegedHelperTools/k3dm-web-console/totpd"]
for p, expected in [(helper / n, 0o755) for n in ("forced-command","totpd","totpctl")] + [
    (plist,0o644),(conf,0o644),(root/"var/db/k3dm-web-console",0o700),
    (root/"var/db/k3dm-web-console-run",0o755),(root/"var/log/k3dm-web-console-totp.log",0o600)]:
    assert stat.S_IMODE(p.stat().st_mode) == expected, p
PY
}

@test "[M9] [N11] uninstall verifies stub, restores both moves on failure and resumes partial cleanup" {
  wct_fixture
  wct_seed_part_a
  run "$bin" install
  [ "$status" = 0 ]
  cp "$helper/forced-command.stub" "$SCRATCH/stub"
  cp "$conf/manifest" "$SCRATCH/manifest"
  cp "$helper/forced-command" "$SCRATCH/entry"
  echo damaged >> "$helper/forced-command.stub"
  : > "$log"
  run "$bin" uninstall
  [ "$status" = 8 ]
  run grep 'priv /bin/mv ' "$log"
  [ "$status" = 1 ]
  cp "$SCRATCH/stub" "$helper/forced-command.stub"
  echo 0 > "$root/renames"
  echo 2 > "$root/bad-move"
  run "$bin" uninstall
  [ "$status" = 5 ]
  cmp "$SCRATCH/manifest" "$conf/manifest"
  cmp "$SCRATCH/entry" "$helper/forced-command"
  rm "$root/bad-move"
  touch "$root/job-stays"
  run "$bin" uninstall
  [ "$status" = 1 ]
  cmp "$SCRATCH/stub" "$helper/forced-command"
  [ ! -f "$root/Library/LaunchDaemons/${_WCT_LABEL}.plist" ]
  run "$bin" uninstall
  [ "$status" = 1 ]
  [[ "$output" != *'not installed'* ]]
  rm "$root/job-stays"
  run "$bin" uninstall
  [ "$status" = 0 ]
}

@test "[M12] [N11] recovery from C preserves the revoked console marker" {
  wct_fixture
  wct_seed_part_a
  local label=com.k3d-manager.web-console-sshd.plist verb
  cp "$root/Library/LaunchDaemons/$label" "$conf/.prev/$label"
  run "$WC_BIN" revoke
  [ "$status" = 0 ]
  for verb in install uninstall; do
    printf '1 moved /Library/LaunchDaemons/%s /etc/k3dm-web-console/.prev/%s\n' "$label" "$label" > "$root/var/db/k3dm-web-console.txn"
    run "$bin" "$verb"
    [ "$status" = 0 ] || { echo "$output"; return 1; }
    [[ "$output" = *'rolled back an interrupted install'* ]]
    [ -f "$conf/revoked" ]
    [ ! -e "$root/Library/LaunchDaemons/$label" ]
  done
  touch "$root/fail-bootstrap"
  run "$bin" install
  [ "$status" = 5 ] && [ ! -e "$root/Library/LaunchDaemons/$label" ]
  touch "$root/fail.print"
  run "$bin" install
  [ "$status" = 1 ]
}

@test "[M12] exit cleanup reconciles a marker created during C install" {
  wct_fixture
  wct_seed_part_a
  mkdir "$root/launchd-tools"
  mv "$root/bin/launchctl" "$root/launchd-tools/launchctl"
  cat > "$root/bin/launchctl" <<'SH'
#!/bin/bash
[[ -f "$K3DM_WC_ROOT/.k3dm-wc-fixture" ]] || exit 99
if [[ "$1" = bootstrap && "$*" = *web-console-totp* ]]; then
  : > "$K3DM_WC_ROOT/etc/k3dm-web-console/revoked"
fi
exec "$K3DM_WC_ROOT/launchd-tools/launchctl" "$@"
SH
  chmod 755 "$root/bin/launchctl"
  run "$bin" install
  [ "$status" = 0 ] || { echo "$status $output"; return 1; }
  [ -f "$conf/revoked" ]
  [ ! -e "$root/Library/LaunchDaemons/com.k3d-manager.web-console-sshd.plist" ]
  [ -e "$root/Library/LaunchDaemons/${_WCT_LABEL}.plist" ]
  [ -f "$conf/launchd.plist.revoked" ]
}

@test "[M12] [N6] console port comes only from installed sshd config" {
  wct_fixture
  wct_seed_part_a
  sed '1s/42722/43001/' "$conf/sshd_config" > "$SCRATCH/sshd_config"
  cp "$SCRATCH/sshd_config" "$conf/sshd_config"
  run env WEB_CONSOLE_SSH_PORT=43002 "$bin" install
  [ "$status" = 0 ] || { echo "$output"; return 1; }
  grep -Fxq console_port=43001 "$conf/totp.conf"
  printf 'Port 43002\n' > "$conf/sshd_config"
  run "$bin" install --dry-run
  [ "$status" = 2 ]
}

@test "[M9] [N11] interpreter and file custody refusal controls" {
  wct_fixture
  wct_seed_part_a
  local py="$root$_WCT_PY"
  mv "$py" "$py.real"
  ln -s python3.real "$py"
  echo 501 > "$root/owner.python3"
  run "$bin" install
  [ "$status" = 8 ]
  rm "$root/owner.python3"
  chmod 0775 "$py.real"
  run "$bin" install
  [ "$status" = 8 ]
  chmod 0755 "$py.real"
  ln -s "$SCRATCH/outside" "$helper/totpctl"
  run "$bin" install
  [ "$status" = 8 ]
  [ ! -e "$SCRATCH/outside" ]
  rm "$helper/totpctl"
  mkdir "$root/var/db/k3dm-web-console.lock"
  run "$bin" install
  [ "$status" = 7 ]
  run "$bin" uninstall
  [ "$status" = 7 ]
  rmdir "$root/var/db/k3dm-web-console.lock"
  touch "$root/fail.sleep"
  run "$bin" install
  [ "$status" = 10 ]
  run "$bin" uninstall
  [ "$status" = 10 ]
  rm "$root/fail.sleep"
  run "$bin" install
  [ "$status" = 0 ]
}

@test "[N5] wrapper delegates secret handling to totpctl" {
  wct_fixture
  # Inspect the two entry functions, then prove the wrapper reaches the client.
  local body verb
  for verb in enroll rotate; do
    body="$(declare -f "_wct_$verb")"
    run grep -E 'ENROLL_|ROTATE_|read[[:space:]]|SECRET|admin\.sock|sudo[[:space:]]' <<< "$body"
    [ "$status" = 1 ]
    # Match the literal command in the wrapper.
    # shellcheck disable=SC2016
    grep -Fq '_wc_priv "$_WCT_PY" -IS' <<< "$body"
  done
}

@test "[M8] [N5] enroll calls the shared privilege wrapper, never bare sudo" {
  [ "$HOME" = "$SCRATCH" ]
  [ -d "$GUARD_BIN" ]
  local priv_hits="$SCRATCH/priv-hits"
  run /bin/bash -c '
    source "$1"
    GUARD_BIN="$2" GUARD_HITS="$3" PRIV_HITS="$4"
    PATH="$GUARD_BIN:/usr/bin:/bin"
    [ "$(command -v sudo)" = "$GUARD_BIN/sudo" ] || exit 90
    [ "$(command -v launchctl)" = "$GUARD_BIN/launchctl" ] || exit 91
    _wc_priv() { printf "%s\n" "$*" >> "$PRIV_HITS"; }
    _wc_priv_open() { return 0; }
    _wct_refusal_check() { return 0; }
    _WCT_PY=/fixture/python
    _wct_enroll
  ' _ "$REPO/bin/k3dm-web-console-totp" "$GUARD_BIN" "$GUARD_HITS" "$priv_hits"
  [ "$status" = 0 ] || { echo "$output"; return 1; }
  grep -Fq '/fixture/python -IS' "$priv_hits" && grep -Fq 'totpctl enroll' "$priv_hits"
  [ ! -s "$GUARD_HITS" ]
}

@test "[M9] [N11] repair when daemon is unreachable and retry a failed first bootstrap" {
  wct_fixture
  wct_seed_part_a
  touch "$root/fail-bootstrap"
  run "$bin" install
  [ "$status" = 5 ]
  cmp "$helper/forced-command" "$helper/forced-command.stub"
  rm "$root/fail-bootstrap"
  run "$bin" install
  [ "$status" = 0 ]
  # The injected code reads the shim's arguments.
  # shellcheck disable=SC2016
  sed -i.bak '/case "$2" in/i\
if [[ "$3" = status && ! -f "$K3DM_WC_ROOT/totp-job" ]]; then exit 1; fi
' "$root/bin/python3"
  rm "$root/totp-job"
  : > "$log"
  run "$bin" install
  [ "$status" = 0 ]
  grep -q 'priv /bin/launchctl bootstrap' "$log"
}

@test "[M9] [N11] uninstall reports a remaining artifact and retries its removal" {
  wct_fixture
  wct_seed_part_a
  run "$bin" install
  [ "$status" = 0 ]
  mkdir "$root/rm-tools"
  ln -s ../shim "$root/rm-tools/rm"
  rm "$root/bin/rm"
  cat > "$root/bin/rm" <<'SH'
#!/bin/bash
[[ -f "$K3DM_WC_ROOT/.k3dm-wc-fixture" ]] || exit 99
for arg do [[ "$arg" != "$K3DM_WC_ROOT/var/log/k3dm-web-console-totp.log" ]] || exit 1; done
exec "$K3DM_WC_ROOT/rm-tools/rm" "$@"
SH
  chmod 755 "$root/bin/rm"
  run "$bin" uninstall
  [ "$status" = 1 ]
  [ -f "$root$_WCT_LOG" ]
  cmp "$helper/forced-command" "$helper/forced-command.stub"
  rm "$root/bin/rm"
  ln -s ../shim "$root/bin/rm"
  run "$bin" uninstall
  [ "$status" = 0 ]
  [ ! -e "$root$_WCT_LOG" ]
}

@test "[M9] [N11] source changes from HEAD are refused even when syntax is valid" {
  wct_fixture
  wct_seed_part_a
  mkdir -p "$SCRATCH/blobs/scripts/libexec" "$SCRATCH/blobs/scripts/etc/launchd"
  cp "$REPO/scripts/libexec/"*.py "$SCRATCH/blobs/scripts/libexec/"
  cp "$REPO/$_WCT_PLIST_TEMPLATE" "$SCRATCH/blobs/$_WCT_PLIST_TEMPLATE"
  ln -s "$REPO/bin" "$SCRATCH/blobs/bin"
  ln -s "$REPO/scripts/lib" "$SCRATCH/blobs/scripts/lib"
  export WC_FIXTURE_REPO="$SCRATCH/blobs"
  printf '\n# valid source drift\n' >> "$WC_FIXTURE_REPO/$_WCT_GATE_SOURCE"
  printf '%s\n' scripts/libexec/k3dm-console-gate.py > "$root/changed-source"
  run "$bin" install
  [ "$status" = 9 ] || { echo "$status $output"; return 1; }
  [[ "$output" = *'sources differ from HEAD'* ]] || { echo "$output"; return 1; }
  run grep -q 'priv /bin/mv ' "$log"
  [ "$status" = 1 ]
}

@test "[M9] [N11] tracked source drift is refused before any move" {
  wct_fixture
  wct_seed_part_a
  mkdir -p "$SCRATCH/blobs/scripts/libexec" "$SCRATCH/blobs/scripts/etc/launchd"
  cp "$REPO/scripts/libexec/"*.py "$SCRATCH/blobs/scripts/libexec/"
  cp "$REPO/$_WCT_PLIST_TEMPLATE" "$SCRATCH/blobs/$_WCT_PLIST_TEMPLATE"
  ln -s "$REPO/bin" "$SCRATCH/blobs/bin"
  ln -s "$REPO/scripts/lib" "$SCRATCH/blobs/scripts/lib"
  export WC_FIXTURE_REPO="$SCRATCH/blobs"
  [ -d "$WC_FIXTURE_REPO" ]
  [ -f "$root/.k3dm-wc-fixture" ]
  [ "$root" = "$K3DM_WC_ROOT" ]
  printf '%s\n' bin/k3dm-web-console-totp > "$root/changed-source"
  [ -f "$root/changed-source" ]
  [ "$(cat "$root/changed-source")" = bin/k3dm-web-console-totp ]
  run "$bin" install
  [ "$status" = 9 ] || { echo "$status $output"; return 1; }
  [[ "$output" = *'sources differ from HEAD'* ]] || { echo "$output"; return 1; }
  run grep -q 'priv /bin/mv ' "$log"
  [ "$status" = 1 ]
}

@test "[M9] [N7] PYAPP trust failure refuses before any move" {
  wct_fixture
  wct_seed_part_a
  [ -f "$root/.k3dm-wc-fixture" ]
  [ "$root" = "$K3DM_WC_ROOT" ]
  touch "$root/fail.acl.Python"
  [ -f "$root/fail.acl.Python" ]
  run "$bin" install
  [ "$status" = 8 ] || { echo "$status $output"; return 1; }
  run grep -q 'priv /bin/mv ' "$log"
  [ "$status" = 1 ]
}

@test "[M9] [N11] incomplete part A members refuse even without a pending plist" {
  wct_fixture
  wct_seed_part_a
  sed -i.bak '\|access_ca.pub|d' "$conf/manifest"
  rm -f "$conf/launchd.plist.pending"
  run "$bin" install
  [ "$status" = 2 ]
  [[ "$output" = *'part A incomplete'* ]]
  run grep -q 'priv /bin/mv ' "$log"
  [ "$status" = 1 ]
}

@test "[M9] [N7] only fixed tmux locations are resolved" {
  wct_fixture
  wct_seed_part_a
  mkdir -p "$SCRATCH/early"
  touch "$SCRATCH/early/tmux"
  chmod 755 "$SCRATCH/early/tmux"
  PATH="$GUARD_BIN:$SCRATCH/early:$PATH"
  _assert_guard_path "$PATH"
  _WC_PREFIX="$root"
  run _wct_find_tmux
  [ "$status" = 0 ]
  [ "$output" = /opt/homebrew/bin/tmux ]
}

@test "[M9] main resets PATH and removes a sudo function" {
  wct_fixture
  # Exercise the function in a child shell so Bats' own helper scope cannot
  # affect whether the local sudo function is removed.
  run /bin/bash -c 'source "$1"; PATH="$2:/scratch:/tmp"; [ "$(command -v sudo)" = "$2/sudo" ] && [ "$(command -v launchctl)" = "$2/launchctl" ] || exit 90; sudo() { return 99; }; _wct_main_env; declare -F sudo && exit 1; printf "%s\n" "$PATH"' _ "$REPO/bin/k3dm-web-console-totp" "$GUARD_BIN"
  [ "$status" = 0 ]
  [ "$output" = /usr/bin:/bin:/usr/sbin:/sbin ]
}

@test "[M9] [N11] checkout paths are refused as tmux executables" {
  wct_fixture
  wct_seed_part_a
  mkdir -p "$root$REPO/bin"
  ln -s "$REPO/bin/k3dm-web-console-totp" "$root$REPO/bin/k3dm-web-console-totp"
  run _wct_realpath "$REPO/bin/k3dm-web-console-totp"
  [ "$status" = 0 ] && [ "$output" = "$REPO/bin/k3dm-web-console-totp" ] || { echo "resolved=$output"; return 1; }
  run "$bin" install --tmux "$REPO/bin/k3dm-web-console-totp"
  [ "$status" = 2 ] || { echo "$status $output"; return 1; }
  [[ "$output" = *'tmux path outside HOME and checkout required'* ]] || { echo "$output"; return 1; }
  rm "$root/opt/homebrew/bin/tmux"
  ln -s "$root$REPO/bin/k3dm-web-console-totp" "$root/opt/homebrew/bin/tmux"
  run "$bin" install --tmux /opt/homebrew/bin/tmux
  [ "$status" = 2 ] || { echo "$status $output"; return 1; }
  [[ "$output" = *'tmux path outside HOME and checkout required'* ]] || { echo "$output"; return 1; }
}
