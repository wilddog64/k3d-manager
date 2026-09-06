import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "lib"))

from hermes import repairs


def record(name, status, evidence="source unavailable", data=None):
    return {"sensor": name, "status": status, "evidence": evidence,
            "sampled_at": "2026-09-06T12:00:00Z", "data": data or {}}


def state(history=None):
    return {"correlation_history": history or []}


def r2_records(verdict="single-service"):
    return [record("reachability", "degraded", data={"verdict": verdict,
                   "failed_hosts": ["prometheus.3ai-talk.org"]}),
            record("node_pressure", "healthy", "healthy")]


def r4_records(conclusion="timed_out"):
    return [record("ci", "degraded", data={"repo": "wilddog64/k3d-manager",
                   "run_id": 123, "conclusion": conclusion})]


def test_single_degraded_sensor_proposes_nothing():
    assert repairs.propose([record("eso", "degraded", "bad")], state()) == []


def test_r1_fires_only_when_both_webhook_sensors_unknown_sustained():
    inputs = [record("eso", "unknown"), record("node_pressure", "unknown")]
    current = state()
    assert repairs.propose(inputs, current) == []
    assert [item["key"] for item in repairs.propose(inputs, current)] == ["r1"]


def test_r2_fires_on_single_service_with_healthy_substrate():
    proposals = repairs.propose(r2_records(), state())
    assert proposals[0]["key"] == "r2"
    assert proposals[0]["command"] == "launchctl kickstart -k com.k3d-manager.prometheus-port-forward"
    assert repairs.propose(r2_records("edge-down"), state()) == []


def test_r3_fires_on_edge_down_sustained():
    inputs = [record("reachability", "degraded", data={"verdict": "edge-down", "failed_hosts": []})]
    assert [item["key"] for item in repairs.propose(inputs, state([["reachability"], ["reachability"]]))] == ["r3"]


def test_r4_fires_only_on_transient_conclusion(monkeypatch):
    monkeypatch.setattr(repairs, "_r4_token", lambda: ("token", "pat"))
    assert [item["key"] for item in repairs.propose(r4_records(), state())] == ["r4"]
    assert repairs.propose(r4_records("failure"), state()) == []


def test_approve_refuses_when_precondition_no_longer_holds():
    current = state()
    proposal = repairs.propose(r2_records(), current)[0]
    calls = []
    outcome = repairs.approve(proposal["action_id"], current,
                              [record("reachability", "healthy", "healthy"),
                               record("node_pressure", "healthy", "healthy")],
                              lambda *args: calls.append(args))
    assert outcome["outcome"] == "refused: precondition no longer holds"
    assert not calls


def test_approve_refuses_unknown_or_non_allowlist_action():
    current = state()
    assert repairs.approve("bogus", current, [], lambda *_: (0, ""))["outcome"].startswith("refused")
    current["pending_repairs"] = {"bad": {"key": "not-r", "action_id": "bad"}}
    assert repairs.approve("bad", current, [], lambda *_: (0, ""))["outcome"] == "refused: action is not allowlisted"


def test_approve_runs_lever_and_records_audit():
    current = state()
    proposal = repairs.propose(r2_records(), current)[0]
    calls = []

    def runner(argv, env, cwd):
        calls.append((argv, env, cwd))
        return 0, "done"

    outcome = repairs.approve(proposal["action_id"], current, r2_records(), runner)
    assert outcome["outcome"] == "executed"
    assert calls == [(["launchctl", "kickstart", "-k", "com.k3d-manager.prometheus-port-forward"], {}, None)]
    assert current["repair_audit"][0]["action_id"] == proposal["action_id"]
    assert current["repairs_attempted_this_incident"] == ["r2"]


def test_r4_degrades_to_skipped_on_permission_error(monkeypatch):
    monkeypatch.setattr(repairs, "_r4_token", lambda: ("token", "pat"))
    current = state()
    proposal = repairs.propose(r4_records(), current)[0]
    outcome = repairs.approve(proposal["action_id"], current, r4_records(),
                              lambda *_: (1, "Resource not accessible by personal access token"))
    assert outcome["outcome"] == "skipped: token lacks actions:write"


def test_r4_refuses_when_hermes_token_missing_no_ambient_auth(monkeypatch):
    monkeypatch.setattr(repairs, "_r4_token", lambda: ("", "pat"))
    current = state()
    proposal = repairs.propose(r4_records(), current)[0]
    calls = []
    outcome = repairs.approve(proposal["action_id"], current, r4_records(),
                              lambda *a: calls.append(a) or (0, ""))
    assert outcome["outcome"] == "skipped: hermes GitHub token unavailable"
    assert not calls
    assert "r4" not in current.get("repairs_attempted_this_incident", [])


def test_r4_business_logic_403_is_not_misclassified_as_missing_scope(monkeypatch):
    monkeypatch.setattr(repairs, "_r4_token", lambda: ("token", "pat"))
    current = state()
    proposal = repairs.propose(r4_records(), current)[0]
    outcome = repairs.approve(proposal["action_id"], current, r4_records(),
                              lambda *_: (1, "This workflow run cannot be retried (HTTP 403)"))
    assert outcome["outcome"] == "failed"


def test_approve_refuses_second_action_for_already_attempted_key():
    current = state()
    proposal = repairs.propose(r2_records(), current)[0]
    assert repairs.approve(proposal["action_id"], current, r2_records(),
                           lambda *_: (0, "done"))["outcome"] == "executed"
    current["pending_repairs"]["r2-stale"] = {**proposal, "action_id": "r2-stale"}
    outcome = repairs.approve("r2-stale", current, r2_records(), lambda *_: (0, "done"))
    assert outcome["outcome"] == "refused: repair already attempted this incident"


def test_propose_is_idempotent_per_condition():
    current = state()
    first = repairs.propose(r2_records(), current)
    second = repairs.propose(r2_records(), current)
    assert first[0]["action_id"] == second[0]["action_id"]
    assert list(current["pending_repairs"]) == [first[0]["action_id"]]


def test_r4_precondition_requires_repo_to_avoid_keyerror():
    records = [record("ci", "degraded", data={"run_id": 123, "conclusion": "timed_out"})]
    assert repairs.propose(records, state()) == []


def test_approve_pops_pending_proposal():
    current = state()
    proposal = repairs.propose(r2_records(), current)[0]
    assert proposal["action_id"] in current["pending_repairs"]
    repairs.approve(proposal["action_id"], current, r2_records(), lambda *_: (0, "done"))
    assert proposal["action_id"] not in current["pending_repairs"]


def test_no_repair_runs_in_poll_path():
    current = state()
    proposals = repairs.propose(r2_records(), current)
    assert proposals and "repair_audit" not in current


def test_r4_uses_github_app_token_when_app_credentials_are_present(monkeypatch):
    secrets = {
        repairs.APP_ID_SERVICE: "app-id",
        repairs.APP_INSTALLATION_SERVICE: "installation-id",
        repairs.APP_PRIVATE_KEY_SERVICE: "private-key",
    }
    monkeypatch.setattr(repairs, "_keychain_secret", lambda service: secrets.get(service, ""))
    from hermes import github_app
    calls = []
    monkeypatch.setattr(github_app, "installation_token",
                        lambda *args: calls.append(args) or "app-token")

    _argv, env = repairs._r4_command(r4_records())

    assert calls == [("app-id", "installation-id", "private-key")]
    assert env == {"GH_TOKEN": "app-token"}


def test_r4_falls_back_to_pat_when_app_credentials_are_absent(monkeypatch):
    monkeypatch.setattr(repairs, "_keychain_secret",
                        lambda service: "pat-token" if service == repairs.GITHUB_SERVICE else "")

    _argv, env = repairs._r4_command(r4_records())

    assert env == {"GH_TOKEN": "pat-token"}
