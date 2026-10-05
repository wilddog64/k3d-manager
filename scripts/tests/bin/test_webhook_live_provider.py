import importlib.machinery
import importlib.util
from pathlib import Path

import pytest


ROOT = Path(__file__).resolve().parents[3]
SOURCE = ROOT / "bin" / "k3dm-webhook"
SPEC = importlib.util.spec_from_loader(
    "k3dm_webhook_live_provider_test",
    importlib.machinery.SourceFileLoader("k3dm_webhook_live_provider_test", str(SOURCE)),
)
WEBHOOK = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(WEBHOOK)


@pytest.fixture(autouse=True)
def reset_live_provider_cache(monkeypatch):
    WEBHOOK._LIVE_PROVIDER_CACHE = {"at": 0.0, "marker": None, "provider": None}
    monkeypatch.delenv("CLUSTER_PROVIDER", raising=False)
    monkeypatch.delenv("K3D_MANAGER_CLUSTER_PROVIDER", raising=False)


def test_marker_aws_only_hostinger_reachable(monkeypatch, tmp_path):
    marker = tmp_path / "active-provider"
    marker.write_text("k3s-aws\n")
    monkeypatch.setattr(WEBHOOK, "_ACTIVE_PROVIDER_FILE", marker)
    monkeypatch.setattr(WEBHOOK, "_context_reachable", lambda ctx: ctx == "ubuntu-hostinger")
    assert WEBHOOK._resolve_provider() == "k3s-hostinger"


def test_marker_aws_reachable_is_probed_first(monkeypatch, tmp_path):
    marker = tmp_path / "active-provider"
    marker.write_text("k3s-aws\n")
    calls = []
    monkeypatch.setattr(WEBHOOK, "_ACTIVE_PROVIDER_FILE", marker)
    monkeypatch.setattr(WEBHOOK, "_context_reachable", lambda ctx: calls.append(ctx) or ctx == "ubuntu-k3s")
    assert WEBHOOK._resolve_provider() == "k3s-aws"
    assert calls[0] == "ubuntu-k3s"


def test_marker_aws_falls_back_to_marker_when_nothing_reachable(monkeypatch, tmp_path):
    marker = tmp_path / "active-provider"
    marker.write_text("k3s-aws\n")
    monkeypatch.setattr(WEBHOOK, "_ACTIVE_PROVIDER_FILE", marker)
    monkeypatch.setattr(WEBHOOK, "_context_reachable", lambda _ctx: False)
    assert WEBHOOK._resolve_provider() == "k3s-aws"


def test_no_marker_falls_back_to_aws(monkeypatch, tmp_path):
    marker = tmp_path / "missing"
    monkeypatch.setattr(WEBHOOK, "_ACTIVE_PROVIDER_FILE", marker)
    monkeypatch.setattr(WEBHOOK, "_context_reachable", lambda _ctx: False)
    assert WEBHOOK._resolve_provider() == "k3s-aws"


def test_preferred_provider_skips_probe(monkeypatch, tmp_path):
    monkeypatch.setattr(WEBHOOK, "_ACTIVE_PROVIDER_FILE", tmp_path / "missing")
    monkeypatch.setattr(WEBHOOK, "_context_reachable", lambda _ctx: pytest.fail("unexpected probe"))
    assert WEBHOOK._resolve_provider("hostinger") == "k3s-hostinger"


def test_cache_invalidates_when_marker_changes(monkeypatch, tmp_path):
    marker = tmp_path / "active-provider"
    marker.write_text("k3s-aws\n")
    calls = []
    monkeypatch.setattr(WEBHOOK, "_ACTIVE_PROVIDER_FILE", marker)
    monkeypatch.setattr(WEBHOOK, "_context_reachable", lambda ctx: calls.append(ctx) or ctx == "ubuntu-k3s")
    assert WEBHOOK._resolve_provider() == "k3s-aws"
    assert WEBHOOK._resolve_provider() == "k3s-aws"
    assert calls == ["ubuntu-k3s"]
    marker.write_text("k3s-hostinger\n")
    assert WEBHOOK._resolve_provider() == "k3s-aws"
    assert calls[-2:] == ["ubuntu-hostinger", "ubuntu-k3s"]
