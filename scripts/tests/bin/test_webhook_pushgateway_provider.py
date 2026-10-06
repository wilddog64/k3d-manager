import importlib.machinery
import importlib.util
from pathlib import Path

import pytest


ROOT = Path(__file__).resolve().parents[3]
SOURCE = ROOT / "bin" / "k3dm-webhook"
SPEC = importlib.util.spec_from_loader(
    "k3dm_webhook_pushgateway_provider_test",
    importlib.machinery.SourceFileLoader(
        "k3dm_webhook_pushgateway_provider_test", str(SOURCE)
    ),
)
WEBHOOK = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(WEBHOOK)


@pytest.mark.parametrize(
    ("provider", "supported"),
    [
        ("hub", False),
        ("k3s-hostinger", True),
        ("k3s-aws", True),
        ("k3s-gcp", True),
        ("k3s-az", True),
    ],
)
def test_provider_supports_pushgateway(provider, supported):
    assert WEBHOOK._provider_supports_pushgateway(provider) is supported


def test_smoke_uses_provider_scoped_pushgateway_ports(monkeypatch):
    requested = []

    class Response:
        status = 200

        def __enter__(self):
            return self

        def __exit__(self, *_args):
            return False

    def urlopen(request, **_kwargs):
        requested.append(request.full_url)
        return Response()

    monkeypatch.setattr(WEBHOOK.urllib.request, "urlopen", urlopen)
    monkeypatch.setattr(WEBHOOK, "_provider_supports_pushgateway", lambda _provider: True)
    WEBHOOK._smoke_test_services(retries=1, provider="k3s-aws", quick=True)
    assert any(url.endswith(":9092/-/healthy") for url in requested)
    requested.clear()
    WEBHOOK._smoke_test_services(retries=1, provider="k3s-hostinger", quick=True)
    assert any(url.endswith(":9091/-/healthy") for url in requested)
