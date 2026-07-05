#!/usr/bin/env python3
"""Fork-safe subprocess primitive for k3dm-webhook.

In-repo modularization (see docs/plans/v1.13.0-webhook-modularization.md):
the posix_spawn-based capture helper extracted verbatim from bin/k3dm-webhook
so the auth slice and future slices can share it without importing the
entrypoint. No command behavior changes.
"""

import os
import signal
import time
from pathlib import Path


def _spawn_capture_text(cmd, cwd=None, env=None, timeout=15):
    """Run cmd via os.posix_spawn and return (rc, output, timed_out).

    This avoids fork()/atfork crashes on macOS after NEF/urllib/ssl load."""
    import tempfile as _tmp
    import shlex as _shlex, shutil as _shutil

    _env = dict(os.environ) if env is None else dict(env)
    with _tmp.NamedTemporaryFile(delete=False) as _out:
        _out_path = _out.name
    try:
        _file_actions = [
            (os.POSIX_SPAWN_OPEN, 1, _out_path,
             os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600),
            (os.POSIX_SPAWN_DUP2, 1, 2),
        ]
        if cwd:
            cmd_str = " ".join(_shlex.quote(str(c)) for c in cmd)
            cmd = ["/bin/bash", "-c", f"cd {_shlex.quote(str(cwd))} && {cmd_str}"]
        exe = cmd[0]
        if not os.path.isabs(exe):
            exe = _shutil.which(exe) or exe
        child_pid = os.posix_spawn(exe, cmd, _env, file_actions=_file_actions, setsid=True)
        deadline = time.time() + timeout
        status = None
        timed_out = False
        while time.time() < deadline:
            try:
                waited_pid, status = os.waitpid(child_pid, os.WNOHANG)
                if waited_pid == child_pid:
                    break
            except ChildProcessError:
                status = 0
                break
            time.sleep(0.1)
        else:
            timed_out = True
            try:
                os.killpg(child_pid, signal.SIGTERM)
            except (ProcessLookupError, OSError):
                pass
            try:
                os.waitpid(child_pid, 0)
            except ChildProcessError:
                pass
        try:
            output = Path(_out_path).read_text(errors="replace")
        except OSError:
            output = ""
        if status is None:
            rc = 124 if timed_out else 1
        elif os.WIFEXITED(status):
            rc = os.WEXITSTATUS(status)
        elif os.WIFSIGNALED(status):
            rc = -os.WTERMSIG(status)
        else:
            rc = 1
        return rc, output, timed_out
    finally:
        try:
            os.unlink(_out_path)
        except OSError:
            pass
