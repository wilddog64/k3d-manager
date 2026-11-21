#!/usr/bin/env bats
# Bats sources the system library at runtime. Its hooks call the shims and
# consume the dynamically scoped process arrays defined by these tests.
# shellcheck disable=SC1090,SC1091,SC2329,SC2030,SC2031

setup() {
  REPO="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
  SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/wc-test.XXXXXX")"
  [ -d "$SCRATCH" ]
  export HOME="$SCRATCH"
}

teardown() {
  rm -rf -- "$SCRATCH"
}

@test "[M1] [N1] [N2] [N3] [N4] configuration template has exactly the prescribed lines" {
  local target="$REPO/scripts/etc/ssh/k3dm-web-console_sshd_config.tmpl"
  [ -f "$target" ]
  cat > "$SCRATCH/expected" <<'EOF'
ListenAddress 127.0.0.1:{{CONSOLE_PORT}}
AddressFamily inet
HostKey /etc/k3dm-web-console/ssh_host_ed25519_key
PidFile none
UsePAM no
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitEmptyPasswords no
HostbasedAuthentication no
GSSAPIAuthentication no
PermitRootLogin no
PubkeyAuthentication yes
AuthenticationMethods publickey
TrustedUserCAKeys /etc/k3dm-web-console/access_ca.pub
AuthorizedKeysFile none
AllowUsers {{CONSOLE_USER}}
DisableForwarding yes
AllowTcpForwarding no
AllowAgentForwarding no
AllowStreamLocalForwarding no
GatewayPorts no
PermitTunnel no
X11Forwarding no
PermitUserRC no
PermitUserEnvironment no
PermitListen none
PermitOpen none
PermitTTY yes
ForceCommand /Library/PrivilegedHelperTools/k3dm-web-console/forced-command
SetEnv ZDOTDIR=/etc/k3dm-web-console/zdotdir
MaxAuthTries 3
MaxSessions 1
MaxStartups 3:50:10
LoginGraceTime 30
LogLevel VERBOSE
ClientAliveInterval 300
ClientAliveCountMax 3
StrictModes yes
UseDNS no
EOF
  cmp "$SCRATCH/expected" "$target"
}

@test "[N9] forced command refuses without a terminal, including arguments" {
  local target="$REPO/scripts/libexec/k3dm-console-forced-command"
  [ -f "$target" ]
  run /bin/sh "$target"
  [ "$status" -eq 1 ]
  [ "$output" = 'console gate not installed' ]
  run /bin/sh "$target" example
  [ "$status" -eq 1 ]
  [ "$output" = 'console gate not installed' ]
  printf '#!/bin/sh\nexit 0\n' > "$SCRATCH/control"
  run /bin/sh "$SCRATCH/control"
  [ "$status" -eq 0 ]
}

@test "[M7] console is classified as operator installed" {
  local dir="$REPO/scripts/etc/machine"
  grep -q '^install-web-console-sshd|.\+' "$dir/not-installed.list"
  grep -q '^web-console-sshd|.\+' "$dir/not-installed.list"
}

@test "[N10] console is absent from automatic installation lists" {
  local dir="$REPO/scripts/etc/machine" file
  for file in "$dir"/agents.*.list "$dir"/secrets.*.list "$dir"/hub-local.list "$dir"/hub-singletons.list; do
    [ -f "$file" ] || continue
    run grep -q 'web-console' "$file"
    [ "$status" -eq 1 ]
  done
}

@test "[M9] operator instructions describe the accepted risks" {
  local doc="$REPO/docs/howto/web-console-sshd.md" risk
  [ -f "$doc" ]
  for risk in R-INSTALL R-SUDO R-CONFIG R-REPARENT R-PORT-GAP R-REVOKE-CODE; do
    grep -q "$risk" "$doc"
  done
  grep -q 'AFTER_REVOKE=1' "$doc"
  grep -q 'PURGE=1' "$doc"
  run grep -q 'Remote Login stays off' "$REPO/docs/roadmap.md"
  [ "$status" -eq 1 ]
}

wc_library() {
  source "$REPO/scripts/lib/web_console_common.sh"
}

@test "[M3] [N5] [N7] real privilege wrapper returns the failure without echoing argv" {
  source "$REPO/scripts/lib/system.sh"
  wc_library
  sudo() { printf '%s\n' "$@" >> "$SCRATCH/calls"; return 37; }
  run _wc_priv /usr/bin/true fixture-sentinel
  [ "$status" = 37 ]
  [ -z "$output" ]
  grep -Fxq fixture-sentinel "$SCRATCH/calls"
  local before; before="$(cat "$SCRATCH/calls")"
  run _wc_priv_open </dev/null
  [ "$status" = 10 ]
  [[ "$output" = *"an interactive terminal is required"* ]]
  [ "$(cat "$SCRATCH/calls")" = "$before" ]
}

@test "[M3] [N7] production main resets command lookup before privilege use" {
  source "$REPO/bin/k3dm-web-console-sshd"
  sudo() { return 91; }
  [ "$(type -t sudo)" = function ]
  PATH="$SCRATCH"
  _wc_main_env
  [ "$PATH" = /usr/bin:/bin:/usr/sbin:/sbin ]
  [ "$(type -t sudo)" = file ]
}

@test "[N12] missing fixture marker refuses before consulting shims" {
  mkdir "$SCRATCH/bin"
  printf '#!/bin/sh\ntouch "%s/used"\n' "$SCRATCH" > "$SCRATCH/bin/uname"
  chmod +x "$SCRATCH/bin/uname"
  run env K3DM_WC_ROOT="$SCRATCH" "$REPO/bin/k3dm-web-console-sshd" install
  [ "$status" = 2 ]
  [ ! -e "$SCRATCH/used" ]
  [ ! -e "$SCRATCH/calls.log" ]
}

# The scratch zsh, rather than the generating Bash process, expands its variables.
# shellcheck disable=SC2016
@test "[M8] [N12] trusted zsh entry reads only ZDOTDIR" {
  [ "$(uname -s)" = Darwin ] || skip "zsh trusted-entry test is Darwin-only"
  [ -x /bin/zsh ]
  [ "$HOME" = "$SCRATCH" ]
  local file target="$REPO/scripts/libexec/k3dm-console-forced-command"
  [ -x "$target" ]
  for file in .zshenv .zprofile .zshrc .zlogin; do
    printf ': > "$HOME/seen%s"\n' "$file" > "$HOME/$file"
  done
  run env -i HOME="$HOME" ZDOTDIR=/var/empty PATH=/usr/bin:/bin /bin/zsh -c 'exec "$1"' entry "$target"
  [ "$status" = 1 ]
  [ "$output" = 'console gate not installed' ]
  for file in .zshenv .zprofile .zshrc .zlogin; do [ ! -e "$HOME/seen$file" ]; done
  run env -i HOME="$HOME" PATH=/usr/bin:/bin /bin/zsh -c 'exec "$1"' entry "$target"
  [ "$status" = 1 ]
  [ -f "$HOME/seen.zshenv" ]
  rm "$HOME/seen.zshenv"
  mkdir "$SCRATCH/zdot"
  printf ': > "$HOME/seen-zdot"\n' > "$SCRATCH/zdot/.zshenv"
  run env -i HOME="$HOME" ZDOTDIR="$SCRATCH/zdot" PATH=/usr/bin:/bin /bin/zsh -c 'exec "$1"' entry "$target"
  [ "$status" = 1 ]
  [ -f "$HOME/seen-zdot" ]
  [ ! -e "$HOME/seen.zshenv" ]
}

@test "[M1] [N1] [N2] [N4] OpenSSH reads the canonical configuration and enforces host-key validation" {
  [ "$(uname -s)" = Darwin ] || skip "sshd not found"
  [ -x /usr/sbin/sshd ]
  local tmpl="$REPO/scripts/etc/ssh/k3dm-web-console_sshd_config.tmpl"
  [ -r "$tmpl" ]
  sed -e 's/{{CONSOLE_PORT}}/42722/g' -e 's/{{CONSOLE_USER}}/someone/g' "$tmpl" > "$SCRATCH/config"
  run /usr/sbin/sshd -G -f "$SCRATCH/config"
  [ "$status" = 0 ]
  [ "$(grep '^listenaddress ' <<< "$output")" = 'listenaddress 127.0.0.1:42722' ]
  [ "$(grep '^setenv ' <<< "$output")" = 'setenv ZDOTDIR=/etc/k3dm-web-console/zdotdir' ]
  run /usr/sbin/sshd -t -f "$SCRATCH/config"
  [ "$status" -ne 0 ]
  [[ "$output" = *'no hostkeys available'* ]]
  run /usr/sbin/sshd -t -f "$SCRATCH/config" -h "$SCRATCH/missing"
  [ "$status" -ne 0 ]
  /usr/bin/ssh-keygen -q -t ed25519 -C fixture -N '' -f "$SCRATCH/host"
  run /usr/sbin/sshd -t -f "$SCRATCH/config" -h "$SCRATCH/host"
  [ "$status" = 0 ]
}

@test "[M2] [N6] launchd executes only sshd with the installed configuration" {
  local plist="$REPO/scripts/etc/launchd/com.k3d-manager.web-console-sshd.plist.tmpl"
  python3 - "$plist" <<'PY'
import plistlib, sys
with open(sys.argv[1], 'rb') as stream:
    actual = plistlib.load(stream)
log = '/var/log/k3dm-web-console-sshd.log'
assert actual == dict(Label='com.k3d-manager.web-console-sshd',
    ProgramArguments=['/usr/sbin/sshd','-D','-e','-f','/etc/k3dm-web-console/sshd_config'],
    RunAtLoad=True, KeepAlive=True, ThrottleInterval=10, AbandonProcessGroup=False,
    Umask=63, StandardErrorPath=log, StandardOutPath=log)
PY
}

@test "[M6] [N8] port validation rejects reserved, out-of-range, empty and nondecimal ports" {
  source "$REPO/bin/k3dm-web-console-sshd"
  wc_library
  local port reason
  while IFS='|' read -r port reason; do
    run _wc_port_valid "$port"
    [ "$status" = 2 ]
    [ "$output" = "web-console-sshd: refusing port $port: $reason" ]
  done <<'CASES'
|empty value
abc|not a decimal port
22|outside 1024-49151
80|outside 1024-49151
0|outside 1024-49151
1023|outside 1024-49151
49152|outside 1024-49151
65535|outside 1024-49151
2222|reserved SSH alternate
2200|reserved SSH alternate
2299|reserved SSH alternate
2022|reserved SSH alternate
8022|reserved SSH alternate
10222|reserved SSH alternate
22222|reserved SSH alternate
32222|reserved SSH alternate
CASES
  _wc_port_valid 42722
}

@test "[M10] [N3] CA validation prints only the parsed fingerprint of a single allowed key" {
  source "$REPO/bin/k3dm-web-console-sshd"
  wc_library
  [ "$HOME" = "$SCRATCH" ]
  ssh-keygen -q -t ed25519 -N '' -C private-comment -f "$SCRATCH/test-key"
  run _wc_ca_read < "$SCRATCH/test-key.pub"
  [ "$status" = 0 ]
  [[ "$output" =~ ^256\ SHA256:[[:alnum:]+/=]+\ \(ED25519\)$ ]]
  cat "$SCRATCH/test-key.pub" "$SCRATCH/test-key.pub" > "$SCRATCH/two"
  run _wc_ca_read < "$SCRATCH/two"
  [ "$status" = 2 ]
  run _wc_ca_read <<< "restrict $(cat "$SCRATCH/test-key.pub")"
  [ "$status" = 2 ]
  run _wc_ca_read <<< '# no key'
  [ "$status" = 2 ]
}

@test "[N4] exact-line rendering rejects noncanonical sshd directives" {
  source "$REPO/bin/k3dm-web-console-sshd"
  local template good change old new
  IFS= read -r -d '' template < "$REPO/scripts/etc/ssh/k3dm-web-console_sshd_config.tmpl" || [ -n "$template" ]
  local suffix=$'\n'
  good=$(_wc_render "$template" 42722 someone)
  [[ "$good" = *'AllowUsers someone'* ]]
  for change in 'ListenAddress 127.0.0.1:{{CONSOLE_PORT}}' 'SetEnv ZDOTDIR=/etc/k3dm-web-console/zdotdir'; do
    run _wc_render "${template/"$change$suffix"/}" 42722 someone
    [ "$status" = 4 ]
  done
  for change in 'Port 22' 'Include=/x' 'AcceptEnv LANG' 'Subsystem sftp internal-sftp' 'Subsystem=sftp internal-sftp' \
    'Match User someone' '"Match" User someone' $'Match\tUser someone' '#comment' ''; do
    run _wc_render "$template$change$suffix" 42722 someone
    [ "$status" = 4 ]
  done
  while IFS='|' read -r old new; do
    run _wc_render "${template/"$old"/"$new"}" 42722 someone
    [ "$status" = 4 ]
  done <<'CASES'
127.0.0.1|0.0.0.0
127.0.0.1|::1
PasswordAuthentication no|PasswordAuthentication yes
KbdInteractiveAuthentication no|KbdInteractiveAuthentication yes
AuthorizedKeysFile none|AuthorizedKeysFile .ssh/authorized_keys
DisableForwarding yes|DisableForwarding no
AllowTcpForwarding no|AllowTcpForwarding yes
PermitTunnel no|PermitTunnel yes
X11Forwarding no|X11Forwarding yes
PermitUserRC no|PermitUserRC yes
PermitUserEnvironment no|PermitUserEnvironment yes
PermitListen none|PermitListen any
SetEnv ZDOTDIR=/etc/k3dm-web-console/zdotdir|SetEnv ZDOTDIR=/x FOO=bar
PidFile none|PidFile /var/run/x.pid
CASES
}

@test "[M5] [N11] [N13] absent job requires the captured not-found status and diagnostic" {
  wc_library
  local capture="$REPO/docs/captures/2026-11-19-web-console/c12-absent.txt"
  # m4-air, 2026-11-19. Substitute only the label of the capture daemon.
  [ -r "$capture" ]
  sed -n '/^Bad request\./,/^Could not find service/p' "$capture" | sed 's/capture-sshd/web-console-sshd/g' > "$SCRATCH/reply"
  _wc_tool() { cat "$SCRATCH/reply" >&2; return "$reply_rc"; }
  local reply_rc=113
  _wc_job_absent
  reply_rc=1
  run _wc_job_absent
  [ "$status" = 1 ]
  reply_rc=113
  printf 'Permission denied\n' > "$SCRATCH/reply"
  run _wc_job_absent
  [ "$status" = 1 ]
  reply_rc=0
  run _wc_job_absent
  [ "$status" = 1 ]
}

# m4-air, 2026-11-19. The job, socket and process replies come from C12
# and C17. Test mutations change the relevant field of the captured reply.
wc_fixture() {
  export K3DM_WC_ROOT="$SCRATCH/root" HOME="$SCRATCH/home"
  export WC_CAPTURE_DIR="$REPO/docs/captures/2026-11-19-web-console"
  export WC_FIXTURE_REPO="$REPO"
  local root="$K3DM_WC_ROOT" tool py
  mkdir -p "$root/bin" "$HOME" "$root/private"/{etc/ssh,var/db,var/log} "$root/Library"/{LaunchDaemons,PrivilegedHelperTools} "$root/dev"
  touch "$root/.k3dm-wc-fixture" "$root/dev/null" "$root/private/etc/ssh/sshd_config"
  [ -f "$root/.k3dm-wc-fixture" ]
  [ "$HOME" = "$SCRATCH/home" ]
  ln -s private/etc "$root/etc"; ln -s private/var "$root/var"
  py=$(python3 -c 'import sys; print(sys.executable)')
  printf '#!%s\n' "$py" > "$root/shim"
  cat >> "$root/shim" <<'PY'
import datetime, hashlib, json, os, re, shutil, signal, stat, sys, tempfile, time
from pathlib import Path
root = Path(os.environ['K3DM_WC_ROOT'])
assert (root / '.k3dm-wc-fixture').is_file()
tool = Path(sys.argv[0]).name
args = sys.argv[1:]
captures = Path(os.environ['WC_CAPTURE_DIR'])
repo = Path(os.environ['WC_FIXTURE_REPO'])
def die(rc=1):
    sys.exit(rc)
def get(name, default=''):
    f = root / name
    return f.read_text().strip() if f.exists() else default
def state(name, value):
    (root / name).write_text(value)
def fail(name):
    return (root / ('fail.' + name)).exists()
def capture(name):
    return (captures / name).read_text()
def marker():
    (root/'etc/k3dm-web-console/revoked').write_text('20261119T184301Z.456\n')
def crash_at(boundary, count):
    if get('crash-at') != f'{boundary}:{count}': return
    child=int(get('crash-child'))
    holder=(root/'var/db/k3dm-web-console.lock/holder').read_text().split()[0]
    assert child > 1 and holder == str(child)
    state('crashed',str(child))
    os.kill(child,signal.SIGKILL)
if tool in {'install','mv','rm','mkdir','touch','tee','mktemp','cp','kill'}:
    for arg in args:
        if arg.startswith('/') and not Path(arg).resolve().is_relative_to(root.resolve()):
            die(99)
if fail(tool): die(1)
if tool == 'uname': print(get('platform', 'Darwin'))
elif tool == 'id':
    if args == ['-u']:
        if get('ticket') == 'closed': die(1)
        print('0')
    else: print(get('login','someone') if args == ['-un'] else 'someone:*:501:20::0:0:Fixture:/redacted:' + get('shell','/bin/zsh'))
elif tool == 'date':
    print(time.strftime('%Y%m%dT%H%M%SZ',time.gmtime()) if '-u' in args else int(time.time()))
elif tool == 'git':
    if args[0] in ('ls-files','diff'): die(1 if fail('sources') or get('changed-source','__none__') in args else 0)
    path=args[-1].removeprefix('HEAD:')
    data=(repo/path).read_bytes()
    if args[0]=='cat-file': sys.stdout.buffer.write(data)
    else: print(hashlib.sha1(b'blob '+str(len(data)).encode()+b'\0'+data).hexdigest())
elif tool == 'stat':
    path=Path(args[-1]); st=path.lstat()
    mode=format(stat.S_IMODE(st.st_mode),'o')
    fields={'%u':get('owner.'+path.name,'0'),'%Lp':mode,'%m':str(int(st.st_mtime)), '%u:%g:%Lp':'0:0:'+mode}
    print(os.readlink(path) if args[1]=='%Y' else fields[args[1]])
elif tool == 'ls':
    p=Path(args[-1])
    if args[0]=='-lde': print(stat.filemode(p.lstat().st_mode)+('+' if fail('acl.'+p.name) else '')+' 1 root wheel')
    else: print('\n'.join(sorted(x.name for x in p.iterdir())))
elif tool == 'install':
    p=Path(args[-1]); mode=int(args[args.index('-m')+1],8)
    if '-d' in args: p.mkdir(exist_ok=True)
    else: shutil.copyfile(args[-2],p)
    p.chmod(mode)
elif tool == 'mkdir': Path(args[-1]).mkdir()
elif tool == 'mktemp':
    pat=Path(args[-1]); print(tempfile.mkdtemp(prefix='.stage.',dir=pat.parent))
elif tool == 'tee':
    data=sys.stdin.buffer.read()
    with open(args[-1],'ab' if '-a' in args else 'wb') as f: f.write(data)
    if args[-1].endswith('.txn') and b' moved ' in data: crash_at('append',int(data.split()[0]))
elif tool == 'cp': shutil.copy2(args[-2], args[-1])
elif tool == 'mv':
    src, dst = map(Path, args[-2:])
    if src.parent.name.startswith('.stage.'):
        n=int(get('renames','0'))+1; state('renames',str(n))
        if n==int(get('bad-move','0')): die(1)
    if src.name.endswith('.restore') and fail('restore'): die(1)
    if src.name=='revoked' and fail('newer-id'): marker()
    src.replace(dst)
    if src.name.endswith('.plist.restore'): crash_at('restore-plist',1)
    if dst.name.endswith('.plist') and src.parent.name.startswith('.stage.') and fail('third-revoke'):
        assert n == 3
        marker()
        dst.replace(root/'etc/k3dm-web-console/launchd.plist.revoked')
        die(1)
    if dst.name=='com.k3d-manager.web-console-sshd.plist' and src.parent.name.startswith('.stage.'):
        if fail('before-bootstrap'): marker()
        if fail('late-zdotdir'): (root/'etc/k3dm-web-console/zdotdir/file').touch()
    if src.parent.name.startswith('.stage.'): crash_at('rename',n)
elif tool == 'rm':
    for arg in args:
        if arg.startswith('-'): continue
        p=Path(arg)
        if p.name=='launchd.plist.pending' and fail('clear-parked'): die(1)
        if p.is_dir() and not p.is_symlink(): shutil.rmtree(p)
        else: p.unlink(missing_ok=True)
elif tool == 'head':
    p=Path(args[-1])
    if not p.is_file(): die(1)
    sys.stdout.buffer.write(b''.join(p.read_bytes().splitlines(True)[:int(args[1])]))
elif tool == 'sed': sys.stdout.buffer.write(sys.stdin.buffer.read())
elif tool == 'shasum':
    data=Path(args[-1]).read_bytes() if len(args)>2 else sys.stdin.buffer.read()
    digest=hashlib.sha256(data).hexdigest()
    if len(args)>2 and '.stage.' in args[-1] and fail('rehash'): digest='0'*64
    print(digest+'  -')
elif tool == 'ssh-keygen':
    if '-l' in args:
        if fail('second-fingerprint'): print('256 SHA256:second two (ED25519)')
        data=sys.stdin.read()
        if not data.startswith('ssh-ed25519 '): die(1)
        print('256 SHA256:abc123 fixture-comment (ED25519)')
    else:
        p=Path(args[-1]); p.write_bytes(b'fixture host key'); p.chmod(0o600)
        pub=Path(str(p)+'.pub'); pub.write_text('ssh-ed25519 QUFB fixture\n'); pub.chmod(0o644)
elif tool == 'sshd':
    if args==['-G']: print(get('system-config','passwordauthentication yes\nkbdinteractiveauthentication yes'))
    elif '-f' in args:
        if '-G' not in args and ('-h' not in args or not Path(args[args.index('-h')+1]).is_file()): die(1)
        if fail(args[0]): print('invalid setting for someone in '+os.environ['HOME'],file=sys.stderr); die(1)
        for line in Path(args[args.index('-f')+1]).read_text().splitlines():
            k,v=line.split(' ',1); print(k.lower(),v)
elif tool == 'launchctl':
    job=root/'job'
    if args[0]=='print':
        if fail('print'): die(5)
        if fail('idle'): print(capture('c12-lp-idle.txt')); die(0)
        if job.exists(): print(capture('c12-lp-up.txt').replace('/private/var/db/k3dm-capture-2026-11-19/prod.conf','/etc/k3dm-web-console/sshd_config'))
        else:
            txt=capture('c12-absent.txt').split('Bad request.\n')[1].split('\nrc=')[0]
            print(txt.replace('capture-sshd','web-console-sshd'),file=sys.stderr);die(113)
    elif args[0]=='bootstrap':
        if fail('bootstrap-revoke'): marker(); die(1)
        if fail('bootstrap'): die(1)
        job.touch()
        if fail('after-bootstrap'): marker()
    else: job.unlink(missing_ok=True)
elif tool == 'netstat':
    if fail('busy-after-recovery') and not (root/'var/db/k3dm-web-console.txn').exists():
        print(next(x for x in capture('c12-chain.txt').splitlines() if ' LISTEN ' in x).replace('42723','42722'))
    elif (root/'sockets').exists(): print(get('sockets'))
    elif (root/'job').exists():
        print(next(x for x in capture('c12-chain.txt').splitlines() if ' LISTEN ' in x).replace('42723','42722'))
elif tool == 'ps':
    if 'uid=' in args: print(get('listener-uid','0'))
    elif 'lstart=' in args:
        if args[-1]==get('crashed'): die(1)
        print('Thu Nov 19 18:34:54 2026')
    elif args[-1]=='command=': print(get('processes'))
    elif (root/'job').exists(): print('59966 1 0 Thu Nov 19 18:34:54 2026 sshd: /usr/sbin/sshd')
elif tool=='yq':
    # Test inputs use the same YAML structure as the repository ingress file.
    config=json.load(sys.stdin)
    rules=config.get('ingress', [])
    if 'any_c' in args[-2]:
        enabled=config.get('warp-routing',{}).get('enabled') or config.get('originRequest',{}).get('bastionMode')
        print('true' if enabled or any(r.get('originRequest',{}).get('bastionMode') for r in rules) else 'false')
    else: print('\n'.join(str(r['service']) for r in rules))
elif tool not in ('true','touch','plutil','sleep','kill'): die(2)
PY
  chmod +x "$root/shim"
  for tool in install stat ls cp mv rm mkdir touch tee mktemp launchctl sshd ssh-keygen netstat ps shasum plutil id kill sleep true git uname head date yq sed; do ln -s ../shim "$root/bin/$tool"; done
  printf 'ssh-ed25519 QUFB fixture-comment\n' > "$HOME/ca.pub"
  WC_BIN="$REPO/bin/k3dm-web-console-sshd"
  [ -x "$WC_BIN" ]
}

@test "[M2] [M4] [M10] [M11] [N3] [N5] [N6] [N7] fixture installs, checks, rotates only the CA, and reinstalls idempotently" {
  wc_fixture
  local root="$K3DM_WC_ROOT" config="$K3DM_WC_ROOT/etc/k3dm-web-console" log="$K3DM_WC_ROOT/calls.log"
  run "$WC_BIN" install --ca-file "$HOME/ca.pub"
  [ "$status" = 0 ] || { echo "$output"; return 1; }
  [ "$(wc -l < "$config/manifest" | tr -d ' ')" = 6 ]
  [ -d "$config/.prev" ]
  [ ! -e "$root/Library/LaunchDaemons/.prev" ]
  grep -q '256 SHA256:abc123 (ED25519)' <<< "$output"
  run grep -E 'someone|fixture-comment|QUFB|AllowUsers ' "$log"
  [ "$status" = 1 ]
  run grep -F "$HOME" "$log"
  [ "$status" = 1 ]
  run "$WC_BIN" check
  [ "$status" = 0 ] || { echo "$output"; return 1; }
  grep -q '^PASS C1 ' <<< "$output"
  [ "$(grep -c '^PASS' <<< "$output")" = 8 ]
  [ "$(grep -c '^WARN C8' <<< "$output")" = 1 ]
  run "$WC_BIN" check --strict
  [ "$status" = 1 ]
  [[ "$output" = *'FAIL C8'* ]]
  : > "$log"
  run "$WC_BIN" install
  [ "$status" = 0 ]
  [[ "$output" = *'already installed'* ]]
  run grep -F '/bin/mv ' "$log"
  [ "$status" = 1 ]
  printf 'ssh-ed25519 QkJC new-comment\n' > "$HOME/ca.pub"
  : > "$log"
  run "$WC_BIN" install --ca-file "$HOME/ca.pub"
  [ "$status" = 0 ]
  [ "$(grep -c 'priv /bin/mv ' "$log")" = 2 ]
  run grep -E 'someone|fixture-comment|QkJC|bootout|AllowUsers ' "$log"
  [ "$status" = 1 ]
  run grep -F "$HOME" "$log"
  [ "$status" = 1 ]
}

@test "[M5] [M12] [N13] revoke parks the daemon, changes its marker, and explicit restore consumes the matching event" {
  wc_fixture
  local dir="$K3DM_WC_ROOT/etc/k3dm-web-console" plist="$K3DM_WC_ROOT/Library/LaunchDaemons/com.k3d-manager.web-console-sshd.plist" first second
  run "$WC_BIN" install --ca-file "$HOME/ca.pub"
  [ "$status" = 0 ]
  : > "$K3DM_WC_ROOT/calls.log"
  run "$WC_BIN" revoke </dev/null
  [ "$status" = 0 ] || { echo "$output"; return 1; }
  [ ! -e "$plist" ]
  [ -f "$dir/launchd.plist.revoked" ]
  [ ! -e "$K3DM_WC_ROOT/job" ]
  read -r first < "$dir/revoked"
  awk '/priv .*mv.*revoked.tmp/ {m=NR} /priv .*mv.*launchd.plist.revoked/ {p=NR} /priv .*bootout/ {if (!b) b=NR} END{exit !(m && m<p && p<b)}' "$K3DM_WC_ROOT/calls.log"
  run "$WC_BIN" revoke </dev/null
  [ "$status" = 0 ]
  read -r second < "$dir/revoked"
  [ "$first" != "$second" ]
  : > "$K3DM_WC_ROOT/calls.log"
  run "$WC_BIN" install
  [ "$status" = 2 ]
  [[ "$output" = *'rerun with --after-revoke'* ]]
  run grep '^priv ' "$K3DM_WC_ROOT/calls.log"
  [ "$status" = 1 ]
  run "$WC_BIN" install --after-revoke
  [ "$status" = 0 ] || { echo "$output"; return 1; }
  [ -f "$dir/revoked.consumed.$second" ]
  [ ! -e "$dir/revoked" ]
  [ ! -e "$dir/launchd.plist.revoked" ]
  [ -f "$plist" ]
  run "$WC_BIN" check
  [ "$status" = 0 ]
  [[ "$output" = *'PASS C1 '* ]]
}

@test "[M2] [M8] [N6] [N12] preflight refusals and dry-run leave all privileged paths untouched" {
  wc_fixture
  local root="$K3DM_WC_ROOT" f
  run "$root/bin/mkdir" /outside-fixture
  [ "$status" = 99 ]
  run "$WC_BIN" install --dry-run --ca-file "$HOME/ca.pub"
  [ "$status" = 0 ]
  [[ "$output" = *'AllowUsers <login>'* ]]
  for f in etc/zshenv etc/zshenv.zwc etc/ssh/sshrc; do
    touch "$root/$f"
    run "$WC_BIN" install
    [ "$status" = 2 ]
    [[ "$output" = *"/$f exists"* ]]
    rm "$root/$f"
  done
  printf '/bin/bash\n' > "$root/shell"
  run "$WC_BIN" install
  [ "$status" = 2 ]
  rm "$root/shell"
  printf 'Linux\n' > "$root/platform"
  run "$WC_BIN" install
  [ "$status" = 2 ]
  rm "$root/platform"
  touch "$root/fail.sources"
  run "$WC_BIN" install
  [ "$status" = 9 ]
  rm "$root/fail.sources"
  run grep '^priv ' "$root/calls.log"
  [ "$status" = 1 ]
  chmod 0775 "$root/Library"
  run "$WC_BIN" install
  [ "$status" = 8 ]
  [[ "$output" = *'writable'* ]]
  [ ! -d "$root/var/db/k3dm-web-console.lock" ]
  [ ! -e "$root/etc/k3dm-web-console" ]
  rm "$root/bin/plutil"; : > "$root/calls.log"
  run "$WC_BIN" install
  [ "$status" = 2 ]
  [ ! -s "$root/calls.log" ]
}

@test "[M2] [N5] staged validation failure redacts stderr and rolls back a first install" {
  wc_fixture
  touch "$K3DM_WC_ROOT/fail.-t"
  run "$WC_BIN" install --ca-file "$HOME/ca.pub"
  [ "$status" = 4 ] || { echo "$output"; return 1; }
  [[ "$output" = *'<login>'* && "$output" = *'in ~'* && "$output" != *"$HOME"* && "$output" != *'someone'* ]]
  [ ! -e "$K3DM_WC_ROOT/etc/k3dm-web-console" ]
  [ ! -e "$K3DM_WC_ROOT/Library/PrivilegedHelperTools/k3dm-web-console" ]
  [ ! -e "$K3DM_WC_ROOT/var/log/k3dm-web-console-sshd.log" ]
  [ ! -e "$K3DM_WC_ROOT/var/db/k3dm-web-console.txn" ]
  run grep 'bootstrap' "$K3DM_WC_ROOT/calls.log"
  [ "$status" = 1 ]
}

@test "[M11] pending install has four rows and uninstall purges the pending generation" {
  wc_fixture
  local dir="$K3DM_WC_ROOT/etc/k3dm-web-console"
  run "$WC_BIN" install
  [ "$status" = 3 ] || { echo "$output"; return 1; }
  [ ! -e "$K3DM_WC_ROOT/Library/LaunchDaemons/com.k3d-manager.web-console-sshd.plist" ]
  [ -f "$dir/launchd.plist.pending" ]
  [ ! -e "$K3DM_WC_ROOT/job" ]
  [ "$(wc -l < "$dir/manifest" | tr -d ' ')" = 4 ]
  run "$WC_BIN" check
  [ "$status" = 1 ]
  [[ "$output" = *'FAIL C1 '* ]]
  run "$WC_BIN" uninstall --purge
  [ "$status" = 0 ]
  [ ! -d "$dir" ]
}

wc_pty_run() {
  local code output quoted
  if [[ "$(uname -s)" = Darwin ]]; then
    output=$(script -q /dev/null "$@" </dev/null) && code=0 || code=$?
  else
    printf -v quoted '%q ' "$@"
    output=$(script -qec "$quoted" /dev/null </dev/null) && code=0 || code=$?
  fi
  printf '%s' "$output" | tr -d '\010\r' | sed 's/^\^D//'
  return "$code"
}

@test "[M8] [N9] refusing stub also exits one in a verified pty" {
  run /bin/sh -c 'test -t 0 && test -t 1' </dev/null
  [ "$status" = 1 ]
  wc_pty_run /bin/sh -c 'test -t 0 && test -t 1'
  local stub="$REPO/scripts/libexec/k3dm-console-forced-command"
  [ -x "$stub" ]
  run wc_pty_run "$stub"
  [ "$status" = 1 ]
  [ "$output" = 'console gate not installed' ]
  run wc_pty_run "$stub" foo bar
  [ "$status" = 1 ]
  [ "$output" = 'console gate not installed' ]
  run grep -E '(^|[;[:space:]])(exec|sh|bash|zsh)([;[:space:]]|$)' "$stub"
  [ "$status" = 1 ]
}

@test "[M2] [M3] [N5] real wrapper rolls back two scratch destinations when third move fails" {
  source "$REPO/scripts/lib/system.sh"
  wc_library
  _WC_CONF_DIR="$SCRATCH/conf"; _WC_LAUNCHD_DIR="$SCRATCH/jobs"; _WC_HELPER_DIR="$SCRATCH/helpers"
  _WC_JOURNAL="$SCRATCH/journal"; _WC_SEQUENCE=0
  local stage="$SCRATCH/stage" dest
  mkdir -p "$_WC_CONF_DIR/.prev" "$_WC_HELPER_DIR/.prev" "$_WC_LAUNCHD_DIR" "$stage"
  sudo() {
    [[ "${1-}" != -n ]] || shift
    local tool="$1" arg
    shift
    for arg in "$@"; do
      case "$arg" in /*) [[ "$arg" = "$SCRATCH/"* ]] || return 99 ;; esac
    done
    printf '%s %s\n' "$tool" "$*" >> "$SCRATCH/priv-calls"
    if [[ "$tool" = /bin/mv && "$*" = *"$stage/three "* && -f "$SCRATCH/inject" ]]; then return 37; fi
    "$tool" "$@"
  }
  run _wc_priv /bin/rm -f /outside-scratch
  [ "$status" = 99 ]
  for dest in one two three; do
    printf 'original %s\n' "$dest" > "$_WC_CONF_DIR/$dest"
    printf 'replacement %s\n' "$dest" > "$stage/$dest"
  done
  touch "$SCRATCH/inject" "$_WC_JOURNAL"
  run _wc_commit "$stage" "$_WC_CONF_DIR/one" "$_WC_CONF_DIR/two" "$_WC_CONF_DIR/three"
  [ "$status" = 5 ]
  for dest in one two three; do
    [ "$(cat "$_WC_CONF_DIR/$dest")" = "original $dest" ]
    printf 'replacement %s\n' "$dest" > "$stage/$dest"
  done
  rm "$SCRATCH/inject"; touch "$_WC_JOURNAL"
  _wc_commit "$stage" "$_WC_CONF_DIR/one" "$_WC_CONF_DIR/two" "$_WC_CONF_DIR/three"
  [ "$(wc -l < "$_WC_JOURNAL" | tr -d ' ')" = 3 ]
  for dest in one two three; do [ "$(cat "$_WC_CONF_DIR/$dest")" = "replacement $dest" ]; done
}

@test "[M5] [N11] surviving console socket identifies its user session and privileged parent" {
  wc_library
  local cap="$REPO/docs/captures/2026-11-19-web-console/c12-chain.txt"
  [ -r "$cap" ]
  [ "$HOME" = "$SCRATCH" ]
  # m4-air 2026-11-19, C12/P7. Remove the listener to exercise recovery after bootout.
  awk '/^tcp4/ && /ESTABLISHED/ {print}' "$cap" > "$SCRATCH/sockets"
  awk '/^[0-9]/ && $1!=59966 {print}' "$cap" > "$SCRATCH/ps"
  _WC_PREFIX="$SCRATCH"
  local K3DM_WC_STOP_WAIT_SCALE=0
  _wc_tool() {
    local cmd="$1"; shift
    case "$cmd" in
      /usr/sbin/netstat) cat "$SCRATCH/sockets" ;;
      /bin/launchctl) printf 'Could not find service "%s" in domain for system\n' "$_WC_LABEL" >&2; return 113 ;;
      /bin/ps)
        if [[ "$1" = -axo ]]; then cat "$SCRATCH/ps"
        else awk -v p="${!#}" '$1==p {print $4,$5,$6,$7,$8; found=1} END {exit !found}' "$SCRATCH/ps"; fi ;;
      *) return 99 ;;
    esac
  }
  _wc_priv() {
    case "$1" in
      /bin/launchctl) return 113 ;;
      /bin/kill)
        echo "$2 $3" >> "$SCRATCH/kill"
        if [[ "$2" = -KILL ]]; then
          awk -v p="$3" '$1!=p' "$SCRATCH/ps" > "$SCRATCH/remaining"; mv "$SCRATCH/remaining" "$SCRATCH/ps"
          awk -v p="$3" '$11 !~ (":" p "$")' "$SCRATCH/sockets" > "$SCRATCH/remaining"; mv "$SCRATCH/remaining" "$SCRATCH/sockets"
        fi ;;
      *) return 99 ;;
    esac
  }
  _wc_stop 42723
  local p
  for p in 60135 60138 60139; do grep -Fxq -- "-TERM $p" "$SCRATCH/kill"; grep -Fxq -- "-KILL $p" "$SCRATCH/kill"; done
  run grep -E ' (10112|10115|31009|31012|60133|70003)$' "$SCRATCH/kill"
  [ "$status" = 1 ]
  awk '/^tcp4/ && /ESTABLISHED/ {print}' "$cap" > "$SCRATCH/sockets"
  awk '/^[0-9]/ && $1!=59966 && $1!=60135 {print}' "$cap" > "$SCRATCH/ps"
  : > "$SCRATCH/kill"
  run _wc_stop 42723
  [ "$status" = 1 ]
  [[ "$output" = *'60138 is not a console session; not signalled'* ]]
  [ ! -s "$SCRATCH/kill" ]
}

@test "[M4] [N1] [N4] local check identifies the broken file, listener and login entry" {
  wc_fixture
  local root="$K3DM_WC_ROOT" dir="$K3DM_WC_ROOT/etc/k3dm-web-console" file original row
  run "$WC_BIN" install --ca-file "$HOME/ca.pub"
  [ "$status" = 0 ]
  row=$(awk '/^tcp4/ && / LISTEN / {print;exit}' "$WC_CAPTURE_DIR/c12-chain.txt")
  row="${row//42723/42722}"
  for original in "${row/127.0.0.1.42722/0.0.0.0.42722}" "${row/127.0.0.1.42722/\*.42722}" "${row/59966/99999}" "$row"$'\n'"$row" ''; do
    printf '%s\n' "$original" > "$root/sockets"
    run "$WC_BIN" check
    [ "$status" = 1 ]
    [[ "$output" = *'FAIL C3 '* ]]
  done
  rm "$root/sockets"
  printf '501\n' > "$root/listener-uid"
  run "$WC_BIN" check
  [ "$status" = 1 ]
  [[ "$output" = *'FAIL C3 '* ]]
  rm "$root/listener-uid"
  for file in launchd.plist.pending launchd.plist.revoked revoked; do
    touch "$dir/$file"; run "$WC_BIN" check; rm "$dir/$file"
    [ "$status" = 1 ]
    [[ "$output" = *'FAIL C1 '* ]]
  done
  cp "$dir/manifest" "$SCRATCH/old"
  sed '/ssh_host_ed25519_key.pub/d' "$SCRATCH/old" > "$dir/manifest"
  run "$WC_BIN" check
  [ "$status" = 1 ]
  [[ "$output" = *'FAIL C1 '* ]]
  cp "$SCRATCH/old" "$dir/manifest"
  printf '#different\n' >> "$root/Library/PrivilegedHelperTools/k3dm-web-console/forced-command"
  run "$WC_BIN" check
  [ "$status" = 1 ]
  [[ "$output" = *'FAIL C6 '* ]]
  printf '"Match" User someone\n' >> "$dir/sshd_config"
  touch "$root/etc/ssh/sshrc"; run "$WC_BIN" check
  [ "$status" = 1 ]
  [[ "$output" = *'FAIL C2 '* && "$output" = *'FAIL C10 '* ]]
}

@test "[M4] C7 rejects tunnel routes and reports uncertainty with FAIL taking precedence" {
  wc_fixture
  source "$WC_BIN"; wc_library; _wc_fixture_gate
  local port=42722 route file="$HOME/route.yml"
  for route in ssh://localhost:22 tcp://127.0.0.1:22 ssh://127.0.0.1:49777 http://127.0.0.1:22 rdp://localhost; do
    printf '{"ingress":[{"service":"%s"}]}\n'  "$route" > "$file"
    run _wc_check_routes "$file"
    [ "$status" = 1 ] || { echo "$output"; return 1; }
  done
  printf '{"ingress":[{"service":"ssh://127.0.0.1:42722"}]}\n'  > "$file"
  _wc_check_routes "$file"
  printf '/bin/cloudflared tunnel --token secret\n' > "$K3DM_WC_ROOT/processes"
  run _wc_check_routes "$file"; [ "$status" = 2 ]
  run _wc_check_routes "$HOME/missing"; [ "$status" = 1 ]
  for route in '{"warp-routing":{"enabled":true}}' '{"originRequest":{"bastionMode":true}}' '{"ingress":[{"service":"http://example","originRequest":{"bastionMode":true}}]}' '[:'; do
    printf '%s\n' "$route" > "$file"
    run _wc_check_routes "$file"; [ "$status" = 1 ]
  done
  run grep -F "$HOME" "$K3DM_WC_ROOT/calls.log"
  [ "$status" = 1 ]
}

@test "[M4] C8 follows the complete Include graph and reports uncertainty for Match and excessive depth" {
  wc_fixture
  source "$WC_BIN"; wc_library; _wc_fixture_gate
  shopt -s nullglob
  local dir="$K3DM_WC_ROOT/etc/ssh" n
  mkdir "$dir/sshd_config.d" "$dir/crypto"
  printf 'Include sshd_config.d/*\n' > "$dir/sshd_config"
  printf 'Include /etc/ssh/crypto.conf\n' > "$dir/sshd_config.d/100-macos.conf"
  ln -s crypto/apple.conf "$dir/crypto.conf"
  printf 'PasswordAuthentication no\n' > "$dir/crypto/apple.conf"
  _wc_system_graph "$dir/sshd_config" 0
  printf '"mATch" User someone\n' >> "$dir/crypto/apple.conf"
  run _wc_system_graph "$dir/sshd_config" 0; [ "$status" = 1 ]
  printf 'Include crypto/apple.conf\n' > "$dir/sshd_config.d/100-macos.conf"
  run _wc_system_graph "$dir/sshd_config" 0; [ "$status" = 1 ]
  printf 'PasswordAuthentication no\n' > "$dir/crypto/apple.conf"
  _wc_system_graph "$dir/sshd_config" 0
  chmod 000 "$dir/crypto/apple.conf"
  run _wc_system_graph "$dir/sshd_config" 0; [ "$status" = 1 ]
  chmod 0644 "$dir/crypto/apple.conf"
  for ((n=0;n<17;n++)); do printf 'Include level%s\n' "$((n+1))" > "$dir/level$n"; done
  touch "$dir/level17"
  run _wc_system_graph "$dir/level0" 0; [ "$status" = 1 ]
}

wc_upgrade_snapshot() {
  python3 - "$K3DM_WC_ROOT" <<'PY'
import hashlib, sys
from pathlib import Path
r=Path(sys.argv[1])
assert (r/'.k3dm-wc-fixture').is_file()
manifest=r/'etc/k3dm-web-console/manifest'
rows=[]
for row in manifest.read_text().splitlines():
    digest, name, part, source=row.split()
    p=r/name.lstrip('/')
    if p.name in ('forced-command','forced-command.stub'): p.write_bytes(b'#!/bin/sh\nexit 1 # previous\n')
    elif p.name in ('sshd_config','access_ca.pub') or name.endswith('.plist'): p.write_bytes(p.read_bytes()+b'\n')
    rows.append(' '.join([hashlib.sha256(p.read_bytes()).hexdigest(),name,part,source]))
manifest.write_text('\n'.join(rows)+'\n')
PY
}

@test "[M2] [M12] [N5] [N13] journal survives crashes on both sides of every upgrade rename" {
  wc_fixture
  local root="$K3DM_WC_ROOT" n boundary txn="$K3DM_WC_ROOT/var/db/k3dm-web-console.txn"
  local paths=(/etc/k3dm-web-console/access_ca.pub /Library/PrivilegedHelperTools/k3dm-web-console/forced-command.stub /Library/PrivilegedHelperTools/k3dm-web-console/forced-command /etc/k3dm-web-console/sshd_config /etc/k3dm-web-console/manifest /Library/LaunchDaemons/com.k3d-manager.web-console-sshd.plist)
  run "$WC_BIN" install --ca-file "$HOME/ca.pub"
  [ "$status" = 0 ]
  wc_upgrade_snapshot
  cp -R "$root" "$SCRATCH/before"
  source "$WC_BIN"; wc_library; _wc_fixture_gate
  for boundary in rename append; do
    for n in 1 2 3 4 5 6; do
      [ -f "$root/.k3dm-wc-fixture" ]
      rm -rf -- "$root"; cp -R "$SCRATCH/before" "$root"
      printf '0\n' > "$root/renames"
      printf '%s:%s\n' "$boundary" "$n" > "$root/crash-at"
      run /bin/bash -c 'printf "%s\n" "$$" > "$K3DM_WC_ROOT/crash-child"; exec "$@"' fixture "$WC_BIN" install --ca-file "$HOME/ca.pub"
      [ "$status" = 137 ] || { echo "$boundary $n: $status $output"; return 1; }
      local i path backup
      : > "$SCRATCH/expected"
      for ((i=0;i<n;i++)); do
        path="${paths[i]}"
        case "$path" in /Library/PrivilegedHelperTools/*) backup="${path%/*}/.prev" ;; *) backup=/etc/k3dm-web-console/.prev ;; esac
        printf '%s moved %s %s/%s\n' "$((i+1))" "$path" "$backup" "${path##*/}" >> "$SCRATCH/expected"
      done
      cmp "$SCRATCH/expected" "$txn"
      if [[ "$boundary" = append ]]; then [ "$(cat "$root/renames")" = "$((n-1))" ]; fi
      rm "$root/crash-at"
      if [[ "$boundary:$n" = rename:6 ]]; then
        # Simulate revoke after the plist rename and recover without launching
        # another installer, the same library entry point part C uses.
        printf '20261119T180000Z.123\n' > "$root/etc/k3dm-web-console/revoked"
        mv "$root${paths[5]}" "$root/etc/k3dm-web-console/launchd.plist.revoked"
        touch "$root/fail.restore"
        run _wc_txn_recover
        [ "$status" = 5 ]
        cmp "$txn" "$SCRATCH/expected"
        rm "$root/fail.restore"
      fi
      _wc_txn_recover
      [ ! -e "$txn" ]
      for path in "${paths[@]}"; do
        if [[ "$boundary:$n" = rename:6 && "$path" = "${paths[5]}" ]]; then
          [ ! -e "$root$path" ]
          cmp "$SCRATCH/before$path" "$root/etc/k3dm-web-console/launchd.plist.revoked"
        else cmp "$SCRATCH/before$path" "$root$path"; fi
      done
      [ ! -e "$root/Library/LaunchDaemons/.prev" ]
      run "$WC_BIN" install --after-revoke --ca-file "$HOME/ca.pub"
      [ "$status" = 0 ] || { echo "$boundary $n: $status $output"; return 1; }
      [ -f "$root/job" ]; [ ! -e "$txn" ]
    done
  done
}

@test "[M3] [N5] [N7] source keeps privilege decisions and diagnostics inside the wrapper" {
  python3 - "$REPO" <<'PY'
import re, sys
from pathlib import Path
repo=Path(sys.argv[1])
script=(repo/'bin/k3dm-web-console-sshd').read_text()
lib=(repo/'scripts/lib/web_console_common.sh').read_text()
body=re.search(r'^function _wc_priv\(\) \{\n(.*?)\n\}',lib,re.M|re.S)
assert body and body[1].strip()=='_run_command --interactive-sudo --soft --quiet -- "$@"'
assert (lib+script).count('_run_command')==1
assert 'unset -f sudo' not in lib
assert re.search(r'^function main\(\) \{\n  _wc_main_env\n',script,re.M)
assert re.search(r'^function _wc_main_env\(\) \{\n  PATH=/usr/bin:/bin:/usr/sbin:/sbin\n  unset -f sudo\n\}',script,re.M)
for line in (lib+script).splitlines():
    if '_wc_priv /' in line:
        checked=('||' in line or '&&' in line or '; then' in line)
        assert checked, line
        if '/usr/bin/tee ' in line: assert re.search(r'(?<!2)>/dev/null',line), line
        if '/usr/sbin/sshd ' not in line: assert '2>/dev/null' in line, line
    assert not re.search(r'^\s*(?:command\s+)?sudo\s',line),line
sudoers=(repo/'bin/install-sudoers.sh').read_text()
for line in sudoers.splitlines():
    if 'NOPASSWD' in line:
        assert '/bin/sleep' not in line, line
        assert '/usr/bin/id' not in line, line
PY
  _WC_JOURNAL=/x
  wc_library
  [ "$_WC_JOURNAL" = /var/db/k3dm-web-console.txn ]
}

@test "[M3] tty opens a ticket and confirms it works in a pipe" {
  local child="$SCRATCH/check-ticket"
  cat > "$child" <<'SH'
#!/bin/bash
source "$1/scripts/lib/system.sh"
source "$1/scripts/lib/web_console_common.sh"
sudo() {
  printf '%s\n' "$*" >> "$WC_TICKET_CALLS"
  if [[ "${1-}" = -n ]]; then return 19; fi
}
_wc_priv_open
rc=$?
printf 'caller-alive=%s\n' "$rc"
exit "$rc"
SH
  chmod +x "$child"
  export WC_TICKET_CALLS="$SCRATCH/ticket-calls"
  run wc_pty_run "$child" "$REPO"
  [ "$status" = 10 ]
  [[ "$output" = *'ticket not usable from a pipe'* && "$output" = *'caller-alive=10'* ]]
  [ "$(head -1 "$WC_TICKET_CALLS")" = "/bin/sleep 0" ]
  [ "$(tail -1 "$WC_TICKET_CALLS")" = '-n /usr/bin/id -u' ]
}

@test "[M6] [N8] fallback never hides a busy or part-C-mismatched port" {
  wc_fixture
  local root="$K3DM_WC_ROOT"
  awk '/^tcp4/ && / LISTEN /{gsub(/42723/,"42722");print;exit}' "$WC_CAPTURE_DIR/c12-chain.txt" > "$root/sockets"
  run "$WC_BIN" install --dry-run
  [ "$status" = 2 ]
  [[ "$output" = *'refusing port 42722: held by another process'* ]]
  touch "$root/job"
  run "$WC_BIN" install --dry-run
  [ "$status" = 0 ]
  [[ "$output" = *'ListenAddress 127.0.0.1:42722'* ]]
  rm "$root/job" "$root/sockets"
  mkdir "$root/etc/k3dm-web-console"
  printf 'console_port=42722\n' > "$root/etc/k3dm-web-console/totp.conf"
  run env WEB_CONSOLE_SSH_PORT=42723 "$WC_BIN" install --dry-run
  [ "$status" = 2 ]
  [[ "$output" = *'part C is installed on port 42722'* ]]
  run env WEB_CONSOLE_SSH_PORT='' "$WC_BIN" install --dry-run
  [ "$status" = 2 ]
  [[ "$output" = *'empty value'* ]]
  run grep '^priv ' "$root/calls.log"
  [ "$status" = 1 ]
}

@test "[M5] revoke uses the installed port then the privileged previous port then the environment or default" {
  wc_fixture
  local root="$K3DM_WC_ROOT" dir="$K3DM_WC_ROOT/etc/k3dm-web-console"
  mkdir -p "$dir/.prev"; chmod 0700 "$dir/.prev"
  source "$WC_BIN"; wc_library; _wc_fixture_gate
  printf 'ListenAddress 127.0.0.1:42720\n' > "$dir/sshd_config"
  printf 'ListenAddress 127.0.0.1:42721\n' > "$dir/.prev/sshd_config"
  [ "$(_wc_port_lookup)" = '42720 installed' ]
  rm "$dir/sshd_config"
  [ "$(_wc_port_lookup)" = '42721 prev' ]
  grep -q 'priv /usr/bin/head -n 1 .*\.prev/sshd_config' "$root/calls.log"
  printf 'Port 22\n' > "$dir/.prev/sshd_config"
  [ "$(WEB_CONSOLE_SSH_PORT=42723 _wc_port_lookup)" = '42723 env' ]
  [ "$(_wc_port_lookup)" = '42722 default' ]
  printf 'closed\n' > "$root/ticket"
  run "$WC_BIN" revoke </dev/null
  [ "$status" = 10 ]
  [ ! -e "$dir/revoked" ]
}

@test "[M5] [N11] [N13] listener mismatch never signals its tree and still attempts bootout" {
  wc_library
  local cap="$REPO/docs/captures/2026-11-19-web-console/c12-chain.txt"
  [ -f "$cap" ]
  [ "$HOME" = "$SCRATCH" ]
  local K3DM_WC_STOP_WAIT_SCALE=0 listener_uid=501
  _WC_PREFIX="$SCRATCH"
  _wc_tool() {
    case "$1:$2" in
      /usr/sbin/netstat:*) awk '/^tcp4/ {print}' "$cap" ;;
      /bin/ps:-axo) awk '/^[0-9]/{print}' "$cap" ;;
      /bin/ps:-o)
        if [[ "$3" = uid= ]]; then echo "$listener_uid"
        else awk -v p="${!#}" '$1==p {print $4,$5,$6,$7,$8;rc=1} END{exit !rc}' "$cap"; fi ;;
      /bin/launchctl:print) printf 'pid = 98765\n' ;;
      *) return 99 ;;
    esac
  }
  _wc_priv() { printf '%s\n' "$*" >> "$SCRATCH/signals"; return 1; }
  for listener_uid in 501 0; do
    : > "$SCRATCH/signals"
    run _wc_stop 42723
    [ "$status" = 1 ]
    [[ "$output" = *'job still registered after bootout'* ]]
    grep -q 'launchctl bootout' "$SCRATCH/signals"
    run grep '/bin/kill' "$SCRATCH/signals"; [ "$status" = 1 ]
  done
}

@test "[M5] [N11] a changed lstart prevents signalling a reused PID while the original session is signalled" {
  wc_library
  local cap="$REPO/docs/captures/2026-11-19-web-console/c12-chain.txt" signal=TERM
  [ "$HOME" = "$SCRATCH" ]
  [ -r "$cap" ]
  # shellcheck disable=SC2034 # Read by _wc_signal_set.
  local members=() excluded=()
  members[60138]='Thu Nov 19 18:34:57 2026'
  # shellcheck disable=SC2034 # Read by _wc_signal_set.
  members[60139]='Thu Nov 19 18:34:57 2026'
  _wc_tool() {
    if [[ "${!#}" = 60139 ]]; then printf 'Thu Nov 19 18:35:01 2026\n'
    else awk '$1==60138 {print $4,$5,$6,$7,$8}' "$cap"; fi
  }
  _wc_priv() { printf '%s\n' "$*" >> "$SCRATCH/signals"; }
  for signal in TERM KILL; do
    : > "$SCRATCH/signals"
    _wc_signal_set "$signal"
    [ "$(cat "$SCRATCH/signals")" = "/bin/kill -$signal 60138" ]
  done
}

@test "[M2] [N6] destination trust rejects symlinks, operator ownership, ACLs and writable files before lock" {
  wc_fixture
  local root="$K3DM_WC_ROOT" dir="$K3DM_WC_ROOT/etc/k3dm-web-console" mode
  mkdir "$dir"; touch "$dir/sshd_config"
  for mode in symlink owner acl writable; do
    case "$mode" in
      symlink) rm "$dir/sshd_config"; ln -s /dev/null "$dir/sshd_config" ;;
      owner) rm "$dir/sshd_config"; touch "$dir/sshd_config"; echo 501 > "$root/owner.sshd_config" ;;
      acl) rm "$root/owner.sshd_config"; touch "$root/fail.acl.sshd_config" ;;
      writable) rm "$root/fail.acl.sshd_config"; chmod 0664 "$dir/sshd_config" ;;
    esac
    : > "$root/calls.log"
    run "$WC_BIN" install --ca-file "$HOME/ca.pub"
    [ "$status" = 8 ]
    [[ "$output" = *'untrusted path'* ]]
    run grep 'priv /bin/mkdir' "$root/calls.log"; [ "$status" = 1 ]
  done
}

@test "[M2] [M11] foreign forced-command refused and manifest-listed part C gate preserved" {
  wc_fixture
  local root="$K3DM_WC_ROOT" dir="$K3DM_WC_ROOT/etc/k3dm-web-console" helper="$K3DM_WC_ROOT/Library/PrivilegedHelperTools/k3dm-web-console"
  run "$WC_BIN" install --ca-file "$HOME/ca.pub"
  [ "$status" = 0 ]
  printf '#!/bin/sh\nexit 29\n' > "$helper/forced-command"
  run "$WC_BIN" install
  [ "$status" = 8 ]
  [[ "$output" = *'unrecognised forced-command'* ]]
  local hash
  hash=$(shasum -a 256 < "$helper/forced-command"); hash="${hash%% *}"
  awk -v h="$hash" '$2 ~ /\/forced-command$/ {$1=h;$3="C";$4="blob-fixture"} {print}' "$dir/manifest" > "$SCRATCH/new"
  cp "$SCRATCH/new" "$dir/manifest"
  run "$WC_BIN" install
  [ "$status" = 0 ] || { echo "$output"; return 1; }
  [ "$(awk '$3=="A"{n++}END{print n}' "$dir/manifest")" = 5 ]
  [ "$(shasum -a 256 < "$helper/forced-command")" = "$hash  -" ]
  run "$WC_BIN" uninstall --purge
  [ "$status" = 6 ]
}

@test "[M7] recipes pass operator inputs as shell arguments" {
  python3 - "$REPO/Makefile" <<'PY'
from pathlib import Path
import sys
s=Path(sys.argv[1]).read_text()
for name in ('install-web-console-sshd','uninstall-web-console-sshd','revoke-web-console-sshd','web-console-sshd-check'):
    assert any(name in ln.split()[1:] for ln in s.splitlines() if ln.startswith('.PHONY:')), name
install=s.split('\ninstall-web-console-sshd:\n')[1].split('\n\n')[0]
assert '$${CA_FILE:+--ca-file "$$CA_FILE"}' in install
assert '$${AFTER_REVOKE:+--after-revoke}' in install
uninstall=s.split('\nuninstall-web-console-sshd:\n')[1].split('\n\n')[0]
assert 'case "$${PURGE-}"' in uninstall and '1) set -- --purge' in uninstall and '"$$@"' in uninstall
PY
}

@test "[N12] fixture tool invocation goes through the shim even for an installed read-only tool" {
  wc_fixture
  source "$WC_BIN"; wc_library; _wc_fixture_gate
  printf 'fixture-platform\n' > "$K3DM_WC_ROOT/platform"
  local answer
  answer=$(_wc_tool /usr/bin/uname -s)
  [ "$answer" = fixture-platform ]
  grep -q 'tool /usr/bin/uname -s' "$K3DM_WC_ROOT/calls.log"
}

@test "[N1] [N4] sshd interprets quoted Match, tab Match, and an additional SetEnv assignment" {
  [ "$(uname -s)" = Darwin ] || skip "sshd not found"
  [ -x /usr/sbin/sshd ]
  local tmpl="$REPO/scripts/etc/ssh/k3dm-web-console_sshd_config.tmpl" keyword
  [ -f "$tmpl" ]
  sed -e 's/{{CONSOLE_PORT}}/42722/g' -e 's/{{CONSOLE_USER}}/someone/g' "$tmpl" > "$SCRATCH/canonical"
  ssh-keygen -q -t ed25519 -N '' -C fixture -f "$SCRATCH/host"
  for keyword in '"Match" User someone' $'Match\tUser someone'; do
    cp "$SCRATCH/canonical" "$SCRATCH/config"
    printf '%s\nPasswordAuthentication yes\n' "$keyword" >> "$SCRATCH/config"
    run /usr/sbin/sshd -T -C user=someone -f "$SCRATCH/config" -h "$SCRATCH/host"
    [ "$status" = 0 ]
    grep -Fxq 'passwordauthentication yes' <<< "$output"
  done
  sed 's@^SetEnv .*@SetEnv ZDOTDIR=/x FOO=bar@' "$SCRATCH/canonical" > "$SCRATCH/config"
  run /usr/sbin/sshd -T -C user=someone -f "$SCRATCH/config" -h "$SCRATCH/host"
  [ "$status" = 0 ]
  grep -Fxq 'setenv FOO=bar' <<< "$output"
}

@test "[M12] [N13] revoked marker at either bootstrap boundary leaves no registered job or active plist" {
  wc_fixture
  local root="$K3DM_WC_ROOT" dir="$K3DM_WC_ROOT/etc/k3dm-web-console" plist="$K3DM_WC_ROOT/Library/LaunchDaemons/com.k3d-manager.web-console-sshd.plist" mode count
  cp -R "$root" "$SCRATCH/pristine"
  for mode in before-bootstrap after-bootstrap bootstrap-revoke late-zdotdir; do
    [ -f "$root/.k3dm-wc-fixture" ]
    rm -rf -- "$root"; cp -R "$SCRATCH/pristine" "$root"
    touch "$root/fail.$mode"
    run "$WC_BIN" install --ca-file "$HOME/ca.pub"
    case "$mode" in
      before-bootstrap) [ "$status" = 11 ]; count=0 ;;
      after-bootstrap) [ "$status" = 11 ]; count=1 ;;
      bootstrap-revoke) [ "$status" = 5 ]; count=1 ;;
      late-zdotdir) [ "$status" = 8 ]; count=0 ;;
    esac
    [ ! -e "$root/job" ]
    [ ! -e "$plist" ]
    if [[ "$mode" = *-bootstrap ]]; then [ -f "$dir/revoked" ]; [ -f "$dir/launchd.plist.revoked" ]; fi
    [ "$(awk '/priv .*launchctl bootstrap/{n++}END{print n+0}' "$root/calls.log")" = "$count" ]
  done
}

@test "[M12] [N13] failed explicit restore puts back its marker and a newer marker is never consumed" {
  wc_fixture
  local root="$K3DM_WC_ROOT" dir="$K3DM_WC_ROOT/etc/k3dm-web-console" id
  run "$WC_BIN" install --ca-file "$HOME/ca.pub"
  [ "$status" = 0 ]
  run "$WC_BIN" revoke </dev/null
  [ "$status" = 0 ]
  read -r id < "$dir/revoked"
  touch "$root/fail.bootstrap"; : > "$root/calls.log"
  run "$WC_BIN" install --after-revoke
  [ "$status" = 5 ]
  [ "$(cat "$dir/revoked")" = "$id" ]
  [ ! -e "$root/job" ]
  [ ! -e "$root/Library/LaunchDaemons/com.k3d-manager.web-console-sshd.plist" ]
  [ "$(grep -c 'priv .*launchctl bootstrap' "$root/calls.log")" = 1 ]
  rm "$root/fail.bootstrap"; touch "$root/fail.newer-id"; : > "$root/calls.log"
  run "$WC_BIN" install --after-revoke
  [ "$status" = 11 ]
  [ "$(cat "$dir/revoked")" = 20261119T184301Z.456 ]
  [ ! -e "$root/job" ]
  run grep 'priv .*launchctl bootstrap' "$root/calls.log"; [ "$status" = 1 ]
  [ ! -e "$root/Library/LaunchDaemons/com.k3d-manager.web-console-sshd.plist" ]
}

@test "[M2] [N5] failed bootstrap restores the prior generation including the previous plist" {
  wc_fixture
  local root="$K3DM_WC_ROOT" path dir="$K3DM_WC_ROOT/etc/k3dm-web-console"
  run "$WC_BIN" install --ca-file "$HOME/ca.pub"
  [ "$status" = 0 ]
  wc_upgrade_snapshot
  cp -R "$dir" "$SCRATCH/before"
  cp "$root/Library/LaunchDaemons/com.k3d-manager.web-console-sshd.plist" "$SCRATCH/old-plist"
  : > "$root/calls.log"; touch "$root/fail.bootstrap"
  run "$WC_BIN" install --ca-file "$HOME/ca.pub"
  [ "$status" = 5 ]
  [[ "$output" = *'load failed; previous generation restored'* ]]
  cmp "$SCRATCH/old-plist" "$root/Library/LaunchDaemons/com.k3d-manager.web-console-sshd.plist"
  for path in sshd_config manifest access_ca.pub; do cmp "$SCRATCH/before/$path" "$dir/$path"; done
  [ "$(grep -c 'priv .*launchctl bootstrap' "$root/calls.log")" = 2 ]
}

@test "[M2] lock handles live, holderless, stale and guarded cases" {
  wc_fixture
  wc_library; _wc_fixture_gate
  local lock="$K3DM_WC_ROOT/var/db/k3dm-web-console.lock"
  _wc_lock_take
  run _wc_lock_take; [ "$status" = 7 ]
  rm "$lock/holder"
  run _wc_lock_take; [ "$status" = 7 ]
  printf '9999 Thu Nov 19 18:34:54 2026\n' > "$lock/holder"; echo 9999 > "$K3DM_WC_ROOT/crashed"
  mkdir "$lock.reclaim"
  touch -t 202001010000 "$lock.reclaim"
  run _wc_lock_take; [ "$status" = 7 ]; [[ "$output" = *'stale reclaim guard'* ]]
  [ -d "$lock.reclaim" ]; rmdir "$lock.reclaim"
  _wc_lock_take
  [ -f "$lock/holder" ]
  [ ! -e "$lock.reclaim" ]
  _wc_lock_release
  [ ! -e "$lock" ]
}

wc_run_fault() {
  run /bin/bash -c 'printf "%s\n" "$$" > "$K3DM_WC_ROOT/crash-child"; exec "$@"' fixture "$WC_BIN" install "$@"
}

@test "[M2] [M12] [N13] reboot after interrupted recovery or commit rollback sees only the parked prior plist" {
  wc_fixture
  local root="$K3DM_WC_ROOT" conf="$K3DM_WC_ROOT/etc/k3dm-web-console"
  local plist="$root/Library/LaunchDaemons/com.k3d-manager.web-console-sshd.plist" txn="$root/var/db/k3dm-web-console.txn"
  run "$WC_BIN" install --ca-file "$HOME/ca.pub"
  [ "$status" = 0 ]
  printf '\n' >> "$plist"
  cp "$plist" "$SCRATCH/previous"
  cp -R "$root" "$SCRATCH/generation"
  printf '0\n' > "$root/renames"
  printf 'ssh-ed25519 QkJC replacement\n' > "$HOME/ca.pub"
  touch "$root/fail.third-revoke"
  printf 'restore-plist:1\n' > "$root/crash-at"
  wc_run_fault --ca-file "$HOME/ca.pub"
  [ "$status" = 137 ] || { echo "$status $output"; return 1; }
  [ -e "$txn" ]
  [ -f "$conf/revoked" ]
  # A fresh directory reader sees exactly what RunAtLoad would see at boot.
  run /bin/ls -A "$root/Library/LaunchDaemons"
  [ "$status" = 0 ]; [ -z "$output" ]
  [ ! -e "$plist" ]
  cmp "$conf/launchd.plist.revoked" "$SCRATCH/previous"
  [ -f "$root/.k3dm-wc-fixture" ]
  rm -rf "$root"; cp -R "$SCRATCH/generation" "$root"
  echo 0 > "$root/renames"; touch "$root/fail.third-revoke"
  run "$WC_BIN" install --ca-file "$HOME/ca.pub"
  [ "$status" = 5 ]; [[ "$output" = *'commit failed; previous generation restored'* ]]
  [ -f "$conf/revoked" ]; [ ! -e "$plist" ]; [ ! -e "$txn" ]
  cmp "$conf/launchd.plist.revoked" "$SCRATCH/previous"
  [ -e "$root/.k3dm-wc-fixture" ]; rm -rf "$root"; cp -R "$SCRATCH/generation" "$root"
  printf '0\n' > "$root/renames"; printf 'rename:3\n' > "$root/crash-at"
  wc_run_fault --ca-file "$HOME/ca.pub"
  [ "$status" = 137 ]
  run "$WC_BIN" revoke </dev/null
  [ "$status" = 0 ]
  cp -R "$root" "$SCRATCH/interrupted"
  printf 'restore-plist:1\n' > "$root/crash-at"
  wc_run_fault --after-revoke
  [ "$status" = 137 ] || { echo "$status $output"; return 1; }
  # A fresh directory reader sees exactly what RunAtLoad would see at boot.
  run /bin/ls -A "$root/Library/LaunchDaemons"
  [ "$status" = 0 ]; [ -z "$output" ]
  [ ! -e "$plist" ]
  cmp "$conf/launchd.plist.revoked" "$SCRATCH/previous"
  local option
  for option in plain validated; do
    [ -e "$root/.k3dm-wc-fixture" ]; rm -rf "$root"; cp -R "$SCRATCH/interrupted" "$root"
    rm "$root/crash-at"; touch "$root/fail.-t"
    if [[ "$option" = plain ]]; then
      run "$WC_BIN" install; [ "$status" = 2 ]; [[ "$output" = *'recovering first'* ]]
    else
      run "$WC_BIN" install --after-revoke; [ "$status" = 4 ]
    fi
    cmp "$conf/revoked" "$SCRATCH/interrupted/etc/k3dm-web-console/revoked"
    [ ! -e "$plist" ]; [ ! -e "$txn" ]; cmp "$conf/launchd.plist.revoked" "$SCRATCH/previous"
  done
}

@test "[M2] [N5] first-install crash records the created directories and retries a failed restore" {
  wc_fixture
  local root="$K3DM_WC_ROOT" txn="$K3DM_WC_ROOT/var/db/k3dm-web-console.txn"
  echo rename:3 > "$root/crash-at"
  wc_run_fault --ca-file "$HOME/ca.pub"
  [ "$status" = 137 ]
  cat > "$SCRATCH/expected" <<'JOURNAL'
1 created /etc/k3dm-web-console -
2 created /etc/k3dm-web-console/zdotdir -
3 created /Library/PrivilegedHelperTools/k3dm-web-console -
4 created /etc/k3dm-web-console/.prev -
5 created /Library/PrivilegedHelperTools/k3dm-web-console/.prev -
6 moved /etc/k3dm-web-console/access_ca.pub -
7 moved /Library/PrivilegedHelperTools/k3dm-web-console/forced-command.stub -
8 moved /Library/PrivilegedHelperTools/k3dm-web-console/forced-command -
JOURNAL
  cmp "$SCRATCH/expected" "$txn"; rm "$root/crash-at"
  run "$WC_BIN" install --ca-file "$HOME/ca.pub"
  [ "$status" = 0 ]; [[ "$output" = *'rolled back an interrupted install'* ]]
  wc_upgrade_snapshot
  echo 0 > "$root/renames"; echo rename:2 > "$root/crash-at"
  wc_run_fault --ca-file "$HOME/ca.pub"
  [ "$status" = 137 ]
  rm "$root/crash-at"; touch "$root/fail.restore"; cp "$txn" "$SCRATCH/expected"
  run "$WC_BIN" install --ca-file "$HOME/ca.pub"
  [ "$status" = 5 ]; [[ "$output" = *'restore incomplete; journal kept'* ]]
  cmp "$txn" "$SCRATCH/expected"; [ ! -d "$root/var/db/k3dm-web-console.lock" ]
  rm "$root/fail.restore"
  run "$WC_BIN" install --ca-file "$HOME/ca.pub"
  [ "$status" = 0 ]; [ ! -e "$txn" ]
}

@test "[M2] [M12] staged hash and final parked-file cleanup report their distinct failures" {
  wc_fixture
  local root="$K3DM_WC_ROOT" dir="$K3DM_WC_ROOT/etc/k3dm-web-console"
  touch "$root/fail.rehash"
  run "$WC_BIN" install --ca-file "$HOME/ca.pub"
  [ "$status" = 8 ]; [ ! -d "$dir" ]; [ ! -e "$root/job" ]
  rm "$root/fail.rehash"
  run "$WC_BIN" install
  [ "$status" = 3 ]; [ -e "$dir/launchd.plist.pending" ]
  touch "$root/fail.clear-parked"
  run "$WC_BIN" install --ca-file "$HOME/ca.pub"
  [ "$status" = 1 ]; [[ "$output" = *'stale launchd.plist.pending not removed'* ]]
  [ -f "$root/job" ]; [ -f "$dir/launchd.plist.pending" ]
  run "$WC_BIN" check; [ "$status" = 1 ]; [[ "$output" = *'FAIL C1'* ]]
  rm "$root/fail.clear-parked"
  run "$WC_BIN" install; [ "$status" = 0 ]; [ ! -e "$dir/launchd.plist.pending" ]
}

@test "[M5] [N11] [N13] stop follows the captured process tree across bootout and distinguishes socket states" {
  wc_library
  local cap="$REPO/docs/captures/2026-11-19-web-console/c12-chain.txt"
  export K3DM_WC_STOP_WAIT_SCALE=0
  [ "$HOME" = "$SCRATCH" ]; [ -r "$cap" ]; _WC_PREFIX="$SCRATCH"
  local e9_table="$SCRATCH/processes" e9_sockets="$SCRATCH/socket-e9_table" e9_calls="$SCRATCH/signals" e9_scenario
  local e9_row
  e9_row=$(awk '/^tcp4/ && /ESTABLISHED/ && $4~/42723$/ {print; exit}' "$cap")
  _wc_tool() {
    local cmd="$1"; shift
    case "$cmd" in
      /bin/ps)
        if [[ "$1" = -axo ]]; then cat "$e9_table"
        elif [[ "$2" = uid= ]]; then awk -v p="${!#}" '$1==p {print $3}' "$e9_table"
        else awk -v p="${!#}" '$1==p {print $4,$5,$6,$7,$8;f=1} END{exit !f}' "$e9_table"; fi ;;
      /usr/sbin/netstat) cat "$e9_sockets" ;;
      /bin/launchctl)
        if [[ -f "$SCRATCH/job" ]]; then cat "$SCRATCH/job"
        elif [[ "$e9_scenario" = unknown ]]; then echo 'lookup failed' >&2; return 5
        else printf 'Could not find service "%s" in domain for system\n' "$_WC_LABEL" >&2; return 113; fi ;;
      *) return 99 ;;
    esac
  }
  _wc_priv() {
    printf '%s\n' "$*" >> "$e9_calls"
    case "$1" in
      /bin/launchctl)
        if [[ "$e9_scenario" = tree ]]; then
          awk '$1==60138 {$1=70001;$2=60138} $1==70001 {print}' "$cap" >> "$e9_table"
          awk '$1==60135 || $1==70002 {$2=1} $1!=59966 {print}' "$e9_table" > "$e9_table.tmp"
          mv "$e9_table.tmp" "$e9_table"
          awk '$6!="LISTEN"' "$e9_sockets" > "$e9_sockets.tmp"; mv "$e9_sockets.tmp" "$e9_sockets"
        fi
        case "$e9_scenario" in idle|registered) return 4 ;; esac
        rm -f "$SCRATCH/job"; return 113 ;;
      /bin/kill)
        [[ "$2" = -KILL && "$e9_scenario" != survivor ]] || return 0
        awk -v p="$3" '$1!=p' "$e9_table" > "$e9_table.tmp"; mv "$e9_table.tmp" "$e9_table"
        awk -v p="$3" '$11 !~ (":"p"$")' "$e9_sockets" > "$e9_sockets.tmp"; mv "$e9_sockets.tmp" "$e9_sockets" ;;
      *) return 99 ;;
    esac
  }
  for e9_scenario in tree privileged ambiguous gone timewait finwait idle registered unknown survivor; do
    awk '/^[0-9]/{print}' "$cap" > "$e9_table"; : > "$e9_sockets"; : > "$e9_calls"; rm -f "$SCRATCH/job"
    # Model pkill -f against the saved command column. The listener matches
    # the config path, but its forked session cannot be stopped that way.
    [ "$(awk '/^[0-9]+ / && /prod[.]conf/{print $1}' "$e9_table")" = 59966 ]
    grep -Eq '^60138 +60135 ' "$e9_table"
    printf '60133 1 501 Thu Nov 19 18:34:57 2026 cloudflared\n70003 1 501 Thu Nov 19 18:34:57 2026 tmux: server\n' >> "$e9_table"
    case "$e9_scenario" in
      tree) awk '$1==60135 {$1=70002;print}' "$cap" >> "$e9_table"
        awk '/^tcp4/{print}' "$cap" > "$e9_sockets"; echo 'pid = 59966' > "$SCRATCH/job" ;;
      privileged) echo "${e9_row/60138/60135}" > "$e9_sockets" ;;
      ambiguous) echo "${e9_row/60138/60139}" > "$e9_sockets" ;;
      gone) echo "${e9_row/60138/99999}" > "$e9_sockets" ;;
      timewait) echo "${e9_row/ESTABLISHED/TIME_WAIT}" > "$e9_sockets" ;;
      finwait) echo "${e9_row/ESTABLISHED/FIN_WAIT_2}" > "$e9_sockets" ;;
      idle) echo 'state = not running' > "$SCRATCH/job" ;;
      registered) echo 'pid = 59966' > "$SCRATCH/job" ;;
      survivor) echo "$e9_row" > "$e9_sockets" ;;
    esac
    run _wc_stop 42723
    case "$e9_scenario" in
      tree)
        [ "$status" = 0 ]
        for p in 60135 60138 60139 70001 70002; do grep -Fxq "/bin/kill -KILL $p" "$e9_calls"; done
        run grep -E '/kill .* (10112|10115|31009|31012|60133|70003)$' "$e9_calls"; [ "$status" = 1 ] ;;
      privileged) [ "$status" = 0 ]; grep -Fxq '/bin/kill -TERM 60135' "$e9_calls" ;;
      ambiguous) [ "$status" = 1 ]; [[ "$output" = *'60139 is not a console session'* ]]; run grep '/kill' "$e9_calls"; [ "$status" = 1 ] ;;
      idle|registered|unknown) [ "$status" = 1 ]; [[ "$output" = *'job still registered'* ]] ;;
      survivor) [ "$status" = 1 ]; [[ "$output" = *'survivor 60138'* ]] ;;
      *) [ "$status" = 0 ]; run grep '/kill' "$e9_calls"; [ "$status" = 1 ] ;;
    esac
    grep -q 'launchctl bootout' "$e9_calls"
  done
}

@test "[M2] [M12] [N13] shared recovery reconciles even without journal and reports a failed park" {
  wc_fixture
  local root="$K3DM_WC_ROOT" dir="$K3DM_WC_ROOT/etc/k3dm-web-console" plist="$K3DM_WC_ROOT/Library/LaunchDaemons/com.k3d-manager.web-console-sshd.plist"
  wc_library; _wc_fixture_gate
  mkdir -p "$dir"
  touch "$plist" "$root/job"
  echo 20261119T180000Z.123 > "$dir/revoked"
  touch "$root/fail.mv"
  run _wc_txn_recover
  [ "$status" = 1 ]
  [ ! -e "$root/job" ]; [ -e "$plist" ]
  : > "$root/var/db/k3dm-web-console.txn"
  run "$WC_BIN" install --after-revoke
  [ "$status" = 1 ]; [[ "$output" = *'revoked marker present but the daemon is not parked; run revoke again'* ]]
  rm "$root/fail.mv"
  _wc_txn_recover
  [ ! -e "$plist" ]; [ ! -e "$root/job" ]; [ -e "$dir/launchd.plist.revoked" ]
  run grep 'priv .*bootstrap' "$root/calls.log"; [ "$status" = 1 ]
}

@test "[M3] privilege refusal returns to its caller" {
  wc_library
  local rc=0
  _wc_priv_open </dev/null || rc=$?
  [ "$rc" = 10 ]
  run /bin/bash -c 'source "$1"; _wc_priv_open </dev/null; printf "returned=%s\n" "$?"' fixture "$REPO/scripts/lib/web_console_common.sh"
  [ "$status" = 0 ]; [[ "$output" = *'returned=10'* ]]
}

@test "[M7] every literal console label has exactly one classification" {
  local label entries
  [ -f "$REPO/bin/k3dm-web-console-sshd" ]
  entries=$(grep -Eho 'com\.k3d-manager\.web-console-[A-Za-z0-9.-]+' "$REPO/bin/k3dm-web-console-sshd" "$REPO/scripts/lib/web_console_common.sh" | sort -u)
  while read -r label; do
    case "$label" in *.plist|*.plist.tmpl|*.sh) continue ;; esac
    [ "$(cut -d'|' -f1 "$REPO/scripts/etc/machine/not-installed.list" | grep -Fxc "${label#com.k3d-manager.}")" = 1 ]
  done <<< "$entries"
}

@test "[M4] [M11] C1 through C10 identify corrupt manifests, CA, entry, config and mode changes" {
  wc_fixture
  local root="$K3DM_WC_ROOT" dir="$K3DM_WC_ROOT/etc/k3dm-web-console" helper="$K3DM_WC_ROOT/Library/PrivilegedHelperTools/k3dm-web-console" mutation item
  run "$WC_BIN" install --ca-file "$HOME/ca.pub"; [ "$status" = 0 ]
  printf 'passwordauthentication no\nkbdinteractiveauthentication no\n' > "$root/system-config"
  run "$WC_BIN" check --strict; [ "$status" = 0 ]; grep -q '^PASS C8 ' <<< "$output"
  cp -R "$root" "$SCRATCH/healthy"
  for mutation in helper-mode manifest-digest missing-ca two-ca tab-match extra-setenv nonempty-zdot bash-shell zshenv ancestor; do
    case "$mutation" in
      helper-mode) chmod 0775 "$helper/forced-command"; item=C6 ;;
      manifest-digest) printf 'mismatch' >> "$dir/ssh_host_ed25519_key.pub"; item=C1 ;;
      missing-ca) rm "$dir/access_ca.pub"; item=C5 ;;
      two-ca) cat "$HOME/ca.pub" >> "$dir/access_ca.pub"; item=C5 ;;
      tab-match) printf 'Match\tUser someone\n' >> "$dir/sshd_config"; item=C2 ;;
      extra-setenv) printf 'SetEnv ZDOTDIR=/x FOO=bar\n' >> "$dir/sshd_config"; item=C2 ;;
      nonempty-zdot) touch "$dir/zdotdir/unexpected"; item=C1 ;;
      bash-shell) echo /bin/bash > "$root/shell"; item=C10 ;;
      zshenv) touch "$root/etc/zshenv"; item=C10 ;;
      ancestor) chmod 0775 "$root/Library"; item=C1 ;;
    esac
    run "$WC_BIN" check
    [ "$status" = 1 ] || { echo "$mutation $output"; return 1; }
    grep -q "^FAIL $item " <<< "$output"
    [ -f "$root/.k3dm-wc-fixture" ]; rm -rf "$root"; cp -R "$SCRATCH/healthy" "$root"
  done
}

@test "[M4] C7 discovers process configs, skips missing defaults, and applies strict mode" {
  wc_fixture
  local root="$K3DM_WC_ROOT" scenario yq="$K3DM_WC_ROOT/bin/yq"
  run "$WC_BIN" install --ca-file "$HOME/ca.pub"; [ "$status" = 0 ]
  printf 'passwordauthentication no\nkbdinteractiveauthentication no\n' > "$root/system-config"
  mkdir -p "$root/route" "$HOME/.cloudflared"
  printf '{"ingress":[{"service":"tcp://127.0.0.1:22"}]}\n' > "$root/route/bad"
  printf '{"ingress":[{"service":"http_status:404"}]}\n' > "$HOME/.cloudflared/config.yml"
  for scenario in missing-config bad-route token ambiguous default-managed absent-yq unreadable; do
    local level=WARN
    : > "$root/processes"
    case "$scenario" in
      missing-config) echo '/usr/bin/cloudflared --config=/missing' > "$root/processes"; level=FAIL ;;
      bad-route) echo '/usr/bin/cloudflared --config /route/bad' > "$root/processes"; level=FAIL ;;
      token) echo '/usr/bin/cloudflared --token hidden' > "$root/processes" ;;
      ambiguous) echo '/usr/bin/cloudflared --config /path with spaces' > "$root/processes" ;;
      default-managed) echo '/usr/bin/cloudflared tunnel run' > "$root/processes" ;;
      absent-yq) mv "$yq" "$yq.off" ;;
      unreadable) chmod 000 "$HOME/.cloudflared/config.yml"; level=FAIL ;;
    esac
    run "$WC_BIN" check
    grep -q "^$level C7 " <<< "$output"
    if [[ "$level" = FAIL ]]; then [ "$status" = 1 ]; else [ "$status" = 0 ]; fi
    run "$WC_BIN" check --strict
    [ "$status" = 1 ]; grep -q '^FAIL C7 ' <<< "$output"
    if [[ "$scenario" = absent-yq ]]; then mv "$yq.off" "$yq"; fi
    chmod 0644 "$HOME/.cloudflared/config.yml"
  done
}

@test "[M2] [N3] [N5] source, fingerprint, zdotdir and ancestor refusals avoid installation" {
  wc_fixture
  local root="$K3DM_WC_ROOT" dir="$K3DM_WC_ROOT/etc/k3dm-web-console" file
  for file in scripts/lib/system.sh scripts/lib/agent_rigor.sh; do
    echo "$file" > "$root/changed-source"; run "$WC_BIN" install; [ "$status" = 9 ]
  done
  rm "$root/changed-source"
  touch "$root/fail.second-fingerprint"; run "$WC_BIN" install --ca-file "$HOME/ca.pub"; [ "$status" = 2 ]
  rm "$root/fail.second-fingerprint"
  printf 'ssh-dss QUFB invalid\n' > "$HOME/unsupported"
  run "$WC_BIN" install --ca-file "$HOME/unsupported"; [ "$status" = 2 ]
  mkdir -p "$dir/zdotdir"; touch "$dir/zdotdir/file"
  run "$WC_BIN" install; [ "$status" = 8 ]; [[ "$output" = *'not empty'* ]]
  rm "$dir/zdotdir/file"
  mv "$root/Library" "$root/other"; ln -s other "$root/Library"
  run "$WC_BIN" install; [ "$status" = 8 ]
  [ ! -e "$root/var/db/k3dm-web-console.lock" ]
}

@test "[M5] uninstall enforces its terminal and part C guard and purges every revoked record" {
  wc_fixture
  local root="$K3DM_WC_ROOT" dir="$K3DM_WC_ROOT/etc/k3dm-web-console"
  run "$WC_BIN" install --ca-file "$HOME/ca.pub"; [ "$status" = 0 ]
  run "$WC_BIN" revoke; [ "$status" = 0 ]
  touch "$dir/revoked.consumed.20260101T000000Z.1" "$root/Library/LaunchDaemons/com.k3d-manager.web-console-totp.plist"
  run "$WC_BIN" uninstall --purge; [ "$status" = 6 ]
  rm "$root/Library/LaunchDaemons/com.k3d-manager.web-console-totp.plist"
  run "$WC_BIN" uninstall --purge; [ "$status" = 0 ]
  [ ! -e "$dir" ]; [ ! -e "$root/Library/PrivilegedHelperTools/k3dm-web-console" ]
  [ ! -e "$root/Library/LaunchDaemons/.prev" ]
  # Exercise just the real terminal refusal with a guard against any root call.
  source "$WC_BIN"; wc_library
  _wc_priv() { printf 'unexpected privilege' > "$SCRATCH/priv"; return 99; }
  run _wc_uninstall </dev/null
  [ "$status" = 10 ]; [ ! -e "$SCRATCH/priv" ]
}

@test "[M2] concurrent reclaimers elect one holder of a stale install lock" {
  wc_fixture
  wc_library; _wc_fixture_gate
  local lock="$K3DM_WC_ROOT/var/db/k3dm-web-console.lock" first second
  mkdir "$lock"
  echo '9999 Thu Nov 19 18:34:54 2026' > "$lock/holder"
  echo 9999 > "$K3DM_WC_ROOT/crashed"
  _wc_lock_take > "$SCRATCH/first" 2>&1 & first=$!
  _wc_lock_take > "$SCRATCH/second" 2>&1 & second=$!
  local a=0 b=0
  wait "$first" || a=$?
  wait "$second" || b=$?
  case "$a/$b" in 0/7|7/0) ;; *) echo "reclaimers returned $a and $b"; return 1 ;; esac
  [ -s "$lock/holder" ]; [ ! -e "$lock.reclaim" ]
  _wc_lock_release
}

@test "[M2] [M6] [N8] recovery clears stale stages before its binding port decision" {
  wc_fixture
  local root="$K3DM_WC_ROOT" conf="$K3DM_WC_ROOT/etc/k3dm-web-console"
  local helper="$K3DM_WC_ROOT/Library/PrivilegedHelperTools/k3dm-web-console"
  mkdir -p "$conf/.stage.left" "$helper/.stage.left" "$conf/.prev"
  chmod 700 "$conf/.prev"
  echo 'console_port=42723' > "$conf/.prev/totp.conf"
  printf '1 moved /etc/k3dm-web-console/totp.conf /etc/k3dm-web-console/.prev/totp.conf\n' > "$root/var/db/k3dm-web-console.txn"
  run "$WC_BIN" install
  [ "$status" = 2 ]; [[ "$output" = *'rolled back an interrupted install'*'part C is installed on port 42723'* ]]
  [ ! -e "$conf/.stage.left" ]; [ ! -e "$helper/.stage.left" ]
  [ ! -e "$root/var/db/k3dm-web-console.txn" ]
  rm "$conf/totp.conf"
  : > "$root/var/db/k3dm-web-console.txn"; touch "$root/fail.busy-after-recovery"
  run "$WC_BIN" install
  [ "$status" = 2 ]; [[ "$output" = *'rolled back an interrupted install'*'held by another process'* ]]
  run grep 'priv .*bootstrap' "$root/calls.log"; [ "$status" = 1 ]
}

@test "[M2] [M12] [N13] failed recovery keeps the explicit revoke and never bootstraps during revoked rollback" {
  wc_fixture
  local root="$K3DM_WC_ROOT" dir="$K3DM_WC_ROOT/etc/k3dm-web-console"
  local journal="$root/var/db/k3dm-web-console.txn" id
  run "$WC_BIN" install --ca-file "$HOME/ca.pub"; [ "$status" = 0 ]
  run "$WC_BIN" revoke </dev/null; [ "$status" = 0 ]
  read -r id < "$dir/revoked"
  echo 'ssh-ed25519 QkJC replacement' > "$HOME/ca.pub"
  touch "$root/fail.bootstrap" "$root/fail.restore"
  run "$WC_BIN" install --after-revoke --ca-file "$HOME/ca.pub"
  [ "$status" = 5 ]; [[ "$output" = *'restore incomplete; journal kept'* ]]
  [ "$(cat "$dir/revoked")" = "$id" ]
  [ -s "$journal" ]; [ ! -e "$root/job" ]
  source "$WC_BIN"; wc_library; _wc_fixture_gate
  local plist_path="$_WC_LAUNCHD_DIR/${_WC_LABEL}.plist" consumed='' new_log=0
  [ ! -e "$root$plist_path" ]
  rm "$root/fail.restore"; : > "$root/calls.log"
  run _wc_load_previous
  [ "$status" = 5 ]; [[ "$output" = *'previous generation restored'* ]]
  [ ! -e "$journal" ]; [ ! -e "$root$plist_path" ]; [ ! -e "$root/job" ]
  run grep 'priv .*launchctl bootstrap' "$root/calls.log"; [ "$status" = 1 ]
}

@test "[bug-2026-11-20] [E1] tty opens ticket under sudoers with NOPASSWD /usr/bin/true" {
  local child="$SCRATCH/check-ticket-nopasswd"
  cat > "$child" <<'SH'
#!/bin/bash
source "$1/scripts/lib/system.sh"
source "$1/scripts/lib/web_console_common.sh"
sudo() {
  printf '%s\n' "$*" >> "$WC_TICKET_CALLS"
  if [[ "${1-}" = /usr/bin/true || "${2-}" = /usr/bin/true ]]; then
    return 0
  fi
  if [[ "${1-}" = -n ]]; then
    if [[ ! -f "$WC_TICKET_FILE" ]]; then
      printf 'sudo: a password is required\n' >&2
      return 1
    fi
    if [[ "${2-}" = /usr/bin/id && "${3-}" = -u ]]; then
      printf '%s\n' "${WC_STUB_UID:-0}"
      return 0
    fi
    return 0
  fi
  if [[ -n "${WC_STUB_DENY-}" ]]; then
    return 1
  fi
  touch "$WC_TICKET_FILE"
  return 0
}
[ "$(type -t sudo)" = function ] || exit 98
[ ! -e "$WC_TICKET_FILE" ] || exit 97
_wc_priv_open
rc=$?
printf 'caller-alive=%s\n' "$rc"
exit "$rc"
SH
  chmod +x "$child"
  export WC_TICKET_FILE="$SCRATCH/ticket"
  export WC_TICKET_CALLS="$SCRATCH/ticket-calls"

  # Case A: no ticket -> opens ticket and confirms it via sudo -n
  rm -f "$WC_TICKET_FILE" "$WC_TICKET_CALLS"
  run wc_pty_run "$child" "$REPO"
  [ "$status" = 0 ]
  [[ "$output" = *'caller-alive=0'* ]]
  [ -f "$WC_TICKET_FILE" ]
  grep -Fxq -- "-n /usr/bin/id -u" "$WC_TICKET_CALLS"
  awk '/^-n \/usr\/bin\/id -u$/ { if (found_non_n) { exit 0 } else { exit 1 } } !/^-n/ && !/\/usr\/bin\/true/ { found_non_n=1 } END { if (!NR) exit 1 }' "$WC_TICKET_CALLS"

  # Case B: positive control WC_STUB_DENY=1 -> rc 10
  rm -f "$WC_TICKET_FILE" "$WC_TICKET_CALLS"
  export WC_STUB_DENY=1
  run wc_pty_run "$child" "$REPO"
  [ "$status" = 10 ]
  [[ "$output" = *'caller-alive=10'* ]]
  unset WC_STUB_DENY

  # Case C: WC_STUB_UID=501 -> rc 10 (uid must be exactly 0)
  rm -f "$WC_TICKET_FILE" "$WC_TICKET_CALLS"
  export WC_STUB_UID=501
  run wc_pty_run "$child" "$REPO"
  [ "$status" = 10 ]
  [[ "$output" = *'caller-alive=10'* ]]
  unset WC_STUB_UID
}

@test "[bug-2026-11-20] [E2] headless revoke stops without ticket under NOPASSWD /usr/bin/true" {
  local WC_BIN="$REPO/bin/k3dm-web-console-sshd"
  source "$REPO/scripts/lib/system.sh"
  source "$WC_BIN"
  wc_library
  local sentinel_log="$SCRATCH/sentinel.log"
  export WC_TICKET_FILE="$SCRATCH/ticket"
  export WC_TICKET_CALLS="$SCRATCH/ticket-calls"

  sudo() {
    printf '%s\n' "$*" >> "$WC_TICKET_CALLS"
    if [[ "${1-}" = /usr/bin/true || "${2-}" = /usr/bin/true ]]; then
      return 0
    fi
    if [[ "${1-}" = -n ]]; then
      if [[ ! -f "$WC_TICKET_FILE" ]]; then
        printf 'sudo: a password is required\n' >&2
        return 1
      fi
      if [[ "${2-}" = /usr/bin/id && "${3-}" = -u ]]; then
        printf '%s\n' "${WC_STUB_UID:-0}"
        return 0
      fi
      return 0
    fi
    if [[ -n "${WC_STUB_DENY-}" ]]; then
      return 1
    fi
    touch "$WC_TICKET_FILE"
    return 0
  }

  [ "$(type -t sudo)" = function ]
  [ ! -e "$WC_TICKET_FILE" ]

  _wc_port_lookup() { printf '%s\n' port_lookup >> "$sentinel_log"; echo "42722 test"; }
  _wc_revoke_mark() { printf '%s\n' revoke_mark >> "$sentinel_log"; return 0; }
  _wc_stop() { printf '%s\n' stop >> "$sentinel_log"; return 0; }

  # Case 1: no ticket file -> exits 10 with message and no sentinels logged
  rm -f "$sentinel_log" "$WC_TICKET_FILE" "$WC_TICKET_CALLS"
  run _wc_revoke </dev/null
  [ "$status" = 10 ]
  [[ "$output" = *"revoke needs an open sudo ticket or a terminal"* ]]
  [ ! -s "$sentinel_log" ]

  # Case 2: positive control with ticket file -> check passes and reaches sentinels
  touch "$WC_TICKET_FILE"
  run _wc_revoke </dev/null
  [ "$status" = 0 ]
  grep -Fxq port_lookup "$sentinel_log"
}
