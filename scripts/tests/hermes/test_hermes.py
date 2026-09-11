import json
import sys
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "lib"))

from hermes.correlator import Correlator
from hermes.sensors import (argocd, ci, eso, github_token_expiry, kine, kine_log_signals,
                            node_pressure, reachability, token_expiry_advisory)


def health(entries):
    return {"services": entries, "all_ok": all(x["ok"] is not False for x in entries)}


def webhook(payload):
    return lambda _url, _headers: payload


def assert_normalized(item, sensor):
    assert set(item) == {"sensor", "status", "evidence", "sampled_at", "data"}
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


def test_argocd_flags_failed_operation_behind_green_status():
    def app(name, health, sync, phase):
        status = {"health": {"status": health}, "sync": {"status": sync}}
        if phase:
            status["operationState"] = {"phase": phase}
        return {"metadata": {"name": name}, "spec": {"project": "shop"}, "status": status}

    green_failed = json.dumps([app("identity", "Healthy", "Synced", "Failed")])
    state = {}
    results = [argocd(lambda *_: (0, green_failed), state, token="x") for _ in range(4)]
    assert [r["status"] for r in results] == ["healthy", "healthy", "healthy", "degraded"]
    assert "shop/identity" in results[-1]["evidence"]
    assert "last-op=Failed" in results[-1]["evidence"]

    green_error = json.dumps([app("data-layer", "Healthy", "Synced", "Error")])
    error_state = {}
    assert [argocd(lambda *_: (0, green_error), error_state, token="x")["status"]
            for _ in range(4)][-1] == "degraded"

    for benign in ("Succeeded", "Running", "Terminating", None):
        payload = json.dumps([app("ok", "Healthy", "Synced", benign)])
        out = argocd(lambda *_: (0, payload), {}, token="x")
        assert out["status"] == "healthy", f"phase {benign} must not alert"
        assert out["evidence"] == "1 applications healthy"


def test_argocd_evidence_names_apps_from_cr_shape_and_truncates():
    apps = [{"metadata": {"name": f"app{i}"}, "spec": {"project": "shop"},
             "status": {"health": {"status": "Degraded"}, "sync": {"status": "OutOfSync"}}}
            for i in range(5)]
    state = {}
    for _ in range(4):
        out = argocd(lambda *_: (0, json.dumps(apps)), state, token="x")
    assert out["status"] == "degraded"
    assert "shop/app0" in out["evidence"]
    assert "unnamed" not in out["evidence"]
    assert "(+2 more)" in out["evidence"]


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


def test_kine_log_signals_ignores_compact_rev_key_in_slow_sql():
    """A stalled hub emits Slow SQL lines that embed compact_rev_key.

    Regression guard for the 2026-09-11 blind spot: a bare "compact" substring
    test reported compaction_recent=True during a total compaction outage,
    making the stall branch of the kine sensor unreachable.
    """
    stalled = (
        'time="..." level=info msg="Slow SQL (total time: 2.37s): SELECT '
        "( SELECT MAX(crkv.prev_revision) FROM kine AS crkv WHERE "
        "crkv.name = 'compact_rev_key'), kv.id FROM kine AS kv\"\n"
    ) * 3
    signals = kine_log_signals(stalled)
    assert signals["slow_sql_count"] == 3
    assert signals["compaction_recent"] is False
    assert signals["compaction_failed"] is False

    progressing = stalled + (
        'time="..." level=info msg="COMPACT deleted 467 rows from 1000 '
        'revisions in 3.49s - compacted to 1000/91537"\n'
    )
    assert kine_log_signals(progressing)["compaction_recent"] is True

    failing = stalled + (
        'time="..." level=error msg="Compact failed: failed to record compact '
        'revision: sql: transaction has already been committed or rolled back"\n'
    )
    assert kine_log_signals(failing)["compaction_failed"] is True


def test_kine_degrades_on_reported_compaction_failure_below_size_threshold():
    failing = json.dumps({"available": True, "state_db_bytes": 554 * 1024 * 1024,
                          "slow_sql_count": 133, "compaction_recent": False,
                          "compaction_failed": True, "stale_acg_registration": False})
    state = {}
    assert [kine(lambda *_: (0, failing), state)["status"]
            for _ in range(3)] == ["healthy", "healthy", "degraded"]


def test_kine_degraded_only_for_stalled_compaction_or_size_and_never_writes():
    healthy = json.dumps({"available": True, "state_db_bytes": 1024,
                          "slow_sql_count": 0, "compaction_recent": True,
                          "stale_acg_registration": False})
    bad = json.dumps({"available": True, "state_db_bytes": 9 * 1024 * 1024 * 1024,
                      "slow_sql_count": 2, "compaction_recent": False,
                      "stale_acg_registration": True})
    assert kine(lambda *_: (0, healthy), {})["status"] == "healthy"
    state = {}
    assert [kine(lambda *_: (0, bad), state)["status"] for _ in range(3)] == ["healthy", "healthy", "degraded"]
    assert kine(lambda *_: (1, ""), {})["status"] == "unknown"


def test_ci_healthy_degraded_unknown_and_debounce():
    now = datetime(2026, 9, 5, tzinfo=timezone.utc)
    def source(conclusion="success", status="completed"):
        def fetch(url, _headers):
            if "actions/runs" in url:
                return {"workflow_runs": [{"head_sha": "abc", "id": 123}]}
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
    return {"sensor": name, "status": status, "evidence": name,
            "sampled_at": "2026-09-05T12:00:00Z", "data": {}}


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


def token_headers(mapping):
    return lambda _url, _headers: mapping


def test_github_token_expiry_window_and_no_header():
    now = datetime(2026, 11, 25, tzinfo=timezone.utc)
    hdr = token_headers({"github-authentication-token-expiration": "2026-12-04 02:33:02 UTC"})
    info = github_token_expiry(hdr, token="x", warn_days=14, now=now)
    assert info == {"service": "k3dm-hermes-gh-token", "days": 9,
                    "expires_at": "2026-12-04T02:33:02Z"}
    assert github_token_expiry(hdr, token="x", warn_days=5, now=now) is None
    assert github_token_expiry(token_headers({}), token="x", now=now) is None
    assert github_token_expiry(hdr, token="", now=now) is None


def test_token_expiry_advisory_dedup_and_silence():
    now = datetime(2026, 11, 25, tzinfo=timezone.utc)
    hdr = token_headers({"github-authentication-token-expiration": "2026-12-04 02:33:02 UTC"})
    state = {}
    first = token_expiry_advisory(hdr, state, "2026-11-25", token="x", now=now)
    assert first is not None and "k3dm-hermes-gh-token" in first and "preflight" in first
    assert token_expiry_advisory(hdr, state, "2026-11-25", token="x", now=now) is None
    assert token_expiry_advisory(hdr, state, "2026-11-26", token="x", now=now) is not None
    far = token_headers({"github-authentication-token-expiration": "2027-06-01 00:00:00 UTC"})
    assert token_expiry_advisory(far, {}, "2026-11-25", token="x", now=now) is None
    assert token_expiry_advisory(token_headers({}), {}, "2026-11-25", token="x", now=now) is None
