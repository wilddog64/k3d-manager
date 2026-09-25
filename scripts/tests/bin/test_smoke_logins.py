import importlib.machinery
import importlib.util
import io
import json
import sys
from email.message import Message
from pathlib import Path
from urllib.error import HTTPError

import pytest


ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "scripts" / "lib"))
SOURCE = ROOT / "scripts" / "lib" / "webhook" / "smoke.py"
SPEC = importlib.util.spec_from_loader("k3dm_webhook_smoke_test", importlib.machinery.SourceFileLoader("k3dm_webhook_smoke_test", str(SOURCE)))
WEBHOOK = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(WEBHOOK)
SENTINEL = "PW-SENTINEL-DO-NOT-PRINT"


class Response:
    status = 200

    def __init__(self, body=b""):
        self.body = body

    def read(self):
        return self.body


def redirect(location):
    headers = Message()
    headers["Location"] = location
    return HTTPError("https://example.test", 302, "Found", headers, None)


def code_flow_opener(login_page, result):
    requests = []

    class Opener:
        def open(self, request, timeout):
            requests.append(request)
            if len(requests) == 1:
                return Response(login_page.encode())
            raise result

    return Opener(), requests


def test_code_flow_unescapes_form_action_and_accepts_code(monkeypatch):
    opener, requests = code_flow_opener(
        '<form id="kc-form-login" action="/login?x=one&amp;y=two">',
        redirect("https://frontend.3ai-talk.org/callback?code=abc"),
    )
    monkeypatch.setattr(WEBHOOK.urllib.request, "build_opener", lambda *args: opener)

    ok, detail = WEBHOOK._smoke_code_flow(None, "https://keycloak.test/auth", "https://frontend.3ai-talk.org/callback", "admin", SENTINEL)

    assert ok is True
    assert detail == "code received"
    assert requests[1].full_url == "https://keycloak.test/login?x=one&y=two"
    assert SENTINEL not in requests[1].full_url


@pytest.mark.parametrize(("page", "expected"), [
    ("Invalid username or password", "credentials rejected"),
    ("Invalid parameter: redirect_uri", "client redirect_uri rejected"),
    ("<form id='required-action-update-password'>Update password</form>", "required action pending"),
])
def test_code_flow_reports_operator_failure_reason(monkeypatch, page, expected):
    opener, _ = code_flow_opener("<form id='kc-form-login' action='/login'>", HTTPError("https://keycloak.test/login", 200, "OK", Message(), None))

    def open_with_page(request, timeout):
        if request.get_method() == "GET":
            return Response("<form id='kc-form-login' action='/login'>".encode())
        raise HTTPError("https://keycloak.test/login", 400, "Bad Request", Message(), io.BytesIO(page.encode()))

    opener.open = open_with_page
    monkeypatch.setattr(WEBHOOK.urllib.request, "build_opener", lambda *args: opener)
    ok, detail = WEBHOOK._smoke_code_flow(None, "https://keycloak.test/auth", "https://frontend.test/callback", "admin", SENTINEL)
    assert ok is False
    assert detail == expected
    assert SENTINEL not in detail


def test_argocd_vault_unreadable_skips_without_initial_secret(monkeypatch):
    monkeypatch.delenv("K3DM_SMOKE_ARGOCD_PASS", raising=False)
    monkeypatch.setattr(WEBHOOK, "_smoke_vault_secret", lambda path, key: None)
    monkeypatch.setattr(WEBHOOK, "_smoke_secret", lambda *args, **kwargs: pytest.fail("initial secret must not be read"))

    name, ok, detail = WEBHOOK._smoke_argocd_login(None)

    assert (name, ok) == ("ArgoCD login", None)
    assert "admin via Vault argocd/admin" in detail


@pytest.mark.parametrize("provider", ["k3d", "k3s-hostinger"])
def test_argocd_uses_public_url_for_every_provider(monkeypatch, provider):
    monkeypatch.setenv("K3DM_SMOKE_ARGOCD_PASS", SENTINEL)
    seen = []

    def fake_post(ctx, url, data, headers=None):
        seen.append(url)
        return 200, json.dumps({"token": "token"}).encode()

    monkeypatch.setattr(WEBHOOK, "_smoke_post", fake_post)
    WEBHOOK._smoke_argocd_login(None)
    assert seen == ["https://argocd.3ai-talk.org/api/v1/session"]


def test_prometheus_rejects_an_unauthenticated_success(monkeypatch):
    codes = iter([(200, b""), (200, b"")])
    monkeypatch.setattr(WEBHOOK, "_smoke_http_code", lambda ctx, request: next(codes))
    _, ok, detail = WEBHOOK._smoke_basic_auth(None, "Prometheus login", "https://prometheus.test", "admin", SENTINEL, "Vault k3d-manager/prometheus-basic-auth", True)
    assert ok is False
    assert detail.endswith("auth not enforced")
    assert SENTINEL not in detail


def test_alertmanager_env_is_parsed_without_sourcing(monkeypatch, tmp_path):
    auth = tmp_path / ".local/share/k3d-manager"
    auth.mkdir(parents=True)
    (auth / "alertmanager-basic-auth.env").write_text("ALERTMANAGER_BASIC_AUTH_USER=admin\nALERTMANAGER_BASIC_AUTH_PASSWORD=" + SENTINEL + "\nUNSAFE=$(echo no)\n")
    monkeypatch.setenv("HOME", str(tmp_path))
    user, password = WEBHOOK._smoke_alertmanager_credentials()
    assert user == "admin"
    assert password == SENTINEL


def test_alertmanager_missing_file_skips(monkeypatch, tmp_path):
    monkeypatch.setenv("HOME", str(tmp_path))
    assert WEBHOOK._smoke_alertmanager_credentials() == (None, None)


def test_source_parity_and_secret_safe_details(monkeypatch):
    makefile = (ROOT / "Makefile").read_text()
    keycloak = (ROOT / "bin/get-keycloak-password").read_text()
    for token in ("argocd/admin", "observability/grafana", "k3d-manager/prometheus-basic-auth", "keycloak/users", "keycloak-secrets", "KEYCLOAK_ADMIN_PASSWORD", "alertmanager-basic-auth.env"):
        assert token in makefile or token in keycloak
    monkeypatch.setattr(WEBHOOK, "_smoke_http_code", lambda ctx, request: (401, b""))
    _, _, detail = WEBHOOK._smoke_basic_auth(None, "x", "https://example.test", "admin", SENTINEL, "Vault test")
    assert SENTINEL not in detail


def test_grafana_failure_is_skipped_while_monitoring_is_paused(monkeypatch):
    monkeypatch.setattr(WEBHOOK, "_smoke_vault_secret",
                        lambda path, key: SENTINEL if key == "password" else "admin")
    monkeypatch.setattr(WEBHOOK, "_smoke_post", lambda *args, **kwargs: (502, b""))
    monkeypatch.setattr(WEBHOOK, "_monitoring_paused", lambda *args, **kwargs: True)
    name, ok, detail = WEBHOOK._smoke_grafana_login(None)
    assert (name, ok) == ("Grafana login", None)
    assert "monitoring paused" in detail and SENTINEL not in detail
    monkeypatch.setattr(WEBHOOK, "_monitoring_paused", lambda *args, **kwargs: False)
    assert WEBHOOK._smoke_grafana_login(None)[1] is False


def test_pre_form_error_is_not_labelled_credentials_rejected():
    """Keycloak's 400 error page reuses the invalid-credentials wording before any
    login form is served (2026-09-15 browser-flow regression); do not call that a
    rejected credential."""
    page = "<html><body>We are sorry... Invalid username or password.</body></html>"
    assert WEBHOOK._smoke_code_flow_error(400, page, posted=False) == \
        "authorization request rejected (HTTP 400)"
    assert WEBHOOK._smoke_code_flow_error(200, page) == "credentials rejected"


def test_redirect_uri_error_wins_before_and_after_post():
    page = "<html>Invalid parameter: redirect_uri</html>"
    assert WEBHOOK._smoke_code_flow_error(400, page, posted=False) == "client redirect_uri rejected"
    assert WEBHOOK._smoke_code_flow_error(400, page) == "client redirect_uri rejected"
