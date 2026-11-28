"""Offline browser-side capture acceptance tests."""
import io
import os
from pathlib import Path
import pty
import sys
import termios
import threading
from types import SimpleNamespace

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'lib'))
from wcb_capture import c8c9, isolation, recorder, supervisor


@pytest.fixture
def capture(tmp_path, monkeypatch):
    opbase, rootbase = tmp_path / 'operator', tmp_path / 'root'
    opbase.mkdir(); rootbase.mkdir()
    monkeypatch.setattr(isolation, 'OPERATOR_BASE', opbase)
    monkeypatch.setattr(isolation, 'ROOT_BASE', rootbase)
    first, second = isolation.scratch_dirs(create=True)
    second.mkdir()
    assert first.is_relative_to(tmp_path) and second.is_relative_to(tmp_path)
    return first, second


def test_c8_red_control_and_candidate_pass(capture):
    result = c8c9.classify_c8({'a': b'Connection from 127.0.0.1'}, {'a'})
    assert result['a'] == 'fail'
    result = c8c9.classify_c8({'a': b'', 'b': b'Connection from x', 'c': b'Connection from y'}, {'b', 'c'})
    assert result['a'] == 'candidate-pass'
    assert result['summary'] != 'origin JWT validation not shown'


def test_c8_void_when_control_c_fails(capture):
    result = c8c9.classify_c8({'a': b'', 'b': b'Connection from x', 'c': b''}, {'b'})
    assert result['a'] == 'void'
    assert result['c'] == 'void'
    assert c8c9.classify_c8({}, set())['summary'] == 'origin JWT validation not shown'


def test_c8_main_runs_clients_and_slices_logs_by_offsets(capture, monkeypatch):
    scratch, root = capture
    browser = scratch / 'browser'; browser.mkdir()
    sshd = root / 'sshd.log'; sshd.write_bytes(b'old sshd line\n')
    connector = scratch / 'connector.log'; connector.write_bytes(b'old connector line\n')
    root_steps = root / 'root-steps.log'; root_steps.write_text('[root 00:00:00] up c8\n')
    requests = []
    monkeypatch.setattr(c8c9.requests, 'submit', lambda verb: requests.append(verb) or len(requests))
    monkeypatch.setattr(isolation, 'check_port', lambda _port: None)
    monkeypatch.setattr(isolation, 'port_free', lambda _port=42723: True)
    monkeypatch.setattr(c8c9, '_write_safe', lambda path, text, kind='recorder': path.write_text(text) or True)
    seen = []
    def runner(argv, **kwargs):
        seen.append((argv, kwargs))
        assert argv == ['cloudflared', 'access', 'ssh', '--hostname', 'capture.example.net']
        assert kwargs['env']['HOME'] == str(scratch / 'cfhome')
        key = 'a' if len(seen) == 1 else 'b' if len(seen) == 2 else 'c'
        connector.write_text(connector.read_text() + 'request-' + key + '\n')
        if key == 'a':
            sshd.write_text(sshd.read_text() + 'Connection from 127.0.0.1 port 5\n')
        else:
            sshd.write_text(sshd.read_text() + 'Connection from 127.0.0.1 port 6\n')
        return SimpleNamespace(returncode=255, stderr='probe ' + key, stdout='')
    answers = iter(['', 'capture.example.net', '', '', '', '', '', '', 'n'])
    result = c8c9.main_c8([], runner=runner, input_fn=lambda _prompt: next(answers), output=print,
                          wait_for=lambda *_args: True)
    assert result == 0
    assert requests == ['up-c8', 'down']
    assert len(seen) == 3
    assert 'Connection from' in (browser / 'c8-a-sshd.txt').read_text()
    assert 'byte_offsets=' in (browser / 'c8-a-sshd.txt').read_text()
    assert 'byte_offsets=' in (browser / 'c8-a-connector.txt').read_text()
    assert 'exit=255' in (browser / 'c8-a-client.txt').read_text()
    assert 'error=probe a' in (browser / 'c8-a-client.txt').read_text()
    assert 'result=not run' in (browser / 'c8-d-result.txt').read_text()


def test_c8_candidate_pass_and_all_void_summary():
    clean = c8c9.classify_c8({'a': b'', 'b': b'Accepted publickey', 'c': b'Connection from 127.0.0.1'}, {'b', 'c'})
    assert clean['a'] == 'candidate-pass'
    assert clean['b'] == 'reached' and clean['c'] == 'reached'
    assert clean['summary'] == 'review connector slices'
    invalid = c8c9.classify_c8({'a': b'', 'b': b'', 'c': b'', 'd': b''}, set(), {'d': 'not run'})
    assert [invalid[key] for key in 'abcd'] == ['void', 'void', 'void', 'not run']
    assert invalid['summary'] == 'origin JWT validation not shown'
    assert c8c9.classify_c8({'d': b'Connection from 127.0.0.1'}, {'b', 'c'})['d'] == 'fail'


def test_c15_compares_hash_field_only(capture):
    # Comments can differ while the field-2 SHA256 values are identical.
    assert supervisor.Supervisor._hash('256 SHA256:abc one (ED25519)') == supervisor.Supervisor._hash(
        '256 SHA256:abc two (ED25519)')


@pytest.mark.parametrize('profile', ['c5', 'c5-exit', 'c5-notty', 'c4-login1', 'c4-login2', 'c15-a', 'c15-b', 'c8', 'c9-hold'])
def test_recorder_requires_return_and_marks_abandoned(capture, profile, monkeypatch):
    first, _ = capture
    monkeypatch.setattr(recorder.isolation, 'check_write', lambda *_a, **_k: None)
    master, slave = pty.openpty()
    output = io.StringIO()
    rec = recorder.Recorder(profile, input_fd=slave, output=output, env={}, timeout=0, hold_seconds=0)
    assert os.isatty(slave)
    assert rec.run() == 3
    assert list((first / 'browser').glob('abandoned-' + profile + '-*'))
    assert not (first / 'browser' / ('done-' + profile)).exists()
    os.close(master); os.close(slave)


def test_recorder_interprets_input_as_data(capture, monkeypatch):
    first, _ = capture
    monkeypatch.setattr(recorder.isolation, 'check_write', lambda *_a, **_k: None)
    master, slave = pty.openpty()
    output = io.StringIO()
    rec = recorder.Recorder('c4-login2', input_fd=slave, output=output, env={}, timeout=.2)
    thread = threading.Thread(target=rec.run); thread.start()
    os.write(master, b'\n')
    os.write(master, b'$(touch X)\n')
    thread.join(2)
    assert not thread.is_alive()
    assert 'done c4-login2' in output.getvalue()
    assert 'prev c4-login1 other' in rec.log.read_text()
    assert (first / 'browser' / 'done-c4-login2').is_file()
    assert not (first / 'X').exists()
    os.close(master); os.close(slave)


def test_c5_records_idle_hold_and_terminal_probe_sequence(capture, monkeypatch):
    first, _ = capture
    monkeypatch.setattr(recorder.isolation, 'check_write', lambda *_a, **_k: None)
    master, slave = pty.openpty()
    rec = recorder.Recorder('c5', input_fd=slave, output=io.StringIO(), env={'TERM': 'xterm'},
                            timeout=.2, hold_seconds=0)
    prompts = []
    rec.raw_window = lambda prompt, duration, send=None: prompts.append((prompt, send)) or 'bytes 1b5b52'
    os.write(master, b'\n')
    assert rec.run() == 0
    assert [item[1] for item in prompts] == [None, None, b'\x1b[6n', b'\x1b[c', b'\x1b[c']
    assert 'leave page untouched for 3 minutes' in rec.log.read_text()
    assert 'idle-hold pid=' in rec.log.read_text()
    assert (first / 'browser' / 'done-c5').is_file()
    os.close(master); os.close(slave)


@pytest.mark.parametrize('profile, lines, expected_code, expected_text', [
    ('c5-exit', (b'\n', b'blank\n'), 3, 'exit 3'),
    ('c5-notty', (b'\n', b'blank\n'), 0, 'pty=yes'),
    ('c8', (b'\n', b'blank\n'), 0, 'reached '),
    ('c15-a', (b'\n', b'blank\n', b'fingerprint\n'), 0, 'safari fingerprint'),
    ('c4-login1', (b'\n', b'blank\n'), 0, 'c4 void certificate not inspected'),
])
def test_recorder_profile_specific_outputs(capture, monkeypatch, profile, lines, expected_code, expected_text):
    first, _ = capture
    monkeypatch.setattr(recorder.isolation, 'check_write', lambda *_a, **_k: None)
    master, slave = pty.openpty()
    output = io.StringIO()
    rec = recorder.Recorder(profile, input_fd=slave, output=output, env={'USER': 'tester'}, timeout=.3)
    if profile.startswith('c15-'):
        (first / 'browser' / (profile + '-comparison')).write_text('algorithm ed25519\ncomparison matched\n')
    def send_lines():
        import time
        for line in lines:
            os.write(master, line)
            time.sleep(.01)
    sender = threading.Thread(target=send_lines); sender.start()
    assert rec.run() == expected_code
    sender.join(1)
    rendered = rec.log.read_text()
    assert expected_text in rendered
    if expected_code == 0 and profile != 'c4-login1':
        assert (first / 'browser' / ('done-' + profile)).exists()
    os.close(master); os.close(slave)


def test_c4_certificate_inspection_redacts_principal_and_key_id(capture, monkeypatch, tmp_path):
    first, _ = capture
    monkeypatch.setattr(recorder.isolation, 'check_write', lambda *_a, **_k: None)
    auth = tmp_path / 'ssh_user_auth'
    auth.write_text('publickey ssh-ed25519-cert-v01@openssh.com AAAAopaque\n')
    seen = []
    def runner(argv, **kwargs):
        seen.append(kwargs['input'])
        return SimpleNamespace(returncode=0, stdout=(
            'Signing CA: ED25519 SHA256:privatefingerprint (using ssh-ed25519)\n'
            'Key ID: "tester"\nValid: from 2026-11-01T00:00:00 to 2026-11-02T00:00:00\n'
            'Principals:\n        tester\n'), stderr='')
    master, slave = pty.openpty()
    rec = recorder.Recorder('c4-login1', input_fd=slave, output=io.StringIO(),
                            env={'USER': 'tester', 'SSH_USER_AUTH': str(auth)},
                            command_runner=runner, timeout=.2)
    os.write(master, b'\nblank\n')
    assert rec.run() == 0
    logged = rec.log.read_text()
    assert seen == ['ssh-ed25519-cert-v01@openssh.com AAAAopaque']
    assert 'principal length=6 equals_login=yes' in logged
    assert 'Key ID: length=6 equals_login=yes' in logged
    assert 'privatefingerprint' not in logged and 'tester' not in logged
    assert (first / 'browser' / 'done-c4-login1').exists()
    os.close(master); os.close(slave)


def test_unprompted_window_records_control_bytes_in_raw_mode(capture, monkeypatch):
    first, _ = capture
    monkeypatch.setattr(recorder.isolation, 'check_write', lambda *_a, **_k: None)
    master, slave = pty.openpty()
    rec = recorder.Recorder('c5', input_fd=slave, output=io.StringIO(), env={}, timeout=.2)
    observed = {}
    def client():
        import time
        deadline = time.monotonic() + 1
        while time.monotonic() < deadline:
            attrs = termios.tcgetattr(slave)
            if not attrs[3] & termios.ICANON:
                observed['lflag'] = attrs[3]
                os.write(master, b'\x03\x1a\x1c')
                return
            time.sleep(.005)
    writer = threading.Thread(target=client); writer.start()
    assert rec.raw_window('control bytes', .5) == 'bytes 031a1c'
    writer.join(1)
    assert observed['lflag'] & (termios.ICANON | termios.ECHO | termios.ISIG) == 0
    assert termios.tcgetattr(slave)[3] & termios.ICANON
    assert '031a1c' in rec.log.read_text()
    os.close(master); os.close(slave)


def test_terminal_reply_is_sent_and_recorded_as_hex(capture, monkeypatch):
    monkeypatch.setattr(recorder.isolation, 'check_write', lambda *_a, **_k: None)
    master, slave = pty.openpty()
    rec = recorder.Recorder('c5', input_fd=slave, output=io.StringIO(), env={}, timeout=.2)
    writes = []
    real_write = os.write
    def spy(fd, data):
        if fd == 1:
            writes.append(data)
            return len(data)
        return real_write(fd, data)
    monkeypatch.setattr(recorder.os, 'write', spy)
    def client():
        import time
        deadline = time.monotonic() + 1
        while time.monotonic() < deadline:
            if not termios.tcgetattr(slave)[3] & termios.ICANON:
                real_write(master, b'\x1b[1;2R')
                return
            time.sleep(.005)
    sender = threading.Thread(target=client); sender.start()
    assert rec.raw_window('device status', .5, b'\x1b[6n') == 'bytes 1b5b313b3252'
    sender.join(1)
    assert writes == [b'\x1b[6n']
    assert 'bytes 1b5b313b3252' in rec.log.read_text()
    os.close(master); os.close(slave)


def test_c9_hold_writes_heartbeat_and_records_eof(capture, monkeypatch):
    monkeypatch.setattr(recorder.isolation, 'check_write', lambda *_a, **_k: None)
    read_fd, write_fd = os.pipe()
    os.write(write_fd, b'\nblank\n'); os.close(write_fd)
    rec = recorder.Recorder('c9-hold', input_fd=read_fd, output=io.StringIO(), env={}, timeout=.02)
    assert rec.run() == 0
    assert 'heartbeat ' in rec.log.read_text()
    assert 'EOF' in rec.log.read_text()
    os.close(read_fd)


@pytest.mark.parametrize('partial, expected', [(False, 'no bytes'), (True, 'timeout after partial input')])
def test_line_timeout_distinguishes_empty_and_partial(capture, monkeypatch, partial, expected):
    monkeypatch.setattr(recorder.isolation, 'check_write', lambda *_a, **_k: None)
    read_fd, write_fd = os.pipe()
    if partial: os.write(write_fd, b'partial')
    rec = recorder.Recorder('c4-login2', input_fd=read_fd, output=io.StringIO(), env={}, timeout=.02)
    assert rec.line('answer', timeout=.02) is None
    assert expected in rec.log.read_text()
    os.close(read_fd); os.close(write_fd)


def _supervisor_fixture(capture, monkeypatch, requests=None):
    scratch, root = capture
    browser = scratch / 'browser'; browser.mkdir(exist_ok=True)
    (root / 'root-steps.log').write_text('')
    (root / 'sshd.log').write_text('')
    monkeypatch.setattr(supervisor.isolation, 'scratch_dirs', lambda: (scratch, root))
    monkeypatch.setattr(supervisor.isolation, 'check_write', lambda *_a, **_k: None)
    monkeypatch.setattr(supervisor.isolation, 'port_free', lambda _port=42723: True)
    ops = [] if requests is None else requests
    def submit(verb):
        ops.append(verb)
        with (root / 'root-steps.log').open('a') as stream:
            if verb.startswith('up-'): stream.write('[root 00:00:01] up ' + verb[3:] + '\n')
            elif verb == 'down': stream.write('[root 00:00:02] down\n')
            elif verb == 'rekey': stream.write('[root 00:00:03] rekey\n')
        return len(ops)
    monkeypatch.setattr(supervisor.requests, 'submit', submit)
    return scratch, root, ops


def test_supervisor_resumes_at_first_profile_without_done_marker(capture, monkeypatch):
    scratch, root, _ops = _supervisor_fixture(capture, monkeypatch)
    for name in ('c5', 'c5-exit'):
        (scratch / 'browser' / ('done-' + name)).touch()
    token = scratch / 'tunnel-token'; token.write_text('fixture'); token.chmod(0o600)
    (root / 'access_ca.pub').write_text('public key')
    sup = supervisor.Supervisor(runner=lambda *_a, **_k: SimpleNamespace(returncode=0, stdout='', stderr=''),
                                output=lambda _line: None, env={})
    visited = []
    sup.profile = lambda name: visited.append(name) or True
    assert sup.run() == 0
    assert visited == list(supervisor.SEQUENCE[2:])


def test_supervisor_reoffers_abandoned_profile_and_records_sshd_slice(capture, monkeypatch):
    scratch, root, ops = _supervisor_fixture(capture, monkeypatch)
    sup = supervisor.Supervisor(runner=lambda *_a, **_k: SimpleNamespace(returncode=0, stdout='', stderr=''),
                                output=lambda _line: None, env={}, sleeper=lambda _delay: None)
    outcomes = iter([('abandoned', None), ('done', None)])
    sup._watch_profile = lambda _name: next(outcomes)
    (root / 'sshd.log').write_text('first ssh line\n')
    def watch(_name):
        with (root / 'sshd.log').open('a') as stream: stream.write('accepted login\n')
        return next(outcomes)
    sup._watch_profile = watch
    assert sup.profile('c5')
    assert ops == ['up-c5', 'down', 'up-c5', 'down']
    assert len((scratch / 'browser' / 'sshd-c5.txt').read_text().splitlines()) >= 2
    assert 'c5' in sup.results[0]


@pytest.mark.parametrize('command, expected, continues', [
    ('result accepted', 'accepted', True), ('skip', 'not run', True), ('stop', 'not run', False),
])
def test_supervisor_commands_advance_and_stop(capture, monkeypatch, command, expected, continues):
    _scratch, _root, ops = _supervisor_fixture(capture, monkeypatch)
    sup = supervisor.Supervisor(runner=lambda *_a, **_k: SimpleNamespace(returncode=0, stdout='', stderr=''),
                                output=lambda _line: None, env={}, sleeper=lambda _delay: None)
    sup._watch_profile = lambda _name: ('command' if command.startswith('result') else command, 'accepted')
    result = sup.profile('c5-notty')
    assert result is continues
    assert sup.results == [('c5-notty', expected)]
    assert ops == ['up-c5-notty', 'down']


def test_supervisor_c15_hash_field_voids_stale_and_offers_changed(capture, monkeypatch):
    scratch, root, ops = _supervisor_fixture(capture, monkeypatch)
    class Fingerprints:
        served_hash = 'SHA256:old'
        def __call__(self, argv, **kwargs):
            if argv[0].endswith('ssh-keyscan'):
                return SimpleNamespace(returncode=0, stdout='ssh-ed25519 AAAA\n', stderr='')
            if argv[-1] == '-':
                return SimpleNamespace(returncode=0, stdout='256 %s served (ED25519)\n' % self.served_hash, stderr='')
            return SimpleNamespace(returncode=0, stdout='256 %s file (ED25519)\n' % self.served_hash, stderr='')
    runner = Fingerprints()
    sup = supervisor.Supervisor(runner=runner, output=lambda _line: None, env={}, sleeper=lambda _delay: None)
    assert sup._hash('256 SHA256:same served (ED25519)') == sup._hash('256 SHA256:same file (ED25519)')
    sup.hash_a = 'SHA256:old'
    assert sup.profile('c15-b')  # void is recorded and the sequence can continue
    assert sup.results == [('c15-b', 'void')]
    assert not ops
    runner.served_hash = 'SHA256:new'
    (root / 'root-steps.log').write_text('')
    (root / 'sshd.log').write_text('')
    sup._watch_profile = lambda _name: ('done', None)
    assert sup.profile('c15-b')
    assert ops == ['up-c15-b', 'down']
    assert (scratch / 'browser' / 'c15-b-comparison').read_text().endswith('comparison matched\n')


def test_browser_subprocess_controls_are_statically_named():
    assert supervisor.SEQUENCE == ('c5', 'c5-exit', 'c5-notty', 'c4-login1', 'c4-login2', 'c15-a', 'c15-b')
