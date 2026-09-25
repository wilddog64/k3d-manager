#!/usr/bin/env python3
"""Browser-emulating SSO and service smoke client for k3dm-webhook.

This module is a pure leaf: it performs the existing offline/remote smoke
checks but has no HTTP server ownership or import-time network side effects.
"""

import base64
import hashlib
import json
import os
import time
import urllib.parse
import urllib.request
import uuid
from html import unescape
from html.parser import HTMLParser
from http.cookiejar import CookieJar
from pathlib import Path

from webhook.proc import _spawn_capture_text

__all__ = [
    "_SMOKE_RETRIES", "_SMOKE_RETRY_SLEEP", "_SMOKE_USER_AGENT",
    "K3DM_SMOKE_FE_REALM", "K3DM_SMOKE_FE_CLIENT", "K3DM_SMOKE_FE_REDIRECT",
    "_SmokeLoginFormParser", "_SmokeNoRedirect",
    "_smoke_secret", "_smoke_vault_secret", "_smoke_post", "_smoke_http_code",
    "_smoke_code_flow", "_smoke_code_flow_error", "_smoke_keycloak_admin",
    "_smoke_frontend_sso", "_smoke_argocd_login", "_smoke_argocd_sso",
    "_smoke_basic_auth", "_smoke_alertmanager_credentials",
    "_smoke_synthetic_token", "_smoke_frontend_api", "_smoke_grafana_login",
    "_smoke_test_logins", "_smoke_test_services",
    "_provider_supports_pushgateway", "_kubectl_absent", "_monitoring_paused",
    "_eso_health_results", "configure_runtime",
]

_secret_register = lambda value: value
_provider_resolver = lambda preferred=None: preferred
_provider_context_resolver = lambda provider=None: provider
_provider_pushgateway_support = None
_posix_capture = None


def _register_secret(value):
    return _secret_register(value)


def _resolve_provider(preferred=None):
    return _provider_resolver(preferred)


def _provider_context(provider=None):
    return _provider_context_resolver(provider)


def _provider_supports_pushgateway(provider):
    if _provider_pushgateway_support is not None:
        return _provider_pushgateway_support(provider)
    return provider != "hub"


def _posix_spawn_capture(cmd, timeout, cwd=None, env=None):
    if _posix_capture is not None:
        return _posix_capture(cmd, timeout, cwd=cwd, env=env)
    _rc, output, timed_out = _spawn_capture_text(cmd, cwd=cwd, env=env, timeout=timeout)
    return output.strip(), timed_out


def configure_runtime(register_secret, resolve_provider, provider_context, posix_spawn_capture,
                      provider_supports_pushgateway):
    global _secret_register, _provider_resolver, _provider_context_resolver
    global _provider_pushgateway_support, _posix_capture
    _secret_register = register_secret
    _provider_resolver = resolve_provider
    _provider_context_resolver = provider_context
    _provider_pushgateway_support = provider_supports_pushgateway
    _posix_capture = posix_spawn_capture


_SMOKE_RETRIES = 3
_SMOKE_RETRY_SLEEP = 10
K3DM_SMOKE_FE_REALM = os.environ.get("K3DM_SMOKE_FE_REALM", "shopping-cart")
K3DM_SMOKE_FE_CLIENT = os.environ.get("K3DM_SMOKE_FE_CLIENT", "frontend")
K3DM_SMOKE_FE_REDIRECT = os.environ.get(
    "K3DM_SMOKE_FE_REDIRECT", "https://frontend.3ai-talk.org/callback")
_SMOKE_USER_AGENT = "k3dm-smoketest/1"


def _kubectl_absent(output):
    """True when combined kubectl stdout+stderr indicates the resource, CRD, or
    namespace does not exist (as opposed to existing-but-unhealthy). Relies on
    _posix_spawn_capture merging stderr into the returned text."""
    if not output or not output.strip():
        return False
    _low = output.lower()
    return any(sig in _low for sig in (
        "notfound",
        "not found",
        "no resources found",
        "doesn't have a resource type",
        "could not find the requested resource",
    ))


def _smoke_secret(namespace, key, secret_name, context=None):
    """Read one key from a k8s Secret and base64-decode it. Returns str or None.

    Lets the login smoke test auto-discover admin credentials that already live
    in-cluster instead of requiring K3DM_SMOKE_* env vars. Returns None on any
    failure (secret/key absent, timeout, decode error) so the caller degrades to a
    ⚪ skip rather than a false red."""
    import base64 as _b64
    cmd = ["kubectl", "get", "secret", secret_name, "-n", namespace,
           "-o", "jsonpath={.data." + key + "}", "--request-timeout=5s"]
    if context:
        cmd += ["--context", context]
    out, timed_out = _posix_spawn_capture(cmd, timeout=8)
    if timed_out or not out.strip():
        return None
    try:
        return _register_secret(_b64.b64decode(out.strip()).decode("utf-8", "replace"))
    except Exception:
        return None


class _SmokeLoginFormParser(HTMLParser):
    def __init__(self):
        super().__init__()
        self.action = None
        self.required_action = False

    def handle_starttag(self, tag, attrs):
        values = dict(attrs)
        if tag == "form" and values.get("id") == "kc-form-login":
            self.action = unescape(values.get("action", ""))
        if tag == "form" and ("required-action" in values.get("id", "") or
                              "required-action" in values.get("action", "")):
            self.required_action = True

    def handle_data(self, data):
        if "update password" in data.lower():
            self.required_action = True


class _SmokeNoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def _smoke_vault_secret(path, key):
    """Read a current KV value from the hub Vault port-forward."""
    token = _smoke_secret("secrets", "root_token", "vault-root", context="k3d-k3d-cluster")
    if not token:
        return None
    try:
        req = urllib.request.Request(
            f"http://127.0.0.1:18200/v1/secret/data/{path}",
            headers={"X-Vault-Token": token, "User-Agent": _SMOKE_USER_AGENT},
        )
        with urllib.request.urlopen(req, timeout=8) as resp:
            return _register_secret(json.loads(resp.read()).get("data", {}).get("data", {}).get(key))
    except Exception:
        return None


def _smoke_post(ctx, url, data, headers=None):
    body = urllib.parse.urlencode(data).encode() if isinstance(data, dict) else data
    request_headers = {"User-Agent": _SMOKE_USER_AGENT}
    if headers:
        request_headers.update(headers)
    req = urllib.request.Request(url, data=body, headers=request_headers, method="POST")
    with urllib.request.urlopen(req, timeout=8, context=ctx) as resp:
        return resp.status, resp.read()


def _smoke_http_code(ctx, request):
    try:
        with urllib.request.urlopen(request, timeout=8, context=ctx) as resp:
            return resp.status, resp.read()
    except urllib.error.HTTPError as exc:
        return exc.code, exc.read()
    except Exception:
        return None, b""


def _smoke_code_flow(ctx, auth_url, redirect_uri, username, password):
    """Run Keycloak's browser code flow and return (ok, detail), never a secret."""
    jar = CookieJar()
    opener = urllib.request.build_opener(
        urllib.request.HTTPCookieProcessor(jar), _SmokeNoRedirect(),
        urllib.request.HTTPSHandler(context=ctx))
    try:
        request = urllib.request.Request(auth_url, headers={"User-Agent": _SMOKE_USER_AGENT})
        response = opener.open(request, timeout=8)
        page = response.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as exc:
        page = exc.read().decode("utf-8", "replace")
        return False, _smoke_code_flow_error(exc.code, page, posted=False)
    except Exception:
        return False, "HTTP unavailable"
    parser = _SmokeLoginFormParser()
    parser.feed(page)
    if parser.required_action:
        return False, "required action pending"
    if not parser.action:
        return False, _smoke_code_flow_error(getattr(response, "status", 200), page, posted=False)
    target = urllib.parse.urljoin(auth_url, parser.action)
    data = urllib.parse.urlencode({"username": username, "password": password,
                                   "credentialId": ""}).encode()
    request = urllib.request.Request(target, data=data, method="POST",
                                     headers={"User-Agent": _SMOKE_USER_AGENT,
                                              "Content-Type": "application/x-www-form-urlencoded"})
    try:
        response = opener.open(request, timeout=8)
        return False, _smoke_code_flow_error(getattr(response, "status", 200), response.read().decode("utf-8", "replace"))
    except urllib.error.HTTPError as exc:
        location = exc.headers.get("Location", "")
        if exc.code in (302, 303) and location.startswith(redirect_uri) and "code=" in location:
            return True, "code received"
        return False, _smoke_code_flow_error(exc.code, exc.read().decode("utf-8", "replace"))
    except Exception:
        return False, "HTTP unavailable"


def _smoke_code_flow_error(code, page, posted=True):
    """Classify a failed code-flow step. `posted` is False before any credential is sent,
    where Keycloak's generic error page reuses the invalid-credentials wording."""
    lower = page.lower()
    if "invalid parameter: redirect_uri" in lower:
        return "client redirect_uri rejected"
    if not posted:
        return f"authorization request rejected (HTTP {code})"
    if "invalid username or password" in lower:
        return "credentials rejected"
    if "invalid parameter: redirect_uri" in lower:
        return "client redirect_uri rejected"
    if "update password" in lower or "required action" in lower:
        return "required action pending"
    return f"HTTP {code}"


def _smoke_keycloak_admin(ctx):
    source = "identity/keycloak-secrets Secret"
    user = _smoke_secret("identity", "KEYCLOAK_ADMIN", "keycloak-secrets", context="k3d-k3d-cluster")
    password = _smoke_secret("identity", "KEYCLOAK_ADMIN_PASSWORD", "keycloak-secrets", context="k3d-k3d-cluster")
    if not user or not password:
        return "Keycloak admin login", None, f"admin via {source}: credentials unavailable"
    try:
        code, raw = _smoke_post(ctx, "https://keycloak.3ai-talk.org/realms/master/protocol/openid-connect/token", {
            "grant_type": "password", "client_id": "admin-cli", "username": user, "password": password})
        return "Keycloak admin login", bool(code == 200 and json.loads(raw).get("access_token")), f"{user} via {source}: HTTP {code}"
    except Exception:
        return "Keycloak admin login", False, f"{user} via {source}: HTTP unavailable"


def _smoke_frontend_sso(ctx):
    source = "Vault keycloak/users"
    outcomes = []
    for user in ("admin", "developer", "operator"):
        password = _register_secret(_smoke_vault_secret(f"keycloak/users/{user}", "password"))
        if not password:
            outcomes.append((user, None, "credentials unavailable"))
            continue
        state = uuid.uuid4().hex
        verifier = uuid.uuid4().hex + uuid.uuid4().hex
        challenge = base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest()).rstrip(b"=").decode()
        query = urllib.parse.urlencode({"client_id": K3DM_SMOKE_FE_CLIENT, "response_type": "code",
            "scope": "openid", "redirect_uri": K3DM_SMOKE_FE_REDIRECT, "state": state,
            "code_challenge": challenge, "code_challenge_method": "S256"})
        ok, detail = _smoke_code_flow(ctx, f"https://keycloak.3ai-talk.org/realms/{K3DM_SMOKE_FE_REALM}/protocol/openid-connect/auth?{query}", K3DM_SMOKE_FE_REDIRECT, user, password)
        outcomes.append((user, ok, detail))
    detail = "; ".join(f"{user} via {source}: {message}" for user, _, message in outcomes)
    if any(ok is False for _, ok, _ in outcomes):
        overall = False
    elif any(ok is None for _, ok, _ in outcomes):
        overall = None
    else:
        overall = True
    return "Frontend SSO login", overall, detail


def _smoke_argocd_login(ctx):
    source = "env" if os.environ.get("K3DM_SMOKE_ARGOCD_PASS") else "Vault argocd/admin"
    password = _register_secret(os.environ.get("K3DM_SMOKE_ARGOCD_PASS") or _smoke_vault_secret("argocd/admin", "password"))
    if not password:
        return "ArgoCD login", None, f"admin via {source}: credentials unavailable"
    try:
        code, raw = _smoke_post(ctx, "https://argocd.3ai-talk.org/api/v1/session",
                                json.dumps({"username": "admin", "password": password}).encode(),
                                headers={"Content-Type": "application/json"})
        return "ArgoCD login", bool(code == 200 and json.loads(raw).get("token")), f"admin via {source}: HTTP {code}"
    except Exception:
        return "ArgoCD login", False, f"admin via {source}: HTTP unavailable"


def _smoke_argocd_sso(ctx):
    source = "Vault keycloak/users/admin"
    password = _register_secret(_smoke_vault_secret("keycloak/users/admin", "password"))
    if not password:
        return "ArgoCD SSO login", None, f"admin via {source}: credentials unavailable"
    request = urllib.request.Request("https://argocd.3ai-talk.org/auth/login", headers={"User-Agent": _SMOKE_USER_AGENT})
    opener = urllib.request.build_opener(_SmokeNoRedirect(), urllib.request.HTTPSHandler(context=ctx))
    try:
        opener.open(request, timeout=8)
        return "ArgoCD SSO login", False, f"admin via {source}: HTTP 200"
    except urllib.error.HTTPError as exc:
        location = exc.headers.get("Location", "")
        if exc.code not in (302, 303) or f"/realms/{K3DM_SMOKE_FE_REALM}/protocol/openid-connect/auth" not in location:
            return "ArgoCD SSO login", False, f"admin via {source}: HTTP {exc.code}"
        ok, detail = _smoke_code_flow(ctx, location, "https://argocd.3ai-talk.org/auth/callback", "admin", password)
        return "ArgoCD SSO login", ok, f"admin via {source}: {detail}"
    except Exception:
        return "ArgoCD SSO login", False, f"admin via {source}: HTTP unavailable"


def _smoke_basic_auth(ctx, name, url, user, password, source, check_unauthenticated=False):
    if not password:
        return name, None, f"{user} via {source}: credentials unavailable"
    encoded = _register_secret(base64.b64encode(f"{user}:{password}".encode()).decode())
    request = urllib.request.Request(url, headers={"User-Agent": _SMOKE_USER_AGENT, "Authorization": f"Basic {encoded}"})
    code, _ = _smoke_http_code(ctx, request)
    if code != 200:
        return name, False, f"{user} via {source}: HTTP {code if code else 'unavailable'}"
    if check_unauthenticated:
        anonymous = urllib.request.Request(url, headers={"User-Agent": _SMOKE_USER_AGENT})
        unauth_code, _ = _smoke_http_code(ctx, anonymous)
        if unauth_code == 200:
            return name, False, f"{user} via {source}: auth not enforced"
    return name, True, f"{user} via {source}: HTTP 200"


def _smoke_alertmanager_credentials():
    path = Path(os.environ.get("HOME", str(Path.home()))) / ".local/share/k3d-manager/alertmanager-basic-auth.env"
    try:
        values = dict(line.strip().split("=", 1) for line in path.read_text().splitlines()
                      if "=" in line and line.strip() and not line.lstrip().startswith("#"))
    except OSError:
        return None, None
    return values.get("ALERTMANAGER_BASIC_AUTH_USER", "admin"), _register_secret(values.get("ALERTMANAGER_BASIC_AUTH_PASSWORD"))


def _smoke_synthetic_token(ctx, provider):
    source = "identity/k3dm-smoke-user Secret"
    user = _smoke_secret("identity", "username", "k3dm-smoke-user", context="k3d-k3d-cluster")
    password = _smoke_secret("identity", "password", "k3dm-smoke-user", context="k3d-k3d-cluster")
    realm = _smoke_secret("identity", "realm", "k3dm-smoke-user", context="k3d-k3d-cluster") or K3DM_SMOKE_FE_REALM
    if not user or not password:
        return ("Keycloak smoke token (k3dm-smoke-user)", None,
                f"k3dm-smoke-user via {source}: credentials unavailable"), None
    base = "https://keycloak.3ai-talk.org" if provider == "k3s-hostinger" else "http://keycloak.shopping-cart.local"
    try:
        code, raw = _smoke_post(ctx, f"{base}/realms/{realm}/protocol/openid-connect/token", {
            "grant_type": "password", "client_id": "k3dm-smoke", "username": user, "password": password})
        token = json.loads(raw).get("access_token") if code == 200 else None
        return ("Keycloak smoke token (k3dm-smoke-user)", bool(token),
                f"k3dm-smoke-user via {source}: HTTP {code}"), _register_secret(token)
    except Exception:
        return ("Keycloak smoke token (k3dm-smoke-user)", False,
                f"k3dm-smoke-user via {source}: HTTP unavailable"), None


def _smoke_frontend_api(ctx, provider, token):
    source = "identity/k3dm-smoke-user Secret"
    if not token:
        return "Frontend API (smoke token)", None, f"k3dm-smoke-user via {source}: token unavailable"
    base = "https://frontend.3ai-talk.org" if provider == "k3s-hostinger" else "http://frontend.shopping-cart.local"
    path = os.environ.get("K3DM_SMOKE_FRONTEND_AUTHED_PATH", "/api/cart")
    for attempt in range(_SMOKE_RETRIES):
        request = urllib.request.Request(f"{base}{path}", headers={"User-Agent": _SMOKE_USER_AGENT,
                                      "Authorization": f"Bearer {token}"})
        code, _ = _smoke_http_code(ctx, request)
        if code and (200 <= code < 300 or attempt == _SMOKE_RETRIES - 1):
            return "Frontend API (smoke token)", 200 <= code < 300, f"k3dm-smoke-user via {source}: HTTP {code} on {path}"
        time.sleep(_SMOKE_RETRY_SLEEP)
    return "Frontend API (smoke token)", False, f"k3dm-smoke-user via {source}: HTTP unavailable"


def _smoke_grafana_login(ctx):
    source = "Vault observability/grafana"
    user = _smoke_vault_secret("observability/grafana", "username") or "admin"
    password = _register_secret(_smoke_vault_secret("observability/grafana", "password"))
    if not password:
        return "Grafana login", None, f"{user} via {source}: credentials unavailable"
    try:
        code, _ = _smoke_post(ctx, "https://grafana.3ai-talk.org/login",
                              json.dumps({"user": user, "password": password}).encode(),
                              headers={"Content-Type": "application/json"})
        if code != 200 and _monitoring_paused():
            return "Grafana login", None, f"{user} via {source}: monitoring paused (make monitoring-resume)"
        return "Grafana login", code == 200, f"{user} via {source}: HTTP {code}"
    except Exception:
        if _monitoring_paused():
            return "Grafana login", None, f"{user} via {source}: monitoring paused (make monitoring-resume)"
        return "Grafana login", False, f"{user} via {source}: HTTP unavailable"


def _smoke_test_logins(provider, app_context):
    """Credentialed operator login checks plus explicitly-labelled synthetic probes."""
    import ssl
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    results = [_smoke_keycloak_admin(ctx), _smoke_frontend_sso(ctx), _smoke_argocd_login(ctx),
               _smoke_argocd_sso(ctx)]
    prom_user = _smoke_vault_secret("k3d-manager/prometheus-basic-auth", "user") or "admin"
    prom_pass = _register_secret(_smoke_vault_secret("k3d-manager/prometheus-basic-auth", "password"))
    results.append(_smoke_basic_auth(ctx, "Prometheus login", "https://prometheus.3ai-talk.org/api/v1/status/buildinfo", prom_user, prom_pass, "Vault k3d-manager/prometheus-basic-auth", True))
    alert_user, alert_pass = _smoke_alertmanager_credentials()
    results.append(_smoke_basic_auth(ctx, "Alertmanager login", "https://alertmanager.3ai-talk.org/api/v2/status", alert_user or "admin", alert_pass, "~/.local/share/k3d-manager/alertmanager-basic-auth.env"))
    results.append(_smoke_grafana_login(ctx))
    smoke_result, smoke_token = _smoke_synthetic_token(ctx, provider)
    results.append(smoke_result)
    results.append(_smoke_frontend_api(ctx, provider, smoke_token))
    return results


def _monitoring_paused(context=None, argons=None):
    """True iff the hub observability stack is DELIBERATELY paused by
    observability_pause. Signal: the kube-prometheus-stack ArgoCD Application
    exists and its spec.syncPolicy.automated is empty (exactly what the pause
    sets). This distinguishes an intentional pause from a crash — a
    broken-but-managed stack still has automated set, so it stays a real FAIL.
    The observability stack and its ArgoCD Applications always live on the hub
    (infra) context, never the app-cluster context. Any uncertainty (kubectl
    absent, timeout) returns False (not known paused)."""
    context = context or os.environ.get("INFRA_CONTEXT", "k3d-k3d-cluster")
    argons = argons or os.environ.get("ARGOCD_NAMESPACE", "cicd")
    out, timed_out = _posix_spawn_capture(
        ["kubectl", "get", "application", "kube-prometheus-stack",
         "-n", argons, "--context", context,
         "-o", "jsonpath={.metadata.name}={.spec.syncPolicy.automated}",
         "--request-timeout=5s"],
        timeout=8,
    )
    if timed_out or _kubectl_absent(out):
        return False
    return out.strip() == "kube-prometheus-stack="


def _eso_health_results(context, label_prefix=""):
    """ClusterSecretStore + ExternalSecret health on one kube context.
    Returns [(name, ok, detail), ...] named '<label_prefix>ESO ...'."""
    results = []
    css_name = f"{label_prefix}ESO ClusterSecretStore"
    es_name = f"{label_prefix}ESO ExternalSecrets"
    try:
        _css_out, _css_timeout = _posix_spawn_capture(
            ["kubectl", "get", "clustersecretstore", "vault-backend",
             "--context", context, "-o", "json"],
            timeout=8,
        )
        if _css_timeout:
            raise RuntimeError("kubectl clustersecretstore timed out")
        if _kubectl_absent(_css_out):
            results.append((css_name, None,
                            f"not installed (no ClusterSecretStore on {context})"))
        else:
            _data = json.loads(_css_out)
            _conds = _data.get("status", {}).get("conditions", [])
            _ready = next((c for c in _conds if c.get("type") == "Ready"), None)
            _val = f"Ready={_ready.get('status', 'Unknown')}" if _ready else "no conditions"
            results.append((css_name, _val == "Ready=True", _val))
    except Exception as _exc:
        results.append((css_name, False, str(_exc)[:200]))

    try:
        _es_out, _es_timeout = _posix_spawn_capture(
            ["kubectl", "get", "externalsecret", "-A",
             "--context", context, "-o", "json"],
            timeout=10,
        )
        if _es_timeout:
            raise RuntimeError("kubectl externalsecret timed out")
        if _kubectl_absent(_es_out):
            results.append((es_name, None,
                            f"not installed (no ExternalSecret CRD on {context})"))
            _es_data = None
        else:
            _es_data = json.loads(_es_out)
        if _es_data is not None:
            _items = _es_data.get("items", [])
            _not_ready = [
                it["metadata"]["name"]
                for it in _items
                if not any(
                    c.get("type") == "Ready" and c.get("status") == "True"
                    for c in it.get("status", {}).get("conditions", [])
                )
            ]
            _total = len(_items)
            if _not_ready:
                results.append((es_name, False,
                                f"{len(_not_ready)}/{_total} not synced: {', '.join(_not_ready[:3])}"))
            else:
                results.append((es_name, True, f"{_total}/{_total} synced"))
    except Exception as _exc:
        results.append((es_name, False, str(_exc)[:200]))
    return results


def _smoke_test_services(retries=None, provider=None, quick=False):
    """HTTP smoke test for each service. Returns list of (name, ok, detail) tuples."""
    import ssl
    import time
    _retries = retries if retries is not None else _SMOKE_RETRIES
    provider = _resolve_provider(provider)
    app_context = _provider_context(provider)
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE

    if provider == "k3s-hostinger":
        frontend_url = "https://frontend.3ai-talk.org/"
        keycloak_url = "https://keycloak.3ai-talk.org/realms/master"
    else:
        frontend_url = "http://frontend.shopping-cart.local/"
        keycloak_url = "http://keycloak.shopping-cart.local/health/live"

    results = []
    if provider == "k3s-hostinger":
        argocd_health_url = "https://argocd.3ai-talk.org/healthz"
        prometheus_ready_url = "https://prometheus.3ai-talk.org/-/ready"
    else:
        argocd_health_url = "http://localhost:8080/healthz"
        prometheus_ready_url = "http://localhost:19190/-/ready"

    smoke_endpoints = [
        ("ArgoCD", argocd_health_url, [200]),
        ("Frontend", frontend_url, [200]),
        ("Keycloak", keycloak_url, [200]),
        ("Prometheus", prometheus_ready_url, [200]),
        ("Grafana", "https://grafana.3ai-talk.org/api/health", [200]),
    ]
    if _provider_supports_pushgateway(provider):
        smoke_endpoints.append(("Pushgateway", "http://localhost:9091/-/healthy", [200]))

    def _probe_endpoint(endpoint):
        name, url, ok_codes = endpoint
        last_err = ""
        passed = False
        for attempt in range(_retries):
            try:
                req = urllib.request.Request(url, headers={"User-Agent": "k3dm-smoketest/1"})
                with urllib.request.urlopen(req, timeout=8, context=ctx) as resp:
                    code = resp.status
                    if code in ok_codes:
                        passed = True
                        last_err = f"HTTP {code}"
                        break
                    if name == "Prometheus" and code == 401:
                        return name, None, "HTTP 401 (authentication required)"
                    last_err = f"HTTP {code}"
            except urllib.error.HTTPError as exc:
                if name == "Prometheus" and exc.code == 401:
                    return name, None, "HTTP 401 (authentication required)"
                last_err = str(exc)
            except Exception as exc:
                last_err = str(exc)
            if attempt < _retries - 1:
                time.sleep(_SMOKE_RETRY_SLEEP)
        return name, passed, last_err

    # These probes are independent. Running them serially made one slow API or
    # tunnel consume the whole webhook request budget and collapse status to
    # UNKNOWN; keep per-service failures but complete the response in parallel.
    from concurrent.futures import ThreadPoolExecutor
    with ThreadPoolExecutor(max_workers=len(smoke_endpoints)) as _pool:
        results.extend(_pool.map(_probe_endpoint, smoke_endpoints))

    # The summary status command needs a bounded liveness snapshot.  The full
    # sweep below also checks Vault, ESO, Kubernetes, and browser logins and can
    # legitimately take longer than a CLI status probe should wait.
    if quick:
        return results

    # A deliberately paused hub monitoring stack (make monitoring-pause) is not a
    # failure — downgrade its expected 502s to a skip so status stays green. The
    # Prometheus/Grafana URLs front the hub monitoring in every provider mode
    # (the public *.3ai-talk.org names route to the hub via cloudflared), so this
    # applies regardless of provider — the hub-specific paused signal is the gate.
    _paused = None
    for _i, (_n, _ok, _d) in enumerate(results):
        if _ok is False and _n in ("Prometheus", "Grafana"):
            if _paused is None:
                _paused = _monitoring_paused()
            if _paused:
                results[_i] = (_n, None, "monitoring paused (make monitoring-resume)")

    if _provider_supports_pushgateway(provider):
        for _i, (_pn, _pok, _pd) in enumerate(results):
            if _pn == "Pushgateway" and _pok is False:
                _pg_out, _pg_to = _posix_spawn_capture(
                    ["kubectl", "get", "pods", "-n", "monitoring",
                     "-l", "app.kubernetes.io/name=prometheus-pushgateway",
                     "--context", app_context, "-o", "name", "--request-timeout=5s"],
                    timeout=8,
                )
                if not _pg_to and (_kubectl_absent(_pg_out) or not _pg_out.strip()):
                    results[_i] = ("Pushgateway", None,
                                   f"not deployed (no pushgateway pod on {app_context})")
                break

    # Product catalog: verify at least one product has a non-empty imageUrl.
    # This request follows the same retry contract as the health endpoints;
    # during tunnel/node recovery a transient 502 must not become a false
    # product-data failure.
    _products_detail = ""
    _products_ok = False
    for _attempt in range(_SMOKE_RETRIES):
        try:
            products_url = f"{frontend_url.rstrip('/')}/api/products"
            req = urllib.request.Request(products_url, headers={"User-Agent": "k3dm-smoketest/1"})
            with urllib.request.urlopen(req, timeout=8, context=ctx) as resp:
                body = json.loads(resp.read())
                products = body.get("items", body) if isinstance(body, dict) else body
                if isinstance(products, list) and products:
                    with_images = sum(1 for p in products if p.get("imageUrl") or p.get("image_url"))
                    _products_ok = with_images > 0
                    _products_detail = (f"{with_images}/{len(products)} have image_url"
                                        if _products_ok else f"0/{len(products)} have image_url")
                else:
                    _products_detail = "empty or non-list response"
        except Exception as exc:
            _products_detail = str(exc)[:200]
        if _products_ok or _attempt == _SMOKE_RETRIES - 1:
            break
        time.sleep(_SMOKE_RETRY_SLEEP)
    results.append(("Product images", _products_ok, _products_detail))

    results.extend(_eso_health_results(app_context))
    if app_context != "k3d-k3d-cluster":
        results.extend(_eso_health_results("k3d-k3d-cluster", "Hub "))

    # Data-layer StatefulSet readiness for the active app cluster — uses posix_spawn, safe after NEF load
    _dl_ns_out, _dl_ns_timeout = _posix_spawn_capture(
        ["kubectl", "get", "namespace", "shopping-cart-data",
         "--context", app_context, "-o", "name", "--request-timeout=5s"],
        timeout=8,
    )
    if not _dl_ns_timeout and _kubectl_absent(_dl_ns_out):
        results.append(("Data layer", None,
                        f"not deployed (namespace shopping-cart-data absent on {app_context})"))
    else:
        _dl_names = ["postgresql-orders", "postgresql-payment", "postgresql-products", "minio"]
        _dl_ready = 0
        _dl_not_ready = []
        for _ss in _dl_names:
            _dl_out, _dl_timeout = _posix_spawn_capture(
                ["kubectl", "get", "statefulset", _ss,
                 "-n", "shopping-cart-data", "--context", app_context,
                 "-o", "jsonpath={.status.readyReplicas}",
                 "--request-timeout=5s"],
                timeout=8,
            )
            if not _dl_timeout and _dl_out.strip().isdigit() and int(_dl_out.strip()) >= 1:
                _dl_ready += 1
            else:
                _dl_not_ready.append(_ss)
        _dl_ok = _dl_ready == len(_dl_names)
        _dl_detail = (
            f"{_dl_ready}/{len(_dl_names)} ready"
            if _dl_ok
            else f"{len(_dl_not_ready)} not ready: {', '.join(_dl_not_ready[:2])}"
        )
        results.append(("Data layer", _dl_ok, _dl_detail))

    results.extend(_smoke_test_logins(provider, app_context))
