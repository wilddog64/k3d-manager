"""Read-only Cloudflare API capture."""
import json
import os
import pwd
from pathlib import Path
import re
import stat
import subprocess
import sys
import time
import uuid

from . import filters, isolation

TOKEN_ITEM = 'k3dm-cloudflare-access-capture-token'
_operator_uid = os.getuid
ACCOUNT_RE = re.compile(r'^[0-9a-f]{32}$')
ID_RE = re.compile(r'^(?:[0-9a-f]{32}|[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})$', re.I)
HOST_RE = re.compile(r'^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)+$')
TEAM_RE = re.compile(r'^([a-z0-9-]{1,63})\.cloudflareaccess\.com$')
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
            if presence.returncode != 44:
                raise ValueError('token lookup failed')
            self.output('capture token not in Keychain')
            if self.input('Store it now? macOS will prompt for it, hidden [y/N] ').strip().lower() != 'y':
                raise ValueError('token lookup failed')
            login = pwd.getpwuid(os.getuid()).pw_name
            add = [self._binary('security'), 'add-generic-password', '-a', login, '-s', TOKEN_ITEM, '-w']
            result = self.runner(add, env={'PATH': '/usr/bin:/bin', 'HOME': str(Path.home())}, check=False)
            if result.returncode:
                raise ValueError('token lookup failed')
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

    def _resolve(self, item, url, token, matcher):
        response = self._curl(url, token)
        if response.returncode:
            return None, 'http error'
        try:
            data = json.loads(response.stdout or '')
        except (ValueError, TypeError):
            return None, 'invalid json'
        if not isinstance(data, dict) or data.get('success') is False:
            return None, 'unexpected shape' if not isinstance(data, dict) else 'http error'
        info = data.get('result_info')
        if info is not None and not isinstance(info, dict):
            return None, 'unexpected shape'
        if isinstance(info, dict):
            pages = info.get('total_pages', 1)
            if not isinstance(pages, int):
                return None, 'unexpected shape'
            if pages > 1: return None, 'more than one page'
        rows = data.get('result')
        if not isinstance(rows, list):
            return None, 'unexpected shape'
        try:
            found = [row for row in rows if matcher(row)]
        except (AttributeError, TypeError):
            return None, 'invalid field'
        if not found:
            return None, '0 matches'
        if len(found) > 1:
            return None, 'multiple matches'
        try:
            resolved = found[0]
        except (KeyError, TypeError, AttributeError, ValueError):
            return None, 'invalid field'
        return resolved, None

    @staticmethod
    def _write_terms(path, values):
        isolation.check_write(path)
        exists = False
        try:
            info = path.lstat()
            exists = True
        except FileNotFoundError:
            pass
        if exists and (not stat.S_ISREG(info.st_mode) or stat.S_IMODE(info.st_mode) != 0o600 or
                       info.st_uid != _operator_uid()):
            raise isolation.Refused('unsafe terms file')
        target = path
        if exists:
            target = path.parent / ('.terms-' + str(os.getpid()) + '-' + uuid.uuid4().hex)
            isolation.check_write(target)
        flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, 'O_NOFOLLOW', 0)
        fd = os.open(target, flags, 0o600)
        try:
            os.fchmod(fd, 0o600)
            info = os.fstat(fd)
            if not stat.S_ISREG(info.st_mode) or stat.S_IMODE(info.st_mode) != 0o600 or info.st_uid != _operator_uid():
                raise OSError('unsafe terms file')
            payload = ('\n'.join(values) + '\n').encode('utf-8')
            written = 0
            while written < len(payload):
                amount = os.write(fd, payload[written:])
                if amount <= 0:
                    raise OSError('short terms write')
                written += amount
        except BaseException:
            os.close(fd)
            try: target.unlink()
            except FileNotFoundError: pass
            raise
        os.close(fd)
        if exists:
            os.replace(target, path)

    def _read_terms(self, path):
        try:
            fd = os.open(path, os.O_RDONLY | getattr(os, 'O_NOFOLLOW', 0))
        except FileNotFoundError:
            return None
        except OSError as exc:
            raise isolation.Refused('unsafe terms file') from exc
        try:
            info = os.fstat(fd)
            if not stat.S_ISREG(info.st_mode) or stat.S_IMODE(info.st_mode) != 0o600 or info.st_uid != _operator_uid():
                raise isolation.Refused('unsafe terms file')
            with os.fdopen(fd, 'r', encoding='utf-8', closefd=False) as stream:
                text = stream.read()
        except UnicodeDecodeError as exc:
            raise isolation.Refused('terms invalid; re-run api') from exc
        finally:
            os.close(fd)
        values = text.splitlines()
        if len(values) != 5 or not ACCOUNT_RE.fullmatch(values[0]) or not ID_RE.fullmatch(values[1]) or \
                not ID_RE.fullmatch(values[2]) or not HOST_RE.fullmatch(values[3]) or \
                not re.fullmatch(r'[a-z0-9-]{1,63}', values[4]):
            raise isolation.Refused('terms invalid; re-run api')
        return values

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
        terms_path = operator / 'terms'
        values = self._read_terms(terms_path) if after_disable else None
        if values is None:
            account = self.input('Cloudflare account id:').strip()
            if not ACCOUNT_RE.fullmatch(account):
                raise ValueError('account id validation failed')
            token = self._token()

            def app_match(row):
                return isinstance(row, dict) and row.get('name') == 'wcb-capture'

            app_row, app_error = self._resolve('app', BASE + '/accounts/' + account +
                '/access/apps?name=wcb-capture&exact=true', token, app_match)
            app_id = None
            app_host = None
            if app_row:
                candidate_id = app_row.get('id', app_row.get('uid'))
                domain = app_row.get('domain')
                candidate_host = domain.split('/', 1)[0].lower() if isinstance(domain, str) else ''
                app_id = candidate_id if isinstance(candidate_id, str) and ID_RE.fullmatch(candidate_id) else None
                app_host = candidate_host if HOST_RE.fullmatch(candidate_host) else None
            app = app_id
            hostname = app_host
            if app_error:
                self.output('app: not resolved (' + app_error + ')')
            else:
                if app: self.output('app id: resolved')
                else: self.output('app id: not resolved (invalid field)')
                if hostname and HOST_RE.fullmatch(hostname): self.output('hostname: resolved')
                else: self.output('hostname: not resolved (invalid field)')
            if not app:
                app = self.input('Throwaway application id: ').strip()
                if not ID_RE.fullmatch(app): raise ValueError('application id validation failed')
            if not hostname:
                hostname = self.input('Throwaway hostname: ').strip()
                if not HOST_RE.fullmatch(hostname.lower()): raise ValueError('hostname validation failed')
                hostname = hostname.lower()

            def tunnel_match(row):
                return isinstance(row, dict) and row.get('name') == 'k3dm-capture-tunnel' and not row.get('deleted_at')

            tunnel_row, tunnel_error = self._resolve('tunnel', BASE + '/accounts/' + account +
                '/cfd_tunnel?name=k3dm-capture-tunnel&is_deleted=false', token, tunnel_match)
            tunnel = tunnel_row.get('id') if tunnel_row else None
            if tunnel_row and (not isinstance(tunnel, str) or not ID_RE.fullmatch(tunnel)):
                tunnel, tunnel_error = None, 'invalid field'
            if tunnel_error: self.output('tunnel: not resolved (' + tunnel_error + ')')
            else: self.output('tunnel: resolved')
            if not tunnel:
                tunnel = self.input('Throwaway tunnel id: ').strip()
                if not ID_RE.fullmatch(tunnel): raise ValueError('tunnel id validation failed')

            def team_match(row):
                return isinstance(row, dict)

            team_row, team_error = self._resolve('team', BASE + '/accounts/' + account +
                '/access/organizations', token, team_match)
            auth_domain = team_row.get('auth_domain') if team_row else None
            team_match_result = TEAM_RE.fullmatch(auth_domain.lower()) if isinstance(auth_domain, str) else None
            team = team_match_result.group(1) if team_match_result else None
            if team_row is not None and not team: team_error = 'invalid field'
            if team_error: self.output('team: not resolved (' + team_error + ')')
            else: self.output('team: resolved')
            if not team:
                team = self.input('Cloudflare team name: ').strip()
                if not re.fullmatch(r'[a-z0-9-]{1,63}', team.lower()): raise ValueError('team validation failed')
                team = team.lower()
            values = [account, app, tunnel, hostname, team]
            self._write_terms(terms_path, values)
        else:
            account, app, tunnel, hostname, team = values
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
        if not after_disable and self.input('Capture gateway CA too? [y/N]').strip().lower() == 'y':
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
