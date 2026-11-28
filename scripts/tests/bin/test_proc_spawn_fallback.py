"""Offline tests for _spawn_capture_text posix_spawn setsid -> setpgroup fallback."""

import os
import shutil
import signal
import sys
import time
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "scripts" / "lib"))

from webhook import proc  # noqa: E402


def _wait_process_gone(pid, deadline_sec=2.0):
    deadline = time.monotonic() + deadline_sec
    while time.monotonic() < deadline:
        try:
            os.kill(pid, 0)
        except ProcessLookupError:
            return True
        except PermissionError:
            return False
        time.sleep(0.05)
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return True
    return False


def test_fallback_retries_with_setpgroup_and_captures_output(monkeypatch):
    """S-M1, S-N1: NotImplementedError on setsid=True falls back to setpgroup=0."""
    real_spawn = os.posix_spawn
    calls = []

    def no_setsid_spawn(path, argv, env, **kwargs):
        calls.append(dict(kwargs))
        if kwargs.get("setsid"):
            raise NotImplementedError("setsid unavailable on this platform")
        return real_spawn(path, argv, env, **kwargs)

    monkeypatch.setattr(proc.os, "posix_spawn", no_setsid_spawn)
    assert proc.os.posix_spawn is no_setsid_spawn

    rc, output, timed_out = proc._spawn_capture_text(
        [sys.executable, "-c", "print('fallback-ok')"],
        timeout=5,
    )

    assert rc == 0
    assert output.strip() == "fallback-ok"
    assert timed_out is False
    assert len(calls) == 2
    assert calls[0].get("setsid") is True
    assert "setpgroup" not in calls[0]
    assert calls[1].get("setpgroup") == 0
    assert "setsid" not in calls[1]
    assert calls[0]["file_actions"] == calls[1]["file_actions"]


def test_fallback_child_leads_own_process_group(monkeypatch):
    """S-M2: In the setpgroup=0 fallback, child reports getpgrp() == getpid()."""
    real_spawn = os.posix_spawn
    calls = []

    def no_setsid_spawn(path, argv, env, **kwargs):
        calls.append(dict(kwargs))
        if kwargs.get("setsid"):
            raise NotImplementedError("setsid unavailable on this platform")
        return real_spawn(path, argv, env, **kwargs)

    monkeypatch.setattr(proc.os, "posix_spawn", no_setsid_spawn)
    assert proc.os.posix_spawn is no_setsid_spawn

    rc, output, timed_out = proc._spawn_capture_text(
        [sys.executable, "-c", "import os; print(os.getpid(), os.getpgrp())"],
        timeout=5,
    )

    assert rc == 0
    assert timed_out is False
    assert len(calls) == 2
    assert calls[1].get("setpgroup") == 0
    child_pid, child_pgrp = (int(tok) for tok in output.strip().split())
    assert child_pgrp == child_pid
    assert child_pgrp != os.getpgrp()


def test_fallback_timeout_kills_grandchild_process_group(monkeypatch, tmp_path):
    """S-M3: Timeout group kill still terminates grandchild in setpgroup=0 fallback."""
    real_spawn = os.posix_spawn
    calls = []

    def no_setsid_spawn(path, argv, env, **kwargs):
        calls.append(dict(kwargs))
        if kwargs.get("setsid"):
            raise NotImplementedError("setsid unavailable on this platform")
        return real_spawn(path, argv, env, **kwargs)

    monkeypatch.setattr(proc.os, "posix_spawn", no_setsid_spawn)
    assert proc.os.posix_spawn is no_setsid_spawn
    assert tmp_path.is_dir()

    pid_file = tmp_path / "grandchild.pid"
    sleep_bin = shutil.which("sleep")
    if sleep_bin:
        gc_argv = [sleep_bin, "30"]
        gc_exe = sleep_bin
    else:
        gc_exe = sys.executable
        gc_argv = [sys.executable, "-c", "import time; time.sleep(30)"]

    child_script = (
        "import os, sys\n"
        "pid_file = sys.argv[1]\n"
        "gc_exe = sys.argv[2]\n"
        "gc_argv = sys.argv[2:]\n"
        "gc_pid = os.posix_spawn(gc_exe, gc_argv, os.environ)\n"
        "tmp = pid_file + '.tmp'\n"
        "with open(tmp, 'w', encoding='utf-8') as fh:\n"
        "    fh.write(f'{gc_pid}\\n')\n"
        "os.replace(tmp, pid_file)\n"
        "os.waitpid(gc_pid, 0)\n"
    )

    gc_pid = None
    try:
        _rc, _output, timed_out = proc._spawn_capture_text(
            [sys.executable, "-c", child_script, str(pid_file), gc_exe, *gc_argv[1:]],
            timeout=1.5,
        )
        assert timed_out is True
        assert len(calls) == 2
        assert calls[1].get("setpgroup") == 0
        assert pid_file.exists(), "child did not record grandchild PID before timeout"
        gc_pid = int(pid_file.read_text(encoding="utf-8").strip())
        assert gc_pid > 0
        assert _wait_process_gone(gc_pid), f"grandchild {gc_pid} survived group kill"
    finally:
        if gc_pid is not None:
            try:
                os.kill(gc_pid, signal.SIGKILL)
            except ProcessLookupError:
                pass


def test_setsid_used_first_and_no_fallback_when_supported(monkeypatch):
    """S-N2: Positive control — setsid=True is used first and no fallback runs on success."""
    real_spawn = os.posix_spawn
    calls = []

    def recording_spawn(path, argv, env, **kwargs):
        calls.append(dict(kwargs))
        return real_spawn(path, argv, env, **kwargs)

    monkeypatch.setattr(proc.os, "posix_spawn", recording_spawn)
    assert proc.os.posix_spawn is recording_spawn

    rc, output, timed_out = proc._spawn_capture_text(
        [sys.executable, "-c", "print('setsid-ok')"],
        timeout=5,
    )

    assert rc == 0
    assert output.strip() == "setsid-ok"
    assert timed_out is False
    assert len(calls) == 1
    assert calls[0].get("setsid") is True
    assert "setpgroup" not in calls[0]


def test_non_notimplemented_error_does_not_trigger_fallback(monkeypatch):
    """Non-NotImplementedError from posix_spawn propagates without retrying."""
    calls = []

    def failing_spawn(path, argv, env, **kwargs):
        calls.append(dict(kwargs))
        raise FileNotFoundError("no such binary")

    monkeypatch.setattr(proc.os, "posix_spawn", failing_spawn)
    assert proc.os.posix_spawn is failing_spawn

    with pytest.raises(FileNotFoundError, match="no such binary"):
        proc._spawn_capture_text(["/nonexistent/binary"], timeout=5)

    assert len(calls) == 1
    assert calls[0].get("setsid") is True
