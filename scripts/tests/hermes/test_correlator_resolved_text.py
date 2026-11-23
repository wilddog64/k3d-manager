"""Resolved incident wording reflects the incident and current sensor records."""

from hermes.correlator import Correlator


def record(sensor, status):
    return {"sensor": sensor, "status": status, "evidence": sensor,
            "sampled_at": "2026-11-08T12:00:00Z", "data": {}}


def open_incident(correlation_window=1, names=("ci", "values_branch")):
    corr, state = Correlator(correlation_window=correlation_window), {}
    event = corr.process([record(name, "degraded") for name in names], state)
    if event is None:
        event = corr.process([record(name, "degraded") for name in names], state)
    assert event["kind"] == "incident"
    return corr, state, event


def resolve(corr, state, records):
    event = corr.process(records, state)
    assert event["kind"] == "resolved"
    assert event["sensors"] == []
    assert state["incident_active"] is False
    assert state["incident_sensors"] == []
    return event["text"]


def test_resolved_names_incident_sensors_and_classifies_current_records():
    corr, state, incident = open_incident()
    assert incident["text"].startswith("Hermes incident: ci + values_branch.")
    text = resolve(corr, state, [record("ci", "healthy"),
                                 record("values_branch", "healthy"),
                                 record("new_check", "degraded")])
    assert text == ("Hermes correlated incident resolved (ci + values_branch). "
                    "Cleared: ci, values_branch. Still degraded: new_check. No data: none.")


def test_resolved_lists_silent_sensor_and_unknown_sensor_as_no_data():
    corr, state, _ = open_incident()
    text = resolve(corr, state, [record("ci", "unknown"), record("values_branch", "healthy")])
    assert text == ("Hermes correlated incident resolved (ci + values_branch). "
                    "Cleared: values_branch. Still degraded: none. No data: ci.")

    corr, state, _ = open_incident()
    text = resolve(corr, state, [record("values_branch", "healthy")])
    assert text.endswith("Cleared: values_branch. Still degraded: none. No data: ci.")


def test_resolved_uses_current_records_with_three_cycle_window_and_deduplicates():
    corr, state = Correlator(correlation_window=3), {}
    incident = corr.process([record("ci", "degraded"), record("values_branch", "degraded")], state)
    assert incident["kind"] == "incident"
    healthy = [record("ci", "healthy"), record("values_branch", "healthy")]
    assert corr.process(healthy, state) is None
    assert corr.process(healthy, state) is None
    text = resolve(corr, state, [record("ci", "healthy"), record("ci", "healthy"),
                                 record("values_branch", "healthy")])
    assert text == ("Hermes correlated incident resolved (ci + values_branch). "
                    "Cleared: ci, values_branch. Still degraded: none. No data: none.")


def test_resolved_without_recorded_incident_sensors_uses_fallback_header():
    corr, state, _ = open_incident()
    state["incident_sensors"] = []
    text = resolve(corr, state, [record("ci", "healthy")])
    assert text == ("Hermes correlated incident resolved (sensors not recorded). "
                    "Cleared: none. Still degraded: none. No data: none.")


def test_incident_and_escalation_event_text_remain_unchanged():
    corr, state = Correlator(correlation_window=1), {}
    incident = corr.process([record("ci", "degraded"), record("values_branch", "degraded")], state)
    assert incident["kind"] == "incident"
    assert incident["sensors"] == ["ci", "values_branch"]
    assert incident["text"].startswith("Hermes incident: ci + values_branch.")
    escalation = corr.process([record("ci", "degraded"), record("values_branch", "degraded"),
                               record("new_check", "degraded")], state)
    assert escalation["kind"] == "escalation"
    assert escalation["sensors"] == ["ci", "new_check", "values_branch"]
    assert escalation["text"].startswith("Hermes escalation (new_check joined): ci + new_check + values_branch.")
