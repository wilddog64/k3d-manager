"""CLI e2e scope checks using injected recording command runners."""
import importlib.util
from importlib.machinery import SourceFileLoader
import json
import os
from pathlib import Path
import sys
from types import SimpleNamespace

import pytest

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'scripts' / 'lib'))


def _cli():
    path = ROOT / 'bin/k3dm-wcb-capture'
    loader = SourceFileLoader('wcb_cli_e2e', str(path))
    spec = importlib.util.spec_from_loader('wcb_cli_e2e', loader)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


@pytest.fixture
def campaign(tmp_path, monkeypatch):
    from wcb_capture import api, c8c9, collect, isolation, rootchecks, stage, supervisor

    opbase, rootbase = tmp_path / 'operator', tmp_path / 'root'
    opbase.mkdir(); rootbase.mkdir()
    monkeypatch.setattr(isolation, 'OPERATOR_BASE', opbase)
    monkeypatch.setattr(isolation, 'ROOT_BASE', rootbase)
    operator, root = isolation.scratch_dirs(create=True)
    root.mkdir()
    assert operator.is_relative_to(tmp_path) and root.is_relative_to(tmp_path)
    (root / 'root-steps.log').write_text('[root 00:00:00] start\n')
    (root / 'sshd.log').write_text('')
    (root / 'access_ca.pub').write_text('ssh-ed25519 AAAA')
    (operator / 'browser').mkdir()
    (operator / 'cfhome').mkdir()
    token = operator / 'tunnel-token'; token.write_text('fixture-token'); token.chmod(0o600)

    calls = []
    def record(name, argv):
        calls.append((name, list(argv)))

    class Runner:
        def __init__(self): self.hash_count = 0
        def __call__(self, argv, **kwargs):
            name = Path(argv[0]).name if argv else 'empty'
            if argv and argv[0] == 'cloudflared': name = 'cloudflared'
            record(name, argv)
            if name == 'git':
                if argv[1:3] == ['status', '--porcelain']:
                    stdout = b''
                elif argv[1:3] == ['rev-parse', 'HEAD']:
                    stdout = b'fakecommit\n'
                elif argv[1:2] == ['rev-parse']:
                    stdout = b'0123456789abcdef0123456789abcdef01234567\n'
                elif argv[1:2] == ['show']:
                    stdout = b'fixture staged content\n'
                else: stdout = b''
            elif name == 'security':
                stdout = 'T' * 32 + '\n' if '-w' in argv else ''
            elif name == 'curl':
                body = {'result': {'public_key': 'ssh-ed25519 AAAAB3NzaC1yc2EAAAADAQAB'}} if '/ca' in kwargs.get('input', '') else {'result': {'status': 'healthy'}}
                stdout = json.dumps(body)
            elif name == 'ssh-keyscan':
                stdout = '127.0.0.1 ssh-ed25519 AAAAfixture\n'
            elif name == 'ssh-keygen' and '-f' in argv:
                private = Path(argv[-1]); private.write_text('private fixture\n')
                Path(str(private) + '.pub').write_text('ssh-ed25519 AAAAfixture tester\n')
                stdout = ''
            elif name == 'ssh-keygen':
                self.hash_count += 1
                current = 'SHA256:hash-a' if self.hash_count <= 3 else 'SHA256:hash-b'
                stdout = '256 %s comment-%d (ED25519)\n' % (current, self.hash_count)
            elif name == 'ssh':
                stdout = ''
            elif name == 'sudo':
                stdout = ''
                if argv[-1:] == ['--teardown']:
                    import shutil
                    shutil.rmtree(root, ignore_errors=True)
            elif name == 'sshd':
                stdout = ''
            else:
                stdout = ''
            if name == 'cloudflared':
                with (operator / 'connector.log').open('a') as stream:
                    stream.write('request arrived at connector\n')
            return SimpleNamespace(returncode=0, stdout=stdout, stderr='stub error' if name == 'cloudflared' else '')

    runner = Runner()
    monkeypatch.setattr(isolation, 'check_port', lambda port: (None if port == 42723 else (_ for _ in ()).throw(AssertionError(port))))
    monkeypatch.setattr(isolation, 'port_free', lambda port=42723: port == 42723)
    monkeypatch.setattr(isolation, 'refuse_multiplexer', lambda *_args: None)
    monkeypatch.setattr(isolation, 'check_write', lambda path, mode='operator': _assert_scoped(path, operator, root, ROOT))

    # A root-driver stand-in consumes name-only requests and records its sshd action.
    requests = []
    def submit(verb):
        requests.append(verb)
        req = operator / 'req'; req.mkdir(exist_ok=True)
        path = req / ('%04d-%s' % (len(requests), verb)); path.touch()
        if verb.startswith('up-'):
            record('sshd', ['/usr/sbin/sshd', '-f', str(root / 'sshd_config'), '-p', '42723'])
            with (root / 'root-steps.log').open('a') as stream: stream.write('[root 00:00:01] up %s\n' % verb[3:])
            if verb == 'up-c8':
                pass
            else:
                (operator / 'browser' / ('done-' + verb[3:])).touch()
        elif verb == 'down':
            with (root / 'root-steps.log').open('a') as stream: stream.write('[root 00:00:02] down\n')
        return len(requests)

    monkeypatch.setattr(supervisor.requests, 'submit', submit)
    monkeypatch.setattr(c8c9.requests, 'submit', submit)
    monkeypatch.setattr(rootchecks.requests, 'submit', submit)
    monkeypatch.setattr(stage.os, 'getlogin', lambda: 'tester')
    monkeypatch.setattr(rootchecks.os, 'getlogin', lambda: 'tester')
    monkeypatch.setattr(rootchecks, '_wait', lambda *_args, **_kwargs: True)
    fake_repo = tmp_path / 'fake-repo'; fake_repo.mkdir()
    written_paths = []
    original_write_text, original_write_bytes = Path.write_text, Path.write_bytes
    original_touch, original_mkdir = Path.touch, Path.mkdir
    def tracked_write_text(path, *args, **kwargs):
        written_paths.append(Path(path).resolve()); return original_write_text(path, *args, **kwargs)
    def tracked_write_bytes(path, *args, **kwargs):
        written_paths.append(Path(path).resolve()); return original_write_bytes(path, *args, **kwargs)
    def tracked_touch(path, *args, **kwargs):
        written_paths.append(Path(path).resolve()); return original_touch(path, *args, **kwargs)
    def tracked_mkdir(path, *args, **kwargs):
        written_paths.append(Path(path).resolve()); return original_mkdir(path, *args, **kwargs)
    monkeypatch.setattr(Path, 'write_text', tracked_write_text)
    monkeypatch.setattr(Path, 'write_bytes', tracked_write_bytes)
    monkeypatch.setattr(Path, 'touch', tracked_touch)
    monkeypatch.setattr(Path, 'mkdir', tracked_mkdir)
    monkeypatch.setattr(stage, 'REPO', fake_repo)
    monkeypatch.setattr(stage.subprocess, 'run', runner)
    monkeypatch.setattr(rootchecks.subprocess, 'run', runner)
    monkeypatch.setattr(supervisor.subprocess, 'run', runner)
    monkeypatch.setattr(c8c9.subprocess, 'run', runner)
    monkeypatch.setattr(collect.subprocess, 'run', runner)
    monkeypatch.setattr(stage.main, '__defaults__', (stage._run_command, lambda _prompt: 'yes', os.getuid()))
    monkeypatch.setattr(collect.main_collect, '__defaults__', (None, lambda _prompt: 'n', print))
    monkeypatch.setattr(collect.main_down, '__defaults__', (None, runner, lambda _prompt: 'discard', print))

    original_api_init = api.Api.__init__
    api_answers = iter(['a' * 32, 'b' * 32, 'c' * 32, 'capture.example.net', 'team-name', 'n'])
    def api_init(instance, *args, **kwargs):
        kwargs.update(runner=runner, binary_dir=tmp_path / 'stubs',
                      input_fn=lambda _prompt: next(api_answers), output_fn=lambda _line: None,
                      sleeper=lambda _delay: None)
        original_api_init(instance, *args, **kwargs)
    monkeypatch.setattr(api.Api, '__init__', api_init)

    monkeypatch.setattr(c8c9, 'input', lambda prompt='': (
        'n' if 'other app' in prompt else 'capture.example.net' if 'hostname' in prompt.lower() else ''), raising=False)
    monkeypatch.setattr(c8c9, '_wait_line', lambda *_args, **_kwargs: True)
    monkeypatch.setattr(supervisor, 'input', lambda _prompt='': '', raising=False)
    monkeypatch.setattr(supervisor, 'Supervisor', _inject_supervisor(supervisor.Supervisor, runner, operator, root))
    monkeypatch.setattr(rootchecks.main, '__defaults__', (None, runner, print))
    monkeypatch.setattr(c8c9.main_c8, '__defaults__', (None, runner, None, print, None, None))
    monkeypatch.setattr(c8c9.main_c9, '__defaults__', (None, runner, None, print))

    def cli_runner(argv, **kwargs):
        name = Path(argv[0]).name
        record(name, argv)
        if name == 'launchctl': return SimpleNamespace(returncode=1, stdout='', stderr='')
        if name == 'netstat': return SimpleNamespace(returncode=0, stdout='', stderr='')
        if name == 'sudo': return SimpleNamespace(returncode=0, stdout='ok\n', stderr='')
        return runner(argv, **kwargs)

    return SimpleNamespace(tmp_path=tmp_path, operator=operator, root=root, calls=calls,
                           requests=requests, runner=runner, cli_runner=cli_runner,
                           written_paths=written_paths, fake_repo=fake_repo)


def _inject_supervisor(cls, runner, operator, root):
    original = cls.__init__
    def init(self, *args, **kwargs):
        kwargs.update(runner=runner, output=lambda _line: None, env={}, sleeper=lambda _delay: None, timeout=.01)
        original(self, *args, **kwargs)
        # Done markers let browser-up exercise resume without waiting for Safari.
        for name in ('c5', 'c5-exit', 'c5-notty', 'c4-login1', 'c4-login2'):
            (operator / 'browser' / ('done-' + name)).touch()
        (operator / 'browser' / 'done-c15-a').touch()
        (operator / 'browser' / 'c15-a-hash').write_text('SHA256:hash-old\n')
        # c15-b is executed to prove the new served hash is compared by field 2.
        with (root / 'root-steps.log').open('a') as stream: stream.write('[root 00:00:00] up c15-b\n')
        return None
    return type('InjectedSupervisor', (cls,), {'__init__': init})


def _assert_scoped(path, operator, root, repo):
    target = Path(path).resolve()
    allowed = (operator.resolve(), root.resolve(), (repo / 'docs/captures').resolve())
    if not any(target == base or base in target.parents for base in allowed):
        raise AssertionError('write outside scratch/collect roots: ' + str(target))


def test_all_cli_subcommands_use_recording_stubs_and_stay_in_scratch(campaign, monkeypatch):
    cli = _cli()
    monkeypatch.setattr(cli, '_ancestors', lambda: [])
    commands = ('stage', 'api', 'browser-up', 'c8', 'c9', 'root-checks', 'status', 'c14-plain', 'collect', 'down')
    expected_codes = {'stage': 0, 'api': 0, 'browser-up': 0, 'c8': 3, 'c9': 0,
                      'root-checks': 0, 'status': 0, 'c14-plain': 0, 'collect': 0, 'down': 0}
    for command in commands:
        assert cli.main([command], runner=campaign.cli_runner) == expected_codes[command]
    # Catch any command-line construction that would broaden the capture.
    observed = {name for name, _argv in campaign.calls}
    for required in ('launchctl', 'sudo', 'netstat', 'sshd', 'curl', 'security', 'cloudflared', 'ssh'):
        assert required in observed, 'recording stub was not called: ' + required
    for name, argv in campaign.calls:
        assert '42722' not in argv
        assert not any(arg in ('create', 'login', '--token') or arg.startswith('--token=') for arg in argv)
        if name == 'sshd': assert '42723' in argv
        if name == 'cloudflared': assert argv[:3] == ['cloudflared', 'access', 'ssh']
        if name == 'sudo': assert argv[0] == '/usr/bin/sudo'
        labels = [arg for arg in argv if arg.startswith('com.k3d-manager.')]
        assert all(label == 'com.k3d-manager.capture-sshd' for label in labels)
    assert all(p.is_relative_to(campaign.tmp_path) for p in (campaign.operator, campaign.root))
    allowed = (campaign.operator.resolve(), campaign.root.resolve(),
               (campaign.fake_repo / 'docs' / 'captures').resolve())
    assert all(any(path == base or base in path.parents for base in allowed)
               for path in campaign.written_paths)
    assert not campaign.operator.exists()  # down removed only the fake (1)
    assert not campaign.root.exists()


