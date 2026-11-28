"""Stage the reviewed capture driver from a git commit."""
import os
from pathlib import Path
import shlex
import stat
import subprocess
import tempfile

try:
    from . import isolation
except ImportError:
    import isolation

REPO = Path(__file__).resolve().parents[3]
FILES = {
    'rootd.py': ('scripts/lib/wcb_capture/rootd.py', '0755'),
    'isolation.py': ('scripts/lib/wcb_capture/isolation.py', '0644'),
    'recorder.py': ('scripts/lib/wcb_capture/recorder.py', '0755'),
    'principals-any': ('scripts/lib/wcb_capture/templates/principals-any', '0755'),
    'sshd_config.base': ('scripts/lib/wcb_capture/templates/sshd_config.base', '0644'),
    'capture-sshd.plist.template': ('scripts/lib/wcb_capture/templates/capture-sshd.plist', '0644'),
}


def _run_command(argv, **kwargs):
    return subprocess.run(argv, check=True, **kwargs)


def main(argv, runner=_run_command, prompt=input, owner=0):
    if argv:
        return 2
    try:
        first, root = isolation.scratch_dirs(create=True)
        status = runner(['/usr/bin/git', 'status', '--porcelain', '--', 'bin/k3dm-wcb-capture',
                         'scripts/lib/wcb_capture'], cwd=str(REPO), stdout=subprocess.PIPE).stdout
        if status:
            raise isolation.Refused('dirty kit tree')
        commit = runner(['/usr/bin/git', 'rev-parse', 'HEAD'], cwd=str(REPO),
                        stdout=subprocess.PIPE).stdout.decode().strip()
        blobs = {}
        contents = {}
        print('commit ' + commit)
        for dest, (source, _) in FILES.items():
            blobs[dest] = runner(['/usr/bin/git', 'rev-parse', commit + ':' + source], cwd=str(REPO),
                                 stdout=subprocess.PIPE).stdout.decode().strip()
            contents[dest] = runner(['/usr/bin/git', 'show', commit + ':' + source], cwd=str(REPO),
                                    stdout=subprocess.PIPE).stdout
            print('%s %s' % (dest, blobs[dest]))
        if prompt('Confirm this is the GitHub branch tip; type yes: ').strip() != 'yes':
            raise isolation.Refused('not confirmed')
        for name in ('req', 'ca'):
            directory = first / name
            isolation.check_write(directory)
            directory.mkdir(mode=0o700, exist_ok=True)
        if root.exists() or root.is_symlink():
            info = root.lstat()
            if not stat.S_ISDIR(info.st_mode) or info.st_uid != owner or info.st_mode & 0o022:
                raise isolation.Refused('unsafe root scratch')
        isolation.check_write(root, mode='root')
        isolation.check_write(root / 'zdotdir', mode='root')
        runner(['/usr/bin/sudo', '/usr/bin/install', '-d', '-o', 'root', '-g', 'wheel', '-m', '0755', str(root)])
        runner(['/usr/bin/sudo', '/usr/bin/install', '-d', '-o', 'root', '-g', 'wheel', '-m', '0755',
                str(root / 'zdotdir')])
        with tempfile.TemporaryDirectory(dir=str(first)) as tmp:
            for dest, (_, mode) in FILES.items():
                source = Path(tmp) / dest
                source.write_bytes(contents[dest])
                os.chmod(source, 0o600)
                isolation.check_write(root / dest, mode='root')
                runner(['/usr/bin/sudo', '/usr/bin/install', '-o', 'root', '-g', 'wheel', '-m', mode,
                        str(source), str(root / dest)])
        login = os.getlogin()
        line = ['/usr/bin/sudo', '/Library/Developer/CommandLineTools/usr/bin/python3', '-IS',
                str(root / 'rootd.py'), '--scratch', str(first), '--login', login]
        for name, blob in blobs.items():
            line.extend(('--expect', name + '=' + blob))
        print(' '.join(shlex.quote(part) for part in line))
        return 0
    except (isolation.Refused, OSError, subprocess.CalledProcessError) as exc:
        print('stage refused: ' + str(exc))
        return 2
