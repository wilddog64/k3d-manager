import json
import sys
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "lib"))

from hermes.correlator import Correlator
from hermes.sensors import argocd, ci, eso, node_pressure, reachability


def health(entries):
    return {"services": entries, "all_ok": all(x["ok"] is not False for x in entries)}


def webhook(payload):
    return lambda _url, _headers: payload


def assert_normalized(item, sensor):
    assert set(item) == {"sensor", "status", "evidence", "sampled_at"}
    assert item["sensor"] == sensor
    assert item["status"] in {"healthy", "degraded", "unknown"}


def test_eso_healthy_degraded_unknown_and_debounce():
    good = health([{"name": "ESO ClusterSecretStore", "ok": True, "detail": "Ready=True"},
                   {"name": "ESO ExternalSecrets", "ok": True, "detail": "7/7 synced"}])
    healthy = eso(webhook(good), {}, token="x")
    assert_normalized(healthy, "eso")
    assert healthy["status"] == "healthy"
    bad = health([{"name": "ESO ClusterSecretStore", "ok": True, "detail": "Ready=True"},
                  {"name": "ESO ExternalSecrets", "ok": False, "detail": "3/7 synced"}])
    state = {}
    assert [eso(webhook(bad), state, token="x")["status"] for _ in range(3)] == ["healthy", "healthy", "degraded"]
    unknown = health([{"name": "ESO ClusterSecretStore", "ok": None, "detail": "absent"},
                      {"name": "ESO ExternalSecrets", "ok": True, "detail": "ok"}])
    assert eso(webhook(unknown), {}, token="x")["status"] == "unknown"
    assert eso(webhook(good), {}, token="")["status"] == "unknown"


def test_argocd_healthy_degraded_unknown_and_debounce():
    good = json.dumps([{ "name": "cart", "project": "shop", "status": {"health": {"status": "Healthy"}, "sync": {"status": "Synced"}}}])
    bad = json.dumps([{ "name": "cart", "project": "shop", "status": {"health": {"status": "Degraded"}, "sync": {"status": "OutOfSync"}}}])
    healthy = argocd(lambda *_: (0, good), {}, token="x")
    assert_normalized(healthy, "argocd")
    assert healthy["status"] == "healthy"
    state = {}
    assert [argocd(lambda *_: (0, bad), state, token="x")["status"] for _ in range(4)] == ["healthy", "healthy", "healthy", "degraded"]
    assert argocd(lambda *_: (1, ""), {}, token="x")["status"] == "unknown"
    assert argocd(lambda *_: (0, good), {}, token="")["status"] == "unknown"


def test_reachability_healthy_degraded_unknown_and_debounce():
    good = json.dumps({"verdict": "ok", "hosts": []})
    bad = json.dumps({"verdict": "edge-down", "hosts": [{"healthy": False}]})
    healthy = reachability(lambda *_: (0, good), {})
    assert_normalized(healthy, "reachability")
    assert healthy["status"] == "healthy"
    state = {}
    assert [reachability(lambda *_: (2, bad), state)["status"] for _ in range(3)] == ["healthy", "healthy", "degraded"]
    assert reachability(lambda *_: (3, "{}"), {})["status"] == "unknown"


def test_node_pressure_healthy_degraded_unknown_and_debounce():
    good = health([{"name": "Data layer", "ok": True, "detail": "4/4 ready"}])
    bad = health([{"name": "Data layer", "ok": False, "detail": "1 not ready"},
                  {"name": "ArgoCD", "ok": False, "detail": "HTTP 502"}])
    healthy = node_pressure(webhook(good), {}, token="x")
    assert_normalized(healthy, "node_pressure")
    assert healthy["status"] == "healthy"
    state = {}
    assert [node_pressure(webhook(bad), state, token="x")["status"] for _ in range(3)] == ["healthy", "healthy", "degraded"]
    assert node_pressure(webhook(health([{"name": "Data layer", "ok": None}])), {}, token="x")["status"] == "unknown"
    assert node_pressure(webhook(good), {}, token="")["status"] == "unknown"


def test_ci_healthy_degraded_unknown_and_debounce():
    now = datetime(2026, 9, 5, tzinfo=timezone.utc)
    def source(conclusion="success", status="completed"):
        def fetch(url, _headers):
            if "actions/runs" in url:
                return {"workflow_runs": [{"head_sha": "abc"}]}
            return {"check_runs": [{"name": "test", "conclusion": conclusion, "status": status,
                                    "started_at": "2026-09-05T00:00:00Z"}]}
        return fetch
    healthy = ci(source(), {}, token="x", now=now)
    assert_normalized(healthy, "ci")
    assert healthy["status"] == "healthy"
    state = {}
    assert [ci(source("failure"), state, token="x", now=now)["status"] for _ in range(2)] == ["healthy", "degraded"]
    assert ci(lambda *_: (_ for _ in ()).throw(RuntimeError()), {}, token="x", now=now)["status"] == "unknown"
    assert ci(source(), {}, token="", now=now)["status"] == "unknown"
    stuck_now = datetime(2026, 9, 5, 2, tzinfo=timezone.utc)
    assert ci(source("success", "in_progress"), {"debounce": {"ci": 1}}, token="x", now=stuck_now)["status"] == "degraded"


def sensor(name, status):
    return {"sensor": name, "status": status, "evidence": name, "sampled_at": "2026-09-05T12:00:00Z"}


def test_correlator_fire_silence_dedupe_resolved_and_unknown():
    corr, state = Correlator(correlation_window=1), {}
    assert corr.process([sensor("eso", "degraded")], state) is None
    incident = corr.process([sensor("eso", "degraded"), sensor("ci", "degraded")], state)
    assert incident["kind"] == "incident"
    assert corr.process([sensor("eso", "degraded"), sensor("ci", "degraded")], state) is None
    assert corr.process([sensor("eso", "healthy"), sensor("ci", "healthy")], state)["kind"] == "resolved"
    assert Correlator().process([sensor("eso", "unknown"), sensor("ci", "unknown")], {}) is None


def test_llm_budget_cap_and_deterministic_fallback():
    calls, state = [], {}
    corr = Correlator(correlation_window=1, daily_budget=1)
    llm = lambda text, provider: calls.append(provider) or "LLM summary"
    assert corr.process([sensor("eso", "degraded"), sensor("ci", "degraded")], state, llm, "2026-09-05")["text"] == "LLM summary"
    corr.process([sensor("eso", "healthy"), sensor("ci", "healthy")], state)
    fallback = corr.process([sensor("eso", "degraded"), sensor("ci", "degraded")], state, llm, "2026-09-05")
    assert calls == ["gemini"]
    assert fallback["text"].startswith("Hermes incident:")


def test_claude_is_not_an_llm_summary_author():
    calls = []
    event = Correlator(provider="claude").process(
        [sensor("eso", "degraded"), sensor("ci", "degraded")], {},
        lambda *_: calls.append(True), "2026-09-05")
    assert not calls
    assert event["text"].startswith("Hermes incident:")
