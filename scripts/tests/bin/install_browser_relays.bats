#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
  SCRIPT="${REPO_ROOT}/bin/install-browser-relays.sh"
  export K3DM_LAUNCHD_DIR="${BATS_TEST_TMPDIR}/LaunchDaemons"
  mkdir -p "$K3DM_LAUNCHD_DIR"
  [[ "$K3DM_LAUNCHD_DIR" == "${BATS_TEST_TMPDIR}"/* ]]
  export HOME="${BATS_TEST_TMPDIR}/home"
  mkdir -p "$HOME"
  [[ "$HOME" == "${BATS_TEST_TMPDIR}"/* ]]
}

# Read-only capture on m4-air.local, 2026-11-06:
# /usr/bin/stat -f '%Su' /etc/passwd printed root; the same command on
# ~/.local/share/k3d-manager/logs/frontend-browser-http.log printed cliang.
# GNU stat -c '%U' /etc/passwd printed root; /usr/bin/stat -c '%U'
# /etc/passwd printed "illegal option -- c" and exited 1.
setup_owner_fixture() {
  export LOGS="$HOME/.local/share/k3d-manager/logs"
  export CALLS="$BATS_TEST_TMPDIR/chown.log" STAT_CALLS="$BATS_TEST_TMPDIR/stat.log"
  export STUBS="$BATS_TEST_TMPDIR/stubs"
  [[ "$HOME" == "$BATS_TEST_TMPDIR"/* ]]
  [[ "$LOGS" == "$HOME"/* && "$CALLS" == "$BATS_TEST_TMPDIR"/* ]]
  mkdir -p "$LOGS/subdir" "$STUBS"
  touch "$LOGS/frontend-browser-http.log" "$LOGS/argocd-browser-https.log" \
    "$LOGS/keycloak-browser-http.log" "$LOGS/keycloak-browser-http-launchctl.log" \
    "$LOGS/argocd-browser-https-launchctl.log" "$LOGS/user-browser-http.log" \
    "$LOGS/unrelated.log" "$LOGS/subdir/nested-browser-http.log"
  ln -s "$LOGS/frontend-browser-http.log" "$LOGS/symlink-browser-http.log"
  : > "$CALLS"
  : > "$STAT_CALLS"
  cat > "$STUBS/stat" <<'SH'
#!/bin/sh
printf '%s\n' "$1" >> "$STAT_CALLS"
case "$STAT_STYLE:$1:$2:$3" in
  bsd:-c:%U:--) exit 1 ;;
  bsd:-f:%Su:--|gnu:-c:%U:--) ;;
  *) exit 2 ;;
esac
case "$4" in
  */user-browser-http.log) echo cliang ;;
  *) echo root ;;
esac
SH
  cat > "$STUBS/id" <<'SH'
#!/bin/sh
case "$1" in
  -u) echo "${FAKE_UID:-501}" ;;
  -un) echo cliang ;;
  *) exit 2 ;;
esac
SH
  chmod +x "$STUBS/stat" "$STUBS/id"
  export PATH="$STUBS:$PATH" STAT_STYLE=gnu
}

run_relay_fixture() {
  run env CALLS="$CALLS" bash -c '
    _run_command() {
      case "$*" in
        *"/usr/sbin/chown"*)
          printf "%s\n" "$*" >> "$CALLS"
          if [[ "${FAIL_CHOWN:-0}" == 1 ]]; then return 1; fi
          ;;
      esac
      return 0
    }
    export -f _run_command
    exec "$@"
  ' _ "$SCRIPT" "$@"
}

assert_repair_calls() {
  [ "$(wc -l < "$CALLS" | tr -d ' ')" -eq 5 ]
  for name in frontend-browser-http.log argocd-browser-https.log keycloak-browser-http.log \
    keycloak-browser-http-launchctl.log argocd-browser-https-launchctl.log; do
    run grep -F -x -- "--interactive-sudo --soft -- /usr/sbin/chown -h cliang -- $LOGS/$name" "$CALLS"
    [ "$status" -eq 0 ]
    [ "$(printf '%s\n' "$output" | wc -l | tr -d ' ')" -eq 1 ]
  done
  while IFS= read -r line; do
    [[ "$line" == "--interactive-sudo --soft -- /usr/sbin/chown -h cliang -- "* ]]
  done < "$CALLS"
}

@test "GNU stat repairs root-owned browser logs once and ignores other files" {
  setup_owner_fixture
  run_relay_fixture
  [ "$status" -eq 0 ]
  assert_repair_calls
  run grep -F -- '-f' "$STAT_CALLS"
  [ "$status" -ne 0 ]
}

@test "BSD stat fallback repairs root-owned browser logs once" {
  setup_owner_fixture
  export STAT_STYLE=bsd
  run_relay_fixture
  [ "$status" -eq 0 ]
  assert_repair_calls
  run grep -F -x -- '-f' "$STAT_CALLS"
  [ "$status" -eq 0 ]
}

@test "failed chown exits non-zero and names the log" {
  setup_owner_fixture
  export FAIL_CHOWN=1
  run_relay_fixture
  [ "$status" -ne 0 ]
  [[ "$output" == *"Unable to change browser log owner: $LOGS/argocd-browser-https-launchctl.log"* ]]
  [ "$(wc -l < "$CALLS" | tr -d ' ')" -eq 1 ]
}

@test "dry-run makes no chown call, while install does" {
  [ -x /usr/bin/plutil ] || skip "plutil is macOS-only; the relay installer lints with it"
  setup_owner_fixture
  run_relay_fixture
  [ "$status" -eq 0 ]
  assert_repair_calls
  : > "$CALLS"
  run_relay_fixture --dry-run
  [ "$status" -eq 0 ]
  [ ! -s "$CALLS" ]
}

@test "uninstall makes no chown call, while install does" {
  setup_owner_fixture
  run_relay_fixture
  [ "$status" -eq 0 ]
  assert_repair_calls
  : > "$CALLS"
  run_relay_fixture --uninstall
  [ "$status" -eq 0 ]
  [ ! -s "$CALLS" ]
}

@test "root without SUDO_USER refuses and root with SUDO_USER repairs for that user" {
  setup_owner_fixture
  export FAKE_UID=0
  unset SUDO_USER
  run_relay_fixture
  [ "$status" -ne 0 ]
  [[ "$output" == *"SUDO_USER is unset"* ]]
  [ ! -s "$CALLS" ]
  export SUDO_USER=operator
  run_relay_fixture
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$CALLS" | tr -d ' ')" -eq 5 ]
  while IFS= read -r line; do
    [[ "$line" == "--interactive-sudo --soft -- /usr/sbin/chown -h operator -- $LOGS/"* ]]
  done < "$CALLS"
}

@test "dry-run prints five linted plists without writing outside scratch" {
  [ -x /usr/bin/plutil ] || skip "plutil is macOS-only; the relay installer lints with it"
  run "$SCRIPT" --dry-run
  [ "$status" -eq 0 ]
  [ "$(grep -c '<plist version=' <<< "$output")" -eq 5 ]
  [[ "$output" == *"<string>127.0.0.1</string>"* ]]
  [[ ! -e "$K3DM_LAUNCHD_DIR/com.k3d-manager.relay.argocd-https.plist" ]]
}

@test "relay output has exact socket settings and no unsafe executable paths" {
  [ -x /usr/bin/plutil ] || skip "plutil is macOS-only; the relay installer lints with it"
  run "$SCRIPT" --dry-run
  [ "$status" -eq 0 ]
  # The five complete XML documents are extracted and inspected with Python's plist parser.
  python3 - "$SCRIPT" "$BATS_TEST_TMPDIR/plists" <<'PY'
import pathlib, plistlib, subprocess, sys, tempfile
script, outdir = sys.argv[1:]
pathlib.Path(outdir).mkdir()
text = subprocess.check_output([script, "--dry-run"], text=True)
documents = text.split("<?xml version=\"1.0\" encoding=\"UTF-8\"?>")[1:]
assert len(documents) == 5, len(documents)
expected = [
    ("com.k3d-manager.relay.argocd-https", "127.0.0.1", "443", "18443"),
    ("com.k3d-manager.relay.keycloak-http", "127.0.0.1", "80", "18080"),
    ("com.k3d-manager.relay.hostinger-frontend-http", "127.0.0.2", "80", "18082"),
    ("com.k3d-manager.relay.sandbox-frontend-http", "127.0.0.3", "80", "18083"),
]
for i, (label, ip, service, high) in enumerate(expected):
    data = ("<?xml version=\"1.0\" encoding=\"UTF-8\"?>" + documents[i]).encode()
    path = pathlib.Path(outdir) / f"{i}.plist"
    path.write_bytes(data)
    subprocess.run(["/usr/bin/plutil", "-lint", str(path)], check=True, capture_output=True)
    p = plistlib.loads(data)
    assert p["Label"] == label
    assert p["Sockets"]["Listeners"] == {"SockNodeName": ip, "SockServiceName": service, "SockType": "stream", "SockFamily": "IPv4"}
    assert p["inetdCompatibility"] == {"Wait": False}
    assert p["UserName"] == "nobody"
    assert p["ProgramArguments"] == ["/usr/bin/nc", ip, high]
    values = [p["Label"], p["UserName"], *p["ProgramArguments"]]
    values += [p["Sockets"]["Listeners"]["SockNodeName"], p["Sockets"]["Listeners"]["SockServiceName"]]
    assert all(not any(x in value for x in ("/Users/", "/opt/homebrew", "/usr/local", "/tmp/")) for value in values)
alias = plistlib.loads(("<?xml version=\"1.0\" encoding=\"UTF-8\"?>" + documents[4]).encode())
path = pathlib.Path(outdir) / "4.plist"
path.write_bytes(("<?xml version=\"1.0\" encoding=\"UTF-8\"?>" + documents[4]).encode())
subprocess.run(["/usr/bin/plutil", "-lint", str(path)], check=True, capture_output=True)
assert alias["ProgramArguments"] == ["/bin/sh", "-c", "/sbin/ifconfig lo0 alias 127.0.0.2 up; /sbin/ifconfig lo0 alias 127.0.0.3 up; /bin/launchctl bootout system/com.k3d-manager.relay.hostinger-frontend-http; /bin/launchctl bootstrap system /Library/LaunchDaemons/com.k3d-manager.relay.hostinger-frontend-http.plist; /bin/launchctl bootout system/com.k3d-manager.relay.sandbox-frontend-http; /bin/launchctl bootstrap system /Library/LaunchDaemons/com.k3d-manager.relay.sandbox-frontend-http.plist; exit 0"]
assert alias.get("RunAtLoad") is True
assert "KeepAlive" not in alias, "a one-shot alias job must not be KeepAlive (respawn loop restarts the relays)"
assert all("127.0.0." in arg or arg in ("/bin/sh", "-c") or arg.startswith("/sbin/ifconfig") or arg.startswith("/bin/launchctl") for arg in alias["ProgramArguments"])
PY
}

@test "install and uninstall route privileged commands through _run_command" {
  local stub_log="${BATS_TEST_TMPDIR}/run.log"
  : > "$stub_log"
  [[ "$stub_log" == "${BATS_TEST_TMPDIR}"/* ]]
  run env RUN_LOG="$stub_log" bash -c '_run_command() { printf "%s\n" "$*" >> "$RUN_LOG"; }; export -f _run_command; exec "$1"' _ "$SCRIPT"
  # The positive control invokes the same stub on install mode.
  [ "$status" -eq 0 ]
  [ "$(grep -c 'launchctl bootstrap system' "$stub_log")" -eq 5 ]
  [ "$(grep -c 'install -o root -g wheel -m 0644' "$stub_log")" -eq 5 ]
  [ "$(grep -c 'launchctl bootout system' "$stub_log")" -eq 11 ]
  while IFS= read -r line; do [[ "$line" == --interactive-sudo* ]]; done < "$stub_log"
  : > "$stub_log"
  run env RUN_LOG="$stub_log" bash -c '_run_command() { printf "%s\n" "$*" >> "$RUN_LOG"; }; export -f _run_command; exec "$1" --uninstall' _ "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(grep -c 'launchctl bootout system' "$stub_log")" -eq 5 ]
  [ "$(grep -c '/bin/rm -f' "$stub_log")" -eq 5 ]
  while IFS= read -r line; do [[ "$line" == --interactive-sudo* ]]; done < "$stub_log"
}

@test "script contains no bare sudo and test override is non-root only" {
  [[ -x "$SCRIPT" ]]
  run grep -En '(^|[;&|[:space:]])sudo[[:space:]]' "$SCRIPT"
  [ "$status" -ne 0 ]
  run grep -F 'if [[ "$EUID" -ne 0 && -n "${K3DM_LAUNCHD_DIR:-}" ]]; then' "$SCRIPT"
  [ "$status" -eq 0 ]
}
