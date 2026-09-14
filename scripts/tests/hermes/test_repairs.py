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


def r5_records(stale=True):
    return [record("kine", "degraded", data={"state_db_bytes": 9 * 1024 * 1024 * 1024,
                   "slow_sql_count": 2, "compaction_recent": False,
                   "stale_acg_registration": stale})]


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
    monkeypatch.setattr(repairs, "_keychain_secret", lambda service: "token")
    assert [item["key"] for item in repairs.propose(r4_records(), state())] == ["r4"]
    assert repairs.propose(r4_records("failure"), state()) == []


def r6_records(slow_sql=2, recent=False, failed=False, db_bytes=554 * 1024 * 1024):
    return [record("kine", "degraded", data={"state_db_bytes": db_bytes,
                   "slow_sql_count": slow_sql, "compaction_recent": recent,
                   "compaction_failed": failed, "stale_acg_registration": False})]


def test_r5_requires_the_specific_stale_acg_kine_signature():
    keys = [item["key"] for item in repairs.propose(r5_records(), state())]
    assert keys[0] == "r5"
    # Without the stale ACG signature R5 must not fire, but a compaction stall
    # is still a real incident, so R6 proposes the lever that actually works.
    assert [item["key"] for item in repairs.propose(r5_records(False), state())] == ["r6"]


def test_r6_proposes_server_restart_on_compaction_stall_below_size_threshold():
    proposal = repairs.propose(r6_records(), state())[0]
    assert proposal["key"] == "r6"
    assert proposal["command"] == "docker restart k3d-k3d-cluster-server-0"
    assert repairs.propose(r6_records(failed=True, slow_sql=0, recent=True),
                           state())[0]["key"] == "r6"


def test_r6_silent_when_compaction_is_progressing():
    assert repairs.propose(r6_records(slow_sql=2, recent=True), state()) == []
    assert repairs.propose(r6_records(slow_sql=0, recent=False), state()) == []


def test_r6_is_never_auto_executed_by_the_kine_guard():
    """The auto guard is R5-only; restarting the control plane stays human-approved."""
    current, calls = state(), []
    outcome = repairs.auto_remediate_kine(
        r6_records(), current, lambda *args: calls.append(args) or (0, ""), True)
    assert outcome is None
    assert calls == []
    assert "r6" not in current.get("repairs_attempted_this_incident", [])


def test_r5_auto_guard_is_opt_in_and_runs_once():
    current, calls = state(), []
    assert repairs.auto_remediate_kine(r5_records(), current, lambda *args: calls.append(args), False) is None
    proposal = repairs.propose(r5_records(), current)[0]
    outcome = repairs.auto_remediate_kine(r5_records(), current,
                                          lambda *args: calls.append(args) or (0, "paused"), True)
    assert outcome["outcome"] == "executed" and outcome["automatic"] is True
    assert calls[-1][0][-1] == "--replicas=0"
    assert proposal["action_id"] not in current["pending_repairs"]
    assert repairs.auto_remediate_kine(r5_records(), current, lambda *_: (0, ""), True) is None


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
    monkeypatch.setattr(repairs, "_keychain_secret", lambda service: "token")
    current = state()
    proposal = repairs.propose(r4_records(), current)[0]
    outcome = repairs.approve(proposal["action_id"], current, r4_records(),
                              lambda *_: (1, "Resource not accessible by personal access token"))
    assert outcome["outcome"] == "skipped: token lacks actions:write"


def test_r4_refuses_when_hermes_token_missing_no_ambient_auth(monkeypatch):
    monkeypatch.setattr(repairs, "_keychain_secret", lambda service: "")
    current = state()
    proposal = repairs.propose(r4_records(), current)[0]
    calls = []
    outcome = repairs.approve(proposal["action_id"], current, r4_records(),
                              lambda *a: calls.append(a) or (0, ""))
    assert outcome["outcome"] == "skipped: hermes GitHub token unavailable"
    assert not calls
    assert "r4" not in current.get("repairs_attempted_this_incident", [])


def test_r4_business_logic_403_is_not_misclassified_as_missing_scope(monkeypatch):
    monkeypatch.setattr(repairs, "_keychain_secret", lambda service: "token")
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


def test_r4_command_uses_keychain_pat(monkeypatch):
    monkeypatch.setattr(repairs, "_keychain_secret",
                        lambda service: "pat-token" if service == repairs.GITHUB_SERVICE else "")

    _argv, env = repairs._r4_command(r4_records())

    assert env == {"GH_TOKEN": "pat-token"}
