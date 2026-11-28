"""Operator-side browser profile supervisor."""
import os
import re
import select
import subprocess
import sys
import time
import stat

from . import isolation, requests

SEQUENCE = ('c5', 'c5-exit', 'c5-notty', 'c4-login1', 'c4-login2', 'c15-a', 'c15-b')


class Supervisor:
    def __init__(self, runner=None, input_fn=input, output=print, sleeper=time.sleep,
                 timeout=3600, env=None, clock=time.monotonic, command_reader=None):
        self.runner, self.input, self.output, self.sleep = runner or subprocess.run, input_fn, output, sleeper
        self.timeout, self.env, self.clock = timeout, dict(os.environ if env is None else env), clock
        self.scratch, self.root = isolation.scratch_dirs()
        self.steps = self.root / 'root-steps.log'; self.sshd = self.root / 'sshd.log'
        self.results, self.hash_a = [], None
        self.stopped = False
        self.command_reader = command_reader or self._read_command
        marker = self.scratch / 'browser' / 'c15-a-hash'
        if marker.is_file(): self.hash_a = marker.read_text(encoding='utf-8').strip()

    def fingerprint(self):
        served = self.runner(['/usr/bin/ssh-keyscan', '-p', '42723', '-t', 'ed25519', '127.0.0.1'],
                             capture_output=True, text=True, check=False)
        parsed = self.runner(['/usr/bin/ssh-keygen', '-lf', '-'], input=served.stdout,
                             capture_output=True, text=True, check=False)
        key_file = self.runner(['/usr/bin/ssh-keygen', '-lf', str(self.root / 'host_key.pub')],
                               capture_output=True, text=True, check=False)
        return self._hash(parsed.stdout), self._hash(key_file.stdout)

    @staticmethod
    def _hash(text):
        match = re.search(r'^\d+\s+(SHA256:\S+)', text, re.M)
        return match.group(1) if match else None

    def wait_for(self, predicate):
        end = self.clock() + self.timeout
        while self.clock() < end:
            value = predicate()
            if value: return value
            self.sleep(.25)
        return None

    @staticmethod
    def _read_command():
        ready, _, _ = select.select([sys.stdin], [], [], 0)
        return sys.stdin.readline().strip() if ready else None

    def _watch_profile(self, name):
        end = self.clock() + self.timeout
        while self.clock() < end:
            outcome = self._outcome(name)
            if outcome: return outcome, None
            command = self.command_reader()
            if command:
                if command == 'skip' or command == 'stop': return command, command
                match = re.fullmatch(r'result\s+(accepted|refused|other)', command)
                if match: return 'command', match.group(1)
            self.sleep(.25)
        return None, None

    def profile(self, name):
        if name.startswith('c15-'):
            served, expected = self.fingerprint()
            valid = served == expected and (name != 'c15-b' or (self.hash_a is not None and served != self.hash_a))
            self.output('c15 fingerprint ' + ('matched' if valid else 'void'))
            if not valid:
                self.results.append((name, 'void'))
                self._write_result(name, 'void')
                return True
            if name == 'c15-a': self.hash_a = served
            browser = self.scratch / 'browser'
            isolation.check_write(browser); browser.mkdir(mode=0o700, exist_ok=True)
            comparison = browser / (name + '-comparison')
            isolation.check_write(comparison)
            comparison.write_text('algorithm ed25519\ncomparison matched\n', encoding='utf-8')
        while True:
            previous_abandoned = {path.name for path in (self.scratch / 'browser').glob('abandoned-' + name + '-*')}
            self._abandoned_before = previous_abandoned
            root_offset = self.steps.stat().st_size if self.steps.exists() else 0
            requests.submit('up-' + name)
            if not self.wait_for(lambda: self._event_since(self.steps, root_offset, 'up ' + name)):
                self.results.append((name, 'not run')); self._write_result(name, 'not run')
                self.stopped = True
                return False
            before = self.sshd.stat().st_size if self.sshd.exists() else 0
            self.output('log in now: ' + name)
            outcome, command_value = self._watch_profile(name)
            if outcome == 'abandoned':
                self.output('abandoned; offering ' + name + ' again')
                down_offset = self.steps.stat().st_size if self.steps.exists() else 0
                requests.submit('down')
                self.wait_for(lambda: self._event_since(self.steps, down_offset, 'down'))
                if not isolation.port_free(42723): raise isolation.Refused('port remains busy after abandoned login')
                continue
            if outcome == 'stop':
                self.results.append((name, 'not run'))
                self._write_result(name, 'not run')
                self.stopped = True
            elif outcome == 'skip':
                self.results.append((name, 'not run'))
                self._write_result(name, 'not run')
            elif outcome == 'command':
                status = 'void' if name == 'c4-login1' and command_value == 'refused' else command_value
                self.results.append((name, status))
                self._write_result(name, status)
            else:
                status = 'done' if outcome == 'done' else 'not run'
                self.results.append((name, status))
                if outcome != 'done': self._write_result(name, status)
            self._slice(name, before)
            down_offset = self.steps.stat().st_size if self.steps.exists() else 0
            requests.submit('down')
            self.wait_for(lambda: self._event_since(self.steps, down_offset, 'down'))
            if not isolation.port_free(42723):
                raise isolation.Refused('port remains busy after down')
            if outcome == 'stop': return False
            if name == 'c15-a':
                marker = self.scratch / 'browser' / 'c15-a-hash'
                isolation.check_write(marker); marker.write_text(self.hash_a + '\n', encoding='utf-8')
                rekey_offset = self.steps.stat().st_size if self.steps.exists() else 0
                requests.submit('rekey')
                self.wait_for(lambda: self._event_since(self.steps, rekey_offset, 'rekey'))
            return True

    def _event_since(self, path, offset, event):
        try:
            with path.open('rb') as stream:
                stream.seek(offset)
                return event.encode() in stream.read()
        except OSError:
            return False

    def _write_result(self, name, result):
        browser = self.scratch / 'browser'
        isolation.check_write(browser); browser.mkdir(mode=0o700, exist_ok=True)
        target = browser / ('result-' + name)
        isolation.check_write(target)
        target.write_text(result + '\n', encoding='utf-8')

    def _outcome(self, name):
        browser = self.scratch / 'browser'
        if (browser / ('done-' + name)).exists(): return 'done'
        if browser.exists() and any(path.name not in getattr(self, '_abandoned_before', set())
                                    for path in browser.glob('abandoned-' + name + '-*')): return 'abandoned'
        return None

    def _slice(self, name, start):
        data = self.sshd.read_bytes() if self.sshd.exists() else b''
        end = len(data)
        directory = self.scratch / 'browser'; isolation.check_write(directory)
        directory.mkdir(mode=0o700, exist_ok=True)
        target = directory / ('sshd-' + name + '.txt')
        target.write_bytes(('offsets %d %d\n' % (start, end)).encode() + data[start:end])

    def run(self):
        isolation.refuse_multiplexer(self.env, ())
        isolation.check_port(42723)
        if not isolation.port_free(42723): raise isolation.Refused('port busy')
        ca = self.root / 'access_ca.pub'
        if not ca.is_file(): requests.submit('install-ca')
        token = self.scratch / 'tunnel-token'
        info = token.lstat()
        if not stat.S_ISREG(info.st_mode) or token.is_symlink() or stat.S_IMODE(info.st_mode) != 0o600 or info.st_uid != os.getuid():
            raise isolation.Refused('unsafe token file')
        (self.scratch / 'cfhome').mkdir(mode=0o700, exist_ok=True)
        connector = 'HOME=%s cloudflared tunnel --no-autoupdate --loglevel debug --logfile %s run --token-file %s' % (
            self.scratch / 'cfhome', self.scratch / 'connector.log', token)
        isolation.check_cloudflared(['cloudflared', 'tunnel', '--no-autoupdate', '--loglevel', 'debug', '--logfile',
                                     str(self.scratch / 'connector.log'), 'run', '--token-file', str(token)],
                                    {'HOME': str(self.scratch / 'cfhome')})
        self.output(connector)
        for name in SEQUENCE:
            browser = self.scratch / 'browser'
            if ((browser / ('done-' + name)).exists() or
                    (browser / ('result-' + name)).is_file()):
                continue
            if not self.profile(name) or self.stopped:
                break
        return 0


def main(argv=None):
    try:
        if argv: raise isolation.Refused('unexpected arguments')
        return Supervisor().run()
    except (isolation.Refused, OSError, subprocess.SubprocessError) as exc:
        print('browser-up refused: ' + str(exc), file=sys.stderr); return 2
