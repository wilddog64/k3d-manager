#!/Library/Developer/CommandLineTools/usr/bin/python3 -IS
"""Attended, non-executing recorder used as sshd ForceCommand."""
import datetime
import errno
import os
from pathlib import Path
import select
import subprocess
import sys
import termios
import time
import tty

from . import isolation

PROFILES = ('c5', 'c5-exit', 'c5-notty', 'c4-login1', 'c4-login2', 'c15-a', 'c15-b', 'c8', 'c9-hold', 'c7', 'c13-ca1', 'c13-ca2')
PREVIOUS = ('error page', 'reconnected by itself', 'blank', 'other')


class Recorder:
    def __init__(self, profile, input_fd=0, output=sys.stdout, env=None, clock=time.monotonic,
                 sleeper=time.sleep, timeout=120, idle_timeout=60, reply_timeout=5, hold_seconds=180,
                 command_runner=subprocess.run):
        if profile not in PROFILES:
            raise isolation.Refused('unknown profile')
        self.profile, self.input_fd, self.output = profile, input_fd, output
        self.env, self.clock, self.sleep = dict(os.environ if env is None else env), clock, sleeper
        self.timeout, self.idle_timeout, self.reply_timeout, self.hold_seconds = timeout, idle_timeout, reply_timeout, hold_seconds
        self.command_runner = command_runner
        self.scratch, _ = isolation.scratch_dirs()
        self.directory = self.scratch / 'browser'
        isolation.check_write(self.directory)
        self.directory.mkdir(mode=0o700, exist_ok=True)
        self.log = self.directory / (profile + '-' + datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S.%fZ') + '.log')
        isolation.check_write(self.log)
        fd = os.open(str(self.log), os.O_CREAT | os.O_APPEND | os.O_WRONLY | getattr(os, 'O_NOFOLLOW', 0), 0o600)
        self.stream = os.fdopen(fd, 'a', encoding='utf-8')

    def write(self, value):
        self.output.write(value + '\n'); self.output.flush()
        self.stream.write(value + '\n'); self.stream.flush()

    def line(self, prompt, choices=None, timeout=None):
        self.output.write(prompt + '\n'); self.output.flush()
        deadline = self.clock() + (self.timeout if timeout is None else timeout)
        data = bytearray()
        while True:
            remaining = deadline - self.clock()
            if remaining <= 0:
                self.write('no bytes' if not data else 'timeout after partial input')
                return None
            try:
                ready, _, _ = select.select([self.input_fd], [], [], remaining)
                if not ready:
                    self.write('no bytes' if not data else 'timeout after partial input')
                    return None
                chunk = os.read(self.input_fd, 1)
            except OSError as exc:
                if exc.errno == errno.EIO:
                    self.write('HUP'); return None
                raise
            if not chunk:
                self.write('EOF'); return None
            if chunk in (b'\n', b'\r'):
                break
            data.extend(chunk)
        value = data.decode('utf-8', 'replace').strip()
        if choices and value not in choices:
            value = 'other'
        return value

    def raw_window(self, prompt, duration, send=None):
        old = termios.tcgetattr(self.input_fd)
        try:
            tty.setraw(self.input_fd)
            attrs = termios.tcgetattr(self.input_fd)
            attrs[6][termios.VMIN] = 0
            attrs[6][termios.VTIME] = 1
            termios.tcsetattr(self.input_fd, termios.TCSANOW, attrs)
            self.output.write(prompt + '\n'); self.output.flush()
            if send:
                os.write(1, send)
            ready, _, _ = select.select([self.input_fd], [], [], duration)
            if not ready:
                result = 'no bytes'
            else:
                data = os.read(self.input_fd, 4096)
                result = 'EOF' if not data else 'bytes ' + data.hex()
            self.write(result)
            return result
        finally:
            termios.tcsetattr(self.input_fd, termios.TCSADRAIN, old)

    def certificate(self):
        auth = self.env.get('SSH_USER_AUTH')
        if not auth:
            self.write('c4 void certificate not inspected'); return
        try:
            lines = Path(auth).read_text(encoding='utf-8').splitlines()
            key = next(line[len('publickey '):] for line in lines if line.startswith('publickey '))
        except (OSError, StopIteration):
            self.write('c4 void certificate not inspected'); return
        result = self.command_runner(['/usr/bin/ssh-keygen', '-L', '-f', '-'], input=key, text=True,
                                     capture_output=True, check=False)
        principal_list = False
        for line in result.stdout.splitlines():
            stripped = line.strip()
            if stripped == 'Principals:':
                principal_list = True
                self.write('Principals:')
            elif principal_list and line[:1].isspace() and stripped:
                self.write('principal length=%d equals_login=%s' %
                           (len(stripped), 'yes' if stripped == self.env.get('USER') else 'no'))
            elif stripped.startswith('Key ID:'):
                value = stripped.split(':', 1)[1].strip().strip('"')
                self.write('Key ID: length=%d equals_login=%s' %
                           (len(value), 'yes' if value == self.env.get('USER') else 'no'))
                principal_list = False
            elif stripped.startswith('Valid:'):
                value = stripped.split(':', 1)[1].strip()
                self.write('Valid: length=%d' % len(value))
                principal_list = False
            elif stripped.startswith('Signing CA:'):
                value = stripped.split(':', 1)[1].strip().split()
                self.write('Signing CA: ' + (value[0] if value else 'unknown') + ' fingerprint=redacted')
                principal_list = False
            elif stripped and not line[:1].isspace():
                principal_list = False

    def run(self):
        steps = {'c5': 5, 'c5-exit': 1, 'c5-notty': 1, 'c4-login1': 1, 'c4-login2': 1, 'c15-a': 1,
                 'c15-b': 1, 'c8': 1, 'c9-hold': 1, 'c7': 1, 'c13-ca1': 1, 'c13-ca2': 1}
        self.output.write('press Return to start %s (step 1/%d)\n' % (self.profile, steps[self.profile])); self.output.flush()
        ready, _, _ = select.select([self.input_fd], [], [], self.timeout)
        if not ready or not os.read(self.input_fd, 4096):
            self.write('abandoned')
            marker = self.directory / ('abandoned-' + self.profile + '-' + datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S.%fZ'))
            isolation.check_write(marker)
            marker_fd = os.open(str(marker), os.O_CREAT | os.O_EXCL | os.O_WRONLY | getattr(os, 'O_NOFOLLOW', 0), 0o600)
            os.close(marker_fd)
            return 3
        self.write('attended start')
        if self.profile != 'c5':
            previous = self.line('Previous session: ' + ', '.join(PREVIOUS), PREVIOUS)
            if previous:
                order = ('c5', 'c5-exit', 'c5-notty', 'c4-login1', 'c4-login2', 'c15-a', 'c15-b')
                index = order.index(self.profile) if self.profile in order else -1
                previous_profile = order[index - 1] if index > 0 else 'previous'
                self.write('prev ' + previous_profile + ' ' + previous)
        if self.profile in ('c5-exit',):
            self.write('exit 3'); self.stream.close(); return 3
        if self.profile == 'c5-notty':
            self.write('pty=' + ('yes' if os.isatty(self.input_fd) else 'no'))
        elif self.profile == 'c4-login1':
            self.certificate()
        elif self.profile.startswith('c15-'):
            comparison = self.directory / (self.profile + '-comparison')
            comparison_text = comparison.read_text(encoding='utf-8').replace('\n', '; ') if comparison.is_file() else 'unavailable'
            self.write('algorithm ed25519; ' + comparison_text)
            answer = self.line('Safari: fingerprint, warning, or nothing?', ('fingerprint', 'warning', 'nothing'))
            if answer: self.write('safari ' + answer)
        elif self.profile == 'c8':
            self.write('reached ' + datetime.datetime.now(datetime.timezone.utc).isoformat())
        elif self.profile == 'c9-hold':
            while True:
                self.write('heartbeat ' + datetime.datetime.now(datetime.timezone.utc).isoformat())
                ready, _, _ = select.select([self.input_fd], [], [], 5)
                if ready and not os.read(self.input_fd, 4096): self.write('EOF'); break
        elif self.profile == 'c5':
            self.write('pty=' + str(os.isatty(self.input_fd)).lower())
            self.write('TERM=' + self.env.get('TERM', ''))
            self.write('env=' + ','.join(sorted(self.env)))
            self.raw_window('Control keys: press Ctrl-C, Ctrl-Z, Ctrl-\\', 10)
            self.raw_window('Unprompted bytes; switch tab', self.idle_timeout)
            self.raw_window('Terminal reply ESC[6n', self.reply_timeout, b'\x1b[6n')
            self.raw_window('Terminal reply ESC[c', self.reply_timeout, b'\x1b[c')
            self.write('leave page untouched for 3 minutes')
            self.sleep(self.hold_seconds)
            self.raw_window('Idle-hold terminal reply ESC[c', self.reply_timeout, b'\x1b[c')
            self.write('idle-hold pid=' + str(os.getpid()))
        elif self.profile == 'c5-exit':
            pass
        if self.profile in ('c4-login2',): self.write('login accepted')
        self.write('done ' + self.profile)
        done = self.directory / ('done-' + self.profile)
        isolation.check_write(done)
        done_fd = os.open(str(done), os.O_CREAT | os.O_EXCL | os.O_WRONLY | getattr(os, 'O_NOFOLLOW', 0), 0o600)
        os.write(done_fd, b'done\n'); os.close(done_fd)
        self.stream.close()
        return 0


def main(argv=None):
    argv = list(sys.argv[1:] if argv is None else argv)
    try:
        if len(argv) != 1: raise isolation.Refused('profile required')
        return Recorder(argv[0]).run()
    except isolation.Refused as exc:
        print('recorder refused: ' + str(exc), file=sys.stderr); return 2


if __name__ == '__main__':
    raise SystemExit(main())
