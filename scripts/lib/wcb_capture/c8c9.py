"""C8 enforcement and C9 session behavior captures."""
import datetime
import os
from pathlib import Path
import subprocess
import sys

from . import filters, isolation, requests, scan


def _connection(data):
    if isinstance(data, str): data = data.encode()
    return b'Connection from ' in data or b'Accepted ' in data


def classify_c8(sshd_slices, reached, attempts=None):
    """Return the C8 verdicts using request slices and the (b)/(c) controls."""
    attempts = dict(attempts or {})
    reached = set(reached)
    result = {}
    controls = 'b' in reached and 'c' in reached
    for key in 'abcd':
        if attempts.get(key) == 'not run':
            result[key] = 'not run'
            continue
        connected = _connection(sshd_slices.get(key, b''))
        if key in ('a', 'd') and connected:
            result[key] = 'fail'
        elif key in ('a', 'd') and controls:
            result[key] = 'candidate-pass'
        elif key == 'b':
            result[key] = 'reached' if connected else 'void'
        elif key == 'c':
            result[key] = 'reached' if connected else 'void'
        else:
            result[key] = 'void'
    result['summary'] = ('origin JWT validation not shown'
                         if all(result.get(k) in ('void', 'not run') for k in 'abcd')
                         else 'review connector slices')
    return result


def _slices(path, ranges):
    content = Path(path).read_bytes()
    return {name: content[start:end] for name, (start, end) in ranges.items()}


def _capture_dir():
    scratch, _ = isolation.scratch_dirs()
    target = scratch / 'browser'
    isolation.check_write(target)
    target.mkdir(mode=0o700, exist_ok=True)
    return scratch, target


_C8_STATES = {
    'a': 'Access required ON; send a request without an Access JWT.',
    'b': 'Access required ON; log in with the primary app and send a valid-JWT request.',
    'c': 'Access required OFF; send the same request without a JWT.',
    'd': 'Access required ON; use a valid JWT for a different app audience.',
}


def _write_safe(path, text, kind='recorder'):
    isolation.check_write(path)
    projected = filters.filter_text(text, kind)
    # A scan failure withholds the artifact rather than persisting unfiltered data.
    temp = path.with_name(path.name + '.scan')
    temp.write_text(projected, encoding='utf-8')
    hits = scan.scan_file(temp)
    if hits:
        temp.unlink()
        return False
    temp.replace(path)
    return True


def main_c8(argv=None, runner=None, input_fn=input, output=print, sleeper=None,
            wait_for=None):
    try:
        runner = runner or subprocess.run
        input_fn = input_fn or input
        output = output or print
        wait_for = wait_for or _wait_line
        if argv: raise isolation.Refused('unexpected arguments')
        scratch, directory = _capture_dir()
        isolation.refuse_multiplexer(os.environ, ())
        isolation.check_port(42723)
        if not isolation.port_free(42723): raise isolation.Refused('port busy')
        output('Close every iPad tab on the throwaway hostname before starting C8.')
        input_fn('After closing every matching iPad tab, press Return: ')
        requests.submit('up-c8')
        _, root = isolation.scratch_dirs()
        steps, sshlog, connector = root / 'root-steps.log', root / 'sshd.log', scratch / 'connector.log'
        if not wait_for(steps, 'up c8'):
            raise isolation.Refused('root driver did not start c8')
        hostname = input_fn('Throwaway hostname: ').strip()
        if not hostname or any(char in hostname for char in '\r\n /'):
            raise isolation.Refused('invalid hostname')
        home = scratch / 'cfhome'
        isolation.check_write(home)
        home.mkdir(mode=0o700, exist_ok=True)
        attempts, sshd_slices, connector_slices = {}, {}, {}
        for key in 'abcd':
            output('Request (%s): %s' % (key, _C8_STATES[key]))
            if key == 'd':
                answer = input_fn('Can the client send the other app\'s token from scratch HOME? y/n: ').strip().lower()
                if answer != 'y':
                    attempts[key] = 'not run'
                    _store_c8(directory, key, 'not run', 'not run', b'', b'')
                    continue
            else:
                input_fn('Set the dashboard state above, then press Return: ')
            argv_client = ['cloudflared', 'access', 'ssh', '--hostname', hostname]
            child_env = dict(os.environ)
            child_env['HOME'] = str(home)
            isolation.check_cloudflared(argv_client, child_env)
            input_fn('Press Return to run request (%s): ' % key)
            starts = {'sshd': sshlog.stat().st_size if sshlog.exists() else 0,
                      'connector': connector.stat().st_size if connector.exists() else 0}
            try:
                response = runner(argv_client, env=child_env, capture_output=True, text=True, check=False)
                code = response.returncode
                error = response.stderr or ''
            except Exception as exc:
                code, error = 1, type(exc).__name__
            if sleeper:
                sleeper(0.1)
            ends = {'sshd': sshlog.stat().st_size if sshlog.exists() else starts['sshd'],
                    'connector': connector.stat().st_size if connector.exists() else starts['connector']}
            sshd_slices[key] = _slice_bytes(sshlog, starts['sshd'], ends['sshd'])
            connector_slices[key] = _slice_bytes(connector, starts['connector'], ends['connector'])
            attempts[key] = 'attempted'
            _store_c8(directory, key, code, error, sshd_slices[key], connector_slices[key], starts, ends)
        reached = {key for key in 'bc' if _connection(sshd_slices.get(key, b''))}
        verdicts = classify_c8(sshd_slices, reached, attempts)
        common_connector = set(connector_slices.get('b', b'').decode('utf-8', 'replace').splitlines()) & set(
            connector_slices.get('c', b'').decode('utf-8', 'replace').splitlines())
        _write_safe(directory / 'c8-connector-hints.txt', '\n'.join(sorted(common_connector)) or 'no shared lines', 'connector')
        for key, verdict in verdicts.items(): output('%s: %s' % (key, verdict))
        _write_safe(directory / 'c8-summary.txt', '\n'.join('%s: %s' % item for item in verdicts.items()))
        requests.submit('down')
        if all(verdicts.get(k) in ('void', 'not run') for k in 'abcd'):
            output('origin JWT validation not shown')
            return 3
        return 0
    except (isolation.Refused, OSError, ValueError) as exc:
        print('c8 refused: ' + str(exc), file=sys.stderr); return 2


def _wait_line(path, needle, timeout=60):
    import time
    until = time.monotonic() + timeout
    while time.monotonic() < until:
        if Path(path).exists() and needle in Path(path).read_text(errors='replace'): return True
        time.sleep(.1)
    return False


def _slice_bytes(path, start, end):
    if not Path(path).exists() or end < start: return b''
    with open(path, 'rb') as stream:
        stream.seek(start)
        return stream.read(end - start)


def _store_c8(directory, key, code, error, sshd, connector, starts=None, ends=None):
    starts, ends = starts or {}, ends or {}
    prefix = 'c8-' + key
    _write_safe(directory / (prefix + '-client.txt'), 'exit=%s\nerror=%s' % (code, error), 'recorder')
    _write_safe(directory / (prefix + '-sshd.txt'),
                'byte_offsets=%s:%s\n' % (starts.get('sshd', 'n/a'), ends.get('sshd', 'n/a')) +
                (sshd.decode('utf-8', 'replace') if isinstance(sshd, bytes) else str(sshd)), 'sshd')
    _write_safe(directory / (prefix + '-connector.txt'),
                'byte_offsets=%s:%s\n' % (starts.get('connector', 'n/a'), ends.get('connector', 'n/a')) +
                (connector.decode('utf-8', 'replace') if isinstance(connector, bytes) else str(connector)), 'connector')
    _write_safe(directory / (prefix + '-result.txt'), 'result=' + str(code), 'recorder')


def main_c9(argv=None, runner=None, input_fn=None, output=print):
    try:
        runner = runner or subprocess.run
        input_fn = input_fn or input
        if argv: raise isolation.Refused('unexpected arguments')
        scratch, directory = _capture_dir()
        isolation.refuse_multiplexer(os.environ, ())
        isolation.check_port(42723)
        if not isolation.port_free(42723): raise isolation.Refused('port busy')
        _, root = isolation.scratch_dirs()
        steps, sshd = root / 'root-steps.log', root / 'sshd.log'
        sequence = ('Login with the operator GitHub account', 'Change policy to dummy email; use a private Safari tab',
                    'Revoke existing sessions', 'Stop C9 and try a fresh connection',
                    'Start C9, delete the throwaway app, then try fresh', 'Remove public hostname and check DNS')
        for index, prompt in enumerate(sequence, 1):
            stamp = datetime.datetime.now(datetime.timezone.utc).isoformat()
            output('%s step %d: %s' % (stamp, index, prompt))
            if index == 1: requests.submit('up-c9-hold')
            if index == 4: requests.submit('c9-stop')
            if index == 5: requests.submit('up-c9-hold')
            if index == 6:
                hostname = input_fn('Throwaway hostname: ').strip()
                result = runner(['/usr/bin/dscacheutil', '-q', 'host', '-a', 'name', hostname],
                                capture_output=True, text=True, check=False)
                _record(directory, 'c9-dns.txt', 'exit=%d\n%s' % (result.returncode, result.stdout))
            input_fn('Record the observed outcome, then press Return: ')
            _record(directory, 'c9-step-%d.txt' % index, stamp + ' ' + prompt)
            _record(directory, 'c9-step-%d-sshd-offset.txt' % index,
                    str(sshd.stat().st_size if sshd.exists() else 0))
            _record(directory, 'c9-step-%d-root-offset.txt' % index,
                    str(steps.stat().st_size if steps.exists() else 0))
        return 0
    except (isolation.Refused, OSError, subprocess.SubprocessError) as exc:
        print('c9 refused: ' + str(exc), file=sys.stderr); return 2


def _record(directory, name, text):
    path = directory / name
    isolation.check_write(path)
    path.write_text(text + '\n', encoding='utf-8')
