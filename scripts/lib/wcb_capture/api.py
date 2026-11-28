"""Read-only Cloudflare API capture."""
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time

from . import filters, isolation

TOKEN_ITEM = 'k3dm-cloudflare-access-capture-token'
ACCOUNT_RE = re.compile(r'^[0-9a-f]{32}$')
ID_RE = re.compile(r'^(?:[0-9a-f]{32}|[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})$', re.I)
BASE = 'https://api.cloudflare.com/client/v4'


def _scrub_token(value, token):
    if isinstance(value, dict):
        return {key: _scrub_token(item, token) for key, item in value.items()}
    if isinstance(value, list):
        return [_scrub_token(item, token) for item in value]
    if isinstance(value, str):
        return value.replace(token, '<redacted:token>')
    return value


class Api:
    """API runner; runner and binary_dir are injectable offline test seams."""
    def __init__(self, runner=None, binary_dir=None, input_fn=input, output_fn=print, sleeper=None):
        self.runner = runner or subprocess.run
        self.binary_dir = Path(binary_dir) if binary_dir else None
        self.input = input_fn
        self.output = output_fn
        self.sleeper = sleeper or time.sleep

    def _binary(self, name):
        if self.binary_dir:
            return str(self.binary_dir / name)
        return '/usr/bin/' + name

    def _run(self, argv, **kwargs):
        return self.runner(argv, env={'PATH': '/usr/bin:/bin'}, capture_output=True,
                            text=True, check=False, **kwargs)

    def _token(self):
        lookup = [self._binary('security'), 'find-generic-password', '-s', TOKEN_ITEM]
        presence = self._run(lookup)
        if presence.returncode:
            raise ValueError('token lookup failed')
        result = self._run(lookup + ['-w'])
        if result.returncode:
            raise ValueError('token lookup failed')
        token = result.stdout.strip()
        if not re.fullmatch(r'[A-Za-z0-9_-]{20,200}', token):
            raise ValueError('token validation failed')
        return token

    def _curl(self, url, token):
        config = '\n'.join((
            'url = "' + url + '"',
            'header = "Authorization: Bearer ' + token + '"',
            'request = "GET"', 'proto = "=https"', 'fail-with-body',
            'max-time = 30', 'silent', 'show-error', '',
        ))
        return self._run([self._binary('curl'), '-q', '--config', '-'], input=config)

    def run(self, after_disable=False):
        operator, _ = isolation.scratch_dirs(create=True)
        isolation.check_write(operator / 'raw')
        completion = operator / 'collect.complete'
        if completion.exists():
            isolation.check_write(completion)
            completion.unlink()
        raw_dir, filtered_dir = operator / 'raw', operator / 'filtered'
        for directory in (raw_dir, filtered_dir):
            isolation.check_write(directory)
            if directory.is_symlink():
                raise isolation.Refused('unsafe capture directory')
        raw_dir.mkdir(mode=0o700, exist_ok=True)
        filtered_dir.mkdir(mode=0o700, exist_ok=True)
        os.chmod(raw_dir, 0o700)
        os.chmod(filtered_dir, 0o700)
        account = self.input('Cloudflare account id: ').strip()
        app = self.input('Throwaway application id: ').strip()
        tunnel = self.input('Throwaway tunnel id: ').strip()
        hostname = self.input('Throwaway hostname: ').strip()
        team = self.input('Cloudflare team name: ').strip()
        if not ACCOUNT_RE.fullmatch(account):
            raise ValueError('account id validation failed')
        if not ID_RE.fullmatch(app):
            raise ValueError('application id validation failed')
        if not ID_RE.fullmatch(tunnel):
            raise ValueError('tunnel id validation failed')
        if not hostname or not team:
            raise ValueError('scan term validation failed')
        terms_path = operator / 'terms'
        isolation.check_write(terms_path)
        terms_path.write_text('\n'.join((account, app, tunnel, hostname, team)) + '\n', encoding='utf-8')
        os.chmod(terms_path, 0o600)
        token = self._token()
        endpoints = [
            ('apps', '/accounts/' + account + '/access/apps'),
            ('app', '/accounts/' + account + '/access/apps/' + app),
            ('policies', '/accounts/' + account + '/access/apps/' + app + '/policies'),
            ('identity-providers', '/accounts/' + account + '/access/identity_providers'),
            ('organization', '/accounts/' + account + '/access/organizations'),
            ('ca', '/accounts/' + account + '/access/apps/' + app + '/ca'),
            ('ca-stability', '/accounts/' + account + '/access/apps/' + app + '/ca'),
            ('tunnel', '/accounts/' + account + '/cfd_tunnel/' + tunnel),
        ]
        if self.input('Capture gateway CA too? [y/N] ').strip().lower() == 'y':
            endpoints.insert(7, ('gateway-ca', '/accounts/' + account + '/access/gateway_ca'))
        if after_disable:
            endpoints = [('app-after-disable', '/accounts/' + account + '/access/apps/' + app)]
        for index, (name, path) in enumerate(endpoints, 1):
            if name == 'ca-stability':
                self.sleeper(60)
            response = self._curl(BASE + path, token)
            body = response.stdout or response.stderr or ''
            try:
                data = json.loads(body)
            except (ValueError, TypeError):
                data = {'result': body.replace(token, '<redacted:token>')}
            data = _scrub_token(data, token)
            codes = []
            if isinstance(data, dict):
                errors = data.get('errors', [])
                if isinstance(errors, list):
                    codes = [item.get('code') for item in errors if isinstance(item, dict) and item.get('code') is not None]
            if getattr(response, 'returncode', 0) and '403' in str(getattr(response, 'stderr', '')) and codes:
                template = path.replace(account, '{account_id}').replace(app, '{app_id}').replace(tunnel, '{tunnel_id}')
                data = {'error': '403 on ' + template + ', code ' + ','.join(map(str, codes))}
            ca_key = None
            ca_fields = None
            if name in ('ca', 'ca-stability') and not after_disable:
                try:
                    public_key = data['result']['public_key']
                except (KeyError, TypeError):
                    raise ValueError('CA public_key field missing')
                ca_fields = public_key.split()
                ca_key = ' '.join(ca_fields[:2])
                if (len(ca_key) >= 16384 or not re.fullmatch(
                        r'(?:ssh-ed25519|ecdsa-sha2-nistp(?:256|384|521)|ssh-rsa) [A-Za-z0-9+/]+={0,3}', ca_key)):
                    raise ValueError('CA public_key validation failed')
            raw_path = raw_dir / (name + '.json')
            isolation.check_write(raw_path)
            data = _scrub_token(data, token)
            if isinstance(data, dict):
                data['_capture_header'] = filters.capture_header()
            raw_path.write_text(json.dumps(data, indent=2) + '\n', encoding='utf-8')
            os.chmod(raw_path, 0o600)
            filtered = filters.filter_json(data, terms=(account, app, tunnel, hostname, team))
            if ca_fields:
                filtered = {'algorithm': ca_fields[0], 'body_length': len(ca_fields[1])}
            if isinstance(filtered, dict):
                filtered['_capture_header'] = filters.capture_header()
            filtered_path = filtered_dir / (name + '-1.json')
            isolation.check_write(filtered_path)
            filtered_path.write_text(json.dumps(filtered, indent=2, sort_keys=True) + '\n', encoding='utf-8')
            os.chmod(filtered_path, 0o600)
            if name == 'ca' and ca_key:
                ca_dir = operator / 'ca'
                isolation.check_write(ca_dir)
                if ca_dir.is_symlink():
                    raise isolation.Refused('unsafe CA directory')
                ca_dir.mkdir(mode=0o700, exist_ok=True)
                os.chmod(ca_dir, 0o700)
                ca_file = ca_dir / 'access_ca.pub'
                isolation.check_write(ca_file)
                ca_file.write_text(ca_key + '\n', encoding='ascii')
                os.chmod(ca_file, 0o600)
                self.output('CA algorithm ' + ca_fields[0] + '; body length ' + str(len(ca_fields[1])))
        return 0


def main(argv):
    try:
        return Api().run('--after-disable' in argv)
    except isolation.Refused:
        raise
    except Exception as exc:
        # Only the stable operation context is exposed; subprocess exceptions may contain secrets.
        print('api: request/setup step failed (' + type(exc).__name__ + ')', file=sys.stderr)
        return 1
