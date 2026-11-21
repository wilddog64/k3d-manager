"""Installed promotion authority. Production paths are bound only in main."""

import argparse
import base64
import collections
import hashlib
from datetime import date
import json
import os
from pathlib import Path
import re
import socket
import stat
import struct
import subprocess
import sys
import termios
import time

CLT = "/Library/Developer/CommandLineTools"
PY = CLT + "/usr/bin/python3"
GIT = CLT + "/usr/bin/git"
FRAME = CLT + "/Library/Frameworks/Python3.framework/Versions/3.9/bin/python3"
LIBEXEC = "/usr/local/libexec/k3dm-promote"
ROOT = "/var/db/k3dm-promote"
CONF = "/etc/k3dm-promote/promote.conf"
LABEL = "com.k3d-manager.promote-authority"
MODULES = ("k3dm-promote-daemon.py", "hub_approval.py", "promote_mover.py")
LINKS = {PY: "../../Library/Frameworks/Python3.framework/Versions/3.9/bin/python3", FRAME: "python3.9"}
CHAIN = tuple(
    dict.fromkeys(
        str(p)
        for leaf in (PY, FRAME, FRAME + ".9", *(LIBEXEC + "/" + m for m in MODULES))
        for p in (*reversed(Path(leaf).parents), Path(leaf))
        if str(p) != "/"
    )
) + ("/etc/k3dm-promote", CONF, ROOT, ROOT + "/creds", ROOT + "/state", ROOT + "/mirror.git")
OPS = {
    "request": "sha branch channel requested_by",
    "show": "id",
    "approve": "id nonce approver totp check at sig",
    "deny": "id nonce approver",
    "promote": "id sha",
    "status": "",
}
OID = r"(?:[0-9a-f]{40}|[0-9a-f]{64})"


def under(root, path):
    return Path(root) / path.lstrip("/")


def has_acl(path):
    if sys.platform == "darwin":
        # Darwin does not expose file ACLs through Python's listxattr.
        listing = subprocess.run(
            ["/bin/ls", "-lde", str(path)], check=True, stdout=subprocess.PIPE, env={"LC_ALL": "C"}
        ).stdout
        return len(listing.splitlines()) > 1
    return bool(
        {"system.posix_acl_access", "system.posix_acl_default"}.intersection(os.listxattr(path, follow_symlinks=False))
    )


def integrity(root, owner_uid, chain):
    for name in chain:
        path = under(root, name)
        try:
            info = path.lstat()
            if info.st_uid != owner_uid or has_acl(path):
                raise ValueError
            # On Linux symlink permission bits are fixed at 0777. Darwin
            # exposes the actual link mode of the pinned CLT interpreter.
            if info.st_mode & 0o022 and (name not in LINKS or sys.platform == "darwin"):
                raise ValueError
            if name in LINKS:
                if os.readlink(path) != LINKS[name]:
                    raise ValueError
            elif stat.S_ISLNK(info.st_mode):
                raise ValueError
        except (OSError, ValueError, subprocess.SubprocessError):
            print(path, file=sys.stderr)
            raise SystemExit(78)


def bootstrap(root, owner_uid, chain):
    integrity(root, owner_uid, chain)
    sys.path.insert(0, str(under(root, LIBEXEC)))
    global hub_approval, promote_mover
    import hub_approval, promote_mover


def parse_config(raw):
    if len(raw) > 4096 or not raw.endswith(b"\n"):
        raise ValueError
    conf = {}
    for line in raw[:-1].decode("ascii").split("\n"):
        key, sep, value = line.partition("=")
        if not sep or key in conf:
            raise ValueError
        conf[key] = value
    if set(conf) != {"operator_uid", "operator_gid", "operator_ids", "repo_ssh", "repo_slug"}:
        raise ValueError
    for key in ("operator_uid", "operator_gid"):
        if not re.fullmatch(r"[0-9]{1,10}", conf[key]) or not int(conf[key]):
            raise ValueError
        conf[key] = int(conf[key])
    ids = conf["operator_ids"].split(",")
    if not all(re.fullmatch(r"[A-Z0-9]{2,32}|cli", i) for i in ids):
        raise ValueError
    conf["operator_ids"] = ids
    match = re.fullmatch(r"git@github\.com:([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)\.git", conf["repo_ssh"])
    if not match or match[1] != conf["repo_slug"]:
        raise ValueError
    return conf


def load_config(path):
    with open(path, "rb") as stream:
        return parse_config(stream.read(4097))


def render(template_text, values):
    return re.sub(r"@([a-z_]+)@", lambda m: str(values[m[1]]), template_text)


def creds(root):
    return under(root, ROOT + "/creds")


def ssh(root):
    directory = creds(root)
    return (
        f"/usr/bin/ssh -F /dev/null -i {directory}/deploy_key -o IdentitiesOnly=yes "
        f"-o UserKnownHostsFile={directory}/known_hosts -o StrictHostKeyChecking=yes -o BatchMode=yes"
    )


def build_mover(config, root):
    return promote_mover.Mover(
        config["repo_ssh"],
        config["repo_slug"],
        promote_mover.CurlApi(str(creds(root) / "read_token")),
        ssh(root),
        str(under(root, ROOT + "/mirror.git")),
        hub_approval.SystemClock(),
    )


def secrets(root, owner):
    directory = creds(root)
    try:
        for name in ("totp.secret", "relay_hmac.key", "known_hosts", "deploy_key", "primed", "read_token"):
            info = (directory / name).lstat()
            if info.st_uid != owner or info.st_mode != stat.S_IFREG | 0o600:
                raise ValueError
        key = (directory / "relay_hmac.key").read_bytes()
        secret = base64.b32decode((directory / "totp.secret").read_bytes().strip())
        if len(secret) < 20 or not re.fullmatch(b"[0-9a-f]{64}\n", key):
            raise ValueError
        return secret, bytes.fromhex(key.decode())
    except (ValueError, OSError):
        return None, None


def stamp(clock=None, fmt="%Y%m%dT%H%M%SZ"):
    return time.strftime(fmt, time.gmtime(clock.now() if clock else time.time()))


def status(root, engine, configured):
    state = under(root, ROOT + "/state")
    ids = [p.stem for p in state.glob("p*.json") if re.fullmatch(hub_approval.ID, p.stem)]
    pending = {i for i in ids if engine.show(i)["state"] == "pending"}
    lost = ids and any(not (state / n).exists() for n in ("serial.json", "totp-state.json", "clock-hw.json"))
    rows = collections.deque(maxlen=10)
    for name in ("audit.1.jsonl", "audit.jsonl"):
        if (state / name).exists():
            with (state / name).open() as stream:
                for line in stream:
                    row = json.loads(line)
                    if row["id"] in pending:
                        row["id"] = None
                    rows.append(row)
    marker = creds(root) / "ruleset-verified"
    ruleset = "asserted " + json.loads(marker.read_bytes())["asserted_on"] if marker.exists() else "not asserted"
    return dict(
        daemon="ok",
        configured=configured,
        pending=len(pending),
        state="lost" if lost else "ok",
        ruleset=ruleset,
        audit=list(rows),
    )


def unique_fields(pairs):
    result = dict(pairs)
    if len(result) != len(pairs):
        raise ValueError("duplicate JSON field")
    return result


def read_request(conn, monotonic):
    end = monotonic() + 10
    line = bytearray()
    while len(line) < 4096:
        left = end - monotonic()
        if left <= 0:
            break
        conn.settimeout(min(5, left))
        chunk = conn.recv(4096 - len(line))
        if not chunk:
            break
        line.extend(chunk)
        if b"\n" in chunk:
            if line.count(b"\n") != 1 or not line.endswith(b"\n"):
                break
            req = json.loads(line.decode("utf-8"), object_pairs_hook=unique_fields)
            if not isinstance(req, dict) or type(req.get("v")) is not int:
                break
            if req.pop("v") != 1:
                break
            op = req.pop("op", None)
            if (
                isinstance(op, str)
                and op in OPS
                and set(req) == set(OPS[op].split())
                and all(isinstance(v, str) for v in req.values())
            ):
                for value in req.values():
                    value.encode("utf-8")
                return op, req
            break
    raise ValueError


def local_peercred_uid(conn):
    raw = conn.getsockopt(0, 1, 76)
    if len(raw) != 76:
        raise ValueError("incomplete peer credential")
    version, uid = struct.unpack_from("=II", raw)
    if version:
        raise ValueError
    return uid


class RealFs:
    root = "/"
    owner_uid = 0
    owner_gid = 0
    rundir = Path("/var/run/k3dm-promote")
    chown = staticmethod(os.chown)
    mkdir = staticmethod(os.mkdir)


def serve(
    config,
    engine_factory,
    mover_factory=build_mover,
    listener=None,
    peer_uid=local_peercred_uid,
    fs=RealFs(),
    monotonic=time.monotonic,
):
    run = Path(fs.rundir)
    try:
        info = run.lstat()
        if (info.st_uid, info.st_gid, info.st_mode) != (fs.owner_uid, fs.owner_gid, stat.S_IFDIR | 0o755):
            archive = run.with_name(run.name + ".bad." + stamp())
            if os.path.lexists(archive):
                archive = archive.with_name(archive.name + "." + str(time.time_ns()))
            run.rename(archive)
    except FileNotFoundError:
        pass
    if not run.exists():
        fs.mkdir(run, 0o755)
        run.chmod(0o755)
        fs.chown(run, 0, 0)
    path = run / "sock"
    path.unlink(missing_ok=True)
    with listener or socket.socket(socket.AF_UNIX) as server:
        old = os.umask(0o177)
        try:
            server.bind(str(path))
        finally:
            os.umask(old)
        fs.chown(path, config["operator_uid"], config["operator_gid"])
        server.listen(8)
        while True:
            try:
                conn, _ = server.accept()
            except ConnectionAbortedError:
                continue
            with conn:
                try:
                    if peer_uid(conn) != config["operator_uid"]:
                        continue
                except (ValueError, OSError):
                    continue
                try:
                    op, req = read_request(conn, monotonic)
                except (ValueError, OSError, RecursionError):
                    result = hub_approval.Refused("bad_input")
                else:
                    try:
                        secret, key = secrets(fs.root, fs.owner_uid)
                        engine = engine_factory(
                            str(under(fs.root, ROOT + "/state")),
                            hub_approval.SystemClock(),
                            secret,
                            config["operator_ids"],
                            key,
                        )
                        if op == "status":
                            result = status(fs.root, engine, key is not None)
                        elif op != "show" and key is None:
                            raise hub_approval.Unknown("unconfigured")
                        elif op == "promote":
                            result = promote_mover.promote(
                                engine, mover_factory(config, fs.root), req["id"], req["sha"], monotonic() + 120
                            )
                        else:
                            result = getattr(engine, op)(**req)
                    except (hub_approval.Refused, hub_approval.Unknown) as exc:
                        exc.message = " ".join(exc.message.split())[:1024]
                        result = exc
                    except (OSError, ValueError):
                        result = hub_approval.Unknown("io")
                try:
                    conn.sendall((hub_approval.to_wire(result) + "\n").encode())
                except OSError:
                    pass


def sync(path):
    fd = os.open(path, os.O_RDONLY)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def activate(target):
    source = target.with_name(target.name + ".new")
    source.chmod(0o600)
    sync(source)
    source.replace(target)
    sync(target.parent)


def stage(target, data):
    tmp = target.with_name(target.name + ".new")
    tmp.unlink(missing_ok=True)
    with os.fdopen(os.open(tmp, os.O_EXCL | os.O_CREAT | os.O_WRONLY, 0o600), "wb") as f:
        f.write(data)
        f.flush()
        os.fsync(f.fileno())


def ask(inp, out, prompt):
    print(prompt, file=out, flush=True)
    line = inp.readline()
    if not line:
        raise ValueError("console input ended")
    return line.rstrip("\n")


def command(argv):
    return subprocess.run(
        argv,
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env={
            "PATH": "/usr/bin:/bin",
            "HOME": "/var/empty",
            "GIT_CONFIG_GLOBAL": "/dev/null",
            "GIT_CONFIG_NOSYSTEM": "1",
        },
    ).stdout


def enrol(root, config, tty_in, tty_out, tools, rotate=None, mover_factory=build_mover, urandom=os.urandom):
    if not tty_in.isatty() or not tty_out.isatty():
        raise ValueError("enrol requires a console")
    directory = creds(root)
    primed = directory / "primed"
    if rotate in ("deploy-key", "token", "host-key"):
        primed.unlink(missing_ok=True)
        sync(directory)
    for kind, name in (
        ("totp", "totp.secret"),
        ("relay-key", "relay_hmac.key"),
        ("deploy-key", "deploy_key"),
        ("token", "read_token"),
        ("host-key", "known_hosts"),
        ("fetch", "primed"),
    ):
        target = directory / name
        tmp = directory / (name + ".new")
        tmp.unlink(missing_ok=True)
        if kind == "deploy-key":
            (directory / "deploy_key.new.pub").unlink(missing_ok=True)
        if not target.exists() or rotate == kind:
            if kind in ("totp", "relay-key"):
                value = base64.b32encode(urandom(20)).decode() if kind == "totp" else urandom(32).hex()
                stage(target, (value + "\n").encode())
                prompt = (
                    "otpauth://totp/k3dm-promote?secret=" + value + "\n" + value
                    if kind == "totp"
                    else "wrangler secret put PROMOTE_RELAY_HMAC_KEY\n" + value
                )
                ask(tty_in, tty_out, prompt + "\nPress Enter after saving.")
                print("\033[3J\033[H\033[2J", end="", file=tty_out, flush=True)
            elif kind == "deploy-key":
                command([tools["ssh_keygen"], "-q", "-t", "ed25519", "-N", "", "-C", "k3dm-promote", "-f", str(tmp)])
            elif kind == "token":
                attrs = termios.tcgetattr(tty_in)
                hidden = list(attrs)
                hidden[3] &= ~termios.ECHO
                termios.tcsetattr(tty_in, termios.TCSANOW, hidden)
                try:
                    token = ask(tty_in, tty_out, "Read token:")
                    if not re.fullmatch(r"[A-Za-z0-9._~+/-]+=*", token):
                        raise ValueError("invalid token")
                    stage(target, (token + "\n").encode())
                finally:
                    termios.tcsetattr(tty_in, termios.TCSANOW, attrs)
            elif kind == "host-key":
                stage(target, command([tools["ssh_keyscan"], "-t", "ed25519", "github.com"]))
                fingerprint = command([tools["ssh_keygen"], "-lf", str(tmp), "-E", "sha256"]).decode()
                if ask(tty_in, tty_out, fingerprint + "Compare on your own device. Type yes:") != "yes":
                    tmp.unlink()
                    raise ValueError("host key unconfirmed")
            else:
                try:
                    mover_factory(config, root).prime()
                except (hub_approval.Unknown, hub_approval.Refused) as exc:
                    print("First fetch failed (" + exc.code + "). Check the deploy key and retry enrol.", file=tty_out)
                    raise ValueError("first fetch failed") from exc
                sha = (
                    command(
                        [
                            tools.get("git", GIT),
                            "-C",
                            str(under(root, ROOT + "/mirror.git")),
                            "rev-parse",
                            "--verify",
                            "refs/k3dm/remote/heads/deploy/hub^{commit}",
                        ]
                    )
                    .decode()
                    .strip()
                )
                stage(target, (stamp(fmt="%Y-%m-%d") + " " + sha + "\n").encode())
            activate(target)
        if kind == "deploy-key":
            pub = directory / "deploy_key.pub"
            stage(pub, command([tools["ssh_keygen"], "-y", "-f", str(target)]))
            activate(pub)
            (directory / "deploy_key.new.pub").unlink(missing_ok=True)
            print("Register this write deploy key. Delete the old key on rotation.", pub.read_text(), file=tty_out)


def reset_state(root, clock):
    state = under(root, ROOT + "/state")
    state.rename(state.with_name("state.lost." + stamp(clock)))
    state.mkdir(mode=0o700)
    sync(state.parent)


OPS_WORD = {
    ("branch", "create"): "new",
    ("branch", "force"): "forced",
    ("branch", "update"): "fast-forward",
    ("branch", "delete"): "deleted",
    ("tag", "create"): "new",
    ("tag", "update"): "forced",
    ("tag", "delete"): "deleted",
}


def classify(kind, op, pre, expected_pre, post, target, rc, word):
    if pre == expected_pre:
        if not rc and word == OPS_WORD[kind, op] and post == target:
            return "accepted"
        if rc and word == "remote-rejected" and pre == post:
            return "rejected"
    return "inconclusive"


def probe_deploy_key(root, config, tty_in, tty_out, git=GIT, clock=None):
    mirror = str(under(root, ROOT + "/mirror.git"))
    url = config["repo_ssh"]

    def run(*args, check=True):
        return subprocess.run(
            [git, "-c", "core.hooksPath=/dev/null", "-C", mirror, *args],
            text=True,
            capture_output=True,
            check=check,
            env={
                "PATH": "/usr/bin:/bin",
                "HOME": "/var/empty",
                "GIT_CONFIG_GLOBAL": "/dev/null",
                "GIT_CONFIG_NOSYSTEM": "1",
                "GIT_SSH_COMMAND": ssh(root),
                "LC_ALL": "C",
            },
        )

    head = "refs/k3dm/remote/heads/deploy/hub"
    s, p, q = [run("rev-parse", "--verify", head + rev + "^{commit}").stdout.strip() for rev in ("", "~1", "~2")]
    branch = "refs/heads/deploy/hub-ruleset-probe"
    tag = "refs/tags/hub-promote-probe/" + stamp(clock)

    def refs(*names):
        return {ref: sha for sha, ref in (line.split() for line in run("ls-remote", url, *names).stdout.splitlines())}

    try:
        existing = refs(branch, tag)
    except (OSError, ValueError, subprocess.SubprocessError):
        return 1
    if existing:
        print(existing, file=tty_out)
        return 1

    def observe(ref):
        try:
            return refs(ref).get(ref, "absent")
        except (OSError, ValueError, subprocess.SubprocessError):
            return "unknown"

    def step(kind, op, before, target):
        ref = branch if kind == "branch" else tag
        pre = observe(ref)
        force = ["--force"] if OPS_WORD[kind, op] == "forced" else []
        result = run(
            "push", "--porcelain", *force, url, ("" if target == "absent" else target) + ":" + ref, check=False
        )
        post = observe(ref)
        word = "other"
        for line in result.stdout.splitlines():
            parts = line.split("\t")
            if len(parts) == 3 and parts[1].partition(":")[2] == ref:
                word = {"*": "new", " ": "fast-forward", "+": "forced", "-": "deleted"}.get(parts[0], "other")
                if parts[0] == "!" and parts[2].startswith("[remote rejected]"):
                    word = "remote-rejected"
        observed = classify(kind, op, pre, before, post, target, result.returncode, word)
        print("|".join(("deploy-key", kind, op, "accepted", observed, pre, post, word)), file=tty_out, flush=True)
        return observed == "accepted"

    ok = True
    try:
        for row in (
            ("branch", "create", "absent", s),
            ("branch", "force", s, p),
            ("tag", "create", "absent", s),
            ("branch", "update", p, s),
            ("tag", "update", s, p),
        ):
            ok &= step(*row)
            if row[:2] == ("tag", "create"):
                ask(tty_in, tty_out, f"Hold rows now. B={branch} T={tag} S={s} P={p} Q={q}. Press Enter to continue.")
    finally:
        for kind, before in (("branch", s), ("tag", p)):
            try:
                ok &= step(kind, "delete", before, "absent")
            except (OSError, ValueError, subprocess.SubprocessError):
                ok = False
    try:
        remaining = refs(branch, tag)
    except (OSError, ValueError, subprocess.SubprocessError):
        return 1
    if remaining:
        print(remaining, file=tty_out)
    return int(not ok or bool(remaining))


def mark_ruleset(root, tty_in, tty_out, probe_file, clock):
    raw = probe_file.read(65537)
    if isinstance(raw, str):
        raw = raw.encode()
    if len(raw) > 65536:
        raise ValueError("probe file too long")
    expected = {(c, *pair) for c in ("gh-token", "ssh-push-key", "cve-write-token", "deploy-key") for pair in OPS_WORD}
    metadata = {"2e", "inventory"}
    if any(ord(ch) < 32 and ch != "\n" or ord(ch) == 127 for ch in raw.decode()):
        raise ValueError("invalid probe file")
    for line in raw.decode().splitlines():
        if re.fullmatch(
            r"2e\|landed [0-9a-f]{7,64}\|live-verified \d{4}-\d\d-\d\d|inventory\|[^|]+\|\d{4}-\d\d-\d\d", line
        ):
            date.fromisoformat(line[-10:])
            metadata.remove(line.split("|")[0])
            continue
        cred, kind, op, want, got, pre, post, word = line.split("|")
        expected.remove((cred, kind, op))
        accepted = cred == "deploy-key"
        if (
            got != want
            or want != ("accepted" if accepted else "rejected")
            or not all(v == "absent" or re.fullmatch(OID, v) for v in (pre, post))
            or (pre == "absent") != (op == "create")
            or (accepted and (word != OPS_WORD[kind, op] or (post == "absent") != (op == "delete") or post == pre))
            or (not accepted and (pre != post or word != "remote-rejected"))
        ):
            raise ValueError("inconsistent probe row")
    if expected or metadata:
        raise ValueError("incomplete probe file")
    rid = ask(tty_in, tty_out, raw.decode() + "\nRuleset ID:")
    if not re.fullmatch("[1-9][0-9]*", rid) or ask(tty_in, tty_out, "Type yes to record:") != "yes":
        raise ValueError("unconfirmed ruleset")
    marker = creds(root) / "ruleset-verified"
    stage(
        marker,
        json.dumps(
            dict(
                kind="operator assertion",
                asserted_on=stamp(clock, "%Y-%m-%d"),
                ruleset_id=int(rid),
                probe_sha256=hashlib.sha256(raw).hexdigest(),
            )
        ).encode(),
    )
    activate(marker)


def render_stage(directory, check):
    values = json.loads((directory / "values.json").read_bytes())
    for name in ("promote.conf", LABEL + ".plist"):
        data = render((directory / (name + ".tmpl")).read_text(), values).encode()
        if name == "promote.conf":
            parse_config(data)
        target = directory / "rendered" / name
        if check:
            if target.read_bytes() != data:
                raise ValueError("render mismatch")
            print(data.decode(), end="")
        else:
            target.write_bytes(data)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "action",
        choices=("serve", "enrol", "reset-state", "probe-deploy-key", "mark-ruleset", "render", "render-check"),
    )
    parser.add_argument("directory", nargs="?")
    parser.add_argument("--rotate", choices=("totp", "relay-key", "deploy-key", "token", "host-key"))
    args = parser.parse_args()
    if args.rotate and args.action != "enrol":
        parser.error("--rotate applies only to enrol")
    if (args.action in ("render", "render-check")) != (args.directory is not None):
        parser.error("only a render operation takes a staging directory")
    if args.action in ("render", "render-check"):
        render_stage(Path(args.directory), args.action == "render-check")
        return 0
    bootstrap("/", 0, CHAIN)
    try:
        config = load_config(CONF)
    except (OSError, ValueError):
        print(CONF, file=sys.stderr)
        return 78
    if args.action == "serve":
        serve(config, hub_approval.Engine)
    elif args.action == "reset-state":
        reset_state("/", hub_approval.SystemClock())
    else:
        with open("/dev/tty") as inp, open("/dev/tty", "w") as out:
            if args.action == "enrol":
                enrol(
                    "/",
                    config,
                    inp,
                    out,
                    {"ssh_keygen": "/usr/bin/ssh-keygen", "ssh_keyscan": "/usr/bin/ssh-keyscan"},
                    args.rotate,
                )
            elif args.action == "mark-ruleset":
                mark_ruleset("/", inp, out, sys.stdin.buffer, hub_approval.SystemClock())
            else:
                return probe_deploy_key("/", config, inp, out)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, KeyError, subprocess.SubprocessError):
        sys.exit("authority operation failed")
