import base64
import importlib.machinery
import importlib.util
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "lib"))

from hermes.correlator import Correlator
from hermes.sensors import (argocd, ci, eso, github_token_expiry, kine, kine_log_signals,
                            node_pressure, reachability, stale_acg_registration,
                            status_checks, token_expiry_advisory)

ROOT = Path(__file__).resolve().parents[3]
loader = importlib.machinery.SourceFileLoader("k3dm_hermes_status", str(ROOT / "bin" / "k3dm-hermes"))
spec = importlib.util.spec_from_loader("k3dm_hermes_status", loader)
k3dm_hermes = importlib.util.module_from_spec(spec)
loader.exec_module(k3dm_hermes)


def status_payload(overall, checks=None):
    checks = checks or []
    return json.dumps({"overall": overall, "checks": checks,
                       "counts": {"services_failed": len([item for item in checks if item.get("status") == "error"]),
                                  "services_warning": len([item for item in checks if item.get("status") == "warning"]),
                                  "services_healthy": 0}})


def test_status_checks_debounce_warn_and_unknown_contracts():
    failed = [{"id": "frontend_sso_login", "status": "error", "message": "HTTP 400"},
              {"id": "argocd_sso_login", "status": "error", "message": "HTTP 400"}]
    state = {}
    records = [status_checks(lambda *_: (1, status_payload("fail", failed)), state) for _ in range(2)]
    assert [item["status"] for item in records] == ["healthy", "degraded"]
    assert records[-1]["data"]["failed_ids"] == ["frontend_sso_login", "argocd_sso_login"]
    warning = status_checks(lambda *_: (0, status_payload("warn", [{"id": "grafana", "status": "warning"}])), {})
    assert warning["status"] == "healthy"
    assert warning["data"]["warned_ids"] == ["grafana"]
    assert status_checks(lambda *_: (2, status_payload("unknown")), {})["status"] == "unknown"


def test_status_checks_handles_invalid_empty_and_timeout_output_as_unknown():
    assert status_checks(lambda *_: (0, "not-json"), {})["status"] == "unknown"
    assert status_checks(lambda *_: (0, ""), {})["status"] == "unknown"
    assert status_checks(lambda *_: (_ for _ in ()).throw(TimeoutError()), {})["status"] == "unknown"


def test_status_interval_gate_wires_sensor_and_can_be_disabled(monkeypatch):
    monkeypatch.setenv("K3DM_HERMES_STATUS_ENABLED", "1")
    monkeypatch.setattr(k3dm_hermes, "_keychain_secret", lambda *_: "")
    monkeypatch.setenv("K3DM_HERMES_STATUS_INTERVAL_MIN", "39")
    calls = []
    runner = lambda *_: calls.append(True) or (0, status_payload("healthy"))
    for name in ("eso", "argocd", "reachability", "node_pressure", "kine", "ci"):
        monkeypatch.setattr(k3dm_hermes, name,
                            lambda *_args, sensor_name=name, **_kwargs: sensor(sensor_name, "healthy"))
    state = {}
    assert k3dm_hermes._status_due(state, 1_000)
    records, _event = k3dm_hermes._run_cycle(state, runner)
    state["status_last_run"] = 1_000
    assert not k3dm_hermes._status_due(state, 1_000 + 38 * 60)
    assert k3dm_hermes._status_due(state, 1_000 + 39 * 60)
    assert calls == [True]
    assert next(item for item in records if item["sensor"] == "status_checks")["status"] == "healthy"
    monkeypatch.setenv("K3DM_HERMES_STATUS_ENABLED", "0")
    assert not k3dm_hermes._status_due({}, 1_000)


def test_status_notifications_are_state_change_only(monkeypatch):
    posted = []
    monkeypatch.setattr(k3dm_hermes, "post_summary", lambda _relay, text: posted.append(text))
    monkeypatch.setattr(k3dm_hermes.e2e_bugs, "file_bugs", lambda *_args, **_kwargs: {"push": "stubbed"})
    monkeypatch.setattr(k3dm_hermes, "_status_local_date", lambda: "2026-09-16")
    record = {"data": {"checks": [{"id": "frontend_sso_login", "message": "HTTP 400", "status": "error"}], "counts": {"services_failed": 1}}}
    state = {}
    k3dm_hermes._status_notification(state, record, "relay")
    assert len(posted) == 1 and "frontend_sso_login" in posted[0]
    k3dm_hermes._status_notification(state, record, "relay")
    assert len(posted) == 1
    k3dm_hermes._status_notification(state, {"data": {"checks": [], "counts": {}}}, "relay")
    assert len(posted) == 2 and "recovered" in posted[-1]


def _stub_status_poll(monkeypatch, payload):
    from hermes import audit
    monkeypatch.setenv("K3DM_HERMES_STATUS_ENABLED", "1")
    monkeypatch.setenv("K3DM_HERMES_STATUS_INTERVAL_MIN", "39")
    monkeypatch.setattr(k3dm_hermes, "_keychain_secret", lambda *_: "")
    monkeypatch.setattr(k3dm_hermes, "_drain_approvals", lambda *_: [])
    monkeypatch.setattr(k3dm_hermes, "token_expiry_advisory", lambda *_args, **_kw: None)
    monkeypatch.setattr(audit, "monthly_audit_advisory", lambda *_args, **_kw: None)
    monkeypatch.setattr(k3dm_hermes.pager, "security_events", lambda *_: [])
    monkeypatch.setattr(k3dm_hermes, "_schedule_e2e", lambda *_: None)
    monkeypatch.setattr(k3dm_hermes, "_publish_status", lambda *_: True)
    monkeypatch.setattr(k3dm_hermes, "_page", lambda _state, texts, _relay: texts)
    for name in ("eso", "argocd", "reachability", "node_pressure", "kine", "ci"):
        monkeypatch.setattr(k3dm_hermes, name,
                            lambda *_args, sensor_name=name, **_kwargs: sensor(sensor_name, "healthy"))
    calls = []
    return calls, lambda *_: calls.append(True) or (0, payload)


def test_status_poll_advances_gate_only_when_sampled_and_defaults_off(monkeypatch, tmp_path, capsys):
    calls, runner = _stub_status_poll(monkeypatch, status_payload("healthy"))
    state, path = {}, tmp_path / "state.json"
    monkeypatch.delenv("K3DM_HERMES_STATUS_ENABLED")
    k3dm_hermes._poll(state, path, now=1000, status_runner=runner)
    assert calls == [] and "status_last_run" not in state
    monkeypatch.setenv("K3DM_HERMES_STATUS_ENABLED", "1")
    for now in (1000, 1300, 3340):
        k3dm_hermes._poll(state, path, now=now, status_runner=runner)
    assert len(calls) == 2 and state["status_last_run"] == 3340
    assert json.loads(path.read_text())["status_last_run"] == 3340
    monkeypatch.setenv("K3DM_HERMES_STATUS_ENABLED", "0")
    k3dm_hermes._poll(state, path, now=6000, status_runner=runner)
    assert len(calls) == 2


def test_unknown_status_poll_never_pages_or_files_and_preserves_open_groups(monkeypatch, tmp_path, capsys):
    calls, runner = _stub_status_poll(monkeypatch, status_payload("unknown"))
    def unexpected(*_args, **_kw):
        raise AssertionError("unknown status must not notify or file")
    monkeypatch.setattr(k3dm_hermes, "post_summary", unexpected)
    monkeypatch.setattr(k3dm_hermes.e2e_bugs, "file_bugs", unexpected)
    groups = [{"slug": "e2e-sso-auth-frontend-sso-login"}]
    state = {"status_groups": groups}
    for n in range(7):
        k3dm_hermes._poll(state, tmp_path / "state.json", now=1000 + n * 2400, status_runner=runner)
        output = json.loads(capsys.readouterr().out)
        assert output["pages"] == []
        assert output["records"][-1]["status"] == "unknown"
    assert len(calls) == 7 and state["status_groups"] == groups


def test_status_poll_redacts_nested_payload_before_stdout(monkeypatch, tmp_path, capsys):
    payload = status_payload("fail", [{"id": "frontend_sso_login", "status": "error",
                                      "message": "password=TEST_SENTINEL",
                                      "extra": {"detail": ["Bearer NESTED_SENTINEL"]}}])
    _calls, runner = _stub_status_poll(monkeypatch, payload)
    k3dm_hermes._poll({}, tmp_path / "state.json", now=1000, status_runner=runner)
    output = capsys.readouterr().out
    assert "TEST_SENTINEL" not in output and "NESTED_SENTINEL" not in output
    assert "<redacted>" in output


def test_status_reminder_waits_for_local_midnight(monkeypatch):
    from datetime import timedelta
    class LocalClock:
        current = datetime(2026, 9, 16, 23, 50, tzinfo=timezone(timedelta(hours=-7)))
        @classmethod
        def now(cls):
            return cls
        @classmethod
        def astimezone(cls):
            return cls.current
    monkeypatch.setattr(k3dm_hermes, "datetime", LocalClock)
    monkeypatch.setattr(k3dm_hermes, "timestamp", lambda: "2026-09-17T06:50:00Z")
    posted, filed = [], []
    monkeypatch.setattr(k3dm_hermes, "post_summary", lambda _relay, text: posted.append(text))
    monkeypatch.setattr(k3dm_hermes.e2e_bugs, "file_bugs",
                        lambda *args: filed.append(args) or {"push": "stubbed"})
    record = {"sampled_at": "2026-09-17T06:50:00Z", "data": {"checks": [
        {"id": "frontend_sso_login", "status": "error", "message": "HTTP 400"}],
        "counts": {"services_failed": 1}}}
    state = {}
    k3dm_hermes._status_notification(state, record, "relay")
    assert state["status_reminder_date"] == "2026-09-16"
    assert filed[0][2]["source"] == "status" and filed[0][3] == "2026-09-16"
    k3dm_hermes._status_notification(state, record, "relay")
    assert len(posted) == 1
    LocalClock.current += timedelta(minutes=20)
    k3dm_hermes._status_notification(state, record, "relay")
    k3dm_hermes._status_notification(state, record, "relay")
    assert len(posted) == 2 and "ongoing" in posted[-1]
    assert len(filed) == 1


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


def test_stale_acg_registration_decodes_base64_secret_data():
    def secret(server):
        return {"metadata": {"name": "cluster-x"},
                "data": {"server": base64.b64encode(server.encode()).decode()}}
    assert "host.k3d.internal" not in json.dumps(secret("https://host.k3d.internal:6443"))
    assert stale_acg_registration([secret("https://host.k3d.internal:6443")]) is True
    assert stale_acg_registration([secret("https://kubernetes.default.svc")]) is False
    assert stale_acg_registration([{"data": {"server": "not base64!"}}]) is False
    assert stale_acg_registration([{"stringData": {"server": "https://host.k3d.internal:6443"}}]) is True
    assert stale_acg_registration([]) is False


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


def test_correlator_re_pages_when_a_sensor_joins_an_active_incident():
    corr, state = Correlator(correlation_window=1), {}
    assert corr.process([sensor("kine", "degraded"), sensor("eso", "degraded")], state)["kind"] == "incident"
    assert corr.process([sensor("kine", "degraded"), sensor("eso", "degraded")], state) is None
    escalation = corr.process([sensor("kine", "degraded"), sensor("eso", "degraded"),
                               sensor("reachability", "degraded")], state)
    assert escalation["kind"] == "escalation"
    assert "reachability" in escalation["text"]
    assert corr.process([sensor("kine", "degraded"), sensor("eso", "degraded"),
                         sensor("reachability", "degraded")], state) is None
    assert corr.process([sensor("kine", "healthy"), sensor("eso", "healthy"),
                         sensor("reachability", "healthy")], state)["kind"] == "resolved"
    assert state["incident_sensors"] == []


def test_correlator_does_not_re_page_a_flapping_sensor_within_one_incident():
    corr, state = Correlator(correlation_window=1), {}
    corr.process([sensor("kine", "degraded"), sensor("eso", "degraded")], state)
    corr.process([sensor("kine", "degraded"), sensor("eso", "degraded"),
                  sensor("reachability", "degraded")], state)
    assert corr.process([sensor("kine", "degraded"), sensor("eso", "degraded")], state) is None
    assert corr.process([sensor("kine", "degraded"), sensor("eso", "degraded"),
                         sensor("reachability", "degraded")], state) is None


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
