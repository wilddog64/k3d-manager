"""Review and teardown of operator-side capture artifacts."""
import datetime
import os
import stat
import shutil
import subprocess

from . import isolation, scan


def _down_dirs():
    try:
        return isolation.scratch_dirs()
    except isolation.Refused as exc:
        if str(exc) != 'operator scratch is missing':
            raise
        roots = []
        for candidate in isolation.ROOT_BASE.glob('k3dm-capture-*'):
            suffix = candidate.name[len('k3dm-capture-'):]
            try:
                datetime.date.fromisoformat(suffix)
            except ValueError:
                continue
            info = candidate.lstat()
            if not stat.S_ISDIR(info.st_mode) or candidate.is_symlink():
                raise isolation.Refused('unsafe root scratch')
            roots.append(candidate)
        if len(roots) != 1:
            raise
        root = roots[0]
        operator = isolation.OPERATOR_BASE / ('k3dm-captures-' + root.name[len('k3dm-capture-'):])
        return operator, root


def main_collect(argv=None, input_fn=input, output_fn=print):
    try:
        operator, _ = isolation.scratch_dirs()
        filtered = operator / 'filtered'
        terms = operator / 'terms'
        if filtered.exists() or filtered.is_symlink():
            isolation.check_write(filtered)
        if terms.exists() or terms.is_symlink():
            isolation.check_write(terms)
        approved = []
        for path in sorted(filtered.glob('*')) if filtered.exists() else []:
            if path.is_symlink() or not path.is_file():
                continue
            isolation.check_write(path)
            hits = scan.scan_file(path, terms_path=terms)
            if hits:
                for hit in hits:
                    output_fn('{}: {} line {}'.format(path.name, hit.pattern, hit.line))
                continue
            output_fn('--- ' + path.name + ' ---')
            output_fn(path.read_text(encoding='utf-8', errors='replace'))
            answer = input_fn('Collect this file? [y/n] ').strip().lower()
            if answer == 'y':
                approved.append(path)
        marker = operator / 'collect.complete'
        isolation.check_write(marker)
        if approved:
            date = operator.name[len('k3dm-captures-'):]
            destination = isolation.REPO / 'docs/captures' / (date + '-web-console-b')
            isolation.check_write(destination)
            destination.mkdir(parents=True, exist_ok=True)
            for path in approved:
                target = destination / path.name
                isolation.check_write(target)
                shutil.copyfile(path, target)
            readme = destination / 'README.md'
            isolation.check_write(readme)
            table = ['# Web console part B captures', '', '| Capture | Files | Result | Status |', '|---|---|---|---|']
            table += ['| {} | {} | recorded | not run |'.format(p.stem.rsplit('-', 1)[0], p.name) for p in approved]
            readme.write_text('\n'.join(table) + '\n', encoding='utf-8')
        marker.write_text(datetime.datetime.now().isoformat() + '\n', encoding='utf-8')
        os.chmod(marker, 0o600)
        return 0
    except isolation.Refused:
        raise
    except Exception as exc:
        output_fn('collect: failed (' + type(exc).__name__ + ')')
        return 1


def main_down(argv=None, runner=None, input_fn=input, output_fn=print):
    """Quit the staged driver, teardown root state, then collect or discard scratch."""
    runner = runner or subprocess.run
    try:
        operator, root = _down_dirs()
    except isolation.Refused as exc:
        output_fn(str(exc))
        return 2
    if not operator.exists() and not root.exists():
        output_fn('nothing to remove')
        return 0
    marker = operator / 'collect.complete'
    latest_capture = max((path.stat().st_mtime_ns for path in operator.rglob('*')
                          if path.is_file() and path != marker), default=0) if operator.exists() else 0
    collected_at = marker.stat().st_mtime_ns if marker.exists() else 0
    if operator.exists() and (not marker.exists() or latest_capture > collected_at):
        if input_fn('Type discard to remove uncollected captures: ').strip().lower() != 'discard':
            output_fn('refusing to remove scratch before collect or discard')
            return 2
    request_dir = operator / 'req'
    if request_dir.is_dir():
        try:
            from .requests import submit
            submit('quit')
        except (ImportError, OSError, ValueError):
            pass
    if root.exists():
        teardown = root / 'rootd.py'
        line = ['/usr/bin/sudo', '/Library/Developer/CommandLineTools/usr/bin/python3', '-IS',
                str(teardown), '--teardown']
        try:
            result = runner(line, capture_output=True, text=True, check=False)
        except Exception as exc:
            output_fn('down: teardown failed (' + type(exc).__name__ + ')')
            return 1
        if getattr(result, 'returncode', 1) != 0:
            output_fn('down: teardown failed')
            return 1
    if operator.exists():
        isolation.check_write(operator)
        shutil.rmtree(operator)
    output_fn('Dashboard cleanup: delete both throwaway apps, the throwaway tunnel and capture token; restore any policy change.')
    return 0
