import base64
import errno
import hashlib
import hmac
import importlib.util
import io
import json
import os
from pathlib import Path
import pty
import re
import select
import shutil
import signal
import socket
import struct
import subprocess
import sys
import termios
import tempfile
import threading
import time
import pytest

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "../../.."))
TOTPD_PATH = os.path.join(REPO_ROOT, "scripts/libexec/k3dm-console-totpd.py")
TOTPCTL_PATH = os.path.join(REPO_ROOT, "scripts/libexec/k3dm-console-totpctl.py")
GATE_PATH = os.path.join(REPO_ROOT, "scripts/libexec/k3dm-console-gate.py")
# agent-audit: allow assert-removed N6/N7/M10 asserts re-indented, scan scoped to part C files
PART_C_LIBEXEC = tuple(os.path.join(REPO_ROOT, "scripts/libexec", name) for name in (
    "k3dm-console-gate.py",
    "k3dm-console-totpd.py",
    "k3dm-console-totpctl.py",
))

def load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod

@pytest.fixture(autouse=True)
def runtime_modules():
    global totpd, totpctl, gate
    totpd = load_module("totpd", TOTPD_PATH)
    totpctl = load_module("totpctl", TOTPCTL_PATH)
    gate = load_module("gate", GATE_PATH)
    previous_handler = signal.getsignal(signal.SIGALRM)
    previous_timer = signal.getitimer(signal.ITIMER_REAL)
    def deadline(_signum, _frame):
        raise TimeoutError("test exceeded 55-second hard deadline")
    signal.signal(signal.SIGALRM, deadline)
    signal.setitimer(signal.ITIMER_REAL, 55)
    try:
        yield
    finally:
        signal.setitimer(signal.ITIMER_REAL, 0)
        signal.signal(signal.SIGALRM, previous_handler)
        if previous_timer[0] > 0:
            signal.setitimer(signal.ITIMER_REAL, *previous_timer)


def make_short_tmpdir():
    base = "/private/tmp" if os.path.exists("/private/tmp") else "/tmp"
    d = tempfile.mkdtemp(prefix="wct.", dir=base)
    assert len(d) < 104
    return d

def _signal_process_group(proc, sig):
    try:
        os.killpg(proc.pid, sig)
    except (ProcessLookupError, PermissionError):
        if proc.poll() is None:
            try:
                proc.send_signal(sig)
            except (ProcessLookupError, PermissionError):
                pass

def _stop_pty_process(proc, master_fd, timeout=2):
    _signal_process_group(proc, signal.SIGTERM)
    try:
        os.close(master_fd)
    except OSError:
        pass
    try:
        proc.wait(timeout=timeout)
    except subprocess.TimeoutExpired:
        _signal_process_group(proc, signal.SIGKILL)
        proc.wait(timeout=timeout)

def make_state_and_run_dirs(tmp):
    state_dir = os.path.join(tmp, "state")
    run_dir = os.path.join(tmp, "run")
    os.makedirs(state_dir, mode=0o700, exist_ok=True)
    os.chmod(state_dir, 0o700)
    os.makedirs(run_dir, mode=0o755, exist_ok=True)
    os.chmod(run_dir, 0o755)
    return state_dir, run_dir

def ps_fixture_output(argv, capture):
    # m4-air, 2026-11-19. c12-chain and c12-admit-session show the parent
    # titles and the two interpreter fields. ps reads comm separately because
    # a Darwin comm (including an sshd-session title) may itself contain spaces.
    rows = [line.split(None, 4) for line in capture.splitlines() if line.strip()]
    if "comm=" in argv:
        return next((r[3] for r in rows if r[0] == argv[-1]), "")
    assert argv[-1] == "pid=,ppid=,uid=,args="
    return "\n".join(" ".join([*r[:3], r[4]]) for r in rows)


def make_stub_runner():
    # Listener row shape from m4-air, 2026-11-19, c12-chain.txt.
    netstat_sample = "tcp4 0 0 127.0.0.1.42722 *.* LISTEN 0 0 131072 131072 sshd:12345 00180 00000006 0000000003cb4f0f 00000000 00000800 1 0 000000"
    ps_uid_sample = "0"
    launchctl_sample = "pid = 12345"
    ps_table_sample = """
12345 1 0 /usr/sbin/sshd /usr/sbin/sshd -D
20001 12345 0 sshd-session sshd-session: someone [priv]
20002 20001 501 sshd-session sshd-session: someone@ttys001
30001 20002 501 /Library/Developer/CommandLineTools/Library/Frameworks/Python3.framework/Versions/3.9/Resources/Python.app/Contents/MacOS/Python /Library/Developer/CommandLineTools/Library/Frameworks/Python3.framework/Versions/3.9/Resources/Python.app/Contents/MacOS/Python -IS /Library/PrivilegedHelperTools/k3dm-web-console/forced-command
"""
    lstart_sample = "Sat Nov 21 04:00:00 2026"
    def runner(cmd, timeout=1.0):
        if cmd[0] == "/bin/ls":
            return totpd.default_runner(cmd, timeout)
        c0 = cmd[0]
        if "netstat" in c0:
            return netstat_sample
        if "ps" in c0:
            if "-o" in cmd and "uid=" in cmd:
                return ps_uid_sample
            if "-o" in cmd and "lstart=" in cmd:
                return lstart_sample
            return ps_fixture_output(cmd, ps_table_sample.replace(" 501 ", f" {os.getuid()} "))
        if "launchctl" in c0:
            return launchctl_sample
        return ""
    return runner

def test_N1_and_M2_totp_vectors_and_replay():
    tmp = make_short_tmpdir()
    server_thread = None
    stop_event = threading.Event()
    try:
        state_dir, run_dir = make_state_and_run_dirs(tmp)
        conf_path = os.path.join(tmp, "totp.conf")
        with open(conf_path, "w") as f:
            f.write(f"uid={os.getuid()}\ntmux=/bin/sh\nidle_seconds=120\nconsole_port=42722\n")
        raw_secret = b"12345678901234567890"
        b32_secret = base64.b32encode(raw_secret).decode("ascii")
        initial_state = {
            "secret": b32_secret,
            "last_counter": 0,
            "failures": 0,
            "locked_until": 0,
            "enrolled": True,
        }
        with open(os.path.join(state_dir, "state.json"), "w") as f:
            json.dump(initial_state, f)
        vectors = [
            (59, "287082"),
            (89, "359152"),
            (119, "969429"),
            (149, "338314"),
            (179, "254676"),
            (359, "481090"),
            (1111111109, "081804"),
        ]
        for t_val, expected_code in vectors:
            code = totpd.compute_hotp(raw_secret, t_val // 30)
            assert code == expected_code
        cur_time = [59.0]
        def clock_fn():
            return cur_time[0]
        runner = make_stub_runner()
        server_thread = threading.Thread(
            target=totpd.run,
            kwargs=dict(
                conf_path=conf_path,
                state_dir=state_dir,
                stop_event=stop_event,
                run_dir=run_dir,
                log_path=os.path.join(tmp, "totp.log"),
                runner=runner,
                peer_cred_fn=lambda s: (os.getuid(), 30001),
                clock=clock_fn,
                expected_conf_owner=os.getuid(),
                expected_dir_owner=os.getuid(),
                exit_on_idle=False,
            ),
            daemon=True,
        )
        server_thread.start()
        sock_path = os.path.join(run_dir, "totp.sock")
        for _ in range(50):
            if os.path.exists(sock_path):
                break
            time.sleep(0.05)
        def send_verify(c):
            s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            s.connect(sock_path)
            s.sendall(f"VERIFY {c}\n".encode("ascii"))
            resp = b""
            while b"\n" not in resp:
                chunk = s.recv(32)
                if not chunk:
                    break
                resp += chunk
            s.close()
            return resp.decode("ascii").strip()
        resp = send_verify("287082")
        assert resp == "OK"
        resp_reuse = send_verify("287082")
        assert resp_reuse == "NO"
        cur_time[0] = 89.0
        resp_next = send_verify("359152")
        assert resp_next == "OK"
        cur_time[0] = 119.0
        resp_c2 = send_verify("359152")
        assert resp_c2 == "NO"
        resp_c4 = send_verify("338314")
        assert resp_c4 == "OK"
        resp_c1 = send_verify("287082")
        assert resp_c1 == "NO"
        resp_c5 = send_verify("254676")
        assert resp_c5 == "NO"
        cur_time[0] = 1111111109.0
        resp_big = send_verify("081804")
        assert resp_big == "OK"
    finally:
        stop_event.set()
        if server_thread is not None:
            server_thread.join(timeout=4)
            assert not server_thread.is_alive()
        shutil.rmtree(tmp, ignore_errors=True)

def test_N1_and_M2_lockout_and_hmac_calls():
    tmp = make_short_tmpdir()
    server_thread = None
    stop_event = threading.Event()
    try:
        state_dir, run_dir = make_state_and_run_dirs(tmp)
        conf_path = os.path.join(tmp, "totp.conf")
        with open(conf_path, "w") as f:
            f.write(f"uid={os.getuid()}\ntmux=/bin/sh\nidle_seconds=120\nconsole_port=42722\n")
        raw_secret = b"12345678901234567890"
        b32_secret = base64.b32encode(raw_secret).decode("ascii")
        initial_state = {
            "secret": b32_secret,
            "last_counter": 0,
            "failures": 0,
            "locked_until": 0,
            "enrolled": True,
        }
        with open(os.path.join(state_dir, "state.json"), "w") as f:
            json.dump(initial_state, f)
        cur_time = [59.0]
        mono_time = [10.0]
        def clock_fn():
            return cur_time[0]
        hmac_count = [0]
        def counted_hmac(key, msg):
            hmac_count[0] += 1
            return hmac.new(key, msg, hashlib.sha1).digest()
        server_thread = threading.Thread(
            target=totpd.run,
            kwargs=dict(
                conf_path=conf_path,
                state_dir=state_dir,
                stop_event=stop_event,
                run_dir=run_dir,
                log_path=os.path.join(tmp, "totp.log"),
                runner=make_stub_runner(),
                peer_cred_fn=lambda s: (os.getuid(), 30001),
                clock=clock_fn,
                monotonic=lambda: mono_time[0],
                expected_conf_owner=os.getuid(),
                expected_dir_owner=os.getuid(),
                exit_on_idle=False,
                hmac_fn=counted_hmac,
            ),
            daemon=True,
        )
        server_thread.start()
        sock_path = os.path.join(run_dir, "totp.sock")
        for _ in range(50):
            if os.path.exists(sock_path):
                break
            time.sleep(0.05)
        def send_verify(c):
            s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            s.connect(sock_path)
            s.sendall(f"VERIFY {c}\n".encode("ascii"))
            resp = b""
            while b"\n" not in resp:
                chunk = s.recv(32)
                if not chunk:
                    break
                resp += chunk
            s.close()
            return resp.decode("ascii").strip()
        for i in range(5):
            r = send_verify("000000")
            assert r == "NO"
        assert hmac_count[0] == 15
        before_lock_hmac = hmac_count[0]
        resp_locked = send_verify("287082")
        assert resp_locked == "WAIT 300"
        assert hmac_count[0] == before_lock_hmac
        cur_time[0] = 358.0
        mono_time[0] = 309.0
        resp_locked_1 = send_verify("287082")
        assert resp_locked_1 == "WAIT 1"
        assert hmac_count[0] == before_lock_hmac
        mono_time[0] = 310.0
        resp_after_expiry_wrong = send_verify("000000")
        assert resp_after_expiry_wrong == "NO"
        with open(os.path.join(state_dir, "state.json")) as f:
            st = json.load(f)
        assert st["failures"] == 1
        assert st["locked_until"] == 359  # agent-audit: allow assert-removed expired deadline now retained for escalation (M1/N1)
        resp_after_expiry_ok = send_verify("481090")
        assert resp_after_expiry_ok == "OK"
        with open(os.path.join(state_dir, "state.json")) as f:
            st = json.load(f)
        assert st["failures"] == 0
        cur_time[0] = 389.0
        for _ in range(4):
            assert send_verify("000000") == "NO"
        assert send_verify(totpd.compute_hotp(raw_secret, 12)) == "OK"
        with open(os.path.join(state_dir, "state.json")) as stream:
            assert json.load(stream)["failures"] == 0
    finally:
        stop_event.set()
        if server_thread is not None:
            server_thread.join(timeout=4)
            assert not server_thread.is_alive()
        shutil.rmtree(tmp, ignore_errors=True)

def test_N10_and_E1_commit_failure_and_crash_safety():
    tmp = make_short_tmpdir()
    server_thread = None
    stop_event = threading.Event()
    try:
        state_dir, run_dir = make_state_and_run_dirs(tmp)
        conf_path = os.path.join(tmp, "totp.conf")
        with open(conf_path, "w") as f:
            f.write(f"uid={os.getuid()}\ntmux=/bin/sh\nidle_seconds=120\nconsole_port=42722\n")
        raw_secret = b"12345678901234567890"
        b32_secret = base64.b32encode(raw_secret).decode("ascii")
        initial_state = {
            "secret": b32_secret,
            "last_counter": 0,
            "failures": 0,
            "locked_until": 0,
            "enrolled": True,
        }
        with open(os.path.join(state_dir, "state.json"), "w") as f:
            json.dump(initial_state, f)
        for fault in ("pre-rename-open", "pre-rename-write", "pre-rename-fsync", "pre-rename-replace"):
            with pytest.raises(totpd.CommitPreRenameError):
                totpd.commit_state(state_dir, initial_state, fault=fault)
            assert not os.path.exists(os.path.join(state_dir, "state.json.tmp"))
        with pytest.raises(totpd.CommitPostRenameError):
            totpd.commit_state(state_dir, initial_state, fault="post-rename-dir-fsync")
        leftover = os.path.join(state_dir, "state.json.tmp")
        with open(leftover, "w") as f:
            f.write("corrupted data")
        cur_time = [59.0]
        server_thread = threading.Thread(
            target=totpd.run,
            kwargs=dict(
                conf_path=conf_path,
                state_dir=state_dir,
                stop_event=stop_event,
                run_dir=run_dir,
                log_path=os.path.join(tmp, "totp.log"),
                clock=lambda: cur_time[0],
                peer_cred_fn=lambda s: (0, os.getpid()),
                expected_conf_owner=os.getuid(),
                expected_dir_owner=os.getuid(),
                exit_on_idle=False,
            ),
            daemon=True,
        )
        server_thread.start()
        sock_path = os.path.join(run_dir, "totp.sock")
        for _ in range(50):
            if os.path.exists(sock_path):
                break
            time.sleep(0.05)
        assert not os.path.exists(leftover)
    finally:
        stop_event.set()
        if server_thread is not None:
            server_thread.join(timeout=4)
            assert not server_thread.is_alive()
        shutil.rmtree(tmp, ignore_errors=True)

def test_N1_and_E1_wire_rejections():
    tmp = make_short_tmpdir()
    server_thread = None
    stop_event = threading.Event()
    try:
        state_dir, run_dir = make_state_and_run_dirs(tmp)
        conf_path = os.path.join(tmp, "totp.conf")
        with open(conf_path, "w") as f:
            f.write(f"uid={os.getuid()}\ntmux=/bin/sh\nidle_seconds=120\nconsole_port=42722\n")
        raw_secret = b"12345678901234567890"
        b32_secret = base64.b32encode(raw_secret).decode("ascii")
        with open(os.path.join(state_dir, "state.json"), "w") as f:
            json.dump({"secret": b32_secret, "last_counter": 0, "failures": 0, "locked_until": 0, "enrolled": True}, f)
        server_thread = threading.Thread(
            target=totpd.run,
            kwargs=dict(
                conf_path=conf_path,
                state_dir=state_dir,
                stop_event=stop_event,
                run_dir=run_dir,
                log_path=os.path.join(tmp, "totp.log"),
                runner=make_stub_runner(),
                peer_cred_fn=lambda s: (os.getuid(), 30001),
                expected_conf_owner=os.getuid(),
                expected_dir_owner=os.getuid(),
                exit_on_idle=False,
            ),
            daemon=True,
        )
        server_thread.start()
        sock_path = os.path.join(run_dir, "totp.sock")
        for _ in range(50):
            if os.path.exists(sock_path):
                break
            time.sleep(0.05)
        bad_payloads = [
            b"A" * 33 + b"\n",
            b"VERIFY 12345\n",
            b"VERIFY 1234567\n",
            b"VERIFY abcdef\n",
            b"HELLO\n",
            b"VERIFY 123456",
            b"VERIFY \xff\xff\xff\xff\xff\xff\n",
        ]
        for p in bad_payloads:
            s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            s.connect(sock_path)
            s.sendall(p)
            if b"\n" not in p:
                s.shutdown(socket.SHUT_WR)
            s.settimeout(1.0)
            data = s.recv(32)
            assert data == b""
            s.close()
        with open(os.path.join(state_dir, "state.json")) as f:
            st = json.load(f)
        assert st["failures"] == 0
    finally:
        stop_event.set()
        if server_thread is not None:
            server_thread.join(timeout=4)
            assert not server_thread.is_alive()
        shutil.rmtree(tmp, ignore_errors=True)

def test_N3_and_E2_admit_logic():
    conf = {
        "uid": 501,
        "tmux": "/opt/homebrew/bin/tmux",
        "idle_seconds": 120,
        "console_port": 42722,
    }
    # Listener row shape from m4-air, 2026-11-19, c12-chain.txt.
    netstat_sample = "tcp4 0 0 127.0.0.1.42722 *.* LISTEN 0 0 131072 131072 sshd:12345 00180 00000006 0000000003cb4f0f 00000000 00000800 1 0 000000"
    ps_uid_sample = "0"
    launchctl_sample = "pid = 12345"
    ps_table_sample = """
12345 1 0 /usr/sbin/sshd /usr/sbin/sshd -D
20001 12345 0 sshd-session sshd-session: someone [priv]
20002 20001 501 sshd-session sshd-session: someone@ttys001
30001 20002 501 /Library/Developer/CommandLineTools/Library/Frameworks/Python3.framework/Versions/3.9/Resources/Python.app/Contents/MacOS/Python /Library/Developer/CommandLineTools/Library/Frameworks/Python3.framework/Versions/3.9/Resources/Python.app/Contents/MacOS/Python -IS /Library/PrivilegedHelperTools/k3dm-web-console/forced-command
40001 30001 501 tmux tmux attach-session -E -t =work
40002 1 501 tmux-server tmux new-session -d -s work
40003 40002 501 zsh /bin/zsh
30002 30001 501 /Library/Developer/CommandLineTools/Library/Frameworks/Python3.framework/Versions/3.9/Resources/Python.app/Contents/MacOS/Python /Library/Developer/CommandLineTools/Library/Frameworks/Python3.framework/Versions/3.9/Resources/Python.app/Contents/MacOS/Python -IS /Library/PrivilegedHelperTools/k3dm-web-console/forced-command
"""
    lstart_sample = "Sat Nov 21 04:00:00 2026"
    def stub_runner(cmd, timeout=1.0):
        if cmd[0] == "/bin/ls":
            return totpd.default_runner(cmd, timeout)
        c0 = cmd[0]
        if "netstat" in c0:
            return netstat_sample
        if "ps" in c0:
            if "-o" in cmd and "uid=" in cmd:
                return ps_uid_sample
            if "-o" in cmd and "lstart=" in cmd:
                return lstart_sample
            return ps_fixture_output(cmd, ps_table_sample)
        if "launchctl" in c0:
            if len(cmd) > 2 and "com.k3d-manager.web-console-sshd" in cmd[2]:
                return launchctl_sample
            return "Could not find service in domain for system"
        return ""
    class DummySock:
        pass
    def cred_fn_peer(sock):
        return 501, 30001
    res = totpd.admit(DummySock(), conf, stub_runner, peer_cred_fn=cred_fn_peer)
    assert res is True
    assert totpd.admit(DummySock(), conf, stub_runner, peer_cred_fn=lambda s: (502, 30001)) is False
    assert totpd.admit(DummySock(), conf, stub_runner, peer_cred_fn=lambda s: (501, 40001)) is False
    assert totpd.admit(DummySock(), conf, stub_runner, peer_cred_fn=lambda s: (501, 40002)) is False
    assert totpd.admit(DummySock(), conf, stub_runner, peer_cred_fn=lambda s: (501, 40003)) is False
    assert totpd.admit(DummySock(), conf, stub_runner, peer_cred_fn=lambda s: (501, 30002)) is False
    assert totpd.admit(DummySock(), conf, stub_runner, peer_cred_fn=cred_fn_peer, job_label="wrong.label") is False
    assert totpd.admit(DummySock(), conf, stub_runner, peer_cred_fn=cred_fn_peer, gate_path="/wrong/gate") is False

def test_N6_and_N7_source_scan():
    assert all(os.path.isfile(path) for path in PART_C_LIBEXEC)
    for fpath in PART_C_LIBEXEC:
        fname = os.path.basename(fpath)
        with open(fpath, "r", encoding="utf-8") as f:
            content = f.read()
        if fname == "k3dm-console-totpd.py":
            assert "os.environ" not in content
        if fname == "k3dm-console-gate.py":
            tokens = re.findall(r'os\.environ(?:\["([A-Z_]+)"\]|\.get\("([A-Z_]+)"\))', content)
            used_keys = {k1 or k2 for (k1, k2) in tokens if (k1 or k2)}
            assert used_keys.issubset({"HOME", "USER", "LOGNAME", "TERM", "LANG"})
        for line in content.splitlines():
            if line.strip().startswith("#"):
                continue
            assert "/usr/bin/python3" not in line

def test_N5_and_N9_and_E3_admin_enrol_and_rotate():
    tmp = make_short_tmpdir()
    server_thread = None
    stop_event = threading.Event()
    try:
        state_dir, run_dir = make_state_and_run_dirs(tmp)
        conf_path = os.path.join(tmp, "totp.conf")
        with open(conf_path, "w") as f:
            f.write(f"uid={os.getuid()}\ntmux=/bin/sh\nidle_seconds=120\nconsole_port=42722\n")
        cur_time = [100.0]
        server_thread = threading.Thread(
            target=totpd.run,
            kwargs=dict(
                conf_path=conf_path,
                state_dir=state_dir,
                stop_event=stop_event,
                run_dir=run_dir,
                log_path=os.path.join(tmp, "totp.log"),
                clock=lambda: cur_time[0],
                peer_cred_fn=lambda s: (0, os.getpid()),
                expected_conf_owner=os.getuid(),
                expected_dir_owner=os.getuid(),
                exit_on_idle=False,
            ),
            daemon=True,
        )
        server_thread.start()
        admin_sock = os.path.join(run_dir, "admin.sock")
        for _ in range(50):
            if os.path.exists(admin_sock):
                break
            time.sleep(0.05)
        def send_admin(cmd):
            s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            s.connect(admin_sock)
            s.sendall(cmd.encode("ascii") + b"\n")
            resp = b""
            while b"\n" not in resp:
                chunk = s.recv(32)
                if not chunk:
                    break
                resp += chunk
            s.close()
            return resp.decode("ascii").strip()
        assert send_admin("STATUS") == "NOT_ENROLLED"
        b_resp = send_admin("ENROLL_BEGIN")
        assert b_resp.startswith("SECRET ")
        secret_b32 = b_resp.split()[1]
        assert len(secret_b32) == 32
        assert send_admin("ENROLL_BEGIN") == "REFUSED"
        raw_sec = base64.b32decode(secret_b32)
        code = totpd.compute_hotp(raw_sec, int(cur_time[0] // 30))
        c_resp = send_admin(f"ENROLL_COMMIT {code}")
        assert c_resp == "OK"
        assert send_admin("STATUS") == "ENROLLED"
        assert send_admin("ENROLL_BEGIN") == "ENROLLED"
        r_resp = send_admin("ROTATE_BEGIN")
        assert r_resp.startswith("SECRET ")
        new_secret_b32 = r_resp.split()[1]
        new_raw_sec = base64.b32decode(new_secret_b32)
        new_code = totpd.compute_hotp(new_raw_sec, int(cur_time[0] // 30))
        rot_commit = send_admin(f"ROTATE_COMMIT {new_code}")
        assert rot_commit == "OK"
        with open(os.path.join(state_dir, "state.json")) as f:
            st = json.load(f)
        assert st["secret"] == new_secret_b32
    finally:
        stop_event.set()
        if server_thread is not None:
            server_thread.join(timeout=4)
            assert not server_thread.is_alive()
        shutil.rmtree(tmp, ignore_errors=True)

def test_N8_and_E4_gate_prompt_failures():
    tmp = make_short_tmpdir()
    try:
        conf_path = os.path.join(tmp, "totp.conf")
        with open(conf_path, "w") as f:
            f.write(f"uid={os.getuid()}\ntmux=/bin/sh\nidle_seconds=120\nconsole_port=42722\n")
        sock_path = os.path.join(tmp, "totp.sock")
        instance = GateProcess(Path(tmp), dict(
            conf_path=conf_path,
            sock_path=sock_path,
            expected_conf_owner=os.getuid(),
            expected_server_uid=os.getuid(),
            prompt_timeout=2,
            refuse_connect=True,
        ))
        try:
            instance.until(b"Code: ")
            instance.send(b"123456\n")
            instance.until(b"console login unavailable")
            assert instance.proc.wait(timeout=2) == 1
        finally:
            instance.close()
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

def test_N2_and_N4_and_E5_terminal_filter():
    cpr = b"\x1b[12;34R"
    assert gate.is_terminal_reply(cpr) is True
    da = b"\x1b[?62;1;2;6;7;8;9c"
    assert gate.is_terminal_reply(da) is True
    focus = b"\x1b[I"
    assert gate.is_terminal_reply(focus) is True
    dsr = b"\x1b[0n"
    assert gate.is_terminal_reply(dsr) is True
    win = b"\x1b[8;24;80t"
    assert gate.is_terminal_reply(win) is True
    osc = b"\x1b]11;rgb:0000/0000/0000\x07"
    assert gate.is_terminal_reply(osc) is True
    assert gate.is_terminal_reply(b"\x1b[A") is False
    assert gate.is_terminal_reply(b"hello") is False

def test_N6_and_N7_and_M10_gate_entry():
    assert all(os.path.isfile(path) for path in PART_C_LIBEXEC)
    if sys.platform != "darwin":
        pytest.skip("gate entry test is Darwin-only")
    tmp = make_short_tmpdir()
    try:
        scratch = os.path.join(tmp, "scratch")
        os.makedirs(scratch)
        for name in (".zshenv", ".zprofile", ".zshrc", ".zlogin"):
            with open(os.path.join(scratch, name), "w") as f:
                f.write(f"touch {scratch}/marker_{name}\n")
        ub = os.path.join(scratch, "ub")
        os.makedirs(ub)
        pp = os.path.join(scratch, "pp")
        os.makedirs(pp)
        with open(os.path.join(pp, "sitecustomize.py"), "w") as f:
            f.write(f"import os; os.system('touch {scratch}/marker_sitecustomize')\n")
        py = "/Library/Developer/CommandLineTools/usr/bin/python3"
        assert Path(py).is_file()
        user_site = subprocess.check_output(
            [py, "-s", "-c", "import site; print(site.getusersitepackages())"],
            env={"HOME": scratch, "PYTHONUSERBASE": ub}, text=True,
        ).strip()
        assert Path(ub) in Path(user_site).parents
        Path(user_site).mkdir(parents=True)
        marker = Path(scratch, "marker_usercustomize")
        Path(user_site, "usercustomize.py").write_text(f"open({str(marker)!r}, 'w').close()")
        with open(GATE_PATH, "r") as f:
            first_line = f.readline().strip()
        assert first_line == "#!/Library/Developer/CommandLineTools/usr/bin/python3 -IS"
        env = {
            "HOME": scratch,
            "ZDOTDIR": "/var/empty",
            "PATH": "/usr/bin:/bin",
            "PYTHONPATH": pp,
            "PYTHONSTARTUP": os.path.join(scratch, "s.py"),
            "PYTHONUSERBASE": ub,
        }
        res = subprocess.run(
            ["/bin/zsh", "-c", GATE_PATH],
            env=env,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        assert res.returncode == 1
        assert b"console: an interactive terminal is required" in res.stderr
        for name in (".zshenv", ".zprofile", ".zshrc", ".zlogin", "sitecustomize"):
            assert not os.path.exists(os.path.join(scratch, f"marker_{name}"))
        assert not marker.exists()
        assert env["HOME"] == scratch
        no_zdot = env.copy()
        del no_zdot["ZDOTDIR"]
        subprocess.run(["/bin/zsh", "-c", GATE_PATH], env=no_zdot, stdin=subprocess.DEVNULL)
        assert Path(scratch, "marker_.zshenv").exists()
        source = Path(GATE_PATH).read_text().splitlines(keepends=True)
        for flags, expected in [("-IS", b"False"), ("-I", b"True"), ("", b"True")]:
            entry = Path(scratch, "entry")
            entry.write_text(f"#!{py} {flags}\nimport sys\nprint('site' in sys.modules, file=sys.stderr)\n" + "".join(source[1:]))
            entry.chmod(0o755)
            result = subprocess.run([str(entry)], env=env, stdin=subprocess.DEVNULL, capture_output=True)
            assert result.returncode == 1 and expected in result.stderr.splitlines()
        assert marker.exists()
        assert Path(scratch, "marker_sitecustomize").exists()
        forbidden = re.compile(rb"(?:^|[\s\x22\x27]|#!)/usr/bin/python3(?:$|[\s\x22\x27])")
        for entry in PART_C_LIBEXEC:
            assert not forbidden.search(Path(entry).read_bytes()), entry
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

def test_N4_and_E5_tmux_allowed_commands():
    allowed_subcommands = {"has-session", "new-session", "attach-session"}
    sample_calls = [
        ["tmux", "has-session", "-t", "=work"],
        ["tmux", "new-session", "-d", "-s", "work"],
        ["tmux", "attach-session", "-E", "-t", "=work"],
    ]
    for call in sample_calls:
        subcmd = call[1]
        assert subcmd in allowed_subcommands
    disallowed = ["set-option", "lock-after-time", "lock-command", "list-clients", "detach-client"]
    for d in disallowed:
        assert d not in allowed_subcommands

def test_N7_and_E2_directory_permissions():
    tmp = make_short_tmpdir()
    try:
        state_dir, run_dir = make_state_and_run_dirs(tmp)
        assert os.stat(run_dir).st_mode & 0o777 == 0o755
        assert os.stat(state_dir).st_mode & 0o777 == 0o700
        symlink_run = os.path.join(tmp, "sym_run")
        os.symlink(run_dir, symlink_run)
        conf_path = os.path.join(tmp, "totp.conf")
        with open(conf_path, "w") as f:
            f.write(f"uid={os.getuid()}\ntmux=/bin/sh\nidle_seconds=120\nconsole_port=42722\n")
        assert totpd.run(conf_path=conf_path, state_dir=state_dir, run_dir=symlink_run, expected_dir_owner=os.getuid()) == 1
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

def test_N9_and_E3_rotate_commit():
    tmp = make_short_tmpdir()
    server_thread = None
    stop_event = threading.Event()
    try:
        state_dir, run_dir = make_state_and_run_dirs(tmp)
        conf_path = os.path.join(tmp, "totp.conf")
        with open(conf_path, "w") as f:
            f.write(f"uid={os.getuid()}\ntmux=/bin/sh\nidle_seconds=120\nconsole_port=42722\n")
        old_secret = base64.b32encode(b"oldsecret12345678901").decode("ascii")
        with open(os.path.join(state_dir, "state.json"), "w") as f:
            json.dump({"secret": old_secret, "last_counter": 10, "failures": 0, "locked_until": 0, "enrolled": True}, f)
        cur_time = [300.0]
        server_thread = threading.Thread(
            target=totpd.run,
            kwargs=dict(
                conf_path=conf_path,
                state_dir=state_dir,
                stop_event=stop_event,
                run_dir=run_dir,
                log_path=os.path.join(tmp, "totp.log"),
                clock=lambda: cur_time[0],
                peer_cred_fn=lambda s: (0, os.getpid()),
                expected_conf_owner=os.getuid(),
                expected_dir_owner=os.getuid(),
                exit_on_idle=False,
            ),
            daemon=True,
        )
        server_thread.start()
        admin_sock = os.path.join(run_dir, "admin.sock")
        for _ in range(50):
            if os.path.exists(admin_sock):
                break
            time.sleep(0.05)
        def send_admin(cmd):
            s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            s.connect(admin_sock)
            s.sendall(cmd.encode("ascii") + b"\n")
            resp = b""
            while b"\n" not in resp:
                chunk = s.recv(32)
                if not chunk:
                    break
                resp += chunk
            s.close()
            return resp.decode("ascii").strip()
        resp = send_admin("ROTATE_BEGIN")
        assert resp.startswith("SECRET ")
        new_sec = resp.split()[1]
        assert send_admin("ROTATE_COMMIT 000000") == "NO"
        with open(os.path.join(state_dir, "state.json")) as f:
            st = json.load(f)
        assert st["secret"] == old_secret
        raw_new = base64.b32decode(new_sec)
        valid_code = totpd.compute_hotp(raw_new, int(cur_time[0] // 30))
        assert send_admin(f"ROTATE_COMMIT {valid_code}") == "OK"
        with open(os.path.join(state_dir, "state.json")) as f:
            st = json.load(f)
        assert st["secret"] == new_sec
    finally:
        stop_event.set()
        if server_thread is not None:
            server_thread.join(timeout=4)
            assert not server_thread.is_alive()
        shutil.rmtree(tmp, ignore_errors=True)

def test_N12_and_E4_verifier_socket_not_in_child():
    tmp = make_short_tmpdir()
    try:
        conf_path = os.path.join(tmp, "totp.conf")
        with open(conf_path, "w") as f:
            f.write(f"uid={os.getuid()}\ntmux=/bin/sh\nidle_seconds=120\nconsole_port=42722\n")
        sock_path = os.path.join(tmp, "totp.sock")
        srv = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        srv.bind(sock_path)
        srv.listen(1)
        connected_peer_pid = [None]
        def srv_loop():
            try:
                conn, _ = srv.accept()
                if hasattr(socket, "SOL_LOCAL"):
                    sol_local = getattr(socket, "SOL_LOCAL", 0)
                    pid_bytes = conn.getsockopt(sol_local, 2, 4)
                    connected_peer_pid[0] = struct.unpack("i", pid_bytes)[0]
                conn.recv(64)
                conn.sendall(b"OK\n")
                conn.close()
            except Exception:
                pass
        t_srv = threading.Thread(target=srv_loop, daemon=True)
        t_srv.start()
        v_res = gate.verify_totp(sock_path, "287082", expected_server_uid=os.getuid())
        assert v_res == "OK"
        srv.close()
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


class VerifierFixture:
    def __init__(self, root):
        self.root = Path(root)
        assert self.root.name.startswith("wct.") and self.root.is_dir()
        self.state_dir, self.run_dir = make_state_and_run_dirs(root)
        assert Path(self.state_dir).is_relative_to(self.root)
        assert Path(self.run_dir).is_relative_to(self.root)
        self.config = self.root / "totp.conf"
        self.config.write_text("uid=501\ntmux=/usr/bin/tmux\nidle_seconds=120\nconsole_port=42722\n")
        self.state = Path(self.state_dir, "state.json")
        self.secret = base64.b32encode(b"12345678901234567890").decode()
        totpd.commit_state(self.state_dir, dict(secret=self.secret, last_counter=0, failures=0,
                                               locked_until=0, enrolled=True))
        self.wall = 59
        self.tick = 10
        self.uid, self.pid = 501, 30001
        self.events = []
        self.condition = threading.Condition()
        self.stop = threading.Event()
        self.release = threading.Event()
        self.release.set()
        self.calls = []
        self.clients = []
        self.worker = None
        self.start_options = {}

    def runner(self, argv, timeout):
        self.calls.append(tuple(argv))
        if argv[0] == "/usr/sbin/netstat":
            assert self.release.wait(timeout)
        result = make_stub_runner()(argv, timeout)
        if argv[0] == "/bin/ps" and "-axo" in argv:
            result = result.replace(f" {os.getuid()} ", " 501 ")
        return result

    def event(self, name):
        with self.condition:
            self.events.append(name)
            self.condition.notify_all()

    def wait(self, name, count=1):
        with self.condition:
            assert self.condition.wait_for(lambda: self.events.count(name) >= count, timeout=4), self.events

    def start(self):
        assert Path(self.state_dir).is_relative_to(self.root)
        assert Path(self.run_dir).is_relative_to(self.root)
        self.stop.clear()
        self.events.clear()
        self.result = []
        options = dict(peer_cred_fn=lambda s: (0, self.pid) if s.getsockname().endswith("admin.sock") else (self.uid, self.pid))
        options.update(self.start_options)
        def serve():
            self.result.append(totpd.run(
                str(self.config), self.state_dir, self.run_dir, str(self.root / "log"),
                runner=self.runner, expected_conf_owner=os.getuid(), expected_dir_owner=os.getuid(),
                clock=lambda: self.wall, monotonic=lambda: self.tick,
                stop_event=self.stop, event_hook=self.event, **options,
            ))
        self.worker = threading.Thread(target=serve, daemon=True)
        self.worker.start()
        self.wait("ready")

    def connect(self, name="totp"):
        path = Path(self.run_dir, name + ".sock")
        assert self.root in path.parents and len(bytes(path)) < 104
        client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.clients.append(client)
        client.settimeout(4)
        client.connect(str(path))
        return client

    def finish(self):
        self.release.set()
        self.stop.set()
        for client in self.clients:
            client.close()
        if self.worker:
            self.worker.join(4)
            assert not self.worker.is_alive()


@pytest.fixture
def verifier():
    root = make_short_tmpdir()
    instance = VerifierFixture(root)
    try:
        yield instance
    finally:
        instance.finish()
        shutil.rmtree(root)


def receive(client):
    try:
        return client.recv(64)
    except ConnectionResetError:
        return b""


@pytest.mark.parametrize("fault", ["pre-rename-write", "pre-rename-fsync", "pre-rename-replace"])
@pytest.mark.parametrize("code,expected", [(b"287082", b"OK\n"), (b"000000", b"NO\n")])
def test_N10_M2_pre_rename_retry(verifier, monkeypatch, fault, code, expected):
    verifier.start()
    original = verifier.state.read_bytes()
    monkeypatch.setattr(totpd.run, "injected_commit_fault", fault, raising=False)
    client = verifier.connect()
    client.sendall(b"VERIFY " + code + b"\n")
    assert receive(client) == b"UNAVAILABLE\n"
    assert verifier.state.read_bytes() == original
    assert not verifier.state.with_suffix(".json.tmp").exists()
    monkeypatch.delattr(totpd.run, "injected_commit_fault")
    client = verifier.connect()
    client.sendall(b"VERIFY " + code + b"\n")
    assert receive(client) == expected


@pytest.mark.parametrize("code,expected", [(b"287082", "last_counter"), (b"000000", "failures")])
def test_N10_M2_directory_fsync_stops_queue(verifier, monkeypatch, code, expected):
    verifier.start()
    first, second = verifier.connect(), verifier.connect()
    verifier.wait("admitted", 2)
    reached, resume = threading.Event(), threading.Event()
    commit = totpd.commit_state
    def failing_commit(state_dir, state, fault=None):
        reached.set()
        assert resume.wait(4)
        commit(state_dir, state, fault="post-rename-dir-fsync")
    monkeypatch.setattr(totpd, "commit_state", failing_commit)
    first.sendall(b"VERIFY " + code + b"\n")
    assert reached.wait(4)
    second.sendall(b"VERIFY " + code + b"\n")
    resume.set()
    assert receive(first) == b"UNAVAILABLE\n"
    assert receive(second) == b""
    verifier.worker.join(4)
    assert verifier.result == [1]
    assert not list(Path(verifier.run_dir).glob("*.sock"))
    assert json.loads(verifier.state.read_bytes())[expected] == 1
    monkeypatch.setattr(totpd, "commit_state", commit)
    verifier.start()
    client = verifier.connect()
    client.sendall(b"VERIFY " + code + b"\n")
    assert receive(client) == b"NO\n"


def test_N1_M2_same_code_on_two_admitted_connections(verifier):
    verifier.start()
    clients = [verifier.connect(), verifier.connect()]
    verifier.wait("admitted", 2)
    for client in clients:
        client.sendall(b"VERIFY 287082\n")
    assert sorted(map(receive, clients)) == [b"NO\n", b"OK\n"]


@pytest.mark.parametrize("damage", ["unknown", "missing", "unreadable"])
def test_N10_M3_invalid_config_on_both_sockets(verifier, damage):
    saved = verifier.config.read_bytes()
    if damage == "unknown":
        verifier.config.write_bytes(saved + b"unknown=1\n")
    elif damage == "missing":
        verifier.config.unlink()
    else:
        verifier.config.chmod(0)
    verifier.start()
    assert receive(verifier.connect()) == b""
    admin = verifier.connect("admin")
    admin.sendall(b"STATUS\n")
    assert receive(admin) == b"UNAVAILABLE\n"
    verifier.finish()
    if not verifier.config.exists():
        verifier.config.touch(mode=0o600)
    verifier.config.chmod(0o600)
    verifier.config.write_bytes(saved)
    verifier.start()
    client = verifier.connect()
    client.sendall(b"VERIFY 287082\n")
    assert receive(client) == b"OK\n"
    verifier.tick += 6
    verifier.wait("closed done")
    verifier.wall = 89
    client = verifier.connect()
    client.sendall(b"VERIFY 359152\n")
    assert receive(client) == b"OK\n"


def test_N3_M3_finished_rejections_release_slots(verifier):
    verifier.pid = 40000
    verifier.start()
    saved = verifier.state.read_bytes()
    for number in range(1, 51):
        client = verifier.connect()
        verifier.wait("closed rejected", number)
        assert receive(client) == b""
    assert verifier.events.count("check-finished") == 50
    assert sum(cmd[0].endswith("netstat") for cmd in verifier.calls) == 1
    assert verifier.state.read_bytes() == saved
    verifier.pid = 30001
    client = verifier.connect()
    client.sendall(b"VERIFY 287082\n")
    assert receive(client) == b"OK\n"


def test_N3_M3_pending_and_admitted_limits(verifier):
    verifier.release.clear()
    verifier.start()
    clients = [verifier.connect() for _ in range(4)]
    verifier.wait("check-started", 4)
    assert receive(verifier.connect()) == b""
    verifier.release.set()
    verifier.wait("admitted", 4)
    assert sum(cmd[0].endswith("netstat") for cmd in verifier.calls) == 1
    assert sum(cmd[0].endswith("launchctl") for cmd in verifier.calls) == 1
    assert receive(verifier.connect()) == b""
    clients[0].close()
    verifier.wait("closed eof")
    client = verifier.connect()
    client.sendall(b"VERIFY 287082\n")
    assert receive(client) == b"OK\n"
    verifier.tick += 6
    verifier.wait("closed deadline", 3)
    verifier.wall = 89
    client = verifier.connect()
    client.sendall(b"VERIFY 359152\n")
    assert receive(client) == b"OK\n"


def test_N3_E2_wrong_uid_peers_do_not_consume_pending_admission_slots(verifier):
    verifier.release.clear()
    credential_lock = threading.Lock()
    accepted = {}
    first_credentials = 0
    blocked_wrong = 0
    wrong_release = threading.Event()

    def credentials(sock):
        nonlocal first_credentials, blocked_wrong
        with credential_lock:
            if sock not in accepted:
                first_credentials += 1
                is_wrong = first_credentials <= 4
                accepted[sock] = is_wrong
                return (verifier.uid + 1 if is_wrong else verifier.uid), verifier.pid
            is_wrong = accepted[sock]
            if is_wrong:
                blocked_wrong += 1
                verifier.event("wrong-admit-started")
        if is_wrong:
            wrong_release.wait(timeout=4)
            return verifier.uid + 1, verifier.pid
        return verifier.uid, verifier.pid

    verifier.start_options["peer_cred_fn"] = credentials
    verifier.start()
    wrong_peers = [verifier.connect() for _ in range(4)]
    with verifier.condition:
        ready = verifier.condition.wait_for(
            lambda: verifier.events.count("closed wrong-uid") == 4 or blocked_wrong == 4,
            timeout=4,
        )
    assert ready, verifier.events
    good_peer = verifier.connect()
    verifier.wait("accepted", 5)
    verifier.release.set()
    wrong_release.set()
    good_peer.sendall(b"VERIFY 287082\n")
    assert receive(good_peer) == b"OK\n"
    for peer in wrong_peers:
        assert receive(peer) == b""
    verifier.finish()


def test_N3_M3_production_identity_parameters(monkeypatch):
    recorded = {}
    def capture(**kwargs):
        recorded.update(kwargs)
        return 0
    monkeypatch.setattr(totpd, "run", capture)
    with pytest.raises(SystemExit, match="0"):
        totpd.main()
    assert recorded["expected_job_label"] == "com.k3d-manager.web-console-sshd"
    assert recorded["expected_gate_path"] == "/Library/PrivilegedHelperTools/k3dm-web-console/forced-command"
    assert recorded["expected_interpreter"] == totpd.PYAPP
    assert recorded["expected_conf_owner"] == recorded["expected_dir_owner"] == 0


def test_N3_M3_peercred_pid():
    if sys.platform != "darwin":
        pytest.skip("LOCAL_PEERPID is Darwin-only")
    left, right = socket.socketpair()
    with left, right:
        assert totpd.default_peer_cred(left) == (os.getuid(), os.getpid())


class GateProcess:
    def __init__(self, root, options, env=None):
        assert root.is_dir() and root.name.startswith("wct.")
        self.root = root
        master, slave = pty.openpty()
        self.master = master
        self.tty_path = os.ttyname(slave)
        self.buffer = bytearray()
        script = """
import importlib.util, json, os, sys, time
spec = importlib.util.spec_from_file_location("gate", sys.argv[1])
gate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gate)
kwargs = json.loads(sys.argv[2])
def event(name):
    with open(name, "w") as stream:
        stream.write(str(time.monotonic()))
kwargs["event_hook"] = event
if kwargs.pop("never_reaped", False):
    kwargs["reap_fn"] = lambda pid: False
if kwargs.pop("relay_fault", False):
    select_original = gate.select.select
    def select_once(*args):
        if os.path.exists("fail-relay"):
            raise OSError("fixture relay failure")
        return select_original(*args)
    gate.select.select = select_once
if kwargs.pop("short_retry", False):
    original_sleep = time.sleep
    gate.time.sleep = lambda t: original_sleep(.01 if t == 2 else t)
if kwargs.pop("record_outer_flags", False):
    original_fcntl = gate.fcntl.fcntl
    def record_fcntl(fd, command, *args):
        if fd == 0 and command == gate.fcntl.F_SETFL:
            with open("outer-flags", "w") as stream:
                stream.write(str(args[0]))
        return original_fcntl(fd, command, *args)
    gate.fcntl.fcntl = record_fcntl
if kwargs.pop("record_terminal_flush", False):
    original_tcflush = gate.termios.tcflush
    def record_tcflush(fd, selector):
        with open("terminal-flushes", "a") as stream:
            stream.write(str(selector) + "\\n")
        return original_tcflush(fd, selector)
    gate.termios.tcflush = record_tcflush
if kwargs.pop("force_isig_on_tcgetattr", False):
    original_tcgetattr = gate.termios.tcgetattr
    def force_isig(fd):
        attrs = original_tcgetattr(fd)
        attrs[3] |= gate.termios.ISIG
        return attrs
    gate.termios.tcgetattr = force_isig
if kwargs.pop("record_terminal_restore", False):
    original_tcsetattr = gate.termios.tcsetattr
    def record_tcsetattr(fd, when, attrs):
        with open("terminal-restores", "a") as stream:
            stream.write(str(when) + "\\n")
        return original_tcsetattr(fd, when, attrs)
    gate.termios.tcsetattr = record_tcsetattr
if kwargs.pop("refuse_connect", False):
    def refuse_connect(*_args):
        raise ConnectionRefusedError("fixture verifier unavailable")
    kwargs["connect_fn"] = refuse_connect
if kwargs.pop("hang_connect", False):
    kwargs["connect_fn"] = lambda *_: time.sleep(60)
raise SystemExit(gate.run(**kwargs))
"""
        try:
            self.proc = subprocess.Popen(
                [sys.executable, "-IS", "-c", script, GATE_PATH, json.dumps(options)],
                cwd=root, env=dict({"HOME": str(root), "TERM": "xterm", "PATH": "/bin:/usr/bin"}, **(env or {})),
                stdin=slave, stdout=slave, stderr=slave, start_new_session=True,
            )
        finally:
            os.close(slave)

    def until(self, marker, timeout=5):
        deadline = time.monotonic() + timeout
        while marker not in self.buffer:
            remaining = deadline - time.monotonic()
            assert remaining > 0 and select.select([self.master], [], [], remaining)[0], bytes(self.buffer[-256:])
            self.buffer.extend(os.read(self.master, 16384))
        index = self.buffer.index(marker) + len(marker)
        del self.buffer[:index]

    def send(self, data):
        os.write(self.master, data)

    def close(self):
        _signal_process_group(self.proc, signal.SIGTERM)
        try:
            os.close(self.master)
        except OSError:
            pass
        try:
            self.proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            _signal_process_group(self.proc, signal.SIGKILL)
            self.proc.wait(timeout=2)


@pytest.fixture
def start_gate(verifier):
    gates = []
    def start(**overrides):
        options = dict(conf_path=str(verifier.config), sock_path=str(Path(verifier.run_dir, "totp.sock")),
                       expected_conf_owner=os.getuid(), expected_server_uid=os.getuid(), prompt_timeout=3)
        options.update(overrides)
        instance = GateProcess(verifier.root, options, options.pop("gate_env", None))
        gates.append(instance)
        return instance
    yield start
    for instance in gates:
        instance.close()


@pytest.mark.parametrize("fault", ["missing", "mode", "unknown", "owner"])
def test_N8_M4_gate_bad_config(verifier, start_gate, fault):
    if fault == "missing":
        verifier.config.unlink()
    elif fault == "mode":
        verifier.config.chmod(0o666)
    elif fault == "unknown":
        with verifier.config.open("a") as stream:
            stream.write("extra=1\n")
    instance = start_gate(expected_conf_owner=0 if fault == "owner" else os.getuid())
    instance.until(b"console login unavailable")
    assert instance.proc.wait(timeout=1) == 1


@pytest.mark.parametrize("failure", ["missing", "eof", "garbage", "incomplete", "unavailable", "wrong-owner",
                                     "connect-deadline", "reply-deadline"])
def test_N8_N2_M4_verifier_failures(verifier, start_gate, failure):
    path = Path(verifier.run_dir, "totp.sock")
    assert verifier.root in path.parents
    server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    with server:
        if failure != "missing":
            server.bind(str(path))
            server.listen()
            server.settimeout(4)
        instance = start_gate(hang_connect=failure == "connect-deadline",
                              expected_server_uid=0 if failure == "wrong-owner" else os.getuid())
        instance.until(b"Code: ")
        started = time.monotonic()
        instance.send(b"287082\n")
        if failure not in ("missing", "connect-deadline"):
            peer, _ = server.accept()
            with peer:
                if failure != "wrong-owner":
                    assert peer.recv(32) == b"VERIFY 287082\n"
                else:
                    assert peer.recv(32) == b""
                if failure == "reply-deadline":
                    instance.until(b"console login unavailable", timeout=6)
                else:
                    response = {"garbage": b"WHAT\n", "incomplete": b"OK", "unavailable": b"UNAVAILABLE\n"}
                    if failure in response:
                        peer.sendall(response[failure])
        if failure != "reply-deadline":
            instance.until(b"console login unavailable", timeout=4)
        assert instance.proc.wait(timeout=1) == 1
        elapsed = time.monotonic() - started
        if failure == "connect-deadline":
            assert 3 <= elapsed < 4
        if failure == "reply-deadline":
            assert 5 <= elapsed < 6


@pytest.mark.parametrize("end", ["idle", "SIGHUP", "SIGTERM"])
def test_N2_N8_M4_prompt_ends(verifier, start_gate, end):
    instance = start_gate(prompt_timeout=0.15 if end == "idle" else 3)
    instance.until(b"Code: ")
    if end != "idle":
        instance.proc.send_signal(getattr(signal, end))
    assert instance.proc.wait(timeout=2) == 1


@pytest.fixture
def scratch_tmux(verifier):
    binary = shutil.which("tmux")
    if not binary and sys.platform != "darwin":
        pytest.skip("tmux not found")
    assert binary, "tmux missing on Darwin"
    path = verifier.root / "tmux.sock"
    argv = [binary, "-S", str(path), "-f", "/dev/null"]
    assert path.parent == verifier.root and not path.exists()
    env = {"HOME": str(verifier.root), "TERM": "xterm", "PATH": "/usr/bin:/bin"}
    def control(*args, check=True):
        return subprocess.run(argv + list(args), cwd=verifier.root, env=env,
                              capture_output=True, check=check, timeout=5, text=True)
    try:
        yield argv, control
    finally:
        control("kill-server", check=False)


def wait_clients(control, count):
    deadline = time.monotonic() + 4
    while time.monotonic() < deadline:
        output = control("list-clients", "-F", "#{client_tty}", check=False)
        rows = output.stdout.splitlines()
        if len(rows) == count:
            return rows
        time.sleep(.025)
    pytest.fail(f"expected {count} clients, saw {rows}")


@pytest.fixture
def home_client(verifier, scratch_tmux):
    argv, control = scratch_tmux
    control("new-session", "-d", "-s", "work-console", "/bin/sleep 120")
    pane_pid = int(control("display-message", "-p", "-t", "work-console:", "#{pane_pid}").stdout)
    master, slave = pty.openpty()
    env = {"HOME": str(verifier.root), "TERM": "xterm", "PATH": "/bin:/usr/bin",
           "SSH_AUTH_SOCK": str(verifier.root / "auth"), "DISPLAY": ":99"}
    home = subprocess.Popen(argv + ["attach-session", "-t", "=work-console"], cwd=verifier.root, env=env,
                            stdin=slave, stdout=slave, stderr=slave, start_new_session=True)
    os.close(slave)
    try:
        home_tty, = wait_clients(control, 1)
        yield home_tty, pane_pid
    finally:
        _stop_pty_process(home, master)


@pytest.mark.parametrize("end", ["SIGKILL", "SIGTERM", "SIGHUP", "disconnect", "detach"])
def test_N1_N2_M5_M6_real_gate_client_lifecycle(verifier, start_gate, scratch_tmux, end, home_client):
    argv, control = scratch_tmux
    home_tty, pane_pid = home_client
    verifier.start()
    instance = start_gate(tmux_prefix=argv)
    instance.until(b"Code: ")
    for byte in (3, 26, 28, 4):
        instance.send(b"11" + bytes([byte]))
        instance.until(b"Code: ")
    assert wait_clients(control, 1) == [home_tty]
    instance.send(b"000000\n")
    instance.until(b"Invalid code")
    instance.until(b"Code: ")
    instance.send(b"287082\n")
    tty, = set(wait_clients(control, 2)) - {home_tty}
    assert control("display-message", "-p", "-c", tty, "#{session_name}").stdout.strip() == "work"
    if end == "disconnect":
        os.close(instance.master)
        instance.master = os.open(os.devnull, os.O_RDONLY)
    elif end == "detach":
        control("detach-client", "-t", tty)
    else:
        instance.proc.send_signal(getattr(signal, end))
    assert instance.proc.wait(timeout=4) == {"SIGKILL": -signal.SIGKILL, "detach": 0}.get(end, 1)
    assert wait_clients(control, 1) == [home_tty]
    os.kill(pane_pid, 0)
    for name in ("work", "work-console"):
        assert control("has-session", "-t", "=" + name).returncode == 0


def test_N1_M1_second_gate_and_idle_reauthentication(verifier, start_gate, scratch_tmux):
    argv, control = scratch_tmux
    verifier.start()
    first = start_gate(tmux_prefix=argv, idle_seconds=3)
    first.until(b"Code: ")
    first.send(b"287082\n")
    first_tty, = wait_clients(control, 1)
    second = start_gate(tmux_prefix=argv, idle_seconds=20)
    second.until(b"Code: ")
    assert wait_clients(control, 1) == [first_tty]
    verifier.wall = 89
    second.send(b"359152\n")
    assert first_tty in wait_clients(control, 2)
    first.until(b"Code: ", timeout=5)
    assert first_tty not in wait_clients(control, 1)
    verifier.wall = 119
    first.send(b"969429\n")
    assert len(wait_clients(control, 2)) == 2


@pytest.mark.parametrize("verb", ["enroll", "rotate"])
@pytest.mark.parametrize("fault", [None, "wrong-code", "pre-rename-fsync", "post-rename-dir-fsync"])
def test_N5_N9_N10_M8_admin_commit_at_pty(verifier, monkeypatch, verb, fault):
    admin_commit_at_pty(verifier, monkeypatch, verb, fault)


@pytest.mark.parametrize("verb", ["enroll", "rotate"])
def test_enrol_failure_warns(verifier, monkeypatch, verb):
    admin_commit_at_pty(verifier, monkeypatch, verb, "wrong-code")


@pytest.mark.parametrize("verb", ["enroll", "rotate"])
def test_N5_E3_secret_never_creates_temp_files(verifier, monkeypatch, verb):
    scratch_tmp = verifier.root / "tmp"
    scratch_tmp.mkdir()
    before = {path for path in Path("/tmp").glob("wct-leak-*")}
    try:
        admin_commit_at_pty(verifier, monkeypatch, verb, None, tmpdir=str(scratch_tmp))
        assert list(scratch_tmp.iterdir()) == []
        assert {path for path in Path("/tmp").glob("wct-leak-*")} == before
    finally:
        for path in set(Path("/tmp").glob("wct-leak-*")) - before:
            path.unlink(missing_ok=True)


def _matrix_from_hex_rows(rows):
    return [[bool((int(value, 16) >> (40 - col)) & 1) for col in range(41)] for value in rows]


def test_qr_reference_matrices_and_limits():
    # python-qrcode 8.0 (version 6, ERROR_CORRECT_L, byte mode, mask_pattern 0), each decoded back with zxing-cpp 2.3.0;
    # m4-air, 2026-11-24. Replaces segno 1.6.6 vectors (segno inserts a non-canonical 0x00 before the EC/11 padding).
    first = """1fca4426e7f 1046abbbe41 1758133005d 1746aaa825d 17468008e5d 10490c0ce41 1fd5555557f 001f999df00 1dfa22bfdc4 08163414149 16c89888065 0a2c2233c51 09ec22019e0 120eaaaa149 1278c4000eb 182eaaefca2 0ef1009d8cf 0c33fbd98ea 0e595445cef 14beedcfc12 03d15557ae9 133ffff58c9 014ff331cb7 0b0ddd9fc71 1c4e22ebbce 1f9b7351160 094188888cf 13970011d32 04640023bc8 0ea2a22914f 154484048c7 0f86eaedf83 11fd000bbfe 0013cf89312 1fdc4554b57 1054ccccb10 175175559f3 174f7f75618 175377f4997 1051d99c9aa 1fd6f328903""".split()
    second = """1fcbee66e7f 10426ea7a41 1751115045d 174c45dde5d 174bef8885d 1048babbf41 1fd5555557f 001d8888f00 1dff9999dc4 1e31111094b 07771d54467 08b3aeaf8d1 1d42ae2c1d1 0b8a1547301 1ec454451cf 0b869b88eb2 0c49b9b98c3 060999990e9 0f611d5dc6f 06aaeeafc51 046f7bf3eda 1e971133f09 176b4455dbb 13a59ba8f51 17d3b99b9ca 0b151999961 0c659190ccd 022a2aa9d72 06723aa33e8 071e113772b 14d444558d3 0d2a88aac82 11f599b99f1 00199119b13 1fd15154757 105aeee8b12 17577eb01f0 174f5173612 175b444599c 1051b8ba9e2 1fdfb99a9cb""".split()
    uris = [b"otpauth://totp/k3dm-console-m5-air?secret=JBSWY3DPEHPK3PXPJBSWY3DPEHPK3PXP&issuer=k3dm-console",
            b"otpauth://totp/k3dm-console-hhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhh?secret=JBSWY3DPEHPK3PXPJBSWY3DPEHPK3PXP&issuer=k3dm-console"]
    assert len(uris[0]) == 94 and len(uris[1]) == 128
    assert totpctl._qr_matrix(uris[0]) == _matrix_from_hex_rows(first)
    assert totpctl._qr_matrix(uris[1]) == _matrix_from_hex_rows(second)
    assert totpctl._qr_matrix(b"x" * 135) is None
    matrix = totpctl._qr_matrix(b"x" * 134)
    assert len(matrix) == 41 and all(len(row) == 41 for row in matrix)


def test_qr_render_has_exact_quiet_zone_and_sgr_cells():
    matrix = [[(r + c) % 3 == 0 for c in range(41)] for r in range(41)]
    rendered = totpctl._qr_render(matrix)
    lines = rendered.splitlines(keepends=True)
    assert len(lines) == 25
    padded = [[False] * 49 for _ in range(4)]
    padded.extend([[False] * 4 + row + [False] * 4 for row in matrix])
    padded.extend([[False] * 49 for _ in range(4)])
    for index, line in enumerate(lines):
        assert line.endswith("\x1b[0m\n")
        cells = re.findall(r"\x1b\[(30|97);(40|107)m\u2580", line[:-5])
        assert len(cells) == 49
        for col, (fg, bg) in enumerate(cells):
            assert (fg == "30") == padded[index * 2][col]
            assert (bg == "40") == (padded[index * 2 + 1][col] if index * 2 + 1 < 49 else False)


def test_totpctl_is_stdlib_only_and_python39_safe(verifier):
    source = Path(TOTPCTL_PATH).read_text()
    assert not re.search(r"\b(subprocess|popen|system|execv?e?|spawn\w*)\s*\(", source)
    tree = __import__("ast").parse(source)
    imported = {alias.name.split(".", 1)[0] for node in __import__("ast").walk(tree)
                if isinstance(node, (__import__("ast").Import, __import__("ast").ImportFrom))
                for alias in node.names}
    assert imported <= set(sys.stdlib_module_names)
    hub_python = "/Library/Developer/CommandLineTools/usr/bin/python3"
    if not Path(hub_python).exists():
        pytest.skip("hub CommandLineTools Python 3 not installed on this host")
    assert Path(verifier.root).is_dir()
    path, server, worker, _commands = _admin_stub(verifier.root, [("STATUS", "ENROLLED")])
    program = ("import importlib.util, sys; "
               "spec=importlib.util.spec_from_file_location('ctl', sys.argv[1]); "
               "ctl=importlib.util.module_from_spec(spec); spec.loader.exec_module(ctl); "
               "raise SystemExit(ctl.run(['status', '--wire'], admin_sock=sys.argv[2], check_root=False))")
    env = os.environ.copy()
    env["HOME"] = str(verifier.root)
    try:
        result = subprocess.run([hub_python, "-IS", "-c", program, TOTPCTL_PATH, str(path)],
                                cwd=verifier.root, env=env, capture_output=True, text=True, timeout=10)
        worker.join(timeout=2)
        assert not worker.is_alive()
    finally:
        server.close()
    assert result.returncode == 0, result.stderr
    assert result.stdout == "ENROLLED\n"


class _ReadRecorder(io.StringIO):
    def __init__(self, value, output):
        super().__init__(value)
        self.output = output
        self.read_lengths = []
    def readline(self, size=-1):
        self.read_lengths.append(len(self.output.getvalue()))
        return super().readline(size)
    def isatty(self):
        return False


@pytest.mark.parametrize("verb", ["enroll", "rotate", "recovery-regen"])
def test_pause_keeps_codes_until_read_and_clear_after(verifier, monkeypatch, verb):
    assert Path(verifier.run_dir).is_relative_to(verifier.root)
    assert Path(verifier.state_dir).is_relative_to(verifier.root)
    if verb == "recovery-regen":
        incoming = "yes\n287082\n\n"
    else:
        secret = base64.b32encode(b"only-in-test-secret!").decode()
        incoming = "287082\n\n"
    assert Path(verifier.root).is_dir()
    commands = []
    alphabet = "234567ABCD"
    def fake_admin(_path, command):
        commands.append(command)
        if command in ("ENROLL_BEGIN", "ROTATE_BEGIN"):
            return f"SECRET {secret}"
        if command == "RECOVERY_BEGIN":
            return "RECOVERY_PENDING"
        if command.startswith("RECOVERY_GET "):
            index = int(command.rsplit(" ", 1)[1])
            return f"CODE AAAA-BBBB-CCCC-AAA{alphabet[index]}"
        if command.endswith(" 287082"):
            return "OK"
        return "OK"
    monkeypatch.setattr(totpctl, "send_admin_cmd", fake_admin)
    path = str(verifier.root / "stub-admin.sock")
    try:
        output = io.StringIO()
        reader = _ReadRecorder(incoming, output)
        assert totpctl.run([verb], admin_sock=str(path), tty_in=reader, tty_out=output, check_root=False) == 0
        assert len(reader.read_lengths) == (3 if verb == "recovery-regen" else 2)
        before_pause_read = reader.read_lengths[-1]
        assert "\x1b[3J\x1b[H\x1b[2J" not in output.getvalue()[:before_pause_read]
        assert "Save the recovery codes now" in output.getvalue()[:before_pause_read]
        assert "\x1b[3J\x1b[H\x1b[2J" in output.getvalue()[before_pause_read:]
        assert commands[-1].endswith("COMMIT 287082")
    finally:
        pass


def test_pause_unavailable_keeps_potentially_live_codes(verifier, monkeypatch):
    assert Path(verifier.root).is_dir()
    secret = base64.b32encode(b"only-in-test-secret!").decode()
    def fake_admin(_path, command):
        if command == "ENROLL_BEGIN":
            return f"SECRET {secret}"
        if command.startswith("RECOVERY_GET "):
            index = int(command.rsplit(" ", 1)[1])
            return f"CODE AAAA-BBBB-CCCC-AAA{'234567ABCD'[index]}"
        if command.startswith("ENROLL_COMMIT "):
            return "UNAVAILABLE"
        return "OK"
    monkeypatch.setattr(totpctl, "send_admin_cmd", fake_admin)
    output = io.StringIO()
    reader = _ReadRecorder("287082\n\n", output)
    assert totpctl.run(["enroll"], admin_sock=str(verifier.root / "stub.sock"), tty_in=reader,
                       tty_out=output, check_root=False) == 1
    before_clear = output.getvalue().index("\x1b[3J\x1b[H\x1b[2J")
    assert output.getvalue().index("commit not confirmed; run web-console-totp-status") < output.getvalue().index(
        "Save the recovery codes now") < before_clear
    assert len(reader.read_lengths) == 2


def admin_commit_at_pty(verifier, monkeypatch, verb, fault, tmpdir=None):
    raw = b"only-in-test-secret!"
    assert len(raw) == 20
    secret = base64.b32encode(raw)
    code = totpd.compute_hotp(raw, verifier.wall // 30).encode()
    wrong_code = str((int(code) + 1) % 1000000).zfill(6).encode()
    old_state = verifier.state.read_bytes()
    if verb == "enroll":
        verifier.state.unlink()
    random_calls = {10: 0, 16: 0}
    def generate(size):
        if size == 20:  # agent-audit: allow assert-removed generate() now also serves 10/16-byte recovery draws
            return raw
        assert size in (10, 16)
        random_calls[size] += 1
        return bytes([random_calls[size] % 256]) * size
    monkeypatch.setattr(totpd.os, "urandom", generate)
    monkeypatch.setattr(totpd.run, "injected_commit_fault", fault, raising=False)
    verifier.start()
    program = """
import fcntl, importlib.util, os, sys, termios
os.setsid()
fcntl.ioctl(0, termios.TIOCSCTTY, 0)
def audit(event, args):
    if event in ("subprocess.Popen", "os.exec", "os.posix_spawn"):
        with open("spawns", "a") as stream:
            stream.write(repr(args) + chr(10))
sys.addaudithook(audit)
spec = importlib.util.spec_from_file_location("ctl", sys.argv[1])
ctl = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ctl)
raise SystemExit(ctl.run([sys.argv[3]], admin_sock=sys.argv[2], check_root=False))
"""
    sock = Path(verifier.run_dir, "admin.sock")
    assert verifier.root in sock.parents
    master, slave = pty.openpty()
    argv = [sys.executable, "-IS", "-c", program, TOTPCTL_PATH, str(sock), verb]
    env = {"HOME": str(verifier.root)}
    if tmpdir is not None:
        env["TMPDIR"] = tmpdir
    proc = subprocess.Popen(argv, env=env, cwd=verifier.root, stdin=slave, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    os.close(slave)
    transcript = bytearray()
    try:
        while b"Code: " not in transcript:
            assert select.select([master], [], [], 3)[0]
            transcript.extend(os.read(master, 4096))
        assert b"Scan this with your phone's camera or authenticator app:" in transcript
        assert transcript.index(b"Scan this with your phone's camera or authenticator app:") < transcript.index(b"Secret:")
        assert b"otpauth://totp/" in transcript and secret in transcript
        assert not verifier.state.exists() if verb == "enroll" else verifier.state.read_bytes() == old_state
        assert not verifier.state.with_suffix(".json.tmp").exists()
        for file in verifier.root.rglob("*"):
            if file.is_file():
                assert secret not in file.read_bytes() and raw not in file.read_bytes()
        os.write(master, (wrong_code if fault == "wrong-code" else code) + b"\n")
        if fault != "wrong-code":
            prompt = b"Save the recovery codes now (not on your travel device), then press Enter to clear the screen: "
            while prompt not in transcript:
                assert select.select([master], [], [], 3)[0]
                transcript.extend(os.read(master, 4096))
            assert b"\x1b[3J\x1b[H\x1b[2J" not in transcript
            os.write(master, b"\n")
        deadline = time.monotonic() + 4
        while proc.poll() is None or select.select([master], [], [], 0)[0]:
            assert time.monotonic() < deadline
            if not select.select([master], [], [], 0.1)[0]:
                continue
            try:
                data = os.read(master, 4096)
            except OSError as exc:
                if exc.errno == errno.EIO:
                    break
                raise
            if not data:
                break
            transcript.extend(data)
        stdout, stderr = proc.communicate(timeout=3)
        assert stdout == stderr == b""
        assert proc.returncode == (1 if fault else 0)
        assert code not in transcript and wrong_code not in transcript
        if fault == "wrong-code":
            assert b"Save the recovery codes now" not in transcript
            assert b"Invalid code" in transcript
            assert b"The recovery codes shown are void." in transcript
            assert transcript.count(b"The recovery codes shown are void.") == 1
            assert b"\x1b[3J\x1b[H\x1b[2J" in transcript
            assert _recovery_admin(verifier, "RECOVERY_GET 0") == "UNAVAILABLE"
        elif fault:
            assert b"commit not confirmed; run web-console-totp-status" in transcript
        else:
            assert b"enrolled" in transcript and b"\x1b[3J\x1b[H\x1b[2J" in transcript
        if fault in ("pre-rename-fsync", "wrong-code"):
            assert not verifier.state.exists() if verb == "enroll" else verifier.state.read_bytes() == old_state
        else:
            state = json.loads(verifier.state.read_bytes())
            assert state["secret"] == secret.decode() and state["last_counter"] == 1
        log = verifier.root / "log"
        capture = repr((argv, env, verifier.calls)).encode() + stdout + stderr
        if log.exists():
            capture += log.read_bytes()
        if (verifier.root / "spawns").exists():
            capture += (verifier.root / "spawns").read_bytes()
        for value in (secret, raw, code, wrong_code):
            assert value not in capture
    finally:
        _stop_pty_process(proc, master)


@pytest.mark.parametrize("wire,human", [("NOT_ENROLLED", "not enrolled"), ("ENROLLED", "enrolled"),
                                        ("UNAVAILABLE", "state damaged")])
def test_N5_M8_status_words(verifier, wire, human, capsys):
    if wire == "NOT_ENROLLED":
        verifier.state.unlink()
    if wire == "UNAVAILABLE":
        verifier.state.write_bytes(b"{")
    verifier.start()
    sock = str(Path(verifier.run_dir, "admin.sock"))
    for args, expected in [(["status"], human), (["status", "--wire"], wire)]:
        assert totpctl.run(args, admin_sock=sock, check_root=False) == 0
        assert capsys.readouterr().out == expected + "\n"


@pytest.mark.parametrize("fault", [
    "wrong-uid", "listener-uid", "launchctl-pid", "two-listeners", "no-listener", "child",
    "identical-child", "server", "pane", "wrong-comm", "wrong-args", "pid-reused",
    "timeout", "budget", "different-label", "different-gate", "different-python",
    "wrong-great-grandparent",
])
def test_N3_E2_rejected_peer_never_answers(verifier, fault):
    baseline = verifier.runner
    alternate = {"label": "scratch.job", "entry": "/scratch/entry", "exe": "/scratch/Python"}
    verifier.start_options = dict(expected_job_label=alternate["label"], expected_gate_path=alternate["entry"],
                             expected_interpreter=alternate["exe"])
    lstart_calls = []
    rejected = [False]
    def runner(argv, timeout):
        value = baseline(argv, timeout)
        active = rejected[0]
        if argv[0] == "/bin/launchctl":
            if argv[-1] != "system/" + alternate["label"]:
                raise FileNotFoundError
            if active and fault == "launchctl-pid":
                return "pid = 54321"
        if argv[0] == "/usr/sbin/netstat" and active:
            if fault == "two-listeners":
                return value + "\n" + value
            if fault == "no-listener":
                return ""
        if argv[0] == "/bin/ps":
            if "uid=" in argv and fault == "listener-uid" and active:
                return "501"
            if "lstart=" in argv and active:
                if fault == "timeout":
                    raise subprocess.TimeoutExpired(argv, timeout)
                if fault == "budget":
                    verifier.tick += 3
                if fault == "pid-reused":
                    lstart_calls.append(1)
                    return str(len(lstart_calls))
            value = value.replace(totpd.PYAPP, alternate["exe"]).replace(totpd.DEFAULT_GATE_PATH, alternate["entry"])
            if "comm=" in argv:
                if active and fault in ("child", "pane", "server", "wrong-comm"):
                    return "python3.9"
                if active and fault == "identical-child":
                    return alternate["exe"]
            if "-axo" in argv and active:
                if fault == "wrong-great-grandparent":
                    return value.replace("20001 12345 0", "20001 40001 0") + "\n40001 1 0 /usr/sbin/init /usr/sbin/init"
                if fault == "wrong-args":
                    return value.replace(" -IS ", " -S ")
                if fault in ("child", "identical-child", "server", "pane"):
                    args = alternate["exe"] + " -IS " + alternate["entry"]
                    return value + f"\n40001 30001 501 {args}\n40002 1 501 tmux\n40003 40002 501 zsh"
        return value
    verifier.runner = runner
    verifier.start()
    client = verifier.connect()
    client.sendall(b"VERIFY 287082\n")
    assert receive(client) == b"OK\n"
    verifier.finish()
    for key, case in [("expected_job_label", "different-label"), ("expected_gate_path", "different-gate"),
                      ("expected_interpreter", "different-python")]:
        if case == fault:
            del verifier.start_options[key]
    rejected[0] = True
    if fault == "wrong-uid":
        verifier.uid += 1
    verifier.pid = {"child": 40001, "identical-child": 40001, "server": 40002, "pane": 40003}.get(fault, 30001)
    before = verifier.state.read_bytes()
    verifier.start()
    # Send nothing: closure must happen on identity completion, before a read.
    client = verifier.connect()
    assert receive(client) == b""
    assert verifier.state.read_bytes() == before


@pytest.mark.parametrize("damage", ["missing", "json", "fields", "unreadable"])
def test_N10_M2_state_unavailable(verifier, damage):
    if damage == "missing":
        verifier.state.unlink()
    elif damage == "unreadable":
        verifier.state.chmod(0)
    else:
        verifier.state.write_bytes(b"{" if damage == "json" else b'{"enrolled":true}')
    verifier.start()
    client = verifier.connect()
    client.sendall(b"VERIFY 287082\n")
    assert receive(client) == b"UNAVAILABLE\n"
    if damage != "missing":
        admin = verifier.connect("admin")
        admin.sendall(b"ENROLL_BEGIN\n")
        assert receive(admin) == b"UNAVAILABLE\n"
    if damage == "json":
        assert verifier.state.read_bytes() == b"{"


def test_N12_N4_M7_child_descriptors_and_tmux_commands(verifier, start_gate, scratch_tmux):
    argv, control = scratch_tmux
    recorder = verifier.root / "record.py"
    log = verifier.root / "child.jsonl"
    recorder.write_text("""
import json, os, socket, stat, struct, sys
root, log, *argv = sys.argv[1:]
assert os.getcwd() == root and os.path.dirname(log) == root
peers = []
for entry in os.listdir("/dev/fd"):
    try:
        fd = int(entry)
        if not stat.S_ISSOCK(os.fstat(fd).st_mode):
            continue
        with socket.socket(fileno=os.dup(fd)) as sock:
            peers.append(None)
            if sys.platform == "darwin":
                pid = sock.getsockopt(0, 2)
            else:
                pid, _, _ = struct.unpack("3i", sock.getsockopt(socket.SOL_SOCKET, socket.SO_PEERCRED, 12))
            peers[-1] = pid
    except OSError:
        continue
with open(log, "a") as stream:
    stream.write(json.dumps(dict(peers=peers, argv=argv, env=dict(os.environ))) + "\\n")
if argv:
    os.execv(argv[0], argv)
""")
    prefix = [sys.executable, "-IS", str(recorder), str(verifier.root), str(log)]
    # Darwin may discard LOCAL_PEERPID when the last server descriptor closes.
    # Hold an unread server-side duplicate so the recorder can identify the
    # original connection even after the verifier has replied.
    def fixture_credentials(sock):
        verifier.clients.append(sock.dup())
        return verifier.uid, verifier.pid
    verifier.start_options["peer_cred_fn"] = fixture_credentials
    verifier.start()
    instance = start_gate(tmux_prefix=prefix + argv)
    instance.until(b"Code: ")
    instance.send(b"287082\n")
    wait_clients(control, 1)
    records = [json.loads(line) for line in log.read_text().splitlines()]
    expected = [["has-session", "-t", "=work"], ["new-session", "-d", "-s", "work"],
                ["attach-session", "-E", "-t", "=work"]]
    assert [r["argv"] for r in records] == [argv + operation for operation in expected]
    assert all(record["peers"] == [] for record in records)
    for value in (verifier.secret, "12345678901234567890", "287082", "000000"):
        assert value not in log.read_text()
    # The same recorder must identify a deliberately inherited fixture connection.
    client = verifier.connect()
    verifier.wait("admitted", 2)
    subprocess.run(prefix, cwd=verifier.root, pass_fds=(client.fileno(),), check=True, timeout=3)
    assert os.getpid() in json.loads(log.read_text().splitlines()[-1])["peers"]


@pytest.mark.parametrize("defect", ["mode", "symlink", "owner", "acl"])
def test_N7_E2_run_directory_layout(verifier, monkeypatch, defect):
    if sys.platform != "darwin" and defect == "acl":
        pytest.skip("Darwin ACL layout test")
    assert Path(totpd.DEFAULT_RUN_DIR).parent == Path(totpd.DEFAULT_STATE_DIR).parent
    assert not Path(totpd.DEFAULT_RUN_DIR).is_relative_to(Path(totpd.DEFAULT_STATE_DIR))
    verifier.start()
    verifier.finish()
    events = []
    run_dir = Path(verifier.run_dir)
    assert verifier.root in run_dir.parents
    original_stat = os.stat
    if defect == "owner":
        def stat_run_dir(path, *args, **kwargs):
            result = original_stat(path, *args, **kwargs)
            if os.fspath(path) == str(run_dir):
                return type("FixtureStat", (), {"st_uid": os.getuid() + 1,
                                                   "st_mode": result.st_mode})()
            return result
        monkeypatch.setattr(os, "stat", stat_run_dir)
    if defect == "mode":
        run_dir.chmod(0o775)
    if defect == "symlink":
        actual = run_dir.with_name("actual")
        run_dir.rename(actual)
        run_dir.symlink_to(actual, target_is_directory=True)
    if defect == "acl":
        subprocess.run(["/bin/chmod", "+a", "everyone allow read", str(run_dir)], check=True)
    def runner(argv, timeout):
        if argv[0] == "/bin/ls" and "-lde" in argv:
            suffix = "+ 1 root wheel" if defect == "acl" else " 1 root wheel"
            return "drwxr-xr-x" + suffix
        return totpd.default_runner(argv, timeout)
    assert totpd.run(str(verifier.config), verifier.state_dir, verifier.run_dir, str(verifier.root / "log"),
                     runner=runner,
                     expected_conf_owner=os.getuid(), expected_dir_owner=os.getuid(),
                     event_hook=events.append, max_iterations=1) == 1
    assert "ready" not in events


def test_N3_M3_admin_refuses_unprivileged_peer(verifier):
    verifier.start_options["peer_cred_fn"] = lambda _: (os.getuid(), os.getpid())
    verifier.start()
    assert receive(verifier.connect("admin")) == b""
    verifier.finish()
    verifier.start_options.clear()
    verifier.start()
    client = verifier.connect("admin")
    client.sendall(b"STATUS\n")
    assert receive(client) == b"ENROLLED\n"


def test_escalating_lock_decay_and_expiry_reset(verifier):
    verifier.start()
    def verify(code="000000"):
        client = verifier.connect()
        client.sendall(f"VERIFY {code}\n".encode())
        return receive(client).strip().decode()
    level = 0
    for expected in (300, 1800, 14400, 86400, 86400):
        for _ in range(4 if expected != 300 else 5):
            assert verify() == "NO"
        level = min(4, level + 1)
        state = totpd.load_state(verifier.state_dir)
        assert state["lock_level"] == level
        assert state["locked_until"] - verifier.wall == expected
        verifier.tick += expected
        verifier.wall += expected
        assert verify() == "NO"
        state = totpd.load_state(verifier.state_dir)
        assert state["failures"] == 1 and state["locked_until"] > 0
        verifier.wall += 5


def test_decay_after_full_days(verifier):
    state = totpd.load_state(verifier.state_dir)
    state.update(failures=5, lock_level=2, locked_until=verifier.wall - 1)
    totpd.commit_state(verifier.state_dir, state)
    verifier.wall += 86400
    verifier.start()
    assert totpd.load_state(verifier.state_dir)["lock_level"] == 1
    verifier.finish()
    verifier.wall += 86400
    verifier.start()
    state = totpd.load_state(verifier.state_dir)
    assert state["lock_level"] == 0 and state["locked_until"] == 0
    assert set(json.loads(verifier.state.read_text())) == {"secret", "last_counter", "failures", "locked_until", "enrolled"}


def _verify_wrong(verifier):
    client = verifier.connect()
    client.sendall(b"VERIFY 000000\n")
    return receive(client).strip().decode()


def test_decay_counts_each_day_once(verifier):
    verifier.wall = 200000
    state = totpd.load_state(verifier.state_dir)
    state.update(failures=5, lock_level=4, locked_until=verifier.wall - 86400)
    totpd.commit_state(verifier.state_dir, state)
    verifier.start()
    levels = []
    for _ in range(3):
        assert _verify_wrong(verifier) == "NO"
        current = totpd.load_state(verifier.state_dir)
        levels.append(current["lock_level"])
    assert levels == [3, 3, 3]
    assert current["locked_until"] == state["locked_until"] + 86400


def test_decay_keeps_part_day_remainder(verifier):
    verifier.wall = 200000
    state = totpd.load_state(verifier.state_dir)
    state.update(failures=5, lock_level=4, locked_until=verifier.wall - 43200)
    totpd.commit_state(verifier.state_dir, state)
    verifier.start()
    verifier.wall += 86400
    assert _verify_wrong(verifier) == "NO"
    first = totpd.load_state(verifier.state_dir)
    assert first["lock_level"] == 3
    assert first["locked_until"] == state["locked_until"] + 86400
    verifier.wall += 43200
    assert _verify_wrong(verifier) == "NO"
    second = totpd.load_state(verifier.state_dir)
    assert second["lock_level"] == 2
    assert second["locked_until"] == state["locked_until"] + 2 * 86400
    verifier.finish()
    verifier.start()
    assert totpd.load_state(verifier.state_dir)["lock_level"] == 2


def test_decay_spans_several_days(verifier):
    verifier.wall = 200000
    state = totpd.load_state(verifier.state_dir)
    state.update(failures=5, lock_level=4, locked_until=verifier.wall - 1)
    totpd.commit_state(verifier.state_dir, state)
    verifier.wall += 3 * 86400
    verifier.start()
    current = totpd.load_state(verifier.state_dir)
    assert current["lock_level"] == 1
    assert current["locked_until"] == state["locked_until"] + 3 * 86400


def test_decay_two_restarts_same_day(verifier):
    verifier.wall = 200000
    state = totpd.load_state(verifier.state_dir)
    state.update(failures=5, lock_level=3, locked_until=verifier.wall - 86401)
    totpd.commit_state(verifier.state_dir, state)
    verifier.start()
    first = totpd.load_state(verifier.state_dir)
    assert first["lock_level"] == 2
    first_until = first["locked_until"]
    assert first_until == state["locked_until"] + 86400
    verifier.finish()
    verifier.wall += 100
    verifier.tick += 100
    verifier.start()
    second = totpd.load_state(verifier.state_dir)
    assert second["lock_level"] == 2
    assert second["locked_until"] == first_until


def test_decay_resets_failures_at_startup(verifier):
    verifier.wall = 200000
    state = totpd.load_state(verifier.state_dir)
    state.update(failures=3, lock_level=2, locked_until=verifier.wall - 86401)
    totpd.commit_state(verifier.state_dir, state)
    verifier.start()
    current = totpd.load_state(verifier.state_dir)
    assert (current["lock_level"], current["failures"]) == (1, 0)
    for index in range(5):
        assert _verify_wrong(verifier) == "NO"
    assert _verify_wrong(verifier) == "WAIT 1800"


def test_decay_resets_failures_on_request(verifier):
    verifier.wall = 200000
    state = totpd.load_state(verifier.state_dir)
    state.update(failures=3, lock_level=2, locked_until=verifier.wall + 100)
    totpd.commit_state(verifier.state_dir, state)
    verifier.start()
    verifier.wall += 100 + 86400
    verifier.tick += 100 + 86400
    assert _verify_wrong(verifier) == "NO"
    current = totpd.load_state(verifier.state_dir)
    assert current["failures"] == 1
    assert current["lock_level"] == 1


def test_no_phantom_lock_after_clock_correction(verifier):
    verifier.wall = 200000
    state = totpd.load_state(verifier.state_dir)
    state.update(failures=2, lock_level=1, locked_until=verifier.wall + 300)
    totpd.commit_state(verifier.state_dir, state)
    verifier.start()
    assert _verify_wrong(verifier) == "NO"
    verifier.finish()
    state = totpd.load_state(verifier.state_dir)
    state.update(failures=4, lock_level=1, locked_until=verifier.wall + 300)
    totpd.commit_state(verifier.state_dir, state)
    verifier.start()
    assert _verify_wrong(verifier) == "NO"
    verifier.finish()
    state = totpd.load_state(verifier.state_dir)
    state.update(failures=5, lock_level=1, locked_until=verifier.wall + 300)
    totpd.commit_state(verifier.state_dir, state)
    verifier.start()
    assert _verify_wrong(verifier).startswith("WAIT ")


def test_rotate_clears_lock_level(verifier):
    state = totpd.load_state(verifier.state_dir)
    state.update(failures=5, lock_level=3, locked_until=verifier.wall + 1)
    totpd.commit_state(verifier.state_dir, state)
    verifier.start()
    admin = verifier.connect("admin")
    admin.sendall(b"ROTATE_BEGIN\n")
    secret_reply = receive(admin).decode().strip()
    admin.close()
    assert secret_reply.startswith("SECRET ")
    secret = base64.b32decode(secret_reply.split()[1])
    code = totpd.compute_hotp(secret, int(verifier.wall // 30))
    admin = verifier.connect("admin")
    admin.sendall(f"ROTATE_COMMIT {code}\n".encode())
    assert receive(admin) == b"OK\n"
    current = json.loads(verifier.state.read_text())
    assert current["failures"] == current["locked_until"] == 0
    for index in range(5):
        assert _verify_wrong(verifier) == "NO"
    assert _verify_wrong(verifier) == "WAIT 300"
    assert set(current) == {"secret", "last_counter", "failures", "locked_until", "enrolled"}


def test_level4_reply(verifier):
    state = totpd.load_state(verifier.state_dir)
    state.update(failures=5, lock_level=4, locked_until=verifier.wall + 86400)
    totpd.commit_state(verifier.state_dir, state)
    verifier.start()
    client = verifier.connect()
    client.sendall(b"VERIFY 000000\n")
    assert receive(client) == b"WAIT 86400\n"
    gate_source = (Path(__file__).parents[2] / "libexec" / "k3dm-console-gate.py").read_text()
    assert 'Too many attempts; try again later' in gate_source


def test_restart_keeps_level(verifier):
    verifier.start()
    for _ in range(5):
        client = verifier.connect()
        client.sendall(b"VERIFY 000000\n")
        assert receive(client) == b"NO\n"
    verifier.finish()
    state = totpd.load_state(verifier.state_dir)
    state["locked_until"] = verifier.wall - 1
    totpd.commit_state(verifier.state_dir, state)
    verifier.start()
    for _ in range(5):
        client = verifier.connect()
        client.sendall(b"VERIFY 000000\n")
        assert receive(client) == b"NO\n"
    state = totpd.load_state(verifier.state_dir)
    assert state["lock_level"] == 2 and state["locked_until"] - verifier.wall == 1800


def test_monotonic_deadline_once_and_success_resets(verifier):
    verifier.start()
    def request(code):
        client = verifier.connect()
        client.sendall(f"VERIFY {code}\n".encode())
        return receive(client).strip()
    for _ in range(5):
        assert request("000000") == b"NO"
    verifier.wall += 301
    assert request("000000") == b"WAIT 300"
    state = totpd.load_state(verifier.state_dir)
    assert state["locked_until"] > 0
    verifier.tick += 300
    code = totpd.compute_hotp(base64.b32decode(verifier.secret), verifier.wall // 30)
    assert request(code) == b"OK"
    state = totpd.load_state(verifier.state_dir)
    assert (state["failures"], state["locked_until"], state["lock_level"]) == (0, 0, 0)


def test_unlock_migration_and_level0_five_keys(verifier):
    legacy = {"secret": verifier.secret, "last_counter": 0, "failures": 5,
              "locked_until": verifier.wall + 300, "enrolled": True}
    totpd.commit_state(verifier.state_dir, legacy)
    assert totpd.load_state(verifier.state_dir)["lock_level"] == 1
    assert totpd.load_state(verifier.state_dir)["locked_until"] == verifier.wall + 300
    verifier.start()
    client = verifier.connect()
    client.sendall(b"VERIFY 000000\n")
    assert receive(client) == b"WAIT 300\n"
    verifier.tick += 300
    verifier.wall += 300
    for _ in range(5):
        client = verifier.connect()
        client.sendall(b"VERIFY 000000\n")
        assert receive(client) == b"NO\n"
    assert totpd.load_state(verifier.state_dir)["lock_level"] == 2
    client = verifier.connect()
    client.sendall(b"VERIFY 000000\n")
    assert receive(client) == b"WAIT 1800\n"
    client = verifier.connect("admin")
    client.sendall(b"UNLOCK\n")
    assert receive(client) == b"UNLOCKED\n"
    assert set(json.loads(verifier.state.read_text())) == {"secret", "last_counter", "failures", "locked_until", "enrolled"}
    assert totpd.load_state(verifier.state_dir)["lock_level"] == 0
    level_zero = dict(legacy, lock_level=0)
    totpd.commit_state(verifier.state_dir, level_zero)
    assert totpd.load_state(verifier.state_dir)["lock_level"] == 0
    assert totpd.load_state(verifier.state_dir)["locked_until"] == legacy["locked_until"]
    assert totpd.load_state(verifier.state_dir) is not False
    for level in (True, -1, 5, "1"):
        totpd.commit_state(verifier.state_dir, dict(legacy, lock_level=level))
        assert totpd.load_state(verifier.state_dir) is False
    totpd.commit_state(verifier.state_dir, dict(legacy, extra="refused"))
    assert totpd.load_state(verifier.state_dir) is False


def test_totpctl_unlock_cli(monkeypatch, capsys):
    monkeypatch.setattr(totpctl, "send_admin_cmd", lambda _sock, command: "UNLOCKED" if command == "UNLOCK" else "UNAVAILABLE")
    assert totpctl.run(["unlock"], check_root=False) == 0
    assert capsys.readouterr().out == "unlocked\n"


def test_structured_log_and_level4_reply(verifier):
    verifier.start()
    for _ in range(5):
        client = verifier.connect()
        client.sendall(b"VERIFY 000000\n")
        assert receive(client) == b"NO\n"
    log = (verifier.root / "log").read_text()
    assert "event=totp-failure failures=5 lock_level=1" in log
    assert "event=totp-lock lock_level=1 seconds=300" in log
    assert "000000" not in log and verifier.secret not in log


@pytest.mark.parametrize("operation", ["enroll", "rotate"])
def test_N9_M8_pending_secret_lifetime(verifier, operation):
    if operation == "enroll":
        verifier.state.unlink()
    initial = verifier.state.read_bytes() if verifier.state.exists() else None
    verifier.start()
    def request(cmd):
        client = verifier.connect("admin")
        client.sendall(cmd + b"\n")
        return receive(client).strip()
    begin = operation.upper().encode() + b"_BEGIN"
    commit = operation.upper().encode() + b"_COMMIT "
    for expiry in ("wrong-limit", "timeout"):
        secret = request(begin)
        assert secret.startswith(b"SECRET ")
        assert request(begin) == b"REFUSED"
        valid = totpd.compute_hotp(base64.b32decode(secret[7:]), verifier.wall // 30).encode()
        wrong = str((int(valid) + 1) % 1000000).zfill(6).encode()
        if expiry == "wrong-limit":
            for _ in range(5):
                assert request(commit + wrong) == b"NO"
        else:
            verifier.wall += 300
        assert request(commit + valid) == b"UNAVAILABLE"
        assert (verifier.state.read_bytes() if verifier.state.exists() else None) == initial
        assert not verifier.state.with_suffix(".json.tmp").exists()


@pytest.mark.parametrize("mode", ["stop-ignoring-child", "unreapable", "idle-input", "blocked-terminal",
                                   "split-replies", "escape-release", "oversized-reply"])
def test_N2_M6_gate_relay_at_pty(verifier, start_gate, mode):
    recorder = verifier.root / "pty-child.py"
    report = verifier.root / "report"
    recorder.write_text("""
import json, os, signal, sys, time, tty
mode, report, operation = sys.argv[1:4]
if operation != "attach-session":
    raise SystemExit(0)
if mode in ("stop-ignoring-child", "idle-input"):
    signal.signal(signal.SIGTERM, signal.SIG_IGN)
    signal.signal(signal.SIGHUP, signal.SIG_IGN)
tty.setraw(0)
def record(value):
    with open(report, "a") as stream:
        stream.write(json.dumps([time.monotonic(), value]) + "\\n")
record(os.getpid())
os.write(1, b"CHILD-READY")
if mode == "blocked-terminal":
    while True:
        os.write(1, b"X" * 65536)
while True:
    data = os.read(0, 256)
    if not data:
        break
    record(data.hex())
""")
    verifier.start()
    idle = 1.0 if mode != "unreapable" else 15
    options = dict(tmux_prefix=[sys.executable, "-IS", str(recorder), mode, str(report)],
                   idle_seconds=idle, never_reaped=(mode == "unreapable"),
                   record_terminal_flush=(mode == "idle-input"))
    instance = start_gate(**options)
    instance.until(b"Code: ")
    instance.send(b"287082\n")
    instance.until(b"CHILD-READY")
    child = json.loads(report.read_text().splitlines()[0])[1]
    if mode in ("stop-ignoring-child", "unreapable"):
        began = time.monotonic()
        instance.proc.terminate()
        assert instance.proc.wait(timeout=5.1) == 1
        assert time.monotonic() - began >= (4 if mode == "unreapable" else 2)
        if mode == "stop-ignoring-child":
            with pytest.raises(ProcessLookupError):
                os.kill(child, 0)
    elif mode == "blocked-terminal":
        assert instance.proc.wait(timeout=idle + 3.5) == 1
    elif mode == "idle-input":
        wait_file(verifier.root / "idle-end")
        instance.send(b"359152\n")
        instance.until(b"Code: ", timeout=4)
        assert verifier.events.count("admitted") == 1
        verifier.wall = 89
        instance.send(b"359152\n")
        instance.until(b"CHILD-READY")
        assert verifier.events.count("admitted") == 2
        assert len(report.read_text().splitlines()) == 2
        flushes = [int(value) for value in (verifier.root / "terminal-flushes").read_text().splitlines()]
        assert flushes == [termios.TCIFLUSH]
    elif mode == "split-replies":
        replies = [b"\x1b[2;3R", b"\x1b[?1;2c", b"\x1b[>1c", b"\x1b[?1;2$y", b"\x1b[I", b"\x1b[O",
                   b"\x1b]11;x\x07", b"\x1bP1x\x1b\\", b"\x1b[0n", b"\x1b[3n", b"\x1b[8;2;3t"]
        for reply in replies:
            instance.send(reply[:2])
            time.sleep(.05)
            second = time.monotonic()
            instance.send(reply[2:])
            deadline = time.monotonic() + .25
            while True:
                rows = [json.loads(row) for row in report.read_text().splitlines()[1:]]
                if rows and rows[-1][1] == reply.hex():
                    break
                assert time.monotonic() < deadline
                time.sleep(.002)
            assert rows[-1][0] >= second
        wait_file(verifier.root / "idle-end")
        stamp = float((verifier.root / "idle-end").read_text())
        assert stamp - json.loads(report.read_text().splitlines()[0])[0] < idle + .25
    else:
        data = b"\x1b" if mode == "escape-release" else b"\x1b]" + b"x" * 63
        began = time.monotonic()
        instance.send(data)
        instance.until(b"Code: ", timeout=2)
        rows = [json.loads(row) for row in report.read_text().splitlines()[1:]]
        assert bytes.fromhex("".join(row[1] for row in rows)) == data
        elapsed = rows[0][0] - began
        if mode == "escape-release":
            assert .099 <= elapsed <= .3
        else:
            assert elapsed < .1


def wait_file(path, timeout=4):
    deadline = time.monotonic() + timeout
    while not path.exists() or not path.stat().st_size:
        assert time.monotonic() < deadline, path
        time.sleep(.005)


def test_N10_M2_stalled_partial_line(verifier):
    verifier.start()
    original = verifier.state.read_bytes()
    client = verifier.connect()
    verifier.wait("admitted")
    client.sendall(b"VERIFY 287")
    verifier.tick += 5.01
    verifier.wait("closed deadline")
    assert receive(client) == b"" and verifier.state.read_bytes() == original
    valid = verifier.connect()
    valid.sendall(b"VERIFY 287082\n")
    assert receive(valid) == b"OK\n"


def test_N1_M2_window_per_candidate(verifier):
    for counter in (1, 2, 3, 4, 5):
        code = totpd.compute_hotp(base64.b32decode(verifier.secret), counter)
        result = totpd.verify_code(verifier.secret, code, 3, 0)
        assert result == ((True, counter) if counter in (2, 3, 4) else (False, None))


def test_N10_M2_unreadable_clock(verifier):
    verifier.wall = None
    verifier.start()
    before = verifier.state.read_bytes()
    client = verifier.connect()
    client.sendall(b"VERIFY 287082\n")
    assert receive(client) == b"UNAVAILABLE\n"
    assert verifier.state.read_bytes() == before
    verifier.wall = 59
    client = verifier.connect()
    client.sendall(b"VERIFY 287082\n")
    assert receive(client) == b"OK\n"


@pytest.mark.parametrize("failure", ["WAIT", "NO", "malformed"])
def test_N1_N8_M4_failed_prompt_limit(verifier, start_gate, failure):
    # Only the per-attempt sleep is shortened in the fixture process.
    verifier.start()
    instance = start_gate(short_retry=True)
    instance.until(b"Code: ")
    for i in range(10):
        if failure == "malformed":
            code = b"12345" if i % 2 else b"1234567"
            message = b"Invalid code"
        else:
            if failure == "NO":
                verifier.tick += 86401
            code = b"000000"
            message = b"Too many attempts" if failure == "WAIT" and i >= 5 else b"Invalid code"
        instance.send(code + b"\n")
        instance.until(message)
        if i < 9:
            instance.until(b"Code: ")
    assert instance.proc.wait(timeout=1) == 1
    assert verifier.events.count("admitted") == (0 if failure == "malformed" else 10)


def test_N2_N8_M4_tmux_control_deadline(verifier, start_gate):
    path = verifier.root / "hung.py"
    path.write_text("import pathlib,time\npathlib.Path('has-started').touch()\ntime.sleep(30)\n")
    verifier.start()
    instance = start_gate(tmux_prefix=[sys.executable, str(path)])
    instance.until(b"Code: ")
    started = time.monotonic()
    instance.send(b"287082\n")
    assert instance.proc.wait(timeout=6) == 1
    assert 5 <= time.monotonic() - started < 6 and (verifier.root / "has-started").exists()
    assert not (verifier.root / "attached").exists()


def test_N6_M1_original_command_is_ignored(verifier, start_gate, scratch_tmux):
    argv, control = scratch_tmux
    marker = verifier.root / "original-command"
    command = "/usr/bin/touch " + str(marker)
    verifier.start()
    instance = start_gate(tmux_prefix=argv, gate_env={"SSH_ORIGINAL_COMMAND": command})
    instance.until(b"Code: ")
    instance.send(b"287082\n")
    wait_clients(control, 1)
    assert not marker.exists()
    subprocess.run(["/bin/sh", "-c", command], cwd=verifier.root, check=True)
    assert marker.exists()


def test_N10_E1_complete_state_at_commit_boundaries(verifier, monkeypatch):
    previous = verifier.state.read_bytes()
    replacement = json.loads(previous)
    replacement["last_counter"] += 1
    actual_replace = os.replace
    def fail_replace(tmp, final):
        assert Path(final) == verifier.state
        assert verifier.state.read_bytes() == previous
        assert json.loads(Path(tmp).read_bytes()) == replacement
        assert Path(tmp).stat().st_mode & 0o777 == 0o600
        raise OSError("fixture rename failed")
    with monkeypatch.context() as patch:
        patch.setattr(totpd.os, "replace", fail_replace)
        with pytest.raises(totpd.CommitPreRenameError):
            totpd.commit_state(verifier.state_dir, replacement)
    assert os.replace == actual_replace
    assert verifier.state.read_bytes() == previous
    totpd.commit_state(verifier.state_dir, replacement)
    assert json.loads(verifier.state.read_bytes()) == replacement


def test_N2_M6_idle_reprompt_outage(verifier, scratch_tmux, start_gate):
    argv, control = scratch_tmux
    verifier.start()
    instance = start_gate(tmux_prefix=argv, idle_seconds=1)
    instance.until(b"Code: ")
    instance.send(b"287082\n")
    wait_clients(control, 1)
    instance.until(b"Code: ")
    assert wait_clients(control, 0) == []
    verifier.finish()
    instance.send(b"359152\n")
    instance.until(b"console login unavailable")
    assert instance.proc.wait(timeout=2) == 1


def test_N4_M7_home_client_environments_and_options(verifier, scratch_tmux, start_gate):
    argv, control = scratch_tmux
    control("new-session", "-d", "-s", "work", "/bin/sleep 120")
    control("new-session", "-d", "-s", "work-console", "/bin/sleep 120")
    master, slave = pty.openpty()
    home_env = {"HOME": str(verifier.root), "TERM": "xterm", "PATH": "/usr/bin:/bin",
                "SSH_AUTH_SOCK": str(verifier.root / "auth"), "DISPLAY": ":99"}
    home = subprocess.Popen(argv + ["attach-session", "-t", "=work"], cwd=verifier.root, env=home_env,
                            stdin=slave, stdout=slave, stderr=slave, start_new_session=True)
    os.close(slave)
    def snapshot():
        return [control(*args).stdout for args in [
            ["show-environment", "-g"], ["show-environment", "-t", "=work"],
            ["show-options", "-g"], ["show-options", "-s"], ["show-options", "-w"],
            ["show-options", "-t", "work:"], ["show-options", "-t", "work-console:"]]]
    try:
        home_tty, = wait_clients(control, 1)
        before = snapshot()
        assert "DISPLAY=:99" in before[1] and home_env["SSH_AUTH_SOCK"] in before[1]
        verifier.start()
        instance = start_gate(tmux_prefix=argv, idle_seconds=1)
        instance.until(b"Code: ")
        instance.send(b"287082\n")
        clients = wait_clients(control, 2)
        assert home_tty in clients
        assert snapshot() == before
        gate_tty, = set(clients) - {home_tty}
        control("switch-client", "-c", gate_tty, "-t", "=work-console")
        instance.until(b"Code: ")
        assert wait_clients(control, 1) == [home_tty] and snapshot() == before
        second = start_gate(tmux_prefix=argv)
        second.until(b"Code: ")
        verifier.wall = 89
        second.send(b"359152\n")
        assert home_tty in wait_clients(control, 2)
        assert snapshot() == before
        second.proc.terminate()
        second.proc.wait(timeout=4)
        assert wait_clients(control, 1) == [home_tty]
        m2, s2 = pty.openpty()
        no_e = subprocess.Popen(argv + ["attach-session", "-t", "=work"], cwd=verifier.root,
                                env={k: v for k, v in home_env.items() if k not in ("DISPLAY", "SSH_AUTH_SOCK")},
                                stdin=s2, stdout=s2, stderr=s2, start_new_session=True)
        os.close(s2)
        try:
            wait_clients(control, 2)
            after = snapshot()
            assert after[0] == before[0] and after[1] != before[1]
            assert "-DISPLAY" in after[1] and "-SSH_AUTH_SOCK" in after[1]
        finally:
            _stop_pty_process(no_e, m2)
    finally:
        _stop_pty_process(home, master)


def test_N1_E1_compare_digest_required():
    assert "hmac.compare_digest(" in Path(TOTPD_PATH).read_text()


@pytest.mark.parametrize("sequence", ["replay", "lockout"])
def test_N1_M2_restart_persists_gate_decision(verifier, sequence):
    verifier.start()
    def verify(code):
        client = verifier.connect()
        client.sendall(b"VERIFY " + code + b"\n")
        return receive(client)
    if sequence == "lockout":
        for _ in range(5):
            assert verify(b"000000") == b"NO\n"
    else:
        assert verify(b"287082") == b"OK\n"
    verifier.finish()
    verifier.start()
    assert verify(b"287082") == (b"WAIT 300\n" if sequence == "lockout" else b"NO\n")
    verifier.wall = 359
    verifier.tick += 300
    assert verify(b"481090") == b"OK\n"


def test_N9_M8_rotation_verifies_only_the_committed_secret(verifier, monkeypatch):
    new = b"only-in-test-secret!"
    random_calls = {10: 0, 16: 0}
    def generate(size):
        if size == 20:
            return new
        assert size in (10, 16)
        random_calls[size] += 1
        return bytes([random_calls[size] % 256]) * size
    monkeypatch.setattr(totpd.os, "urandom", generate)
    verifier.start()
    def request(name, wire):
        sock = verifier.connect(name)
        sock.sendall(wire + b"\n")
        return receive(sock).strip()
    assert request("admin", b"ROTATE_BEGIN") == b"SECRET " + base64.b32encode(new)
    assert request("totp", b"VERIFY 287082") == b"OK"
    old_bytes = verifier.state.read_bytes()
    assert request("admin", b"ROTATE_COMMIT 000000") == b"NO"
    assert verifier.state.read_bytes() == old_bytes
    code = totpd.compute_hotp(new, 1).encode()
    assert request("admin", b"ROTATE_COMMIT " + code) == b"OK"
    verifier.wall = 89
    assert request("totp", b"VERIFY 359152") == b"NO"
    assert request("totp", b"VERIFY " + totpd.compute_hotp(new, 2).encode()) == b"OK"


def test_N5_N9_M8_pending_secret_dies_with_verifier(verifier):
    verifier.state.unlink()
    program = """
import importlib.util, os, sys
spec = importlib.util.spec_from_file_location("totpd", sys.argv[1])
daemon = importlib.util.module_from_spec(spec)
spec.loader.exec_module(daemon)
def event(name):
    if name == "ready":
        print("ready", flush=True)
raise SystemExit(daemon.run(*sys.argv[2:6], expected_conf_owner=os.getuid(), expected_dir_owner=os.getuid(),
                            peer_cred_fn=lambda s: (0, os.getpid()), event_hook=event))
"""
    proc = subprocess.Popen([sys.executable, "-IS", "-c", program, TOTPD_PATH, str(verifier.config),
                             verifier.state_dir, verifier.run_dir, str(verifier.root / "log")],
                            cwd=verifier.root, stdout=subprocess.PIPE)
    try:
        assert select.select([proc.stdout], [], [], 4)[0] and proc.stdout.readline() == b"ready\n"
        client = verifier.connect("admin")
        client.sendall(b"ENROLL_BEGIN\n")
        assert receive(client).startswith(b"SECRET ")
        assert list(Path(verifier.state_dir).iterdir()) == []
    finally:
        proc.kill()
        proc.wait(timeout=3)
    assert list(Path(verifier.state_dir).iterdir()) == []
    verifier.start()
    client = verifier.connect("admin")
    client.sendall(b"STATUS\n")
    assert receive(client) == b"NOT_ENROLLED\n"


def test_N3_E2_stale_socket_names_rebound(verifier):
    for name in ("totp", "admin"):
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as stale:
            stale.bind(str(Path(verifier.run_dir, name + ".sock")))
    verifier.start()
    admin = verifier.connect("admin")
    admin.sendall(b"STATUS\n")
    assert receive(admin) == b"ENROLLED\n"
    verify = verifier.connect()
    verify.sendall(b"VERIFY 287082\n")
    assert receive(verify) == b"OK\n"


def test_N10_M2_no_reply_before_rename(verifier, monkeypatch):
    original = totpd.commit_state
    entered = threading.Event()
    resume = threading.Event()
    def paused(directory, state, **kwargs):
        entered.set()
        assert resume.wait(3)
        original(directory, state, **kwargs)
    monkeypatch.setattr(totpd, "commit_state", paused)
    verifier.start()
    for code, expected in [(b"287082", b"OK\n"), (b"000000", b"NO\n")]:
        entered.clear()
        resume.clear()
        sock = verifier.connect()
        sock.sendall(b"VERIFY " + code + b"\n")
        assert entered.wait(3)
        try:
            assert not select.select([sock], [], [], .05)[0]
        finally:
            resume.set()
        assert receive(sock) == expected


def test_N5_E3_child_recorder_detects_seeded_values(verifier):
    probe = "synthetic-recorder-self-test"
    script = "import json,os,sys; print(json.dumps([sys.argv[1:],dict(os.environ)]))"
    def recorded(argv, env):
        return subprocess.check_output([sys.executable, "-IS", "-c", script, *argv], env=env,
                                       cwd=verifier.root, timeout=3)
    assert probe.encode() not in recorded([], {"HOME": str(verifier.root)})
    assert probe.encode() in recorded([probe], {"HOME": str(verifier.root)})
    assert probe.encode() in recorded([], {"HOME": str(verifier.root), "FIXTURE_SAMPLE": probe})


def test_N2_M6_operator_input_extends_idle(verifier, start_gate, scratch_tmux):
    argv, control = scratch_tmux
    verifier.start()
    instance = start_gate(tmux_prefix=argv, idle_seconds=1)
    instance.until(b"Code: ")
    instance.send(b"287082\n")
    client, = wait_clients(control, 1)
    for data in (b"x", b"\x1b[<0;2;3M", b"y"):
        time.sleep(.55)
        instance.send(data)
        assert client in wait_clients(control, 1)
    instance.until(b"Code: ")
    assert wait_clients(control, 0) == []


def test_N1_M7_create_race_is_rechecked(verifier, start_gate, scratch_tmux):
    argv, control = scratch_tmux
    script = verifier.root / "race.py"
    script.write_text("""
import os, pathlib, subprocess, sys, time
argv = sys.argv[1:]
if "has-session" in argv:
    result = subprocess.run(argv)
    if result.returncode:
        pathlib.Path(f"checked-{os.getpid()}").touch()
        deadline = time.monotonic() + 3
        while len(list(pathlib.Path(".").glob("checked-*"))) < 2:
            if time.monotonic() >= deadline:
                raise SystemExit(2)
            time.sleep(.01)
    raise SystemExit(result.returncode)
os.execv(argv[0], argv)
""")
    verifier.start()
    prefix = [sys.executable, "-IS", str(script), *argv]
    first = start_gate(tmux_prefix=prefix)
    second = start_gate(tmux_prefix=prefix)
    first.until(b"Code: ")
    second.until(b"Code: ")
    first.send(b"287082\n")
    deadline = time.monotonic() + 3
    while not list(verifier.root.glob("checked-*")):
        assert time.monotonic() < deadline
        time.sleep(.01)
    verifier.wall = 89
    second.send(b"359152\n")
    assert len(wait_clients(control, 2)) == 2
    assert len(list(verifier.root.glob("checked-*"))) == 2
    assert control("list-sessions", "-F", "#{session_name}").stdout.splitlines() == ["work"]


def test_N2_M6_relay_error_closes_only_gate(verifier, start_gate, scratch_tmux, home_client):
    argv, control = scratch_tmux
    verifier.start()
    instance = start_gate(tmux_prefix=argv, relay_fault=True)
    instance.until(b"Code: ")
    instance.send(b"287082\n")
    assert home_client[0] in wait_clients(control, 2)
    (verifier.root / "fail-relay").touch()
    instance.send(b"x")
    assert instance.proc.wait(timeout=4) == 1
    assert wait_clients(control, 1) == [home_client[0]]
    os.kill(home_client[1], 0)
    assert control("has-session", "-t", "=work-console").returncode == 0
    assert control("has-session", "-t", "=work").returncode == 0


def test_N2_M4_reprompt_rejects_stuck_verifier(verifier, start_gate, scratch_tmux):
    argv, control = scratch_tmux
    path = Path(verifier.run_dir, "totp.sock")
    assert verifier.root in path.parents
    verifier.start()
    instance = start_gate(tmux_prefix=argv, idle_seconds=1)
    instance.until(b"Code: ")
    instance.send(b"287082\n")
    wait_clients(control, 1)
    instance.until(b"Code: ")
    verifier.finish()
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as server:
        server.bind(str(path))
        server.listen()
        server.settimeout(3)
        instance.send(b"359152\n")
        peer, _ = server.accept()
        with peer:
            assert peer.recv(32) == b"VERIFY 359152\n"
            assert instance.proc.wait(timeout=6) == 1
    assert wait_clients(control, 0) == []


def test_N2_M4_zero_byte_prompt_read(verifier, start_gate):
    instance = start_gate()
    instance.until(b"Code: ")
    os.close(instance.master)
    instance.master = os.open(os.devnull, os.O_RDONLY)
    assert instance.proc.wait(timeout=2) == 1


def test_N1_M2_cannot_verify_against_old_wall_clock(verifier):
    verifier.start()
    verifier.wall = 119
    client = verifier.connect()
    client.sendall(b"VERIFY 969429\n")
    assert receive(client) == b"OK\n"
    verifier.wall = 59
    client = verifier.connect()
    client.sendall(b"VERIFY 287082\n")
    assert receive(client) == b"NO\n"


def test_N1_N2_N8_E4_errors_never_start_a_child(verifier, start_gate):
    recorder = verifier.root / "inert-tmux.py"
    recorder.write_text("""
import json, pathlib, sys
assert pathlib.Path.cwd().name.startswith("wct.")
with open("calls.jsonl", "a") as stream:
    stream.write(json.dumps(sys.argv[1:]) + chr(10))
""")
    prefix = [sys.executable, "-IS", str(recorder)]
    calls = verifier.root / "calls.jsonl"
    gate_process = start_gate(tmux_prefix=prefix)
    gate_process.until(b"Code: ")
    gate_process.send(b"\x03")
    gate_process.until(b"Code: ")
    gate_process.send(b"287082\n")
    assert gate_process.proc.wait(timeout=4) == 1
    assert not calls.exists()
    verifier.start()
    gate_process = start_gate(tmux_prefix=prefix)
    gate_process.until(b"Code: ")
    gate_process.send(b"287082\n")
    assert gate_process.proc.wait(timeout=4) == 0
    assert [json.loads(row)[0] for row in calls.read_text().splitlines()] == ["has-session", "attach-session"]


def test_N2_M6_pane_output_does_not_extend_idle(verifier, scratch_tmux, start_gate):
    argv, control = scratch_tmux
    pane = verifier.root / "output.py"
    pane.write_text("import time\nwhile True:\n    print('pane-output', flush=True)\n    time.sleep(.05)\n")
    control("new-session", "-d", "-s", "work", sys.executable, str(pane))
    verifier.start()
    instance = start_gate(tmux_prefix=argv, idle_seconds=1)
    instance.until(b"Code: ")
    instance.send(b"287082\n")
    instance.until(b"pane-output")
    assert len(wait_clients(control, 1)) == 1
    instance.until(b"Code: ", timeout=2)
    assert wait_clients(control, 0) == []
    assert control("has-session", "-t", "=work").returncode == 0


def test_N5_M8_secret_scan_across_enrollment_and_login(verifier, monkeypatch, start_gate, scratch_tmux):
    argv, control = scratch_tmux
    recorder = verifier.root / "spawn.py"
    records = verifier.root / "records"
    recorder.write_text("""
import json, os, sys
mode, *command = sys.argv[1:]
with open("records", "a") as stream:
    stream.write(json.dumps([command, dict(os.environ)]) + chr(10))
if mode == "exec":
    os.execv(command[0], command)
""")
    prefix = [sys.executable, "-IS", str(recorder)]
    fixture_env = {"HOME": str(verifier.root), "PATH": "/usr/bin:/bin"}
    baseline = verifier.runner

    def runner(cmd, timeout):
        # ps, netstat and launchctl use captured output. The child still
        # observes the exact argument vector and environment for each call.
        mode = "exec" if cmd[0] == "/bin/ls" else "record"
        output = subprocess.check_output(prefix + [mode, *cmd], cwd=verifier.root,
                                         env=fixture_env, timeout=timeout, text=True)
        return output if mode == "exec" else baseline(cmd, timeout)

    verifier.runner = runner
    admin_commit_at_pty(verifier, monkeypatch, "enroll", None)
    recovery_raw = bytes([1]) * 10
    recovery_code = base64.b32encode(recovery_raw).decode()
    recovery_path = Path(verifier.state_dir, "recovery.json")
    recovery_data = json.loads(recovery_path.read_text())
    assert len(recovery_data["codes"]) == 10
    assert all(recovery_code not in recovery_path.read_text() for recovery_code in
               (base64.b32encode(bytes([i]) * 10).decode() for i in range(1, 11)))
    raw = b"only-in-test-secret!"
    secret = base64.b32encode(raw)
    verifier.wall = 89
    code = totpd.compute_hotp(raw, 2).encode()
    wrong = b"000000"
    assert wrong != code
    instance = start_gate(tmux_prefix=prefix + ["exec", *argv], short_retry=True,
                          gate_env={"USER": "fixture-user", "LOGNAME": "fixture-user", "LANG": "C",
                                    "SSH_ORIGINAL_COMMAND": "must-not-reach-tmux",
                                    "SSH_AUTH_SOCK": str(verifier.root / "ignored-auth.sock")})
    instance.until(b"Code: ")
    instance.send(wrong + b"\n")
    instance.until(b"Invalid code")
    instance.until(b"Code: ")
    instance.send(("-".join(recovery_code[i:i + 4] for i in range(0, 16, 4))).encode() + b"\n")
    wait_clients(control, 1)
    assert "event=totp-recovery-used remaining=9" in (verifier.root / "log").read_text()
    records_data = [json.loads(line) for line in records.read_text().splitlines()]
    commands = [row[0] for row in records_data]
    expected_tmux_env = {
        "PATH": "/usr/bin:/bin:/usr/sbin:/sbin:/usr/bin",
        "HOME": str(verifier.root),
        "USER": "fixture-user",
        "LOGNAME": "fixture-user",
        "TERM": "xterm",
        "LANG": "C",
    }
    tmux_records = [env for command, env in records_data if argv[0] in command]
    assert tmux_records
    # Darwin injects these process-locale keys when starting the Python recorder.
    runtime_keys = {"LC_CTYPE", "__CF_USER_TEXT_ENCODING"}
    for env in tmux_records:
        assert set(env) - runtime_keys == set(expected_tmux_env)
        assert set(env) <= set(expected_tmux_env) | runtime_keys
        assert all(env[key] == value for key, value in expected_tmux_env.items())
    for tool in ("/bin/ps", "/usr/sbin/netstat", "/bin/launchctl", argv[0]):
        assert any(call[0] == tool for call in commands)
    values = (raw, secret, code, wrong, recovery_raw, recovery_code.encode())
    for file in verifier.root.rglob("*"):
        assert all(value not in os.fsencode(file.name) for value in values)
        if file.is_file() and file != verifier.state:
            assert all(value not in file.read_bytes() for value in values), file
    assert secret in verifier.state.read_bytes()


def test_N1_D4b_lockout_requests_do_not_increment_failures(verifier):
    verifier.start()
    state = json.loads(verifier.state.read_bytes())
    state.update(failures=5, locked_until=verifier.wall + 300)
    totpd.commit_state(verifier.state_dir, state)
    before = verifier.state.read_bytes()
    client = verifier.connect()
    client.sendall(b"VERIFY 287082\n")
    assert receive(client) == b"WAIT 300\n"
    assert verifier.state.read_bytes() == before


def test_N1_D11b_non_verify_commands_do_not_count(verifier):
    verifier.start()
    before = verifier.state.read_bytes()
    client = verifier.connect()
    client.sendall(b"GARBAGE287082\n")
    verifier.wait("closed wire-reject")
    assert receive(client) == b""
    assert verifier.state.read_bytes() == before


def test_N10_D44_expiry_reset_commit_failure_is_unavailable(verifier, monkeypatch):
    verifier.start()
    state = json.loads(verifier.state.read_bytes())
    state.update(failures=5, locked_until=verifier.wall - 1)
    totpd.commit_state(verifier.state_dir, state)
    before = verifier.state.read_bytes()
    monkeypatch.setattr(totpd.run, "injected_commit_fault", "pre-rename-fsync", raising=False)
    client = verifier.connect()
    client.sendall(b"VERIFY 287082\n")
    assert receive(client) == b"UNAVAILABLE\n"
    assert verifier.state.read_bytes() == before


def test_N10_D30_temporary_state_is_private(verifier):
    replacement = json.loads(verifier.state.read_bytes())
    replacement["last_counter"] += 1
    temporary = Path(verifier.state_dir, "state.json.tmp")
    original_open = totpd.os.open

    def inspect_open(path, flags, mode=0o777):
        result = original_open(path, flags, mode)
        if path == str(temporary):
            assert mode == 0o600
        return result

    totpd.os.open = inspect_open
    try:
        totpd.commit_state(verifier.state_dir, replacement)
    finally:
        totpd.os.open = original_open
    assert json.loads(verifier.state.read_bytes()) == replacement


def test_N1_D40_concurrent_same_code_is_accepted_once(verifier):
    verifier.start()
    first, second = verifier.connect(), verifier.connect()
    verifier.wait("admitted", 2)
    first.sendall(b"VERIFY 287082\n")
    second.sendall(b"VERIFY 287082\n")
    assert sorted((receive(first), receive(second))) == [b"NO\n", b"OK\n"]


def _recovery_admin(verifier, command):
    sock = verifier.connect("admin")
    sock.sendall(command.encode("ascii") + b"\n")
    return receive(sock).decode("ascii").strip()


def test_recovery_generate_and_storage(verifier):
    assert Path(verifier.run_dir).is_relative_to(verifier.root)
    assert Path(verifier.state_dir).is_relative_to(verifier.root)
    verifier.start()
    assert _recovery_admin(verifier, "RECOVERY_BEGIN") == "RECOVERY_PENDING"
    grouped = [_recovery_admin(verifier, f"RECOVERY_GET {index}").removeprefix("CODE ") for index in range(10)]
    assert len(set(grouped)) == 10
    assert all(re.fullmatch(r"[A-Z2-7]{4}(?:-[A-Z2-7]{4}){3}", code) for code in grouped)
    assert _recovery_admin(verifier, "RECOVERY_GET 10") == "UNAVAILABLE"
    assert _recovery_admin(verifier, "RECOVERY_GET -1") == "UNAVAILABLE"
    assert _recovery_admin(verifier, "RECOVERY_COMMIT 287082") == "OK"
    recovery_path = Path(verifier.state_dir, "recovery.json")
    assert recovery_path.stat().st_mode & 0o777 == 0o600
    stored = json.loads(recovery_path.read_text())
    assert type(stored["v"]) is int and stored["v"] == 1 and len(stored["codes"]) == 10
    assert all(set(item) == {"s", "h"} for item in stored["codes"])
    assert all(item["h"] == hashlib.sha256(bytes.fromhex(item["s"]) + code.replace("-", "").encode()).hexdigest()
               for item, code in zip(stored["codes"], grouped))
    for code in grouped:
        plain = code.replace("-", "").encode()
        assert plain not in recovery_path.read_bytes()
        assert plain not in verifier.state.read_bytes()
        log_path = verifier.root / "log"
        assert plain not in (log_path.read_bytes() if log_path.exists() else b"")
    assert set(json.loads(verifier.state.read_text())) == {
        "secret", "last_counter", "failures", "locked_until", "enrolled"
    }
    assert _recovery_admin(verifier, "RECOVERY_GET 0") == "UNAVAILABLE"


def test_recovery_plaintext_scan_positive_controls(verifier):
    assert Path(verifier.run_dir).is_relative_to(verifier.root)
    assert Path(verifier.state_dir).is_relative_to(verifier.root)
    verifier.start()
    assert _recovery_admin(verifier, "RECOVERY_BEGIN") == "RECOVERY_PENDING"
    codes = [_recovery_admin(verifier, f"RECOVERY_GET {index}").removeprefix("CODE ") for index in range(10)]
    assert _recovery_admin(verifier, "RECOVERY_COMMIT 287082") == "OK"
    recovery_path = Path(verifier.state_dir, "recovery.json")
    stored = json.loads(recovery_path.read_text())
    assert len(stored["codes"]) == 10
    for code in codes:
        raw = code.replace("-", "").encode()
        assert raw not in recovery_path.read_bytes()
        assert raw not in verifier.state.read_bytes()
        log_path = verifier.root / "log"
        assert raw not in (log_path.read_bytes() if log_path.exists() else b"")
    client = verifier.connect()
    client.sendall(f"VERIFY {codes[0]}\n".encode())
    assert receive(client) == b"OK\n"
    assert "event=totp-recovery-used remaining=9" in (verifier.root / "log").read_text()


def test_recovery_wrong_code_not_logged(verifier):
    assert Path(verifier.run_dir).is_relative_to(verifier.root)
    assert Path(verifier.state_dir).is_relative_to(verifier.root)
    verifier.start()
    assert _recovery_admin(verifier, "RECOVERY_BEGIN") == "RECOVERY_PENDING"
    codes = [_recovery_admin(verifier, f"RECOVERY_GET {index}").removeprefix("CODE ") for index in range(10)]
    assert _recovery_admin(verifier, "RECOVERY_COMMIT 287082") == "OK"
    wrong = "AAAA-BBBB-CCCC-DDDD"
    assert wrong not in codes
    client = verifier.connect()
    client.sendall(f"VERIFY {wrong}\n".encode())
    assert receive(client) != b"OK\n"
    log = (verifier.root / "log").read_text()
    assert "totp-recovery-failure" in log
    assert wrong not in log and wrong.replace("-", "") not in log
    client = verifier.connect()
    client.sendall(f"VERIFY {codes[0]}\n".encode())
    assert receive(client) == b"OK\n"


def test_recovery_unlock_burns_before_reply(verifier):
    state = json.loads(verifier.state.read_text())
    state.update(failures=5, locked_until=86459, lock_level=1)
    totpd.commit_state(verifier.state_dir, state)
    verifier.start()
    assert _recovery_admin(verifier, "RECOVERY_BEGIN") == "RECOVERY_PENDING"
    codes = [_recovery_admin(verifier, f"RECOVERY_GET {index}").removeprefix("CODE ") for index in range(10)]
    code = codes[0]
    assert _recovery_admin(verifier, "RECOVERY_COMMIT 287082") == "OK"
    client = verifier.connect()
    client.sendall(f"VERIFY {code}\n".encode())
    assert receive(client) == b"OK\n"
    after = json.loads(verifier.state.read_text())
    assert (after["failures"], after["locked_until"], after.get("lock_level", 0)) == (0, 0, 0)
    client = verifier.connect()
    client.sendall(f"VERIFY {code}\n".encode())
    assert receive(client) == b"NO\n"
    for code in codes[1:8]:
        client = verifier.connect()
        client.sendall(f"VERIFY {code}\n".encode())
        assert receive(client) == b"OK\n"
    stored = json.loads(Path(verifier.state_dir, "recovery.json").read_text())
    assert len(stored["codes"]) == 2
    assert "event=totp-recovery-used remaining=9" in (verifier.root / "log").read_text()
    assert "event=totp-recovery-low remaining=2" in (verifier.root / "log").read_text()


@pytest.mark.parametrize("locked", [False, True])
def test_recovery_after_wrong_attempts(verifier, locked):
    if locked:
        state = json.loads(verifier.state.read_text())
        state.update(failures=5, locked_until=86459, lock_level=1)
        totpd.commit_state(verifier.state_dir, state)
    verifier.start()
    assert _recovery_admin(verifier, "RECOVERY_BEGIN") == "RECOVERY_PENDING"
    code = _recovery_admin(verifier, "RECOVERY_GET 0").removeprefix("CODE ")
    assert _recovery_admin(verifier, "RECOVERY_COMMIT 287082") == "OK"
    before = json.loads(verifier.state.read_text())
    for _ in range(20):
        client = verifier.connect()
        client.sendall(b"VERIFY AAAA-BBBB-CCCC-DDDD\n")
        assert receive(client) == b"NO\n"
    assert json.loads(verifier.state.read_text()) == before
    verifier.tick += 60
    client = verifier.connect()
    client.sendall(b"VERIFY AAAA-BBBB-CCCC-DDDD\n")
    assert receive(client) == b"NO\n"
    client = verifier.connect()
    client.sendall(f"VERIFY {code}\n".encode())
    assert receive(client) == b"OK\n"
    failures = [line for line in (verifier.root / "log").read_text().splitlines()
                if line.startswith("totp-recovery-failure ")]
    assert failures == ["totp-recovery-failure count=1", "totp-recovery-failure count=20"]


def test_recovery_concurrent_same_code_is_accepted_once(verifier):
    verifier.start()
    assert _recovery_admin(verifier, "RECOVERY_BEGIN") == "RECOVERY_PENDING"
    code = _recovery_admin(verifier, "RECOVERY_GET 0").removeprefix("CODE ")
    assert _recovery_admin(verifier, "RECOVERY_COMMIT 287082") == "OK"
    first, second = verifier.connect(), verifier.connect()
    verifier.wait("admitted", 2)
    first.sendall(f"VERIFY {code}\n".encode())
    second.sendall(f"VERIFY {code}\n".encode())
    assert sorted((receive(first), receive(second))) == [b"NO\n", b"OK\n"]


def test_gate_recovery_reaches_locked_totpd(verifier, start_gate, scratch_tmux):
    argv, control = scratch_tmux
    state = json.loads(verifier.state.read_text())
    state.update(failures=5, locked_until=86459, lock_level=1)
    totpd.commit_state(verifier.state_dir, state)
    verifier.start()
    assert _recovery_admin(verifier, "RECOVERY_BEGIN") == "RECOVERY_PENDING"
    code = _recovery_admin(verifier, "RECOVERY_GET 0").removeprefix("CODE ")
    assert _recovery_admin(verifier, "RECOVERY_COMMIT 287082") == "OK"
    instance = start_gate(tmux_prefix=argv)
    instance.until(b"Code: ")
    instance.send(code.lower().encode() + b"\n")
    wait_clients(control, 1)
    assert "event=totp-recovery-used remaining=9" in (verifier.root / "log").read_text()
    result = json.loads(verifier.state.read_text())
    assert (result["failures"], result["locked_until"], result.get("lock_level", 0)) == (0, 0, 0)


@pytest.mark.parametrize("operation", ["ENROLL", "ROTATE"])
def test_recovery_codes_are_generated_for_enroll_and_rotate(verifier, monkeypatch, operation):
    assert Path(verifier.run_dir).is_relative_to(verifier.root)
    assert Path(verifier.state_dir).is_relative_to(verifier.root)
    if operation == "ENROLL":
        verifier.state.unlink()
    calls = {10: 0, 16: 0}
    def generate(size):
        if size == 20:
            return b"Z" * 20
        assert size in calls
        calls[size] += 1
        return bytes([calls[size]]) * size
    monkeypatch.setattr(totpd.os, "urandom", generate)
    verifier.start()
    begin = _recovery_admin(verifier, operation + "_BEGIN")
    assert begin.startswith("SECRET ")
    codes = [_recovery_admin(verifier, f"RECOVERY_GET {index}").removeprefix("CODE ")
             for index in range(10)]
    assert len(set(codes)) == 10
    raw = base64.b32decode(begin.removeprefix("SECRET "))
    commit_code = totpd.compute_hotp(raw, verifier.wall // 30)
    assert _recovery_admin(verifier, operation + "_COMMIT " + commit_code) == "OK"
    assert len(json.loads(Path(verifier.state_dir, "recovery.json").read_text())["codes"]) == 10
    assert _recovery_admin(verifier, "RECOVERY_GET 0") == "UNAVAILABLE"


@pytest.mark.parametrize("end", ["commit", "abort", "expiry", "fifth-wrong"])
def test_recovery_pending_ends_clear_codes(verifier, end):
    assert Path(verifier.run_dir).is_relative_to(verifier.root)
    assert Path(verifier.state_dir).is_relative_to(verifier.root)
    verifier.start()
    assert _recovery_admin(verifier, "RECOVERY_COMMIT 287082") == "UNAVAILABLE"
    assert _recovery_admin(verifier, "RECOVERY_BEGIN") == "RECOVERY_PENDING"
    assert _recovery_admin(verifier, "ENROLL_BEGIN") == "REFUSED"
    assert _recovery_admin(verifier, "ROTATE_BEGIN") == "REFUSED"
    assert _recovery_admin(verifier, "RECOVERY_GET 3").startswith("CODE ")
    if end == "commit":
        assert _recovery_admin(verifier, "RECOVERY_COMMIT 287082") == "OK"
    elif end == "abort":
        assert _recovery_admin(verifier, "ABORT") == "OK"
    elif end == "expiry":
        verifier.wall = 659
    else:
        for _ in range(5):
            assert _recovery_admin(verifier, "RECOVERY_COMMIT 000000") == "NO"
    assert _recovery_admin(verifier, "RECOVERY_GET 3") == "UNAVAILABLE"


def test_recovery_tmp_cleanup(verifier):
    assert Path(verifier.run_dir).is_relative_to(verifier.root)
    assert Path(verifier.state_dir).is_relative_to(verifier.root)
    tmp = Path(verifier.state_dir, "recovery.json.tmp")
    tmp.write_text("stale")
    verifier.start()
    assert not os.path.lexists(tmp)
    verifier.stop.set()
    verifier.worker.join(timeout=3)
    tmp.symlink_to(verifier.root / "missing-target")
    verifier.start()
    assert not os.path.lexists(tmp)


@pytest.mark.parametrize("damage", ["symlink", "dangling", "mode", "version"])
def test_recovery_damaged_does_not_block_totp(verifier, damage):
    assert Path(verifier.run_dir).is_relative_to(verifier.root)
    assert Path(verifier.state_dir).is_relative_to(verifier.root)
    verifier.start()
    path = Path(verifier.state_dir, "recovery.json")
    if damage == "symlink":
        target = verifier.root / "recovery-target"
        target.write_text('{"v": 1, "codes": []}')
        path.symlink_to(target)
    elif damage == "dangling":
        path.symlink_to(verifier.root / "missing-target")
    elif damage == "mode":
        path.write_text('{"v": 1, "codes": []}')
        path.chmod(0o644)
    else:
        path.write_text('{"v": true, "codes": []}')
        path.chmod(0o600)
    assert _recovery_admin(verifier, "RECOVERY_STATUS") == "RECOVERY 0"
    client = verifier.connect()
    client.sendall(b"VERIFY 287082\n")
    assert receive(client) == b"OK\n"
    assert "totp-recovery-damaged" in (verifier.root / "log").read_text()


def _admin_stub(root, replies):
    assert root.name.startswith("wct.") and root.is_dir()
    path = root / "admin.sock"
    server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    server.bind(str(path))
    server.listen(16)
    commands = []
    def serve():
        for expected, response in replies:
            conn, _ = server.accept()
            with conn:
                request = bytearray()
                while b"\n" not in request:
                    request.extend(conn.recv(64))
                command = request.split(b"\n", 1)[0].decode("ascii")
                commands.append(command)
                assert command == expected
                conn.sendall(response.encode("ascii") + b"\n")
    worker = threading.Thread(target=serve, daemon=True)
    worker.start()
    return path, server, worker, commands


def test_recovery_status_prints_remaining(verifier, capsys):
    assert Path(verifier.run_dir).is_relative_to(verifier.root)
    assert Path(verifier.state_dir).is_relative_to(verifier.root)
    path, server, worker, _commands = _admin_stub(verifier.root, [("RECOVERY_STATUS", "RECOVERY 9")])
    try:
        assert totpctl.run(["recovery-status"], admin_sock=str(path), check_root=False) == 0
        assert capsys.readouterr().out == "9 recovery codes remaining\n"
        worker.join(timeout=2)
        assert not worker.is_alive()
    finally:
        server.close()


@pytest.mark.parametrize("answer,expected", [("no", ["RECOVERY_BEGIN", "ABORT"]),
                                               ("yes", ["RECOVERY_BEGIN", *[f"RECOVERY_GET {i}" for i in range(10)],
                                                        "RECOVERY_COMMIT 287082"])])
def test_recovery_regen_confirmation_and_clear(verifier, capsys, answer, expected):
    assert Path(verifier.run_dir).is_relative_to(verifier.root)
    assert Path(verifier.state_dir).is_relative_to(verifier.root)
    replies = [("RECOVERY_BEGIN", "RECOVERY_PENDING")]
    if answer == "no":
        replies.append(("ABORT", "OK"))
    else:
        alphabet = "234567ABCD"
        replies.extend((f"RECOVERY_GET {index}", f"CODE AAAA-BBBB-CCCC-AAA{alphabet[index]}")
                       for index in range(10))
        replies.append(("RECOVERY_COMMIT 287082", "OK"))
    path, server, worker, commands = _admin_stub(verifier.root, replies)
    try:
        output = io.StringIO()
        code_input = io.StringIO(answer + "\n" + ("287082\n" if answer == "yes" else ""))
        result = totpctl.run(["recovery-regen"], admin_sock=str(path), tty_in=code_input,
                             tty_out=output, check_root=False)
        assert result == (0 if answer == "yes" else 1)
        worker.join(timeout=2)
        assert not worker.is_alive()
        assert commands == expected
        if answer == "yes":
            assert "Recovery codes (each works once):" in output.getvalue()
            assert output.getvalue().count("AAAA-BBBB-CCCC-") == 10
            assert "\x1b[3J\x1b[H\x1b[2J" in output.getvalue()
        else:
            assert "Recovery codes" not in output.getvalue()
    finally:
        server.close()


@pytest.mark.parametrize("fault,expected", [
    ({"recovery.json": "pre-rename-fsync"}, "retry"),
    ({"state.json": "pre-rename-open"}, "burned"),
    ({"recovery.json": "post-rename-dir-fsync"}, "fatal"),
])
def test_recovery_burn_fault_order(verifier, monkeypatch, fault, expected):
    verifier.start()
    assert _recovery_admin(verifier, "RECOVERY_BEGIN") == "RECOVERY_PENDING"
    code = _recovery_admin(verifier, "RECOVERY_GET 0").removeprefix("CODE ")
    assert _recovery_admin(verifier, "RECOVERY_COMMIT 287082") == "OK"
    monkeypatch.setattr(totpd.run, "injected_commit_fault", fault, raising=False)
    client = verifier.connect()
    client.sendall(f"VERIFY {code}\n".encode())
    assert receive(client) == b"UNAVAILABLE\n"
    if expected == "retry":
        monkeypatch.setattr(totpd.run, "injected_commit_fault", None, raising=False)
        client = verifier.connect()
        client.sendall(f"VERIFY {code}\n".encode())
        assert receive(client) == b"OK\n"
    else:
        before = json.loads(verifier.state.read_text())
        if expected == "fatal":
            verifier.worker.join(timeout=3)
            assert not verifier.worker.is_alive()
            assert json.loads(verifier.state.read_text()) == before
            assert len(json.loads(Path(verifier.state_dir, "recovery.json").read_text())["codes"]) == 9
        else:
            client = verifier.connect()
            client.sendall(f"VERIFY {code}\n".encode())
            assert receive(client) == b"NO\n"


def test_gate_recovery_input_normalization_and_cap():
    tmp = Path(make_short_tmpdir())
    assert tmp.is_dir() and tmp.name.startswith("wct.")
    try:
        conf = tmp / "totp.conf"
        conf.write_text(f"uid={os.getuid()}\ntmux=/usr/bin/tmux\nidle_seconds=120\nconsole_port=42722\n")
        sock_path = tmp / "totp.sock"
        server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        server.bind(str(sock_path))
        server.listen(8)
        server.settimeout(4)
        captured = []
        def serve():
            for index in range(7):
                conn, _ = server.accept()
                with conn:
                    conn.settimeout(2)
                    captured.append(conn.recv(64))
                    conn.sendall((b"WAIT 42\n" if index == 6 else b"NO\n"))
        worker = threading.Thread(target=serve, daemon=True)
        worker.start()
        instance = GateProcess(tmp, dict(conf_path=str(conf), sock_path=str(sock_path),
                                          expected_conf_owner=os.getuid(), expected_server_uid=os.getuid(),
                                          prompt_timeout=5, short_retry=True))
        code = "GEZDGNBVGY3TQOJQ"
        inputs = [b"GEZD-GNBV-GY3T-QOJQ\n", code.encode() + b"\n", code.lower().encode() + b"\n",
                  b"GEZD GNBV GY3T QOJQ\n", b"G-EZDGNBVGY3TQOJQ\n", code.encode() + b"X\x7f\n"]
        try:
            instance.until(b"Code: ")
            for data in inputs:
                instance.send(data)
                instance.until(b"Invalid code")
                instance.until(b"Code: ")
            assert captured == [b"VERIFY GEZD-GNBV-GY3T-QOJQ\n"] * 6
            instance.send(code.encode() + b"XXXXX\n")
            instance.until(b"Invalid code")
            instance.until(b"Code: ")
            assert len(captured) == 6
            instance.send(b"287082\n")
            instance.until(b"(42 s)")
            worker.join(timeout=2)
            assert not worker.is_alive()
            assert captured[-1] == b"VERIFY 287082\n"
        finally:
            instance.close()
            server.close()
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def test_gate_recovery_paste_and_lookalikes():
    tmp = Path(make_short_tmpdir())
    assert tmp.is_dir() and tmp.name.startswith("wct.")
    try:
        conf = tmp / "totp.conf"
        conf.write_text(f"uid={os.getuid()}\ntmux=/usr/bin/tmux\nidle_seconds=120\nconsole_port=42722\n")
        sock_path = tmp / "totp.sock"
        server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        server.bind(str(sock_path))
        server.listen(16)
        server.settimeout(5)
        captured = []
        running = [True]

        def serve():
            while running[0]:
                try:
                    conn, _ = server.accept()
                except OSError:
                    break
                with conn:
                    conn.settimeout(2)
                    try:
                        data = conn.recv(64)
                    except OSError:
                        continue
                    if data:
                        captured.append(data)
                        conn.sendall(b"NO\n")

        worker = threading.Thread(target=serve, daemon=True)
        worker.start()

        def make_gate():
            return GateProcess(
                tmp,
                dict(
                    conf_path=str(conf),
                    sock_path=str(sock_path),
                    expected_conf_owner=os.getuid(),
                    expected_server_uid=os.getuid(),
                    prompt_timeout=5,
                    short_retry=True,
                ),
            )

        # Section 1: Positive controls and input normalization / filter (M1, M2, N2, N3)
        instance1 = make_gate()
        try:
            instance1.until(b"Code: ")
            # Positive controls: plain recovery code and 6-digit code pass on pre-fix and post-fix
            instance1.send(b"GEZD-GNBV-GY3T-QOJQ\n")
            instance1.until(b"Invalid code")
            instance1.until(b"Code: ")

            instance1.send(b"108080\n")
            instance1.until(b"Invalid code")
            instance1.until(b"Code: ")

            # M1: Bracketed-paste recovery code
            instance1.send(b"\x1b[200~GEZD-GNBV-GY3T-QOJQ\x1b[201~\n")
            instance1.until(b"Invalid code")
            instance1.until(b"Code: ")

            # M1: Spaces and tab
            instance1.send(b"  GEZD-GNBV-GY3T-QOJQ\t\n")
            instance1.until(b"Invalid code")
            instance1.until(b"Code: ")

            # M1: En-dash replacement
            instance1.send(b"GEZD\xe2\x80\x93GNBV\xe2\x80\x93GY3T\xe2\x80\x93QOJQ\n")
            instance1.until(b"Invalid code")
            instance1.until(b"Code: ")

            # M2, N2: Lookalike 0/1/8 mapped to O/I/B
            instance1.send(b"18EZ-GNBV-GY3T-Q0JQ\n")
            instance1.until(b"Invalid code")
            instance1.until(b"Code: ")

            # N3: Escape sequence inside code (CSI arrow key)
            instance1.send(b"GEZDGNBV\x1b[DGY3TQOJQ\n")
            instance1.until(b"Invalid code")
            instance1.until(b"Code: ")

            # N3: Escape sequence inside code (SS3)
            instance1.send(b"GEZDGNBV\x1bOAGY3TQOJQ\n")
            instance1.until(b"Invalid code")
            instance1.until(b"Code: ")

            assert captured == [
                b"VERIFY GEZD-GNBV-GY3T-QOJQ\n",
                b"VERIFY 108080\n",
                b"VERIFY GEZD-GNBV-GY3T-QOJQ\n",
                b"VERIFY GEZD-GNBV-GY3T-QOJQ\n",
                b"VERIFY GEZD-GNBV-GY3T-QOJQ\n",
                b"VERIFY IBEZ-GNBV-GY3T-QOJQ\n",
                b"VERIFY GEZD-GNBV-GY3T-QOJQ\n",
                b"VERIFY GEZD-GNBV-GY3T-QOJQ\n",
            ]
        finally:
            instance1.close()

        # Section 1b: filter-state edges from the Fix item 2 state machine
        base = len(captured)
        instance1b = make_gate()
        try:
            instance1b.until(b"Code: ")
            # A lone Esc drops only the ESC; the next byte is kept
            instance1b.send(b"\x1bGEZD-GNBV-GY3T-QOJQ\n")
            instance1b.until(b"Invalid code")
            instance1b.until(b"Code: ")

            # Ctrl-C inside an open CSI sequence resets the filter to NORMAL
            instance1b.send(b"\x1b[\x03")
            instance1b.until(b"\x1b[?2004l\r\nCode: ")
            instance1b.send(b"GEZD-GNBV-GY3T-QOJQ\n")
            instance1b.until(b"Invalid code")
            instance1b.until(b"Code: ")

            assert captured[base:] == [
                b"VERIFY GEZD-GNBV-GY3T-QOJQ\n",
                b"VERIFY GEZD-GNBV-GY3T-QOJQ\n",
            ]
        finally:
            instance1b.close()
        del captured[base:]

        # Section 2: Prompt markers (M3), hint markers (M4), whole-line paste (N1), overflow (M5)
        instance2 = make_gate()
        try:
            # M3: First prompt reads until \x1b[?2004l\x1b[H\x1b[2J\x1b[3JCode:
            instance2.until(b"\x1b[?2004l\x1b[H\x1b[2J\x1b[3JCode: ")

            # M3: Ctrl-C re-prompt reads until \x1b[?2004l\r\nCode:
            instance2.send(b"\x03")
            instance2.until(b"\x1b[?2004l\r\nCode: ")

            # M4: Local rejection hint on short input
            instance2.send(b"GEZD\n")
            instance2.until(b"Invalid code (6 digits, or a 16-character recovery code: letters A-Z, digits 2-7)\r\n")
            instance2.until(b"Code: ")

            # M2: 16-character input containing 9 is local rejection with hint
            instance2.send(b"GEZD-GNBV-GY3T-9OJQ\n")
            instance2.until(b"Invalid code (6 digits, or a 16-character recovery code: letters A-Z, digits 2-7)\r\n")
            instance2.until(b"Code: ")

            # M5: 21 real characters with escape inside overflows and gives local rejection hint
            instance2.send(b"GEZDGNBVGY3TQOJQXXXXX\x1b[D\n")
            instance2.until(b"Invalid code (6 digits, or a 16-character recovery code: letters A-Z, digits 2-7)\r\n")
            instance2.until(b"Code: ")

            # M4: Verifier NO marker has no hint
            instance2.send(b"GEZD-GNBV-GY3T-QOJQ\n")
            instance2.until(b"\r\nInvalid code\r\n\x1b[?2004l\x1b[H")
            instance2.until(b"Code: ")

            # N1: Whole-line copy where newline is inside brackets
            instance2.send(b"\x1b[200~GEZD-GNBV-GY3T-QOJQ\n\x1b[201~")
            instance2.until(b"Invalid code")
            instance2.until(b"Code: ")
            instance2.send(b"GEZD-GNBV-GY3T-QOJQ\n")
            instance2.until(b"Invalid code")
            instance2.until(b"Code: ")

            # 3 more VERIFY lines were captured
            assert captured == [
                b"VERIFY GEZD-GNBV-GY3T-QOJQ\n",
                b"VERIFY 108080\n",
                b"VERIFY GEZD-GNBV-GY3T-QOJQ\n",
                b"VERIFY GEZD-GNBV-GY3T-QOJQ\n",
                b"VERIFY GEZD-GNBV-GY3T-QOJQ\n",
                b"VERIFY IBEZ-GNBV-GY3T-QOJQ\n",
                b"VERIFY GEZD-GNBV-GY3T-QOJQ\n",
                b"VERIFY GEZD-GNBV-GY3T-QOJQ\n",
                b"VERIFY GEZD-GNBV-GY3T-QOJQ\n",
                b"VERIFY GEZD-GNBV-GY3T-QOJQ\n",
                b"VERIFY GEZD-GNBV-GY3T-QOJQ\n",
            ]

            # M5: Every captured line matches expected wire format, no ESC byte reached verifier
            for line in captured:
                assert re.fullmatch(rb"VERIFY ([0-9]{6}|[A-Z2-7]{4}(-[A-Z2-7]{4}){3})\n", line)
            assert b"\x1b" not in b"".join(captured)
        finally:
            instance2.close()
            running[0] = False
            server.close()
            worker.join(timeout=2)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def test_N2_G9b_ctrl_c_is_forwarded_after_attach(verifier, start_gate, scratch_tmux):
    argv, control = scratch_tmux
    recorder = verifier.root / "signals.py"
    received = verifier.root / "signal-input"
    recorder.write_text("""
import os, sys, tty
mode, output, *command = sys.argv[1:]
if "attach-session" in command:
    tty.setraw(0)
    os.write(1, b"CHILD-READY")
    with open(output, "wb") as stream:
        stream.write(os.read(0, 1))
    raise SystemExit(0)
os.execv(command[0], command)
""")
    verifier.start()
    prefix = [sys.executable, "-IS", str(recorder), "run", str(received), *argv]
    instance = start_gate(tmux_prefix=prefix, force_isig_on_tcgetattr=True)
    instance.until(b"Code: ")
    instance.send(b"287082\n")
    instance.until(b"CHILD-READY")
    tty_fd = os.open(instance.tty_path, os.O_RDONLY | os.O_NOCTTY)
    try:
        assert not termios.tcgetattr(tty_fd)[3] & termios.ISIG
    finally:
        os.close(tty_fd)
    instance.send(b"\x03")
    assert instance.proc.wait(timeout=3) == 0
    assert received.read_bytes() == b"\x03"


def test_N2_G8_terminal_restore_uses_TCSANOW(verifier, start_gate):
    verifier.start()
    instance = start_gate(record_terminal_restore=True)
    instance.until(b"Code: ")
    instance.proc.terminate()
    assert instance.proc.wait(timeout=3) == 1
    restores = [int(value) for value in (verifier.root / "terminal-restores").read_text().splitlines()]
    assert restores
    assert set(restores) == {termios.TCSANOW}


def test_N2_G8_idle_terminal_restore_uses_TCSANOW(verifier, start_gate, scratch_tmux):
    argv, _control = scratch_tmux
    child = verifier.root / "idle-child.py"
    child.write_text("""
import os, sys, tty, time
if "attach-session" in sys.argv:
    tty.setraw(0)
    os.write(1, b"CHILD-READY")
    while True: time.sleep(1)
os.execv(sys.argv[1], sys.argv[1:])
""")
    verifier.start()
    instance = start_gate(tmux_prefix=[sys.executable, "-IS", str(child), *argv],
                          idle_seconds=0.2, record_terminal_restore=True)
    instance.until(b"Code: ")
    instance.send(b"287082\n")
    instance.until(b"CHILD-READY")
    instance.until(b"Code: ", timeout=5)
    instance.proc.terminate()
    assert instance.proc.wait(timeout=3) == 1
    restores = [int(value) for value in (verifier.root / "terminal-restores").read_text().splitlines()]
    assert restores
    assert set(restores) == {termios.TCSANOW}


def test_N2_G40_gate_uses_monotonic_clock_by_default():
    assert gate.run.__defaults__[-1] is time.monotonic


def test_N2_M6_outer_terminal_descriptor_is_nonblocking(verifier, start_gate, scratch_tmux):
    argv, control = scratch_tmux
    verifier.start()
    instance = start_gate(tmux_prefix=argv, record_outer_flags=True)
    instance.until(b"Code: ")
    instance.send(b"287082\n")
    wait_clients(control, 1)
    flags = int((verifier.root / "outer-flags").read_text())
    assert flags & os.O_NONBLOCK


def test_N5_C10_totpctl_rejects_non_root(verifier, monkeypatch, capsys):
    monkeypatch.setattr(totpctl.os, "geteuid", lambda: 501)
    assert totpctl.run(["status"], admin_sock=str(verifier.root / "missing.sock")) == 1
    assert capsys.readouterr().err == "totpctl: root privileges required\n"


def test_N3_D27_and_D18_wrong_peer_identity_is_rejected(verifier):
    verifier.start()
    before = verifier.state.read_bytes()
    verifier.finish()
    verifier.start_options = {
        "peer_cred_fn": lambda _sock: (os.getuid() + 1, verifier.pid),
    }
    verifier.start()
    client = verifier.connect()
    assert receive(client) == b""
    assert verifier.state.read_bytes() == before
