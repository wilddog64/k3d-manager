#!/usr/bin/env bats

setup() {
  export HOME="${BATS_TEST_TMPDIR}/home"
  export LISTENER_TEST_DIR="${BATS_TEST_TMPDIR}/fixtures"
  export LISTENER_SUPERVISOR_FILE="${BATS_TEST_DIRNAME}/../../../bin/k3dm-browser-listener-supervisor"
  export LISTENER_RELAY_FILE="${BATS_TEST_DIRNAME}/../../../bin/k3dm-browser-listener-relay"
  export _ACG_STATE_DIR="${LISTENER_TEST_DIR}"
  mkdir -p "${HOME}" "${LISTENER_TEST_DIR}"
}

@test "listener supervisor emits only fixed root-owned executables and socket definitions" {
  run python3 - <<'PY'
import importlib.machinery, importlib.util, os, pathlib, pwd, sys
root = pathlib.Path(os.environ['LISTENER_TEST_DIR']).resolve()
source = pathlib.Path(os.environ['LISTENER_SUPERVISOR_FILE']).resolve()
assert root.is_dir() and source.name == 'k3dm-browser-listener-supervisor'
loader = importlib.machinery.SourceFileLoader('listener_supervisor', str(source))
module = importlib.util.module_from_spec(importlib.util.spec_from_loader(loader.name, loader))
loader.exec_module(module)
user = pwd.getpwuid(os.getuid())
cert, key = root / 'ca.crt', root / 'ca.key'
cert.write_text('fixture certificate')
key.write_text('fixture key')
https = module._plist('argocd-https', user, str(cert), str(key))
assert https['UserName'] == user.pw_name
assert https['ProgramArguments'] == ['/usr/bin/python3', '-I', module.RELAY, 'tls', '8080', str(cert), str(key)]
assert https['inetdCompatibility'] == {'Wait': False}
assert https['Sockets']['Listener']['SockNodeName'] == '127.0.0.1'
assert https['Sockets']['Listener']['SockServiceName'] == '443'
http = module._plist('keycloak-http', user)
assert http['ProgramArguments'] == ['/usr/bin/python3', '-I', module.RELAY, 'tcp', '18081']
assert http['Sockets']['Listener']['SockServiceName'] == '80'
front = module._plist('frontend-http', user)
assert front['Sockets']['Listener']['SockNodeName'] == '127.0.0.3'
assert front['ProgramArguments'][-1] == '18082'
alias = module._plist('sandbox-loopback-alias', None)
assert alias['ProgramArguments'] == ['/sbin/ifconfig', 'lo0', 'alias', '127.0.0.3']
assert 'UserName' not in alias
for args in (('argocd-https', user), ('keycloak-http', user, str(cert), str(key))):
    try:
        module._plist(*args)
    except ValueError:
        pass
    else:
        raise AssertionError('accepted invalid listener configuration ' + repr(args))
PY
  if [ "${status}" -ne 0 ]; then
    printf '%s\n' "${output}"
  fi
  [ "${status}" -eq 0 ]
}

@test "Argo CD listener accepts default and safe custom ports and rejects unsafe ports" {
  run python3 - <<'PY'
import importlib.machinery, importlib.util, os, pathlib, types
source = pathlib.Path(os.environ['LISTENER_SUPERVISOR_FILE']).resolve()
assert source.is_file() and source.name == 'k3dm-browser-listener-supervisor'
loader = importlib.machinery.SourceFileLoader('listener_supervisor_ports', str(source))
module = importlib.util.module_from_spec(importlib.util.spec_from_loader(loader.name, loader))
loader.exec_module(module)
user = types.SimpleNamespace(pw_name='fixture-user')
default = module._plist('argocd-https', user, '/scratch/ca.crt', '/scratch/ca.key')
custom = module._plist('argocd-https', user, '/scratch/ca.crt', '/scratch/ca.key', '8443')
low_custom = module._plist('argocd-https', user, '/scratch/ca.crt', '/scratch/ca.key', '80')
assert default['Sockets']['Listener']['SockServiceName'] == '443'
assert custom['Sockets']['Listener']['SockServiceName'] == '8443'
assert low_custom['Sockets']['Listener']['SockServiceName'] == '80'
assert default['Sockets']['Listener']['SockNodeName'] == custom['Sockets']['Listener']['SockNodeName'] == '127.0.0.1'
assert default['ProgramArguments'] == custom['ProgramArguments']
for bad in ('', '0', '65536', '08443', '+8443', '8443;id', '８４４３'):
    try:
        module._plist('argocd-https', user, '/scratch/ca.crt', '/scratch/ca.key', bad)
    except ValueError:
        continue
    raise AssertionError('accepted unsafe custom port ' + repr(bad))
try:
    module._plist('keycloak-http', user, listener_port='8443')
except ValueError:
    pass
else:
    raise AssertionError('accepted a custom Keycloak listener port')
module.__file__ = module.SUPERVISOR
module.os.geteuid = lambda: 0
module._safe_root_path = lambda path: None
module._requesting_user = lambda: user
written = []
module._install_plist = lambda path, payload: written.append((path, payload))
module.subprocess.run = lambda *args, **kwargs: types.SimpleNamespace(returncode=0)
assert module.main([module.SUPERVISOR, 'write', 'argocd-https', '/scratch/ca.crt', '/scratch/ca.key', '9443']) == 0
assert written[-1][1]['Sockets']['Listener']['SockServiceName'] == '9443'
written_count = len(written)
assert module.main([module.SUPERVISOR, 'write', 'argocd-https', '/scratch/ca.crt', '/scratch/ca.key', '9443;id']) == 1
assert len(written) == written_count
PY
  [ "${status}" -eq 0 ]
}

@test "loopback alias setup is synchronous, verifies readiness, and fails closed" {
  run python3 - <<'PY'
import importlib.machinery, importlib.util, os, pathlib, pwd, types

root = pathlib.Path(os.environ['LISTENER_TEST_DIR']).resolve()
source = pathlib.Path(os.environ['LISTENER_SUPERVISOR_FILE']).resolve()
assert root.is_dir() and source.is_file()
loader = importlib.machinery.SourceFileLoader('listener_supervisor_alias', str(source))
module = importlib.util.module_from_spec(importlib.util.spec_from_loader(loader.name, loader))
loader.exec_module(module)
module.ROOT = str(root / 'LaunchDaemons')
module.IFCONFIG = '/sbin/ifconfig'
module.LAUNCHCTL = '/bin/launchctl'
module._safe_root_path = lambda _path: None
module._requesting_user = lambda: pwd.getpwuid(os.getuid())
events = []
present = set()

def successful_command(args, **kwargs):
    args = list(args)
    if args == ['/sbin/ifconfig', 'lo0']:
        assert kwargs.get('timeout') == 5
        events.append(('probe', tuple(sorted(present))))
        output = ''.join(f'\tinet {address} netmask 0xff000000\n' for address in sorted(present))
        return types.SimpleNamespace(returncode=0, stdout=output)
    if args in (['/sbin/ifconfig', 'lo0', 'alias', '127.0.0.3'],
                ['/sbin/ifconfig', 'lo0', 'alias', '127.0.0.2']):
        assert kwargs.get('timeout') == 5
        events.append(('alias', args[-1]))
        present.add(args[-1])
        return types.SimpleNamespace(returncode=0, stdout='')
    if args[1] == 'bootout':
        events.append(('bootout', args[-1]))
        return types.SimpleNamespace(returncode=0, stdout='')
    if args[1] == 'bootstrap':
        events.append(('bootstrap', args[-1]))
        return types.SimpleNamespace(returncode=0, stdout='')
    if args[1] == 'enable':
        events.append(('enable', args[-1]))
        return types.SimpleNamespace(returncode=0, stdout='')
    raise AssertionError(f'unexpected command: {args!r}')

module.subprocess.run = successful_command
module._install_plist = lambda *_args: events.append(('install', None))
module.write_listener('frontend-http')
assert events[0] == ('probe', ()), events
assert events[1] == ('alias', '127.0.0.3'), events
assert events[2][0] == 'probe' and '127.0.0.3' in events[2][1], events
assert events.index(('install', None)) < events.index(('bootstrap', str(root / 'LaunchDaemons' / 'com.k3d-manager.sandbox.frontend-browser-http.plist'))), events
assert events.index(('alias', '127.0.0.3')) < events.index(('bootstrap', str(root / 'LaunchDaemons' / 'com.k3d-manager.sandbox.frontend-browser-http.plist'))), events

# Existing aliases are detected without issuing the mutation command.
events.clear()
present.add('127.0.0.2')
module.write_listener('hostinger-frontend-http')
assert not any(event[0] == 'alias' for event in events), events
assert events[0] == ('probe', ('127.0.0.2', '127.0.0.3')), events

# The second fixed address is created by its alias LaunchDaemon.
events.clear()
present.discard('127.0.0.2')
module.write_listener('hostinger-loopback-alias')
assert events[0] == ('probe', ('127.0.0.3',)), events
assert events[1] == ('alias', '127.0.0.2'), events
assert events[2][0] == 'probe' and '127.0.0.2' in events[2][1], events

# An already-configured alias service is idempotent.
events.clear()
module.write_listener('sandbox-loopback-alias')
assert events[0] == ('probe', ('127.0.0.2', '127.0.0.3')), events
assert not any(event[0] == 'alias' for event in events), events

# The alias LaunchDaemon must fail closed if configuring the interface fails.
events.clear()
present.discard('127.0.0.3')

for failing_command in ('command-error', 'not-ready'):
    events.clear()
    present.discard('127.0.0.3')
    def failed_command(args, **kwargs):
        args = list(args)
        if args == ['/sbin/ifconfig', 'lo0']:
            events.append(('probe',))
            if failing_command == 'command-error' or len([e for e in events if e[0] == 'probe']) > 1:
                return types.SimpleNamespace(returncode=0, stdout='')
            return types.SimpleNamespace(returncode=0, stdout='')
        if args == ['/sbin/ifconfig', 'lo0', 'alias', '127.0.0.3']:
            events.append(('alias',))
            if failing_command == 'command-error':
                raise module.subprocess.CalledProcessError(1, args)
            return types.SimpleNamespace(returncode=0, stdout='')
        raise AssertionError(f'launchd must not run after alias failure: {args!r}')
    module.subprocess.run = failed_command
    try:
        module.write_listener('frontend-http')
    except (OSError, ValueError, module.subprocess.SubprocessError):
        pass
    else:
        raise AssertionError(f'{failing_command} did not fail closed')
    assert not any(event[0] in ('install', 'bootstrap', 'enable', 'bootout') for event in events), events
PY
  if [ "${status}" -ne 0 ]; then
    printf '%s\n' "${output}"
  fi
  [ "${status}" -eq 0 ]
}

@test "listener relay transfers both directions over a controlled socket pair" {
  run python3 - <<'PY'
import importlib.machinery, importlib.util, os, pathlib, socket, sys, threading
root = pathlib.Path(os.environ['LISTENER_TEST_DIR']).resolve()
source = pathlib.Path(os.environ['LISTENER_RELAY_FILE']).resolve()
assert root.is_dir() and source.name == 'k3dm-browser-listener-relay'
loader = importlib.machinery.SourceFileLoader('listener_relay', str(source))
module = importlib.util.module_from_spec(importlib.util.spec_from_loader(loader.name, loader))
loader.exec_module(module)
client, relay_client = socket.socketpair()
relay_backend, backend = socket.socketpair()
module.socket.create_connection = lambda address, timeout=None: relay_backend
errors = []
def run_relay():
    try:
        module._relay(relay_client, 18081)
    except Exception as exc:
        errors.append(exc)
thread = threading.Thread(target=run_relay)
thread.start()
client.sendall(b'request from browser')
assert backend.recv(128) == b'request from browser'
backend.sendall(b'response from service')
backend.shutdown(socket.SHUT_WR)
client.shutdown(socket.SHUT_WR)
assert client.recv(128) == b'response from service'
assert client.recv(128) == b''
thread.join(timeout=2)
assert not thread.is_alive() and not errors, errors
client.close()
backend.close()
PY
  [ "${status}" -eq 0 ]
}

@test "TLS listener relays a verified self-signed fixture handshake and duplex data" {
  local cert="${LISTENER_TEST_DIR}/localhost.crt"
  local key="${LISTENER_TEST_DIR}/localhost.key"
  openssl req -x509 -newkey rsa:2048 -nodes -keyout "${key}" -out "${cert}" \
    -days 1 -subj '/CN=localhost' -addext 'subjectAltName=DNS:localhost' >/dev/null 2>&1
  run env TLS_FIXTURE_CERT="${cert}" TLS_FIXTURE_KEY="${key}" python3 - <<'PY'
import importlib.machinery, importlib.util, os, pathlib, socket, ssl, threading
import signal

signal.alarm(15)

root = pathlib.Path(os.environ['LISTENER_TEST_DIR']).resolve()
source = pathlib.Path(os.environ['LISTENER_RELAY_FILE']).resolve()
cert = pathlib.Path(os.environ['TLS_FIXTURE_CERT']).resolve()
key = pathlib.Path(os.environ['TLS_FIXTURE_KEY']).resolve()
assert root.is_dir() and cert.parent == root and key.parent == root
assert source.is_file() and source.name == 'k3dm-browser-listener-relay'
loader = importlib.machinery.SourceFileLoader('listener_relay_tls', str(source))
module = importlib.util.module_from_spec(importlib.util.spec_from_loader(loader.name, loader))
loader.exec_module(module)

backend = socket.socket()
backend.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
backend.bind(('127.0.0.1', 0))
backend.listen(1)
backend.settimeout(3)
backend_port = backend.getsockname()[1]
relay_listener = socket.socket()
relay_listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
relay_listener.bind(('127.0.0.1', 0))
relay_listener.listen(1)
relay_listener.settimeout(3)
relay_port = relay_listener.getsockname()[1]
assert backend.getsockname()[0] == relay_listener.getsockname()[0] == '127.0.0.1'
server_context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
server_context.load_cert_chain(str(cert), str(key))
client_context = ssl.create_default_context(cafile=str(cert))
errors = []
accepted = []

def serve_backend():
    try:
        peer, _ = backend.accept()
        accepted.append(peer)
        peer.settimeout(3)
        request = b''
        while not request.endswith(b'\r\n\r\n'):
            request += peer.recv(256)
        assert request == b'GET /health HTTP/1.1\r\nHost: localhost\r\n\r\n', request
        peer.sendall(b'tls response')
        peer.shutdown(socket.SHUT_WR)
        peer.close()
    except Exception as exc:
        errors.append(exc)

def serve_relay():
    try:
        raw, _ = relay_listener.accept()
        accepted.append(raw)
        module._relay(raw, backend_port, server_context)
    except Exception as exc:
        errors.append(exc)

backend_thread = threading.Thread(target=serve_backend, daemon=True)
relay_thread = threading.Thread(target=serve_relay, daemon=True)
backend_thread.start()
relay_thread.start()
client = None
try:
    raw_client = socket.create_connection(('127.0.0.1', relay_port), timeout=3)
    client = client_context.wrap_socket(raw_client, server_hostname='localhost')
    client.settimeout(3)
    assert client.getpeercert()['subject'][0][0][1] == 'localhost'
    client.sendall(b'GET /health HTTP/1.1\r\nHost: localhost\r\n\r\n')
    response = b''
    while len(response) < len(b'tls response'):
        chunk = client.recv(128)
        assert chunk, response
        response += chunk
    assert response == b'tls response', response
    try:
        closure = client.recv(1)
    except ssl.SSLError:
        closure = b''  # TCP close may arrive without a TLS close_notify.
    assert closure == b'', 'relay stayed open after the backend closed'
    backend_thread.join(timeout=3)
    relay_thread.join(timeout=3)
    assert not backend_thread.is_alive() and not relay_thread.is_alive(), 'backend close left relay blocked on the open client'
finally:
    if client is not None:
        client.close()
    backend.close()
    relay_listener.close()
    for peer in accepted:
        try:
            peer.close()
        except OSError:
            pass
    backend_thread.join(timeout=1)
    relay_thread.join(timeout=1)
assert not backend_thread.is_alive() and not relay_thread.is_alive()
assert not errors, errors
PY
  if [ "${status}" -ne 0 ]; then
    printf '%s\n' "${output}"
  fi
  [ "${status}" -eq 0 ]
}

@test "TLS relay fixture cleans up a client that never completes its handshake" {
  local cert="${LISTENER_TEST_DIR}/stalled-client.crt"
  local key="${LISTENER_TEST_DIR}/stalled-client.key"
  openssl req -x509 -newkey rsa:2048 -nodes -keyout "${key}" -out "${cert}" \
    -days 1 -subj '/CN=localhost' -addext 'subjectAltName=DNS:localhost' >/dev/null 2>&1
  run env TLS_FIXTURE_CERT="${cert}" TLS_FIXTURE_KEY="${key}" python3 - <<'PY'
import importlib.machinery, importlib.util, os, pathlib, signal, socket, ssl, threading, time

signal.alarm(10)
root = pathlib.Path(os.environ['LISTENER_TEST_DIR']).resolve()
source = pathlib.Path(os.environ['LISTENER_RELAY_FILE']).resolve()
cert = pathlib.Path(os.environ['TLS_FIXTURE_CERT']).resolve()
key = pathlib.Path(os.environ['TLS_FIXTURE_KEY']).resolve()
assert root.is_dir() and cert.parent == root and key.parent == root
loader = importlib.machinery.SourceFileLoader('listener_relay_stalled_tls', str(source))
module = importlib.util.module_from_spec(importlib.util.spec_from_loader(loader.name, loader))
loader.exec_module(module)
server_context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
server_context.load_cert_chain(str(cert), str(key))
listener = socket.socket()
listener.bind(('127.0.0.1', 0))
listener.listen(1)
listener.settimeout(2)
accepted = []
errors = []

def stalled_relay():
    try:
        peer, _ = listener.accept()
        accepted.append(peer)
        module._relay(peer, 1, server_context, handshake_timeout=0.25)
    except (TimeoutError, OSError, ssl.SSLError):
        errors.append('bounded handshake failure')
    except Exception as exc:
        errors.append(repr(exc))

thread = threading.Thread(target=stalled_relay, daemon=True)
thread.start()
raw = socket.create_connection(('127.0.0.1', listener.getsockname()[1]), timeout=2)
started = time.monotonic()
try:
    thread.join(timeout=2)
    assert not thread.is_alive(), 'relay thread survived the bounded handshake timeout'
    assert time.monotonic() - started < 2, 'handshake cleanup exceeded its deadline'
    assert errors == ['bounded handshake failure'], errors
finally:
    raw.close()
    listener.close()
    for peer in accepted:
        peer.close()
    thread.join(timeout=1)
assert not thread.is_alive(), 'cleanup left a relay thread running'
PY
  if [ "${status}" -ne 0 ]; then
    printf '%s\n' "${output}"
  fi
  [ "${status}" -eq 0 ]
}

@test "TLS relay handles a readable partial record without blocking response writes" {
  run python3 - <<'PY'
import importlib.machinery, importlib.util, os, pathlib, socket, ssl, threading

root = pathlib.Path(os.environ['LISTENER_TEST_DIR']).resolve()
source = pathlib.Path(os.environ['LISTENER_RELAY_FILE']).resolve()
assert root.is_dir() and source.is_file()
loader = importlib.machinery.SourceFileLoader('listener_relay_partial_record', str(source))
module = importlib.util.module_from_spec(importlib.util.spec_from_loader(loader.name, loader))
loader.exec_module(module)
response_complete = threading.Event()

class PartialRecordClient:
    def __init__(self):
        self.timeout = None
        self.blocking = True
        self.recv_calls = 0
    def gettimeout(self):
        return self.timeout
    def setblocking(self, value):
        self.blocking = value
    def settimeout(self, value):
        self.timeout = value
        self.blocking = value is None
    def pending(self):
        return 0
    def recv(self, _size):
        self.recv_calls += 1
        assert not self.blocking, 'partial SSL record read was blocking'
        response_complete.set()
        raise ssl.SSLWantReadError()

class Upstream:
    def __init__(self):
        self.shutdowns = []
    def shutdown(self, how):
        self.shutdowns.append(how)

client = PartialRecordClient()
upstream = Upstream()
module.select.select = lambda readable, writable, exceptional, timeout: (readable, writable, [])
module._pump_tls_request(client, upstream, response_complete, threading.Lock())
assert client.recv_calls == 1
assert client.blocking and client.timeout is None, 'request pump did not restore blocking mode'
assert upstream.shutdowns == [socket.SHUT_WR], upstream.shutdowns
PY
  if [ "${status}" -ne 0 ]; then
    printf '%s\n' "${output}"
  fi
  [ "${status}" -eq 0 ]
}

@test "TLS relay preserves a large response while the client reads slowly" {
  local cert="${LISTENER_TEST_DIR}/slow-client.crt"
  local key="${LISTENER_TEST_DIR}/slow-client.key"
  openssl req -x509 -newkey rsa:2048 -nodes -keyout "${key}" -out "${cert}" \
    -days 1 -subj '/CN=localhost' -addext 'subjectAltName=DNS:localhost' >/dev/null 2>&1
  run env TLS_FIXTURE_CERT="${cert}" TLS_FIXTURE_KEY="${key}" python3 - <<'PY'
import hashlib, importlib.machinery, importlib.util, os, pathlib, signal, socket, ssl, threading, time

signal.alarm(20)
root = pathlib.Path(os.environ['LISTENER_TEST_DIR']).resolve()
source = pathlib.Path(os.environ['LISTENER_RELAY_FILE']).resolve()
cert = pathlib.Path(os.environ['TLS_FIXTURE_CERT']).resolve()
key = pathlib.Path(os.environ['TLS_FIXTURE_KEY']).resolve()
assert root.is_dir() and cert.parent == root and key.parent == root
loader = importlib.machinery.SourceFileLoader('listener_relay_slow_tls', str(source))
module = importlib.util.module_from_spec(importlib.util.spec_from_loader(loader.name, loader))
loader.exec_module(module)
payload = b'0123456789abcdef' * 524288  # 8 MiB, large enough to exercise backpressure.
expected_digest = hashlib.sha256(payload).digest()
backend = socket.socket()
backend.bind(('127.0.0.1', 0))
backend.listen(1)
backend.settimeout(5)
relay_listener = socket.socket()
relay_listener.bind(('127.0.0.1', 0))
relay_listener.listen(1)
relay_listener.settimeout(5)
assert backend.getsockname()[0] == relay_listener.getsockname()[0] == '127.0.0.1'
backend_port = backend.getsockname()[1]
server_context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
server_context.load_cert_chain(str(cert), str(key))
client_context = ssl.create_default_context(cafile=str(cert))
errors = []
accepted = []

def serve_backend():
    try:
        peer, _ = backend.accept()
        peer.settimeout(5)
        request = b''
        while not request.endswith(b'\r\n\r\n'):
            request += peer.recv(256)
        assert request == b'GET /large HTTP/1.1\r\nHost: localhost\r\n\r\n', request
        for offset in range(0, len(payload), 32768):
            peer.sendall(payload[offset:offset + 32768])
        peer.shutdown(socket.SHUT_WR)
        peer.close()
    except Exception as exc:
        errors.append(exc)

def serve_relay():
    try:
        raw, _ = relay_listener.accept()
        accepted.append(raw)
        module._relay(raw, backend_port, server_context)
    except Exception as exc:
        errors.append(exc)

backend_thread = threading.Thread(target=serve_backend, daemon=True)
relay_thread = threading.Thread(target=serve_relay, daemon=True)
backend_thread.start()
relay_thread.start()
client = None
try:
    raw = socket.create_connection(('127.0.0.1', relay_listener.getsockname()[1]), timeout=5)
    client = client_context.wrap_socket(raw, server_hostname='localhost')
    client.settimeout(5)
    client.sendall(b'GET /large HTTP/1.1\r\nHost: localhost\r\n\r\n')
    digest = hashlib.sha256()
    received = 0
    while received < len(payload):
        chunk = client.recv(min(32768, len(payload) - received))
        assert chunk, f'truncated response at {received} bytes'
        received += len(chunk)
        digest.update(chunk)
        time.sleep(0.001)
    assert received == len(payload)
    assert digest.digest() == expected_digest
    try:
        assert client.recv(1) == b''
    except ssl.SSLError:
        pass
    backend_thread.join(timeout=5)
    relay_thread.join(timeout=5)
    assert not backend_thread.is_alive() and not relay_thread.is_alive()
finally:
    if client is not None:
        client.close()
    backend.close()
    relay_listener.close()
    for peer in accepted:
        peer.close()
    backend_thread.join(timeout=1)
    relay_thread.join(timeout=1)
assert not backend_thread.is_alive() and not relay_thread.is_alive()
assert not errors, errors
PY
  if [ "${status}" -ne 0 ]; then
    printf '%s\n' "${output}"
  fi
  [ "${status}" -eq 0 ]
}

@test "listener relay rejects root and unsafe configuration" {
  run python3 - <<'PY'
import importlib.machinery, importlib.util, os, pathlib, sys
root = pathlib.Path(os.environ['LISTENER_TEST_DIR']).resolve()
source = pathlib.Path(os.environ['LISTENER_RELAY_FILE']).resolve()
assert root.is_dir() and source.name == 'k3dm-browser-listener-relay'
loader = importlib.machinery.SourceFileLoader('listener_relay', str(source))
module = importlib.util.module_from_spec(importlib.util.spec_from_loader(loader.name, loader))
loader.exec_module(module)
module.os.geteuid = lambda: 0
assert module.main(['relay', 'tcp', '18081']) == 2
module.os.geteuid = lambda: 501
for args in (['relay', 'tcp', '0'], ['relay', 'tcp', '65536'], ['relay', 'tcp', '-1'],
             ['relay', 'udp', '18081'], ['relay', 'tls', '443', 'relative.crt', '/tmp/key']):
    assert module.main(args) != 0, args
PY
  [ "${status}" -eq 0 ]
}

@test "listener upgrade boots out a hostile legacy plist before replacing and bootstrapping it" {
  run python3 - <<'PY'
import importlib.machinery, importlib.util, os, pathlib, plistlib, pwd, sys, types
root = pathlib.Path(os.environ['LISTENER_TEST_DIR']).resolve()
source = pathlib.Path(os.environ['LISTENER_SUPERVISOR_FILE']).resolve()
assert root.is_dir() and source.name == 'k3dm-browser-listener-supervisor'
loader = importlib.machinery.SourceFileLoader('listener_supervisor', str(source))
module = importlib.util.module_from_spec(importlib.util.spec_from_loader(loader.name, loader))
loader.exec_module(module)
launch_daemons = root / 'LaunchDaemons'
launch_daemons.mkdir()
module.ROOT = str(launch_daemons)
label = module.SERVICES['keycloak-http'][0]
plist_path = launch_daemons / (label + '.plist')
with plist_path.open('wb') as stream:
    plistlib.dump({'Label': label, 'ProgramArguments': ['/bin/sh', '-c', 'touch /tmp/hostile']}, stream)
with plist_path.open('rb') as stream:
    assert plistlib.load(stream)['ProgramArguments'][0] == '/bin/sh'  # hostile fixture positive control
module.os.geteuid = lambda: 0
module._safe_root_path = lambda _path: None
module._requesting_user = lambda: pwd.getpwuid(os.getuid())
events = []
def install(path, payload):
    assert pathlib.Path(path) == plist_path
    assert payload['ProgramArguments'] == [module.PYTHON, '-I', module.RELAY, 'tcp', '18081']
    with open(path, 'wb') as stream:
        plistlib.dump(payload, stream)
    events.append('install')
module._install_plist = install
def command(args, **kwargs):
    args = list(args)
    if args[1] == 'bootout':
        with plist_path.open('rb') as stream:
            previous = plistlib.load(stream)['ProgramArguments']
        assert previous == ['/bin/sh', '-c', 'touch /tmp/hostile'] or previous == [module.PYTHON, '-I', module.RELAY, 'tcp', '18081']
        events.append('bootout')
        return types.SimpleNamespace(returncode=5)
    if args[1] == 'bootstrap':
        with plist_path.open('rb') as stream:
            loaded = plistlib.load(stream)
        assert loaded['ProgramArguments'] == [module.PYTHON, '-I', module.RELAY, 'tcp', '18081']
        assert loaded['UserName'] == pwd.getpwuid(os.getuid()).pw_name
        assert '/bin/sh' not in loaded['ProgramArguments']
        events.append('bootstrap-safe')
        return types.SimpleNamespace(returncode=0)
    assert args[1] == 'enable' and args[2] == f'system/{label}'
    events.append('enable')
    return types.SimpleNamespace(returncode=0)
module.subprocess.run = command
module.write_listener('keycloak-http')
assert events == ['bootout', 'install', 'bootstrap-safe', 'enable'], events
events.clear()
module.write_listener('keycloak-http')
assert events == ['bootout', 'install', 'bootstrap-safe', 'enable'], events
with plist_path.open('rb') as stream:
    assert plistlib.load(stream)['UserName'] == pwd.getpwuid(os.getuid()).pw_name
PY
  [ "${status}" -eq 0 ]
}

@test "privileged helper directory preflight creates only safe scratch directories" {
  export DIRECTORY_PREFLIGHT_FILE="${BATS_TEST_DIRNAME}/../../../bin/ensure_privileged_helper_dir.py"
  run python3 - <<'PY'
import importlib.machinery, importlib.util, os, pathlib, stat, sys
root = pathlib.Path(os.environ['LISTENER_TEST_DIR']).resolve()
source = pathlib.Path(os.environ['DIRECTORY_PREFLIGHT_FILE']).resolve()
assert root.is_dir() and source.is_file()
loader = importlib.machinery.SourceFileLoader('helper_directory', str(source))
module = importlib.util.module_from_spec(importlib.util.spec_from_loader(loader.name, loader))
loader.exec_module(module)
parent = root / 'safe-parent'
parent.mkdir(mode=0o700)
target = parent / 'helpers'
assert not target.exists()
module.ensure_directory(str(target), os.getuid())
assert target.is_dir() and stat.S_IMODE(target.stat().st_mode) == 0o755
writable_parent = root / 'writable-parent'
writable_parent.mkdir(mode=0o777)
writable_parent.chmod(0o777)
try:
    module.ensure_directory(str(writable_parent / 'helpers'), os.getuid())
except ValueError:
    pass
else:
    raise AssertionError('accepted a group/world-writable parent')
victim = root / 'victim'
victim.mkdir()
(victim / 'marker').write_text('unchanged')
link = parent / 'linked-helpers'
link.symlink_to(victim, target_is_directory=True)
try:
    module.ensure_directory(str(link), os.getuid())
except ValueError:
    pass
else:
    raise AssertionError('accepted a symlink helper directory')
assert (victim / 'marker').read_text() == 'unchanged'
unsafe = parent / 'unsafe'
unsafe.mkdir(mode=0o775)
unsafe.chmod(0o775)
try:
    module.ensure_directory(str(unsafe), os.getuid())
except ValueError:
    pass
else:
    raise AssertionError('accepted a writable helper directory')
PY
  [ "${status}" -eq 0 ]
}

@test "user LaunchAgent safely supports configured state outside HOME" {
  local setup="${BATS_TEST_TMPDIR}/agent-test.sh" wrapper="${LISTENER_TEST_DIR}/wrapper.sh" log="${LISTENER_TEST_DIR}/listener.log"
  printf '#!/bin/sh\nexit 0\n' > "${wrapper}"
  : > "${log}"
  cat > "${setup}" <<'SH'
set -euo pipefail
REPO_ROOT="$1"
source "${REPO_ROOT}/scripts/lib/acg_browser_listeners.sh"
_ACG_STATE_DIR="$LISTENER_TEST_DIR"
_info() { :; }
_warn() { printf '%s\n' "$*" >&2; }
_acg_write_user_listener_agent com.k3d-manager.keycloak-browser-forward \
  "$LISTENER_TEST_DIR/wrapper.sh" "$LISTENER_TEST_DIR/listener.log"
python3 - "$HOME/Library/LaunchAgents/com.k3d-manager.keycloak-browser-forward.plist" "$LISTENER_TEST_DIR" <<'PY'
import os, pathlib, plistlib, sys
plist_path = pathlib.Path(sys.argv[1])
state = pathlib.Path(sys.argv[2]).resolve()
assert plist_path.is_file() and plist_path.parent == pathlib.Path(os.environ['HOME']) / 'Library/LaunchAgents'
with plist_path.open('rb') as stream:
    plist = plistlib.load(stream)
assert plist['Label'] == 'com.k3d-manager.keycloak-browser-forward'
assert plist['ProgramArguments'] == ['/bin/bash', os.path.join(sys.argv[2], 'wrapper.sh')], plist['ProgramArguments']
assert plist['StandardOutPath'] == os.path.join(sys.argv[2], 'listener.log')
PY
if _acg_write_user_listener_agent com.k3d-manager.keycloak-browser-forward \
  "$HOME/escape.sh" "$LISTENER_TEST_DIR/listener.log"; then
  exit 9
fi
SH
  chmod 755 "${setup}"
  run env HOME="${HOME}" LISTENER_TEST_DIR="${LISTENER_TEST_DIR}" bash "${setup}" "${REPO_ROOT:-$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)}"
  [ "${status}" -eq 0 ]
  [ -s "${HOME}/Library/LaunchAgents/com.k3d-manager.keycloak-browser-forward.plist" ]
}
