#!/usr/bin/env bats

setup() {
    bats_require_minimum_version 1.5.0
    repo="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
    export HOME="$BATS_TEST_TMPDIR/home"
    mkdir "$HOME"
    [[ -d $HOME && $HOME == "$BATS_TEST_TMPDIR/home" ]]
}

@test "promote-authority Makefile targets and not-installed line" {
    for action in install enrol status; do
        grep -q "^promote-authority-$action:" "$repo/Makefile"
    done
    grep -q '^promote-authority-install|operator-run:' "$repo/scripts/etc/machine/not-installed.list"
}

scratch() {
    export tree="$BATS_TEST_TMPDIR/repo" fake="$BATS_TEST_TMPDIR/root" ops="$BATS_TEST_TMPDIR/ops"
    mkdir -p "$tree/bin" "$tree/scripts/lib" "$fake/Library/LaunchDaemons"
    [[ $tree == "$BATS_TEST_TMPDIR/repo" && -d $fake ]]
    cp "$repo/bin/k3dm-promote-authority" "$tree/bin/"
    cp -R "$repo/scripts/libexec" "$repo/scripts/etc" "$tree/scripts/"
    cp "$repo"/scripts/lib/{hub_approval,promote_mover}.py "$tree/scripts/lib/"
    cat > "$tree/scripts/lib/system.sh" <<'STUB'
_run_command() {
    local opt="$1" prog arg dest src
    while [[ $1 != -- ]]; do shift; done
    shift
    prog=$1
    shift
    printf '%s %s\n' "$prog" "$*" >> "$ops"
    if [[ $opt != --interactive-sudo ]]; then
        case "$prog" in
            */git)
                case "$3" in
                    rev-parse)
                        if [[ "$4" == --verify ]]; then echo base; else git hash-object "$tree/${4#*:}"; fi ;;
                    cat-file)
                        for src in "${sources[@]}"; do
                            if [[ $(git hash-object "$tree/$src") == "$5" ]]; then cat "$tree/$src"; return; fi
                        done
                        return 1 ;;
                    *) return 99 ;;
                esac ;;
            */python3) python3 "$@" ;;
            */launchctl) return 1 ;;
            *) return 99 ;;
        esac
        return
    fi
    echo "$prog $BASH_SUBSHELL" >> "$ops.priv"
    local args=()
    for arg in "$@"; do
        case "$arg" in
            /var/db/*|/etc/k3dm-promote*|/usr/local/libexec*|/Library/LaunchDaemons/*) args+=("$fake$arg") ;;
            *) args+=("$arg") ;;
        esac
    done
    set -- "${args[@]}"
    case "$prog" in
        */true)
            if [[ -n ${probe_input:-} ]]; then [[ -z $(cat) ]]; fi ;;
        */ls) echo 'drwxr-xr-x  6 root  wheel  192 Nov 15 13:14 /usr/local' ;;
        */stat)
            # stat -f "%u %g %Lp %HT" on /usr/local and CLT python3, m4-air, 2026-11-20.
            dest=$3
            if [[ $dest == "$fake"* ]]; then
                python3 -c 'import os,sys; print("0 0 %o Directory" % (os.stat(sys.argv[1]).st_mode & 511))' "$dest"
            elif [[ $dest == */bin/python3 ]]; then echo '0 0 755 Symbolic Link'
            else echo '0 0 755 Directory'; fi ;;
        */readlink)
            if [[ $1 == */usr/bin/python3 ]]; then echo ../../Library/Frameworks/Python3.framework/Versions/3.9/bin/python3
            else echo python3.9; fi ;;
        */sh) "$prog" "$@" ;;
        */mkdir|*/rm) [[ ${!#} == "$fake/"* ]] && "$prog" "$@" ;;
        */install)
            dest=${!#}
            [[ $dest == "$fake/"* ]] || return 99
            if [[ $1 == -d ]]; then mkdir -p "$dest"; chmod "$3" "$dest"; else cp "$7" "$dest"; chmod "$2" "$dest"; fi ;;
        */ditto)
            if [[ $1 == --noacl && $2 == --noextattr ]]; then shift 2; fi
            cp -R "$1/." "$2/"
            case "${damage:-none}" in
                acl)
                    touch "$2/acl-injected"
                    if [[ $(uname -s) == Darwin ]]; then
                        /bin/chmod +a "everyone allow read" "$2/hub_approval.py"
                        /bin/ls -lde "$2/hub_approval.py" | grep -q 'everyone allow read'
                    fi ;;
                blob) echo '#' >> "$2/hub_approval.py" ;;
                render) echo '#' >> "$2/rendered/promote.conf" ;;
            esac ;;
        */chmod)
            if [[ $1 == -RN ]]; then
                for dest in "${@:2}"; do
                    [[ $dest == "$fake/"* ]] || return 99
                    if [[ $(uname -s) == Darwin ]]; then /bin/chmod -RN "$dest"; fi
                    if [[ -d $dest ]]; then rm -f "$dest/acl-injected"; fi
                done
            fi ;;
        */chown|*/launchctl) return 0 ;;
        */env)
            dest=${!#}
            [[ ! -e ${dest%/*}/acl-injected ]] || return 99
            if [[ $(uname -s) == Darwin && $(/bin/ls -lde "$dest") == *$'\n'* ]]; then return 99; fi
            git hash-object --no-filters "$dest" ;;
        */python3)
            if [[ ${!#} == mark-ruleset ]]; then
                [[ $(cat) == evidence ]]
            else python3 "$@"; fi ;;
        *) return 99 ;;
    esac
}
STUB
}

@test "install refuses a staged blob mismatch" {
    scratch
    run env damage=blob "$tree/bin/k3dm-promote-authority" install OPERATOR_IDS=cli INSTALL_REF=HEAD
    [[ $status != 0 && $output == *'Staged blob mismatch'* ]]
    run ! grep -q 'launchctl bootstrap' "$ops"
    run "$tree/bin/k3dm-promote-authority" install OPERATOR_IDS=cli INSTALL_REF=HEAD
    [[ $status == 0 ]]
    grep -q 'launchctl bootstrap' "$ops"
    [[ -f "$fake/etc/k3dm-promote/promote.conf" ]]
    run ! compgen -G "$fake/var/db/k3dm-promote/staging.*"
}

@test "render mismatch refuses activation and uninstall keeps state" {
    scratch
    run env damage=render "$tree/bin/k3dm-promote-authority" install OPERATOR_IDS=cli INSTALL_REF=HEAD
    [[ $status != 0 ]]
    run ! grep -q 'launchctl bootstrap' "$ops"
    "$tree/bin/k3dm-promote-authority" install OPERATOR_IDS=cli INSTALL_REF=HEAD
    "$tree/bin/k3dm-promote-authority" uninstall
    [[ -d "$fake/var/db/k3dm-promote/state" && ! -d "$fake/usr/local/libexec/k3dm-promote" ]]
}

@test "source scan: sudo and root-side executables" {
    scratch
    "$tree/bin/k3dm-promote-authority" print-plan > "$BATS_TEST_TMPDIR/plan"
    [[ ! -e "$ops" ]]
    grep -q '/usr/bin/ditto' "$BATS_TEST_TMPDIR/plan"
    run ! grep -En '(^|[;&|[:space:]])sudo[[:space:]]' "$tree/bin/k3dm-promote-authority" "$tree/scripts/libexec/k3dm-promote-daemon.py"
    grep -Fq '_run_command --interactive-sudo' "$tree/bin/k3dm-promote-authority"
    grep -Fq '/usr/sbin/chown' "$BATS_TEST_TMPDIR/plan"
    python3 - "$tree/scripts/libexec/k3dm-promote-daemon.py" "$tree/scripts/etc/launchd-daemons/com.k3d-manager.promote-authority.plist.tmpl" <<'PYSCAN'
import ast
import pathlib
import plistlib
import runpy
import sys

allowed = {"/usr/bin", "/bin", "/usr/sbin", "/Library/Developer/CommandLineTools/usr/bin", "/usr/local/libexec/k3dm-promote"}
def check(path):
    assert str(pathlib.PurePosixPath(path).parent) in allowed, path

with open(sys.argv[2], "rb") as stream:
    program = plistlib.load(stream)["ProgramArguments"]
check(program[0])
assert program[1:] == ["-IS", "/usr/local/libexec/k3dm-promote/k3dm-promote-daemon.py", "serve"]
tools = runpy.run_path(sys.argv[1])
assert tools["GIT"] == "/Library/Developer/CommandLineTools/usr/bin/git"
assert tools["PY"] == program[0] == "/Library/Developer/CommandLineTools/usr/bin/python3"
tree = ast.parse(pathlib.Path(sys.argv[1]).read_text())
for node in ast.walk(tree):
    if isinstance(node, ast.Call) and ast.unparse(node.func) in {"subprocess.run", "subprocess.Popen", "subprocess.call", "subprocess.check_output", "command"}:
        argv = node.args[0]
        if isinstance(argv, (ast.List, ast.Tuple)):
            exe = argv.elts[0]
            if isinstance(exe, ast.Constant):
                check(exe.value)
            else:
                assert ast.unparse(exe) in {"git", "tools['ssh_keygen']", "tools['ssh_keyscan']", "tools.get('git', GIT)"}
        else:
            assert isinstance(argv, ast.Name) and argv.id == "argv"
PYSCAN
    awk '$1 !~ /^\/(bin|usr\/bin|usr\/sbin|Library\/Developer\/CommandLineTools\/usr\/bin)\// {exit 1}
         $1=="/usr/bin/env" && $0 !~ /CommandLineTools\/usr\/bin\/git hash-object/ {exit 1}' "$BATS_TEST_TMPDIR/plan"
}

@test "install refuses a pre-existing unsafe state directory" {
    scratch
    mkdir -p "$fake/var/db/k3dm-promote"
    chmod 777 "$fake/var/db/k3dm-promote"
    run "$tree/bin/k3dm-promote-authority" install OPERATOR_IDS=cli INSTALL_REF=HEAD
    [[ $status != 0 && $output == *'Writable:'* ]]
    run ! grep -q 'launchctl bootstrap' "$ops"
    chmod 700 "$fake/var/db/k3dm-promote"
    "$tree/bin/k3dm-promote-authority" install OPERATOR_IDS=cli INSTALL_REF=HEAD
    grep -q 'launchctl bootstrap' "$ops"
}

@test "enrol requires the physical console before elevation" {
    scratch
    run env TMUX=fixture "$tree/bin/k3dm-promote-authority" enrol
    [[ $status != 0 && ! -e "$ops" ]]
    run env STY=fixture "$tree/bin/k3dm-promote-authority" enrol
    [[ $status != 0 && ! -e "$ops" ]]
    run "$tree/bin/k3dm-promote-authority" enrol </dev/null
    [[ $status != 0 && ! -e "$ops" ]]
    python3 - "$tree/bin/k3dm-promote-authority" "$ops" <<'PYTEST'
import os, pty, subprocess, sys
master, slave = pty.openpty()
try:
    assert os.isatty(slave)
    result = subprocess.run([sys.argv[1], "enrol"], stdin=slave, capture_output=True, env={k:v for k,v in os.environ.items() if k not in ("TMUX","STY")})
    # The recorder reaches the fake root and refuses the absent installed daemon.
    assert result.returncode and " enrol" in open(sys.argv[2]).read()
finally:
    os.close(slave)
    os.close(master)
PYTEST
}

@test "fresh installation bootstraps and serves unconfigured status" {
    scratch
    "$tree/bin/k3dm-promote-authority" install OPERATOR_IDS=cli INSTALL_REF=HEAD
    python3 - "$fake" <<'PYCHECK'
import importlib.util
import json
import os
from pathlib import Path
import socket
import sys

root = Path(sys.argv[1])
assert root.name == "root" and (root / "var/db/k3dm-promote/state").is_dir()
path = root / "usr/local/libexec/k3dm-promote/k3dm-promote-daemon.py"
spec = importlib.util.spec_from_file_location("installed", path)
daemon = importlib.util.module_from_spec(spec)
spec.loader.exec_module(daemon)
for name in (daemon.PY, daemon.FRAME, daemon.FRAME + ".9"):
    target = daemon.under(root, name)
    target.parent.mkdir(parents=True, exist_ok=True)
    if name in daemon.LINKS:
        target.symlink_to(daemon.LINKS[name])
    else:
        target.touch()
daemon.bootstrap(root, os.getuid(), daemon.CHAIN)
assert Path(daemon.hub_approval.__file__).parent == path.parent
conf = daemon.load_config(daemon.under(root, daemon.CONF))
left, right = socket.socketpair()
class Finished(Exception):
    pass

class Listener:
    def __enter__(self):
        return self
    def __exit__(self, *exc):
        pass
    def bind(self, address):
        assert Path(address).parent == root / "run"
        Path(address).touch()
    def listen(self, count):
        assert count == 8
    def accept(self):
        if left.fileno() < 0:
            raise Finished
        return left, None

fs = daemon.RealFs()
fs.root, fs.rundir, fs.chown = root, root / "run", lambda *_: None
fs.owner_uid, fs.owner_gid = os.getuid(), os.getgid()
with left, right:
    right.sendall(b'{"v":1,"op":"status"}\n')
    try:
        daemon.serve(conf, daemon.hub_approval.Engine, listener=Listener(), fs=fs, peer_uid=lambda _:conf["operator_uid"])
    except Finished:
        pass
    assert json.loads(right.recv(4096))["data"] == dict(daemon="ok", configured=False, pending=0, state="ok", ruleset="not asserted", audit=[])
PYCHECK
}

@test "install strips staged and installed ACLs" {
    scratch
    run env damage=acl "$tree/bin/k3dm-promote-authority" install OPERATOR_IDS=cli INSTALL_REF=HEAD
    [[ $status == 0 ]]
    grep -q '^/usr/bin/ditto --noacl --noextattr ' "$ops"
    grep -q '^/bin/chmod -RN /var/db/k3dm-promote/staging' "$ops"
    grep -q '^/bin/chmod -RN .*hub_approval.py .*promote_mover.py .*promote.conf .*plist$' "$ops"
    grep -q 'launchctl bootstrap' "$ops"
}

@test "install and ruleset verification prime sudo before capture or redirection" {
    scratch
    "$tree/bin/k3dm-promote-authority" install OPERATOR_IDS=cli INSTALL_REF=HEAD
    [[ $(head -1 "$ops.priv") == '/usr/bin/true 0' ]]
    : > "$ops.priv"
    echo evidence > "$tree/probe"
    export probe_input="$tree/probe"
    run "$tree/bin/k3dm-promote-authority" ruleset-verified "PROBE_FILE=$tree/probe" </dev/null
    [[ $(head -1 "$ops.priv") == '/usr/bin/true 0' ]]
    [[ $status == 0 ]]
    grep -q 'mark-ruleset' "$ops"
}
