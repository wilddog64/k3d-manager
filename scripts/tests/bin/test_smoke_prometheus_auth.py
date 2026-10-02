import importlib.machinery
import importlib.util
import json
import sys
from pathlib import Path
from urllib.error import HTTPError


ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "scripts" / "lib"))
SOURCE = ROOT / "scripts" / "lib" / "webhook" / "smoke.py"
SPEC = importlib.util.spec_from_loader(
    "k3dm_webhook_smoke_prometheus_auth",
    importlib.machinery.SourceFileLoader("k3dm_webhook_smoke_prometheus_auth", str(SOURCE)),
)
WEBHOOK = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(WEBHOOK)


class Response:
    def __init__(self, status, body=b""):
        self.status = status
        self._body = body

    def __enter__(self):
        return self

    def __exit__(self, *_args):
        return False

    def read(self):
        return self._body


def _urlopen_for(status_or_error):
    def urlopen(request, **_kwargs):
        if "/-/ready" in request.full_url:
            if isinstance(status_or_error, Exception):
                raise status_or_error
            return Response(status_or_error)
        if "/api/products" in request.full_url:
            return Response(200, json.dumps([{"imageUrl": "image"}]).encode())
        return Response(200)

    return urlopen


def _quick(monkeypatch, provider, prometheus_result):
    monkeypatch.setattr(WEBHOOK, "_provider_supports_pushgateway", lambda _provider: False)
    monkeypatch.setattr(WEBHOOK.urllib.request, "urlopen", _urlopen_for(prometheus_result))
    return WEBHOOK._smoke_test_services(retries=1, provider=provider, quick=True)


def _result(results, name):
    return next(result for result in results if result[0] == name)


def test_hostinger_prometheus_http_error_401_is_auth_enforced(monkeypatch):
    error = HTTPError("https://prometheus.3ai-talk.org/-/ready", 401, "Unauthorized", {}, None)
    result = _result(_quick(monkeypatch, "k3s-hostinger", error), "Prometheus")
    assert result[1] is True
    assert "auth enforced" in result[2]


def test_hostinger_prometheus_response_401_is_auth_enforced(monkeypatch):
    result = _result(_quick(monkeypatch, "k3s-hostinger", 401), "Prometheus")
    assert result[1] is True
    assert "auth enforced" in result[2]
    assert not any(ok is False for _name, ok, _detail in _quick(monkeypatch, "k3s-hostinger", 401))


def test_hostinger_prometheus_200_is_auth_proxy_bypass(monkeypatch):
    result = _result(_quick(monkeypatch, "k3s-hostinger", 200), "Prometheus")
    assert result[1] is False
    assert "auth proxy bypassed" in result[2]


def test_hostinger_prometheus_502_still_fails(monkeypatch):
    result = _result(_quick(monkeypatch, "k3s-hostinger", 502), "Prometheus")
    assert result[1] is False
    assert result[2] == "HTTP 502"


def test_k3d_prometheus_200_passes(monkeypatch):
    result = _result(_quick(monkeypatch, "k3d", 200), "Prometheus")
    assert result[1] is True
    assert result[2] == "HTTP 200"


def test_k3d_prometheus_401_does_not_pass(monkeypatch):
    result = _result(_quick(monkeypatch, "k3d", 401), "Prometheus")
    assert result[1] is False


def test_monitoring_paused_downgrades_prometheus_502(monkeypatch):
    monkeypatch.setattr(WEBHOOK, "_provider_supports_pushgateway", lambda _provider: False)
    monkeypatch.setattr(WEBHOOK, "_monitoring_paused", lambda: True)
    monkeypatch.setattr(WEBHOOK, "_eso_health_results", lambda *_args: [])
    monkeypatch.setattr(WEBHOOK, "_smoke_test_logins", lambda *_args: [])
    monkeypatch.setattr(WEBHOOK, "_posix_spawn_capture", lambda *_args, **_kwargs: ("1", False))
    monkeypatch.setattr(WEBHOOK.urllib.request, "urlopen", _urlopen_for(502))
    results = WEBHOOK._smoke_test_services(retries=1, provider="k3s-hostinger")
    assert _result(results, "Prometheus")[1:] == (None, "monitoring paused (make monitoring-resume)")
