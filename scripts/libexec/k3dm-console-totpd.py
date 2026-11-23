#!/Library/Developer/CommandLineTools/usr/bin/python3 -IS
import base64
import concurrent.futures
import math
import re
import threading
import hashlib
import hmac
import json
import os
import selectors
import stat
import socket
import struct
import subprocess
import sys
import time

PYAPP = "/Library/Developer/CommandLineTools/Library/Frameworks/Python3.framework/Versions/3.9/Resources/Python.app/Contents/MacOS/Python"
DEFAULT_GATE_PATH = "/Library/PrivilegedHelperTools/k3dm-web-console/forced-command"
DEFAULT_PART_A_LABEL = "com.k3d-manager.web-console-sshd"
DEFAULT_TOTP_CONF = "/etc/k3dm-web-console/totp.conf"
DEFAULT_STATE_DIR = "/var/db/k3dm-web-console"
DEFAULT_RUN_DIR = "/var/db/k3dm-web-console-run"
DEFAULT_LOG = "/var/log/k3dm-web-console-totp.log"

class CommitPreRenameError(Exception):
    pass

class CommitPostRenameError(Exception):
    pass

def default_runner(cmd, timeout=1.0):
    res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=timeout, check=True)
    return res.stdout.decode("utf-8", errors="replace")

def default_peer_cred(sock):
    if sys.platform == "darwin":
        cred = sock.getsockopt(0, 1, 76)
        version, uid = struct.unpack("II", cred[:8])
        if version != 0:
            raise OSError("unknown peer credential version")
        return uid, sock.getsockopt(0, 2)
    cred = sock.getsockopt(socket.SOL_SOCKET, socket.SO_PEERCRED, 12)
    pid, uid, _gid = struct.unpack("3i", cred)
    return uid, pid


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

def commit_state(state_dir, new_state, fault=None):
    fault = _fault_for_file(fault, "state.json")
    tmp_path = os.path.join(state_dir, "state.json.tmp")
    final_path = os.path.join(state_dir, "state.json")
    try:
        if fault == "pre-rename-open":
            raise OSError("injected fault before open")
        flags = os.O_CREAT | os.O_EXCL | os.O_WRONLY | getattr(os, "O_NOFOLLOW", 0)
        fd = os.open(tmp_path, flags, 0o600)
        try:
            if fault == "pre-rename-write":
                raise OSError("injected fault on write")
            payload = json.dumps(new_state).encode("utf-8")
            with os.fdopen(fd, "wb", closefd=False) as stream:
                stream.write(payload)
                stream.flush()
            if fault == "pre-rename-fsync":
                raise OSError("injected fault on fsync")
            os.fsync(fd)
        finally:
            os.close(fd)
        if fault == "pre-rename-replace":
            raise OSError("injected fault on rename")
        os.replace(tmp_path, final_path)
    except Exception:
        try:
            if os.path.exists(tmp_path):
                os.unlink(tmp_path)
        except Exception:
            pass
        raise CommitPreRenameError("commit failed before rename")
    try:
        if fault == "post-rename-dir-fsync":
            raise OSError("injected fault on dir fsync")
        dir_fd = os.open(state_dir, os.O_RDONLY)
        try:
            os.fsync(dir_fd)
        finally:
            os.close(dir_fd)
    except Exception:
        raise CommitPostRenameError("commit fsync failed after rename")

def _fault_for_file(fault, filename):
    if isinstance(fault, dict):
        return fault.get(filename)
    return fault if filename == "state.json" else None

def commit_recovery(state_dir, entries, fault=None):
    tmp_path = os.path.join(state_dir, "recovery.json.tmp")
    final_path = os.path.join(state_dir, "recovery.json")
    fault = _fault_for_file(fault, "recovery.json")
    try:
        if fault == "pre-rename-open":
            raise OSError("injected fault before open")
        fd = os.open(tmp_path, os.O_CREAT | os.O_EXCL | os.O_WRONLY | getattr(os, "O_NOFOLLOW", 0), 0o600)
        try:
            os.fchmod(fd, 0o600)
            if fault == "pre-rename-write":
                raise OSError("injected fault on write")
            payload = json.dumps({"v": 1, "codes": entries}).encode("utf-8")
            with os.fdopen(fd, "wb", closefd=False) as stream:
                stream.write(payload)
                stream.flush()
            if fault == "pre-rename-fsync":
                raise OSError("injected fault on fsync")
            os.fsync(fd)
        finally:
            os.close(fd)
        if fault == "pre-rename-replace":
            raise OSError("injected fault on rename")
        os.replace(tmp_path, final_path)
    except Exception as exc:
        try:
            if os.path.lexists(tmp_path):
                os.unlink(tmp_path)
        except Exception:
            pass
        raise CommitPreRenameError("recovery commit failed before rename") from exc
    try:
        if fault == "post-rename-dir-fsync":
            raise OSError("injected fault on dir fsync")
        dir_fd = os.open(state_dir, os.O_RDONLY)
        try:
            os.fsync(dir_fd)
        finally:
            os.close(dir_fd)
    except Exception as exc:
        raise CommitPostRenameError("recovery commit fsync failed after rename") from exc

def load_recovery(state_dir, expected_owner=0, log_event=None):
    path = os.path.join(state_dir, "recovery.json")
    try:
        os.lstat(path)
    except FileNotFoundError:
        return []
    except OSError:
        if log_event:
            log_event("totp-recovery-damaged")
        return []
    try:
        fd = os.open(path, os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0))
        try:
            st = os.fstat(fd)
            if not stat.S_ISREG(st.st_mode) or st.st_uid != expected_owner or stat.S_IMODE(st.st_mode) != 0o600:
                raise ValueError("invalid recovery file metadata")
            with os.fdopen(fd, "r", encoding="utf-8", closefd=False) as stream:
                data = json.load(stream)
        finally:
            os.close(fd)
        if (not isinstance(data, dict) or set(data) != {"v", "codes"}
                or type(data.get("v")) is not int or data["v"] != 1):
            raise ValueError("invalid recovery file version")
        entries = data.get("codes")
        if not isinstance(entries, list) or len(entries) > 10:
            raise ValueError("invalid recovery entries")
        for item in entries:
            if not isinstance(item, dict) or set(item) != {"s", "h"}:
                raise ValueError("invalid recovery entry")
            if not re.fullmatch(r"[0-9a-f]{32}", item["s"]) or not re.fullmatch(r"[0-9a-f]{64}", item["h"]):
                raise ValueError("invalid recovery entry")
        return entries
    except Exception:
        if log_event:
            log_event("totp-recovery-damaged")
        return []

def recovery_hash(salt_hex, code):
    return hashlib.sha256(bytes.fromhex(salt_hex) + code.encode("ascii")).hexdigest()

def make_recovery_codes():
    codes = []
    seen = set()
    entries = []
    while len(codes) < 10:
        code = base64.b32encode(os.urandom(10)).decode("ascii")
        if code in seen:
            continue
        seen.add(code)
        codes.append(code)
        salt = os.urandom(16).hex()
        entries.append({"s": salt, "h": recovery_hash(salt, code)})
    return codes, entries

def grouped_recovery(code):
    return "-".join(code[i:i + 4] for i in range(0, 16, 4))

def load_state(state_dir):
    final_path = os.path.join(state_dir, "state.json")
    if not os.path.exists(final_path):
        return None
    try:
        with open(final_path, "r", encoding="utf-8") as f:
            data = json.load(f)
        if not isinstance(data, dict):
            return False
        required = {"secret", "last_counter", "failures", "locked_until", "enrolled"}
        if set(data) not in (required, required | {"lock_level"}) or type(data["enrolled"]) is not bool:
            return False
        for field in ("failures", "last_counter", "locked_until"):
            if type(data[field]) is not int or data[field] < 0:
                return False
        if not re.fullmatch(r"[A-Z2-7]{32}", data["secret"]):
            return False
        if "lock_level" in data:
            if type(data["lock_level"]) is not int or not 0 <= data["lock_level"] <= 4:
                return False
        else:
            data["lock_level"] = 1 if data["locked_until"] > 0 else 0
        return data
    except Exception:
        return False

def compute_hotp(secret_bytes, counter, hmac_fn=None):
    msg = struct.pack(">Q", counter)
    if hmac_fn is not None:
        digest = hmac_fn(secret_bytes, msg)
    else:
        digest = hmac.new(secret_bytes, msg, hashlib.sha1).digest()
    offset = digest[-1] & 0x0F
    code_int = struct.unpack(">I", digest[offset:offset + 4])[0] & 0x7FFFFFFF
    code = code_int % 1000000
    return f"{code:06d}"

def verify_code(secret_b32, code_str, current_counter, last_counter, hmac_fn=None):
    try:
        secret_bytes = base64.b32decode(secret_b32, casefold=True)
    except Exception:
        return False, None
    candidates = [current_counter - 1, current_counter, current_counter + 1]
    matched = None
    for c in candidates:
        cand_code = compute_hotp(secret_bytes, max(0, c), hmac_fn=hmac_fn)
        if hmac.compare_digest(cand_code, code_str):
            if c > last_counter:
                matched = c
    if matched is not None:
        return True, matched
    return False, None

def parse_netstat_listeners(netstat_text, port):
    pids = []
    for line in netstat_text.splitlines():
        fields = line.split()
        if len(fields) < 6 or fields[3] != f"127.0.0.1.{port}" or fields[5] != "LISTEN":
            continue
        owners = [f.rsplit(":", 1)[1] for f in fields[6:] if re.fullmatch(r"[^:]*:[0-9]+", f)]
        if len(owners) != 1:
            return []
        pids.append(int(owners[0]))
    return pids


def parse_ps_table(ps_text):
    table = {}
    for line in ps_text.splitlines():
        line = line.strip()
        if not line:
            continue
        parts = line.split(None, 3)
        if len(parts) != 4:
            continue
        try:
            pid = int(parts[0])
            ppid = int(parts[1])
            uid = int(parts[2])
            args = parts[3]
            if pid in table:
                return {}
            table[pid] = {
                "ppid": ppid,
                "uid": uid,
                "args": args,
            }
        except ValueError:
            continue
    return table

def admit(sock, conf, runner, job_label=DEFAULT_PART_A_LABEL, gate_path=DEFAULT_GATE_PATH, pyapp_path=PYAPP, peer_cred_fn=None, clock_fn=time.monotonic, listener_cache=None):
    start_t = clock_fn()
    cred_fn = peer_cred_fn if peer_cred_fn is not None else default_peer_cred
    try:
        peer_uid, peer_pid = cred_fn(sock)
    except Exception:
        return False
    if peer_uid != conf["uid"]:
        return False
    def bounded_runner(args):
        budget = 2 - (clock_fn() - start_t)
        if budget <= 0:
            raise TimeoutError
        return runner(args, timeout=min(1.0, budget))

    def listener():
        rows = parse_netstat_listeners(bounded_runner(["/usr/sbin/netstat", "-anv", "-p", "tcp"]), conf["console_port"])
        if len(rows) != 1:
            return None
        pid = rows[0]
        if bounded_runner(["/bin/ps", "-o", "uid=", "-p", str(pid)]).strip() != "0":
            return None
        job = bounded_runner(["/bin/launchctl", "print", f"system/{job_label}"])
        return pid if re.findall(r"(?m)^\s*pid = ([0-9]+)\s*$", job) == [str(pid)] else None

    try:
        if listener_cache is None:
            listener_pid = listener()
        else:
            lock = listener_cache["lock"]
            if not lock.acquire(timeout=max(0, 2 - (clock_fn() - start_t))):
                return False
            try:
                if listener_cache["valid"] is None or clock_fn() - listener_cache["time"] >= 1:
                    try:
                        listener_cache["pid"] = listener()
                    except (OSError, subprocess.SubprocessError, TimeoutError):
                        listener_cache["pid"] = None
                    listener_cache.update(valid=True, time=clock_fn())
                listener_pid = listener_cache["pid"]
            finally:
                lock.release()
        if listener_pid is None:
            return False
    except Exception:
        return False
    try:
        lstart1 = bounded_runner(["/bin/ps", "-o", "lstart=", "-p", str(peer_pid)]).strip()
    except Exception:
        return False
    try:
        comm = bounded_runner(["/bin/ps", "-ww", "-o", "comm=", "-p", str(peer_pid)]).strip()
        ps_out = bounded_runner(["/bin/ps", "-ww", "-axo", "pid=,ppid=,uid=,args="])
    except Exception:
        return False
    table = parse_ps_table(ps_out)
    peer_info = table.get(peer_pid)
    if not peer_info:
        return False
    if comm != pyapp_path or peer_info["uid"] != peer_uid:
        return False
    expected_args = f"{pyapp_path} -IS {gate_path}"
    if peer_info["args"] != expected_args:
        return False
    parent_pid = peer_info["ppid"]
    parent_info = table.get(parent_pid)
    if not parent_info:
        return False
    if parent_info["uid"] != conf["uid"]:
        return False
    if not parent_info["args"].startswith("sshd-session: "):
        return False
    if parent_info["args"].endswith(" [priv]"):
        return False
    grandparent_pid = parent_info["ppid"]
    grandparent_info = table.get(grandparent_pid)
    if not grandparent_info:
        return False
    if grandparent_info["uid"] != 0:
        return False
    if not grandparent_info["args"].startswith("sshd-session: "):
        return False
    if not grandparent_info["args"].endswith(" [priv]"):
        return False
    great_grandparent_pid = grandparent_info["ppid"]
    if great_grandparent_pid != listener_pid:
        return False
    try:
        lstart2 = bounded_runner(["/bin/ps", "-o", "lstart=", "-p", str(peer_pid)]).strip()
    except Exception:
        return False
    if not lstart1 or lstart1 != lstart2:
        return False
    if clock_fn() - start_t > 2.0:
        return False
    return True

def run(conf_path=DEFAULT_TOTP_CONF, state_dir=DEFAULT_STATE_DIR, run_dir=DEFAULT_RUN_DIR, log_path=DEFAULT_LOG, runner=None, clock=time.time, expected_conf_owner=0, expected_dir_owner=0, expected_job_label=DEFAULT_PART_A_LABEL, expected_gate_path=DEFAULT_GATE_PATH, expected_interpreter=PYAPP, peer_cred_fn=None, event_hook=None, max_iterations=None, exit_on_idle=False, hmac_fn=None, monotonic=time.monotonic, stop_event=None):
    if runner is None:
        runner = default_runner
    if peer_cred_fn is None:
        peer_cred_fn = default_peer_cred
    def notify(ev):
        if event_hook is not None:
            try:
                event_hook(ev)
            except Exception:
                pass
    def log_event(name):
        try:
            with open(log_path, "a", encoding="utf-8") as f:
                f.write(name + "\n")
        except Exception:
            pass
    def wall_time():
        try:
            value = clock()
            if math.isfinite(value) and value >= 0:
                return value
        except (OSError, TypeError, ValueError, OverflowError):
            pass
        log_event("clock-unavailable")
        return None

    lock_seconds = [300, 1800, 14400, 86400]
    lock_deadline_mono = [None]
    deadline_locked_until = [None]
    active_lock_logged = [False]

    def state_for_commit(state):
        result = dict(state)
        level = result.pop("lock_level", 0)
        if level:
            result["lock_level"] = level
        return result

    def structured(event, **fields):
        try:
            timestamp = wall_time()
            if timestamp is None:
                stamp = "unknown"
            else:
                stamp = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(timestamp))
            log_event(" ".join([stamp, f"event={event}"] + [f"{key}={value}" for key, value in fields.items()]))
        except Exception:
            pass

    def sync_lock_deadline(state, now):
        level = state.get("lock_level", 0)
        locked_until = state.get("locked_until", 0)
        if locked_until <= 0:
            lock_deadline_mono[0] = None
            deadline_locked_until[0] = locked_until
            return
        if lock_deadline_mono[0] is None or deadline_locked_until[0] != locked_until:
            duration = lock_seconds[max(0, min(level, 4) - 1)] if level else 300
            remaining = max(0, min(locked_until - now, duration))
            lock_deadline_mono[0] = monotonic() + remaining
            deadline_locked_until[0] = locked_until

    def decay_state(state, now):
        level = state.get("lock_level", 0)
        until = state.get("locked_until", 0)
        if lock_deadline_mono[0] is not None and monotonic() < lock_deadline_mono[0]:
            return state, False
        if level <= 0 or until <= 0 or now < until:
            return state, False
        elapsed_levels = int((now - until) // 86400)
        if elapsed_levels <= 0:
            return state, False
        new_level = max(0, level - elapsed_levels)
        result = dict(state, lock_level=new_level, failures=0)
        if new_level == 0:
            result["locked_until"] = 0
            lock_deadline_mono[0] = None
        return result, new_level != level or (new_level == 0 and until != 0)

    if os.path.islink(run_dir):
        return 1
    try:
        st_run = os.stat(run_dir)
        if not os.path.isdir(run_dir):
            return 1
        if st_run.st_uid != expected_dir_owner:
            return 1
        if (st_run.st_mode & 0o777) != 0o755:
            return 1
        if sys.platform == "darwin":
            ls_out = runner(["/bin/ls", "-lde", run_dir], timeout=1.0)
            mode = ls_out.split()[0]
            if not mode.startswith("drwxr-xr-x") or "+" in mode:
                return 1
    except Exception:
        return 1
    if os.path.islink(state_dir):
        return 1
    try:
        st_state = os.stat(state_dir)
        if not os.path.isdir(state_dir):
            return 1
        if st_state.st_uid != expected_dir_owner:
            return 1
        if (st_state.st_mode & 0o777) != 0o700:
            return 1
    except Exception:
        return 1
    for leftover_tmp in (os.path.join(state_dir, "state.json.tmp"),
                         os.path.join(state_dir, "recovery.json.tmp")):
        if os.path.lexists(leftover_tmp):
            try:
                os.unlink(leftover_tmp)
            except OSError:
                return 1
    totp_sock_path = os.path.join(run_dir, "totp.sock")
    admin_sock_path = os.path.join(run_dir, "admin.sock")
    for p in (totp_sock_path, admin_sock_path):
        try:
            if os.path.exists(p) or os.path.islink(p):
                os.unlink(p)
        except Exception:
            pass
    totp_sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    totp_sock.setblocking(False)
    totp_sock.bind(totp_sock_path)
    os.chmod(totp_sock_path, 0o666)
    totp_sock.listen(16)
    admin_sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    admin_sock.setblocking(False)
    admin_sock.bind(admin_sock_path)
    os.chmod(admin_sock_path, 0o600)
    admin_sock.listen(16)
    sel = selectors.DefaultSelector()
    sel.register(totp_sock, selectors.EVENT_READ, data={"type": "totp_listener"})
    sel.register(admin_sock, selectors.EVENT_READ, data={"type": "admin_listener"})
    executor = concurrent.futures.ThreadPoolExecutor(max_workers=4)
    pending_checks = 0
    admitted_clients = {}
    admin_clients = {}
    pending_futures = {}
    listener_cache = {"lock": threading.Lock(), "time": 0, "valid": None, "pid": None}
    pending_operation = None
    pending_admin_secret = None
    pending_admin_expiry = 0
    pending_admin_wrong = 0
    pending_recovery_codes = None
    pending_recovery_entries = None
    pending_original_recovery = None
    recovery_failure_count = 0
    recovery_failure_logged = None
    startup_state = load_state(state_dir)
    startup_recovery = load_recovery(state_dir, expected_owner=expected_dir_owner, log_event=log_event)
    active_recovery_entries = list(startup_recovery)
    startup_time = wall_time()
    if startup_state and startup_time is not None:
        sync_lock_deadline(startup_state, startup_time)
        decayed, changed = decay_state(startup_state, startup_time)
        if changed:
            try:
                commit_state(state_dir, state_for_commit(decayed), fault=getattr(run, "injected_commit_fault", None))
                if decayed.get("lock_level", 0) == 0:
                    structured("totp-unlock", source="decay")
            except (CommitPreRenameError, CommitPostRenameError):
                log_event("commit-failed")
    notify("ready")
    iteration = 0
    post_rename_fatal = False
    try:
        while True:
            if stop_event is not None and stop_event.is_set():
                break
            if max_iterations is not None and iteration >= max_iterations:
                break
            iteration += 1
            now = monotonic()
            conf = parse_config(conf_path, expected_owner=expected_conf_owner)
            to_remove = []
            for s, meta in admitted_clients.items():
                if now - meta["time"] > 5.0:
                    to_remove.append(s)
            for s in to_remove:
                try:
                    sel.unregister(s)
                except Exception:
                    pass
                try:
                    s.close()
                except Exception:
                    pass
                admitted_clients.pop(s, None)
                notify("closed deadline")
            to_remove_admin = []
            for s, meta in admin_clients.items():
                if now - meta["time"] > 5.0:
                    to_remove_admin.append(s)
            for s in to_remove_admin:
                try:
                    sel.unregister(s)
                except Exception:
                    pass
                try:
                    s.close()
                except Exception:
                    pass
                admin_clients.pop(s, None)
            done_futures = [f for f in list(pending_futures.keys()) if f.done()]
            for f in done_futures:
                client_sock = pending_futures.pop(f)
                pending_checks -= 1
                notify("check-finished")
                try:
                    admit_res = f.result()
                except Exception:
                    admit_res = False
                if not admit_res:
                    try:
                        client_sock.close()
                    except Exception:
                        pass
                    notify("closed rejected")
                else:
                    if len(admitted_clients) >= 4:
                        try:
                            client_sock.close()
                        except Exception:
                            pass
                        notify("closed admitted-full")
                    else:
                        admitted_clients[client_sock] = {"time": monotonic(), "buf": bytearray()}
                        client_sock.setblocking(False)
                        sel.register(client_sock, selectors.EVENT_READ, data={"type": "totp_client"})
                        notify("admitted")
            events = sel.select(timeout=0.05)
            if exit_on_idle and not events and pending_checks == 0 and not admitted_clients and not admin_clients:
                break
            for key, mask in events:
                data = key.data
                ktype = data["type"]
                if ktype == "totp_listener":
                    try:
                        conn, _ = totp_sock.accept()
                    except OSError:
                        continue
                    notify("accepted")
                    if conf is None:
                        try:
                            conn.close()
                        except Exception:
                            pass
                        notify("closed bad-config")
                        continue
                    try:
                        puid, _ppid = peer_cred_fn(conn)
                    except Exception:
                        puid = -1
                    if puid != conf["uid"]:
                        try:
                            conn.close()
                        except Exception:
                            pass
                        notify("closed wrong-uid")
                        continue
                    if pending_checks >= 4:
                        try:
                            conn.close()
                        except Exception:
                            pass
                        notify("closed pending-full")
                        continue
                    pending_checks += 1
                    notify("check-started")
                    fut = executor.submit(admit, conn, conf, runner, expected_job_label, expected_gate_path, expected_interpreter, peer_cred_fn, monotonic, listener_cache)
                    pending_futures[fut] = conn
                elif ktype == "admin_listener":
                    try:
                        conn, _ = admin_sock.accept()
                    except OSError:
                        continue
                    try:
                        puid, _ppid = peer_cred_fn(conn)
                    except Exception:
                        puid = -1
                    if puid != 0:
                        try:
                            conn.close()
                        except Exception:
                            pass
                        continue
                    conn.setblocking(False)
                    admin_clients[conn] = {"time": monotonic(), "buf": bytearray()}
                    sel.register(conn, selectors.EVENT_READ, data={"type": "admin_client"})
                elif ktype == "admin_client":
                    csock = key.fileobj
                    cmeta = admin_clients.get(csock)
                    if not cmeta:
                        continue
                    try:
                        chunk = csock.recv(64)
                    except Exception:
                        chunk = b""
                    if not chunk:
                        sel.unregister(csock)
                        csock.close()
                        admin_clients.pop(csock, None)
                        continue
                    cmeta["buf"].extend(chunk)
                    if len(cmeta["buf"]) > 32:
                        sel.unregister(csock)
                        csock.close()
                        admin_clients.pop(csock, None)
                        continue
                    if b"\n" in cmeta["buf"]:
                        line_bytes, _ = cmeta["buf"].split(b"\n", 1)
                        line = line_bytes.decode("ascii", errors="replace")
                        reply = None
                        cur_state = load_state(state_dir)
                        timestamp = wall_time()
                        if pending_admin_secret is not None and timestamp is not None and timestamp >= pending_admin_expiry:
                            pending_admin_secret = None
                            pending_recovery_codes = None
                            pending_recovery_entries = None
                            pending_original_recovery = None
                            pending_admin_wrong = 0
                        if conf is None or cur_state is False or timestamp is None:
                            reply = "UNAVAILABLE\n"
                        elif line == "STATUS":
                            if cur_state is None:
                                reply = "NOT_ENROLLED\n"
                            else:
                                reply = "ENROLLED\n"
                        elif line == "RECOVERY_STATUS":
                            if cur_state is None:
                                reply = "NOT_ENROLLED\n"
                            else:
                                entries = load_recovery(state_dir, expected_owner=expected_dir_owner, log_event=log_event)
                                active_recovery_entries = list(entries)
                                reply = f"RECOVERY {len(entries)}\n"
                        elif line == "RECOVERY_BEGIN":
                            if cur_state is None:
                                reply = "NOT_ENROLLED\n"
                            elif pending_admin_secret is not None and timestamp < pending_admin_expiry:
                                reply = "REFUSED\n"
                            else:
                                pending_recovery_codes, pending_recovery_entries = make_recovery_codes()
                                pending_original_recovery = list(active_recovery_entries)
                                pending_operation = "RECOVERY"
                                pending_admin_secret = cur_state["secret"]
                                pending_admin_expiry = timestamp + 600
                                pending_admin_wrong = 0
                                reply = "RECOVERY_PENDING\n"
                        elif re.fullmatch(r"RECOVERY_GET [0-9]", line):
                            index = int(line[-1])
                            if (pending_admin_secret is not None and pending_operation in ("ENROLL", "ROTATE", "RECOVERY")
                                    and timestamp < pending_admin_expiry and pending_recovery_codes is not None):
                                reply = f"CODE {grouped_recovery(pending_recovery_codes[index])}\n"
                            else:
                                reply = "UNAVAILABLE\n"
                        elif line.startswith("RECOVERY_GET"):
                            reply = "UNAVAILABLE\n"
                        elif line.startswith("RECOVERY_COMMIT "):
                            code = line.split(" ", 1)[1].strip()
                            if (pending_operation != "RECOVERY" or pending_admin_secret is None
                                    or timestamp >= pending_admin_expiry or not cur_state or not cur_state.get("enrolled")):
                                reply = "UNAVAILABLE\n"
                            else:
                                ok, _matched_counter = verify_code(cur_state["secret"], code, int(timestamp // 30),
                                                                   cur_state.get("last_counter", 0), hmac_fn=hmac_fn)
                                if not ok:
                                    pending_admin_wrong += 1
                                    if pending_admin_wrong >= 5:
                                        pending_admin_secret = None
                                        pending_recovery_codes = None
                                        pending_recovery_entries = None
                                        pending_original_recovery = None
                                    reply = "NO\n"
                                else:
                                    try:
                                        new_entries = list(pending_recovery_entries)
                                        commit_recovery(state_dir, pending_recovery_entries,
                                                        fault=getattr(run, "injected_commit_fault", None))
                                        active_recovery_entries = new_entries
                                        pending_admin_secret = None
                                        pending_recovery_codes = None
                                        pending_recovery_entries = None
                                        pending_original_recovery = None
                                        reply = "OK\n"
                                    except CommitPreRenameError:
                                        log_event("commit-failed")
                                        pending_admin_secret = None
                                        pending_recovery_codes = None
                                        pending_recovery_entries = None
                                        pending_original_recovery = None
                                        reply = "UNAVAILABLE\n"
                                    except CommitPostRenameError:
                                        log_event("commit-fsync-failed")
                                        pending_admin_secret = None
                                        pending_recovery_codes = None
                                        pending_recovery_entries = None
                                        pending_original_recovery = None
                                        reply = "UNAVAILABLE\n"
                                        post_rename_fatal = True
                        elif line == "ENROLL_BEGIN":
                            if (pending_operation == "RECOVERY" and pending_admin_secret is not None
                                    and timestamp < pending_admin_expiry):
                                reply = "REFUSED\n"
                            elif cur_state is not None:
                                reply = "ENROLLED\n"
                            elif pending_admin_secret is not None and timestamp < pending_admin_expiry:
                                reply = "REFUSED\n"
                            else:
                                sec = base64.b32encode(os.urandom(20)).decode("ascii")
                                pending_recovery_codes, pending_recovery_entries = make_recovery_codes()
                                pending_original_recovery = list(active_recovery_entries)
                                pending_operation = line.split("_", 1)[0]
                                pending_admin_secret = sec
                                pending_admin_expiry = timestamp + 300
                                pending_admin_wrong = 0
                                reply = f"SECRET {sec}\n"
                        elif line.startswith("ENROLL_COMMIT "):
                            code = line.split(" ", 1)[1].strip()
                            if pending_admin_secret is None or pending_operation != line.split("_", 1)[0] or timestamp >= pending_admin_expiry:
                                reply = "UNAVAILABLE\n"
                            else:
                                ok, matched_counter = verify_code(pending_admin_secret, code, int(timestamp // 30), 0, hmac_fn=hmac_fn)
                                if ok:
                                    nstate = {
                                        "secret": pending_admin_secret,
                                        "last_counter": matched_counter,
                                        "failures": 0,
                                        "locked_until": 0,
                                        "enrolled": True,
                                    }
                                    try:
                                        fault = getattr(run, "injected_commit_fault", None)
                                        new_entries = list(pending_recovery_entries)
                                        commit_recovery(state_dir, pending_recovery_entries, fault=fault)
                                        commit_state(state_dir, state_for_commit(nstate), fault=fault)
                                        active_recovery_entries = new_entries
                                        pending_admin_secret = None
                                        pending_recovery_codes = None
                                        pending_recovery_entries = None
                                        pending_original_recovery = None
                                        structured("totp-unlock", source="enrol")
                                        reply = "OK\n"
                                    except CommitPreRenameError:
                                        log_event("commit-failed")
                                        try:
                                            commit_recovery(state_dir, pending_original_recovery or [])
                                            active_recovery_entries = list(pending_original_recovery or [])
                                        except (CommitPreRenameError, CommitPostRenameError):
                                            post_rename_fatal = True
                                        pending_admin_secret = None
                                        pending_recovery_codes = None
                                        pending_recovery_entries = None
                                        pending_original_recovery = None
                                        reply = "UNAVAILABLE\n"
                                    except CommitPostRenameError:
                                        log_event("commit-fsync-failed")
                                        reply = "UNAVAILABLE\n"
                                        pending_admin_secret = None
                                        pending_recovery_codes = None
                                        pending_recovery_entries = None
                                        pending_original_recovery = None
                                        post_rename_fatal = True
                                else:
                                    pending_admin_wrong += 1
                                    if pending_admin_wrong >= 5:
                                        pending_admin_secret = None
                                        pending_recovery_codes = None
                                        pending_recovery_entries = None
                                        pending_original_recovery = None
                                    reply = "NO\n"
                        elif line == "ROTATE_BEGIN":
                            if cur_state is None:
                                reply = "NOT_ENROLLED\n"
                            elif pending_admin_secret is not None and timestamp < pending_admin_expiry:
                                reply = "REFUSED\n"
                            else:
                                sec = base64.b32encode(os.urandom(20)).decode("ascii")
                                pending_recovery_codes, pending_recovery_entries = make_recovery_codes()
                                pending_original_recovery = list(active_recovery_entries)
                                pending_operation = line.split("_", 1)[0]
                                pending_admin_secret = sec
                                pending_admin_expiry = timestamp + 300
                                pending_admin_wrong = 0
                                reply = f"SECRET {sec}\n"
                        elif line.startswith("ROTATE_COMMIT "):
                            code = line.split(" ", 1)[1].strip()
                            if pending_admin_secret is None or pending_operation != line.split("_", 1)[0] or timestamp >= pending_admin_expiry:
                                reply = "UNAVAILABLE\n"
                            else:
                                ok, matched_counter = verify_code(pending_admin_secret, code, int(timestamp // 30), 0, hmac_fn=hmac_fn)
                                if ok:
                                    nstate = dict(cur_state)
                                    nstate["secret"] = pending_admin_secret
                                    nstate["last_counter"] = matched_counter
                                    nstate["failures"] = 0
                                    nstate["locked_until"] = 0
                                    nstate["enrolled"] = True
                                    try:
                                        fault = getattr(run, "injected_commit_fault", None)
                                        new_entries = list(pending_recovery_entries)
                                        commit_recovery(state_dir, pending_recovery_entries, fault=fault)
                                        commit_state(state_dir, state_for_commit(nstate), fault=fault)
                                        active_recovery_entries = new_entries
                                        pending_admin_secret = None
                                        pending_recovery_codes = None
                                        pending_recovery_entries = None
                                        pending_original_recovery = None
                                        structured("totp-unlock", source="rotate")
                                        reply = "OK\n"
                                    except CommitPreRenameError:
                                        log_event("commit-failed")
                                        try:
                                            commit_recovery(state_dir, pending_original_recovery or [])
                                            active_recovery_entries = list(pending_original_recovery or [])
                                        except (CommitPreRenameError, CommitPostRenameError):
                                            post_rename_fatal = True
                                        pending_admin_secret = None
                                        pending_recovery_codes = None
                                        pending_recovery_entries = None
                                        pending_original_recovery = None
                                        reply = "UNAVAILABLE\n"
                                    except CommitPostRenameError:
                                        log_event("commit-fsync-failed")
                                        reply = "UNAVAILABLE\n"
                                        pending_admin_secret = None
                                        pending_recovery_codes = None
                                        pending_recovery_entries = None
                                        pending_original_recovery = None
                                        post_rename_fatal = True
                                else:
                                    pending_admin_wrong += 1
                                    if pending_admin_wrong >= 5:
                                        pending_admin_secret = None
                                        pending_recovery_codes = None
                                        pending_recovery_entries = None
                                        pending_original_recovery = None
                                    reply = "NO\n"
                        elif line == "ABORT":
                            pending_admin_secret = None
                            pending_recovery_codes = None
                            pending_recovery_entries = None
                            pending_original_recovery = None
                            reply = "OK\n"
                        elif line == "UNLOCK":
                            if cur_state is None:
                                reply = "NOT_ENROLLED\n"
                            elif cur_state is False:
                                reply = "UNAVAILABLE\n"
                            else:
                                reset = dict(cur_state, failures=0, locked_until=0, lock_level=0)
                                try:
                                    commit_state(state_dir, state_for_commit(reset), fault=getattr(run, "injected_commit_fault", None))
                                    lock_deadline_mono[0] = None
                                    deadline_locked_until[0] = 0
                                    active_lock_logged[0] = False
                                    structured("totp-unlock", source="admin")
                                    reply = "UNLOCKED\n"
                                except (CommitPreRenameError, CommitPostRenameError):
                                    log_event("commit-failed")
                                    reply = "UNAVAILABLE\n"
                                    if isinstance(sys.exc_info()[1], CommitPostRenameError):
                                        post_rename_fatal = True
                        else:
                            reply = "UNAVAILABLE\n"
                        if reply is not None:
                            try:
                                csock.sendall(reply.encode("ascii"))
                            except Exception:
                                pass
                        sel.unregister(csock)
                        csock.close()
                        admin_clients.pop(csock, None)
                        if post_rename_fatal:
                            break
                elif ktype == "totp_client":
                    csock = key.fileobj
                    cmeta = admitted_clients.get(csock)
                    if not cmeta:
                        continue
                    try:
                        chunk = csock.recv(64)
                    except Exception:
                        chunk = b""
                    if not chunk:
                        sel.unregister(csock)
                        csock.close()
                        admitted_clients.pop(csock, None)
                        notify("closed eof")
                        continue
                    cmeta["buf"].extend(chunk)
                    if len(cmeta["buf"]) > 32 and b"\n" not in cmeta["buf"][:33]:
                        sel.unregister(csock)
                        csock.close()
                        admitted_clients.pop(csock, None)
                        notify("closed wire-reject")
                        continue
                    if b"\n" in cmeta["buf"]:
                        line_bytes, _ = cmeta["buf"].split(b"\n", 1)
                        if len(line_bytes) > 31:
                            sel.unregister(csock)
                            csock.close()
                            admitted_clients.pop(csock, None)
                            notify("closed wire-reject")
                            continue
                        try:
                            line_str = line_bytes.decode("ascii")
                        except UnicodeDecodeError:
                            sel.unregister(csock)
                            csock.close()
                            admitted_clients.pop(csock, None)
                            notify("closed wire-reject")
                            continue
                        if not line_str.startswith("VERIFY "):
                            sel.unregister(csock)
                            csock.close()
                            admitted_clients.pop(csock, None)
                            notify("closed wire-reject")
                            continue
                        code = line_str[7:]
                        recovery_format = re.fullmatch(r"[A-Z2-7]{4}(-[A-Z2-7]{4}){3}", code) is not None
                        if not ((len(code) == 6 and code.isdigit()) or recovery_format):
                            sel.unregister(csock)
                            csock.close()
                            admitted_clients.pop(csock, None)
                            notify("closed wire-reject")
                            continue
                        cur_state = load_state(state_dir)
                        t_now = wall_time()
                        if recovery_format and t_now is not None and cur_state and cur_state.get("enrolled"):
                            entries = load_recovery(state_dir, expected_owner=expected_dir_owner, log_event=log_event)
                            normalized = code.replace("-", "")
                            matched_index = None
                            for index, entry in enumerate(entries):
                                digest = recovery_hash(entry["s"], normalized)
                                if hmac.compare_digest(digest, entry["h"]):
                                    matched_index = index
                            if matched_index is None:
                                recovery_failure_count += 1
                                current_mono = monotonic()
                                if recovery_failure_logged is None or current_mono - recovery_failure_logged >= 60:
                                    log_event(f"totp-recovery-failure count={recovery_failure_count}")
                                    recovery_failure_count = 0
                                    recovery_failure_logged = current_mono
                                reply = "NO\n"
                            else:
                                remaining_codes = entries[:matched_index] + entries[matched_index + 1:]
                                fault = getattr(run, "injected_commit_fault", None)
                                try:
                                    commit_recovery(state_dir, remaining_codes, fault=fault)
                                    active_recovery_entries = list(remaining_codes)
                                except CommitPreRenameError:
                                    log_event("commit-failed")
                                    reply = "UNAVAILABLE\n"
                                except CommitPostRenameError:
                                    log_event("commit-fsync-failed")
                                    reply = "UNAVAILABLE\n"
                                    post_rename_fatal = True
                                else:
                                    reset = dict(cur_state, failures=0, locked_until=0, lock_level=0)
                                    try:
                                        commit_state(state_dir, state_for_commit(reset), fault=fault)
                                        lock_deadline_mono[0] = None
                                        deadline_locked_until[0] = 0
                                        active_lock_logged[0] = False
                                        structured("totp-unlock", source="recovery")
                                        structured("totp-recovery-used", remaining=len(remaining_codes))
                                        if len(remaining_codes) <= 2:
                                            structured("totp-recovery-low", remaining=len(remaining_codes))
                                        reply = "OK\n"
                                    except CommitPreRenameError:
                                        log_event("commit-failed")
                                        reply = "UNAVAILABLE\n"
                                    except CommitPostRenameError:
                                        log_event("commit-fsync-failed")
                                        reply = "UNAVAILABLE\n"
                                        post_rename_fatal = True
                        elif t_now is None or not cur_state or not cur_state.get("enrolled"):
                            reply = "UNAVAILABLE\n"
                            log_event("state-unavailable")
                        else:
                            locked_until = cur_state.get("locked_until", 0)
                            failures = cur_state.get("failures", 0)
                            last_counter = cur_state.get("last_counter", 0)
                            sec = cur_state["secret"]
                            cur_state, changed = decay_state(cur_state, t_now)
                            if changed:
                                try:
                                    commit_state(state_dir, state_for_commit(cur_state), fault=getattr(run, "injected_commit_fault", None))
                                    if cur_state.get("lock_level", 0) == 0:
                                        structured("totp-unlock", source="decay")
                                except (CommitPreRenameError, CommitPostRenameError):
                                    reply = "UNAVAILABLE\n"
                                    log_event("commit-failed")
                                    csock.sendall(reply.encode("ascii"))
                                    sel.unregister(csock)
                                    csock.close()
                                    admitted_clients.pop(csock, None)
                                    continue
                            locked_until = cur_state.get("locked_until", 0)
                            sync_lock_deadline(cur_state, t_now)
                            remaining_mono = None if lock_deadline_mono[0] is None else lock_deadline_mono[0] - monotonic()
                            if locked_until > 0 and remaining_mono is not None and remaining_mono > 0:
                                remaining = max(1, math.ceil(remaining_mono))
                                if not active_lock_logged[0]:
                                    structured("totp-locked-reply", lock_level=cur_state.get("lock_level", 1))
                                    active_lock_logged[0] = True
                                reply = f"WAIT {remaining}\n"
                            else:
                                if locked_until > 0 and failures >= 5 and monotonic() >= lock_deadline_mono[0]:
                                    cur_state["failures"] = 0
                                    cur_state["locked_until"] = locked_until
                                    try:
                                        commit_state(state_dir, state_for_commit(cur_state), fault=getattr(run, "injected_commit_fault", None))
                                        failures = 0
                                    except CommitPreRenameError:
                                        reply = "UNAVAILABLE\n"
                                        log_event("commit-failed")
                                        csock.sendall(reply.encode("ascii"))
                                        sel.unregister(csock)
                                        csock.close()
                                        admitted_clients.pop(csock, None)
                                        notify("closed done")
                                        continue
                                    except CommitPostRenameError:
                                        reply = "UNAVAILABLE\n"
                                        log_event("commit-fsync-failed")
                                        csock.sendall(reply.encode("ascii"))
                                        sel.unregister(csock)
                                        csock.close()
                                        admitted_clients.pop(csock, None)
                                        post_rename_fatal = True
                                        notify("closed done")
                                        break
                                cur_counter = int(t_now // 30)
                                ok, matched = verify_code(sec, code, cur_counter, last_counter, hmac_fn=hmac_fn)
                                if ok:
                                    nstate = dict(cur_state)
                                    nstate["last_counter"] = matched
                                    nstate["failures"] = 0
                                    nstate["locked_until"] = 0
                                    nstate["lock_level"] = 0
                                    try:
                                        fault = getattr(run, "injected_commit_fault", None)
                                        commit_state(state_dir, state_for_commit(nstate), fault=fault)
                                        lock_deadline_mono[0] = None
                                        deadline_locked_until[0] = 0
                                        active_lock_logged[0] = False
                                        structured("totp-unlock", source="success")
                                        reply = "OK\n"
                                    except CommitPreRenameError:
                                        reply = "UNAVAILABLE\n"
                                        log_event("commit-failed")
                                    except CommitPostRenameError:
                                        reply = "UNAVAILABLE\n"
                                        log_event("commit-fsync-failed")
                                        post_rename_fatal = True
                                else:
                                    failures += 1
                                    nstate = dict(cur_state)
                                    nstate["failures"] = failures
                                    if failures >= 5:
                                        nstate["lock_level"] = min(4, nstate.get("lock_level", 0) + 1)
                                        duration = lock_seconds[nstate["lock_level"] - 1]
                                        nstate["locked_until"] = int(t_now + duration)
                                        lock_deadline_mono[0] = monotonic() + duration
                                        deadline_locked_until[0] = nstate["locked_until"]
                                        active_lock_logged[0] = False
                                        structured("totp-lock", lock_level=nstate["lock_level"], seconds=duration)
                                    structured("totp-failure", failures=failures, lock_level=nstate.get("lock_level", 0))
                                    try:
                                        fault = getattr(run, "injected_commit_fault", None)
                                        commit_state(state_dir, state_for_commit(nstate), fault=fault)
                                        reply = "NO\n"
                                    except CommitPreRenameError:
                                        reply = "UNAVAILABLE\n"
                                        log_event("commit-failed")
                                    except CommitPostRenameError:
                                        reply = "UNAVAILABLE\n"
                                        log_event("commit-fsync-failed")
                                        post_rename_fatal = True
                        try:
                            csock.sendall(reply.encode("ascii"))
                        except Exception:
                            pass
                        sel.unregister(csock)
                        csock.close()
                        admitted_clients.pop(csock, None)
                        notify("closed done")
                        if post_rename_fatal:
                            break
            if post_rename_fatal:
                for s in list(admitted_clients.keys()) + list(admin_clients.keys()):
                    try:
                        sel.unregister(s)
                    except Exception:
                        pass
                    try:
                        s.close()
                    except Exception:
                        pass
                admitted_clients.clear()
                admin_clients.clear()
                return 1
    finally:
        for conn in list(admitted_clients) + list(admin_clients) + list(pending_futures.values()):
            conn.close()
        executor.shutdown(wait=True)
        sel.close()
        try:
            totp_sock.close()
        except Exception:
            pass
        try:
            admin_sock.close()
        except Exception:
            pass
        for p in (totp_sock_path, admin_sock_path):
            try:
                if os.path.exists(p) or os.path.islink(p):
                    os.unlink(p)
            except Exception:
                pass
    return 0

def main():
    rc = run(conf_path=DEFAULT_TOTP_CONF, state_dir=DEFAULT_STATE_DIR, run_dir=DEFAULT_RUN_DIR,
             log_path=DEFAULT_LOG, expected_conf_owner=0, expected_dir_owner=0,
             expected_job_label=DEFAULT_PART_A_LABEL, expected_gate_path=DEFAULT_GATE_PATH,
             expected_interpreter=PYAPP)
    raise SystemExit(rc)

if __name__ == "__main__":
    main()
