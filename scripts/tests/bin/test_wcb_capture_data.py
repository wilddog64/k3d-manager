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


def test_api_token_only_enters_curl_stdin_and_curl_is_get(tmp_path, capsys, monkeypatch):
    token = 'A' * 32
    calls = []
    prompts = []
    answers = iter(['a' * 32, 'n'])

    def runner(argv, **kwargs):
        calls.append((argv, kwargs))
        if argv[0].endswith('/security') and '-w' in argv:
            return SimpleNamespace(returncode=0, stdout=token + '\n', stderr='')
        if argv[0].endswith('/security'):
            return SimpleNamespace(returncode=0, stdout='', stderr='')
        if 'curl' in argv[0]:
            count = len([call for call in calls if 'curl' in call[0][0]])
            if count == 4:
                assert (scratch / 'terms').read_text().splitlines() == ['a' * 32, 'b' * 32,
                    'c' * 32, 'throwaway.example.net', 'team-name']
                assert not list((scratch / 'raw').iterdir())
                assert not list((scratch / 'filtered').iterdir())
            response = ({'result': [{'name': 'wcb-capture', 'id': 'b' * 32,
                                    'domain': 'throwaway.example.net/path', 'marker': 'resolution-response'}]}
                        if count == 1 else {'result': [{'name': 'k3dm-capture-tunnel', 'id': 'c' * 32,
                                                       'marker': 'resolution-response'}]}
                        if count == 2 else {'result': [{'auth_domain': 'team-name.cloudflareaccess.com',
                                                       'marker': 'resolution-response'}]}
                        if count == 3 else {'result': {
                            'public_key': 'ssh-ed25519 AAAAB3NzaC1yc2EAAAADAQAB comment',
                            'details': ['a' * 32, 'b' * 32, 'c' * 32,
                                        'throwaway.example.net', 'team-name'],
                            'marker': 'loop-response'}})
            return SimpleNamespace(returncode=0, stdout=json.dumps(response), stderr='')
        raise AssertionError('unexpected command')

    scratch = tmp_path / 'k3dm-captures-2026-01-02'
    scratch.mkdir(mode=0o700)
    assert scratch.parent == tmp_path
    monkeypatch.setattr(api.isolation, 'scratch_dirs', lambda create=False: (scratch, tmp_path / 'root'))
    monkeypatch.setattr(api.isolation, 'check_write', lambda *_args, **_kwargs: None)

    def answer(prompt):
        prompts.append(prompt)
        return next(answers)

    result = api.Api(runner=runner, binary_dir=tmp_path / 'stub',
                     input_fn=answer,
                     sleeper=lambda _seconds: None).run()
    assert result == 0
    assert prompts == ['Cloudflare account id:', 'Capture gateway CA too? [y/N]']
    assert (scratch / 'terms').stat().st_mode & 0o777 == 0o600
    assert (scratch / 'terms').read_text().splitlines() == [
        'a' * 32, 'b' * 32, 'c' * 32, 'throwaway.example.net', 'team-name']
    security_calls = [call for call in calls if call[0][0].endswith('/security')]
    assert [call[0] for call in security_calls] == [
        [str(tmp_path / 'stub/security'), 'find-generic-password', '-s', api.TOKEN_ITEM],
        [str(tmp_path / 'stub/security'), 'find-generic-password', '-s', api.TOKEN_ITEM, '-w'],
    ]
    assert all(call[1]['env'] == {'PATH': '/usr/bin:/bin'} for call in security_calls)
    curl_calls = [call for call in calls if 'curl' in call[0][0]]
    resolution_calls = curl_calls[:3]
    loop_calls = curl_calls[3:]
    assert len(resolution_calls) == 3
    assert len(loop_calls) == 8  # agent-audit: allow assert-removed len==8 split into 3 resolution + 8 loop calls; token-only output check widened to token plus all five resolved values
    account, app, tunnel = 'a' * 32, 'b' * 32, 'c' * 32
    resolution_endpoints = [
        '/accounts/' + 'a' * 32 + '/access/apps?name=wcb-capture&exact=true',
        '/accounts/' + 'a' * 32 + '/cfd_tunnel?name=k3dm-capture-tunnel&is_deleted=false',
        '/accounts/' + 'a' * 32 + '/access/organizations',
    ]
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
    for (argv, kwargs), endpoint in zip(resolution_calls, resolution_endpoints):
        assert argv == [str(tmp_path / 'stub/curl'), '-q', '--config', '-']
        assert endpoint in kwargs['input']
        assert 'request = "GET"' in kwargs['input']
        assert 'proto = "=https"' in kwargs['input']
        assert token not in repr(argv)
    for (argv, kwargs), endpoint in zip(loop_calls, endpoints):
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
    recorded_argv = repr([call[0] for call in calls])
    assert all(value not in recorded_argv for value in
               (account, app, tunnel, 'throwaway.example.net', 'team-name'))
    for path in (scratch / 'filtered').glob('*'):
        content = path.read_text()
        assert all(value not in content for value in
                   (account, app, tunnel, 'throwaway.example.net', 'team-name'))
        assert 'resolution-response' not in content
    for path in (scratch / 'raw').glob('*'):
        assert 'resolution-response' not in path.read_text()
    for path in (scratch / 'ca').glob('*'):
        content = path.read_text()
        assert all(value not in content for value in
                   (account, app, tunnel, 'throwaway.example.net', 'team-name'))
    captured = capsys.readouterr()
    assert all(value not in captured.out + captured.err for value in
               (token, account, app, tunnel, 'throwaway.example.net', 'team-name'))
    assert captured.out.splitlines()[:4] == [
        'app id: resolved', 'hostname: resolved', 'tunnel: resolved', 'team: resolved']


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
    answers = iter(['a' * 32])
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
    answers = iter(['a' * 32, 'b' * 32, 'throwaway.example.net', 'c' * 32, 'team-name', 'n'])

    def runner(argv, **kwargs):
        calls.append((argv, kwargs))
        if argv[0].endswith('/security') and '-w' in argv:
            return SimpleNamespace(returncode=0, stdout=token, stderr='')
        if argv[0].endswith('/security'):
            return SimpleNamespace(returncode=0, stdout='', stderr='')
        curl_count = len([item for item in calls if 'curl' in item[0][0]])
        if curl_count in (1, 2, 3):
            return SimpleNamespace(returncode=0, stdout=json.dumps({'result': []}), stderr='')
        if curl_count == 4:
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
    answers = iter([])

    def runner(argv, **kwargs):
        calls.append((argv, kwargs))
        if argv[0].endswith('/security') and '-w' in argv:
            return SimpleNamespace(returncode=0, stdout=token, stderr='')
        if argv[0].endswith('/security'):
            return SimpleNamespace(returncode=0, stdout='', stderr='')
        return SimpleNamespace(returncode=0, stdout='{}', stderr='')

    scratch = tmp_path / 'k3dm-captures-2026-01-02'
    scratch.mkdir(mode=0o700)
    (scratch / 'terms').write_text('\n'.join(['a' * 32, 'b' * 32, 'c' * 32,
                                               'throwaway.example.net', 'team-name']) + '\n')
    (scratch / 'terms').chmod(0o600)
    patcher = pytest.MonkeyPatch()
    patcher.setattr(api.isolation, 'scratch_dirs', lambda create=False: (scratch, tmp_path / 'root'))
    patcher.setattr(api.isolation, 'check_write', lambda *_args, **_kwargs: None)
    api.Api(runner=runner, binary_dir=tmp_path / 'stub', input_fn=lambda _prompt: next(answers),
            sleeper=lambda _seconds: None).run(after_disable=True)
    curl_calls = [item for item in calls if 'curl' in item[0][0]]
    assert len(curl_calls) == 1
    assert 'access/apps/' + 'b' * 32 in curl_calls[0][1]['input']
    patcher.undo()


def test_api_keychain_offer_only_on_missing_and_add_uses_terminal_runner(tmp_path, monkeypatch):
    token = 'D' * 32
    calls = []
    answers = iter(['y'])
    presence = iter([44, 0, 0])
    monkeypatch.setattr(api.pwd, 'getpwuid', lambda _uid: type('Entry', (), {'pw_name': 'operator'})())

    def runner(argv, **kwargs):
        calls.append((argv, kwargs))
        if 'add-generic-password' in argv:
            return SimpleNamespace(returncode=0, stdout='', stderr='')
        if '-w' in argv:
            return SimpleNamespace(returncode=0, stdout=token, stderr='')
        return SimpleNamespace(returncode=next(presence), stdout='', stderr='')

    api.Api(runner=runner, binary_dir=tmp_path / 'stub', input_fn=lambda _prompt: next(answers))._token()
    add_call = next(call for call in calls if 'add-generic-password' in call[0])
    assert add_call[0] == [str(tmp_path / 'stub/security'), 'add-generic-password', '-a',
                           'operator', '-s', api.TOKEN_ITEM, '-w']
    assert add_call[1] == {'env': {'PATH': '/usr/bin:/bin', 'HOME': str(Path.home())}, 'check': False}

    offered = []
    def locked(argv, **_kwargs):
        return SimpleNamespace(returncode=36, stdout='', stderr='')
    with pytest.raises(ValueError, match='token lookup failed'):
        api.Api(runner=locked, input_fn=lambda prompt: offered.append(prompt))._token()
    assert offered == []


def _run_resolution_flow(tmp_path, monkeypatch, target, replacement, answers):
    scratch = tmp_path / 'k3dm-captures-2026-01-02'
    scratch.mkdir(mode=0o700)
    assert scratch.is_relative_to(tmp_path)
    monkeypatch.setattr(api.isolation, 'scratch_dirs', lambda create=False: (scratch, tmp_path / 'root'))
    monkeypatch.setattr(api.isolation, 'check_write', lambda *_args, **_kwargs: None)
    prompts = []
    output = []
    calls = []
    token = 'R' * 32
    base_responses = [
        {'result': [{'name': 'wcb-capture', 'id': 'b' * 32, 'domain': 'resolved.example.net/path'}]},
        {'result': [{'name': 'k3dm-capture-tunnel', 'id': 'c' * 32}]},
        {'result': [{'auth_domain': 'resolved-team.cloudflareaccess.com'}]},
    ]
    if target == 'app': base_responses[0] = replacement
    if target == 'tunnel': base_responses[1] = replacement
    if target == 'team': base_responses[2] = replacement
    answers_iter = iter(['a' * 32, *answers, 'n'])

    def runner(argv, **kwargs):
        calls.append((argv, kwargs))
        if argv[0].endswith('/security'):
            return SimpleNamespace(returncode=0, stdout=token if '-w' in argv else '', stderr='')
        if 'curl' in argv[0]:
            count = len([call for call in calls if 'curl' in call[0][0]])
            if count <= 3:
                response = base_responses[count - 1]
                if isinstance(response, tuple):
                    return SimpleNamespace(returncode=response[0], stdout=response[1], stderr=response[2])
                if isinstance(response, str):
                    return SimpleNamespace(returncode=0, stdout=response, stderr='')
                return SimpleNamespace(returncode=0, stdout=json.dumps(response), stderr='')
            response = {'result': {'public_key': 'ssh-ed25519 AAAAB3NzaC1yc2EAAAADAQAB'}}
            return SimpleNamespace(returncode=0, stdout=json.dumps(response), stderr='')
        raise AssertionError('unexpected command')

    def input_fn(prompt):
        prompts.append(prompt)
        return next(answers_iter)

    api.Api(runner=runner, binary_dir=tmp_path / 'stub', input_fn=input_fn,
            output_fn=output.append, sleeper=lambda _seconds: None).run()
    return scratch, prompts, output, calls


@pytest.mark.parametrize('response, reason', [
    ({'result': []}, '0 matches'),
    ({'result': [{'name': 'other', 'id': 'd' * 32, 'domain': 'other.example.net'}]}, '0 matches'),
    ({'result': [{'name': 'wcb-capture', 'id': 'd' * 32, 'domain': 'one.example.net'},
                 {'name': 'wcb-capture', 'id': 'e' * 32, 'domain': 'two.example.net'}]}, 'multiple matches'),
    ((22, '', 'curl failed'), 'http error'),
    ('not json', 'invalid json'),
    ({'success': False, 'result': []}, 'http error'),
    ({'result': [], 'result_info': {'total_pages': 2}}, 'more than one page'),
])
def test_api_app_resolution_fallbacks_prompt_app_and_hostname(tmp_path, monkeypatch, capsys, response, reason):
    _scratch, prompts, output, _calls = _run_resolution_flow(
        tmp_path, monkeypatch, 'app', response,
        ['d' * 32, 'fallback.example.net'])
    assert prompts == ['Cloudflare account id:', 'Throwaway application id: ',
                       'Throwaway hostname: ', 'Capture gateway CA too? [y/N]']
    assert 'app: not resolved (' + reason + ')' in output
    assert not any('resolved.example.net' in line for line in output)
    assert 'd' * 32 not in capsys.readouterr().out


def test_api_bad_app_domain_prompts_hostname_only(tmp_path, monkeypatch):
    _scratch, prompts, output, _calls = _run_resolution_flow(
        tmp_path, monkeypatch, 'app',
        {'result': [{'name': 'wcb-capture', 'id': 'b' * 32, 'domain': 'not a hostname/path'}]},
        ['fallback.example.net'])
    assert prompts == ['Cloudflare account id:', 'Throwaway hostname: ', 'Capture gateway CA too? [y/N]']
    assert 'app id: resolved' in output
    assert 'hostname: not resolved (invalid field)' in output


@pytest.mark.parametrize('response, reason', [
    ({'result': []}, '0 matches'),
    ({'result': [{'name': 'other', 'id': 'd' * 32}]}, '0 matches'),
    ({'result': [{'name': 'k3dm-capture-tunnel', 'id': 'd' * 32},
                 {'name': 'k3dm-capture-tunnel', 'id': 'e' * 32}]}, 'multiple matches'),
    ((22, '', 'curl failed'), 'http error'),
    ('not json', 'invalid json'),
    ({'success': False, 'result': []}, 'http error'),
    ({'result': [], 'result_info': {'total_pages': 2}}, 'more than one page'),
    ({'result': [{'name': 'k3dm-capture-tunnel', 'id': 'd' * 32, 'deleted_at': 'yesterday'}]}, '0 matches'),
])
def test_api_tunnel_resolution_fallbacks_prompt_tunnel_only(tmp_path, monkeypatch, response, reason):
    _scratch, prompts, output, _calls = _run_resolution_flow(
        tmp_path, monkeypatch, 'tunnel', response, ['d' * 32])
    assert prompts == ['Cloudflare account id:', 'Throwaway tunnel id: ',
                       'Capture gateway CA too? [y/N]']
    assert 'tunnel: not resolved (' + reason + ')' in output


@pytest.mark.parametrize('response', [
    {'result': [{'auth_domain': 'login.example.com'}]},
    {'result': [{'auth_domain': 'dotless'}]},
    {'result': [{}]},
    {'result': []},
])
def test_api_invalid_team_domains_prompt_team_only(tmp_path, monkeypatch, response):
    _scratch, prompts, output, _calls = _run_resolution_flow(
        tmp_path, monkeypatch, 'team', response, ['fallback-team'])
    assert prompts == ['Cloudflare account id:', 'Cloudflare team name: ',
                       'Capture gateway CA too? [y/N]']
    assert any(line.startswith('team: not resolved (') for line in output)


@pytest.mark.parametrize('answer, add_rc, recheck_rc', [
    ('n', None, None), ('y', 1, None), ('y', 0, 36),
])
def test_api_keychain_decline_add_failure_and_recheck_failure_stop(
        tmp_path, monkeypatch, answer, add_rc, recheck_rc):
    from collections import deque
    calls = []
    presence = deque([44] + ([] if add_rc is None else [recheck_rc]))
    prompts = []
    monkeypatch.setattr(api.pwd, 'getpwuid', lambda _uid: type('Entry', (), {'pw_name': 'operator'})())

    def runner(argv, **kwargs):
        calls.append((argv, kwargs))
        if 'add-generic-password' in argv:
            return SimpleNamespace(returncode=add_rc, stdout='', stderr='')
        return SimpleNamespace(returncode=presence.popleft(), stdout='', stderr='')

    with pytest.raises(ValueError, match='token lookup failed'):
        api.Api(runner=runner, input_fn=lambda prompt: prompts.append(prompt) or answer)._token()
    assert prompts == (['Store it now? macOS will prompt for it, hidden [y/N] ']
                       if answer == 'n' or answer == 'y' else [])
    add_calls = [call for call in calls if 'add-generic-password' in call[0]]
    assert len(add_calls) == (0 if answer == 'n' else 1)
    if add_calls:
        argv, kwargs = add_calls[0]
        assert argv == ['/usr/bin/security', 'add-generic-password', '-a', 'operator',
                        '-s', api.TOKEN_ITEM, '-w']
        assert not {'capture_output', 'input', 'stdin', 'stdout', 'stderr'} & set(kwargs)


def test_api_after_disable_without_terms_resolves_without_gateway_prompt(tmp_path, monkeypatch):
    scratch = tmp_path / 'k3dm-captures-2026-01-02'
    scratch.mkdir(mode=0o700)
    assert scratch.is_relative_to(tmp_path)
    monkeypatch.setattr(api.isolation, 'scratch_dirs', lambda create=False: (scratch, tmp_path / 'root'))
    monkeypatch.setattr(api.isolation, 'check_write', lambda *_args, **_kwargs: None)
    prompts = []
    calls = []
    def runner(argv, **kwargs):
        calls.append((argv, kwargs))
        if argv[0].endswith('/security'):
            return SimpleNamespace(returncode=0, stdout='T' * 32 if '-w' in argv else '', stderr='')
        count = len([call for call in calls if 'curl' in call[0][0]])
        if count == 1:
            body = {'result': [{'name': 'wcb-capture', 'id': 'b' * 32, 'domain': 'app.example.net'}]}
        elif count == 2:
            body = {'result': [{'name': 'k3dm-capture-tunnel', 'id': 'c' * 32}]}
        elif count == 3:
            body = {'result': [{'auth_domain': 'team.cloudflareaccess.com'}]}
        else:
            body = {'result': {'status': 'disabled'}}
        return SimpleNamespace(returncode=0, stdout=json.dumps(body), stderr='')

    def input_fn(prompt):
        prompts.append(prompt)
        return 'a' * 32

    api.Api(runner=runner, input_fn=input_fn, output_fn=lambda _line: None,
            sleeper=lambda _seconds: None).run(after_disable=True)
    assert prompts == ['Cloudflare account id:']
    curl_calls = [call for call in calls if 'curl' in call[0][0]]
    assert len(curl_calls) == 4
    assert '/access/apps/' + 'b' * 32 in curl_calls[-1][1]['input']
    assert 'gateway_ca' not in curl_calls[-1][1]['input']


@pytest.mark.parametrize('unsafe', ['live-symlink', 'dangling-symlink', '0644', 'foreign-owner'])
def test_api_after_disable_refuses_unsafe_terms_without_requests(tmp_path, monkeypatch, unsafe):
    scratch = tmp_path / 'k3dm-captures-2026-01-02'
    scratch.mkdir(mode=0o700)
    assert scratch.is_relative_to(tmp_path)
    terms = scratch / 'terms'
    valid = '\n'.join(['a' * 32, 'b' * 32, 'c' * 32, 'host.example.net', 'team']) + '\n'
    if unsafe == 'live-symlink':
        target = scratch / 'target'
        target.write_text(valid)
        terms.symlink_to(target)
    elif unsafe == 'dangling-symlink':
        terms.symlink_to(scratch / 'missing')
    else:
        terms.write_text(valid)
        terms.chmod(0o644 if unsafe == '0644' else 0o600)
    monkeypatch.setattr(api.isolation, 'scratch_dirs', lambda create=False: (scratch, tmp_path / 'root'))
    monkeypatch.setattr(api.isolation, 'check_write', lambda *_args, **_kwargs: None)
    if unsafe == 'foreign-owner':
        uid = api._operator_uid()
        monkeypatch.setattr(api, '_operator_uid', lambda: uid + 1)
    calls = []
    prompts = []
    def runner(argv, **kwargs):
        calls.append(argv)
        return SimpleNamespace(returncode=0, stdout='', stderr='')
    with pytest.raises(api.isolation.Refused, match='^unsafe terms file$'):
        api.Api(runner=runner, input_fn=lambda prompt: prompts.append(prompt)).run(after_disable=True)
    assert calls == []
    assert prompts == []


def test_api_after_disable_refuses_invalid_terms_content(tmp_path, monkeypatch):
    scratch = tmp_path / 'k3dm-captures-2026-01-02'
    scratch.mkdir(mode=0o700)
    assert scratch.is_relative_to(tmp_path)
    terms = scratch / 'terms'
    terms.write_text('\n'.join(['a' * 32, 'b' * 32, 'c' * 32, 'host.example.net']) + '\n')
    terms.chmod(0o600)
    monkeypatch.setattr(api.isolation, 'scratch_dirs', lambda create=False: (scratch, tmp_path / 'root'))
    monkeypatch.setattr(api.isolation, 'check_write', lambda *_args, **_kwargs: None)
    with pytest.raises(api.isolation.Refused, match='^terms invalid; re-run api$'):
        api.Api(runner=lambda *_args, **_kwargs: pytest.fail('unexpected command'),
                input_fn=lambda _prompt: pytest.fail('unexpected prompt')).run(after_disable=True)


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

