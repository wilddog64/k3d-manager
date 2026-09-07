import sys
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "lib"))

from hermes.audit import AUDIT_SERVICE, monthly_audit_advisory, run_audit

NOW = datetime(2026, 9, 7, tzinfo=timezone.utc)


class FakeHTTPError(Exception):
    def __init__(self, code):
        self.code = code
        super().__init__(f"HTTP {code}")


def keychain(**overrides):
    values = {AUDIT_SERVICE: "audit", "k3dm-hermes-gh-token": "pat"}
    values.update(overrides)
    return lambda service: values.get(service, "")


def github_get(code_scanning=None, dependabot=None, protection=None, errors=None):
    errors = errors or {}

    def get(path, headers):
        if "code-scanning/alerts" in path:
            if "code-scanning" in errors:
                raise errors["code-scanning"]
            return code_scanning if code_scanning is not None else []
        if "dependabot/alerts" in path:
            if "dependabot" in errors:
                raise errors["dependabot"]
            return dependabot if dependabot is not None else []
        if "branches/main/protection" in path:
            if "protection" in errors:
                raise errors["protection"]
            return protection if protection is not None else {}
        raise AssertionError(f"unexpected path: {path}")

    return get


def header_fetch(expiry="2026-12-04 00:00:00 UTC"):
    def fetch(path, headers):
        return {"github-authentication-token-expiration": expiry} if expiry else {}
    return fetch


PROTECTION_OK = {"enforce_admins": {"enabled": True},
                 "required_pull_request_reviews": {"required_approving_review_count": 1}}


def test_clean_month_reports_no_attention():
    report, digest = run_audit(
        github_get(protection=PROTECTION_OK), header_fetch(), keychain(), now=NOW)

    assert report["code_scanning"]["counts"]["high"] == 0
    assert report["dependabot"]["total"] == 0
    assert report["branch_protection"]["ok"] is True
    assert report["attention"] == []
    assert "clean" in digest


def test_open_dependabot_high_surfaces_in_attention_and_digest():
    alerts = [{"number": 9, "security_advisory": {"severity": "high"}}]
    report, digest = run_audit(
        github_get(dependabot=alerts, protection=PROTECTION_OK),
        header_fetch(), keychain(), now=NOW)

    assert report["dependabot"]["counts"]["high"] == 1
    assert report["dependabot"]["numbers"] == [9]
    assert any("dependabot" in item and "#9" in item for item in report["attention"])
    assert "#9" in digest


def test_code_scanning_scope_error_degrades_gracefully():
    report, digest = run_audit(
        github_get(protection=PROTECTION_OK, errors={"code-scanning": FakeHTTPError(403)}),
        header_fetch(), keychain(), now=NOW)

    assert report["code_scanning"]["available"] is False
    assert "token lacks required scope" in report["code_scanning"]["detail"]
    # never a false clean bill — the unavailability is surfaced, not hidden
    assert any("code-scanning" in item for item in report["attention"])
    assert "403" in digest


def test_branch_protection_drift_detected():
    weak = {"enforce_admins": {"enabled": False},
            "required_pull_request_reviews": {"required_approving_review_count": 0}}
    report, digest = run_audit(
        github_get(protection=weak), header_fetch(), keychain(), now=NOW)

    assert report["branch_protection"]["ok"] is False
    assert "enforce_admins off" in report["branch_protection"]["drift"]
    assert any("branch-protection" in item for item in report["attention"])
    assert "⚠️" in digest


def test_missing_audit_token_marks_api_checks_unavailable():
    report, _digest = run_audit(
        github_get(protection=PROTECTION_OK), header_fetch(),
        keychain(**{AUDIT_SERVICE: ""}), now=NOW)

    for check in ("code_scanning", "dependabot", "branch_protection"):
        assert report[check]["available"] is False
        assert AUDIT_SERVICE in report[check]["detail"]


def test_credential_expiry_reported_with_days():
    report, digest = run_audit(
        github_get(protection=PROTECTION_OK), header_fetch(), keychain(), now=NOW)

    audit_cred = next(c for c in report["credentials"] if c["service"] == AUDIT_SERVICE)
    assert audit_cred["status"] == "expires"
    assert audit_cred["days"] == 88
    assert "Credentials:" in digest


def test_monthly_advisory_fires_once_then_dedups_same_month():
    state = {}
    get = github_get(protection=PROTECTION_OK)

    first = monthly_audit_advisory(get, header_fetch(), keychain(), state, "2026-09", now=NOW)
    assert first is not None and "security audit" in first
    assert state["last_security_audit_month"] == "2026-09"

    second = monthly_audit_advisory(get, header_fetch(), keychain(), state, "2026-09", now=NOW)
    assert second is None


def test_monthly_advisory_fires_again_on_month_rollover():
    state = {"last_security_audit_month": "2026-09"}
    digest = monthly_audit_advisory(
        github_get(protection=PROTECTION_OK), header_fetch(), keychain(), state, "2026-10", now=NOW)

    assert digest is not None
    assert state["last_security_audit_month"] == "2026-10"


def test_monthly_advisory_makes_no_network_call_when_already_run():
    def exploding_get(path, headers):
        raise AssertionError("must not fetch when already audited this month")

    state = {"last_security_audit_month": "2026-09"}
    result = monthly_audit_advisory(
        exploding_get, header_fetch(), keychain(), state, "2026-09", now=NOW)

    assert result is None


def test_audit_never_writes_or_touches_repairs():
    # Structural invariant (spec §7): the module performs no writes and never imports repairs.
    source = (Path(__file__).resolve().parents[2] / "lib" / "hermes" / "audit.py").read_text()
    for forbidden in ("repairs", '"POST"', "'POST'", '"PATCH"', "'PATCH'", '"DELETE"', "'DELETE'"):
        assert forbidden not in source
