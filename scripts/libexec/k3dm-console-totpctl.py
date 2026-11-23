#!/Library/Developer/CommandLineTools/usr/bin/python3 -IS
import os
import re
import select
import socket
import sys
import termios

DEFAULT_ADMIN_SOCK = "/var/db/k3dm-web-console-run/admin.sock"

def send_admin_cmd(sock_path, cmd):
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    try:
        s.settimeout(5.0)
        s.connect(sock_path)
        s.sendall(cmd.encode("ascii") + b"\n")
        resp = b""
        while b"\n" not in resp and len(resp) < 64:
            chunk = s.recv(64 - len(resp))
            if not chunk:
                break
            resp += chunk
        if not resp.endswith(b"\n") or resp.count(b"\n") != 1:
            raise OSError("incomplete admin reply")
        return resp[:-1].decode("ascii", errors="replace")
    finally:
        s.close()

def run(argv=None, admin_sock=DEFAULT_ADMIN_SOCK, tty_in=None, tty_out=None, check_root=True):
    if argv is None:
        argv = sys.argv[1:]
    if check_root and os.geteuid() != 0:
        sys.stderr.write("totpctl: root privileges required\n")
        return 1
    if not argv:
        sys.stderr.write("usage: totpctl status [--wire] | enroll | rotate | unlock | recovery-status | recovery-regen\n")
        return 1
    cmd = argv[0]
    if cmd == "status":
        wire = "--wire" in argv
        try:
            resp = send_admin_cmd(admin_sock, "STATUS")
        except OSError:
            if wire:
                return 1
            resp = "UNAVAILABLE"
        if resp not in ("ENROLLED", "NOT_ENROLLED", "UNAVAILABLE"):
            if wire:
                return 1
            resp = "UNAVAILABLE"
        if wire:
            sys.stdout.write(f"{resp}\n")
            sys.stdout.flush()
            return 0
        if resp == "ENROLLED":
            sys.stdout.write("enrolled\n")
        elif resp == "NOT_ENROLLED":
            sys.stdout.write("not enrolled\n")
        else:
            sys.stdout.write("state damaged\n")
        sys.stdout.flush()
        return 0
    if cmd == "unlock":
        try:
            resp = send_admin_cmd(admin_sock, "UNLOCK")
        except OSError:
            resp = "UNAVAILABLE"
        if resp == "UNLOCKED":
            sys.stdout.write("unlocked\n")
            sys.stdout.flush()
            return 0
        if resp == "NOT_ENROLLED":
            sys.stderr.write("totpctl: not enrolled\n")
        else:
            sys.stderr.write("totpctl: state unavailable\n")
        return 1
    if cmd == "recovery-status":
        try:
            resp = send_admin_cmd(admin_sock, "RECOVERY_STATUS")
        except OSError:
            resp = "UNAVAILABLE"
        match = re.fullmatch(r"RECOVERY ([0-9]|10)", resp)
        if match:
            sys.stdout.write(f"{match.group(1)} recovery codes remaining\n")
            return 0
        if resp == "NOT_ENROLLED":
            sys.stderr.write("totpctl: not enrolled\n")
        else:
            sys.stderr.write("totpctl: state unavailable\n")
        return 1
    if cmd == "recovery-regen":
        fin, fout = tty_in, tty_out
        opened_tty = False
        if fin is None or fout is None:
            try:
                tty_fd_in = os.open("/dev/tty", os.O_RDONLY)
                tty_fd_out = os.open("/dev/tty", os.O_WRONLY)
                fin = open(tty_fd_in, "r", encoding="utf-8")
                fout = open(tty_fd_out, "w", encoding="utf-8")
                opened_tty = True
            except Exception:
                sys.stderr.write("totpctl: unable to open /dev/tty\n")
                return 1
        codes_printed = False
        try:
            try:
                resp = send_admin_cmd(admin_sock, "RECOVERY_BEGIN")
            except OSError:
                resp = "UNAVAILABLE"
            if resp != "RECOVERY_PENDING":
                fout.write("recovery regeneration unavailable\n")
                return 1
            fout.write("Replace all recovery codes? Type yes: ")
            fout.flush()
            if fin.isatty() and not select.select([fin], [], [], 600)[0]:
                send_admin_cmd(admin_sock, "ABORT")
                return 1
            if fin.readline(16).strip().lower() != "yes":
                send_admin_cmd(admin_sock, "ABORT")
                return 1
            fout.write("Code: ")
            fout.flush()
            if fin.isatty() and not select.select([fin], [], [], 600)[0]:
                send_admin_cmd(admin_sock, "ABORT")
                return 1
            code = fin.readline(8).strip()
            if not re.fullmatch(r"[0-9]{6}", code):
                send_admin_cmd(admin_sock, "ABORT")
                return 1
            codes = []
            for index in range(10):
                item = send_admin_cmd(admin_sock, f"RECOVERY_GET {index}")
                match = re.fullmatch(r"CODE ([A-Z2-7]{4}(?:-[A-Z2-7]{4}){3})", item)
                if not match:
                    send_admin_cmd(admin_sock, "ABORT")
                    return 1
                codes.append(match.group(1))
            fout.write("Recovery codes (each works once):\n")
            fout.write("\n".join(codes) + "\n")
            fout.flush()
            codes_printed = True
            try:
                result = send_admin_cmd(admin_sock, f"RECOVERY_COMMIT {code}")
            except OSError:
                result = "UNAVAILABLE"
            if result == "OK":
                fout.write("recovery codes replaced\n")
                return 0
            if result != "UNAVAILABLE":
                send_admin_cmd(admin_sock, "ABORT")
            fout.write("recovery codes were not replaced\n")
            return 1
        finally:
            if codes_printed:
                fout.write("\x1b[3J\x1b[H\x1b[2J")
                fout.flush()
            if opened_tty:
                try:
                    fin.close()
                    fout.close()
                except Exception:
                    pass
    if cmd in ("enroll", "rotate"):
        opened_tty = False
        fin = tty_in
        fout = tty_out
        if fin is None or fout is None:
            try:
                tty_fd_in = os.open("/dev/tty", os.O_RDONLY)
                tty_fd_out = os.open("/dev/tty", os.O_WRONLY)
                fin = open(tty_fd_in, "r", encoding="utf-8")
                fout = open(tty_fd_out, "w", encoding="utf-8")
                opened_tty = True
            except Exception:
                sys.stderr.write("totpctl: unable to open /dev/tty\n")
                return 1
        codes_printed = False
        try:
            begin_verb = "ENROLL_BEGIN" if cmd == "enroll" else "ROTATE_BEGIN"
            commit_verb = "ENROLL_COMMIT" if cmd == "enroll" else "ROTATE_COMMIT"
            try:
                resp = send_admin_cmd(admin_sock, begin_verb)
            except Exception:
                resp = "UNAVAILABLE"
            if not resp.startswith("SECRET "):
                if resp == "ENROLLED":
                    fout.write("already enrolled\n")
                elif resp == "NOT_ENROLLED":
                    fout.write("not enrolled\n")
                else:
                    fout.write("state damaged\n")
                fout.flush()
                return 1
            secret = resp.split(" ", 1)[1].strip()
            hostname = socket.gethostname().split(".")[0]
            if not re.fullmatch(r"[A-Z2-7]{32}", secret):
                return 1
            uri = f"otpauth://totp/k3dm-console-{hostname}?secret={secret}&issuer=k3dm-console"
            fout.write(f"Secret: {secret}\n")
            fout.write(f"URI: {uri}\n")
            saved = None
            if fin.isatty():
                saved = termios.tcgetattr(fin)
                hidden = saved.copy()
                hidden[3] &= ~termios.ECHO
                termios.tcsetattr(fin, termios.TCSANOW, hidden)
            try:
                fout.write("Code: ")
                fout.flush()
                if saved and not select.select([fin], [], [], 300)[0]:
                    return 1
                line = fin.readline(8)
            finally:
                if saved:
                    termios.tcsetattr(fin, termios.TCSANOW, saved)
                    fout.write("\n")
            if not line:
                return 1
            code = line.rstrip("\r\n")
            if not re.fullmatch("[0-9]{6}", code):
                fout.write("Invalid code\n")
                return 1
            recovery_codes = []
            for index in range(10):
                item = send_admin_cmd(admin_sock, f"RECOVERY_GET {index}")
                match = re.fullmatch(r"CODE ([A-Z2-7]{4}(?:-[A-Z2-7]{4}){3})", item)
                if not match:
                    send_admin_cmd(admin_sock, "ABORT")
                    fout.write("state damaged\n")
                    return 1
                recovery_codes.append(match.group(1))
            fout.write("Recovery codes (each works once):\n")
            fout.write("\n".join(recovery_codes) + "\n")
            fout.flush()
            codes_printed = True
            try:
                commit_resp = send_admin_cmd(admin_sock, f"{commit_verb} {code}")
            except Exception:
                commit_resp = "UNAVAILABLE"
            if commit_resp == "OK":
                fout.write("enrolled\n")
                fout.flush()
                return 0
            if commit_resp == "UNAVAILABLE":
                fout.write("commit not confirmed; run web-console-totp-status\n")
                fout.flush()
                return 1
            try:
                send_admin_cmd(admin_sock, "ABORT")
            except Exception:
                pass
            fout.write("Invalid code\nThe recovery codes shown are void.\n")
            fout.flush()
            return 1
        finally:
            if codes_printed:
                fout.write("\x1b[3J\x1b[H\x1b[2J")
                fout.flush()
            if opened_tty:
                try:
                    fin.close()
                except Exception:
                    pass
                try:
                    fout.close()
                except Exception:
                    pass
    sys.stderr.write(f"totpctl: unknown command {cmd}\n")
    return 1

def main():
    rc = run()
    sys.exit(rc)

if __name__ == "__main__":
    main()
