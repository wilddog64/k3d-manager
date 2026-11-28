"""Sitting-three local SSH checks; all commands are injectable for offline tests."""
import os
from pathlib import Path
import subprocess
import sys

from . import isolation, requests


class RootChecks:
    def __init__(self, runner=None, output=print):
        self.runner, self.output = runner or subprocess.run, output
        self.scratch, self.root = isolation.scratch_dirs()
        self.ca = self.scratch / 'ca'
        isolation.check_write(self.ca); self.ca.mkdir(mode=0o700, exist_ok=True)

    def call(self, argv, **kwargs):
        return self.runner(argv, capture_output=True, text=True, check=False, **kwargs)

    def generate_user(self, name):
        private = self.ca / name
        isolation.check_write(private)
        result = self.call(['/usr/bin/ssh-keygen', '-q', '-t', 'ed25519', '-N', '', '-f', str(private)])
        if result.returncode: raise isolation.Refused('key generation failed')
        os.chmod(private, 0o600); os.chmod(str(private) + '.pub', 0o644)
        return private

    def c13(self, login):
        key1 = self.generate_user('c13_user1'); key2 = self.generate_user('c13_user2')
        requests.submit('up-c13-ca1')
        driverlog = self.root / 'root-steps.log'
        _wait(driverlog, 'up c13-ca1')
        results = []
        for user, private in ((1, key1), (2, key2)):
            results.append(self.local_c13(user, private, login))
        requests.submit('up-c13-ca2')
        _wait(driverlog, 'up c13-ca2')
        for user, private in ((2, key2), (1, key1)):
            results.append(self.local_c13(user, private, login))
        requests.submit('up-c13-ca1')
        _wait(driverlog, 'up c13-ca1')
        return results

    def local_c13(self, user, private, login):
        cert = self.root / 'c13' / ('c13_user%d-cert.pub' % user)
        known = self.scratch / 'known_hosts'
        isolation.check_write(known); known.touch(mode=0o600, exist_ok=True)
        argv = ['/usr/bin/ssh', '-F', '/dev/null', '-o', 'IdentitiesOnly=yes', '-o', 'IdentityFile=' + str(private),
                '-o', 'CertificateFile=' + str(cert), '-o', 'UserKnownHostsFile=' + str(known), '-p', '42723',
                login + '@127.0.0.1', 'true']
        result = self.call(argv)
        self.output('c13 user%d exit=%d' % (user, result.returncode))
        return result.returncode

    def c7(self, login):
        key = self.generate_user('c7_key')
        request = self.scratch / 'ca' / 'c7_key.pub'
        request.write_bytes(Path(str(key) + '.pub').read_bytes()); os.chmod(request, 0o644)
        requests.submit('install-c7-key')
        _wait(self.root / 'root-steps.log', 'install-c7-key ok')
        known = self.scratch / 'known_hosts'
        known.touch(mode=0o600, exist_ok=True)
        argv = ['/usr/bin/ssh', '-F', '/dev/null', '-o', 'IdentitiesOnly=yes', '-o', 'IdentityFile=' + str(key),
                '-o', 'UserKnownHostsFile=' + str(known), '-p', '42723', login + '@127.0.0.1', 'true']
        result = self.call(argv)
        self.output('c7 exit=%d' % result.returncode)
        return result.returncode

    def run(self, login=None):
        login = login or os.getlogin()
        c13 = self.c13(login)
        requests.submit('up-c7')
        _wait(self.root / 'root-steps.log', 'up c7')
        c7 = self.c7(login)
        requests.submit('down')
        return 0 if c7 == 0 or c13 else 3


def _wait(path, event, timeout=60):
    import time
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        if Path(path).exists() and event in Path(path).read_text(errors='replace'): return True
        time.sleep(.1)
    return False


def main(argv=None, runner=None, output=print):
    try:
        if argv: raise isolation.Refused('unexpected arguments')
        return RootChecks(runner=runner, output=output).run()
    except (isolation.Refused, OSError, subprocess.SubprocessError) as exc:
        print('root-checks refused: ' + str(exc), file=sys.stderr); return 2
