"""Submit name-only requests to the root driver."""
import fcntl
import os
import re

try:
    from . import isolation
except ImportError:
    import isolation

PROFILES = ('c5', 'c5-exit', 'c5-notty', 'c4-login1', 'c4-login2', 'c15-a', 'c15-b',
            'c8', 'c9-hold', 'c7', 'c13-ca1', 'c13-ca2')
VERBS = frozenset(('down', 'rekey', 'install-ca', 'install-c7-key', 'c9-stop', 'quit')) | frozenset(
    'up-' + name for name in PROFILES)


def submit(verb):
    if verb not in VERBS:
        raise isolation.Refused('unknown request')
    scratch, _ = isolation.scratch_dirs()
    req = scratch / 'req'
    isolation.check_write(req)
    req.mkdir(mode=0o700, exist_ok=True)
    lock = scratch / 'req.lock'
    isolation.check_write(lock)
    fd = os.open(str(lock), os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX)
        highest = max((int(match.group(1)) for name in os.listdir(req)
                       if (match := re.match(r'^(\d{4})-', name))), default=0)
        if highest >= 9999:
            raise isolation.Refused('request sequence exhausted')
        sequence = highest + 1
        request_fd = os.open(str(req / ('%04d-%s' % (sequence, verb))),
                             os.O_CREAT | os.O_EXCL | os.O_WRONLY | os.O_NOFOLLOW, 0o600)
        os.close(request_fd)
        return sequence
    finally:
        os.close(fd)
