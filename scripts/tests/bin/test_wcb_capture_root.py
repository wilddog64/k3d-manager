"""Offline checks for the capture root-side interfaces."""
import importlib.util
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'lib' / 'wcb_capture'))
import isolation  # noqa: E402
spec = importlib.util.spec_from_file_location('capture_requests', Path(isolation.__file__).with_name('requests.py'))
capture_requests = importlib.util.module_from_spec(spec)
spec.loader.exec_module(capture_requests)


@pytest.fixture
def capture(tmp_path, monkeypatch):
    assert tmp_path.is_absolute()
    monkeypatch.setattr(isolation, 'OPERATOR_BASE', tmp_path / 'operator')
    monkeypatch.setattr(isolation, 'ROOT_BASE', tmp_path / 'root')
    isolation.OPERATOR_BASE.mkdir()
    isolation.ROOT_BASE.mkdir()
    first, second = isolation.scratch_dirs(create=True)
    second.mkdir()
    assert first.is_relative_to(tmp_path) and second.is_relative_to(tmp_path)
    return first, second


def test_isolation_paths_labels_port(capture):
    first, second = capture
    isolation.check_write(first / 'x')
    isolation.check_write(second / 'x', mode='root')
    isolation.check_label('com.k3d-manager.capture-sshd')
    isolation.check_port(42723)
    for path in ('/etc/k3dm-web-console/x', '/private/etc/k3dm-web-console/x',
                 '/Library/LaunchDaemons/x', str(Path.home() / '.cloudflared/x')):
        with pytest.raises(isolation.Refused):
            isolation.check_write(path)
    with pytest.raises(isolation.Refused):
        isolation.check_label('com.k3d-manager.' + 'web-console-sshd')
    with pytest.raises(isolation.Refused):
        isolation.check_port(42722)


def test_isolation_cloudflared_and_multiplexer():
    isolation.check_cloudflared(['cloudflared', '--version'], {})
    isolation.check_cloudflared(['cloudflared', 'access', 'ssh', '--hostname', 'example'], {})
    for argv, env in [(['cloudflared', 'tunnel', '--config', 'x', 'create', 'x'], {}),
                      (['cloudflared', 'access', 'ssh', '--token=x'], {}),
                      (['cloudflared', '--version'], {'TUNNEL_TOKEN': 'x'})]:
        with pytest.raises(isolation.Refused):
            isolation.check_cloudflared(argv, env)
    isolation.refuse_multiplexer({}, ['zsh'])
    with pytest.raises(isolation.Refused):
        isolation.refuse_multiplexer({}, ['tmux'])


def test_requests_sequence(capture):
    first, _ = capture
    assert capture_requests.submit('up-c5') == 1
    assert capture_requests.submit('down') == 2
    assert sorted(p.name for p in (first / 'req').iterdir()) == ['0001-up-c5', '0002-down']
    with pytest.raises(isolation.Refused):
        capture_requests.submit('unknown')


def _blob(data):
    import hashlib
    return hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest()


@pytest.fixture
def rootd_fixture(tmp_path):
    import os
    import types
    import rootd

    root = tmp_path / 'k3dm-capture-2026-11-28'
    scratch = tmp_path / 'k3dm-captures-2026-11-28'
    root.mkdir()
    scratch.mkdir(mode=0o700)
    (scratch / 'req').mkdir()
    (scratch / 'ca').mkdir()
    assert root.is_relative_to(tmp_path) and scratch.is_relative_to(tmp_path)
    sources = Path(__file__).resolve().parents[2] / 'lib' / 'wcb_capture'
    expect = {}
    for name in rootd.FILES:
        source = {'sshd_config.base': sources / 'templates/sshd_config.base',
                  'capture-sshd.plist.template': sources / 'templates/capture-sshd.plist',
                  'principals-any': sources / 'templates/principals-any'}.get(name, sources / name)
        data = source.read_bytes() if source.exists() else b'fixture recorder\n'
        (root / name).write_bytes(data)
        expect[name] = _blob(data)
    calls = []

    def runner(argv):
        calls.append(argv)
        return types.SimpleNamespace(returncode=0, stdout='0' if argv[0] == '/bin/ps' else '')

    driver = rootd.RootDriver(root, scratch, 'tester', expect, runner=runner,
                              owner=os.getuid(), login_uid=os.getuid(), scratch_parent=tmp_path, root_parent=tmp_path,
                              launch_timeout=0)
    return driver, calls


def test_rootd_request_restart_and_no_writes(rootd_fixture):
    driver, calls = rootd_fixture
    driver.verify()
    driver.open_scratch()
    req = driver.scratch / 'req'
    before = {p: p.read_bytes() for p in req.iterdir()}
    (req / '0001-quit').touch()
    driver.poll()
    assert driver.stop == 'quit'
    assert (req / '0001-quit').exists()
    assert before == {}
    import rootd
    driver = rootd.RootDriver(driver.root, driver.scratch, driver.login, driver.expect,
                              runner=driver.runner, owner=driver.owner, login_uid=driver.login_uid,
                              root_parent=driver.root_parent, scratch_parent=driver.scratch_parent)
    driver.open_scratch()
    driver.poll()
    assert driver.stop is None
    (req / '0002-quit').touch()
    driver.poll()
    assert driver.stop == 'quit'
    assert calls == []


def test_rootd_rejects_bad_files_and_blobs(rootd_fixture):
    driver, _ = rootd_fixture
    driver.verify()
    path = driver.root / 'recorder.py'
    path.chmod(0o666)
    with pytest.raises(ValueError):
        driver.verify()
    path.chmod(0o644)
    path.write_text('changed')
    with pytest.raises(ValueError):
        driver.verify()


def test_rootd_readback_rejects_missing_required(rootd_fixture):
    driver, _ = rootd_fixture
    assert not driver._readback('c4-login2', 'permitrootlogin no\n')


def test_rootd_c13_switch_and_pid(rootd_fixture, monkeypatch):
    driver, calls = rootd_fixture
    (driver.root / 'c13').mkdir()
    (driver.root / 'c13/ca1.pub').write_text('ca1')
    (driver.root / 'c13/ca2.pub').write_text('ca2')
    state = {'pid': None, 'bootstraps': 0}
    monkeypatch.setattr(driver, 'pid', lambda: state['pid'])
    monkeypatch.setattr(driver, '_c13_init', lambda: None)
    monkeypatch.setattr(driver, '_generate_key', lambda: None)
    monkeypatch.setattr(driver, '_readback', lambda profile, output: True)
    monkeypatch.setattr(driver, 'listeners', lambda: [] if state['pid'] is None else ['127.0.0.1.42723 LISTEN sshd:42'])
    original = driver.command

    def command(*args, **kwargs):
        if args[1:2] == ('bootstrap',):
            state['pid'] = 42
            state['bootstraps'] += 1
        return original(*args, **kwargs)

    monkeypatch.setattr(driver, 'command', command)
    with pytest.raises(ValueError):
        driver.up('c13-ca2')
    driver.up('c13-ca1')
    assert (driver.root / 'c13_ca.pub').read_text() == 'ca1'
    assert state['bootstraps'] == 1
    driver.up('c13-ca2')
    assert (driver.root / 'c13_ca.pub').read_text() == 'ca2'
    driver.up('c13-ca1')
    assert (driver.root / 'c13_ca.pub').read_text() == 'ca1'
    assert state['bootstraps'] == 1 and state['pid'] == 42
    assert 'c13 pid before 42 after 42' in (driver.root / 'root-steps.log').read_text()
    driver.profile = 'c5'
    with pytest.raises(ValueError):
        driver.up('c13-ca1')
    with pytest.raises(ValueError):
        driver.up('c13-ca2')
    assert any('bootstrap' in call for call in calls)


def test_rootd_teardown_lock(rootd_fixture):
    import rootd
    driver, calls = rootd_fixture
    other = rootd.RootDriver(driver.root, owner=driver.owner, runner=driver.runner, root_parent=driver.root.parent)
    driver.acquire()
    import shutil
    shutil.rmtree(driver.scratch)
    assert not driver.scratch.exists()
    with pytest.raises(BlockingIOError):
        other.teardown()
    import os
    os.close(driver.lock)
    driver.lock = None
    other.teardown()
    assert not driver.root.exists()
    other.teardown()
    assert any('bootout' in call for call in calls)


def test_stage_uses_git_show_and_refuses_dirty(capture, monkeypatch, capsys):
    import types
    import stage
    first, second = capture
    monkeypatch.setattr(stage.os, 'getlogin', lambda: 'tester')
    monkeypatch.setattr(stage, '_secret_prompt', lambda _prompt: 'X' * 48)
    monkeypatch.setattr(stage.sys, 'stdin', types.SimpleNamespace(isatty=lambda: True))
    calls = []
    dirty = {'value': True}

    def runner(argv, **kwargs):
        calls.append(argv)
        if argv[1:3] == ['status', '--porcelain']:
            output = b' M scripts/lib/wcb_capture/rootd.py\n' if dirty['value'] else b''
        elif argv[1] == 'rev-parse':
            output = b'a' * 40 + b'\n'
        elif argv[1] == 'show':
            output = b'reviewed commit bytes\n'
        elif argv[0] == '/usr/bin/sudo' and '-d' not in argv:
            assert Path(argv[-2]).read_bytes() == b'reviewed commit bytes\n'
            output = b''
        else:
            output = b''
        return types.SimpleNamespace(stdout=output)

    assert stage.main([], runner=runner, prompt=lambda _: 'yes', owner=__import__('os').getuid()) == 2
    assert not any(call[0] == '/usr/bin/sudo' for call in calls)
    dirty['value'] = False
    calls.clear()
    assert stage.main([], runner=runner, prompt=lambda _: 'yes', owner=__import__('os').getuid()) == 0
    output = capsys.readouterr().out
    assert 'commit ' + 'a' * 40 in output and '--expect' in output
    assert len([call for call in calls if len(call) > 1 and call[1] == 'show']) == len(stage.FILES)
    for dest, (_, mode) in stage.FILES.items():
        assert any(call[-1] == str(second / dest) and call[call.index('-m') + 1] == mode
                   for call in calls if call[0] == '/usr/bin/sudo' and '-m' in call)
    assert all('-o' in call and 'root' in call and 'wheel' in call for call in calls if call[0] == '/usr/bin/sudo')
    assert (first / 'tunnel-token').read_text() == 'X' * 48
    assert (first / 'tunnel-token').stat().st_mode & 0o777 == 0o600
    assert first.is_dir() and second.is_relative_to(first.parent.parent)


def _stage_stub(monkeypatch, tmp_path, first, second, *, tty=True, token='S' * 48, existing=None,
                prompt_error=None, env_name=None):
    import types
    import stage
    monkeypatch.setattr(stage.os, 'getlogin', lambda: 'tester')
    monkeypatch.setattr(stage.sys, 'stdin', types.SimpleNamespace(isatty=lambda: tty))
    monkeypatch.setattr(stage, '_operator_uid', lambda: __import__('os').getuid())
    if env_name:
        monkeypatch.setitem(stage.os.environ, env_name, 'multiplexer')
    if existing == 'live-symlink':
        target = first / 'token-target'
        target.write_text(token)
        (first / 'tunnel-token').symlink_to(target)
    elif existing == 'dangling-symlink':
        (first / 'tunnel-token').symlink_to(first / 'missing-target')
    elif existing == '0644':
        (first / 'tunnel-token').write_text(token)
        (first / 'tunnel-token').chmod(0o644)
    elif existing == 'foreign-owner':
        monkeypatch.setattr(stage, '_operator_uid', lambda: __import__('os').getuid() + 1)
        (first / 'tunnel-token').write_text(token)
        (first / 'tunnel-token').chmod(0o600)
    elif existing == 'empty':
        (first / 'tunnel-token').write_text('')
        (first / 'tunnel-token').chmod(0o600)
    elif existing == 'valid':
        (first / 'tunnel-token').write_text(token)
        (first / 'tunnel-token').chmod(0o600)
    calls = []
    secret_calls = []
    def runner(argv, **kwargs):
        calls.append((list(argv), kwargs))
        if argv[1:3] == ['status', '--porcelain']:
            stdout = b''
        elif argv[1] == 'rev-parse':
            stdout = b'a' * 40 + b'\n'
        elif argv[1] == 'show':
            stdout = b'staged source bytes\n'
        else:
            stdout = b''
        return types.SimpleNamespace(stdout=stdout)
    def secret_prompt(_prompt):
        secret_calls.append(_prompt)
        if existing == 'race':
            target = first / 'token-target'
            target.write_text('pre-existing target contents')
            (first / 'tunnel-token').symlink_to(target)
        if prompt_error:
            import getpass
            if isinstance(prompt_error, getpass.GetPassWarning):
                import warnings
                warnings.warn(str(prompt_error), getpass.GetPassWarning)
            else:
                raise prompt_error
        return token
    monkeypatch.setattr(stage, '_secret_prompt', secret_prompt)
    return stage, calls, runner, secret_calls


def test_stage_existing_valid_token_skips_prompt_and_continues(capture, tmp_path, monkeypatch, capsys):
    first, second = capture
    token = 'V' * 48
    stage, calls, runner, secret_calls = _stage_stub(monkeypatch, tmp_path, first, second,
                                                      token=token, existing='valid')
    prompts = []
    assert stage.main([], runner=runner, prompt=lambda value: prompts.append(value) or 'yes',
                      owner=__import__('os').getuid()) == 0
    assert [argv[0] for argv, _kwargs in calls if argv[0] == '/usr/bin/sudo']
    assert secret_calls == []
    assert (first / 'tunnel-token').read_text() == token
    assert token not in capsys.readouterr().out


@pytest.mark.parametrize('existing', ['live-symlink', 'dangling-symlink', '0644', 'foreign-owner', 'empty'])
def test_stage_refuses_unsafe_existing_token(capture, tmp_path, monkeypatch, capsys, existing):
    first, second = capture
    token = 'W' * 48
    stage, calls, runner, _secret_calls = _stage_stub(monkeypatch, tmp_path, first, second,
                                                       token=token, existing=existing)
    assert stage.main([], runner=runner, prompt=lambda _prompt: 'yes',
                      owner=__import__('os').getuid()) == 2
    output = capsys.readouterr().out
    assert 'stage refused: unsafe token file' in output
    assert token not in output
    assert not any(argv[0] == '/usr/bin/sudo' for argv, _kwargs in calls)


def test_stage_requires_tty_for_hidden_token(capture, tmp_path, monkeypatch, capsys):
    first, second = capture
    stage, calls, runner, secret_calls = _stage_stub(monkeypatch, tmp_path, first, second, tty=False)
    assert stage.main([], runner=runner, prompt=lambda _prompt: 'yes',
                      owner=__import__('os').getuid()) == 2
    assert 'stage refused: no terminal for hidden input' in capsys.readouterr().out
    assert secret_calls == []


def test_stage_refuses_getpass_echo_fallback(capture, tmp_path, monkeypatch, capsys):
    import getpass
    first, second = capture
    stage, calls, runner, _secret_calls = _stage_stub(monkeypatch, tmp_path, first, second,
                                                      prompt_error=getpass.GetPassWarning('echo enabled'))
    assert stage.main([], runner=runner, prompt=lambda _prompt: 'yes',
                      owner=__import__('os').getuid()) == 2
    output = capsys.readouterr().out
    assert 'stage refused: cannot disable terminal echo' in output
    assert 'echo enabled' not in output


def test_stage_rejects_bad_connector_token_shape(capture, tmp_path, monkeypatch, capsys):
    first, second = capture
    stage, calls, runner, _secret_calls = _stage_stub(monkeypatch, tmp_path, first, second,
                                                      token='bad-token')
    assert stage.main([], runner=runner, prompt=lambda _prompt: 'yes',
                      owner=__import__('os').getuid()) == 2
    output = capsys.readouterr().out
    assert 'stage refused: token shape invalid' in output
    assert 'bad-token' not in output
    assert not (first / 'tunnel-token').exists()


@pytest.mark.parametrize('env_name', ['TMUX', 'STY'])
def test_stage_refuses_multiplexer_before_token_prompt(capture, tmp_path, monkeypatch, capsys, env_name):
    first, second = capture
    stage, calls, runner, secret_calls = _stage_stub(monkeypatch, tmp_path, first, second,
                                                      env_name=env_name)
    assert stage.main([], runner=runner, prompt=lambda _prompt: 'yes',
                      owner=__import__('os').getuid()) == 2
    output = capsys.readouterr().out
    assert 'stage refused: multiplexer session' in output
    assert not (first / 'tunnel-token').exists()
    assert secret_calls == []


def test_stage_token_create_race_preserves_planted_symlink_target(capture, tmp_path, monkeypatch, capsys):
    first, second = capture
    token = 'Z' * 48
    stage, calls, runner, _secret_calls = _stage_stub(monkeypatch, tmp_path, first, second,
                                                       token=token, existing='race')
    assert stage.main([], runner=runner, prompt=lambda _prompt: 'yes',
                      owner=__import__('os').getuid()) == 2
    output = capsys.readouterr().out
    assert 'stage refused: unsafe token file' in output
    assert (first / 'tunnel-token').is_symlink()
    assert (first / 'token-target').read_text() == 'pre-existing target contents'
    assert token not in output


def test_stage_connector_token_is_written_only_to_private_file(capture, tmp_path, monkeypatch, capsys):
    first, second = capture
    token = 'Q' * 48
    stage, calls, runner, _secret_calls = _stage_stub(monkeypatch, tmp_path, first, second, token=token)
    assert stage.main([], runner=runner, prompt=lambda _prompt: 'yes',
                      owner=__import__('os').getuid()) == 0
    captured = capsys.readouterr()
    assert token not in captured.out + captured.err
    assert token not in repr(calls)
    assert _secret_calls == ['Paste the tunnel connector token (hidden): ']
    for base in (first, second):
        for path in base.rglob('*'):
            if path.is_file() and path != first / 'tunnel-token':
                assert token not in path.read_text(errors='replace')
    assert (first / 'tunnel-token').read_text() == token


@pytest.mark.parametrize('source,dest,event', [('access_ca.pub', 'access_ca.pub', 'install-ca'),
                                               ('c7_key.pub', 'c7_authorized_keys', 'install-c7-key')])
def test_rootd_install_rejects_unsafe_inputs(rootd_fixture, source, dest, event):
    import os
    driver, _ = rootd_fixture
    driver.verify()
    driver.open_scratch()
    ca = driver.scratch / 'ca'
    path = ca / source
    target = ca / 'source'
    target.write_text('ssh-ed25519 QUJD comment\n')
    path.symlink_to(target)
    driver.install(path.name, dest, event)
    assert not (driver.root / dest).exists()
    path.unlink()
    os.mkfifo(path)
    driver.install(path.name, dest, event)
    assert not (driver.root / dest).exists()
    path.unlink()
    path.write_text('x' * 16384)
    driver.install(path.name, dest, event)
    assert not (driver.root / dest).exists()
    path.write_text('not a key')
    driver.install(path.name, dest, event)
    assert not (driver.root / dest).exists()
    path.write_text('ssh-ed25519 QUJD comment\n')
    driver.install(path.name, dest, event)
    assert (driver.root / dest).read_text() == 'ssh-ed25519 QUJD\n'


def test_rootd_unknown_request_is_not_acted_on(rootd_fixture, monkeypatch):
    driver, _ = rootd_fixture
    driver.open_scratch()
    seen = []
    monkeypatch.setattr(driver, 'act', seen.append)
    (driver.scratch / 'req/0001-unknown').touch()
    (driver.scratch / 'req/0002-down').touch()
    assert driver.poll() == 1
    assert seen == ['down']
    assert (driver.scratch / 'req/0001-unknown').exists()


def test_rootd_install_c7_positive_control(rootd_fixture):
    driver, _ = rootd_fixture
    driver.verify()
    driver.open_scratch()
    (driver.scratch / 'ca/c7_key.pub').write_text('ssh-ed25519 QUJD fixture\n')
    driver.install('c7_key.pub', 'c7_authorized_keys', 'install-c7-key')
    assert (driver.root / 'c7_authorized_keys').read_text() == 'ssh-ed25519 QUJD\n'


def test_isolation_realpath_deny_even_inside_allowlist(monkeypatch):
    monkeypatch.setattr(isolation, 'scratch_dirs', lambda create=False: (Path('/etc/k3dm-web-console'), Path('/unused')))
    for path in ('/etc/k3dm-web-console/a', '/private/etc/k3dm-web-console/a'):
        with pytest.raises(isolation.Refused):
            isolation.check_write(path)
    isolation.check_label('com.k3d-manager.capture-sshd')


def test_rootd_readback_stops_bootstrap(rootd_fixture, monkeypatch):
    driver, calls = rootd_fixture
    monkeypatch.setattr(driver, 'pid', lambda: None)
    monkeypatch.setattr(driver, '_generate_key', lambda: None)
    monkeypatch.setattr(driver, '_readback', lambda profile, data: False)
    with pytest.raises(ValueError, match='readback'):
        driver.up('c5')
    assert not any('bootstrap' in call for call in calls)
    assert any('/usr/sbin/sshd' in call for call in calls)


def test_rootd_environment_does_not_override(rootd_fixture, monkeypatch):
    import rootd
    driver, _ = rootd_fixture
    monkeypatch.setenv('WCB_CAPTURE_ROOT_OVERRIDE', '/tmp/forbidden')
    rebuilt = rootd.RootDriver(driver.root, owner=driver.owner, idle_timeout=5)
    assert rebuilt.root == driver.root
    assert rebuilt.idle_timeout == 5


def _readback_fixture(driver, profile):
    ca = 'none' if profile == 'c7' else str(driver.root / ('c13_ca.pub' if profile.startswith('c13-') else 'access_ca.pub'))
    keys = str(driver.root / 'c7_authorized_keys') if profile == 'c7' else 'none'
    return '\n'.join([
        'listenaddress 127.0.0.1:42723', 'port 42723', 'allowusers tester', 'permitrootlogin no',
        'passwordauthentication no', 'kbdinteractiveauthentication no', 'usepam no',
        'authenticationmethods publickey', 'disableforwarding yes', 'permituserenvironment no',
        'pidfile none', 'loglevel VERBOSE', 'hostkey ' + str(driver.root / 'host_key'),
        'setenv ZDOTDIR=' + str(driver.root / 'zdotdir'),
        'forcecommand ' + str(driver.root / 'recorder.py') + ' ' + profile,
        'authorizedkeysfile ' + keys, 'trustedusercakeys ' + ca,
        'authorizedprincipalscommand none', 'authorizedprincipalsfile none',
    ])


@pytest.mark.parametrize('profile', ['c7', 'c13-ca1', 'c13-ca2', 'c4-login2'])
def test_rootd_readback_profile_tables(rootd_fixture, profile):
    driver, _ = rootd_fixture
    data = _readback_fixture(driver, profile)
    assert driver._readback(profile, data)
    assert not driver._readback(profile, data.replace('permitrootlogin no', 'permitrootlogin yes'))
    assert not driver._readback(profile, '\n'.join(line for line in data.splitlines() if not line.startswith('setenv ')))
    if profile == 'c4-login2':
        assert not driver._readback(profile, data.replace('authorizedprincipalscommand none', 'authorizedprincipalscommand evil'))


def test_rootd_scratch_path_and_mode(rootd_fixture):
    driver, _ = rootd_fixture
    driver.open_scratch()
    driver.scratch.chmod(0o755)
    with pytest.raises(ValueError):
        driver.open_scratch()
    driver.scratch.chmod(0o700)
    driver.scratch = driver.scratch.parent / 'elsewhere' / driver.scratch.name
    with pytest.raises(ValueError):
        driver.open_scratch()


def test_rootd_c13_refuses_pid_change(rootd_fixture, monkeypatch):
    driver, _ = rootd_fixture
    (driver.root / 'c13').mkdir()
    (driver.root / 'c13/ca2.pub').write_text('ca2')
    driver.profile = 'c13-ca1'
    pids = iter([42, 43])
    monkeypatch.setattr(driver, 'pid', lambda: next(pids))
    with pytest.raises(RuntimeError, match='pid changed'):
        driver._c13_switch('c13-ca2')
    assert 'c13 pid before 42 after 43' in (driver.root / 'root-steps.log').read_text()


def test_rootd_input_wrong_owner(rootd_fixture):
    driver, _ = rootd_fixture
    driver.open_scratch()
    (driver.scratch / 'ca/access_ca.pub').write_text('ssh-ed25519 QUJD comment\n')
    driver.login_uid += 1
    driver.install('access_ca.pub', 'access_ca.pub', 'install-ca')
    assert not (driver.root / 'access_ca.pub').exists()
    driver.login_uid -= 1
    driver.install('access_ca.pub', 'access_ca.pub', 'install-ca')
    assert (driver.root / 'access_ca.pub').exists()


def test_rootd_up_requires_matching_listener_and_root_owner(rootd_fixture, monkeypatch):
    import types
    driver, _ = rootd_fixture
    state = {'started': False, 'listener': 59967, 'uid': '0'}
    calls = []
    # Netstat shape captured on m4-air, 2026-11-19: c12-netstat-up-root.txt.
    line = ('tcp4 0 0 127.0.0.1.42723 *.* LISTEN 0 0 131072 131072 '
            'sshd:{pid} 00180 00000006')

    def runner(argv):
        calls.append(argv)
        if argv[:2] == ['/bin/launchctl', 'print']:
            return types.SimpleNamespace(returncode=0 if state['started'] else 113,
                                         stdout='pid = 59966' if state['started'] else '')
        if argv[:2] == ['/bin/launchctl', 'bootstrap']:
            state['started'] = True
        if argv[0] == '/usr/sbin/netstat':
            return types.SimpleNamespace(returncode=0,
                                         stdout=line.format(pid=state['listener']) if state['started'] else '')
        if argv[0] == '/usr/sbin/sshd':
            return types.SimpleNamespace(returncode=0, stdout=_readback_fixture(driver, 'c8'))
        if argv[0] == '/bin/ps':
            return types.SimpleNamespace(returncode=0, stdout=state['uid'])
        return types.SimpleNamespace(returncode=0, stdout='')

    driver.runner = runner
    monkeypatch.setattr(driver, '_generate_key', lambda: None)
    with pytest.raises(RuntimeError, match='listener pid'):
        driver.up('c8')
    assert not (driver.root / 'root-steps.log').exists()
    state.update(started=False, listener=59966, uid='501')
    with pytest.raises(RuntimeError, match='owner mismatch'):
        driver.up('c8')
    state.update(started=False, listener=59966, uid='0')
    driver.up('c8')
    assert 'up c8' in (driver.root / 'root-steps.log').read_text()
    assert {'/bin/launchctl', '/usr/sbin/netstat', '/usr/sbin/sshd', '/bin/ps'} <= {call[0] for call in calls}


@pytest.mark.parametrize('name', ['SIGINT', 'SIGHUP', 'SIGTERM'])
def test_rootd_signal_exits_boot_out(rootd_fixture, monkeypatch, name):
    import signal
    import rootd
    driver, calls = rootd_fixture
    handlers = {}
    monkeypatch.setattr(signal, 'signal', lambda number, handler: handlers.update({number: handler}))
    rootd._install_signals(driver)
    sig = getattr(signal, name)
    driver.sleep = lambda seconds: handlers[sig](sig, None)
    driver.run()
    assert any('bootout' in call for call in calls)
    assert 'exit ' + name in (driver.root / 'root-steps.log').read_text()


def test_rootd_idle_exits_boot_out(rootd_fixture):
    driver, calls = rootd_fixture
    ticks = iter([0, 10])
    driver.clock = lambda: next(ticks)
    driver.idle_timeout = 5
    driver.run()
    assert any('bootout' in call for call in calls)
    assert 'exit idle' in (driver.root / 'root-steps.log').read_text()


def test_rootd_quit_exits_boot_out(rootd_fixture):
    driver, calls = rootd_fixture
    driver.sleep = lambda seconds: (driver.scratch / 'req/0001-quit').touch()
    driver.run()
    assert any('bootout' in call for call in calls)
    assert 'exit quit' in (driver.root / 'root-steps.log').read_text()


def test_isolation_port_free_from_recorded_netstat(monkeypatch):
    import types
    calls = []
    # m4-air, 2026-11-19, docs/captures/2026-11-19-web-console/c12-netstat-up-root.txt.
    occupied = ('tcp4 0 0 127.0.0.1.42723 *.* LISTEN 0 0 131072 131072 '
                'sshd:59966 00180 00000006')
    state = {'output': occupied}

    def runner(argv):
        calls.append(argv)
        return types.SimpleNamespace(stdout=state['output'])

    monkeypatch.setattr(isolation, '_run_command', runner)
    assert not isolation.port_free()
    state['output'] = ''
    assert isolation.port_free()
    assert calls == [['/usr/sbin/netstat', '-anv', '-p', 'tcp']] * 2


@pytest.mark.parametrize('env,ancestors', [({'TMUX': 'x'}, []), ({'STY': 'x'}, []), ({}, ['screen'])])
def test_isolation_refuse_multiplexer(env, ancestors):
    with pytest.raises(isolation.Refused):
        isolation.refuse_multiplexer(env, ancestors)
    isolation.refuse_multiplexer({}, ['zsh'])


def test_isolation_cloudflared_allowlist():
    valid = [
        ['cloudflared', 'tunnel', '--config', 'x', 'ingress', 'validate'],
        ['cloudflared', 'tunnel', '--config', 'x', 'ingress', 'rule', 'https://example.test'],
        ['cloudflared', 'tunnel', '--no-autoupdate', '--loglevel', 'debug', '--logfile', 'x',
         'run', '--token-file', 'secret-file'],
    ]
    for argv in valid:
        isolation.check_cloudflared(argv, {})
    for argv in (['cloudflared', 'tunnel', '--config', 'x', 'login'],
                 ['cloudflared', 'tunnel', 'run', '--token', 'secret'],
                 ['cloudflared', 'tunnel', 'run', '--token=secret']):
        with pytest.raises(isolation.Refused):
            isolation.check_cloudflared(argv, {})


def test_rootd_principals_only_for_login(monkeypatch, capsys):
    import importlib.machinery
    import types
    path = Path(isolation.__file__).parent / 'templates/principals-any'
    loader = importlib.machinery.SourceFileLoader('capture_principals', str(path))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    calls = []

    def runner(argv, **kwargs):
        calls.append((argv, kwargs['input']))
        return types.SimpleNamespace(returncode=0, stdout='    Principals:\n        alice\n        bob\n    Critical Options:\n')

    monkeypatch.setattr(module, '_run_command', runner)
    monkeypatch.setattr(sys, 'argv', ['principals-any', 'alice', 'other', 'ssh-ed25519-cert-v01@openssh.com', 'AAA'])
    assert module.main() == 1
    assert calls == []
    monkeypatch.setattr(sys, 'argv', ['principals-any', 'alice', 'alice', 'ssh-ed25519-cert-v01@openssh.com', 'AAA'])
    assert module.main() == 0
    assert capsys.readouterr().out == 'alice\nbob\n'
    assert calls == [(['/usr/bin/ssh-keygen', '-L', '-f', '-'], 'ssh-ed25519-cert-v01@openssh.com AAA\n')]


@pytest.mark.parametrize('mode', [0o664, 0o646])
def test_rootd_refuses_writable_root_file(rootd_fixture, mode):
    driver, _ = rootd_fixture
    driver.verify()
    (driver.root / 'recorder.py').chmod(mode)
    with pytest.raises(ValueError):
        driver.verify()


def test_rootd_refuses_symlink_and_wrong_owner(rootd_fixture):
    driver, _ = rootd_fixture
    driver.verify()
    path = driver.root / 'recorder.py'
    original = path.read_bytes()
    path.unlink()
    path.symlink_to(driver.root / 'rootd.py')
    with pytest.raises(ValueError):
        driver.verify()
    path.unlink()
    path.write_bytes(original)
    driver.owner += 1
    with pytest.raises(ValueError):
        driver.verify()


def test_rootd_c13_generates_two_ca_certificates(rootd_fixture, monkeypatch):
    import os
    import stat
    import types
    driver, _ = rootd_fixture
    driver.open_scratch()
    for number in (1, 2):
        (driver.scratch / ('ca/c13_user%d.pub' % number)).write_text('ssh-ed25519 QUJD fixture\n')
        (driver.scratch / ('ca/c13_user%d' % number)).write_text('PRIVATE USER KEY')
    calls = []
    opened = []
    real_open = os.open

    def observe_open(path, *args, **kwargs):
        if kwargs.get('dir_fd') == driver.ca_fd:
            opened.append(str(path))
        return real_open(path, *args, **kwargs)

    def runner(argv):
        calls.append(argv)
        assert argv[0] == '/usr/bin/ssh-keygen'
        if '-f' in argv:
            key = Path(argv[argv.index('-f') + 1])
            assert key.is_relative_to(driver.root / 'c13')
            key.write_text('private ca fixture')
            Path(str(key) + '.pub').write_text('ssh-ed25519 QUJD fixture\n')
        elif '-s' in argv:
            assert argv[argv.index('-V') + 1] == '+1h'
            assert argv[argv.index('-n') + 1] == 'tester'
            public = Path(argv[-1])
            public.with_name(public.stem + '-cert.pub').write_text('certificate fixture')
        return types.SimpleNamespace(returncode=0, stdout='')

    driver.runner = runner
    monkeypatch.setattr(os, 'open', observe_open)
    driver._c13_init()
    assert opened == ['c13_user1.pub', 'c13_user2.pub']
    assert stat.S_IMODE((driver.root / 'c13').stat().st_mode) == 0o755
    for number in (1, 2):
        ca = driver.root / ('c13/ca%d' % number)
        cert = driver.root / ('c13/c13_user%d-cert.pub' % number)
        assert stat.S_IMODE(ca.stat().st_mode) == 0o600
        assert stat.S_IMODE(Path(str(ca) + '.pub').stat().st_mode) == 0o644
        assert stat.S_IMODE(cert.stat().st_mode) == 0o644
    assert len(calls) == 4


@pytest.mark.parametrize('number,kind', [(n, k) for n in (1, 2) for k in ('missing', 'invalid', 'symlink')])
def test_rootd_c13_refuses_invalid_user_keys(rootd_fixture, number, kind):
    driver, calls = rootd_fixture
    driver.open_scratch()
    ca = driver.scratch / 'ca'
    for n in (1, 2):
        (ca / ('c13_user%d.pub' % n)).write_text('ssh-ed25519 QUJD fixture\n')
    target = ca / ('c13_user%d.pub' % number)
    if kind == 'missing':
        target.unlink()
    elif kind == 'invalid':
        target.write_text('bad key')
    else:
        target.unlink()
        target.symlink_to(ca / ('c13_user%d.pub' % (3 - number)))
    with pytest.raises((OSError, ValueError)):
        driver.up('c13-ca1')
    assert not any('bootstrap' in call for call in calls)
    assert not (driver.root / 'c13').exists()


def test_rootd_cli_rejects_override_options(monkeypatch):
    import rootd
    seen = []

    class FakeDriver:
        def __init__(self, *args, **kwargs):
            seen.append((args, kwargs))

        def run(self):
            seen.append('ran')

    monkeypatch.setattr(rootd, '__file__', '/private/var/db/k3dm-capture-2026-11-28/rootd.py')
    monkeypatch.setattr(rootd, 'RootDriver', FakeDriver)
    monkeypatch.setattr(rootd, '_install_signals', lambda driver: None)
    monkeypatch.setenv('WCB_CAPTURE_ROOT_OVERRIDE', '/tmp/forbidden')
    assert rootd.main(['--scratch', '/private/tmp/k3dm-captures-2026-11-28', '--login', 'tester']) == 0
    assert seen[0][0][0] == Path('/private/var/db/k3dm-capture-2026-11-28')
    assert seen[0][1] == {} and seen[1] == 'ran'
    for option in ('--root', '--timeout', '--owner'):
        with pytest.raises(SystemExit) as error:
            rootd.main([option, '1'])
        assert error.value.code == 2


def test_rootd_preserves_operator_scratch_snapshot(rootd_fixture):
    driver, calls = rootd_fixture
    request = driver.scratch / 'req/0001-down'
    request.write_bytes(b'operator-owned bytes')
    driver.open_scratch()
    request = driver.scratch / 'req/0002-down'
    request.write_bytes(b'another operator-owned request')

    def snapshot():
        return {str(path.relative_to(driver.scratch)): (path.is_dir(), path.read_bytes() if path.is_file() else None)
                for path in driver.scratch.rglob('*')}

    before = snapshot()
    driver.poll()
    assert snapshot() == before
    assert any('bootout' in call for call in calls)


def test_rootd_first_key_and_rekey(rootd_fixture):
    import types
    driver, _ = rootd_fixture
    calls = []

    def runner(argv):
        calls.append(argv)
        assert argv[:4] == ['/usr/bin/ssh-keygen', '-q', '-t', 'ed25519']
        key = Path(argv[argv.index('-f') + 1])
        assert key == driver.root / 'host_key'
        key.write_text('host key generation %d' % len(calls))
        Path(str(key) + '.pub').write_text('public key generation %d' % len(calls))
        return types.SimpleNamespace(returncode=0, stdout='')

    driver.runner = runner
    driver._generate_key()
    driver._generate_key()
    assert len(calls) == 1
    driver.act('rekey')
    assert len(calls) == 2
    assert (driver.root / 'host_key').read_text() == 'host key generation 2'
    assert 'rekey' in (driver.root / 'root-steps.log').read_text()


def test_rootd_teardown_refuses_outside_pattern(rootd_fixture, tmp_path):
    import rootd
    driver, calls = rootd_fixture
    outside = tmp_path / 'not-a-capture'
    outside.mkdir()
    (outside / 'keep').write_text('untouched')
    invalid = rootd.RootDriver(outside, owner=driver.owner, runner=driver.runner, root_parent=tmp_path)
    with pytest.raises(ValueError):
        invalid.teardown()
    assert (outside / 'keep').read_text() == 'untouched'
    assert not calls
    driver.teardown()
    assert not driver.root.exists()
    assert any('bootout' in call for call in calls)
