import base64
import hashlib
import hmac
import importlib.machinery
import importlib.util
import io
import json
import os
import pty
from contextlib import contextmanager
from pathlib import Path
import socket
import sys
import tempfile
import threading

import pytest

REPO = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(REPO / "scripts/lib"))
import hub_approval
import promote_mover


def load(name, path):
    loader = importlib.machinery.SourceFileLoader(name, str(path))
    module = importlib.util.module_from_spec(importlib.util.spec_from_loader(name, loader))
    loader.exec_module(module)
    return module


d = load("daemon", REPO / "scripts/libexec/k3dm-promote-daemon.py")
d.hub_approval, d.promote_mover = hub_approval, promote_mover
SECRET = b"12345678901234567890"
KEY = bytes(range(32))
CONFIG = dict(
    operator_uid=501, operator_gid=20, operator_ids=["U0123ABCD"], repo_ssh="git@github.com:a/b.git", repo_slug="a/b"
)


@pytest.fixture
def root(monkeypatch):
    with tempfile.TemporaryDirectory(dir="/tmp") as tmp:
        p = Path(tmp)
        monkeypatch.setenv("HOME", tmp)
        assert p.resolve().parent == Path("/tmp").resolve() and Path.home() == p
        for name in ("creds", "state", "mirror.git"):
            d.under(p, d.ROOT + "/" + name).mkdir(mode=0o700, parents=True)
        for name, data in {
            "relay_hmac.key": KEY.hex().encode() + b"\n",
            "totp.secret": base64.b32encode(SECRET),
            "deploy_key": b"private",
            "primed": b"primed",
            "known_hosts": b"host",
            "read_token": b"token",
        }.items():
            target = d.creds(p) / name
            d.stage(target, data)
            d.activate(target)
        yield p


class EndServe(Exception):
    pass


def session(root, messages, uid=501, times=None, mover_factory=d.build_mover):
    path = root / "run" / "sock"
    ready = threading.Event()
    errors = []
    ownership = []
    engine_calls = []
    existing = path.parent.exists()

    class Listener(socket.socket):
        count = 0

        def listen(self, backlog):
            super().listen(backlog)
            ready.set()

        def accept(self):
            if self.count == len(messages):
                raise EndServe
            self.count += 1
            return super().accept()

    class Fs(d.RealFs):
        rundir = path.parent
        owner_uid = os.getuid()
        owner_gid = os.getgid()
        chown = staticmethod(lambda *args: ownership.append(args))

    fs = Fs()
    fs.root = root
    clock = root / "clock"
    clock.write_text("1700000040")

    def engine(directory, _, secret, ids, key):
        engine_calls.append(directory)
        return hub_approval.Engine(directory, hub_approval.FileClock(clock), secret, ids, key)

    def server():
        try:
            d.serve(
                CONFIG,
                engine,
                mover_factory=mover_factory,
                listener=Listener(socket.AF_UNIX),
                peer_uid=lambda _: uid,
                fs=fs,
                **({"monotonic": times} if times else {}),
            )
        except EndServe:
            pass
        except BaseException as exc:
            errors.append(exc)

    thread = threading.Thread(target=server, daemon=True)
    thread.start()
    assert ready.wait(3), errors
    assert path.is_socket() and path.stat().st_mode & 0o777 == 0o600
    replies = []
    for message in messages:
        if callable(message):
            message = message(replies)
        with socket.socket(socket.AF_UNIX) as conn:
            conn.settimeout(7)
            conn.connect(str(path))
            if message is not None:
                try:
                    conn.sendall(
                        message if isinstance(message, bytes) else json.dumps(dict(v=1, **message)).encode() + b"\n"
                    )
                except BrokenPipeError:
                    pass
            try:
                line = conn.makefile("rb").readline()
            except ConnectionResetError:
                line = b""
            replies.append(json.loads(line) if line else None)
    thread.join(3)
    assert not thread.is_alive() and not errors, errors
    assert ownership[-1] == (path, CONFIG["operator_uid"], CONFIG["operator_gid"])
    if not existing:
        assert ownership[0] == (path.parent, 0, 0)
    if uid != CONFIG["operator_uid"]:
        assert not engine_calls
    elif any(reply and reply["code"] == "ok" for reply in replies):
        assert engine_calls
    return replies


def test_main_reads_no_environment(root, monkeypatch):
    monkeypatch.setenv("K3DM_PROMOTE_ROOT", str(root))
    seen = []
    monkeypatch.setattr(sys, "argv", ["daemon", "serve"])
    monkeypatch.setattr(d, "bootstrap", lambda *args: seen.append(args[0]))
    monkeypatch.setattr(d, "load_config", lambda path: seen.append(path) or CONFIG)
    monkeypatch.setattr(d, "serve", lambda *args: None)
    assert d.main() == 0 and seen == ["/", d.CONF]
    for path in (REPO / "scripts/libexec/k3dm-promote-daemon.py", REPO / "bin/k3dm-promote-client"):
        assert "os.environ" not in path.read_text() and "os.getenv" not in path.read_text()


def test_wrong_peer_uid_never_reaches_engine(root):
    assert session(root, [dict(op="status")], uid=502) == [None]
    assert session(root, [dict(op="status")])[0]["data"]["configured"]


def test_stalled_client_does_not_block_next(root):
    replies = session(root, [None, dict(op="status")])
    assert [r["code"] for r in replies] == ["bad_input", "ok"]


def test_conf_rejects_non_github_repo():
    raw = b"operator_uid=501\noperator_gid=20\noperator_ids=cli\nrepo_ssh=git@github.com:a/b.git\nrepo_slug=a/b\n"
    assert d.parse_config(raw)["repo_slug"] == "a/b"
    for url in (b"file:///tmp/repo", b"/tmp/repo", b"git@other:a/b.git", b"ssh://github.com/a/b"):
        with pytest.raises(ValueError):
            d.parse_config(raw.replace(b"git@github.com:a/b.git", url))

    for url, slug in ((b"file:///x/y.git", b"x/y"), (b"/x/y.git", b"x/y"), (b"ssh://git@github.com/a/b.git", b"a/b")):
        with pytest.raises(ValueError):
            d.parse_config(raw.replace(b"git@github.com:a/b.git", url).replace(b"repo_slug=a/b", b"repo_slug=" + slug))


def test_reset_state_keeps_creds_and_mirror(root):
    base = d.under(root, d.ROOT)
    for name in ("state", "creds", "mirror.git"):
        (base / name / "sentinel").touch()
    d.reset_state(root, hub_approval.SystemClock())
    assert list(base.glob("state.lost.*/sentinel")) and not list((base / "state").iterdir())
    assert all((base / name / "sentinel").exists() for name in ("creds", "mirror.git"))


def test_configured_requires_primed(root):
    assert session(root, [dict(op="status")])[0]["data"]["configured"]
    (d.creds(root) / "primed").unlink()
    assert not session(root, [dict(op="status")])[0]["data"]["configured"]


@pytest.mark.parametrize(
    "data", [None, b"", b"A" * 64 + b"\n", b"a" * 63 + b"\n", b"a" * 66 + b"\n", b"a" * 64, b"a" * 64 + b"\n\n"]
)
def test_configured_requires_valid_relay_key(root, data):
    target = d.creds(root) / "relay_hmac.key"

    def change(_):
        target.unlink() if data is None else target.write_bytes(data)
        return dict(op="status")

    replies = session(root, [dict(op="status"), change, dict(op="promote", id="anything", sha="bad")])
    assert [r["data"]["configured"] for r in replies[:2]] == [True, False]
    assert replies[-1]["code"] == "unconfigured"


def test_socket_forged_sig_refused_uncounted(root):
    def signed(replies, key):
        (root / "clock").write_text("1700000070")
        card = replies[0]["data"]
        code = hub_approval.totp_code(SECRET, 1700000070)
        at = "1700000070"
        canonical = "\n".join(
            ("k3dm-promote-approve:v1", card["id"], card["nonce"], "U0123ABCD", card["check"], code, at, "")
        )
        return dict(
            op="approve",
            id=card["id"],
            nonce=card["nonce"],
            check=card["check"],
            approver="U0123ABCD",
            totp=code,
            at=at,
            sig=hmac.new(key, canonical.encode(), hashlib.sha256).hexdigest(),
        )

    state = d.under(root, d.ROOT + "/state")
    before = {}

    def forged(r):
        before.update({p: p.read_bytes() for p in state.glob("*.json")})
        return signed(r, bytes(32))

    def genuine(r):
        assert before == {p: p.read_bytes() for p in state.glob("*.json")}
        return signed(r, KEY)

    replies = session(
        root,
        [
            dict(op="request", sha="a" * 40, branch="k3d-manager-v1.45.0", channel="cli", requested_by="tester"),
            forged,
            genuine,
        ],
    )
    assert replies[1]["code"] == "signature" and replies[1]["data"] == {"approval": "kept"}
    assert replies[2]["code"] == "ok"


def test_probe_client_side_refusal_is_inconclusive():
    args = ("tag", "update", "S", "S", "S", "P", 1)
    assert d.classify(*args, "other") == "inconclusive"
    assert d.classify(*args, "remote-rejected") == "rejected"


def test_probe_missing_ref_is_inconclusive():
    for pre, want in (("absent", "inconclusive"), ("S", "accepted")):
        assert d.classify("branch", "delete", pre, "S", "absent", "absent", 0, "deleted") == want


def probe_file():
    rows = []
    for cred in ("deploy-key", "ssh-push-key", "gh-token", "cve-write-token"):
        for (kind, op), word in d.OPS_WORD.items():
            pre = "absent" if op == "create" else "a" * 40
            post = "absent" if op == "delete" else "b" * 40
            result = "accepted" if cred == "deploy-key" else "rejected"
            if result == "rejected":
                post, word = pre, "remote-rejected"
            rows.append("|".join((cred, kind, op, result, result, pre, post, word)))
    return "\n".join(rows + ["2e|landed d1ec381c|live-verified 2026-11-20", "inventory|howto|2026-11-20"]) + "\n"


def mark(root, data):
    d.mark_ruleset(
        root, io.StringIO("123\nyes\n"), io.StringIO(), io.BytesIO(data.encode()), hub_approval.SystemClock()
    )


def test_mark_ruleset_refuses_incomplete_file(root):
    data = probe_file()
    with pytest.raises(ValueError):
        mark(root, data.partition("\n")[2])
    assert not (d.creds(root) / "ruleset-verified").exists()
    mark(root, data)
    assert json.loads((d.creds(root) / "ruleset-verified").read_bytes())["ruleset_id"] == 123


def test_mark_ruleset_refuses_inconsistent_rows(root):
    data = probe_file()
    with pytest.raises(ValueError):
        mark(root, data.replace("|new\n", "|other\n", 1))
    mark(root, data)


@contextmanager
def console(answers):
    master, slave = pty.openpty()
    with os.fdopen(slave, "r") as inp, os.fdopen(os.dup(slave), "w", buffering=1) as out:
        try:
            assert inp.isatty() and out.isatty()
            os.write(master, answers.encode())

            def read():
                import select

                chunks = []
                out.flush()
                while select.select([master], [], [], 0.05)[0]:
                    chunks.append(os.read(master, 8192))
                return b"".join(chunks).decode()

            yield inp, out, read
        finally:
            os.close(master)


def test_enrol_relay_key_only_on_tty(root, monkeypatch, capsys, caplog):
    caplog.set_level("DEBUG")
    key = bytes(reversed(range(32)))
    calls = []

    def record(argv):
        calls.append(list(argv))
        return b"public-key\n"

    monkeypatch.setattr(d, "command", record)
    directory = d.creds(root)
    d.stage(directory / "deploy_key.pub", b"public-key\n")
    d.activate(directory / "deploy_key.pub")
    other = {path: path.read_bytes() for path in directory.iterdir() if path.name != "relay_hmac.key"}
    with console("\n") as (inp, out, read):
        d.enrol(root, CONFIG, inp, out, {"ssh_keygen": "stub"}, "relay-key", urandom=lambda _: key)
        display = read()
    assert display.count(key.hex()) == 1 and "\033[3J" in display
    assert (d.creds(root) / "relay_hmac.key").read_bytes() == key.hex().encode() + b"\n"
    assert calls and key.hex() not in repr(calls)
    assert key.hex() not in "".join(capsys.readouterr()) + caplog.text
    assert other == {path: path.read_bytes() for path in directory.iterdir() if path.name != "relay_hmac.key"}
    for path in root.rglob("*"):
        if path.is_file() and path != directory / "relay_hmac.key":
            assert key.hex().encode() not in path.read_bytes()


@pytest.mark.skipif(sys.platform != "darwin", reason="LOCAL_PEERCRED requires Darwin")
def test_local_peercred():
    left, right = socket.socketpair()
    with left, right:
        assert d.local_peercred_uid(left) == os.getuid()


def client_call(monkeypatch, args, fields):
    c = load("client", REPO / "bin/k3dm-promote-client")
    captured = []

    def exchange(path, request):
        captured.append(request)
        return dict(v=1, code="signature", result="refused", data={"approval": "kept"}, message="signature")

    monkeypatch.setattr(c, "exchange", exchange)
    out, err = io.StringIO(), io.StringIO()
    rc = c.run(args, io.StringIO(json.dumps(fields)), out, err)
    return rc, captured, out.getvalue(), err.getvalue()


def test_client_forwards_envelope_unchanged(root, monkeypatch):
    fields = dict(id="id", sig=" OddCase ", check="Check", nonce="nonce", totp="123456", at=" at ", approver="caller")
    rc, captured, _, err = client_call(monkeypatch, ["approve"], fields)
    assert rc == 1 and captured == [dict(v=1, op="approve", **fields)] and fields["sig"] not in err


def test_client_secrets_never_in_argv(root, monkeypatch):
    fields = dict(id="id", nonce="private-nonce", approver="caller", check="abcd", totp="123456", at="123", sig="sig")
    assert client_call(monkeypatch, ["approve"], fields)[1][0]["nonce"] == fields["nonce"]
    rc, captured, out, err = client_call(monkeypatch, ["approve", "--nonce", fields["nonce"]], fields)
    assert rc == 2 and not captured and not out and fields["nonce"] not in err


def test_request_parser_and_status_audit(root):
    bad = [
        b"x" * 4097,
        b"\xff\n",
        b"[]\n",
        b"{\n",
        b'{"op":"status","v":true}\n',
        dict(op="request"),
        dict(op="status", extra=""),
        dict(op="show", id=3),
    ]
    bad += [
        dict(op=name)
        for name in (
            "begin_promote",
            "authorize_push",
            "consume",
            "refuse",
            "finish_unmoved",
            "commit_moved",
            "outcome",
            "note_refusal",
        )
    ]
    replies = session(
        root,
        bad
        + [
            dict(op="request", sha="a" * 40, branch="k3d-manager-v1.45.0", channel="cli", requested_by="operator"),
            lambda r: dict(op="show", id=r[-1]["data"]["id"]),
            dict(op="status"),
        ],
    )
    assert all(r["code"] == "bad_input" for r in replies[:-3])
    card, shown, status = [r["data"] for r in replies[-3:]]
    assert shown["check"] == card["check"] and card["nonce"] not in json.dumps([shown, status])
    assert set(status) == set("daemon configured pending state ruleset audit".split())
    assert status["pending"] == 1 and status["audit"][-1]["id"] is None
    d.under(root, d.ROOT + "/state/serial.json").unlink()
    assert session(root, [dict(op="status")])[0]["data"]["state"] == "lost"


def test_bootstrap_chain_and_socket_mode(root):
    import shutil

    paths = set(d.CHAIN)
    files = {d.PY, d.FRAME, d.FRAME + ".9", d.CONF, *(d.LIBEXEC + "/" + m for m in d.MODULES)}
    for name in sorted(paths - files):
        d.under(root, name).mkdir(exist_ok=True, parents=True)
    for name in files:
        target = d.under(root, name)
        if name in d.LINKS:
            target.symlink_to(d.LINKS[name])
        else:
            target.touch()
    for name in ("hub_approval.py", "promote_mover.py"):
        shutil.copy(REPO / "scripts/lib" / name, d.under(root, d.LIBEXEC))
    old_path = sys.path[:]
    try:
        d.bootstrap(root, os.getuid(), d.CHAIN)
        assert sys.path[0] == str(d.under(root, d.LIBEXEC))
    finally:
        sys.path[:] = old_path
    for name in paths - set(d.LINKS):
        target = d.under(root, name)
        mode = target.stat().st_mode
        target.chmod(mode | 0o020)
        with pytest.raises(SystemExit) as failure:
            d.integrity(root, os.getuid(), d.CHAIN)
        assert failure.value.code == 78
        target.chmod(mode)
    run = root / "run"
    run.mkdir(mode=0o700)
    (run / "marker").touch()
    session(root, [dict(op="status")])
    assert list(root.glob("run.bad.*/marker")) and run.stat().st_mode & 0o777 == 0o755


def test_probe_operations_on_bare_origin(root, monkeypatch):
    import shutil
    import subprocess

    mirror = d.under(root, d.ROOT + "/mirror.git")
    origin = root / "origin.git"
    git = shutil.which("git")
    assert mirror.is_dir() and origin.parent == root

    def local(*args, data=None):
        return subprocess.run(
            [
                git,
                "-C",
                str(mirror),
                "-c",
                "user.name=Fixture",
                "-c",
                "user.email=test@example.invalid",
                *map(str, args),
            ],
            input=data,
            capture_output=True,
            text=True,
            check=True,
        ).stdout.strip()

    local("init", "--bare", "-q")
    local("init", "--bare", "-q", origin)
    tree = local("mktree", data="")
    commits = []
    for i in range(3):
        commits.append(local("commit-tree", tree, *(["-p", commits[-1]] if commits else []), data=f"{i}\n"))
    conf = dict(CONFIG, repo_ssh=str(origin))
    head = "refs/k3dm/remote/heads/deploy/hub"
    local("update-ref", head, commits[1])
    calls = []
    real = subprocess.run

    def recording(argv, **kwargs):
        if "push" in argv:
            calls.append(argv)
        return real(argv, **kwargs)

    monkeypatch.setattr(subprocess, "run", recording)

    def probe():
        text = io.StringIO()
        rc = d.probe_deploy_key(root, conf, io.StringIO("\n"), text, git=git)
        return rc, [line.split("|") for line in text.getvalue().splitlines() if line.startswith("deploy-key|")]

    with pytest.raises(subprocess.CalledProcessError):
        probe()
    assert not calls
    local("update-ref", head, commits[2])
    rc, rows = probe()
    assert rc == 0 and len(calls) == len(rows) == 7
    assert [r[-1] for r in rows] == ["new", "forced", "new", "fast-forward", "forced", "deleted", "deleted"]
    assert all("--atomic" not in argv and len([a for a in argv if ":refs/" in a]) == 1 for argv in calls)
    assert local("ls-remote", origin) == ""
    calls.clear()

    def lost_observation(argv, **kwargs):
        if "ls-remote" in argv and len(calls) == 1:
            raise subprocess.CalledProcessError(128, argv)
        return recording(argv, **kwargs)

    monkeypatch.setattr(subprocess, "run", lost_observation)
    rc, rows = probe()
    assert rc == 1 and rows[0][4] == "inconclusive"
    assert len(calls) == 7 and [r[2:5] for r in rows[-2:]] == [["delete", "accepted", "accepted"]] * 2
    assert local("ls-remote", origin) == ""
    monkeypatch.setattr(subprocess, "run", recording)
    hook = origin / "hooks/pre-receive"
    hook.write_text("#!/bin/sh\nexit 1\n")
    hook.chmod(0o755)
    rc, rows = probe()
    assert rc == 1 and len(rows) == 7 and rows[0][4:] == ["rejected", "absent", "absent", "remote-rejected"]
    assert rows[-1][4] == "inconclusive"


@pytest.mark.parametrize(
    "alter,expected",
    [
        ({"sig": ""}, "signature"),
        ({"sig": "f" * 63}, "signature"),
        ({"sig": "f" * 65}, "signature"),
        ({"sig": "F" * 64}, "signature"),
        ({"sig": "z" * 64}, "signature"),
        ({"check": "ZZZZ"}, "signature"),
        ({"id": "p999-1234abcd"}, "signature"),
        ({"delta": -301}, "envelope_stale"),
        ({"delta": 121}, "envelope_stale"),
        ({"wrong_code": True}, "totp"),
        ({"bad_check": True}, "check"),
    ],
)
def test_signed_envelope_refusals(root, alter, expected):
    def mac(fields):
        payload = "\n".join(
            ["k3dm-promote-approve:v1", *[fields[k] for k in ("id", "nonce", "approver", "check", "totp", "at")], ""]
        )
        return hmac.new(KEY, payload.encode(), hashlib.sha256).hexdigest()

    assert (
        mac(
            dict(
                id="p1-0123abcd",
                nonce="00112233aabbccdd",
                approver="U0123ABCD",
                check="03Q1",
                totp="287082",
                at="1700000059",
            )
        )
        == "5f45ca7b5b3724c6b0d50e0600af206effbb5669d2fb86b530d9ba913d5d572e"
    )

    def attempt(replies):
        card = replies[0]["data"]
        now = 1700000070
        (root / "clock").write_text(str(now))
        fields = dict(
            op="approve",
            id=card["id"],
            nonce=card["nonce"],
            approver="U0123ABCD",
            check=card["check"],
            at=str(now + alter.get("delta", 0)),
            totp=hub_approval.totp_code(SECRET, now),
        )
        if alter.get("wrong_code"):
            fields["totp"] = "000000"
        if alter.get("bad_check"):
            fields["check"] = "ZZZZ"
        fields["sig"] = mac(fields)
        fields.update({k: v for k, v in alter.items() if k in fields})
        return fields

    replies = session(
        root,
        [
            dict(op="request", sha="a" * 40, branch="k3d-manager-v1.45.0", channel="cli", requested_by="operator"),
            attempt,
        ],
    )
    assert replies[1]["code"] == expected and replies[1]["data"] == {"approval": "kept"}
    state = d.under(root, d.ROOT + "/state")
    count = int(expected in ("check", "totp"))
    assert json.loads((state / (replies[0]["data"]["id"] + ".json")).read_bytes())["failed_attempts"] == count
    assert json.loads((state / "totp-state.json").read_bytes())["fail_count"] == count


@pytest.mark.parametrize(
    "reply,code",
    [
        ({"v": True}, "protocol"),
        ({"code": "bogus"}, "protocol"),
        ({"result": "refused", "code": "signature", "data": {}}, "protocol"),
        ({"result": "unknown", "code": "io", "data": {"extra": 0}}, "protocol"),
        ({"data": {"new": "0" * 40}}, "protocol"),
        ({"message": "x\ny"}, "protocol"),
        ({}, "ok"),
    ],
)
def test_client_reply_validation(root, monkeypatch, reply, code):
    c = load("client", REPO / "bin/k3dm-promote-client")
    sha = "a" * 40
    base = dict(
        v=1,
        result="ok",
        code="ok",
        message="ok",
        data=dict(new=sha, old="b" * 40, outcome="moved", tag="hub-promote/20261120T000000Z"),
    )
    monkeypatch.setattr(c, "exchange", lambda *_: dict(base, **reply))
    out = io.StringIO()
    rc = c.run(["promote", "--id", "p1-1234abcd", "--sha", sha], io.StringIO(), out, io.StringIO())
    assert rc == (0 if code == "ok" else 75) and json.loads(out.getvalue())["code"] == code


@pytest.mark.parametrize("mode", ["scripted", "pages", "during_push"])
def test_promote_deadline_through_socket(root, mode):
    import shutil
    import subprocess

    origin = root / "origin.git"
    mirror = d.under(root, d.ROOT + "/mirror.git")
    git = shutil.which("git")
    assert origin.parent == root and mirror.is_dir()

    def local(*args, data=None):
        return subprocess.run(
            [git, "-c", "user.name=Fixture", "-c", "user.email=test@example.invalid", "-C", str(origin), *args],
            input=data,
            text=True,
            capture_output=True,
            check=True,
        ).stdout.strip()

    origin.mkdir()
    local("init", "--bare", "-q")
    tree = local("mktree", data="")
    old = local("commit-tree", tree, data="old")
    new = local("commit-tree", tree, "-p", old, data="new")
    branch = "k3d-manager-v1.45.0"
    deploy = "refs/heads/deploy/hub"
    local("update-ref", deploy, old)
    local("update-ref", "refs/heads/" + branch, new)
    now = [200.0]
    pages = []

    class Api(promote_mover.CurlApi):
        def get(self, path, timeout):
            pages.append(path)
            if mode == "pages":
                now[0] += 121
                return 200, {"check_runs": [{"status": "completed", "conclusion": "success"}] * 100, "total_count": 101}
            if "check-runs" in path:
                return 200, {"check_runs": [{"status": "completed", "conclusion": "success"}], "total_count": 1}
            return 200, []

    class Mover(promote_mover.Mover):
        def move(self, id, sha, record_branch, authorize, deadline):
            assert record_branch == branch and deadline == now[0] + 120
            if mode == "scripted":
                now[0] += 121
                self._timeout(deadline, 60)
            return super().move(id, sha, record_branch, authorize, deadline)

        def _git(self, args, *rest, **kwargs):
            if mode == "during_push" and "push" in args:
                now[0] += 121
            return super()._git(args, *rest, **kwargs)

    def factory(conf, base):
        assert base == root and conf == CONFIG
        return Mover(
            str(origin), "a/b", Api("unused"), "", str(mirror), hub_approval.SystemClock(), lambda: now[0], git
        )

    def approve(replies):
        card = replies[0]["data"]
        at = "1700000070"
        (root / "clock").write_text(at)
        code = hub_approval.totp_code(SECRET, int(at))
        sig = hub_approval.approval_mac(KEY, card["id"], card["nonce"], "U0123ABCD", card["check"], code, at)
        return dict(
            op="approve",
            id=card["id"],
            nonce=card["nonce"],
            approver="U0123ABCD",
            check=card["check"],
            totp=code,
            at=at,
            sig=sig,
        )

    replies = session(
        root,
        [
            dict(op="request", sha=new, branch=branch, channel="cli", requested_by="operator"),
            approve,
            lambda r: dict(op="promote", id=r[0]["data"]["id"], sha=new),
            lambda r: dict(op="show", id=r[0]["data"]["id"]),
        ],
        times=lambda: now[0],
        mover_factory=factory,
    )
    if mode == "during_push":
        assert replies[2]["code"] == "ok" and local("rev-parse", deploy) == new
        assert replies[3]["data"]["state"] == "consumed"
    else:
        assert replies[2]["code"] == "deadline" and local("rev-parse", deploy) == old
        assert replies[3]["data"]["state"] == "approved" and replies[3]["data"]["push_at"] is None
        if mode == "pages":
            assert len(pages) == 1


@pytest.mark.parametrize("bad", ["owner", "mode", "symlink"])
def test_unsafe_credential_refuses_mutation(root, bad):
    target = d.creds(root) / "read_token"
    assert d.secrets(root, os.getuid()) == (SECRET, KEY)
    owner = os.getuid()
    if bad == "owner":
        owner += 1
    elif bad == "mode":
        target.chmod(0o620)
    else:
        original = target.with_suffix(".original")
        target.rename(original)
        target.symlink_to(original)
    assert d.secrets(root, owner) == (None, None)


@pytest.mark.parametrize("missing", ["totp.secret", "deploy_key", "known_hosts", "read_token", "short_totp"])
def test_unconfigured_show_and_mutations(root, missing):
    req = dict(op="request", sha="a" * 40, branch="k3d-manager-v1.45.0", channel="cli", requested_by="operator")
    card = session(root, [req])[0]["data"]
    if missing == "short_totp":
        (d.creds(root) / "totp.secret").write_bytes(base64.b32encode(b"short"))
    else:
        (d.creds(root) / missing).unlink()
    denied = dict(op="deny", id=card["id"], nonce=card["nonce"], approver="U0123ABCD")
    approved = dict(denied, op="approve", check=card["check"], at="", sig="", totp="")
    results = session(
        root,
        [
            req,
            denied,
            approved,
            dict(op="promote", id=card["id"], sha=req["sha"]),
            dict(op="show", id=card["id"]),
            dict(op="status"),
        ],
        mover_factory=lambda *_: pytest.fail("unconfigured mover constructed"),
    )
    assert all(r["code"] == "unconfigured" for r in results[:4])
    assert results[4]["data"]["state"] == "pending" and not results[5]["data"]["configured"]


def test_mover_configuration(root):
    mover = d.build_mover(CONFIG, root)
    assert mover.repo_url == CONFIG["repo_ssh"] and mover.repo_slug == CONFIG["repo_slug"]
    assert mover.workdir == str(d.under(root, d.ROOT + "/mirror.git"))
    assert Path(mover.api.token_path) == d.creds(root) / "read_token"
    assert mover.ssh_command == (
        f"/usr/bin/ssh -F /dev/null -i {d.creds(root)}/deploy_key -o IdentitiesOnly=yes "
        f"-o UserKnownHostsFile={d.creds(root)}/known_hosts -o StrictHostKeyChecking=yes -o BatchMode=yes"
    )


@pytest.mark.parametrize(
    "interrupt", ["totp.secret", "relay_hmac.key", "deploy_key", "read_token", "known_hosts", "primed"]
)
def test_interrupted_enrol_resumes(root, monkeypatch, interrupt):
    directory = d.creds(root)
    for path in directory.iterdir():
        path.unlink()
    tools = {"ssh_keygen": "keygen", "ssh_keyscan": "keyscan", "git": "git"}
    calls = []
    tokens = ("fixture_token", KEY.hex(), base64.b32encode(SECRET).decode())

    def stub(argv):
        calls.append(list(argv))
        assert all(s not in str(argv) for s in tokens)
        if "-q" in argv:
            dest = Path(argv[-1])
            assert dest == directory / "deploy_key.new"
            dest.write_bytes(b"private")
            dest.with_suffix(".new.pub").write_bytes(b"public")
        if "-y" in argv:
            return b"public"
        if argv[0] == "keyscan":
            return b"github.com ssh-ed25519 fixture"
        if argv[0] == "git":
            return b"c" * 40
        return b"fingerprint"

    monkeypatch.setattr(d, "command", stub)

    class FirstFetch:
        def prime(self):
            assert not (directory / "primed").exists()

    def run(answers, rotate=None):
        with console(answers) as (inp, out, read):
            d.enrol(
                root,
                CONFIG,
                inp,
                out,
                tools,
                rotate=rotate,
                mover_factory=lambda *_: FirstFetch(),
                urandom=lambda size: SECRET if size == 20 else KEY,
            )
            return read()

    activate = d.activate

    def fail(target):
        if target.name == interrupt:
            raise InterruptedError
        activate(target)

    monkeypatch.setattr(d, "activate", fail)
    with pytest.raises(InterruptedError):
        run("\n\nfixture_token\nyes\n")
    assert not (directory / interrupt).exists()
    assert not (directory / "primed").exists()
    monkeypatch.setattr(d, "activate", activate)
    (directory / (interrupt + ".new")).write_bytes(b"ignored leftover")
    answers = "".join(
        reply
        for name, reply in (
            ("totp.secret", "\n"),
            ("relay_hmac.key", "\n"),
            ("read_token", "fixture_token\n"),
            ("known_hosts", "yes\n"),
        )
        if not (directory / name).exists()
    )
    run(answers)
    assert d.secrets(root, os.getuid()) == (SECRET, KEY)
    assert (directory / "deploy_key.pub").read_bytes() == b"public"
    assert all(p.stat().st_mode & 0o777 == 0o600 for p in directory.iterdir())
    for rotation, answers in (
        ("token", "replacement\n"),
        ("deploy-key", ""),
        ("host-key", "yes\n"),
        ("relay-key", "\n"),
        ("totp", "\n"),
    ):
        calls.clear()
        run(answers, rotation)
        assert any(a[0] == "git" for a in calls) == (rotation in ("token", "deploy-key", "host-key"))


@pytest.mark.parametrize("sig", ["", "ABCDEF", " padded signature "])
def test_client_socket_transport(root, sig):
    c = load("client", REPO / "bin/k3dm-promote-client")
    fields = dict(id="id", nonce="secret_nonce", approver="AB", totp="123456", at=" 001 ", check="01A1", sig=sig)
    path = root / "client.sock"
    received = []
    with socket.socket(socket.AF_UNIX) as server:
        server.bind(str(path))
        server.listen(1)
        assert path.is_socket() and path.parent == root

        def reply():
            conn, _ = server.accept()
            with conn, conn.makefile("rb") as stream:
                received.append(json.loads(stream.readline()))
                conn.sendall(
                    b'{"v":1,"result":"refused","code":"envelope_stale","message":"stale","data":{"approval":"kept"}}\n'
                )

        thread = threading.Thread(target=reply, daemon=True)
        thread.start()
        out, err = io.StringIO(), io.StringIO()
        rc = c.run(["--socket", str(path), "approve"], io.StringIO(json.dumps(fields)), out, err)
        thread.join(2)
    assert rc == 1 and received == [dict(v=1, op="approve", **fields)]
    assert json.loads(out.getvalue())["code"] == "envelope_stale" and err.getvalue() == "stale\n"
    for invalid in (
        dict(fields, extra=""),
        {k: v for k, v in fields.items() if k != "at"},
        {k: v for k, v in fields.items() if k != "sig"},
        dict(fields, totp=123456),
    ):
        out = io.StringIO()
        assert c.run(["--socket", str(path), "approve"], io.StringIO(json.dumps(invalid)), out, io.StringIO()) == 2
        assert not out.getvalue()
    out = io.StringIO()
    assert c.run(["--socket", str(path), "status"], io.StringIO(), out, io.StringIO()) == 75
    assert json.loads(out.getvalue())["code"] == "unreachable"


def test_stale_card_and_relay_rotation(root, monkeypatch):
    state = d.under(root, d.ROOT + "/state")
    req = dict(op="request", sha="a" * 40, branch="k3d-manager-v1.45.0", channel="cli", requested_by="operator")
    replacement = bytes(reversed(KEY))

    def sign(card, key):
        now = "1700000070"
        code = hub_approval.totp_code(SECRET, int(now))
        return dict(
            op="approve",
            id=card["id"],
            nonce=card["nonce"],
            approver="U0123ABCD",
            check=card["check"],
            totp=code,
            at=now,
            sig=hub_approval.approval_mac(key, card["id"], card["nonce"], "U0123ABCD", card["check"], code, now),
        )

    def rotate(replies):
        monkeypatch.setattr(d, "command", lambda *_: b"public")
        with console("\n") as (inp, out, _):
            d.enrol(root, CONFIG, inp, out, {"ssh_keygen": "keygen"}, "relay-key", urandom=lambda _: replacement)
        return sign(replies[2]["data"], KEY)

    def stale(r):
        (root / "clock").write_text("1700000070")
        return sign(r[0]["data"], KEY)

    replies = session(
        root,
        [
            req,
            lambda r: dict(op="deny", id=r[0]["data"]["id"], nonce=r[0]["data"]["nonce"], approver="U0123ABCD"),
            req,
            stale,
            rotate,
            lambda r: sign(r[2]["data"], replacement),
        ],
    )
    assert [r["code"] for r in replies] == ["ok", "ok", "ok", "not_pending", "signature", "ok"]
    # Part 2a reports the disposition of the denied card itself.
    assert replies[3]["data"] == {"approval": "final"}
    assert json.loads((state / (replies[2]["data"]["id"] + ".json")).read_bytes())["failed_attempts"] == 0


@pytest.mark.parametrize(
    "mutation",
    [
        lambda s: s.replace(b"operator_gid=20", b"operator_gid=0"),
        lambda s: s.replace(b"operator_uid=501", b"operator_uid=-1"),
        lambda s: s.replace(b"operator_ids=cli", b"operator_ids=cli, bad"),
        lambda s: s.replace(b"repo_slug=a/b", b"repo_slug=b/a"),
        lambda s: s.replace(b"repo_slug=a/b\n", b""),
        lambda s: s + b"extra=x\n",
        lambda s: s + b"operator_gid=20\n",
        lambda s: s + b"\n",
        lambda s: s + b"#comment\n",
        lambda s: s.replace(b"\n", b"\r\n"),
        lambda s: s.rstrip(),
        lambda s: s + b"x" * 4096,
    ],
)
def test_config_grammar(mutation):
    raw = b"operator_uid=501\noperator_gid=20\noperator_ids=cli\nrepo_ssh=git@github.com:a/b.git\nrepo_slug=a/b\n"
    assert d.parse_config(raw)["operator_ids"] == ["cli"]
    with pytest.raises(ValueError):
        d.parse_config(mutation(raw))


def test_probe_handle_leftover_and_deleted_ref(root, monkeypatch):
    import shutil
    import subprocess

    mirror = d.under(root, d.ROOT + "/mirror.git")
    origin = root / "origin.git"
    git = shutil.which("git")
    assert mirror.is_dir() and origin.parent == root

    def local(*args, data=None):
        return subprocess.run(
            [
                git,
                "-C",
                str(mirror),
                "-c",
                "user.name=Fixture",
                "-c",
                "user.email=test@example.invalid",
                *map(str, args),
            ],
            input=data,
            capture_output=True,
            text=True,
            check=True,
        ).stdout.strip()

    local("init", "--bare", "-q")
    local("init", "--bare", "-q", origin)
    tree = local("mktree", data="")
    sha = local("commit-tree", tree, data="base")
    for message in ("next", "last"):
        sha = local("commit-tree", tree, "-p", sha, data=message)
    local("update-ref", "refs/k3dm/remote/heads/deploy/hub", sha)
    branch = "refs/heads/deploy/hub-ruleset-probe"
    local("push", str(origin), sha + ":" + branch)
    original = subprocess.run
    pushes = []

    def recording(argv, **kwargs):
        if "push" in argv:
            pushes.append(argv)
        # Step 5 updated the tag. Delete the branch as another principal just
        # before the subsequent ls-remote checks it for step 6.
        if len(pushes) == 5 and "ls-remote" in argv and argv[-1] == branch:
            original([git, "-C", str(origin), "update-ref", "-d", branch], check=True)
        return original(argv, **kwargs)

    monkeypatch.setattr(subprocess, "run", recording)

    def probe():
        with console("\n") as (inp, out, read):
            rc = d.probe_deploy_key(root, dict(CONFIG, repo_ssh=str(origin)), inp, out, git)
            return rc, read()

    assert probe()[0] == 1 and not pushes
    local("-C", str(origin), "update-ref", "-d", branch)
    rc, rows = probe()
    assert rc == 1 and len(pushes) == 7 and "branch|delete|accepted|inconclusive|absent|absent|" in rows
    assert local("ls-remote", str(origin)) == ""


@pytest.mark.parametrize(
    "alter",
    [
        lambda r: dict(r, pre="a" * 40),
        lambda r: dict(r, post="absent"),
        lambda r: dict(r, observed="rejected"),
        lambda r: dict(r, porcelain="remote-rejected"),
        lambda r: dict(r, expected="inconclusive"),
    ],
)
def test_mark_ruleset_evidence_consistency(root, alter):
    lines = probe_file().splitlines()
    keys = "credential ref operation expected observed pre post porcelain".split()
    row = alter(dict(zip(keys, lines[0].split("|"))))
    lines[0] = "|".join(row[k] for k in keys)
    with pytest.raises(ValueError):
        mark(root, "\n".join(lines))
    assert not (d.creds(root) / "ruleset-verified").exists()
    mark(root, probe_file())


def test_status_rotated_audit_and_effective_redaction(root):
    card = session(
        root, [dict(op="request", sha="a" * 40, branch="k3d-manager-v1.45.0", channel="cli", requested_by="operator")]
    )[0]["data"]
    state = d.under(root, d.ROOT + "/state")
    request_line = json.loads((state / "audit.jsonl").read_bytes())
    for name, indexes in (("audit.1.jsonl", range(12)), ("audit.jsonl", range(12, 15))):
        with (state / name).open("w") as log:
            for i in indexes:
                print(json.dumps(dict(request_line, actor=str(i))), file=log)
    result = session(root, [dict(op="status")])[0]["data"]
    assert [row["actor"] for row in result["audit"]] == list(map(str, range(5, 15)))
    assert all(row["id"] is None for row in result["audit"])
    assert card["nonce"] not in json.dumps(result)


def test_console_failure_preserves_active_host_key_and_prime_retry(root, monkeypatch):
    directory = d.creds(root)
    active = (directory / "known_hosts").read_bytes()
    monkeypatch.setattr(d, "command", lambda argv: b"c" * 40 if argv[0] == "git" else b"new-public-data")
    tools = dict(ssh_keygen="keygen", ssh_keyscan="scan", git="git")

    class Prime:
        attempts = 0

        def prime(self):
            self.attempts += 1
            if self.attempts == 1:
                raise OSError("fixture fetch failed")

    prime = Prime()
    with console("no\n") as (inp, out, _):
        with pytest.raises(ValueError, match="host key unconfirmed"):
            d.enrol(root, CONFIG, inp, out, tools, "host-key", lambda *_: prime)
    assert (directory / "known_hosts").read_bytes() == active
    assert not (directory / "known_hosts.new").exists() and not (directory / "primed").exists()
    with console("yes\n") as (inp, out, _):
        with pytest.raises(OSError, match="fixture fetch"):
            d.enrol(root, CONFIG, inp, out, tools, "host-key", lambda *_: prime)
    assert not (directory / "primed").exists()
    with console("") as (inp, out, _):
        d.enrol(root, CONFIG, inp, out, tools, mover_factory=lambda *_: prime)
    assert prime.attempts == 2 and (directory / "primed").read_text().endswith(" " + "c" * 40 + "\n")


@pytest.mark.parametrize("operation,wait", [("promote", 240), ("status", 15)])
def test_client_timeouts_and_empty_reply(root, monkeypatch, operation, wait):
    client = load("client", REPO / "bin/k3dm-promote-client")
    path = str(root / "fixture.sock")
    limits = []

    class SocketDouble:
        def __init__(self, *_):
            pass

        def __enter__(self):
            return self

        def __exit__(self, *_):
            pass

        def connect(self, address):
            assert address == path

        def settimeout(self, timeout):
            limits.append(timeout)

        def sendall(self, data):
            assert json.loads(data)["op"] == operation

        def recv(self, limit):
            assert 0 < limit <= 65536
            if empty:
                return b""
            raise TimeoutError

    monkeypatch.setattr(client.socket, "socket", SocketDouble)
    cmd = ["--socket", path, operation]
    if operation == "promote":
        cmd += ["--id", "p1-1234abcd", "--sha", "a" * 40]
    for empty in (False, True):
        limits.clear()
        out = io.StringIO()
        assert client.run(cmd, io.StringIO(), out, io.StringIO()) == 75
        assert json.loads(out.getvalue())["code"] == "unreachable"
        assert limits[0] == 5 and wait - 1 < limits[1] <= wait


def test_integrity_refuses_acl(root, monkeypatch):
    target = root / "installed"
    target.touch()
    d.integrity(root, os.getuid(), ["/installed"])
    if sys.platform == "darwin":
        d.subprocess.run(["/bin/chmod", "+a", "everyone allow read", str(target)], check=True)
    else:
        monkeypatch.setattr(os, "listxattr", lambda *args, **kwargs: ["system.posix_acl_access"])
    with pytest.raises(SystemExit) as failure:
        d.integrity(root, os.getuid(), ["/installed"])
    assert failure.value.code == 78


def test_multiline_mover_error_is_valid_reply(root):
    error = (
        "fatal: Could not read from remote repository.\n\nPlease make sure you have the correct access rights\nand the repository exists. "
        + "x" * 1024
    )

    def failed_mover(*args):
        raise hub_approval.Unknown("lookup_failed", error)

    request = dict(op="promote", id="p1-1234abcd", sha="a" * 40)
    (reply,) = session(root, [request], mover_factory=failed_mover)
    assert reply["code"] == "lookup_failed" and reply["message"] == " ".join(error.split())[:1024]
    client = load("client", REPO / "bin/k3dm-promote-client")
    assert client.valid(reply, request)
