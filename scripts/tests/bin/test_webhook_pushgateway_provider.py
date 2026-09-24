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
