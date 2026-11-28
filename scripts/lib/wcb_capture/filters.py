"""Privacy projections for capture artifacts."""
import json
import datetime
import getpass
import platform
import re
import os

from . import isolation


_SENSITIVE = re.compile(r'(?i)("?(?:id|uid|account_id|zone_id|tunnel_id|aud|email|domain|name)"?\s*[:=]\s*)("[^"]*"|[^,\s}\]]+)')
_KEY = re.compile(r'(?m)^(ssh-(?:ed25519|rsa)|ecdsa-sha2-nistp\d+)\s+(\S+)(?:\s+.*)?$')
_IP = re.compile(r'(?<![\w.])(?:\d{1,3}\.){3}\d{1,3}(?![\w.])')


def _terms(text, terms, login, home):
    values = set(terms or ())
    if login:
        values.add(login)
        if len(login) > 16:
            values.add(login[:16])
    if home:
        values.add(home)
    for value in sorted((str(x) for x in values if x), key=len, reverse=True):
        text = text.replace(value, '<login>' if value == login else '~' if value == home else '<redacted:term>')
    return text


def filter_text(text, kind, terms=None, login=None, home=None):
    """Redact sensitive fields and project text logs without leaking matched values."""
    text = str(text)
    if terms is None:
        try:
            terms_path = isolation.scratch_dirs()[0] / 'terms'
            if terms_path.is_file():
                terms = terms_path.read_text(encoding='utf-8', errors='replace').splitlines()
        except (isolation.Refused, OSError):
            terms = ()
    text = _SENSITIVE.sub(lambda m: m.group(1) + '"<redacted>"', text)
    text = re.sub(r'(?is)-----BEGIN ([^-]+)-----.*?-----END \1-----',
                  lambda match: '<redacted:certificate length=' + str(len(match.group(0))) + '>', text)
    text = _KEY.sub(lambda m: m.group(1) + ' <redacted:public_key length=' + str(len(m.group(2))) + '>', text)
    text = re.sub(r'(?m)^((?:ssh-(?:rsa|ed25519)-cert-v\d+@openssh\.com)\s+)(\S+)(?:\s+.*)?$',
                  lambda m: m.group(2) + ' <redacted:public_key length=' + str(len(m.group(3))) + '>', text)
    text = re.sub(r'(?i)bearer\s+\S+', 'Bearer <redacted:token>', text)
    text = re.sub(r'eyJ[A-Za-z0-9_-]{10,}', '<redacted:token>', text)
    text = re.sub(r'@(?!openssh\.com\b|libssh\.org\b)[a-z0-9.-]+\.[a-z]{2,}', '@<redacted:email>', text, flags=re.I)
    if kind == 'connector':
        text = _IP.sub('<redacted:ip>', text)
        text = re.sub(r'(?i)\b(conn(?:ection)?(?:id|index)?|id|account(?:tag)?|tunnel(?:id)?|hostname|host|ip)[= :]+\S+',
                      r'\1=<redacted>', text)
        text = re.sub(r'(?i)\b[a-z0-9-]+(?:\.[a-z0-9-]+)+\b', '<redacted:hostname>', text)
    login = login or getpass.getuser()
    home = home or os.path.expanduser('~')
    text = _terms(text, terms, login, home)
    if not text.startswith('# host '):
        text = format_capture_header() + '\n' + text
    return text


def filter_json(value, terms=None, login=None, home=None):
    """Recursively retain API structure while redacting identifying values."""
    sensitive = {'id', 'uid', 'account_id', 'zone_id', 'tunnel_id', 'aud', 'email', 'domain'}
    if isinstance(value, dict):
        result = {}
        for key, item in value.items():
            key_lower = str(key).lower()
            if key_lower in sensitive:
                result[key] = '<redacted:' + key_lower + '>'
            elif key_lower == 'public_key' and isinstance(item, str):
                result[key] = '<redacted:public_key length=' + str(len(item)) + '>'
            elif key_lower in ('certificate', 'private_key', 'privatekey') and isinstance(item, str):
                result[key] = '<redacted:certificate length=' + str(len(item)) + '>'
            else:
                result[key] = filter_json(item, terms, login, home)
        return result
    if isinstance(value, list):
        return [filter_json(item, terms, login, home) for item in value]
    if isinstance(value, str):
        result = _terms(value, terms, login or getpass.getuser(), home or os.path.expanduser('~'))
        result = re.sub(r'(?i)bearer\s+\S+', 'Bearer <redacted:token>', result)
        result = re.sub(r'eyJ[A-Za-z0-9_-]{10,}', '<redacted:token>', result)
        result = re.sub(r'@(?!openssh\.com\b|libssh\.org\b)[a-z0-9.-]+\.[a-z]{2,}', '@<redacted:email>', result, flags=re.I)
        result = re.sub(r'(?<![\w.])(?:\d{1,3}\.){3}\d{1,3}(?![\w.])', '<redacted:ip>', result)
        return result
    return value


def filter_api_json(text, terms=None, login=None, home=None):
    result = filter_json(json.loads(text), terms, login, home)
    if isinstance(result, dict):
        result['_capture_header'] = capture_header()
    return json.dumps(result, indent=2, sort_keys=True) + '\n'


def capture_header(cloudflared='unknown', sshd='unknown', ssh='unknown', host='m4-air'):
    return {
        'host': host,
        'date': datetime.date.today().isoformat(),
        'cloudflared': cloudflared,
        'sshd': sshd,
        'ssh': ssh,
        'macOS': platform.mac_ver()[0] or 'unknown',
    }


def format_capture_header(**versions):
    header = capture_header(**versions)
    return '# host {} · {} · cloudflared {} · sshd {} · ssh {} · macOS {}'.format(
        header['host'], header['date'], header['cloudflared'], header['sshd'],
        header['ssh'], header['macOS'])
