import sys
from pathlib import Path

import pytest


ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "scripts" / "lib"))

from webhook import redact, status


@pytest.mark.parametrize("line, expected", [
    ("Authorization: Bearer bearer-secret", "Authorization: Bearer ***REDACTED***"),
    ("jwt=eyJabc_DEF.eyJpayload-1.sig_2", "jwt=***REDACTED***"),
    ("postgres://alice:db-password@db.internal", "postgres://alice:***REDACTED***@db.internal"),
    ("DB_PASSWORD=hunter2", "DB_PASSWORD=***REDACTED***"),
    ("client_secret: secret-value", "client_secret: ***REDACTED***"),
    ("api-key=key-value", "api-key=***REDACTED***"),
    ('{"password":"hunter2"}', '{"password":"***REDACTED***"}'),
    ('{"access_token": "abc"}', '{"access_token": "***REDACTED***"}'),
    ("token: Bearer abc123", "token: Bearer ***REDACTED***"),
    ("redis://:pw@redis:6379", "redis://:***REDACTED***@redis:6379"),
    ("Authorization: Basic dXNlcjpwYXNz", "Authorization: Basic ***REDACTED***"),
    ('password = "two words"', 'password = "***REDACTED***"'),
    ("Vault hvs.abcdefghijklmnopqrstuvwx", "Vault ***REDACTED***"),
    ("Vault s.abcdefghijklmnopqrstuvwx", "Vault ***REDACTED***"),
    ("Stripe sk_live_livevalue", "Stripe ***REDACTED***"),
    ("Stripe sk_test_testvalue", "Stripe ***REDACTED***"),
    ("GitHub ghp_githubvalue", "GitHub ***REDACTED***"),
    ("GitHub github_pat_githubvalue", "GitHub ***REDACTED***"),
])
def test_credential_shapes_are_scrubbed(line, expected):
    assert redact.scrub_credentials(line) == expected


@pytest.mark.parametrize("line", [
    "password is required",
    "token_count=42",
    "commit 0123456789abcdef0123456789abcdef01234567",
    "image sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
    "secretName: app-tls",
    "items.abcdefghijklmnopqrstuvwxyz0123",
])
def test_non_credentials_are_unchanged(line):
    assert redact.scrub_credentials(line) == line


def test_sensitive_key_vocabulary_tracks_shell_sensitive_flags():
    assert "password" in redact.SENSITIVE_KEY_WORDS
    assert "token" in redact.SENSITIVE_KEY_WORDS


def test_diagnostics_output_scrubs_unregistered_bearer_token(tmp_path, monkeypatch):
    job_id = "diagnose-logs"
    job_dir = tmp_path / job_id
    job_dir.mkdir()
    token = "unregistered-bearer-token"
    captured = []
    monkeypatch.setattr(status, "JOB_DIR", tmp_path)
    monkeypatch.setattr(status, "_spawn_capture_text", lambda *args, **kwargs: (
        0, f"Authorization: Bearer {token}", False))
    monkeypatch.setattr(status, "_slack_post", lambda url, text: captured.append(text))
    monkeypatch.setattr(status, "_notify_job", lambda job, text: captured.append(text))
    monkeypatch.setattr(status, "_redact_secrets", lambda text: text)

    status._run_cluster_diagnostics(
        job_id,
        "https://example.test/response",
        request={
            "action": "logs",
            "context": "k3d-k3d-cluster",
            "namespace": "identity",
            "name": "keycloak-0",
        },
    )

    output = (job_dir / "output").read_text()
    assert token not in output
    assert captured and token not in captured[0]


def test_registered_secret_redaction_still_applies_in_diagnostics(tmp_path, monkeypatch):
    job_id = "diagnose-logs-registered"
    job_dir = tmp_path / job_id
    job_dir.mkdir()
    registered = "registered-secret"
    monkeypatch.setattr(status, "JOB_DIR", tmp_path)
    monkeypatch.setattr(status, "_spawn_capture_text", lambda *args, **kwargs: (
        0, registered, False))
    monkeypatch.setattr(status, "_redact_secrets", lambda text: text.replace(
        registered, "***REDACTED***"))
    monkeypatch.setattr(status, "_notify_job", lambda job, text: None)

    status._run_cluster_diagnostics(
        job_id,
        "",
        request={
            "action": "logs",
            "context": "k3d-k3d-cluster",
            "namespace": "identity",
            "name": "keycloak-0",
        },
    )

    output = (job_dir / "output").read_text()
    assert registered not in output
    assert "***REDACTED***" in output
