import importlib.machinery
import importlib.util
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "scripts" / "lib"))

from hermes import pager
from hermes.records import record
from hermes.sensors import argocd

SMS = {pager.SMS_FROM_SERVICE: "from@example.com", pager.SMS_PASSWORD_SERVICE: "app-pw",
       pager.SMS_TO_SERVICE: "5550000000@sms.example"}


def keychain(values):
    return lambda service: values.get(service, "")


def webhook_down():
    return [record("eso", "unknown", "ESO status source unavailable"),
            record("node_pressure", "unknown", "node pressure status source unavailable"),
            record("ci", "healthy", "ok")]


def all_healthy():
    return [record("eso", "healthy", "ok"), record("node_pressure", "healthy", "ok"),
            record("ci", "healthy", "ok")]


class FakeSMTP:
    def __init__(self, calls, fail=False):
        self.calls = calls
        self.fail = fail

    def __call__(self, host, port, timeout):
        self.calls.append(("connect", host, port))
        return self

    def __enter__(self):
        return self

    def __exit__(self, *_args):
        return False

    def starttls(self):
        self.calls.append(("starttls",))

    def login(self, user, password):
        if self.fail:
            raise OSError("auth failed")
        self.calls.append(("login", user))

    def send_message(self, message):
        self.calls.append(("send", message["To"], message.get_content()))


def test_send_sms_uses_starttls_and_truncates():
    calls = []
    assert pager.send_sms(keychain(SMS), "x" * 500, smtp_factory=FakeSMTP(calls))
    assert calls[0] == ("connect", "smtp.gmail.com", 587)
    assert calls[1] == ("starttls",)
    assert calls[3][1] == "5550000000@sms.example"
    assert len(calls[3][2].strip()) == pager.SMS_MAX_CHARS
    assert all("app-pw" not in str(call) for call in calls)


def test_send_sms_fails_closed_without_credentials_or_on_error():
    calls = []
    partial = {k: v for k, v in SMS.items() if k != pager.SMS_TO_SERVICE}
    assert not pager.send_sms(keychain(partial), "hi", smtp_factory=FakeSMTP(calls))
    assert calls == []
    assert not pager.send_sms(keychain(SMS), "hi", smtp_factory=FakeSMTP(calls, fail=True))


def test_webhook_down_pages_once_after_two_polls_then_recovers():
    state = {}
    assert pager.health_events(webhook_down(), state) == []
    second = pager.health_events(webhook_down(), state)
    assert len(second) == 1 and "webhook DOWN" in second[0]
    assert pager.health_events(webhook_down(), state) == []
    recovered = pager.health_events(all_healthy(), state)
    assert recovered == ["Hermes: k3dm webhook recovered"]
    assert pager.health_events(all_healthy(), state) == []


def test_other_sensor_unknown_pages_after_six_polls_with_evidence():
    stuck = [record("eso", "healthy", "ok"), record("node_pressure", "healthy", "ok"),
             record("argocd", "unknown", "ArgoCD status source unavailable: credential rejected")]
    state = {}
    results = [pager.health_events(stuck, state) for _ in range(7)]
    assert results[:5] == [[]] * 5
    assert len(results[5]) == 1 and "argocd" in results[5][0] and "credential rejected" in results[5][0]
    assert results[6] == []
    healthy = stuck[:2] + [record("argocd", "healthy", "12 applications healthy")]
    assert pager.health_events(healthy, state) == ["Hermes: argocd check recovered"]


def test_single_flap_never_pages():
    state = {}
    for _ in range(10):
        assert pager.health_events(webhook_down()[:1] + all_healthy()[1:], state) == []
        assert pager.health_events(all_healthy(), state) == []


def test_job_failure_pages_after_two_failed_polls_then_recovers():
    state = {}
    assert pager.job_events(state, "RuntimeError") == []
    failing = pager.job_events(state, "RuntimeError")
    assert len(failing) == 1 and "RuntimeError" in failing[0]
    assert pager.job_events(state, "RuntimeError") == []
    assert pager.job_events(state, None) == ["Hermes: poll job recovered"]
    assert pager.job_events(state, None) == []


def github_get(code_scanning, dependabot, calls=None):
    def get(path, headers):
        if calls is not None:
            calls.append((path, headers))
        if "code-scanning" in path:
            return code_scanning
        if "dependabot" in path:
            return dependabot
        raise AssertionError(path)
    return get


CS_HIGH = {"number": 3, "rule": {"security_severity_level": "high"}}
CS_LOW = {"number": 4, "rule": {"security_severity_level": "low"}}
DEP_CRIT = {"number": 9, "security_advisory": {"severity": "critical"}}


def test_security_pages_new_severe_alerts_once_per_hour():
    state = {}
    calls = []
    keys = keychain({"audit": "tok"})
    first = pager.security_events(github_get([CS_HIGH, CS_LOW], [DEP_CRIT], calls), keys,
                                  state, "2026-09-15T13", "audit", "o/r")
    assert len(first) == 1
    assert "2 new" in first[0] and "code-scanning #3" in first[0] and "dependabot #9" in first[0]
    assert "#4" not in first[0]
    assert calls[0][1] == {"Authorization": "token tok"}
    assert pager.security_events(github_get([CS_HIGH], [DEP_CRIT], calls), keys,
                                 state, "2026-09-15T13", "audit", "o/r") == []
    assert len(calls) == 2
    assert pager.security_events(github_get([CS_HIGH], [DEP_CRIT]), keys,
                                 state, "2026-09-15T14", "audit", "o/r") == []
    newer = {"number": 10, "security_vulnerability": {"severity": "HIGH"}}
    third = pager.security_events(github_get([CS_HIGH], [DEP_CRIT, newer]), keys,
                                  state, "2026-09-15T15", "audit", "o/r")
    assert len(third) == 1 and "1 new" in third[0] and "dependabot #10" in third[0]


def test_security_fails_quiet_and_retries_without_token_or_on_error():
    state = {}

    def broken(path, headers):
        raise OSError("403")

    assert pager.security_events(broken, keychain({}), state, "h1", "audit", "o/r") == []
    assert pager.security_events(broken, keychain({"audit": "tok"}), state, "h1", "audit", "o/r") == []
    assert "pager_security_hour" not in state


def test_deliver_enforces_daily_budget_and_resets_next_day():
    state = {}
    sent = []

    def send(text):
        sent.append(text)
        return True

    assert pager.deliver(["a", "b", "c"], state, "2026-09-15", send, budget=2) == ["a", "b"]
    assert pager.deliver(["d"], state, "2026-09-15", send, budget=2) == []
    assert pager.deliver(["e"], state, "2026-09-16", send, budget=2) == ["e"]
    assert sent == ["a", "b", "e"]


def test_argocd_rejected_credential_is_named_in_evidence():
    out = argocd(lambda *_: (20, '{"level":"fatal","msg":"rpc error: code = Unauthenticated desc = invalid session"}'),
                 {}, token="x")
    assert out["status"] == "unknown"
    assert "credential rejected" in out["evidence"]
    assert "source unavailable" in out["evidence"]
    assert argocd(lambda *_: (1, "dial tcp: timeout"), {}, token="x")["evidence"] == "ArgoCD status source unavailable"


def load_hermes():
    loader = importlib.machinery.SourceFileLoader("k3dm_hermes_pager", str(ROOT / "bin" / "k3dm-hermes"))
    spec = importlib.util.spec_from_loader("k3dm_hermes_pager", loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


def test_failed_poll_pages_job_failure_and_reraises(tmp_path, monkeypatch):
    hermes = load_hermes()
    state_path = tmp_path / "state.json"
    pages = []
    monkeypatch.setenv("K3DM_HERMES_STATE", str(state_path))
    monkeypatch.delenv("K3DM_HERMES_JITTER", raising=False)
    monkeypatch.setattr(sys, "argv", ["k3dm-hermes"])
    monkeypatch.setattr(hermes, "_poll", lambda *_: (_ for _ in ()).throw(RuntimeError("boom")))
    monkeypatch.setattr(hermes, "_keychain_secret", lambda service: "")
    monkeypatch.setattr(hermes, "post_summary", lambda relay, text: pages.append(text))
    for _ in range(2):
        try:
            hermes.main()
        except RuntimeError:
            pass
        else:
            raise AssertionError("main must re-raise")
    assert len(pages) == 1 and "poll job failing (RuntimeError)" in pages[0]
    assert json.loads(state_path.read_text())["pager_open"] == ["job"]


class FakeRun:
    def __init__(self, stdout, returncode=0):
        self.calls = []
        self.stdout = stdout
        self.returncode = returncode

    def __call__(self, argv, **_kwargs):
        self.calls.append(argv)
        return type("Result", (), {"stdout": self.stdout, "returncode": self.returncode})()


def test_sms_password_reads_shared_alertmanager_item_without_duplicate(monkeypatch):
    hermes = load_hermes()
    run = FakeRun("shared-pw\n")
    looked_up = []
    monkeypatch.setattr(hermes.subprocess, "run", run)
    monkeypatch.setattr(hermes, "_keychain_secret", lambda service: looked_up.append(service) or "k3dm-item")
    assert pager.SMS_PASSWORD_SERVICE == "k3dm-alertmanager-gmail-app-password"
    assert hermes._sms_keychain(pager.SMS_PASSWORD_SERVICE) == "shared-pw"
    assert run.calls == [["security", "find-generic-password", "-s",
                          "k3dm-alertmanager-gmail-app-password", "-w"]]
    assert hermes._sms_keychain(pager.SMS_FROM_SERVICE) == "k3dm-item"
    assert hermes._sms_keychain(pager.SMS_TO_SERVICE) == "k3dm-item"
    assert looked_up == [pager.SMS_FROM_SERVICE, pager.SMS_TO_SERVICE]
    assert len(run.calls) == 1
    monkeypatch.setattr(hermes.subprocess, "run", FakeRun("", returncode=44))
    assert hermes._sms_keychain(pager.SMS_PASSWORD_SERVICE) == ""
