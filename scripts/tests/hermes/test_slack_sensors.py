"""Offline contract tests for Slack manifest and relay sensors."""
import copy
import pytest
import re

from hermes import sensors


class Store:
    def __init__(self):
        self.values = {sensors.SLACK_CONFIG_SERVICE: "access-secret",
                       sensors.SLACK_CONFIG_REFRESH_SERVICE: "refresh-secret"}
        self.calls = []

    def read(self, service):
        self.calls.append(("read", service))
        return self.values.get(service, "")

    def write(self, service, value):
        self.calls.append(("write", service, value))
        if service not in self.values:
            return False
        self.values[service] = value
        return True

    def writable(self, service):
        self.calls.append(("writable", service))
        return True


def manifest():
    # Captured settings shape: m5-air.local, 2026-11-13, apps.manifest.export (redacted).
    commands = [{"command": f"/command-{n}", "url": sensors.SLACK_RELAY + "/"}
                for n in range(11)]
    commands += [{"command": "/hermes-auth", "url": sensors.SLACK_RELAY + "/"},
                 {"command": "/legacy-one", "url": sensors.SLACK_RELAY + "/slack/command"},
                 {"command": "/legacy-many", "url": sensors.SLACK_RELAY + "/slack/commands"}]
    return {"settings": {"interactivity": {"is_enabled": True,
                "request_url": sensors.SLACK_RELAY + "/slack/interactivity"},
                "event_subscriptions": {"request_url": "https://example.test/events"}},
            "features": {"slash_commands": commands}}


def test_c13_manifest_fixture_matches_captured_fourteen_command_count():
    assert len(manifest()["features"]["slash_commands"]) == 14


def test_manifest_capture_shape_is_healthy_and_cached():
    state, store, calls = {}, Store(), []
    api = lambda *args: calls.append(args) or {"ok": True, "manifest": manifest()}
    first = sensors.slack_app_config(api, state, store, now=1000)
    assert first["status"] == "healthy" and len(calls) == 1
    counter = copy.deepcopy(state["debounce"])
    second = sensors.slack_app_config(api, state, store, now=1001)
    assert second["sampled_at"] == first["sampled_at"]
    assert second["data"]["cached"] is True and len(calls) == 1
    assert state["debounce"] == counter


def test_manifest_bad_interactivity_and_command_routes_degrade_on_second_check():
    value = manifest()
    value["settings"]["interactivity"]["is_enabled"] = False
    command = next(item for item in value["features"]["slash_commands"] if item["command"] == "/hermes-auth")
    command["url"] = sensors.SLACK_RELAY + "/hermes/auth"
    api = lambda *_: {"ok": True, "manifest": value}
    state, store = {}, Store()
    assert sensors.slack_app_config(api, state, store, now=1000)["status"] == "healthy"
    result = sensors.slack_app_config(api, state, store, now=5000)["status"]
    assert result == "degraded"
    findings = state["slack_config"]["record"]["data"]["findings"]
    assert any(f["field"] == "settings.interactivity.is_enabled" and f["found"] is False for f in findings)
    assert any("/hermes-auth.url" in f["field"] for f in findings)


def test_m1_wrong_interactivity_request_url_is_named_and_degraded():
    value = manifest()
    value["settings"]["interactivity"]["request_url"] = "https://wrong.example/interactivity"
    api = lambda *_: {"ok": True, "manifest": value}
    state, store = {}, Store()
    sensors.slack_app_config(api, state, store, now=1000)
    result = sensors.slack_app_config(api, state, store, now=5000)
    assert result["status"] == "degraded"
    assert any(f["field"] == "settings.interactivity.request_url" and
               f["found"] == "https://wrong.example/interactivity" for f in result["data"]["findings"])


def test_m2_command_routes_and_missing_required_command():
    cases = [
        (None, "features.slash_commands./hermes-auth"),
        ("https://outside.test/x", "features.slash_commands./hermes-auth.url"),
        ("/slack/eventsX", None),
        ("/slack/interactivity", "features.slash_commands./hermes-auth.url"),
        ("/slack/events", "features.slash_commands./hermes-auth.url"),
        ("/hermes/x", "features.slash_commands./hermes-auth.url"),
    ]
    for path, expected_field in cases:
        value = manifest()
        commands = value["features"]["slash_commands"]
        command = next(item for item in commands if item["command"] == "/hermes-auth")
        if path is None:
            commands.remove(command)
        else:
            command["url"] = path if path.startswith("https:") else sensors.SLACK_RELAY + path
        api = lambda *_args, current=value: {"ok": True, "manifest": current}
        state, store = {}, Store()
        sensors.slack_app_config(api, state, store, now=1000)
        result = sensors.slack_app_config(api, state, store, now=5000)
        fields = {item["field"] for item in result["data"]["findings"]}
        if expected_field:
            assert expected_field in fields
        else:
            assert not any(field.endswith("/hermes-auth.url") for field in fields)


def test_m4_cached_degraded_record_keeps_sample_and_debounce(monkeypatch):
    monkeypatch.setenv("K3DM_HERMES_SLACK_CONFIG_INTERVAL", "60")
    value = manifest()
    value["settings"]["interactivity"]["is_enabled"] = False
    api = lambda *_: {"ok": True, "manifest": value}
    state, store = {}, Store()
    sensors.slack_app_config(api, state, store, now=1000)
    degraded = sensors.slack_app_config(api, state, store, now=5000)
    assert degraded["status"] == "degraded"
    counter = state["debounce"]["slack_app_config"]
    cached = sensors.slack_app_config(lambda *_: (_ for _ in ()).throw(AssertionError("cached API call")),
                                      state, store, now=5050)
    assert cached["status"] == "degraded" and cached["sampled_at"] == degraded["sampled_at"]
    assert cached["data"]["cached"] is True and state["debounce"]["slack_app_config"] == counter


def test_unknown_not_cached_and_does_not_advance_debounce(tmp_path, monkeypatch):
    monkeypatch.setenv("HOME", str(tmp_path))
    state, calls = {"debounce": {"slack_app_config": 1}}, []
    store = Store()
    api = lambda *_: calls.append(True) or {"ok": False, "error": "internal_error"}
    before = state["debounce"]["slack_app_config"]
    for at in (1000, 1001):
        result = sensors.slack_app_config(api, state, store, now=at)
        assert result["status"] == "unknown"
    assert len(calls) == 2 and state["debounce"]["slack_app_config"] == before
    assert result["data"]["error"] == "internal_error"
    assert result["evidence"].startswith("Retry Slack manifest check (internal_error)")


def test_relay_probe_codes_debounce_and_paths():
    state, seen = {}, []
    probe = lambda url: seen.append(url) or 401
    assert sensors.slack_relay_reachable(probe, state)["status"] == "healthy"
    assert seen == [sensors.SLACK_RELAY + p for p in ("/slack/interactivity", "/slack/commands")]
    failing = lambda _url: 500
    assert sensors.slack_relay_reachable(failing, state)["status"] == "healthy"
    assert sensors.slack_relay_reachable(failing, state)["status"] == "healthy"
    assert sensors.slack_relay_reachable(failing, state)["status"] == "degraded"


def test_m7_timeout_degrades_and_names_path():
    state = {}
    def probe(url):
        if url.endswith("/slack/interactivity"):
            raise TimeoutError()
        return 401
    result = None
    for _ in range(3):
        result = sensors.slack_relay_reachable(probe, state)
    assert result["status"] == "degraded" and "/slack/interactivity" in result["evidence"]


def test_rotation_writes_refresh_then_access_and_reads_back(tmp_path, monkeypatch):
    monkeypatch.setenv("HOME", str(tmp_path))
    store, state, calls = Store(), {"slack_config": {"expires_at": 1200}}, []
    def api(method, token, fields):
        calls.append((method, token, fields))
        if method == "tooling.tokens.rotate":
            return {"ok": True, "refresh_token": "fresh-refresh", "token": "fresh-access", "exp": 50000}
        return {"ok": True, "manifest": manifest()}
    result = sensors.slack_app_config(api, state, store, now=1000, may_rotate=True)
    assert result["status"] == "healthy"
    writes = [x[1] for x in store.calls if x[0] == "write"]
    assert writes == [sensors.SLACK_CONFIG_REFRESH_SERVICE, sensors.SLACK_CONFIG_SERVICE]
    assert calls[0][0] == "tooling.tokens.rotate" and calls[-1][1] == "fresh-access"
    assert state["slack_config"]["expires_at"] == 50000


def test_no_secret_in_record_on_api_exception():
    store, state = Store(), {}
    def api(*_):
        raise RuntimeError("access-secret refresh-secret")
    result = sensors.slack_app_config(api, state, store, now=1000)
    assert result["status"] == "unknown"
    assert "secret" not in repr((result, state))
    value = manifest()
    value["settings"]["interactivity"]["request_url"] = "https://access-secret.invalid/refresh-secret"
    echoed = sensors.slack_app_config(lambda *_: {"ok": True, "manifest": value}, {}, store, now=5000)
    assert "access-secret" not in repr(echoed) and "refresh-secret" not in repr(echoed)


def test_n4_api_exception_is_unknown_with_generic_evidence():
    state = {"debounce": {"slack_app_config": 2}}
    result = sensors.slack_app_config(
        lambda *_: (_ for _ in ()).throw(RuntimeError("private-access-secret")), state, Store(), now=1000)
    assert result["status"] == "unknown"
    assert "private-access-secret" not in result["evidence"]
    assert state["debounce"]["slack_app_config"] == 2


def test_keychain_write_keeps_secret_off_argv(monkeypatch):
    from hermes import sensors as module
    calls = []
    monkeypatch.setattr(module.subprocess, "run", lambda argv, **kwargs:
                        calls.append((argv, kwargs)) or type("Result", (), {"returncode": 0})())
    store = module._SlackKeychainStore()
    # The read-back is stubbed and must match the value supplied to stdin.
    monkeypatch.setattr(store, "read", lambda _service: "highly-sensitive")
    assert store.write(sensors.SLACK_CONFIG_SERVICE, "highly-sensitive")
    argv, kwargs = calls[0]
    assert argv == ["security", "-i"]
    assert "highly-sensitive" not in repr(argv)
    assert "highly-sensitive" not in kwargs["input"]
    assert "686967686c792d73656e736974697665" in kwargs["input"]


def test_relay_transport_is_unsigned_and_uses_expected_user_agent(monkeypatch):
    import importlib.machinery
    import importlib.util
    from pathlib import Path
    root = Path(__file__).resolve().parents[3]
    loader = importlib.machinery.SourceFileLoader("slack_transport_test", str(root / "bin" / "k3dm-hermes"))
    spec = importlib.util.spec_from_loader("slack_transport_test", loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    seen = []
    class Response:
        status = 401
        def __enter__(self): return self
        def __exit__(self, *_): return False
    monkeypatch.setattr(module.urllib.request, "urlopen", lambda request, timeout:
                        seen.append((request, timeout)) or Response())
    assert module._hermes_test_slack_relay_probe(sensors.SLACK_RELAY + "/slack/interactivity") == 401
    request, timeout = seen[0]
    assert request.full_url == sensors.SLACK_RELAY + "/slack/interactivity"
    assert request.get_method() == "POST" and request.data == b"" and timeout == 5
    assert request.get_header("User-agent") == sensors.HERMES_USER_AGENT
    assert request.get_header("X-slack-signature") is None
    assert request.get_header("X-slack-request-timestamp") is None


def test_keychain_store_refuses_other_services(monkeypatch):
    calls = []
    monkeypatch.setattr(sensors.subprocess, "run",
                        lambda *args, **kwargs: calls.append((args, kwargs)) or
                        type("Result", (), {"returncode": 0})())
    store = sensors._SlackKeychainStore()
    assert not store.write("unrelated-service", "value")
    assert calls == []
    monkeypatch.setattr(store, "read", lambda _service: "allowed-value")
    assert store.write(sensors.SLACK_CONFIG_SERVICE, "allowed-value")
    assert len(calls) == 1


def test_rejected_rotation_sets_regenerate_and_stops_rotating(tmp_path, monkeypatch):
    monkeypatch.setenv("HOME", str(tmp_path))
    state, store, rotations = {"slack_config": {"expires_at": 1200}}, Store(), []
    def api(method, _token, _fields):
        if method == "tooling.tokens.rotate":
            rotations.append(True)
            return {"ok": False, "error": "invalid_auth"}
        return {"ok": False, "error": "invalid_auth"}
    first = sensors.slack_app_config(api, state, store, now=1000, may_rotate=True)
    assert first["status"] == "unknown" and "regenerate the config token" in first["evidence"]
    assert state["slack_config"]["needs_regenerate"] is True
    sensors.slack_app_config(api, state, store, now=1001, may_rotate=True)
    assert len(rotations) == 1


def test_rotation_transient_error_does_not_require_regeneration(tmp_path, monkeypatch):
    monkeypatch.setenv("HOME", str(tmp_path))
    for code, regenerates in (("ratelimited", False), ("internal_error", False),
                              ("fatal_error", False), ("invalid_refresh_token", True),
                              ("token_revoked", True), ("not_authed", True)):
        state, store = {"slack_config": {"expires_at": 1200}}, Store()
        def api(method, _token, _fields):
            if method == "tooling.tokens.rotate":
                return {"ok": False, "error": code}
            return {"ok": True, "manifest": manifest()}
        result = sensors.slack_app_config(api, state, store, now=1000, may_rotate=True)
        assert result["status"] == "unknown"
        assert bool(state["slack_config"].get("needs_regenerate")) is regenerates
        if not regenerates:
            assert result["data"]["error"] == code
            assert result["evidence"] == f"Slack token rotation failed ({code})"


def test_regenerate_manifest_retries_by_interval_without_clearing_until_refresh_changes(monkeypatch, tmp_path):
    monkeypatch.setenv("HOME", str(tmp_path))
    monkeypatch.setenv("K3DM_HERMES_SLACK_CONFIG_INTERVAL", "60")
    refresh_hash = sensors._slack_refresh_hash("refresh-secret")
    state = {"slack_config": {"needs_regenerate": True, "needs_regenerate_source": "rotate",
                               "needs_regenerate_refresh": refresh_hash,
                               "regenerate_checked_refresh": refresh_hash,
                               "last_error": "invalid_refresh_token", "regenerate_checked_at": 1000}}
    store, calls = Store(), []
    def api(method, *_args):
        calls.append(method)
        return {"ok": True, "manifest": manifest()}
    first = sensors.slack_app_config(api, state, store, now=1000, may_rotate=True)
    second = sensors.slack_app_config(api, state, store, now=1020, may_rotate=True)
    assert first["status"] == second["status"] == "unknown" and calls == []
    recovered = sensors.slack_app_config(api, state, store, now=1061, may_rotate=True)
    assert recovered["status"] == "unknown" and calls == ["apps.manifest.export"]
    assert "Slack config token rejected" in recovered["evidence"]
    assert state["slack_config"]["needs_regenerate"] is True


def test_null_manifest_fields_are_safe_and_required_url_is_reported():
    value = manifest()
    value["settings"]["event_subscriptions"] = None
    command = next(item for item in value["features"]["slash_commands"] if item["command"] == "/hermes-auth")
    command["url"] = None
    api = lambda *_: {"ok": True, "manifest": value}
    state, store = {}, Store()
    sensors.slack_app_config(api, state, store, now=1000)
    result = sensors.slack_app_config(api, state, store, now=5000)
    assert result["status"] == "degraded"
    assert result["data"]["event_url"] is None
    assert any(f["field"] == "features.slash_commands./hermes-auth.url" for f in result["data"]["findings"])


def test_c12_sensor_docs_disclose_slack_keychain_rotation():
    from pathlib import Path
    root = Path(__file__).resolve().parents[3]
    module_doc = (root / "scripts/lib/hermes/sensors.py").read_text().splitlines()[0]
    import inspect
    guide = " ".join((root / "docs/guides/hermes.md").read_text().split())
    assert "Slack config sensor writes its two Keychain items when rotating" in module_doc
    assert "Slack config rotation writes its dedicated token pair" in inspect.getdoc(sensors._keychain_secret)
    assert "rotates and writes only the two items listed below" in guide
    assert "Provision the Hermes credentials first" in guide


def test_c11_unknown_api_exception_does_not_change_debounce_counter():
    state = {"debounce": {"slack_app_config": 3}}
    result = sensors.slack_app_config(
        lambda *_: (_ for _ in ()).throw(RuntimeError("network failure")), state, Store(), now=1000)
    assert result["status"] == "unknown"
    assert state["debounce"]["slack_app_config"] == 3


def test_failed_keychain_write_stays_unknown_and_retries(tmp_path, monkeypatch):
    monkeypatch.setenv("HOME", str(tmp_path))
    class FailingStore(Store):
        def write(self, service, value):
            self.calls.append(("write", service, value))
            return False
    state, store, rotations = {"slack_config": {"expires_at": 1200}}, FailingStore(), []
    def api(method, _token, _fields):
        if method == "tooling.tokens.rotate":
            rotations.append(True)
            return {"ok": True, "refresh_token": "fresh-refresh", "token": "fresh-access", "exp": 50000}
        return {"ok": True, "manifest": manifest()}
    for now in (1000, 1001):
        result = sensors.slack_app_config(api, state, store, now=now, may_rotate=True)
        if now == 1000:
            assert result["status"] == "unknown" and "Keychain" in result["evidence"]
        else:
            assert result["status"] == "healthy"
        assert not state["slack_config"].get("needs_regenerate")
    assert len(rotations) == 1


def test_m5_token_expired_manifest_rotates_after_writability_checks(tmp_path, monkeypatch):
    monkeypatch.setenv("HOME", str(tmp_path))
    store, state, calls = Store(), {}, []
    def api(method, token, fields):
        calls.append((method, token))
        if method == "tooling.tokens.rotate":
            return {"ok": True, "refresh_token": "rotated-r", "token": "rotated-a", "exp": 50000}
        if token == "access-secret":
            return {"ok": False, "error": "token_expired"}
        return {"ok": True, "manifest": manifest()}
    result = sensors.slack_app_config(api, state, store, now=1000, may_rotate=True)
    assert result["status"] == "healthy"
    assert [call[1] for call in store.calls if call[0] == "writable"] == [
        sensors.SLACK_CONFIG_SERVICE, sensors.SLACK_CONFIG_REFRESH_SERVICE]
    assert state["slack_config"]["rotated_at"] == 1000
    assert calls[-1] == ("apps.manifest.export", "rotated-a")


def test_m6_changed_refresh_under_lock_skips_second_rotation(tmp_path, monkeypatch):
    monkeypatch.setenv("HOME", str(tmp_path))
    class RotatedWhileWaiting(Store):
        def __init__(self):
            super().__init__()
            self.refresh_reads = 0
        def read(self, service):
            if service == sensors.SLACK_CONFIG_REFRESH_SERVICE:
                self.refresh_reads += 1
                if self.refresh_reads == 2:
                    self.values[service] = "concurrent-refresh"
                    self.values[sensors.SLACK_CONFIG_SERVICE] = "concurrent-access"
            return super().read(service)
    store, calls = RotatedWhileWaiting(), []
    def api(method, token, _fields):
        calls.append((method, token))
        if method == "apps.manifest.export":
            return {"ok": False, "error": "token_expired"} if token == "access-secret" else {"ok": True, "manifest": manifest()}
        raise AssertionError("rotation must be skipped after another process rotates")
    result = sensors.slack_app_config(api, {"slack_config": {"expires_at": 1200}}, store, now=1000, may_rotate=True)
    assert result["status"] == "healthy"
    assert calls == [("apps.manifest.export", "concurrent-access")]


def test_m6_rejected_rotate_with_concurrently_changed_refresh_uses_stored_pair(tmp_path, monkeypatch):
    monkeypatch.setenv("HOME", str(tmp_path))
    class ChangedOnReject(Store):
        def __init__(self):
            super().__init__()
            self.refresh_reads = 0
        def read(self, service):
            if service == sensors.SLACK_CONFIG_REFRESH_SERVICE:
                self.refresh_reads += 1
                if self.refresh_reads == 3:
                    self.values[service] = "winner-refresh"
                    self.values[sensors.SLACK_CONFIG_SERVICE] = "winner-access"
            return super().read(service)
    store, calls = ChangedOnReject(), []
    def api(method, token, _fields):
        calls.append((method, token))
        if method == "apps.manifest.export":
            return {"ok": False, "error": "token_expired"} if token == "access-secret" else {"ok": True, "manifest": manifest()}
        return {"ok": False, "error": "invalid_auth"}
    result = sensors.slack_app_config(api, {"slack_config": {"expires_at": 1200}}, store,
                                      now=1000, may_rotate=True)
    assert result["status"] == "healthy"
    assert calls == [("tooling.tokens.rotate", None), ("apps.manifest.export", "winner-access")]
    assert not result["data"].get("needs_regenerate")


def test_n7_no_rotate_without_permission_or_writable_keychain(tmp_path, monkeypatch):
    monkeypatch.setenv("HOME", str(tmp_path))
    state, store, rotations = {"slack_config": {"expires_at": 1200}}, Store(), []
    def api(method, *_args):
        if method == "tooling.tokens.rotate":
            rotations.append(True)
            return {"ok": True, "refresh_token": "r2", "token": "a2", "exp": 50000}
        return {"ok": False, "error": "token_expired"}
    sensors.slack_app_config(api, state, store, now=1000, may_rotate=False)
    class LockedStore(Store):
        def __init__(self):
            super().__init__()
            self.checked = []
        def writable(self, _service):
            self.checked.append(_service)
            return False
    locked = LockedStore()
    result = sensors.slack_app_config(api, {"slack_config": {"expires_at": 1200}}, locked,
                                      now=1000, may_rotate=True)
    assert result["status"] == "unknown" and rotations == []
    assert locked.checked == [sensors.SLACK_CONFIG_SERVICE, sensors.SLACK_CONFIG_REFRESH_SERVICE]


def test_n4_missing_item_and_malformed_manifest_are_unknown():
    class MissingStore(Store):
        def read(self, service):
            return "" if service == sensors.SLACK_CONFIG_SERVICE else super().read(service)
    missing = sensors.slack_app_config(lambda *_: {"ok": True, "manifest": manifest()}, {}, MissingStore(), now=1000)
    malformed = sensors.slack_app_config(lambda *_: {"ok": True, "manifest": {"settings": None}}, {}, Store(), now=1000)
    assert missing["status"] == malformed["status"] == "unknown"


def test_c9_slack_error_code_is_reported_on_unknown_without_leaking():
    state = {}
    result = sensors.slack_app_config(lambda *_: {"ok": False, "error": "internal_error"}, state, Store(), now=1000)
    assert result["status"] == "unknown" and result["data"]["error"] == "internal_error"
    assert result["evidence"].startswith("Retry Slack manifest check (internal_error):")
    assert len(result["evidence"]) <= 200


def test_slack_config_notification_posts_only_on_degrade_and_recovery(monkeypatch):
    import importlib.machinery
    import importlib.util
    from pathlib import Path
    root = Path(__file__).resolve().parents[3]
    loader = importlib.machinery.SourceFileLoader("slack_notification_test", str(root / "bin" / "k3dm-hermes"))
    spec = importlib.util.spec_from_loader("slack_notification_test", loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    posted = []
    monkeypatch.setattr(module, "post_summary", lambda relay, message: posted.append((relay, message)) or True)
    state = {}
    bad = {"status": "degraded", "data": {"findings": [{"field": "settings.interactivity.is_enabled"}]}}
    module._slack_config_notification(state, bad, "relay")
    module._slack_config_notification(state, bad, "relay")
    module._slack_config_notification(state, {"status": "healthy", "data": {}}, "relay")
    assert len(posted) == 2
    assert "setting wrong" in posted[0][1] and "recovered" in posted[1][1]


def test_failed_slack_config_notification_retries_next_cycle(monkeypatch):
    import importlib.machinery
    import importlib.util
    from pathlib import Path
    root = Path(__file__).resolve().parents[3]
    loader = importlib.machinery.SourceFileLoader("slack_notification_retry_test", str(root / "bin" / "k3dm-hermes"))
    spec = importlib.util.spec_from_loader("slack_notification_retry_test", loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    responses, posted = iter((False, True, True)), []
    monkeypatch.setattr(module, "post_summary", lambda relay, text: posted.append(text) or next(responses))
    state = {}
    bad = {"status": "degraded", "data": {"findings": [{"field": "setting"}]}}
    module._slack_config_notification(state, bad, "relay")
    assert state["slack_config"].get("notified") is None
    module._slack_config_notification(state, bad, "relay")
    assert state["slack_config"]["notified"] is True
    module._slack_config_notification(state, {"status": "healthy", "data": {}}, "relay")
    assert state["slack_config"]["notified"] is False and len(posted) == 3


def test_failed_recovery_notification_retries_next_cycle(monkeypatch):
    import importlib.machinery
    import importlib.util
    from pathlib import Path
    root = Path(__file__).resolve().parents[3]
    loader = importlib.machinery.SourceFileLoader("slack_recovery_retry_test", str(root / "bin" / "k3dm-hermes"))
    spec = importlib.util.spec_from_loader("slack_recovery_retry_test", loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    responses, posted = iter((False, True)), []
    monkeypatch.setattr(module, "post_summary", lambda relay, text: posted.append(text) or next(responses))
    state = {"slack_config": {"notified": True}}
    healthy = {"status": "healthy", "data": {}}
    module._slack_config_notification(state, healthy, "relay")
    assert state["slack_config"]["notified"] is True
    module._slack_config_notification(state, healthy, "relay")
    assert state["slack_config"]["notified"] is False and len(posted) == 2


def test_rotation_state_is_saved_before_later_poll_failure(monkeypatch, tmp_path):
    import importlib.machinery
    import importlib.util
    import pytest
    from pathlib import Path
    root = Path(__file__).resolve().parents[3]
    loader = importlib.machinery.SourceFileLoader("slack_state_save_test", str(root / "bin" / "k3dm-hermes"))
    spec = importlib.util.spec_from_loader("slack_state_save_test", loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    monkeypatch.setattr(module, "_refresh_index", lambda *_: None)
    monkeypatch.setattr(module, "_status_due", lambda *_: False)
    forwarded = []
    def rotated(state, *args, **kwargs):
        forwarded.append((args, kwargs))
        state["slack_config"] = {"rotated_at": 900, "expires_at": 44100}
        return [], None
    monkeypatch.setattr(module, "_run_cycle", rotated)
    monkeypatch.setattr(module, "_keychain_secret", lambda *_: "")
    monkeypatch.setattr(module, "_drain_approvals", lambda *_: (_ for _ in ()).throw(RuntimeError("later failure")))
    monkeypatch.setattr(module.pager, "security_events", lambda *_: [])
    path = tmp_path / "state.json"
    with pytest.raises(RuntimeError, match="later failure"):
        module._poll_cycle({}, path, now=1000, status_runner=None)
    assert forwarded == [((None,), {"may_rotate": True, "now": 1000, "state_path": path})]
    import json
    saved = json.loads(path.read_text())
    assert saved["slack_config"]["expires_at"] == 44100


def test_n1_regenerate_error_secret_never_reaches_record_cache_or_state():
    import json
    state = {"slack_config": {"needs_regenerate": True,
                               "needs_regenerate_refresh": "refresh-secret",
                               "last_error": "invalid_refresh_token",
                               "regenerate_checked_at": -5000}}
    store = Store()
    store.values[sensors.SLACK_CONFIG_REFRESH_SERVICE] = "new-refresh"
    api = lambda *_: {"ok": False, "error": "bad token xoxe-SECRET"}
    first = sensors.slack_app_config(api, state, store, now=1000)
    replay = sensors.slack_app_config(api, state, store, now=1001)
    encoded = json.dumps((first, replay, state))
    assert "xoxe-SECRET" not in encoded
    assert first["data"]["error"] == "unavailable"
    assert "xoxe-SECRET" not in first["evidence"] and "xoxe-SECRET" not in replay["evidence"]


def test_n2_unchanged_rejected_refresh_never_rotates_at_interval_60(monkeypatch, tmp_path):
    monkeypatch.setenv("HOME", str(tmp_path))
    monkeypatch.setenv("K3DM_HERMES_SLACK_CONFIG_INTERVAL", "60")
    state, store, rotations = {}, Store(), []
    state["slack_config"] = {"expires_at": 2000}
    def api(method, *_args):
        if method == "tooling.tokens.rotate":
            rotations.append(True)
            return {"ok": False, "error": "invalid_refresh_token"}
        return {"ok": True, "manifest": manifest()}
    for now in (1000, 1060, 1120, 1180, 1240):
        result = sensors.slack_app_config(api, state, store, now=now, may_rotate=True)
        assert result["status"] == "unknown"
        assert "Slack config token rejected (invalid_refresh_token)" in result["evidence"]
    assert len(rotations) == 1


def test_n2_regenerate_replay_preserves_action_and_code():
    state = {"slack_config": {"needs_regenerate": True, "needs_regenerate_refresh": sensors._slack_refresh_hash("refresh-secret"),
                               "last_error": "invalid_refresh_token", "regenerate_checked_at": 1000}}
    first = sensors.slack_app_config(lambda *_: {"ok": False, "error": "invalid_refresh_token"},
                                     state, Store(), now=1000)
    replay = sensors.slack_app_config(lambda *_: {"ok": True, "manifest": manifest()},
                                      state, Store(), now=1001)
    assert first["evidence"] == replay["evidence"]
    assert "Slack config token rejected (invalid_refresh_token)" in replay["evidence"]
    assert "regenerate the config token at api.slack.com/apps" in replay["evidence"]


def test_n1_regenerate_bypasses_stale_cached_record_without_secret(monkeypatch):
    import json
    monkeypatch.setenv("K3DM_HERMES_SLACK_CONFIG_INTERVAL", "3600")
    state = {"slack_config": {"needs_regenerate": True,
                               "needs_regenerate_refresh": sensors._slack_refresh_hash("refresh-secret"),
                               "last_error": "invalid_refresh_token",
                               "regenerate_checked_at": 1000,
                               "checked_at": 1000,
                               "record": {"sensor": "slack_app_config", "status": "healthy",
                                          "evidence": "old healthy record", "data": {}}}}
    result = sensors.slack_app_config(lambda *_: {"ok": False, "error": "bad token xoxe-SECRET"},
                                      state, Store(), now=1001)
    assert result["status"] == "unknown" and result["data"].get("cached") is not True
    assert "Slack config token rejected (invalid_refresh_token)" in result["evidence"]
    assert "xoxe-SECRET" not in json.dumps((result, state))


def test_n2_changed_refresh_clears_regenerate_only_after_manifest_success():
    state = {"slack_config": {"needs_regenerate": True, "needs_regenerate_refresh": "old-refresh",
                               "last_error": "invalid_refresh_token", "regenerate_checked_at": -5000}}
    result = sensors.slack_app_config(lambda *_: {"ok": True, "manifest": manifest()}, state,
                                      Store(), now=1000)
    assert result["status"] == "healthy"
    assert "needs_regenerate" not in state["slack_config"]


def test_n2_skip_lock_reload_expiry_from_saved_state(tmp_path, monkeypatch):
    import json
    monkeypatch.setenv("HOME", str(tmp_path))
    monkeypatch.setenv("K3DM_HERMES_SLACK_CONFIG_INTERVAL", "60")
    path = tmp_path / "state.json"
    path.write_text(json.dumps({"slack_config": {"expires_at": 50000, "rotated_at": 900}}))
    class ChangedStore(Store):
        def __init__(self):
            super().__init__()
            self.reads = 0
        def read(self, service):
            self.reads += 1
            if service == sensors.SLACK_CONFIG_REFRESH_SERVICE and self.reads > 2:
                self.values[service] = "other-process-refresh"
                self.values[sensors.SLACK_CONFIG_SERVICE] = "other-process-access"
            return super().read(service)
    store, calls = ChangedStore(), []
    state = {"slack_config": {"expires_at": 1200}}
    result = sensors.slack_app_config(lambda method, token, fields: calls.append((method, token)) or
                                      {"ok": True, "manifest": manifest()},
                                      state, store, now=1000,
                                      may_rotate=True, state_path=path)
    assert result["status"] == "healthy"
    assert calls == [("apps.manifest.export", "other-process-access")]
    assert store.values[sensors.SLACK_CONFIG_REFRESH_SERVICE] == "other-process-refresh"
    assert state["slack_config"]["expires_at"] == 50000
    again = sensors.slack_app_config(lambda method, token, fields: calls.append((method, token)) or
                                     {"ok": True, "manifest": manifest()}, state, store, now=1061,
                                     may_rotate=True, state_path=path)
    assert again["status"] == "healthy"
    assert calls == [("apps.manifest.export", "other-process-access"),
                     ("apps.manifest.export", "other-process-access")]


def test_n2_auth_manifest_errors_request_regeneration_and_rotation_exception_names_class(tmp_path, monkeypatch):
    monkeypatch.setenv("HOME", str(tmp_path))
    state = {}
    result = sensors.slack_app_config(lambda *_: {"ok": False, "error": "account_inactive"},
                                      state, Store(), now=1000)
    assert result["status"] == "unknown" and result["data"]["error"] == "account_inactive"
    state = {"slack_config": {"expires_at": 1200}}
    def raises(method, *_):
        if method == "tooling.tokens.rotate":
            raise TimeoutError("secret detail")
        return {"ok": True, "manifest": manifest()}
    result = sensors.slack_app_config(raises, state, Store(), now=1000, may_rotate=True)
    assert result["evidence"] == "Slack token rotation failed (TimeoutError)"
    assert "secret detail" not in repr(result)


def test_n2_rotation_expiry_must_be_positive_integer(tmp_path, monkeypatch):
    monkeypatch.setenv("HOME", str(tmp_path))
    store = Store()
    def api(method, *_):
        if method == "tooling.tokens.rotate":
            return {"ok": True, "refresh_token": "new-r", "token": "new-a", "exp": "later"}
        return {"ok": True, "manifest": manifest()}
    result = sensors.slack_app_config(api, {"slack_config": {"expires_at": 1200}}, store,
                                      now=1000, may_rotate=True)
    assert result["status"] == "unknown" and result["evidence"] == "Slack rotation returned no expiry"


def test_slack_api_auth_header_only_for_manifest_and_never_in_url(monkeypatch):
    import importlib.machinery
    import importlib.util
    import json
    from pathlib import Path
    root = Path(__file__).resolve().parents[3]
    loader = importlib.machinery.SourceFileLoader("slack_api_header_test", str(root / "bin" / "k3dm-hermes"))
    spec = importlib.util.spec_from_loader("slack_api_header_test", loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    seen = []
    class Response:
        def __enter__(self): return self
        def __exit__(self, *_): return False
        def read(self): return json.dumps({"ok": True}).encode()
    monkeypatch.setattr(module.urllib.request, "urlopen", lambda request, timeout:
                        seen.append((request, timeout)) or Response())
    module._hermes_test_slack_api("apps.manifest.export", "xoxe-test-secret", {"app_id": "A"})
    module._hermes_test_slack_api("tooling.tokens.rotate", None, {"refresh_token": "refresh-secret"})
    manifest_request, rotate_request = (entry[0] for entry in seen)
    assert manifest_request.get_header("Authorization") == "Bearer xoxe-test-secret"
    assert rotate_request.get_header("Authorization") is None
    assert all("xoxe-test-secret" not in request.full_url and "refresh-secret" not in request.full_url
               for request, _timeout in seen)


def test_slack_config_notification_is_called_by_poll_cycle(monkeypatch, tmp_path):
    import importlib.machinery
    import importlib.util
    from pathlib import Path
    root = Path(__file__).resolve().parents[3]
    loader = importlib.machinery.SourceFileLoader("slack_poll_notification_test", str(root / "bin" / "k3dm-hermes"))
    spec = importlib.util.spec_from_loader("slack_poll_notification_test", loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    monkeypatch.setenv("HOME", str(tmp_path))
    marker = tmp_path / "heartbeat.timestamp"
    monkeypatch.setenv("K3DM_HERMES_HEARTBEAT_MARKER", str(marker))
    seen = []
    monkeypatch.setattr(module, "_refresh_index", lambda *_: None)
    monkeypatch.setattr(module, "_status_due", lambda *_: False)
    monkeypatch.setattr(module, "_run_cycle", lambda *_args, **_kwargs: ([{"sensor": "slack_app_config", "status": "degraded", "evidence": "bad", "data": {}}], None))
    monkeypatch.setattr(module, "_keychain_secret", lambda *_: "")
    monkeypatch.setattr(module, "_drain_approvals", lambda *_: [])
    monkeypatch.setattr(module, "_page", lambda *_: [])
    monkeypatch.setattr(module.pager, "security_events", lambda *_: [])
    monkeypatch.setattr(module.pager, "job_events", lambda *_: [])
    monkeypatch.setattr(module, "token_expiry_advisory", lambda *_args, **_kwargs: None)
    from hermes import audit
    monkeypatch.setattr(audit, "monthly_audit_advisory", lambda *_args, **_kwargs: None)
    monkeypatch.setattr(module, "_file_app_health_bugs", lambda *_: None)
    monkeypatch.setattr(module, "_publish_status", lambda *_: None)
    monkeypatch.setattr(module, "_push_kine_metrics", lambda *_: None)
    monkeypatch.setattr(module, "_publish_health_metrics", lambda *_: None)
    command_attempts = []
    def blocked_command(args, *_args, **_kwargs):
        command_attempts.append(args)
        raise AssertionError("un-stubbed poll command attempted")
    monkeypatch.setattr(module.subprocess, "run", blocked_command)
    monkeypatch.setattr(module.subprocess, "Popen", blocked_command)
    monkeypatch.setattr(module.subprocess, "check_output", blocked_command)
    monkeypatch.setattr(module, "_publish_disk_metrics", lambda *_: None)
    monkeypatch.setattr(module, "_publish_orbstack_metrics", lambda *_: None)
    monkeypatch.setattr(module, "_publish_cni_ipam_metrics", lambda *_: None)
    monkeypatch.setattr(module, "_publish_pr_checks", lambda *_: None)
    monkeypatch.setattr(module, "_write_heartbeat_marker", lambda *_: None)
    monkeypatch.setattr(module, "_push_hermes_heartbeat", lambda *_: None)
    monkeypatch.setattr(module, "_schedule_e2e", lambda *_: None)
    monkeypatch.setattr(module, "_orbstack_notice", lambda *_: None)
    monkeypatch.setattr(module, "_slack_config_notification", lambda *args: seen.append(args[1]))
    monkeypatch.setattr(module, "_status_notification", lambda *_: None)
    monkeypatch.setattr(module, "_page", lambda *_: [])
    monkeypatch.setattr(module, "_github_headers", lambda *_: {})
    monkeypatch.setattr(module, "_bats_run", lambda *_: None)
    monkeypatch.setattr(module, "post_summary", lambda *_: True)
    monkeypatch.setattr(module, "_publish_status", lambda *_: None)
    module._poll_cycle({}, tmp_path / "state.json", now=1000, status_runner=None)
    assert seen and seen[0]["sensor"] == "slack_app_config"
    assert command_attempts == []


def test_slack_transport_fixture_teardown_fails_on_recorded_hit():
    import pytest
    import conftest
    monkeypatch = pytest.MonkeyPatch()
    try:
        fixture = conftest._no_live_slack_or_keychain.__wrapped__(monkeypatch)
        hits = next(fixture)
        guard = conftest._make_slack_transport_guard(hits, "fixture-test", "_slack_api")
        with pytest.raises(AssertionError, match="real transport reached"):
            guard()
        assert hits == ["fixture-test._slack_api"]
        with pytest.raises(pytest.fail.Exception, match="real Slack transport reached"):
            next(fixture)
    finally:
        monkeypatch.undo()


@pytest.mark.parametrize("method,argv", [("run", ["ssh", "offline.invalid"]),
                                         ("Popen", ["security", "-i"]),
                                         ("check_output", ["curl", "offline.invalid"])])
def test_sensitive_subprocess_fixture_teardown_fails_on_recorded_hit(method, argv, tmp_path):
    import subprocess
    import conftest
    monkeypatch = pytest.MonkeyPatch()
    safe_calls = []
    if method == "Popen":
        original_class = subprocess.Popen
        class SafePopen(original_class):
            def __init__(self, args, *_args, **_kwargs):
                safe_calls.append(args)
        monkeypatch.setattr(subprocess, method, SafePopen)
    else:
        monkeypatch.setattr(subprocess, method, lambda args, **_kwargs: safe_calls.append(args))
    aggregate_start = len(conftest._HERMES_GUARD_HITS)
    try:
        fixture = conftest._no_sensitive_hermes_subprocesses.__wrapped__(monkeypatch, tmp_path)
        hits = next(fixture)
        with pytest.raises(AssertionError, match="sensitive subprocess reached"):
            getattr(subprocess, method)(argv)
        assert safe_calls == [] and hits
        with pytest.raises(pytest.fail.Exception, match="sensitive subprocess reached"):
            next(fixture)
    finally:
        del conftest._HERMES_GUARD_HITS[aggregate_start:]
        monkeypatch.undo()


def test_sensitive_child_process_ssh_stub_fails_fixture_teardown(tmp_path, monkeypatch):
    import subprocess
    import conftest
    import pytest

    assert conftest._no_sensitive_hermes_subprocesses._fixture_function_marker.autouse is True
    scratch_bin = tmp_path / "fallback-bin"
    scratch_bin.mkdir()
    fallback_hits = tmp_path / "fallback-hits.log"
    fallback_ssh = scratch_bin / "ssh"
    fallback_ssh.write_text("#!/bin/sh\nprintf 'fallback\\n' >> \"$HERMES_TEST_FALLBACK_HITS\"\nexit 1\n",
                           encoding="utf-8")
    fallback_ssh.chmod(0o700)
    aggregate_start = len(conftest._HERMES_GUARD_HITS)
    monkeypatch = pytest.MonkeyPatch()
    undo_calls = []
    original_undo = monkeypatch.undo
    def tracked_undo():
        undo_calls.append(True)
        original_undo()
    monkeypatch.undo = tracked_undo
    monkeypatch.setenv("HERMES_TEST_FALLBACK_HITS", str(fallback_hits))
    monkeypatch.setenv("PATH", str(scratch_bin))
    try:
        fixture = conftest._no_sensitive_hermes_subprocesses.__wrapped__(monkeypatch, tmp_path)
        hits = next(fixture)
        child = tmp_path / "child-script"
        child.write_text("#!/bin/sh\nssh example.invalid\n", encoding="utf-8")
        child.chmod(0o700)
        subprocess.run([str(child)], check=False, capture_output=True, text=True)
        stub_hits = tmp_path / "hermes-sensitive-tools.log"
        assert not fallback_hits.exists()
        assert stub_hits.read_text(encoding="utf-8").strip() == "ssh"
        with pytest.raises(pytest.fail.Exception, match="sensitive child tool reached"):
            next(fixture)
        assert hits == []
        stub_hits.write_text("", encoding="utf-8")
    finally:
        del conftest._HERMES_GUARD_HITS[aggregate_start:]
        monkeypatch.undo()
    assert undo_calls == [True]


def test_slack_rotation_lock_serializes_two_callers(tmp_path, monkeypatch):
    import threading
    monkeypatch.setenv("HOME", str(tmp_path))
    store, rotations = Store(), []
    entered, release = threading.Event(), threading.Event()
    initial_reads = threading.Barrier(2)
    local = threading.local()
    original_read = store.read
    def synchronized_read(service):
        if service == sensors.SLACK_CONFIG_SERVICE and not getattr(local, "initial", False):
            local.initial = True
            initial_reads.wait(timeout=3)
        return original_read(service)
    store.read = synchronized_read
    def api(method, _token, _fields):
        if method == "tooling.tokens.rotate":
            rotations.append(True)
            entered.set()
            assert release.wait(3)
            return {"ok": True, "refresh_token": "new-refresh", "token": "new-access", "exp": 50000}
        return {"ok": True, "manifest": manifest()}
    results = []
    def poll():
        results.append(sensors.slack_app_config(api, {"slack_config": {"expires_at": 1200}},
                                                store, now=1000, may_rotate=True))
    first = threading.Thread(target=poll)
    second = threading.Thread(target=poll)
    first.start()
    second.start()
    assert entered.wait(3)
    release.set()
    first.join(3); second.join(3)
    assert not first.is_alive() and not second.is_alive()
    assert len(rotations) == 1 and len(results) == 2


def test_keychain_write_requires_success_status_and_readback(monkeypatch):
    calls = []
    monkeypatch.setattr(sensors.subprocess, "run", lambda argv, **kwargs:
                        calls.append((argv, kwargs)) or type("Result", (), {"returncode": 1})())
    store = sensors._SlackKeychainStore(reader=lambda _service: "same-value")
    assert store.write(sensors.SLACK_CONFIG_SERVICE, "same-value") is False
    assert calls and "same-value" not in repr(calls[0][0])
    monkeypatch.setattr(sensors.subprocess, "run", lambda argv, **kwargs:
                        type("Result", (), {"returncode": 0})())
    store = sensors._SlackKeychainStore(reader=lambda _service: "different-value")
    assert store.write(sensors.SLACK_CONFIG_SERVICE, "same-value") is False


def test_n1_regenerate_state_uses_hash_on_rotate_manifest_and_operator_retry_paths(tmp_path, monkeypatch):
    import json
    monkeypatch.setenv("HOME", str(tmp_path))
    pairs = [("access-one-distinctive", "refresh-one-distinctive"),
             ("access-two-distinctive", "refresh-two-distinctive"),
             ("access-three-distinctive", "refresh-three-distinctive")]
    for index, (access, refresh) in enumerate(pairs):
        store = Store()
        store.values[sensors.SLACK_CONFIG_SERVICE] = access
        store.values[sensors.SLACK_CONFIG_REFRESH_SERVICE] = refresh
        if index == 0:  # rotate rejected with the current pair
            state = {"slack_config": {"expires_at": 1200}}
            api = lambda method, *_: ({"ok": False, "error": "invalid_refresh_token"}
                                      if method == "tooling.tokens.rotate" else {"ok": False, "error": "invalid_auth"})
            result = sensors.slack_app_config(api, state, store, now=1000, may_rotate=True)
        elif index == 1:  # manifest rejection while rotation is not permitted
            state = {}
            result = sensors.slack_app_config(lambda *_: {"ok": False, "error": "account_inactive"},
                                              state, store, now=1000, may_rotate=True)
        else:  # replacement pair recheck still rejected
            state = {"slack_config": {"needs_regenerate": True, "needs_regenerate_source": "rotate",
                                       "needs_regenerate_refresh": sensors._slack_refresh_hash("old-refresh"),
                                       "last_error": "invalid_refresh_token", "regenerate_checked_at": 0}}
            result = sensors.slack_app_config(lambda *_: {"ok": False, "error": "invalid_auth"},
                                              state, store, now=1000)
        encoded = json.dumps((state, result))
        assert access not in encoded and refresh not in encoded
        assert access not in repr(result) and refresh not in repr(result)


def test_m5_invalid_auth_manifest_rotates_when_expiry_is_absent(tmp_path, monkeypatch):
    monkeypatch.setenv("HOME", str(tmp_path))
    store, calls = Store(), []
    def api(method, token, fields):
        calls.append((method, token))
        if method == "apps.manifest.export" and token == "access-secret":
            return {"ok": False, "error": "invalid_auth"}
        if method == "tooling.tokens.rotate":
            return {"ok": True, "refresh_token": "fresh-r", "token": "fresh-a", "exp": 50000}
        return {"ok": True, "manifest": manifest()}
    result = sensors.slack_app_config(api, {}, store, now=1000, may_rotate=True)
    assert result["status"] == "healthy"
    assert [method for method, _token in calls].count("tooling.tokens.rotate") == 1
    assert ("apps.manifest.export", "fresh-a") in calls


def test_manifest_sourced_regeneration_does_not_stick_without_rotation_permission():
    state = {}
    store = Store()
    bad = sensors.slack_app_config(lambda *_: {"ok": False, "error": "account_inactive"},
                                   state, store, now=1000, may_rotate=False)
    assert bad["status"] == "unknown" and not state["slack_config"].get("needs_regenerate")
    assert "regenerate the config token" not in bad["evidence"]
    good = sensors.slack_app_config(lambda *_: {"ok": True, "manifest": manifest()},
                                    state, store, now=1001, may_rotate=False)
    assert good["status"] == "healthy" and not state["slack_config"].get("needs_regenerate")


def test_manifest_sourced_flag_clears_after_successful_manifest():
    state = {"slack_config": {"needs_regenerate": True, "needs_regenerate_source": "manifest",
                               "last_error": "account_inactive", "regenerate_checked_at": -4000}}
    result = sensors.slack_app_config(lambda *_: {"ok": True, "manifest": manifest()},
                                      state, Store(), now=1000)
    assert result["status"] == "healthy"
    assert not state["slack_config"].get("needs_regenerate")


def test_changed_refresh_ratelimited_keeps_rejected_hash(tmp_path, monkeypatch):
    monkeypatch.setenv("K3DM_HERMES_SLACK_CONFIG_INTERVAL", "3600")
    old_refresh = "old-refresh-distinctive"
    store = Store()
    store.values[sensors.SLACK_CONFIG_REFRESH_SERVICE] = "operator-new-refresh"
    state = {"slack_config": {"needs_regenerate": True, "needs_regenerate_source": "rotate",
                               "needs_regenerate_refresh": sensors._slack_refresh_hash(old_refresh),
                               "last_error": "invalid_refresh_token", "regenerate_checked_at": 1000}}
    calls = []
    result = sensors.slack_app_config(lambda *_: calls.append(True) or
                                      {"ok": False, "error": "ratelimited"},
                                      state, store, now=1100)
    assert result["status"] == "unknown" and result["data"]["error"] == "ratelimited"
    assert state["slack_config"]["needs_regenerate_refresh"] == sensors._slack_refresh_hash(old_refresh)
    assert calls == [True]


def test_replaced_pair_rechecks_immediately_and_keeps_actionable_replay(monkeypatch):
    monkeypatch.setenv("K3DM_HERMES_SLACK_CONFIG_INTERVAL", "3600")
    state = {"slack_config": {"needs_regenerate": True, "needs_regenerate_source": "rotate",
                               "needs_regenerate_refresh": sensors._slack_refresh_hash("old-refresh"),
                               "last_error": "invalid_refresh_token", "regenerate_checked_at": 1000}}
    store = Store()
    calls = []
    api = lambda *_: calls.append(True) or {"ok": True, "manifest": manifest()}
    result = sensors.slack_app_config(api, state, store, now=1100)
    assert result["status"] == "healthy" and calls == [True]
    replay = sensors.slack_app_config(api, state, store, now=1101)
    assert replay["status"] == "healthy"
    assert "regenerate the config token" not in replay["evidence"]


def test_replaced_pair_auth_failure_replay_keeps_regeneration_action(monkeypatch):
    monkeypatch.setenv("K3DM_HERMES_SLACK_CONFIG_INTERVAL", "3600")
    state = {"slack_config": {"needs_regenerate": True, "needs_regenerate_source": "rotate",
                               "needs_regenerate_refresh": sensors._slack_refresh_hash("old-refresh"),
                               "last_error": "invalid_refresh_token", "regenerate_checked_at": 1000}}
    store = Store(); store.values[sensors.SLACK_CONFIG_REFRESH_SERVICE] = "new-refresh"
    result = sensors.slack_app_config(lambda *_: {"ok": False, "error": "invalid_auth"},
                                      state, store, now=1100)
    replay = sensors.slack_app_config(lambda *_: {"ok": False, "error": "internal_error"},
                                      state, store, now=1101)
    assert "Slack config token rejected (invalid_auth)" in result["evidence"]
    assert replay["evidence"] == result["evidence"]


def test_no_expiry_rotation_records_time_and_does_not_rotate_each_poll(tmp_path, monkeypatch):
    monkeypatch.setenv("HOME", str(tmp_path))
    store, state, rotates = Store(), {"slack_config": {"expires_at": 1200}}, []
    def api(method, *_):
        if method == "tooling.tokens.rotate":
            rotates.append(True)
            return {"ok": True, "refresh_token": "r2", "token": "a2", "exp": None}
        return {"ok": True, "manifest": manifest()}
    for now in (1000, 1001, 1002):
        result = sensors.slack_app_config(api, state, store, now=now, may_rotate=True)
        assert result["status"] == "unknown" if now == 1000 else result["status"] == "healthy"
    assert len(rotates) == 1
    assert state["slack_config"]["rotated_at"] == 1000
    assert "expires_at" not in state["slack_config"]


def test_lock_skip_stale_disk_state_drops_expiry_and_reads_rotated_at(tmp_path, monkeypatch):
    import json
    monkeypatch.setenv("HOME", str(tmp_path))
    monkeypatch.setenv("K3DM_HERMES_SLACK_CONFIG_INTERVAL", "60")
    path = tmp_path / "state.json"
    path.write_text(json.dumps({"slack_config": {"expires_at": 1200, "rotated_at": 900}}))
    class ChangedStore(Store):
        def __init__(self):
            super().__init__(); self.reads = 0
        def read(self, service):
            self.reads += 1
            if service == sensors.SLACK_CONFIG_REFRESH_SERVICE and self.reads > 2:
                self.values[service] = "winner-refresh"
                self.values[sensors.SLACK_CONFIG_SERVICE] = "winner-access"
            return super().read(service)
    state = {"slack_config": {"expires_at": 1100, "rotated_at": 900}}
    calls, store = [], ChangedStore()
    api = lambda method, token, _fields: calls.append((method, token)) or (
        {"ok": False, "error": "token_expired"} if token == "winner-access" else
        {"ok": True, "manifest": manifest()})
    result = sensors.slack_app_config(api, state, store, now=5000, may_rotate=True, state_path=path)
    assert result["status"] == "unknown"
    assert calls == [("apps.manifest.export", "winner-access")]
    assert state["slack_config"]["rotated_at"] == 900
    assert "expires_at" not in state["slack_config"]


def test_fixture_transport_guard_records_hit_and_fails_teardown_check():
    import pytest
    from conftest import _assert_no_slack_transport_hits, _make_slack_transport_guard
    hits = []
    blocked = _make_slack_transport_guard(hits, "test_module", "_slack_api")
    with pytest.raises(AssertionError, match="real transport reached"):
        blocked()
    assert hits == ["test_module._slack_api"]
    with pytest.raises(pytest.fail.Exception, match="real Slack transport reached"):
        _assert_no_slack_transport_hits(hits)


def test_2a_last_error_is_sanitized_on_unchanged_refresh_replay(monkeypatch):
    monkeypatch.setenv("K3DM_HERMES_SLACK_CONFIG_INTERVAL", "60")
    state = {"slack_config": {"needs_regenerate": True, "needs_regenerate_source": "rotate",
                               "needs_regenerate_refresh": sensors._slack_refresh_hash("refresh-secret"),
                               "last_error": "bad token xoxe-SECRET", "regenerate_checked_at": -1000}}
    result = sensors.slack_app_config(lambda *_: {"ok": False, "error": "bad token xoxe-SECRET"},
                                      state, Store(), now=1)
    assert state["slack_config"]["last_error"] == "unavailable"
    assert "xoxe-SECRET" not in repr((state, result))
    state["slack_config"]["needs_regenerate_refresh"] = "refresh-secret"
    result = sensors.slack_app_config(lambda *_: {"ok": False, "error": "bad token xoxe-SECRET"},
                                      state, Store(), now=2)
    assert "needs_regenerate_refresh" not in state["slack_config"] or re.fullmatch(
        r"[0-9a-f]{64}", state["slack_config"]["needs_regenerate_refresh"])
    assert "refresh-secret" not in repr((state, result))


def test_5b_lock_reload_copies_rotated_at_from_winner(tmp_path, monkeypatch):
    import json
    monkeypatch.setenv("HOME", str(tmp_path))
    monkeypatch.setenv("K3DM_HERMES_SLACK_CONFIG_INTERVAL", "60")
    path = tmp_path / "state.json"
    path.write_text(json.dumps({"slack_config": {"expires_at": 50000, "rotated_at": 950}}))
    class ChangedStore(Store):
        def __init__(self): super().__init__(); self.reads = 0
        def read(self, service):
            self.reads += 1
            if service == sensors.SLACK_CONFIG_REFRESH_SERVICE and self.reads > 2:
                self.values[service] = "winner-r"; self.values[sensors.SLACK_CONFIG_SERVICE] = "winner-a"
            return super().read(service)
    state, store = {"slack_config": {"expires_at": 1200, "rotated_at": 0}}, ChangedStore()
    result = sensors.slack_app_config(lambda *_: {"ok": True, "manifest": manifest()}, state, store,
                                      now=5000, may_rotate=True, state_path=path)
    assert result["status"] == "healthy" and state["slack_config"]["rotated_at"] == 950


@pytest.mark.parametrize("expiry", [True, -1])
def test_8b_bool_and_negative_expiry_are_rejected(tmp_path, monkeypatch, expiry):
    monkeypatch.setenv("HOME", str(tmp_path))
    store = Store()
    def api(method, *_):
        if method == "tooling.tokens.rotate":
            return {"ok": True, "refresh_token": "r2", "token": "a2", "exp": expiry}
        return {"ok": True, "manifest": manifest()}
    result = sensors.slack_app_config(api, {"slack_config": {"expires_at": 1200}}, store,
                                      now=1000, may_rotate=True)
    assert result["status"] == "unknown" and result["evidence"] == "Slack rotation returned no expiry"


def test_n5b_sensor_requires_readback_after_rotation(tmp_path, monkeypatch):
    monkeypatch.setenv("HOME", str(tmp_path))
    class MisreadStore(Store):
        def __init__(self): super().__init__(); self.writes = 0
        def write(self, service, value):
            self.writes += 1
            return True
        def read(self, service):
            if self.writes >= 2:
                return "wrong-pair"
            return super().read(service)
    store = MisreadStore()
    result = sensors.slack_app_config(lambda method, *_: ({"ok": True, "refresh_token": "r2",
                                                            "token": "a2", "exp": 50000}
                                                           if method == "tooling.tokens.rotate" else
                                                           {"ok": True, "manifest": manifest()}),
                                      {"slack_config": {"expires_at": 1200}}, store,
                                      now=1000, may_rotate=True)
    assert result["status"] == "unknown" and "Keychain write failed" in result["evidence"]


def test_x2_unknown_slack_record_does_not_send_recovery_post(monkeypatch):
    import importlib.machinery
    import importlib.util
    from pathlib import Path
    root = Path(__file__).resolve().parents[3]
    loader = importlib.machinery.SourceFileLoader("unknown_recovery_notice_test", str(root / "bin" / "k3dm-hermes"))
    spec = importlib.util.spec_from_loader("unknown_recovery_notice_test", loader)
    module = importlib.util.module_from_spec(spec); loader.exec_module(module)
    posts = []
    monkeypatch.setattr(module, "post_summary", lambda *args: posts.append(args) or True)
    state = {"slack_config": {"notified": True}}
    module._slack_config_notification(state, {"status": "unknown", "data": {}}, "relay")
    assert posts == [] and state["slack_config"]["notified"] is True


def test_x3_unknown_does_not_advance_checked_at_with_prior_cache():
    state = {"slack_config": {"checked_at": 1, "record": {"sensor": "slack_app_config",
               "status": "healthy", "evidence": "old", "sampled_at": "old", "data": {}}}}
    result = sensors.slack_app_config(lambda *_: {"ok": False, "error": "internal_error"},
                                      state, Store(), now=5000)
    assert result["status"] == "unknown" and state["slack_config"]["checked_at"] == 1
    assert state["slack_config"]["record"]["evidence"] == "old"


def test_x8_relay_404_and_429_are_not_healthy():
    for code in (404, 429):
        state = {}
        result = None
        for _ in range(3):
            result = sensors.slack_relay_reachable(lambda _url, value=code: value, state)
        assert result["status"] == "degraded"


def test_lock_skip_after_rejected_rotate_reloads_stale_disk_expiry(tmp_path, monkeypatch):
    import json
    monkeypatch.setenv("HOME", str(tmp_path))
    path = tmp_path / "state.json"
    path.write_text(json.dumps({"slack_config": {"expires_at": 1200, "rotated_at": 900}}))
    class ChangesAfterReject(Store):
        def __init__(self): super().__init__(); self.refresh_reads = 0
        def read(self, service):
            if service == sensors.SLACK_CONFIG_REFRESH_SERVICE:
                self.refresh_reads += 1
                if self.refresh_reads >= 3:
                    self.values[service] = "winner-refresh"
                    self.values[sensors.SLACK_CONFIG_SERVICE] = "winner-access"
            return super().read(service)
    state = {"slack_config": {"expires_at": 1200, "rotated_at": 900}}
    store, calls = ChangesAfterReject(), []
    def api(method, token, _fields):
        calls.append((method, token))
        if method == "tooling.tokens.rotate":
            return {"ok": False, "error": "invalid_refresh_token"}
        if token == "winner-access":
            return {"ok": False, "error": "token_expired"}
        return {"ok": True, "manifest": manifest()}
    result = sensors.slack_app_config(api, state, store, now=5000, may_rotate=True, state_path=path)
    assert result["status"] == "unknown"
    assert calls == [("tooling.tokens.rotate", None), ("apps.manifest.export", "winner-access")]
    assert "expires_at" not in state["slack_config"]


def test_manifest_auth_after_rotation_never_repeats_each_poll(tmp_path, monkeypatch):
    monkeypatch.setenv("HOME", str(tmp_path))
    monkeypatch.setenv("K3DM_HERMES_SLACK_CONFIG_INTERVAL", "60")
    for code in ("invalid_auth", "token_expired"):
        state, store, calls = {}, Store(), []
        def api(method, *_args):
            calls.append(method)
            if method == "tooling.tokens.rotate":
                return {"ok": True, "refresh_token": "fresh-r", "token": "fresh-a", "exp": 50000}
            return {"ok": False, "error": code}
        results = [sensors.slack_app_config(api, state, store, now=now, may_rotate=True)
                   for now in (1000, 1001, 1002, 1003)]
        assert sum(method == "tooling.tokens.rotate" for method in calls) == 1
        assert all("Slack config token rejected" in item["evidence"] for item in results)
        assert state["slack_config"]["needs_regenerate_source"] == "rotate"


def test_manifest_flag_can_rotate_after_later_token_expired(tmp_path, monkeypatch):
    monkeypatch.setenv("HOME", str(tmp_path))
    monkeypatch.setenv("K3DM_HERMES_SLACK_CONFIG_INTERVAL", "60")
    state, store, calls = {}, Store(), []
    def api(method, *_args):
        calls.append(method)
        if method == "tooling.tokens.rotate":
            return {"ok": True, "refresh_token": "fresh-r", "token": "fresh-a", "exp": 50000}
        if calls.count("apps.manifest.export") == 1:
            return {"ok": False, "error": "account_inactive"}
        if calls.count("apps.manifest.export") == 2:
            return {"ok": False, "error": "token_expired"}
        return {"ok": True, "manifest": manifest()}
    first = sensors.slack_app_config(api, state, store, now=1000, may_rotate=True)
    second = sensors.slack_app_config(api, state, store, now=1060, may_rotate=True)
    assert "needs_regenerate" not in state["slack_config"]
    assert first["status"] == "unknown" and second["status"] == "healthy"
    assert calls.count("tooling.tokens.rotate") == 1


def test_manifest_flag_transient_recheck_keeps_old_error_and_returns_unknown(monkeypatch):
    monkeypatch.setenv("K3DM_HERMES_SLACK_CONFIG_INTERVAL", "60")
    store = Store()
    state = {"slack_config": {"needs_regenerate": True, "needs_regenerate_source": "manifest",
                               "needs_regenerate_refresh": sensors._slack_refresh_hash("refresh-secret"),
                               "regenerate_checked_refresh": sensors._slack_refresh_hash("refresh-secret"),
                               "regenerate_checked_at": 1000, "last_error": "account_inactive"}}
    result = sensors.slack_app_config(lambda *_: {"ok": False, "error": "ratelimited"},
                                      state, store, now=1060, may_rotate=True)
    assert result["status"] == "unknown" and result["data"]["error"] == "ratelimited"
    assert "Slack config token rejected" not in result["evidence"]
    assert state["slack_config"]["last_error"] == "account_inactive"


def test_manifest_flag_rechecks_replaced_pair_without_waiting(monkeypatch):
    monkeypatch.setenv("K3DM_HERMES_SLACK_CONFIG_INTERVAL", "3600")
    state = {"slack_config": {"needs_regenerate": True, "needs_regenerate_source": "manifest",
                               "needs_regenerate_refresh": sensors._slack_refresh_hash("old-refresh"),
                               "regenerate_checked_refresh": sensors._slack_refresh_hash("old-refresh"),
                               "regenerate_checked_at": 1000, "last_error": "account_inactive"}}
    store = Store(); store.values[sensors.SLACK_CONFIG_REFRESH_SERVICE] = "operator-new-refresh"
    calls = []
    result = sensors.slack_app_config(lambda *_: calls.append(True) or
                                      {"ok": True, "manifest": manifest()}, state, store, now=1100)
    assert result["status"] == "healthy" and calls == [True]
    assert not state["slack_config"].get("needs_regenerate")


def test_manifest_sourced_regeneration_interval_state_and_recovery(monkeypatch):
    monkeypatch.setenv("K3DM_HERMES_SLACK_CONFIG_INTERVAL", "60")
    state, calls = {}, []
    def api(*_args):
        calls.append(True)
        if len(calls) == 1:
            return {"ok": False, "error": "account_inactive"}
        if len(calls) == 2:
            return {"ok": False, "error": "not_authed"}
        return {"ok": True, "manifest": manifest()}
    first = sensors.slack_app_config(api, state, Store(), now=1000, may_rotate=True)
    replay = sensors.slack_app_config(api, state, Store(), now=1020, may_rotate=True)
    assert len(calls) == 1 and "Slack config token rejected (account_inactive)" in replay["evidence"]
    assert state["slack_config"]["needs_regenerate_source"] == "manifest"
    assert state["slack_config"]["needs_regenerate_refresh"] == sensors._slack_refresh_hash("refresh-secret")
    checked = sensors.slack_app_config(api, state, Store(), now=1060, may_rotate=True)
    assert checked["status"] == "unknown" and len(calls) == 2
    assert state["slack_config"]["regenerate_checked_at"] == 1060
    assert state["slack_config"]["last_error"] == "not_authed"
    recovered = sensors.slack_app_config(api, state, Store(), now=1120, may_rotate=True)
    assert recovered["status"] == "healthy" and len(calls) == 3
    assert not state["slack_config"].get("needs_regenerate")


def test_recent_successful_rotation_guard_blocks_manifest_retry(tmp_path, monkeypatch):
    monkeypatch.setenv("HOME", str(tmp_path))
    monkeypatch.setenv("K3DM_HERMES_SLACK_CONFIG_INTERVAL", "60")
    state = {"slack_config": {"expires_at": 50000, "rotated_at": 1000}}
    calls = []
    def api(method, *_args):
        calls.append(method)
        return {"ok": False, "error": "token_expired"}
    for now in (1001, 1002, 1003):
        result = sensors.slack_app_config(api, state, Store(), now=now, may_rotate=True)
    assert calls == ["apps.manifest.export"] * 3
    assert result["status"] == "unknown"


def test_changed_pair_transient_recheck_is_throttled_but_new_hash_is_immediate(monkeypatch):
    monkeypatch.setenv("K3DM_HERMES_SLACK_CONFIG_INTERVAL", "3600")
    old_hash = sensors._slack_refresh_hash("old-refresh")
    store = Store(); store.values[sensors.SLACK_CONFIG_REFRESH_SERVICE] = "new-refresh"
    state = {"slack_config": {"needs_regenerate": True, "needs_regenerate_source": "rotate",
                               "needs_regenerate_refresh": old_hash,
                               "regenerate_checked_refresh": old_hash,
                               "regenerate_checked_at": 1000,
                               "last_error": "invalid_refresh_token"}}
    calls = []
    def api(*_args):
        calls.append(True)
        return {"ok": False, "error": "ratelimited"}
    first = sensors.slack_app_config(api, state, store, now=1100)
    second = sensors.slack_app_config(api, state, store, now=1101)
    assert first["status"] == second["status"] == "unknown" and calls == [True]
    assert state["slack_config"]["needs_regenerate_refresh"] == old_hash
    assert state["slack_config"]["regenerate_check_error"] == "ratelimited"
    assert second["data"]["error"] == "ratelimited"
    store.values[sensors.SLACK_CONFIG_REFRESH_SERVICE] = "third-refresh"
    good_calls = []
    result = sensors.slack_app_config(lambda *_: good_calls.append(True) or
                                      {"ok": True, "manifest": manifest()}, state, store, now=1102)
    assert result["status"] == "healthy" and good_calls == [True]
    assert "regenerate_check_error" not in state["slack_config"]


def test_l1_manifest_rejection_of_replacement_pair_can_recover(monkeypatch):
    monkeypatch.setenv("K3DM_HERMES_SLACK_CONFIG_INTERVAL", "60")
    store = Store()
    store.values[sensors.SLACK_CONFIG_REFRESH_SERVICE] = "operator-new-refresh"
    state = {"slack_config": {"needs_regenerate": True, "needs_regenerate_source": "rotate",
                               "needs_regenerate_refresh": sensors._slack_refresh_hash("old-refresh"),
                               "regenerate_checked_refresh": sensors._slack_refresh_hash("old-refresh"),
                               "regenerate_checked_at": 1000, "last_error": "invalid_refresh_token"}}
    rejected = sensors.slack_app_config(lambda *_: {"ok": False, "error": "account_inactive"},
                                        state, store, now=1060)
    assert rejected["status"] == "unknown"
    assert state["slack_config"]["needs_regenerate_source"] == "manifest"
    assert state["slack_config"]["regenerate_checked_refresh"] == sensors._slack_refresh_hash("operator-new-refresh")
    recovered = sensors.slack_app_config(lambda *_: {"ok": True, "manifest": manifest()},
                                         state, store, now=1120)
    assert recovered["status"] == "healthy"
    assert not state["slack_config"].get("needs_regenerate")


def test_l2_recent_rotation_keeps_regenerate_action_and_does_not_recheck(tmp_path, monkeypatch):
    monkeypatch.setenv("HOME", str(tmp_path))
    monkeypatch.setenv("K3DM_HERMES_SLACK_CONFIG_INTERVAL", "60")
    store = Store()
    state = {"slack_config": {"needs_regenerate": True, "needs_regenerate_source": "manifest",
                               "needs_regenerate_refresh": sensors._slack_refresh_hash("refresh-secret"),
                               "regenerate_checked_refresh": sensors._slack_refresh_hash("refresh-secret"),
                               "regenerate_checked_at": 0, "last_error": "account_inactive",
                               "rotated_at": 700}}
    calls = []
    result = sensors.slack_app_config(lambda method, *_: calls.append(method) or
                                      {"ok": False, "error": "token_expired"},
                                      state, store, now=1000, may_rotate=True)
    assert "regenerate the config token" in result["evidence"]
    assert calls == ["apps.manifest.export"]
    assert state["slack_config"]["needs_regenerate"] is True


def test_l3_rejected_refresh_token_is_not_retried_for_six_hours(tmp_path, monkeypatch):
    monkeypatch.setenv("HOME", str(tmp_path))
    monkeypatch.setenv("K3DM_HERMES_SLACK_CONFIG_INTERVAL", "300")
    state, store, calls = {"slack_config": {"expires_at": 1200}}, Store(), []
    def api(method, *_args):
        calls.append(method)
        return {"ok": False, "error": "invalid_refresh_token" if method == "tooling.tokens.rotate"
                else "token_expired"}
    first = sensors.slack_app_config(api, state, store, now=0, may_rotate=True)
    for cycle in range(1, 73):
        latest = sensors.slack_app_config(api, state, store, now=cycle * 300, may_rotate=True)
    assert calls.count("tooling.tokens.rotate") == 1
    assert "regenerate the config token" in first["evidence"]
    assert "regenerate the config token" in latest["evidence"]


def test_round5_rotation_rate_for_twelve_hours(tmp_path, monkeypatch):
    monkeypatch.setenv("HOME", str(tmp_path))
    monkeypatch.setenv("K3DM_HERMES_SLACK_CONFIG_INTERVAL", "300")
    state, store, rotations = {"slack_config": {"expires_at": 1200}}, Store(), []
    def api(method, *_args):
        if method == "tooling.tokens.rotate":
            rotations.append(True)
            return {"ok": True, "refresh_token": "new-refresh", "token": "new-access", "exp": 50000}
        return {"ok": False, "error": "invalid_auth"}
    for cycle in range(145):
        record = sensors.slack_app_config(api, state, store, now=cycle * 300, may_rotate=True)
        if cycle == 0:
            assert state["slack_config"]["needs_regenerate"] is True
    assert len(rotations) <= 12
    assert len(rotations) == 1
    assert state["slack_config"]["needs_regenerate"] is True
    assert "regenerate the config token" in record["evidence"]


@pytest.mark.parametrize("failure", ["ratelimited", "exception", "write"])
def test_l4_failed_rotations_are_throttled_for_an_hour(failure, tmp_path, monkeypatch):
    monkeypatch.setenv("HOME", str(tmp_path))
    monkeypatch.setenv("K3DM_HERMES_SLACK_CONFIG_INTERVAL", "300")
    class WriteFailureStore(Store):
        def write(self, _service, _value): return False
    store = WriteFailureStore() if failure == "write" else Store()
    calls = []
    def api(method, *_args):
        calls.append(method)
        if method == "tooling.tokens.rotate":
            if failure == "exception": raise RuntimeError("offline")
            if failure == "ratelimited": return {"ok": False, "error": "ratelimited"}
            return {"ok": True, "refresh_token": "fresh-r", "token": "fresh-a", "exp": 50000}
        return {"ok": False, "error": "invalid_auth"}
    state = {"slack_config": {"expires_at": 1200}}
    for cycle in range(12):
        sensors.slack_app_config(api, state, store, now=1000 + cycle * 300, may_rotate=True)
    assert calls.count("tooling.tokens.rotate") == 1
    assert state["slack_config"]["rotate_attempted_at"] == 1000


def test_l5_rotation_cooldown_has_one_hour_floor(tmp_path, monkeypatch):
    monkeypatch.setenv("HOME", str(tmp_path))
    monkeypatch.setenv("K3DM_HERMES_SLACK_CONFIG_INTERVAL", "60")
    state, store, calls = {"slack_config": {"expires_at": 1000}}, Store(), []
    now_value = [0]
    def api(method, *_args):
        calls.append(method)
        if method == "tooling.tokens.rotate":
            return {"ok": True, "refresh_token": f"refresh-{len(calls)}",
                    "token": f"access-{len(calls)}", "exp": now_value[0] + 3000}
        return {"ok": True, "manifest": manifest()}
    for cycle in range(24):
        now_value[0] = cycle * 300
        sensors.slack_app_config(api, state, store, now=now_value[0], may_rotate=True)
    assert calls.count("tooling.tokens.rotate") <= 2


def test_l2_manifest_flag_sets_check_time_before_api_exception(monkeypatch):
    state = {"slack_config": {"needs_regenerate": True, "needs_regenerate_source": "manifest",
                               "needs_regenerate_refresh": sensors._slack_refresh_hash("refresh-secret"),
                               "regenerate_checked_at": -4000}}
    result = sensors.slack_app_config(lambda *_: (_ for _ in ()).throw(RuntimeError("offline")),
                                      state, Store(), now=1000)
    assert result["status"] == "unknown"
    assert state["slack_config"]["regenerate_checked_at"] == 1000


def test_1c_expiry_path_obeys_recent_rotation_guard(tmp_path, monkeypatch):
    monkeypatch.setenv("HOME", str(tmp_path))
    monkeypatch.setenv("K3DM_HERMES_SLACK_CONFIG_INTERVAL", "60")
    state = {"slack_config": {"expires_at": 1100, "rotated_at": 900}}
    calls = []
    result = sensors.slack_app_config(lambda method, *_: calls.append(method) or
                                      {"ok": True, "manifest": manifest()},
                                      state, Store(), now=1000, may_rotate=True)
    assert result["status"] == "healthy"
    assert calls == ["apps.manifest.export"]


def test_3c_flag_branch_still_rotates_invalid_auth_when_permitted(tmp_path, monkeypatch):
    monkeypatch.setenv("HOME", str(tmp_path))
    monkeypatch.setenv("K3DM_HERMES_SLACK_CONFIG_INTERVAL", "60")
    state, store, calls = {"slack_config": {"needs_regenerate": True,
                                             "needs_regenerate_source": "manifest",
                                             "needs_regenerate_refresh": sensors._slack_refresh_hash("refresh-secret"),
                                             "regenerate_checked_at": 0,
                                             "last_error": "account_inactive"}}, Store(), []
    def api(method, *_args):
        calls.append(method)
        if method == "apps.manifest.export":
            return ({"ok": False, "error": "invalid_auth"} if calls.count(method) == 1
                    else {"ok": True, "manifest": manifest()})
        return {"ok": True, "refresh_token": "new-refresh", "token": "new-access", "exp": 50000}
    result = sensors.slack_app_config(api, state, store, now=1000, may_rotate=True)
    assert result["status"] == "healthy"
    assert calls.count("tooling.tokens.rotate") == 1


def test_9c_rotation_error_code_rejects_dash_and_dot():
    result = sensors._slack_rotation_unknown("bad-token.code")
    assert result["data"]["error"] == "unavailable"


def test_11d_e_f_regenerate_check_error_is_stored_replayed_and_popped(monkeypatch):
    monkeypatch.setenv("K3DM_HERMES_SLACK_CONFIG_INTERVAL", "3600")
    store = Store()
    store.values[sensors.SLACK_CONFIG_REFRESH_SERVICE] = "operator-new-refresh"
    state = {"slack_config": {"needs_regenerate": True, "needs_regenerate_source": "rotate",
                               "needs_regenerate_refresh": sensors._slack_refresh_hash("old-refresh"),
                               "regenerate_checked_refresh": sensors._slack_refresh_hash("old-refresh"),
                               "regenerate_checked_at": 1000, "last_error": "invalid_refresh_token"}}
    calls = []
    def limited(*_args):
        calls.append(True)
        return {"ok": False, "error": "ratelimited"}
    first = sensors.slack_app_config(limited, state, store, now=1100)
    replay = sensors.slack_app_config(limited, state, store, now=1101)
    assert state["slack_config"]["regenerate_check_error"] == "ratelimited"
    assert replay["data"]["error"] == "ratelimited" and len(calls) == 1
    good = sensors.slack_app_config(lambda *_: {"ok": True, "manifest": manifest()},
                                    state, store, now=4700)
    assert good["status"] == "healthy"
    assert "regenerate_check_error" not in state["slack_config"]


def test_11f_transient_error_is_popped_after_auth_recheck(monkeypatch):
    monkeypatch.setenv("K3DM_HERMES_SLACK_CONFIG_INTERVAL", "60")
    store = Store()
    store.values[sensors.SLACK_CONFIG_REFRESH_SERVICE] = "operator-new-refresh"
    state = {"slack_config": {"needs_regenerate": True, "needs_regenerate_source": "rotate",
                               "needs_regenerate_refresh": sensors._slack_refresh_hash("old-refresh"),
                               "regenerate_checked_refresh": sensors._slack_refresh_hash("old-refresh"),
                               "regenerate_checked_at": 0, "regenerate_check_error": "ratelimited",
                               "last_error": "invalid_refresh_token"}}
    first = sensors.slack_app_config(lambda *_: {"ok": False, "error": "invalid_auth"},
                                     state, store, now=1000)
    replay = sensors.slack_app_config(lambda *_: {"ok": False, "error": "invalid_auth"},
                                      state, store, now=1001)
    assert "regenerate the config token" in first["evidence"]
    assert "regenerate the config token" in replay["evidence"]
    assert replay["data"]["error"] == "invalid_auth"
    assert "regenerate_check_error" not in state["slack_config"]


def test_bad_slack_config_interval_falls_back_to_hour(monkeypatch):
    monkeypatch.setenv("K3DM_HERMES_SLACK_CONFIG_INTERVAL", "1h")
    state, calls = {}, []
    api = lambda *_: calls.append(True) or {"ok": True, "manifest": manifest()}
    first = sensors.slack_app_config(api, state, Store(), now=1000)
    cached = sensors.slack_app_config(api, state, Store(), now=1100)
    assert first["status"] == cached["status"] == "healthy"
    assert cached["data"]["cached"] is True and len(calls) == 1


def test_rotation_unknown_code_is_bounded_and_safe(tmp_path, monkeypatch):
    monkeypatch.setenv("HOME", str(tmp_path))
    result = sensors._slack_rotation_unknown("A" * 49 + "xoxesecret")
    assert result["status"] == "unknown"
    assert result["data"]["error"] == "unavailable"
    assert "xoxesecret" not in result["evidence"]


def test_reject_then_changed_refresh_is_redacted_from_manifest_result(tmp_path, monkeypatch):
    monkeypatch.setenv("HOME", str(tmp_path))
    class ChangedStore(Store):
        def __init__(self): super().__init__(); self.refresh_reads = 0
        def read(self, service):
            if service == sensors.SLACK_CONFIG_REFRESH_SERVICE:
                self.refresh_reads += 1
                if self.refresh_reads >= 3:
                    self.values[service] = "freshpair-secret-919"
                    self.values[sensors.SLACK_CONFIG_SERVICE] = "winner-access-secret"
            return super().read(service)
    api_calls = []
    def api(method, token, _fields):
        api_calls.append((method, token))
        if method == "tooling.tokens.rotate":
            return {"ok": False, "error": "invalid_refresh_token"}
        value = manifest()
        value["settings"]["event_subscriptions"]["request_url"] = \
            "https://example.test/freshpair-secret-919/winner-access-secret"
        return {"ok": True, "manifest": value}
    result = sensors.slack_app_config(api, {"slack_config": {"expires_at": 1200}},
                                      ChangedStore(), now=1000, may_rotate=True)
    assert result["status"] == "healthy", result
    assert ("apps.manifest.export", "winner-access-secret") in api_calls
    assert "freshpair-secret-919" not in repr(result)
    assert "winner-access-secret" not in repr(result)


def test_round4_manifest_auth_poll_limit_mutant_is_caught(tmp_path, monkeypatch):
    monkeypatch.setenv("HOME", str(tmp_path))
    monkeypatch.setenv("K3DM_HERMES_SLACK_CONFIG_INTERVAL", "60")
    state, store, rotations = {}, Store(), []
    def api(method, *_args):
        if method == "tooling.tokens.rotate":
            rotations.append(True)
            return {"ok": True, "refresh_token": "round4-r", "token": "round4-a", "exp": 50000}
        return {"ok": False, "error": "invalid_auth"}
    records = [sensors.slack_app_config(api, state, store, now=1000 + i, may_rotate=True)
               for i in range(4)]
    assert len(rotations) == 1
    assert all("Slack config token rejected" in item["evidence"] for item in records)
