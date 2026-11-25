#!/Library/Developer/CommandLineTools/usr/bin/python3 -IS
import os
import re
import select
import socket
import sys
import termios

DEFAULT_ADMIN_SOCK = "/var/db/k3dm-web-console-run/admin.sock"

def _qr_matrix(data):
    if len(data) > 134:
        return None
    bits = [0, 1, 0, 0]
    for shift in range(7, -1, -1):
        bits.append((len(data) >> shift) & 1)
    for byte in data:
        bits.extend((byte >> shift) & 1 for shift in range(7, -1, -1))
    bits.extend([0] * min(4, 136 * 8 - len(bits)))
    while len(bits) % 8:
        bits.append(0)
    payload = bytearray()
    for offset in range(0, len(bits), 8):
        value = 0
        for bit in bits[offset:offset + 8]:
            value = (value << 1) | bit
        payload.append(value)
    pad = 0xEC
    while len(payload) < 136:
        payload.append(pad)
        pad = 0x11 if pad == 0xEC else 0xEC

    def mul(a, b):
        result = 0
        while b:
            if b & 1:
                result ^= a
            a <<= 1
            if a & 0x100:
                a ^= 0x11D
            b >>= 1
        return result

    generator = [1]
    root = 1
    for _ in range(18):
        nxt = [0] * (len(generator) + 1)
        for i, coefficient in enumerate(generator):
            nxt[i] ^= coefficient
            nxt[i + 1] ^= mul(coefficient, root)
        generator = nxt
        root = mul(root, 2)
    blocks = [payload[:68], payload[68:]]
    ec = []
    for block in blocks:
        remainder = [0] * 18
        for value in block:
            factor = value ^ remainder.pop(0)
            remainder.append(0)
            for index, coefficient in enumerate(generator[1:]):
                remainder[index] ^= mul(coefficient, factor)
        ec.append(remainder)
    codewords = []
    for i in range(68):
        codewords.extend(block[i] for block in blocks)
    for i in range(18):
        codewords.extend(block[i] for block in ec)
    stream = []
    for value in codewords:
        stream.extend((value >> shift) & 1 for shift in range(7, -1, -1))
    stream.extend([0] * 7)
    matrix = [[False] * 41 for _ in range(41)]
    reserved = [[False] * 41 for _ in range(41)]
    def put(row, col, value):
        if 0 <= row < 41 and 0 <= col < 41:
            matrix[row][col] = bool(value)
            reserved[row][col] = True
    for row0, col0 in ((0, 0), (0, 34), (34, 0)):
        for dr in range(-1, 8):
            for dc in range(-1, 8):
                row, col = row0 + dr, col0 + dc
                if 0 <= row < 41 and 0 <= col < 41:
                    dark = 0 <= dr <= 6 and 0 <= dc <= 6 and (dr in (0, 6) or dc in (0, 6) or (2 <= dr <= 4 and 2 <= dc <= 4))
                    put(row, col, dark)
    for i in range(8, 33):
        put(6, i, i % 2 == 0)
        put(i, 6, i % 2 == 0)
    for dr in range(-2, 3):
        for dc in range(-2, 3):
            put(34 + dr, 34 + dc, max(abs(dr), abs(dc)) != 1)
    format_info = int("111011111000100", 2)
    for i in range(8):
        offset = 1 if i >= 6 else 0
        put(i + offset, 8, (format_info >> i) & 1)
        put(8, i + offset, (format_info >> (14 - i)) & 1)
        put(8, 40 - i, (format_info >> i) & 1)
        put(40 - i, 8, (format_info >> (14 - i)) & 1)
    put(33, 8, True)
    bit_index = 0
    col = 40
    upward = True
    while col > 0:
        if col == 6:
            col -= 1
        for row in (range(40, -1, -1) if upward else range(41)):
            for c in (col, col - 1):
                if not reserved[row][c]:
                    bit = stream[bit_index] if bit_index < len(stream) else 0
                    bit_index += 1
                    matrix[row][c] = bool(bit ^ ((row + c) % 2 == 0))
        upward = not upward
        col -= 2
    return matrix

def _qr_render(matrix):
    padded = [[False] * 49 for _ in range(4)]
    padded.extend([[False] * 4 + list(row) + [False] * 4 for row in matrix])
    padded.extend([[False] * 49 for _ in range(4)])
    out = []
    for row in range(0, 49, 2):
        line = []
        for col in range(49):
            fg = "30" if padded[row][col] else "97"
            bg = "40" if row + 1 < 49 and padded[row + 1][col] else "107"
            line.append("\x1b[" + fg + ";" + bg + "m" + "\u2580")
        out.append("".join(line) + "\x1b[0m\n")
    return "".join(out)

def _pause_for_recovery_codes(fin, fout):
    try:
        if fin.isatty():
            termios.tcflush(fin.fileno(), termios.TCIFLUSH)
        fout.write("Save the recovery codes now (not on your travel device), then press Enter to clear the screen: ")
        fout.flush()
        if fin.isatty() and not select.select([fin], [], [], 600)[0]:
            return
        fin.readline(1024)
    except (EOFError, KeyboardInterrupt, OSError):
        pass

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
                _pause_for_recovery_codes(fin, fout)
                return 0
            if result != "UNAVAILABLE":
                send_admin_cmd(admin_sock, "ABORT")
            fout.write("recovery codes were not replaced\n")
            if result == "UNAVAILABLE":
                fout.write("commit not confirmed; run web-console-totp-status\n")
                _pause_for_recovery_codes(fin, fout)
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
            if fin.isatty():
                try:
                    if os.get_terminal_size(fout.fileno()).lines < 34:
                        fout.write("Enlarge this window to at least 34 rows so the whole QR code is visible.\n")
                except (OSError, AttributeError, ValueError):
                    pass
            qr = _qr_matrix(uri.encode("utf-8"))
            if qr is None:
                fout.write("QR not shown (URI too long); enter the Secret line in your authenticator\n")
            else:
                fout.write("Scan this with your phone's camera or authenticator app:\n")
                fout.write(_qr_render(qr))
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
                _pause_for_recovery_codes(fin, fout)
                return 0
            if commit_resp == "UNAVAILABLE":
                fout.write("commit not confirmed; run web-console-totp-status\n")
                fout.flush()
                _pause_for_recovery_codes(fin, fout)
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
