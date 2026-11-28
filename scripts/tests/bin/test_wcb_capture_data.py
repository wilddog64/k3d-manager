"""Offline privacy and CLI tests for the capture kit data side."""
import json
import importlib.util
from importlib.machinery import SourceFileLoader
from pathlib import Path
import shutil
from types import SimpleNamespace
import sys

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'lib'))

from wcb_capture import filters, scan
from wcb_capture import collect
from wcb_capture import api


def _load_cli(name):
    path = Path(__file__).resolve().parents[3] / 'bin/k3dm-wcb-capture'
    loader = SourceFileLoader(name, str(path))
    spec = importlib.util.spec_from_loader(name, loader)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_filter_and_scan_allow_capture_log_fixtures(tmp_path):
    root = Path(__file__).resolve().parents[3]
    fixtures = root / 'docs/captures/2026-11-19-web-console'
    terms = tmp_path / 'terms'
    terms.write_text('unmatched-private-term\n')
    for name in ('sshd-prod.log', 'c17-readback.txt', 'root-steps.log'):
        source = fixtures / name
        cleaned = filters.filter_text(source.read_text(), 'sshd', terms=['<login>'], login='<login>')
        target = tmp_path / name
        target.write_text(cleaned)
        assert scan.scan_file(target, terms_path=terms) == []


@pytest.mark.parametrize('value, expected', [
    ('127.0.0.1', False), ('0.0.0.0', False), ('192.168.1.2', True),
    ('::1', False), ('2001:db8::1', True), ('12:34:56', False),
])
def test_scan_address_rules(tmp_path, value, expected):
    target = tmp_path / 'capture.txt'
    target.write_text(value + '\n')
    assert bool(scan.scan_file(target, terms_path=tmp_path / 'missing')) is expected


def test_scan_reports_names_and_lines_without_match_text(tmp_path):
    target = tmp_path / 'capture.txt'
    target.write_text('safe\nBearer secret-token-value\n')
    hits = scan.scan_file(target, terms_path=tmp_path / 'missing')
    assert [(hit.pattern, hit.line) for hit in hits] == [('bearer', 2)]
    assert 'secret-token-value' not in repr(hits)


def test_scan_blocks_pre_filtered_email_without_echoing_it(tmp_path):
    target = tmp_path / 'pre-filtered.txt'
    target.write_text('contact private@example.org\n')
    hits = scan.scan_file(target, terms_path=tmp_path / 'missing')
    assert [(hit.pattern, hit.line) for hit in hits] == [('email', 1)]
    assert 'private@example.org' not in repr(hits)


def test_scan_reads_each_term_from_terms_file(tmp_path):
    target = tmp_path / 'pre-filtered.txt'
    terms = tmp_path / 'terms'
    target.write_text('account-sentinel-1234\n')
    terms.write_text('account-sentinel-1234\n')
    hits = scan.scan_file(target, terms_path=terms)
    assert [(hit.pattern, hit.line) for hit in hits] == [('term', 1)]
    assert 'account-sentinel-1234' not in repr(hits)


def test_json_filter_redacts_identifiers_and_key_body():
    filtered = filters.filter_json({
        'id': 'abc123', 'email': 'user@example.org', 'ca': {'public_key': 'ssh-ed25519 AAAAB3NzaC1yc2EAAAADAQAB'}})
    rendered = json.dumps(filtered)
    assert 'abc123' not in rendered
    assert 'user@example.org' not in rendered
    assert 'AAAAB3' not in rendered


def test_capture_header_supports_text_and_json():
    text_header = filters.format_capture_header(cloudflared='1.2', sshd='9.9', ssh='9.9')
    json_header = filters.capture_header(cloudflared='1.2', sshd='9.9', ssh='9.9')
    assert text_header.startswith('# host m4-air · ')
    assert text_header.endswith('· cloudflared 1.2 · sshd 9.9 · ssh 9.9 · macOS ' + (json_header['macOS']))
    assert json_header['host'] == 'm4-air'


def test_api_token_only_enters_curl_stdin_and_curl_is_get(tmp_path, capsys):
    token = 'A' * 32
    calls = []
    answers = iter(['a' * 32, 'b' * 32, 'c' * 32, 'throwaway.example.net', 'team-name', 'n'])

    def runner(argv, **kwargs):
        calls.append((argv, kwargs))
        if argv[0].endswith('/security') and '-w' in argv:
            return SimpleNamespace(returncode=0, stdout=token + '\n', stderr='')
        if argv[0].endswith('/security'):
            return SimpleNamespace(returncode=0, stdout='', stderr='')
        if 'curl' in argv[0]:
            response = {'result': {'public_key': 'ssh-ed25519 AAAAB3NzaC1yc2EAAAADAQAB comment'}}
            return SimpleNamespace(returncode=0, stdout=json.dumps(response), stderr='')
        raise AssertionError('unexpected command')

    scratch = tmp_path / 'k3dm-captures-2026-01-02'
    scratch.mkdir(mode=0o700)
    assert scratch.parent == tmp_path
    monkeypatch = pytest.MonkeyPatch()
    monkeypatch.setattr(api.isolation, 'scratch_dirs', lambda create=False: (scratch, tmp_path / 'root'))
    monkeypatch.setattr(api.isolation, 'check_write', lambda *_args, **_kwargs: None)
    result = api.Api(runner=runner, binary_dir=tmp_path / 'stub',
                     input_fn=lambda _prompt: next(answers), output_fn=lambda _line: None,
                     sleeper=lambda _seconds: None).run()
    assert result == 0
    security_calls = [call for call in calls if call[0][0].endswith('/security')]
    assert [call[0] for call in security_calls] == [
        [str(tmp_path / 'stub/security'), 'find-generic-password', '-s', api.TOKEN_ITEM],
        [str(tmp_path / 'stub/security'), 'find-generic-password', '-s', api.TOKEN_ITEM, '-w'],
    ]
    assert all(call[1]['env'] == {'PATH': '/usr/bin:/bin'} for call in security_calls)
    curl_calls = [call for call in calls if 'curl' in call[0][0]]
    assert len(curl_calls) == 8
    account, app, tunnel = 'a' * 32, 'b' * 32, 'c' * 32
    endpoints = [
        '/accounts/' + account + '/access/apps',
        '/accounts/' + account + '/access/apps/' + app,
        '/accounts/' + account + '/access/apps/' + app + '/policies',
        '/accounts/' + account + '/access/identity_providers',
        '/accounts/' + account + '/access/organizations',
        '/accounts/' + account + '/access/apps/' + app + '/ca',
        '/accounts/' + account + '/access/apps/' + app + '/ca',
        '/accounts/' + account + '/cfd_tunnel/' + tunnel,
    ]
    for (argv, kwargs), endpoint in zip(curl_calls, endpoints):
        assert argv == [str(tmp_path / 'stub/curl'), '-q', '--config', '-']
        assert kwargs['input'] == '\n'.join([
            'url = "https://api.cloudflare.com/client/v4' + endpoint + '"',
            'header = "Authorization: Bearer ' + token + '"',
            'request = "GET"', 'proto = "=https"', 'fail-with-body',
            'max-time = 30', 'silent', 'show-error', '',
        ])
        assert '--data' not in argv
        assert 'data =' not in kwargs['input']
        assert token not in repr(argv)
        assert 'POST' not in kwargs['input']
    assert all(call[1]['env'] == {'PATH': '/usr/bin:/bin'} for call in calls)
    ca_capture = json.loads((scratch / 'filtered' / 'ca-1.json').read_text())
    assert ca_capture['algorithm'] == 'ssh-ed25519'
    assert ca_capture['body_length'] == len('AAAAB3NzaC1yc2EAAAADAQAB')
    assert set(ca_capture) == {'algorithm', 'body_length', '_capture_header'}
    assert (scratch / 'ca' / 'access_ca.pub').read_text() == 'ssh-ed25519 AAAAB3NzaC1yc2EAAAADAQAB\n'
    assert all(token not in str(path.read_bytes()) for path in scratch.rglob('*') if path.is_file())
    captured = capsys.readouterr()
    assert token not in captured.out + captured.err
    monkeypatch.undo()


def test_api_rejects_invalid_id_before_token_read_and_token_validation_is_private(tmp_path, capsys):
    calls = []

    def runner(argv, **kwargs):
        calls.append(argv)
        return SimpleNamespace(returncode=0, stdout='short-secret' if '-w' in argv else '', stderr='')

    scratch = tmp_path / 'k3dm-captures-2026-01-02'
    scratch.mkdir(mode=0o700)
    patcher = pytest.MonkeyPatch()
    patcher.setattr(api.isolation, 'scratch_dirs', lambda create=False: (scratch, tmp_path / 'root'))
    patcher.setattr(api.isolation, 'check_write', lambda *_args, **_kwargs: None)
    answers = iter(['invalid-account-id', 'app', 'tunnel', 'host', 'team'])
    with pytest.raises(ValueError, match='account id validation failed'):
        api.Api(runner=runner, binary_dir=tmp_path / 'stub', input_fn=lambda _prompt: next(answers)).run()
    assert calls == []
    answers = iter(['a' * 32, 'b' * 32, 'c' * 32, 'host.example', 'team', 'n'])
    with pytest.raises(ValueError, match='token validation failed'):
        api.Api(runner=runner, binary_dir=tmp_path / 'stub', input_fn=lambda _prompt: next(answers)).run()
    assert 'short-secret' not in capsys.readouterr().out
    assert 'short-secret' not in capsys.readouterr().err
    patcher.undo()


def test_api_error_handler_never_prints_exception_contents(monkeypatch, capsys):
    secret = 'A' * 32

    class FailedApi:
        def __init__(self):
            pass

        def run(self, _after_disable):
            raise RuntimeError(secret)

    monkeypatch.setattr(api, 'Api', FailedApi)
    assert api.main([]) == 1
    captured = capsys.readouterr()
    assert secret not in captured.out + captured.err


def test_api_records_sanitized_403_endpoint_and_code(tmp_path):
    token = 'B' * 32
    calls = []
    answers = iter(['a' * 32, 'b' * 32, 'c' * 32, 'throwaway.example.net', 'team-name', 'n'])

    def runner(argv, **kwargs):
        calls.append((argv, kwargs))
        if argv[0].endswith('/security') and '-w' in argv:
            return SimpleNamespace(returncode=0, stdout=token, stderr='')
        if argv[0].endswith('/security'):
            return SimpleNamespace(returncode=0, stdout='', stderr='')
        if len([item for item in calls if 'curl' in item[0][0]]) == 1:
            return SimpleNamespace(returncode=22, stdout=json.dumps({'errors': [{'code': 10000}]}),
                                   stderr='curl: (22) The requested URL returned error: 403')
        return SimpleNamespace(returncode=0, stdout=json.dumps({'result': {'public_key':
                                   'ssh-ed25519 AAAAB3NzaC1yc2EAAAADAQAB'}}), stderr='')

    scratch = tmp_path / 'k3dm-captures-2026-01-02'
    scratch.mkdir(mode=0o700)
    patcher = pytest.MonkeyPatch()
    patcher.setattr(api.isolation, 'scratch_dirs', lambda create=False: (scratch, tmp_path / 'root'))
    patcher.setattr(api.isolation, 'check_write', lambda *_args, **_kwargs: None)
    api.Api(runner=runner, binary_dir=tmp_path / 'stub', input_fn=lambda _prompt: next(answers),
            output_fn=lambda _line: None, sleeper=lambda _seconds: None).run()
    recorded = json.loads((scratch / 'raw' / 'apps.json').read_text())
    assert recorded['error'] == '403 on /accounts/{account_id}/access/apps, code 10000'
    assert token not in recorded['error']
    patcher.undo()


def test_api_after_disable_repeats_only_app_get(tmp_path):
    token = 'C' * 32
    calls = []
    answers = iter(['a' * 32, 'b' * 32, 'c' * 32, 'throwaway.example.net', 'team-name', 'n'])

    def runner(argv, **kwargs):
        calls.append((argv, kwargs))
        if argv[0].endswith('/security') and '-w' in argv:
            return SimpleNamespace(returncode=0, stdout=token, stderr='')
        if argv[0].endswith('/security'):
            return SimpleNamespace(returncode=0, stdout='', stderr='')
        return SimpleNamespace(returncode=0, stdout='{}', stderr='')

    scratch = tmp_path / 'k3dm-captures-2026-01-02'
    scratch.mkdir(mode=0o700)
    patcher = pytest.MonkeyPatch()
    patcher.setattr(api.isolation, 'scratch_dirs', lambda create=False: (scratch, tmp_path / 'root'))
    patcher.setattr(api.isolation, 'check_write', lambda *_args, **_kwargs: None)
    api.Api(runner=runner, binary_dir=tmp_path / 'stub', input_fn=lambda _prompt: next(answers),
            sleeper=lambda _seconds: None).run(after_disable=True)
    curl_calls = [item for item in calls if 'curl' in item[0][0]]
    assert len(curl_calls) == 1
    assert 'access/apps/' + 'b' * 32 in curl_calls[0][1]['input']
    patcher.undo()


def test_text_filter_redacts_key_and_open_ssh_email_suffix():
    source = 'ssh-ed25519 AAAAB3NzaC1yc2EAAAADAQAB comment\nuser@openssh.com\n'
    cleaned = filters.filter_text(source, 'sshd')
    assert 'AAAAB3' not in cleaned
    assert '@openssh.com' in cleaned


@pytest.mark.parametrize('answer, expected', [('y', True), ('n', False)])
def test_collect_only_copies_clean_approved_files(monkeypatch, tmp_path, answer, expected):
    operator = tmp_path / 'k3dm-captures-2026-01-02'
    (operator / 'filtered').mkdir(parents=True)
    (operator / 'filtered' / 'c1-1.json').write_text('{"ok": true}\n')
    (operator / 'terms').write_text('private-term\n')
    destination = tmp_path / 'repo' / 'docs/captures/2026-01-02-web-console-b'
    monkeypatch.setattr(collect.isolation, 'scratch_dirs', lambda: (operator, tmp_path / 'root'))
    monkeypatch.setattr(collect.isolation, 'check_write', lambda *_args, **_kwargs: None)
    monkeypatch.setattr(collect.isolation, 'REPO', tmp_path / 'repo')
    assert collect.main_collect(input_fn=lambda _prompt: answer, output_fn=lambda _line: None) == 0
    assert (destination / 'c1-1.json').exists() is expected
    assert (operator / 'collect.complete').exists()


def test_collect_never_shows_or_copies_blocked_file(monkeypatch, tmp_path):
    operator = tmp_path / 'k3dm-captures-2026-01-02'
    (operator / 'filtered').mkdir(parents=True)
    (operator / 'filtered' / 'secret.txt').write_text('Bearer secret-value-1234\n')
    (operator / 'terms').write_text('')
    shown = []
    monkeypatch.setattr(collect.isolation, 'scratch_dirs', lambda: (operator, tmp_path / 'root'))
    monkeypatch.setattr(collect.isolation, 'check_write', lambda *_args, **_kwargs: None)
    monkeypatch.setattr(collect.isolation, 'REPO', tmp_path / 'repo')
    assert collect.main_collect(input_fn=lambda _prompt: 'y', output_fn=shown.append) == 0
    assert all('secret-value-1234' not in text for text in shown)
    assert not list((tmp_path / 'repo').rglob('secret.txt'))


def test_down_requires_collect_or_discard_and_second_run_is_idempotent(monkeypatch, tmp_path):
    operator = tmp_path / 'k3dm-captures-2026-01-02'
    root = tmp_path / 'k3dm-capture-2026-01-02'
    operator.mkdir()
    root.mkdir()
    (operator / 'req').mkdir()
    (root / 'rootd.py').write_text('# staged driver')
    monkeypatch.setattr(collect.isolation, 'scratch_dirs', lambda: (operator, root))
    monkeypatch.setattr(collect.isolation, 'check_write', lambda *_args, **_kwargs: None)
    calls = []
    def runner(argv, **kwargs):
        calls.append(argv)
        assert (operator / 'req' / '0001-quit').exists()
        shutil.rmtree(root)
        return SimpleNamespace(returncode=0, stdout='', stderr='')
    assert collect.main_down(runner=runner, input_fn=lambda _prompt: 'n', output_fn=lambda _x: None) == 2
    assert operator.exists()
    assert collect.main_down(runner=runner, input_fn=lambda _prompt: 'discard', output_fn=lambda _x: None) == 0
    assert len(calls) == 1
    assert calls[0][-2:] == [str(root / 'rootd.py'), '--teardown']
    monkeypatch.setattr(collect.isolation, 'scratch_dirs', lambda: (operator, root))
    assert collect.main_down(runner=runner, output_fn=lambda _x: None) == 0


def test_down_tears_down_root_scratch_after_operator_scratch_was_lost(monkeypatch, tmp_path):
    root_base = tmp_path / 'root-base'
    operator_base = tmp_path / 'operator-base'
    root_base.mkdir()
    operator_base.mkdir()
    root = root_base / 'k3dm-capture-2026-01-02'
    root.mkdir()
    (root / 'rootd.py').write_text('# staged driver')
    monkeypatch.setattr(collect.isolation, 'scratch_dirs',
                        lambda: (_ for _ in ()).throw(collect.isolation.Refused('operator scratch is missing')))
    monkeypatch.setattr(collect.isolation, 'ROOT_BASE', root_base)
    monkeypatch.setattr(collect.isolation, 'OPERATOR_BASE', operator_base)
    calls = []

    def runner(argv, **kwargs):
        calls.append(argv)
        shutil.rmtree(root)
        return SimpleNamespace(returncode=0, stdout='', stderr='')

    output = []
    assert collect.main_down(runner=runner, output_fn=output.append) == 0
    assert calls and calls[0][-2:] == [str(root / 'rootd.py'), '--teardown']
    assert any('Dashboard cleanup' in line for line in output)


def test_cli_refuses_sty_tmux_and_ancestor(monkeypatch):
    cli = _load_cli('wcb_capture_cli_test')
    monkeypatch.setattr(cli, '_ancestors', lambda: [])
    monkeypatch.setenv('STY', 'session')
    assert cli.main(['api']) == 2
    monkeypatch.delenv('STY')
    monkeypatch.setattr(cli, '_ancestors', lambda: ['tmux'])
    assert cli.main(['api']) == 2


def test_cli_refused_maps_to_exit_two(monkeypatch):
    cli = _load_cli('wcb_capture_cli_refused_test')
    monkeypatch.setenv('TMUX', 'socket')
    assert cli.main(['api']) == 2


def test_status_uses_injected_label_and_port_probes(monkeypatch, tmp_path, capsys):
    cli = _load_cli('wcb_capture_cli_status_test')
    operator = tmp_path / 'k3dm-captures-2026-01-02'
    root = tmp_path / 'k3dm-capture-2026-01-02'
    (operator / 'browser').mkdir(parents=True)
    (operator / 'browser' / 'done-c5').touch()
    (operator / 'browser' / 'abandoned-c9-20261128T000000Z').touch()
    monkeypatch.setattr(cli.isolation, 'scratch_dirs', lambda: (operator, root))
    calls = []

    def runner(argv, **kwargs):
        calls.append(argv)
        output = '127.0.0.1.42723 LISTEN' if argv[-1] == 'tcp' else 'loaded'
        return SimpleNamespace(returncode=0, stdout=output, stderr='')

    assert cli.main(['status'], runner=runner) == 0
    captured = capsys.readouterr().out
    assert 'label: loaded' in captured
    assert '42723: listening' in captured
    assert 'done: c5' in captured
    assert 'abandoned: c9-20261128T000000Z' in captured
    assert len(calls) == 2


@pytest.mark.parametrize('command', ['api', 'browser-up', 'c8', 'c9', 'collect', 'c14-plain'])
@pytest.mark.parametrize('mode', ['TMUX', 'STY', 'ancestor'])
def test_each_interactive_command_refuses_multiplexer(monkeypatch, command, mode):
    cli = _load_cli('wcb_capture_cli_{}_{}'.format(command, mode))
    monkeypatch.delenv('TMUX', raising=False)
    monkeypatch.delenv('STY', raising=False)
    monkeypatch.setattr(cli, '_ancestors', lambda: ['screen'] if mode == 'ancestor' else [])
    if mode in ('TMUX', 'STY'):
        monkeypatch.setenv(mode, 'session')
    assert cli.main([command]) == 2

