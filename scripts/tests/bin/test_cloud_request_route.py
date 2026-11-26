"""Request JSON written by the CLI, captured before Git stores the blob."""

import importlib.machinery
import importlib.util
from datetime import datetime, timezone
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[3]
LOADER = importlib.machinery.SourceFileLoader("cloud_request_route", str(ROOT / "bin" / "k3dm-cloud-request"))
SPEC = importlib.util.spec_from_loader(LOADER.name, LOADER)
helper = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(helper)


@pytest.mark.parametrize("flags", [[], ["--notify-route", "testing"]])
def test_cli_route_payload(monkeypatch, tmp_path, flags):
    class Clock(datetime):
        @classmethod
        def now(cls, tz):
            return cls(2026, 11, 26, tzinfo=timezone.utc)

    blobs = []
    def git(args, **kwargs):
        if args[0] == "hash-object":
            path = Path(args[-1])
            assert path.parent == tmp_path
            blobs.append(path.read_bytes())
        return ""

    monkeypatch.setattr(helper, "ROOT", tmp_path)
    monkeypatch.setattr(helper, "_git", git)
    monkeypatch.setattr(helper, "datetime", Clock)
    assert helper.main(["make-test-all", *flags]) == 0
    route = b'"notify_route": "testing", ' if flags else b''
    assert blobs == [b'{"action": "make-test-all", "args": {}, "expires_at": "2026-11-26T00:30:00Z", ' + route
                     + b'"requested_at": "2026-11-26T00:00:00Z", "requested_by": "claude-cloud", "schema": 1}\n']


def test_cli_malformed_route_before_git(monkeypatch):
    monkeypatch.setattr(helper, "_git", lambda *_a, **_kw: pytest.fail("unexpected git call"))
    with pytest.raises(SystemExit) as exc:
        helper.main(["make-test-all", "--notify-route", "BAD!"])
    assert exc.value.code == 2
