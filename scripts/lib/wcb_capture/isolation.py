"""Capture-only resource guards."""
import datetime
import os
from pathlib import Path
import re
import stat
import subprocess


class Refused(ValueError):
    """An operation is outside the capture kit's permitted scope."""


OPERATOR_BASE = Path('/private/tmp')
ROOT_BASE = Path('/private/var/db')
REPO = Path(__file__).resolve().parents[3]
_DATE = re.compile(r'^\d{4}-\d{2}-\d{2}$')


def scratch_dirs(create=False):
    first = {p.name[len('k3dm-captures-'):]: p for p in OPERATOR_BASE.glob('k3dm-captures-*')
             if _DATE.fullmatch(p.name[len('k3dm-captures-'):])}
    second = {p.name[len('k3dm-capture-'):]: p for p in ROOT_BASE.glob('k3dm-capture-*')
              if _DATE.fullmatch(p.name[len('k3dm-capture-'):])}
    dates = set(first) | set(second)
    if len(dates) > 1:
        raise Refused('multiple capture dates')
    date = next(iter(dates), datetime.date.today().isoformat())
    if date in second and date not in first:
        raise Refused('operator scratch is missing')
    operator = OPERATOR_BASE / ('k3dm-captures-' + date)
    root = ROOT_BASE / ('k3dm-capture-' + date)
    if create:
        operator.mkdir(mode=0o700, exist_ok=True)
    if operator.exists() or operator.is_symlink():
        info = operator.lstat()
        if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid() or stat.S_IMODE(info.st_mode) != 0o700:
            raise Refused('unsafe operator scratch')
    return operator, root


def _within(path, base):
    try:
        path.relative_to(base)
        return True
    except ValueError:
        return False


def check_write(path, mode='operator'):
    target = Path(path).resolve()
    protected = ['/etc/k3dm-web-console', '/Library/PrivilegedHelperTools/k3dm-web-console',
                 '/Library/LaunchDaemons', '/etc/k3dm-console-tunnel', str(Path.home() / '.cloudflared'),
                 str(REPO / 'scripts/etc/cloudflared'), str(REPO / 'scripts/etc/cloudflared-config.yml.tmpl')]
    if any(_within(target, Path(item).resolve()) for item in protected):
        raise Refused('protected path')
    if any(str(target).startswith(str(Path(base).resolve() / 'k3dm-web-console'))
           for base in ('/var/db', '/var/log')):
        raise Refused('protected path')
    if mode == 'root':
        candidates = [p.resolve() for p in ROOT_BASE.glob('k3dm-capture-*')
                      if _DATE.fullmatch(p.name[len('k3dm-capture-'):])]
        if not candidates:
            _, expected_root = scratch_dirs()
            candidates = [expected_root.resolve()]
        if len(candidates) != 1 or not _within(target, candidates[0]):
            raise Refused('outside capture directories')
        return
    first, second = scratch_dirs()
    if mode == 'operator':
        date = first.name[len('k3dm-captures-'):]
        allowed = (first.resolve(), (REPO / 'docs/captures' / (date + '-web-console-b')).resolve())
    else:
        raise Refused('unknown mode')
    if not any(_within(target, base) for base in allowed):
        raise Refused('outside capture directories')


def check_label(label):
    production_prefix = 'com.k3d-manager.' + 'web-console-'
    if label.startswith(production_prefix) or label != 'com.k3d-manager.capture-sshd':
        raise Refused('forbidden label')


def check_port(port):
    if port != 42723:
        raise Refused('forbidden port')


def _run_command(argv):
    return subprocess.run(argv, capture_output=True, text=True, check=True)


def port_free(port=42723):
    check_port(port)
    result = _run_command(['/usr/sbin/netstat', '-anv', '-p', 'tcp'])
    return not any(re.search(r'\b127\.0\.0\.1\.42723\b', line) and 'LISTEN' in line
                   for line in result.stdout.splitlines())


def check_cloudflared(argv, env):
    args = list(argv)
    if not args or Path(args[0]).name != 'cloudflared' or 'TUNNEL_TOKEN' in env:
        raise Refused('forbidden cloudflared invocation')
    words = args[1:]
    if any(a in ('create', 'login', '--token') or a.startswith('--token=') for a in words):  # agent-audit: allow sensitive-flag denylist that refuses a token in cloudflared argv
        raise Refused('forbidden cloudflared invocation')
    if words == ['--version'] or words[:2] == ['access', 'ssh']:
        return
    if words[:1] == ['tunnel']:
        index = 1
        while index < len(words) and words[index] in ('--config', '--loglevel', '--logfile', '--no-autoupdate'):
            index += 1 if words[index] == '--no-autoupdate' else 2
        if words[index:index + 2] in (['ingress', 'validate'], ['ingress', 'rule']):
            tail = words[index + 2:]
            if (words[index + 1] == 'validate' and not tail) or (words[index + 1] == 'rule' and len(tail) == 1):
                return
        if words[index:index + 1] == ['run']:
            tail = words[index + 1:]
            if len(tail) == 2 and tail[0] == '--token-file' and tail[1] and not tail[1].startswith('-'):
                return
    raise Refused('forbidden cloudflared invocation')


def refuse_multiplexer(env, ancestors):
    if env.get('TMUX') or env.get('STY') or any(os.path.basename(str(a)) in ('tmux', 'screen') for a in ancestors):
        raise Refused('multiplexer session')
