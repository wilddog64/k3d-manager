#!/Library/Developer/CommandLineTools/usr/bin/python3 -IS
import fcntl
import os
import pty
import re
import select
import signal
import stat
import socket
import struct
import subprocess
import sys
import termios
import time

DEFAULT_TOTP_CONF = "/etc/k3dm-web-console/totp.conf"
DEFAULT_TOTP_SOCK = "/var/db/k3dm-web-console-run/totp.sock"

RE_CPR = re.compile(rb"^\x1b\[[0-9]+;[0-9]+R$")
RE_DA = re.compile(rb"^\x1b\[[?>][0-9;]*c$")
RE_MODE = re.compile(rb"^\x1b\[\?[0-9;]*\$y$")
RE_FOCUS = re.compile(rb"^\x1b\[[IO]$")
RE_DSR = re.compile(rb"^\x1b\[[03]n$")
RE_WIN = re.compile(rb"^\x1b\[[48];[0-9]+;[0-9]+t$")

def is_terminal_reply(seq):
    if RE_CPR.match(seq):
        return True
    if RE_DA.match(seq):
        return True
    if RE_MODE.match(seq):
        return True
    if RE_FOCUS.match(seq):
        return True
    if RE_DSR.match(seq):
        return True
    if RE_WIN.match(seq):
        return True
    if seq.startswith(b"\x1b]") and (seq.endswith(b"\x07") or seq.endswith(b"\x1b\\")):
        return True
    if seq.startswith(b"\x1bP") and seq.endswith(b"\x1b\\"):
        return True
    return False

def can_be_terminal_reply_prefix(seq):
    if not seq.startswith(b"\x1b"):
        return False
    if len(seq) == 1:
        return True
    c1 = seq[1:2]
    if c1 == b"[":
        tail = seq[2:]
        return (not tail or re.fullmatch(rb"[?>][0-9;]*", tail) is not None
                or re.fullmatch(rb"\?[0-9;]*\$", tail) is not None
                or re.fullmatch(rb"[0-9]+(;[0-9]*)?", tail) is not None
                or re.fullmatch(rb"[48];[0-9]+;[0-9]*", tail) is not None)
    if c1 in (b"]", b"P"):
        return True
    return False

def parse_config(conf_path, expected_owner=0):
    try:
        st = os.lstat(conf_path)
    except Exception:
        return None
    if not stat.S_ISREG(st.st_mode):
        return None
    if st.st_uid != expected_owner or (expected_owner == 0 and st.st_gid != 0):
        return None
    if (st.st_mode & 0o022) != 0:
        return None
    conf = {}
    try:
        with open(conf_path, "r", encoding="utf-8") as f:
            for line in f:
                line = line.rstrip("\n")
                if line != line.strip() or "=" not in line:
                    return None
                k, v = line.split("=", 1)
                if k != "tmux" and not re.fullmatch("[0-9]+", v):
                    return None
                if k in conf:
                    return None
                conf[k] = v
    except Exception:
        return None
    allowed_keys = {"uid", "tmux", "idle_seconds", "console_port"}
    if set(conf.keys()) != allowed_keys:
        return None
    try:
        uid = int(conf["uid"])
        if uid < 0:
            return None
        idle_seconds = int(conf["idle_seconds"])
        if not (5 <= idle_seconds <= 600):
            return None
        console_port = int(conf["console_port"])
        if not (1024 <= console_port <= 49151):
            return None
        tmux = conf["tmux"]
        if not tmux.startswith("/") or not tmux:
            return None
    except Exception:
        return None
    return {
        "uid": uid,
        "tmux": tmux,
        "idle_seconds": idle_seconds,
        "console_port": console_port,
    }

def verify_totp(sock_path, code, expected_server_uid=0, connect_fn=None):
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    try:
        class ConnectTimeout(Exception):
            pass
        def handle_alarm(signum, frame):
            raise ConnectTimeout("connect deadline expired")
        old_handler = None
        try:
            old_handler = signal.signal(signal.SIGALRM, handle_alarm)
            signal.setitimer(signal.ITIMER_REAL, 3.0)
        except ValueError:
            pass
        try:
            if connect_fn is not None:
                connect_fn(s, sock_path)
            else:
                s.connect(sock_path)
        finally:
            if old_handler is not None:
                try:
                    signal.setitimer(signal.ITIMER_REAL, 0)
                    signal.signal(signal.SIGALRM, old_handler)
                except ValueError:
                    pass
        if sys.platform == "darwin":
            version, s_uid = struct.unpack("II", s.getsockopt(0, 1, 76)[:8])
            if version != 0:
                return "UNAVAILABLE"
        else:
            cred = s.getsockopt(socket.SOL_SOCKET, socket.SO_PEERCRED, 12)
            _pid, s_uid, _gid = struct.unpack("3i", cred)
        if s_uid != expected_server_uid:
            return "UNAVAILABLE"
        s.settimeout(5.0)
        s.sendall(f"VERIFY {code}\n".encode("ascii"))
        resp = bytearray()
        deadline = time.monotonic() + 5
        while len(resp) < 32:
            s.settimeout(max(0, deadline - time.monotonic()))
            chunk = s.recv(32 - len(resp))
            if not chunk:
                break
            resp.extend(chunk)
            if b"\n" in resp:
                if re.fullmatch(rb"(OK|NO|UNAVAILABLE|WAIT [0-9]+)\n", resp):
                    return resp[:-1].decode("ascii")
                break
        return "UNAVAILABLE"
    except Exception:
        return "UNAVAILABLE"
    finally:
        s.close()

def default_reap(pid):
    try:
        wpid, _status = os.waitpid(pid, os.WNOHANG)
        return wpid == pid
    except OSError:
        return True

def bounded_reap(pid, timeout=2.0, clock=time.monotonic):
    start = clock()
    while True:
        try:
            wpid, status = os.waitpid(pid, os.WNOHANG)
            if wpid == pid:
                if os.WIFEXITED(status):
                    return os.WEXITSTATUS(status)
                return 1
        except OSError:
            return 1
        if clock() - start >= timeout:
            return None
        time.sleep(0.05)

def write_with_timeout(fd, data, timeout=2.0, clock=time.monotonic):
    start = clock()
    offset = 0
    while offset < len(data):
        rem = timeout - (clock() - start)
        if rem <= 0:
            return False
        r, w, x = select.select([], [fd], [], min(0.5, rem))
        if w:
            try:
                n = os.write(fd, data[offset:])
                offset += n
            except (BlockingIOError, InterruptedError):
                continue
            except OSError:
                return False
    return True

def run(conf_path=DEFAULT_TOTP_CONF, sock_path=DEFAULT_TOTP_SOCK, tmux_prefix=None, expected_server_uid=0, expected_conf_owner=0, connect_fn=None, reap_fn=None, idle_seconds=None, prompt_timeout=60, event_hook=None, clock=time.monotonic):
    old_umask = os.umask(0o077)
    term_raised = [False]
    class EndConnection(BaseException):
        pass

    def handle_term(signum, frame):
        if not term_raised[0]:
            term_raised[0] = True
            raise EndConnection
    saved_signals = {}
    for sig, handler in (
        (signal.SIGINT, signal.SIG_IGN),
        (signal.SIGTSTP, signal.SIG_IGN),
        (signal.SIGQUIT, signal.SIG_IGN),
        (signal.SIGPIPE, signal.SIG_IGN),
        (signal.SIGHUP, handle_term),
        (signal.SIGTERM, handle_term),
    ):
        try:
            saved_signals[sig] = signal.signal(sig, handler)
        except ValueError:
            pass
    try:
        return _run_impl(
            conf_path=conf_path,
            sock_path=sock_path,
            tmux_prefix=tmux_prefix,
            expected_server_uid=expected_server_uid,
            expected_conf_owner=expected_conf_owner,
            connect_fn=connect_fn,
            reap_fn=reap_fn,
            idle_seconds=idle_seconds,
            prompt_timeout=prompt_timeout,
            event_hook=event_hook,
            clock=clock,
            term_raised=term_raised,
        )
    except (EndConnection, OSError, ValueError):
        return 1
    finally:
        os.umask(old_umask)
        for sig, handler in saved_signals.items():
            try:
                signal.signal(sig, handler)
            except ValueError:
                pass

def _run_impl(conf_path, sock_path, tmux_prefix, expected_server_uid, expected_conf_owner, connect_fn, reap_fn, idle_seconds, prompt_timeout, event_hook, clock, term_raised):
    def notify(ev):
        if event_hook is not None:
            try:
                event_hook(ev)
            except Exception:
                pass
    if not os.isatty(0):
        sys.stderr.write("console: an interactive terminal is required\n")
        return 1
    conf = parse_config(conf_path, expected_owner=expected_conf_owner)
    if conf is None:
        sys.stderr.write("console login unavailable\n")
        return 1
    if idle_seconds is None:
        idle_seconds = conf["idle_seconds"]
    tmux_bin = conf["tmux"]
    if tmux_prefix is not None:
        cmd_prefix = list(tmux_prefix)
    else:
        cmd_prefix = [tmux_bin]
    tmux_dir = os.path.dirname(tmux_bin)
    tmux_env = {"PATH": f"/usr/bin:/bin:/usr/sbin:/sbin:{tmux_dir}"}
    for var in ("HOME", "USER", "LOGNAME", "TERM", "LANG"):
        if var in os.environ:
            tmux_env[var] = os.environ[var]
    orig_attr = termios.tcgetattr(0)
    outer_fd = 0
    saved_flags = {fd: fcntl.fcntl(fd, fcntl.F_GETFL) for fd in (0, 1)}
    child_pid = None
    master_fd = None
    try:
        os.set_blocking(1, False)
        while True:
            if term_raised[0]:
                return 1
            notify("prompt")
            prompt_attr = termios.tcgetattr(outer_fd)
            prompt_attr[3] = prompt_attr[3] & ~(termios.ECHO | termios.ISIG | termios.ICANON)
            prompt_attr[6][termios.VMIN] = 1
            prompt_attr[6][termios.VTIME] = 0
            termios.tcsetattr(outer_fd, termios.TCSANOW, prompt_attr)
            failed_prompts = 0
            code_verified = False
            while failed_prompts < 10 and not code_verified:
                if term_raised[0]:
                    return 1
                clear_screen = b"\x1b[H\x1b[2J\x1b[3JCode: "
                if not write_with_timeout(1, clear_screen, timeout=2.0, clock=clock):
                    return 1
                line_buf = bytearray()
                overflow = False
                start_read = clock()
                while True:
                    if term_raised[0]:
                        return 1
                    rem = prompt_timeout - (clock() - start_read)
                    if rem <= 0:
                        return 1
                    r, _, _ = select.select([outer_fd], [], [], min(0.5, rem))
                    if not r:
                        continue
                    try:
                        b = os.read(outer_fd, 1)
                    except OSError:
                        return 1
                    if not b:
                        return 1
                    start_read = clock()
                    if b in (b"\x03", b"\x1a", b"\x1c", b"\x04"):
                        line_buf.clear()
                        overflow = False
                        if not write_with_timeout(1, b"\nCode: ", timeout=2.0, clock=clock):
                            return 1
                        continue
                    if b in (b"\r", b"\n"):
                        break
                    if b in (b"\x7f", b"\x08"):
                        if line_buf:
                            line_buf.pop()
                        continue
                    if len(line_buf) < 20:
                        line_buf.extend(b)
                    else:
                        overflow = True
                typed = line_buf.decode("ascii", errors="replace")
                code_str = typed.replace(" ", "").replace("-", "").upper()
                if overflow:
                    failed_prompts += 1
                    write_with_timeout(1, b"\nInvalid code\n", timeout=2.0, clock=clock)
                    time.sleep(2.0)
                    continue
                if len(code_str) == 6 and code_str.isdigit():
                    verify_code = code_str
                elif len(code_str) == 16 and re.fullmatch(r"[A-Z2-7]{16}", code_str):
                    verify_code = "-".join(code_str[i:i + 4] for i in range(0, 16, 4))
                else:
                    failed_prompts += 1
                    write_with_timeout(1, b"\nInvalid code\n", timeout=2.0, clock=clock)
                    time.sleep(2.0)
                    continue
                v_res = verify_totp(sock_path, verify_code, expected_server_uid=expected_server_uid, connect_fn=connect_fn)
                if v_res == "OK":
                    code_verified = True
                    break
                if v_res == "NO":
                    failed_prompts += 1
                    write_with_timeout(1, b"\nInvalid code\n", timeout=2.0, clock=clock)
                    time.sleep(2.0)
                    continue
                if v_res.startswith("WAIT"):
                    failed_prompts += 1
                    wait_match = re.fullmatch(r"WAIT ([0-9]+)", v_res)
                    seconds = wait_match.group(1) if wait_match else "?"
                    write_with_timeout(1, f"\nToo many attempts; try again later ({seconds} s)\n".encode(), timeout=2.0, clock=clock)
                    time.sleep(2.0)
                    continue
                sys.stderr.write("console login unavailable\n")
                return 1
            if not code_verified:
                return 1
            try:
                has_res = subprocess.run(cmd_prefix + ["has-session", "-t", "=work"], env=tmux_env, timeout=5.0, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                if has_res.returncode != 0:
                    new_res = subprocess.run(cmd_prefix + ["new-session", "-d", "-s", "work"], env=tmux_env, timeout=5.0, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
                    if new_res.returncode != 0:
                        if b"duplicate session: work" in new_res.stderr:
                            has_again = subprocess.run(cmd_prefix + ["has-session", "-t", "=work"], env=tmux_env, timeout=5.0, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                            if has_again.returncode != 0:
                                return 1
                        else:
                            return 1
            except Exception:
                return 1
            raw_attr = termios.tcgetattr(outer_fd)
            raw_attr[0] = raw_attr[0] & ~(termios.BRKINT | termios.ICRNL | termios.INPCK | termios.ISTRIP | termios.IXON)
            raw_attr[1] = raw_attr[1] & ~termios.OPOST
            raw_attr[2] = raw_attr[2] & ~(termios.CSIZE | termios.PARENB)
            raw_attr[2] = raw_attr[2] | termios.CS8
            raw_attr[3] = raw_attr[3] & ~(termios.ECHO | termios.ICANON | termios.IEXTEN | termios.ISIG)
            raw_attr[6][termios.VMIN] = 1
            raw_attr[6][termios.VTIME] = 0
            termios.tcsetattr(outer_fd, termios.TCSANOW, raw_attr)
            child_pid, master_fd = pty.fork()
            if child_pid == 0:
                try:
                    os.execvpe(cmd_prefix[0], cmd_prefix + ["attach-session", "-E", "-t", "=work"], tmux_env)
                finally:
                    os._exit(1)
            notify("attached")
            fcntl.fcntl(outer_fd, fcntl.F_SETFL, os.O_NONBLOCK)
            fcntl.fcntl(master_fd, fcntl.F_SETFL, os.O_NONBLOCK)
            def update_winsize():
                try:
                    ws = fcntl.ioctl(outer_fd, termios.TIOCGWINSZ, b"\x00" * 8)
                    fcntl.ioctl(master_fd, termios.TIOCSWINSZ, ws)
                except Exception:
                    pass
            update_winsize()
            def handle_winch(signum, frame):
                update_winsize()
            signal.signal(signal.SIGWINCH, handle_winch)
            buf_outer_to_child = bytearray()
            buf_child_to_outer = bytearray()
            last_activity = clock()
            esc_buf = bytearray()
            esc_start = None
            idle_triggered = False
            child_exit_code = None
            while True:
                if term_raised[0]:
                    return 1
                reap_check = bounded_reap(child_pid, timeout=0.0, clock=clock)
                if reap_check is not None:
                    child_exit_code = reap_check
                    break
                now_t = clock()
                to_idle = max(0.0, idle_seconds - (now_t - last_activity))
                if to_idle <= 0:
                    idle_triggered = True
                    break
                select_timeout = min(1.0, to_idle)
                if esc_buf:
                    to_esc = max(0.0, 0.1 - (now_t - esc_start))
                    select_timeout = min(select_timeout, to_esc)
                    if to_esc <= 0 or len(esc_buf) > 64 or not can_be_terminal_reply_prefix(esc_buf):
                        buf_outer_to_child.extend(esc_buf)
                        last_activity = clock()
                        esc_buf.clear()
                        esc_start = None
                rlist = []
                wlist = []
                if len(buf_outer_to_child) + len(esc_buf) < 65536:
                    rlist.append(outer_fd)
                if len(buf_child_to_outer) < 65536:
                    rlist.append(master_fd)
                if buf_outer_to_child:
                    wlist.append(master_fd)
                if buf_child_to_outer:
                    wlist.append(1)
                r_ready, w_ready, _ = select.select(rlist, wlist, [], select_timeout)
                if outer_fd in r_ready:
                    try:
                        chunk = os.read(outer_fd, min(4096, 65536 - len(buf_outer_to_child) - len(esc_buf)))
                        if not chunk:
                            return 1
                        for byte in chunk:
                            b = bytes([byte])
                            if esc_buf:
                                esc_buf.extend(b)
                                if is_terminal_reply(esc_buf):
                                    buf_outer_to_child.extend(esc_buf)
                                    esc_buf.clear()
                                    esc_start = None
                                elif not can_be_terminal_reply_prefix(esc_buf) or len(esc_buf) > 64 or (clock() - esc_start > 0.1):
                                    buf_outer_to_child.extend(esc_buf)
                                    last_activity = clock()
                                    esc_buf.clear()
                                    esc_start = None
                            else:
                                if b == b"\x1b":
                                    esc_buf.extend(b)
                                    esc_start = clock()
                                else:
                                    buf_outer_to_child.extend(b)
                                    last_activity = clock()
                    except (BlockingIOError, InterruptedError):
                        pass
                    except OSError:
                        return 1
                if master_fd in r_ready:
                    try:
                        chunk = os.read(master_fd, min(4096, 65536 - len(buf_child_to_outer)))
                        if not chunk:
                            reap_check = bounded_reap(child_pid, timeout=0.5, clock=clock)
                            child_exit_code = reap_check if reap_check is not None else 1
                            break
                        buf_child_to_outer.extend(chunk)
                    except (BlockingIOError, InterruptedError):
                        pass
                    except OSError:
                        reap_check = bounded_reap(child_pid, timeout=0.5, clock=clock)
                        child_exit_code = reap_check if reap_check is not None else 1
                        break
                if master_fd in w_ready and buf_outer_to_child:
                    try:
                        n = os.write(master_fd, buf_outer_to_child)
                        buf_outer_to_child = buf_outer_to_child[n:]
                    except (BlockingIOError, InterruptedError):
                        pass
                    except OSError:
                        return 1
                if 1 in w_ready and buf_child_to_outer:
                    try:
                        n = os.write(1, buf_child_to_outer)
                        buf_child_to_outer = buf_child_to_outer[n:]
                    except (BlockingIOError, InterruptedError):
                        pass
                    except OSError:
                        return 1
            if not idle_triggered:
                child_pid = None
                return 0 if child_exit_code == 0 else 1
            notify("idle-end")
            try:
                os.kill(child_pid, signal.SIGTERM)
            except OSError:
                pass
            dead = False
            start_term = clock()
            while clock() - start_term < 2.0:
                if (reap_fn or default_reap)(child_pid):
                    dead = True
                    break
                time.sleep(0.05)
            if not dead:
                try:
                    os.kill(child_pid, signal.SIGKILL)
                except OSError:
                    pass
                start_kill = clock()
                while clock() - start_kill < 2.0:
                    if (reap_fn or default_reap)(child_pid):
                        dead = True
                        break
                    time.sleep(0.05)
            if not dead:
                os.close(master_fd)
                os._exit(1)
            notify("reaped")
            try:
                os.close(master_fd)
            except Exception:
                pass
            master_fd = None
            child_pid = None
            buf_outer_to_child.clear()
            buf_child_to_outer.clear()
            esc_buf.clear()
            try:
                termios.tcflush(outer_fd, termios.TCIFLUSH)
            except Exception:
                pass
            termios.tcsetattr(outer_fd, termios.TCSANOW, orig_attr)
    finally:
        term_raised[0] = True
        notify("cleanup")
        for fd, flags in saved_flags.items():
            try:
                fcntl.fcntl(fd, fcntl.F_SETFL, flags)
            except OSError:
                pass
        try:
            termios.tcsetattr(outer_fd, termios.TCSANOW, orig_attr)
        except Exception:
            pass
        if child_pid is not None:
            try:
                os.kill(child_pid, signal.SIGTERM)
            except OSError:
                pass
            start_term = clock()
            dead = False
            while clock() - start_term < 2.0:
                if (reap_fn or default_reap)(child_pid):
                    dead = True
                    break
                time.sleep(0.05)
            if not dead:
                try:
                    os.kill(child_pid, signal.SIGKILL)
                except OSError:
                    pass
                start_kill = clock()
                while clock() - start_kill < 2.0:
                    if (reap_fn or default_reap)(child_pid):
                        dead = True
                        break
                    time.sleep(0.05)
            if not dead:
                if master_fd is not None:
                    try:
                        os.close(master_fd)
                    except Exception:
                        pass
                os._exit(1)
        if master_fd is not None:
            try:
                os.close(master_fd)
            except Exception:
                pass

def main():
    rc = run()
    sys.exit(rc)

if __name__ == "__main__":
    main()
