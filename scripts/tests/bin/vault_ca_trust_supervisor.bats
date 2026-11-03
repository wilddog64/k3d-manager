#!/usr/bin/env bats

setup() {
  mkdir -p "${BATS_TEST_TMPDIR}/home" "${BATS_TEST_TMPDIR}/fixture"
  export HOME="${BATS_TEST_TMPDIR}/home"
  export CA_TEST_DIR="${BATS_TEST_TMPDIR}/fixture"
  export CA_SUPERVISOR_FILE="${BATS_TEST_DIRNAME}/../../../bin/k3dm-vault-ca-trust-supervisor"
  export CA_BOUNDED_CLIENT_FILE="${BATS_TEST_DIRNAME}/../../../bin/k3dm-bounded-sudo"
}

@test "supervisor accepts a safe caller-owned certificate and rejects unsafe paths" {
  run python3 - <<'PY'
import importlib.machinery, importlib.util, os, pathlib, sys
sys.dont_write_bytecode = True
root = pathlib.Path(os.path.realpath(os.environ['CA_TEST_DIR']))
assert root.is_dir() and pathlib.Path(os.environ['HOME']).is_dir()
loader = importlib.machinery.SourceFileLoader('ca_supervisor', os.environ['CA_SUPERVISOR_FILE'])
supervisor = importlib.util.module_from_spec(importlib.util.spec_from_loader(loader.name, loader))
loader.exec_module(supervisor)
cert = root / 'ca.crt'
cert.write_bytes(b'controlled certificate')
cert.chmod(0o600)
assert supervisor._open_certificate(str(cert), os.getuid()) == b'controlled certificate'
link = root / 'link.crt'
link.symlink_to(cert)
directory_link = root / 'linkdir'
directory_link.symlink_to(root, target_is_directory=True)
for value in (str(link), str(directory_link / 'ca.crt'), str(root / '..' / 'fixture' / 'ca.crt'), '-bad', str(root / '-bad'), str(root / 'new\nline'), str(root)):
    try:
        supervisor._open_certificate(value, os.getuid())
    except (ValueError, OSError):
        pass
    else:
        raise AssertionError('accepted unsafe path ' + value)
cert.chmod(0o622)
try:
    supervisor._open_certificate(str(cert), os.getuid())
except ValueError:
    pass
else:
    raise AssertionError('accepted group-writable certificate')
cert.chmod(0o600)
try:
    supervisor._open_certificate(str(cert), os.getuid() + 1)
except ValueError:
    pass
else:
    raise AssertionError('accepted a certificate owned by another user')
PY
  printf '%s\n' "${output}"
  [ "${status}" -eq 0 ]
}

@test "supervisor installation requires root-owned fixed executable paths" {
  run python3 - <<'PY'
import importlib.machinery, importlib.util, os, pathlib, stat, sys, types
sys.dont_write_bytecode = True
source = pathlib.Path(os.environ['CA_SUPERVISOR_FILE'])
assert source.is_file() and source.name == 'k3dm-vault-ca-trust-supervisor'
loader = importlib.machinery.SourceFileLoader('ca_supervisor', str(source))
module = importlib.util.module_from_spec(importlib.util.spec_from_loader(loader.name, loader))
loader.exec_module(module)
expected = '/Library/PrivilegedHelperTools/k3dm-vault-ca-trust-supervisor'
directories = ('/', '/usr', '/usr/bin', '/Library', '/Library/PrivilegedHelperTools')
executables = ('/usr/bin/python3', module.SECURITY)
records = {path: types.SimpleNamespace(st_mode=(stat.S_IFDIR | 0o755), st_uid=0) for path in directories}
records.update({path: types.SimpleNamespace(st_mode=(stat.S_IFREG | 0o755), st_uid=0) for path in executables})
records[expected] = types.SimpleNamespace(st_mode=(stat.S_IFREG | 0o755), st_uid=0)
module.__file__ = expected
module.os.path.realpath = lambda _path: expected
module.os.stat = lambda path, follow_symlinks=False: records[path]
module._validate_installation()
records['/Library/PrivilegedHelperTools'] = types.SimpleNamespace(st_mode=(stat.S_IFDIR | 0o777), st_uid=0)
try:
    module._validate_installation()
except ValueError:
    pass
else:
    raise AssertionError('accepted a writable trusted parent directory')
records['/Library/PrivilegedHelperTools'] = types.SimpleNamespace(st_mode=(stat.S_IFDIR | 0o755), st_uid=0)
records[expected] = types.SimpleNamespace(st_mode=(stat.S_IFREG | 0o777), st_uid=0)
try:
    module._validate_installation()
except ValueError:
    pass
else:
    raise AssertionError('accepted a group/world writable helper')
PY
  [ "${status}" -eq 0 ]
}

@test "supervisor entry rejects extra arguments and dispatches only a scratch certificate" {
  run python3 - <<'PY'
import importlib.machinery, importlib.util, os, pathlib, stat, tempfile, time
import sys
sys.dont_write_bytecode = True
root = pathlib.Path(os.path.realpath(os.environ['CA_TEST_DIR']))
assert root.is_dir() and os.getuid() > 0
loader = importlib.machinery.SourceFileLoader('ca_supervisor', os.environ['CA_SUPERVISOR_FILE'])
supervisor = importlib.util.module_from_spec(importlib.util.spec_from_loader(loader.name, loader))
loader.exec_module(supervisor)
cert = root / 'ca.crt'
cert.write_bytes(b'controlled certificate')
cert.chmod(0o600)
actual_tempdir = tempfile.TemporaryDirectory
def scratch_tempdir(*args, **kwargs):
    assert kwargs['dir'] == '/private/tmp'
    kwargs['dir'] = str(root)
    return actual_tempdir(*args, **kwargs)
supervisor.tempfile.TemporaryDirectory = scratch_tempdir
supervisor.os.geteuid = lambda: 0
supervisor._validate_installation = lambda: None
os.environ['SUDO_UID'] = str(os.getuid())
calls = []
def fake_security(path, **kwargs):
    assert kwargs['absolute_deadline'] > time.monotonic()
    copy = pathlib.Path(path)
    assert copy.parent.parent == root and copy.name == 'ca.crt'
    assert copy.read_bytes() == b'controlled certificate'
    assert stat.S_IMODE(copy.stat().st_mode) == 0o600
    calls.append(path)
    return 0
supervisor._run_security = fake_security
deadline = str(time.monotonic() + 10)
assert supervisor.main(['supervisor', str(cert), deadline]) == 0 and len(calls) == 1
assert supervisor.main(['supervisor', str(cert), deadline, '--extra']) == 2 and len(calls) == 1
assert supervisor.main(['supervisor']) == 2 and len(calls) == 1
os.environ['SUDO_UID'] = '0'
assert supervisor.main(['supervisor', str(cert), deadline]) == 2 and len(calls) == 1
PY
  [ "${status}" -eq 0 ]
}

@test "supervisor absolute deadline covers preflight and certificate opening" {
  run python3 - <<'PY'
import importlib.machinery, importlib.util, os, pathlib, sys, time
root = pathlib.Path(os.environ['CA_TEST_DIR']).resolve()
source = pathlib.Path(os.environ['CA_SUPERVISOR_FILE']).resolve()
assert root.is_dir() and source.name == 'k3dm-vault-ca-trust-supervisor'
loader = importlib.machinery.SourceFileLoader('ca_deadline', str(source))
module = importlib.util.module_from_spec(importlib.util.spec_from_loader(loader.name, loader))
loader.exec_module(module)
module.os.geteuid = lambda: 0
module._validate_installation = lambda: None
os.environ['SUDO_UID'] = str(os.getuid())
calls = []
module._open_certificate = lambda *_args: (time.sleep(.3), b'fixture')[1]
module._run_security = lambda *_args, **_kwargs: calls.append('security') or 0
started = time.monotonic()
rc = module.main(['supervisor', str(root / 'unused.crt'), str(started + .05)])
elapsed = time.monotonic() - started
print(f'rc={rc} elapsed={elapsed:.3f}s security_calls={len(calls)}')
assert rc == 124 and elapsed < .5 and calls == []
PY
  [ "${status}" -eq 0 ]
}

@test "expired supervisor deadline never spawns the Keychain command" {
  run python3 - <<'PY'
import importlib.machinery, importlib.util, os, pathlib, sys, time
root = pathlib.Path(os.environ['CA_TEST_DIR']).resolve()
source = pathlib.Path(os.environ['CA_SUPERVISOR_FILE']).resolve()
assert root.is_dir() and source.name == 'k3dm-vault-ca-trust-supervisor'
loader = importlib.machinery.SourceFileLoader('ca_expired', str(source))
module = importlib.util.module_from_spec(importlib.util.spec_from_loader(loader.name, loader))
loader.exec_module(module)
spawned = []
module.subprocess.Popen = lambda *_args, **_kwargs: spawned.append(True)
rc = module._run_security(str(root / 'unused.crt'), absolute_deadline=time.monotonic() - 1)
assert rc == 124 and not spawned, (rc, spawned)
PY
  [ "${status}" -eq 0 ]
}

@test "supervisor ignores a deadline alarm during TERM grace and still kills the group" {
  local stub="${CA_TEST_DIR}/alarm-stub" marker="${CA_TEST_DIR}/alarm-pid"
  cat > "${stub}" <<'PY'
#!/usr/bin/python3
import os, signal, sys, time
signal.signal(signal.SIGTERM, signal.SIG_IGN)
open(os.environ['CA_TEST_MARKER'], 'w').write(str(os.getpid()))
while True:
    time.sleep(1)
PY
  chmod 755 "${stub}"
  run env CA_TEST_MARKER="${marker}" python3 - "${stub}" <<'PY'
import importlib.machinery, importlib.util, os, pathlib, signal, sys, time
root = pathlib.Path(os.environ['CA_TEST_DIR']).resolve()
stub = pathlib.Path(sys.argv[1]).resolve()
assert root.is_dir() and stub.parent == root and not pathlib.Path(os.environ['CA_TEST_MARKER']).exists()
loader = importlib.machinery.SourceFileLoader('ca_alarm_cleanup', os.environ['CA_SUPERVISOR_FILE'])
module = importlib.util.module_from_spec(importlib.util.spec_from_loader(loader.name, loader))
loader.exec_module(module)
module.signal.signal(module.signal.SIGALRM, module._deadline_requested)
sleep = time.sleep
def signal_during_grace(duration):
    if duration == .1:
        module.signal.raise_signal(module.signal.SIGALRM)
    return sleep(duration)
module.time.sleep = signal_during_grace
start = time.monotonic()
try:
    rc = module._run_security(str(root / 'ca.crt'), command=str(stub), deadline=.15,
                              grace=.1, environment=os.environ.copy())
finally:
    module.time.sleep = sleep
print(f'rc={rc}')
assert rc == 124
pid = int(pathlib.Path(os.environ['CA_TEST_MARKER']).read_text())
try:
    os.kill(pid, 0)
except ProcessLookupError:
    pass
else:
    raise AssertionError('process group leader remained after deadline cleanup')
PY
  [ "${status}" -eq 0 ]
}

@test "bounded sudo client caps startup and kills a resistant descendant after leader exit" {
  run python3 - <<'PY'
import importlib.machinery, importlib.util, os, pathlib, signal, subprocess, sys, time
root = pathlib.Path(os.environ['CA_TEST_DIR']).resolve()
source = pathlib.Path(os.environ['CA_BOUNDED_CLIENT_FILE']).resolve()
assert root.is_dir() and source.is_file()
loader = importlib.machinery.SourceFileLoader('bounded_sudo', str(source))
module = importlib.util.module_from_spec(importlib.util.spec_from_loader(loader.name, loader))
loader.exec_module(module)
script = root / 'leader.py'
marker = root / 'late-effect'
script.write_text(
    'import os,signal,subprocess,sys,time\n'
    'child=subprocess.Popen([sys.executable,"-c",'
    '"import signal,time,pathlib; signal.signal(signal.SIGTERM,signal.SIG_IGN); '
    'time.sleep(.7); pathlib.Path(sys.argv[1]).write_text(\\"late\\")",sys.argv[1]])\n'
    'signal.signal(signal.SIGTERM,lambda *_:sys.exit(0))\n'
    'while True: time.sleep(1)\n')
process = subprocess.Popen([sys.executable, str(script), str(marker)], start_new_session=True)
time.sleep(.05)
module.GRACE = .1
module._terminate_group(process)
assert process.poll() is not None
time.sleep(.8)
assert not marker.exists(), 'TERM-resistant child performed a delayed effect'
PY
  [ "${status}" -eq 0 ]
}

@test "bounded sudo client enforces its deadline across sudo policy startup" {
  run python3 - <<'PY'
import importlib.machinery, importlib.util, os, pathlib, sys, time
root = pathlib.Path(os.environ['CA_TEST_DIR']).resolve()
source = pathlib.Path(os.environ['CA_BOUNDED_CLIENT_FILE']).resolve()
assert root.is_dir() and source.is_file()
loader = importlib.machinery.SourceFileLoader('bounded_sudo_timeout', str(source))
module = importlib.util.module_from_spec(importlib.util.spec_from_loader(loader.name, loader))
loader.exec_module(module)
module.LIMIT = .1
slow = root / 'slow-system.sh'
slow.write_text('_run_command() { /bin/sleep 30; }\n')
started = time.monotonic()
rc = module.main([str(slow), module.ROOT_HELPER, str(root / 'ca.crt')])
elapsed = time.monotonic() - started
print(f'rc={rc} elapsed={elapsed:.3f}s')
assert rc == 124 and elapsed < 1.5
fast = root / 'fast-system.sh'
fast.write_text('_run_command() { return 0; }\n')
assert module.main([str(fast), module.ROOT_HELPER, str(root / 'ca.crt')]) == 0
PY
  [ "${status}" -eq 0 ]
}

@test "supervisor preserves quick security success and failure status" {
  local stub="${CA_TEST_DIR}/security-stub"
  cat > "${stub}" <<'SH'
#!/bin/bash
[[ "$1 $2 $3 $4 $5 $6" == 'add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain' ]] || exit 31
[ "$7" = "$CA_TEST_DIR/ca.crt" ] || exit 32
printf '%s\n' "$CA_TEST_RC" >> "$CA_TEST_DIR/calls"
exit "$CA_TEST_RC"
SH
  chmod 755 "${stub}"
  : > "${CA_TEST_DIR}/ca.crt"
  run python3 - "${stub}" <<'PY'
import importlib.machinery, importlib.util, os, pathlib, sys
sys.dont_write_bytecode = True
root = pathlib.Path(os.environ['CA_TEST_DIR'])
stub = pathlib.Path(sys.argv[1])
assert stub.parent == root and stub.is_file() and not (root / 'calls').exists()
loader = importlib.machinery.SourceFileLoader('ca_supervisor', os.environ['CA_SUPERVISOR_FILE'])
supervisor = importlib.util.module_from_spec(importlib.util.spec_from_loader(loader.name, loader))
loader.exec_module(supervisor)
for rc in (0, 7):
    os.environ['CA_TEST_RC'] = str(rc)
    assert supervisor._run_security(str(root / 'ca.crt'), command=str(stub), deadline=2, environment=os.environ.copy()) == rc
assert (root / 'calls').read_text().splitlines() == ['0', '7']
PY
  [ "${status}" -eq 0 ]
}

@test "supervisor bounds a TERM-resistant controlled security process group" {
  local stub="${CA_TEST_DIR}/security-stub" marker="${CA_TEST_DIR}/pids"
  cat > "${stub}" <<'PY'
#!/usr/bin/python3
import os, signal, subprocess, sys, time
assert sys.argv[1:7] == ['add-trusted-cert', '-d', '-r', 'trustRoot', '-k', '/Library/Keychains/System.keychain']
assert sys.argv[7] == os.environ['CA_TEST_DIR'] + '/ca.crt'
signal.signal(signal.SIGTERM, signal.SIG_IGN)
child = subprocess.Popen([sys.executable, '-c', 'import signal,time; signal.signal(signal.SIGTERM, signal.SIG_IGN); time.sleep(60)'])
with open(os.environ['CA_TEST_MARKER'], 'w') as f:
    f.write(f'{os.getpid()} {child.pid}')
while True:
    time.sleep(1)
PY
  chmod 755 "${stub}"
  : > "${CA_TEST_DIR}/ca.crt"
  run env CA_TEST_MARKER="${marker}" python3 - "${stub}" <<'PY'
import importlib.machinery, importlib.util, os, pathlib, signal, sys, threading, time
sys.dont_write_bytecode = True
root = pathlib.Path(os.environ['CA_TEST_DIR'])
stub = pathlib.Path(sys.argv[1])
assert stub.parent == root and stub.is_file() and not pathlib.Path(os.environ['CA_TEST_MARKER']).exists()
loader = importlib.machinery.SourceFileLoader('ca_supervisor', os.environ['CA_SUPERVISOR_FILE'])
supervisor = importlib.util.module_from_spec(importlib.util.spec_from_loader(loader.name, loader))
loader.exec_module(supervisor)
observed = []
def observe():
    until = time.monotonic() + .8
    marker = pathlib.Path(os.environ['CA_TEST_MARKER'])
    while not marker.exists() and time.monotonic() < until:
        time.sleep(.01)
    if marker.exists():
        pids = [int(x) for x in marker.read_text().split()]
        try:
            for pid in pids:
                os.kill(pid, 0)
        except ProcessLookupError:
            return
        observed.extend(pids)
observer = threading.Thread(target=observe)
observer.start()
start = time.monotonic()
try:
    rc = supervisor._run_security(str(root / 'ca.crt'), command=str(stub), deadline=1, grace=.5, environment=os.environ.copy())
    elapsed = time.monotonic() - start
    observer.join()
    print(f'rc={rc} elapsed={elapsed:.3f}s controlled={len(observed)}')
    assert rc == 124 and .8 <= elapsed < 3 and len(observed) == 2
    until = time.monotonic() + 1
    for pid in observed:
        while True:
            try:
                os.kill(pid, 0)
            except ProcessLookupError:
                break
            assert time.monotonic() < until, f'process {pid} remains'
            time.sleep(.02)
finally:
    for pid in observed:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
PY
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"rc=124"* ]]
}

@test "supervisor interruption terminates its controlled security process group" {
  local stub="${CA_TEST_DIR}/security-stub" worker="${CA_TEST_DIR}/worker.py"
  cat > "${stub}" <<'PY'
#!/usr/bin/python3
import os, signal, subprocess, sys, time
assert sys.argv[1:7] == ['add-trusted-cert', '-d', '-r', 'trustRoot', '-k', '/Library/Keychains/System.keychain']
assert sys.argv[7] == os.environ['CA_TEST_DIR'] + '/ca.crt'
signal.signal(signal.SIGTERM, signal.SIG_IGN)
child = subprocess.Popen([sys.executable, '-c', 'import signal,time; signal.signal(signal.SIGTERM, signal.SIG_IGN); time.sleep(60)'])
with open(os.environ['CA_TEST_MARKER'], 'w') as f:
    f.write(f'{os.getpid()} {child.pid}')
while True:
    time.sleep(1)
PY
  cat > "${worker}" <<'PY'
import importlib.machinery, importlib.util, os, sys
sys.dont_write_bytecode = True
loader = importlib.machinery.SourceFileLoader('ca_supervisor', os.environ['CA_SUPERVISOR_FILE'])
module = importlib.util.module_from_spec(importlib.util.spec_from_loader(loader.name, loader))
loader.exec_module(module)
sys.exit(module._run_security(os.environ['CA_TEST_DIR'] + '/ca.crt', command=sys.argv[1],
                              deadline=15, grace=.5, environment=os.environ.copy()))
PY
  chmod 755 "${stub}"
  : > "${CA_TEST_DIR}/ca.crt"
  run env CA_TEST_MARKER="${CA_TEST_DIR}/pids" python3 - "${worker}" "${stub}" <<'PY'
import os, pathlib, signal, subprocess, sys, time
root = pathlib.Path(os.environ['CA_TEST_DIR'])
worker, stub = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
marker = pathlib.Path(os.environ['CA_TEST_MARKER'])
assert worker.parent == root and stub.parent == root and not marker.exists()
proc = subprocess.Popen([sys.executable, str(worker), str(stub)], stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
pids = []
try:
    until = time.monotonic() + 4
    while not marker.exists() or not marker.read_text().strip():
        assert time.monotonic() < until, 'controlled process did not start'
        time.sleep(.02)
    pids = [int(value) for value in marker.read_text().split()]
    assert len(pids) == 2
    for pid in pids:
        os.kill(pid, 0)
    proc.send_signal(signal.SIGTERM)
    output, _ = proc.communicate(timeout=4)
    print(output.decode(), end='')
    assert proc.returncode == 128 + signal.SIGTERM
    until = time.monotonic() + 1
    for pid in pids:
        while True:
            try:
                os.kill(pid, 0)
            except ProcessLookupError:
                break
            assert time.monotonic() < until, f'controlled process {pid} remains'
            time.sleep(.02)
finally:
    for pid in pids:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    if proc.poll() is None:
        proc.kill()
        proc.wait()
PY
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Vault CA trust interrupted"* ]]
}

@test "supervisor cleans up when termination arrives as signals are unmasked" {
  local stub="${CA_TEST_DIR}/security-stub" marker="${CA_TEST_DIR}/pid"
  cat > "${stub}" <<'PY'
#!/usr/bin/python3
import os, signal, time
signal.signal(signal.SIGTERM, signal.SIG_IGN)
with open(os.environ['CA_TEST_MARKER'], 'w') as stream:
    stream.write(str(os.getpid()))
while True:
    time.sleep(1)
PY
  chmod 755 "${stub}"
  : > "${CA_TEST_DIR}/ca.crt"
  run env CA_TEST_MARKER="${marker}" python3 - "${stub}" <<'PY'
import importlib.machinery, importlib.util, os, pathlib, signal, sys, time
sys.dont_write_bytecode = True
root = pathlib.Path(os.environ['CA_TEST_DIR'])
stub = pathlib.Path(sys.argv[1])
assert root.is_dir() and stub.parent == root and not pathlib.Path(os.environ['CA_TEST_MARKER']).exists()
loader = importlib.machinery.SourceFileLoader('ca_supervisor', os.environ['CA_SUPERVISOR_FILE'])
module = importlib.util.module_from_spec(importlib.util.spec_from_loader(loader.name, loader))
loader.exec_module(module)
real_popen = module.subprocess.Popen
real_mask = module.signal.pthread_sigmask
parent_pid = os.getpid()
launched = []
injected = []
def controlled_popen(*args, **kwargs):
    process = real_popen(*args, **kwargs)
    until = time.monotonic() + 2
    marker = pathlib.Path(os.environ['CA_TEST_MARKER'])
    while not marker.exists() and time.monotonic() < until:
        time.sleep(.01)
    assert marker.exists(), 'controlled subprocess did not start'
    launched.append(int(marker.read_text()))
    return process
def terminate_on_unmask(how, mask):
    previous = real_mask(how, mask)
    if os.getpid() == parent_pid and how == module.signal.SIG_SETMASK and not injected:
        injected.append(True)
        module._stop_requested(signal.SIGTERM, None)
    return previous
module.subprocess.Popen = controlled_popen
module.signal.pthread_sigmask = terminate_on_unmask
pid = None
try:
    rc = module._run_security(str(root / 'ca.crt'), command=str(stub), deadline=5,
                              grace=.2, environment=os.environ.copy())
    assert rc == 128 + signal.SIGTERM, rc
    pid = launched[0]
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        pid = None
    assert pid is None, 'process survived the signal/unmask boundary'
finally:
    if pid is not None:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
PY
  [ "${status}" -eq 0 ]
}
