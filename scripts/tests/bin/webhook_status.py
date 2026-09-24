import importlib.util
import unittest
from importlib.machinery import SourceFileLoader
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "scripts" / "lib"))
SOURCE = ROOT / "scripts" / "lib" / "webhook" / "status.py"
SPEC = importlib.util.spec_from_file_location(
    "webhook_status_test_module", SOURCE,
    loader=SourceFileLoader("webhook_status_test_module", str(SOURCE)),
)
status = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(status)


class WebhookStatusTests(unittest.TestCase):
    def setUp(self):
        status.configure_runtime(
            lambda message: None,
            lambda job_id, text: None,
            lambda text: text.replace("REGISTERED-SECRET", "[REDACTED]"),
            lambda provider=None: provider or "k3s-aws",
            lambda provider=None: "ubuntu-k3s",
            lambda provider: None,
            lambda: None,
            lambda **kwargs: [],
        )

    def test_failing_payload_includes_failed_service_only_in_failure_detail(self):
        payload = {
            "overall": "fail",
            "checks": [
                {"service": "Frontend", "status": "error", "message": "connection refused"},
                {"service": "Catalog", "status": "healthy", "message": "ok"},
            ],
        }
        rendered = status._format_status_summary_slack(payload, "k3s-hostinger")
        self.assertIn("Frontend", rendered)
        self.assertIn("connection refused", rendered)
        self.assertNotIn(":x: Catalog", rendered)

    def test_all_healthy_payload_has_no_failure_claim(self):
        rendered = status._format_status_summary_slack(
            {"overall": "healthy", "checks": [{"service": "Frontend", "status": "healthy", "message": "ok"}]},
            "k3s-hostinger",
        )
        self.assertIn("HEALTHY", rendered)
        self.assertNotIn(":x:", rendered)
        self.assertNotIn("fail", rendered.lower())

    def test_malformed_payload_returns_unknown_summary(self):
        rendered = status._format_status_summary_slack(None, "k3s-hostinger")
        self.assertIn("UNKNOWN", rendered)
        self.assertIn("status source unavailable", rendered)

    def test_registered_secret_is_redacted(self):
        rendered = status._format_status_summary_slack(
            {"overall": "fail", "checks": [{"service": "Frontend", "status": "error", "message": "REGISTERED-SECRET leaked"}]},
            "k3s-hostinger",
        )
        self.assertNotIn("REGISTERED-SECRET", rendered)
        self.assertIn("[REDACTED]", rendered)


if __name__ == "__main__":
    unittest.main()
