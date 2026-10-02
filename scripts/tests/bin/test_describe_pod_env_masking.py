"""`describe-pod` diagnostics mask literal env values of sensitive variables.

docs/bugs/2026-09-28-diagnostics-describe-pod-prints-literal-env-values.md
"""

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "scripts" / "lib"))

from webhook import redact, status  # noqa: E402

SECRETS = (
    "hunter2-synthetic",
    "app:synthetic@db",
    "synthetic-key",
    "dsnsecret0123",
    "T000/B000/whsynthetic",
    "argsbearer-synthetic",
)

DESCRIBE = """Name:             order-service-7d9f
Namespace:        shopping-cart-apps
Containers:
  order:
    Image:         ghcr.io/example/order:1.2.3
    Args:
      --auth
      Bearer argsbearer-synthetic
    Environment:
      DB_PASSWORD:    hunter2-synthetic
      DATABASE_URL:   postgresql://app:synthetic@db:5432/x
      API_KEY:        synthetic-key
      SENTRY_DSN:     https://dsnsecret0123@sentry.example/1
      WEBHOOK_URL:    https://hooks.example/services/T000/B000/whsynthetic
      LOG_LEVEL:      info
      PORT:           8080
      REDIS_PASSWORD: <set to the key 'password' in secret 'redis-cart'>  Optional: false
    Mounts:
      /var/run/secrets from kube-api-access (ro)
Conditions:
  Type              Status
  Ready             True
"""


def test_sensitive_env_values_are_masked_names_kept():
    masked = redact.mask_env_values(DESCRIBE)
    for name in ("DB_PASSWORD", "DATABASE_URL", "API_KEY", "SENTRY_DSN", "WEBHOOK_URL"):
        assert f"{name}:" in masked
    for value in ("hunter2-synthetic", "app:synthetic@db", "synthetic-key", "dsnsecret0123", "whsynthetic"):
        assert value not in masked


def test_non_sensitive_env_and_secret_refs_are_unchanged():
    masked = redact.mask_env_values(DESCRIBE)
    assert "      LOG_LEVEL:      info" in masked
    assert "      PORT:           8080" in masked
    assert "REDIS_PASSWORD: <set to the key 'password' in secret 'redis-cart'>" in masked
    assert "      /var/run/secrets from kube-api-access (ro)" in masked
    assert "  Ready             True" in masked


def test_masking_is_confined_to_the_environment_block():
    text = "Labels:\n  api_url: https://x/y\nEnvironment:  <none>\nMounts:\n  TOKEN_URL: https://x/z\n"
    assert redact.mask_env_values(text) == text


def test_scrubber_still_masks_args_bearer():
    assert "argsbearer-synthetic" not in redact.scrub_credentials(DESCRIBE)


def test_describe_pod_end_to_end_leaks_nothing(tmp_path, monkeypatch):
    job_id = "diagnose-describe"
    (tmp_path / job_id).mkdir()
    captured = []
    monkeypatch.setattr(status, "JOB_DIR", tmp_path)
    monkeypatch.setattr(status, "_spawn_capture_text", lambda *a, **k: (0, DESCRIBE, False))
    monkeypatch.setattr(status, "_slack_post", lambda url, text: captured.append(text))
    monkeypatch.setattr(status, "_notify_job", lambda job, text: captured.append(text))
    monkeypatch.setattr(status, "_redact_secrets", lambda text: text)

    status._run_cluster_diagnostics(
        job_id,
        "https://example.test/response",
        request={"action": "describe-pod", "context": "k3d-k3d-cluster",
                 "namespace": "shopping-cart-apps", "name": "order-service-7d9f"},
    )

    output = (tmp_path / job_id / "output").read_text()
    assert captured
    for secret in SECRETS:
        assert secret not in output
        assert secret not in captured[0]
    assert "LOG_LEVEL:      info" in output
