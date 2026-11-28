#!/Library/Developer/CommandLineTools/usr/bin/python3 -IS
"""Foreground, narrowly scoped root driver for capture sshd."""
import argparse
import fcntl
import hashlib
import os
from pathlib import Path
import pwd
import re
import shutil
import signal
import stat
import subprocess
import sys
import time

LABEL = 'com.k3d-manager.capture-sshd'
PROFILES = ('c5', 'c5-exit', 'c5-notty', 'c4-login1', 'c4-login2', 'c15-a', 'c15-b',
            'c8', 'c9-hold', 'c7', 'c13-ca1', 'c13-ca2')
VERBS = frozenset(('down', 'rekey', 'install-ca', 'install-c7-key', 'c9-stop', 'quit')) | frozenset(
    'up-' + name for name in PROFILES)
FILES = frozenset(('rootd.py', 'isolation.py', 'recorder.py', 'principals-any', 'sshd_config.base',
                   'capture-sshd.plist.template'))
NAME = re.compile(r'^(\d{4})-([a-z0-9-]+)$')
KEY = re.compile(r'^(?:ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp(?:256|384|521)) [A-Za-z0-9+/]+={0,2}$')


def _run_command(argv, **kwargs):
    return subprocess.run(argv, capture_output=True, text=True, **kwargs)


class RootDriver:
    def __init__(self, root, scratch=None, login=None, expect=None, runner=_run_command,
                 owner=0, login_uid=None, clock=time.monotonic, idle_timeout=14400,
                 poll_interval=1, launch_timeout=15, lstat=os.lstat, sleep=time.sleep,
                 scratch_parent=Path('/private/tmp'), root_parent=Path('/private/var/db')):
        self.root = Path(root)
        self.scratch_parent = Path(scratch_parent)
        self.root_parent = Path(root_parent)
        self.scratch = Path(scratch) if scratch is not None else None
        self.login = login
        self.expect = expect or {}
        self.runner = runner
        self.owner = owner
        self.login_uid = login_uid
        self.clock = clock
        self.idle_timeout = idle_timeout
        self.poll_interval = poll_interval
        self.launch_timeout = launch_timeout
        self.lstat = lstat
        self.sleep = sleep
        self.lock = None
        self.scratch_fd = None
        self.req_fd = None
        self.ca_fd = None
        self.sequence = 0
        self.profile = None
        self.stop = None
        self.isolation = None

    def _safe(self, path, directory=False):
        st = self.lstat(str(path))
        if st.st_uid != self.owner or st.st_mode & 0o022 or stat.S_ISLNK(st.st_mode):
            raise ValueError('unsafe root file')
        if directory and not stat.S_ISDIR(st.st_mode):
            raise ValueError('not a directory')
        if not directory and not stat.S_ISREG(st.st_mode):
            raise ValueError('not a file')

    def verify(self):
        if self.root.parent != self.root_parent or not re.fullmatch(r'k3dm-capture-\d{4}-\d{2}-\d{2}', self.root.name):
            raise ValueError('invalid root path')
        self._safe(self.root, True)
        if set(self.expect) != FILES:
            raise ValueError('incomplete expected blob list')
        for name in sorted(FILES):
            path = self.root / name
            self._safe(path)
            data = path.read_bytes()
            blob = hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest()
            if blob != self.expect[name]:
                raise ValueError('blob mismatch')
        self._load_isolation()

    def _load_isolation(self):
        import importlib.util
        self._safe(self.root / 'isolation.py')
        spec = importlib.util.spec_from_file_location('capture_root_isolation', str(self.root / 'isolation.py'))
        self.isolation = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.isolation)
        self.isolation.ROOT_BASE = self.root.parent
        if self.scratch is not None:
            self.isolation.OPERATOR_BASE = self.scratch.parent

    def _guard(self):
        if self.isolation is None:
            self._load_isolation()
        self.isolation.check_write(self.root, mode='root')
        self.isolation.check_label(LABEL)
        self.isolation.check_port(42723)

    def acquire(self):
        self._safe(self.root, True)
        self._guard()
        self.lock = os.open(str(self.root / 'rootd.lock'), os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW, 0o644)
        fcntl.flock(self.lock, fcntl.LOCK_EX | fcntl.LOCK_NB)

    def _log(self, event):
        with (self.root / 'root-steps.log').open('a') as stream:
            stream.write('[root %s] %s\n' % (time.strftime('%H:%M:%S'), event))
        os.chmod(str(self.root / 'root-steps.log'), 0o644)

    def open_scratch(self):
        if self.scratch is None or self.scratch.parent != self.scratch_parent or not re.fullmatch(r'k3dm-captures-\d{4}-\d{2}-\d{2}', self.scratch.name):
            raise ValueError('invalid scratch')
        if self.scratch.name[-10:] != self.root.name[-10:]:
            raise ValueError('capture dates differ')
        if not self.login or not re.fullmatch(r'[a-z_][a-z0-9_-]{0,31}', self.login):
            raise ValueError('invalid login')
        self.scratch_fd = os.open(str(self.scratch), os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
        st = os.fstat(self.scratch_fd)
        uid = self.login_uid if self.login_uid is not None else pwd.getpwnam(self.login).pw_uid
        if st.st_uid != uid or stat.S_IMODE(st.st_mode) != 0o700:
            raise ValueError('unsafe scratch')
        self.req_fd = os.open('req', os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=self.scratch_fd)
        self.ca_fd = os.open('ca', os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=self.scratch_fd)
        try:
            previous = int((self.root / 'seq').read_text().strip())
        except FileNotFoundError:
            previous = 0
        present = [int(m.group(1)) for name in os.listdir(self.req_fd) if (m := NAME.fullmatch(name))]
        self.sequence = max([previous] + present)
        self._save_sequence()

    def _save_sequence(self):
        (self.root / 'seq').write_text(str(self.sequence) + '\n')
        os.chmod(str(self.root / 'seq'), 0o644)

    def command(self, *args, check=True):
        self._guard()
        result = self.runner(list(args))
        if check and result.returncode:
            raise RuntimeError('command failed')
        return result

    def pid(self):
        result = self.command('/bin/launchctl', 'print', 'system/' + LABEL, check=False)
        match = re.search(r'\bpid\s*=\s*(\d+)', result.stdout)
        return int(match.group(1)) if result.returncode == 0 and match else None

    def listeners(self):
        output = self.command('/usr/sbin/netstat', '-anv', '-p', 'tcp').stdout
        return [line for line in output.splitlines() if re.search(r'\b127\.0\.0\.1\.42723\b', line)
                and 'LISTEN' in line]

    def down(self):
        self.command('/bin/launchctl', 'bootout', 'system/' + LABEL, check=False)
        if self.listeners():
            raise RuntimeError('capture port remains occupied')
        self.profile = None
        self._log('down')

    def _generate_key(self):
        if not (self.root / 'host_key').exists():
            self.command('/usr/bin/ssh-keygen', '-q', '-t', 'ed25519', '-N', '', '-f', str(self.root / 'host_key'))

    def _config(self, profile):
        ca = str(self.root / ('c13_ca.pub' if profile.startswith('c13-') else 'access_ca.pub'))
        authorized = 'none'
        extra = ''
        if profile == 'c7':
            ca, authorized = 'none', str(self.root / 'c7_authorized_keys')
        if profile == 'c4-login1':
            extra = ('ExposeAuthInfo yes\nAuthorizedPrincipalsCommand %s/principals-any %s %%u %%t %%k\n'
                     'AuthorizedPrincipalsCommandUser %s' % (self.root, self.login, self.login))
        elif profile in ('c5', 'c5-notty'):
            extra = 'PermitTTY ' + ('no' if profile == 'c5-notty' else 'yes')
        return (self.root / 'sshd_config.base').read_text().format(root=self.root, login=self.login,
                                                                  profile=profile, ca=ca,
                                                                  authorized_keys=authorized, extra=extra)

    def _readback(self, profile, data):
        values = {}
        for line in data.splitlines():
            key, _, value = line.partition(' ')
            key = key.lower()
            if key in values and values[key] != value.strip():
                return False
            values[key] = value.strip()
        expected = {'listenaddress': '127.0.0.1:42723', 'port': '42723', 'allowusers': self.login,
                    'permitrootlogin': 'no', 'passwordauthentication': 'no',
                    'kbdinteractiveauthentication': 'no', 'usepam': 'no',
                    'authenticationmethods': 'publickey', 'disableforwarding': 'yes',
                    'permituserenvironment': 'no', 'pidfile': 'none', 'loglevel': 'VERBOSE',
                    'hostkey': str(self.root / 'host_key'), 'setenv': 'ZDOTDIR=' + str(self.root / 'zdotdir'),
                    'forcecommand': str(self.root / 'recorder.py') + ' ' + profile,
                    'authorizedkeysfile': str(self.root / 'c7_authorized_keys') if profile == 'c7' else 'none',
                    'trustedusercakeys': ('none' if profile == 'c7' else str(self.root /
                        ('c13_ca.pub' if profile.startswith('c13-') else 'access_ca.pub')))}
        if profile == 'c4-login1':
            expected['authorizedprincipalscommand'] = str(self.root / 'principals-any') + ' ' + self.login + ' %u %t %k'
            expected['authorizedprincipalscommanduser'] = self.login
            expected['exposeauthinfo'] = 'yes'
        else:
            expected['authorizedprincipalscommand'] = 'none'
        if profile == 'c4-login2':
            expected['authorizedprincipalsfile'] = 'none'
        if profile in ('c5', 'c5-notty'):
            expected['permittty'] = 'no' if profile == 'c5-notty' else 'yes'
        return all((values.get(key, '').lower() == value.lower() if key == 'loglevel'
                    else values.get(key, '') == value) for key, value in expected.items())

    def _read_public_key(self, filename):
        fd = os.open(filename, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=self.ca_fd)
        try:
            st = os.fstat(fd)
            uid = self.login_uid if self.login_uid is not None else pwd.getpwnam(self.login).pw_uid
            if not stat.S_ISREG(st.st_mode) or st.st_uid != uid or st.st_size >= 16384:
                raise ValueError('unsafe file')
            fields = os.read(fd, 16384).decode('ascii').strip().split()
            if len(fields) < 2 or not KEY.fullmatch(' '.join(fields[:2])):
                raise ValueError('bad key')
            return ' '.join(fields[:2]) + '\n'
        finally:
            os.close(fd)

    def _c13_init(self):
        public_keys = [self._read_public_key('c13_user%d.pub' % number) for number in (1, 2)]
        directory = self.root / 'c13'
        directory.mkdir(mode=0o755, exist_ok=True)
        os.chmod(str(directory), 0o755)
        for number, public_key in enumerate(public_keys, 1):
            ca = directory / ('ca%d' % number)
            if not ca.exists():
                self.command('/usr/bin/ssh-keygen', '-q', '-t', 'ed25519', '-N', '', '-f', str(ca))
            os.chmod(str(ca), 0o600)
            os.chmod(str(ca) + '.pub', 0o644)
            user = directory / ('c13_user%d.pub' % number)
            user.write_text(public_key)
            os.chmod(str(user), 0o644)
            self.command('/usr/bin/ssh-keygen', '-s', str(ca), '-I', 'capture', '-n', self.login,
                         '-V', '+1h', str(user))
            os.chmod(str(directory / ('c13_user%d-cert.pub' % number)), 0o644)

    def _c13_switch(self, profile):
        before = self.pid()
        if before is None or not self.profile or not self.profile.startswith('c13-'):
            raise ValueError('c13 daemon not running')
        number = profile[-1]
        (self.root / 'c13_ca.pub').write_bytes((self.root / 'c13' / ('ca%s.pub' % number)).read_bytes())
        after = self.pid()
        self._log('c13 pid before %s after %s' % (before, after))
        if before != after:
            raise RuntimeError('c13 pid changed')
        self.profile = profile

    def up(self, profile):
        if profile not in PROFILES:
            raise ValueError('unknown profile')
        if profile.startswith('c13-'):
            if self.pid() is not None:
                self._c13_switch(profile)
                return
            if profile == 'c13-ca2' or self.profile is not None:
                raise ValueError('c13 daemon not running')
            self._c13_init()
            (self.root / 'c13_ca.pub').write_bytes((self.root / 'c13' / 'ca1.pub').read_bytes())
        elif self.pid() is not None:
            raise ValueError('daemon already running')
        self._generate_key()
        if profile == 'c7':
            (self.root / 'denied').mkdir(mode=0o700, exist_ok=True)
            os.chmod(str(self.root / 'denied'), 0o700)
        config = self.root / 'sshd_config'
        config.write_text(self._config(profile))
        result = self.command('/usr/sbin/sshd', '-T', '-f', str(config), '-C',
                              'user=%s,host=localhost,addr=127.0.0.1' % self.login)
        if not self._readback(profile, result.stdout):
            raise ValueError('readback mismatch')
        if self.listeners():
            raise ValueError('port busy')
        template = (self.root / 'capture-sshd.plist.template').read_text()
        (self.root / 'capture-sshd.plist').write_text(template.replace('{root}', str(self.root)))
        (self.root / 'sshd.log').touch(exist_ok=True)
        os.chmod(str(self.root / 'sshd.log'), 0o644)
        self.command('/bin/launchctl', 'bootstrap', 'system', str(self.root / 'capture-sshd.plist'))
        deadline = self.clock() + self.launch_timeout
        while True:
            pid = self.pid()
            lines = self.listeners()
            uid = self.command('/bin/ps', '-o', 'uid=', '-p', str(pid), check=False) if pid else None
            if (pid and any(re.search(r'\bsshd:%s\b' % pid, line) for line in lines)
                    and uid.returncode == 0 and uid.stdout.strip() == '0'):
                break
            if self.clock() >= deadline:
                raise RuntimeError('listener pid or owner mismatch')
            self.sleep(min(self.poll_interval, max(0, deadline - self.clock())))
        self.profile = profile
        self._log('up ' + profile)
        if profile == 'c13-ca1':
            self._log('c13 pid before none after %s' % pid)

    def install(self, filename, dest, event):
        try:
            content = self._read_public_key(filename)
            (self.root / dest).write_text(content)
            os.chmod(str(self.root / dest), 0o644)
            self._log(event + ' ok')
        except (OSError, UnicodeError, ValueError):
            self._log(event + ' refused invalid')

    def act(self, verb):
        if verb.startswith('up-'):
            self.up(verb[3:])
        elif verb in ('down', 'c9-stop'):
            self.down()
        elif verb == 'quit':
            self.stop = 'quit'
        elif verb == 'rekey':
            for name in ('host_key', 'host_key.pub'):
                (self.root / name).unlink(missing_ok=True)
            self._generate_key()
            self._log('rekey')
        elif verb == 'install-ca':
            self.install('access_ca.pub', 'access_ca.pub', verb)
        elif verb == 'install-c7-key':
            self.install('c7_key.pub', 'c7_authorized_keys', verb)

    def poll(self):
        ignored = 0
        for name in sorted(os.listdir(self.req_fd)):
            match = NAME.fullmatch(name)
            if not match or match.group(2) not in VERBS:
                ignored += 1
                continue
            seq, verb = int(match.group(1)), match.group(2)
            if seq <= self.sequence:
                continue
            self.sequence = seq
            self._save_sequence()
            self.act(verb)
        return ignored

    def run(self):
        self.verify()
        self.acquire()
        self.open_scratch()
        self._log('start')
        last = self.clock()
        ignored_at = last
        try:
            while not self.stop:
                before = self.sequence
                ignored = self.poll()
                now = self.clock()
                if before != self.sequence:
                    last = now
                if ignored and now - ignored_at >= 60:
                    self._log('ignored %d' % ignored)
                    ignored_at = now
                if now - last >= self.idle_timeout:
                    self.stop = 'idle'
                if not self.stop:
                    self.sleep(self.poll_interval)
        finally:
            self.down()
            self._log('exit ' + (self.stop or 'error'))

    def teardown(self):
        if (self.root.parent != self.root_parent or
                not re.fullmatch(r'k3dm-capture-\d{4}-\d{2}-\d{2}', self.root.name)):
            raise ValueError('invalid root path')
        if not self.root.exists() and not self.root.is_symlink():
            return
        self._safe(self.root / 'rootd.py')
        self.acquire()
        self.down()
        shutil.rmtree(str(self.root))


def _install_signals(driver):
    for sig in (signal.SIGINT, signal.SIGHUP, signal.SIGTERM):
        signal.signal(sig, lambda number, frame: setattr(driver, 'stop', signal.Signals(number).name))


def main(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument('--scratch')
    parser.add_argument('--login')
    parser.add_argument('--expect', action='append', default=[])
    parser.add_argument('--teardown', action='store_true')
    args = parser.parse_args(argv)
    root = Path(__file__).absolute().parent
    if not re.fullmatch(r'/private/var/db/k3dm-capture-\d{4}-\d{2}-\d{2}', str(root)):
        print('invalid root path', file=sys.stderr)
        return 2
    try:
        expected = dict(item.split('=', 1) for item in args.expect)
        driver = RootDriver(root, args.scratch, args.login, expected)
        if args.teardown:
            driver.teardown()
        else:
            _install_signals(driver)
            driver.run()
        return 0
    except (OSError, ValueError, RuntimeError) as exc:
        print('driver refused: ' + str(exc), file=sys.stderr)
        return 2


if __name__ == '__main__':
    sys.exit(main())
