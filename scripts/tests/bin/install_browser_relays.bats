#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
  SCRIPT="${REPO_ROOT}/bin/install-browser-relays.sh"
  export K3DM_LAUNCHD_DIR="${BATS_TEST_TMPDIR}/LaunchDaemons"
  mkdir -p "$K3DM_LAUNCHD_DIR"
  [[ "$K3DM_LAUNCHD_DIR" == "${BATS_TEST_TMPDIR}"/* ]]
}

@test "dry-run prints five linted plists without writing outside scratch" {
  run "$SCRIPT" --dry-run
  [ "$status" -eq 0 ]
  [ "$(grep -c '<plist version=' <<< "$output")" -eq 5 ]
  [[ "$output" == *"<string>127.0.0.1</string>"* ]]
  [[ ! -e /Library/LaunchDaemons/com.k3d-manager.relay.argocd-https.plist ]]
}

@test "relay output has exact socket settings and no unsafe executable paths" {
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
