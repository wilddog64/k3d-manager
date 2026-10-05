import importlib.machinery
import importlib.util
import json
import plistlib
import sys
from pathlib import Path
from types import SimpleNamespace

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "lib"))
from hermes import app_health_triage, e2e_bugs
from hermes.sensors import app_health


ROOT = Path(__file__).resolve().parents[3]
loader = importlib.machinery.SourceFileLoader("k3dm_hermes_app_health", str(ROOT / "bin" / "k3dm-hermes"))
spec = importlib.util.spec_from_loader("k3dm_hermes_app_health", loader)
k3dm_hermes = importlib.util.module_from_spec(spec)
loader.exec_module(k3dm_hermes)


TARGET = {"service": "payment-service", "namespace": "shopping-cart-payment", "port": 8084}


def _run_for(payloads):
    calls = []

    def run(argv, _env):
        calls.append(argv)
        path = argv[-1].split("/proxy", 1)[1]
        value = payloads[path]
        if isinstance(value, tuple):
            return value
        return 0, json.dumps(value)

    return run, calls


def _delta_payload(aggregate=None, liveness=None, readiness=None):
    return {
        "/actuator/health": aggregate or {"status": "DOWN"},
        "/actuator/health/liveness": liveness or {"status": "UP"},
        "/actuator/health/readiness": readiness or {"status": "UP"},
    }


def test_delta_is_degraded_after_debounce():
    run, _calls = _run_for(_delta_payload())
    state = {}
    assert app_health(run, state, [TARGET], context="app") ["status"] == "healthy"
    assert app_health(run, state, [TARGET], context="app")["status"] == "healthy"
    third = app_health(run, state, [TARGET], context="app")
    assert third["status"] == "degraded"
    assert "payment-service" in third["evidence"]


def test_down_components_are_reported():
    run, _calls = _run_for(_delta_payload({"status": "DOWN", "components": {
        "rabbit": {"status": "DOWN"}, "db": {"status": "UP"}}}))
    item = app_health(run, {}, [TARGET], context="app")
    assert item["data"]["down_components"] == {"payment-service": ["rabbit"]}


def test_group_visible_outage_is_not_this_sensors_concern():
    run, _calls = _run_for(_delta_payload(readiness={"status": "DOWN"}))
    item = app_health(run, {}, [TARGET], context="app")
    assert item["status"] == "healthy"
    assert "argocd" in item["evidence"]


def test_all_up_is_healthy_with_one_call_per_service():
    run, calls = _run_for({"/actuator/health": {"status": "UP"},
                           "/actuator/health/liveness": {"status": "DOWN"},
                           "/actuator/health/readiness": {"status": "DOWN"}})
    item = app_health(run, {}, [TARGET], context="app")
    assert item["status"] == "healthy"
    assert len(calls) == 1


def test_unreachable_aggregate_is_unknown_not_healthy():
    run, _calls = _run_for({"/actuator/health": (1, "")})
    assert app_health(run, {}, [TARGET], context="app")["status"] == "unknown"
    run, _calls = _run_for({"/actuator/health": (0, "not-json")})
    assert app_health(run, {}, [TARGET], context="app")["status"] == "unknown"
    run, _calls = _run_for({"/actuator/health": {"detail": "missing status"}})
    assert app_health(run, {}, [TARGET], context="app")["status"] == "unknown"


def test_missing_group_endpoint_is_unknown():
    run, _calls = _run_for(_delta_payload(liveness=(1, "")))
    item = app_health(run, {}, [TARGET], context="app")
    assert item["status"] == "unknown"


def test_one_bad_service_does_not_mask_the_others():
    good = {"service": "good", "namespace": "ns", "port": 1}
    bad = {"service": "bad", "namespace": "ns", "port": 2}
    run, _calls = _run_for({
        "/actuator/health": {"status": "UP"},
    })
    def mixed(argv, env):
        if ":2/proxy" in argv[-1]:
            return 1, ""
        return run(argv, env)
    assert app_health(mixed, {}, [good, bad], context="app")["status"] == "unknown"


def test_no_targets_and_no_context_are_unknown():
    assert app_health(lambda *_: (_ for _ in ()).throw(AssertionError()), {}, [])["status"] == "unknown"
    assert app_health(lambda *_: (_ for _ in ()).throw(AssertionError()), {}, [TARGET])["status"] == "unknown"


def test_triage_produces_a_stable_slug():
    data = {"z-service": ["db"], "a-service": ["rabbit"]}
    first = app_health_triage.triage(data)
    second = app_health_triage.triage(data)
    assert [item["target"] for item in first] == ["a-service", "z-service"]
    assert [item["slug"] for item in first] == [item["slug"] for item in second]


def test_app_health_doc_names_the_component_and_the_gap():
    group = app_health_triage.triage({"payment-service": ["rabbit"]})[0]
    text = e2e_bugs._doc(group, {"source": "app-health", "run_id": "r1"},
                         "k3d-manager-v1.40.0", "2026-10-01")
    assert "rabbit" in text
    assert "probe groups" in text and "liveness" in text and "readiness" in text
    assert "2026-09-16" in text


def test_commit_subject_says_app_health(monkeypatch, tmp_path):
    calls = []
    def fake_run(argv, **_kwargs):
        calls.append(argv)
        return SimpleNamespace(returncode=0, stdout="", stderr="")
    monkeypatch.setattr(e2e_bugs, "_run", fake_run)
    result = e2e_bugs._commit_push(tmp_path, [Path("docs/bugs/x.md")], "slot",
                                   {"source": "app-health", "run_id": "r1"},
                                   "k3d-manager-v1.40.0")
    assert result == "pushed"
    commit = next(argv for argv in calls if "commit" in argv)
    assert "app-health" in " ".join(commit)


def test_launchagent_template_enables_app_health_for_ubuntu_hostinger():
    template = (ROOT / "scripts" / "etc" / "launchd" /
                "com.k3d-manager.hermes.plist.tmpl").read_text()
    for placeholder in ("HERMES_BIN", "K3DM_REPO_ROOT", "HERMES_LOG"):
        template = template.replace("{{" + placeholder + "}}", "dummy")
    plist = plistlib.loads(template.encode())
    environment = plist["EnvironmentVariables"]
    assert environment["K3DM_HERMES_APP_HEALTH_ENABLED"] == "1"
    assert environment["K3DM_HERMES_APP_CONTEXT"] == "ubuntu-hostinger"
    assert environment["K3DM_HERMES_PROVIDER"] == "k3s-hostinger"
    assert environment["K3DM_HERMES_APPROVAL_DRAIN_URL"] == "https://k3dm-slack-relay.k3dm.workers.dev/hermes/approvals"


def test_run_cycle_webhook_fetch_pins_hostinger_provider(monkeypatch):
    monkeypatch.setenv("K3DM_HERMES_PROVIDER", "k3s-hostinger")
    monkeypatch.setattr(k3dm_hermes, "_keychain_secret", lambda *_: "dummy")
    urls = []
    monkeypatch.setattr(k3dm_hermes, "_http_json",
                        lambda url, _headers: urls.append(url) or {"services": []})
    for name in ("eso", "argocd", "values_branch", "reachability", "node_pressure",
                 "hostnet_drift", "kine", "vectordb", "alert_delivery", "ci", "app_health"):
        monkeypatch.setattr(k3dm_hermes, name, lambda *_args, **_kwargs: {
            "sensor": "stub", "status": "healthy", "evidence": "stub", "data": {}
        })

    k3dm_hermes._run_cycle({})

    assert urls and urls[0].endswith("provider=k3s-hostinger")
