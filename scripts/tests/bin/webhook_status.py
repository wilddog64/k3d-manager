import importlib.util
import unittest
from importlib.machinery import SourceFileLoader
from pathlib import Path
import sys
import os
import tempfile
from unittest import mock

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "scripts" / "lib"))
SOURCE = ROOT / "scripts" / "lib" / "webhook" / "status.py"
SPEC = importlib.util.spec_from_file_location(
    "webhook_status_test_module", SOURCE,
    loader=SourceFileLoader("webhook_status_test_module", str(SOURCE)),
)
status = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(status)

WEBHOOK_SPEC = importlib.util.spec_from_file_location(
    "k3dm_webhook_test_module", ROOT / "bin" / "k3dm-webhook",
    loader=SourceFileLoader("k3dm_webhook_test_module", str(ROOT / "bin" / "k3dm-webhook")),
)
webhook = importlib.util.module_from_spec(WEBHOOK_SPEC)
WEBHOOK_SPEC.loader.exec_module(webhook)


class WebhookStatusTests(unittest.TestCase):
    def setUp(self):
        status.configure_runtime(
            lambda message: None,
            lambda job_id, text: None,
            lambda text: text.replace("REGISTERED-SECRET", "[REDACTED]"),
            lambda provider=None: provider or "k3s-aws",
            lambda provider=None: {
                "k3s-aws": "ubuntu-k3s", "k3s-hostinger": "ubuntu-hostinger",
                "k3s-gcp": "ubuntu-gcp", "k3s-az": "ubuntu-azure",
            }.get(provider, "ubuntu-k3s"),
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

    def test_tunnel_port_helpers_select_provider_ports(self):
        with mock.patch.dict(os.environ, {}, clear=False):
            os.environ.pop("TUNNEL_SANDBOX_LOCAL_PORT", None)
            os.environ.pop("TUNNEL_LOCAL_PORT", None)
            self.assertEqual(webhook._tunnel_port_for_provider("k3s-aws"), 16443)
            self.assertEqual(webhook._tunnel_port_for_provider("k3s-hostinger"), 6443)
            self.assertEqual(status._tunnel_port_for_context("ubuntu-k3s"), 16443)
            self.assertEqual(status._tunnel_port_for_context("ubuntu-hostinger"), 6443)

    def test_tunnel_port_helpers_respect_configured_ports(self):
        with mock.patch.dict(os.environ, {"TUNNEL_SANDBOX_LOCAL_PORT": "17443", "TUNNEL_LOCAL_PORT": "7443"}):
            self.assertEqual(webhook._tunnel_port_for_provider("k3s-aws"), 17443)
            self.assertEqual(webhook._tunnel_port_for_provider("k3s-hostinger"), 7443)
            self.assertEqual(status._tunnel_port_for_context("ubuntu-k3s"), 17443)
            self.assertEqual(status._tunnel_port_for_context("ubuntu-hostinger"), 7443)

    def test_tunnel_port_for_context_falls_back_on_invalid_values(self):
        cases = (
            ("ubuntu-k3s", "TUNNEL_SANDBOX_LOCAL_PORT", 16443),
            ("ubuntu-hostinger", "TUNNEL_LOCAL_PORT", 6443),
        )
        for context, name, default in cases:
            for value in ("", "abc", "0", "70000", "-1", "12.5"):
                with self.subTest(context=context, value=value):
                    with mock.patch.dict(os.environ, {name: value}):
                        self.assertEqual(status._tunnel_port_for_context(context), default)
            with self.subTest(context=context, value="valid"):
                with mock.patch.dict(os.environ, {name: "17443"}):
                    self.assertEqual(status._tunnel_port_for_context(context), 17443)

    def test_app_context_filters_provider_apps_and_keeps_shared_apps(self):
        for matcher in (webhook._app_matches_provider_context, status._app_matches_provider_context):
            self.assertTrue(matcher("ubuntu-k3s-data-layer", "ubuntu-k3s"))
            self.assertFalse(matcher("ubuntu-hostinger-data-layer", "ubuntu-k3s"))
            self.assertTrue(matcher("acg-shared-app", "ubuntu-k3s"))

    def test_post_provision_keeps_degraded_provider_and_shared_apps(self):
        output = []
        webhook._POST_PROVISION_DELAY_SECS = 0
        with tempfile.TemporaryDirectory():
            with mock.patch.object(webhook, "_notify_job", side_effect=lambda _job, text: output.append(text)), \
                    mock.patch.object(webhook, "_smoke_test_services", return_value=[]), \
                    mock.patch.object(webhook, "_posix_spawn_capture", return_value=(
                        "ubuntu-k3s-broken Degraded\nacg-shared Degraded\nubuntu-hostinger-broken Degraded", False)), \
                    mock.patch.object(webhook, "_call_gemini", return_value="REAL FAILURE"), \
                    mock.patch("socket.create_connection") as connect:
                connect.return_value.__enter__.return_value = object()
                webhook._run_post_provision_check("scratch-job", "k3s-aws")
        report = "\n".join(output)
        self.assertIn("ubuntu-k3s-broken", report)
        self.assertIn("acg-shared", report)
        self.assertNotIn("ubuntu-hostinger-broken", report)
        self.assertEqual(connect.call_args.args[0], ("localhost", 16443))

    def test_hostinger_checks_use_hostinger_tunnel_port(self):
        webhook._POST_PROVISION_DELAY_SECS = 0
        output = []
        with tempfile.TemporaryDirectory() as scratch, \
                mock.patch.object(webhook, "_notify_job", side_effect=lambda _job, text: output.append(text)), \
                mock.patch.object(webhook, "_smoke_test_services", return_value=[]), \
                mock.patch.object(webhook, "_posix_spawn_capture", return_value=("", False)), \
                mock.patch("socket.create_connection") as post_connect:
            post_connect.return_value.__enter__.return_value = object()
            webhook._run_post_provision_check("scratch-job", "k3s-hostinger")
        self.assertEqual(post_connect.call_args.args[0], ("localhost", 6443))
        self.assertIn("*SSH tunnel (6443):* UP ✅", "\n".join(output))

        with tempfile.TemporaryDirectory() as scratch:
            job_dir = Path(scratch) / "job"
            job_dir.mkdir()
            outputs = iter([
                ("hub Ready", False), ("app Ready", False), ("", False),
                ("", False), ("", False), ("", False),
            ])
            with mock.patch.object(status, "JOB_DIR", Path(scratch)), \
                    mock.patch.object(status, "_posix_spawn_capture", side_effect=lambda *a, **k: next(outputs)), \
                    mock.patch.object(status, "_post_status_report", return_value=True), \
                    mock.patch.object(status, "_notify_job"), \
                    mock.patch.object(status, "_smoke_test_services", return_value=[]), \
                    mock.patch("socket.create_connection") as status_connect:
                status_connect.return_value.__enter__.return_value = object()
                status._run_cluster_status("job", "", provider="k3s-hostinger")
            report = (job_dir / "output").read_text()
        self.assertEqual(status_connect.call_args.args[0], ("localhost", 6443))
        self.assertIn("*SSH tunnel (6443):* UP ✅", report)

    def test_status_scopes_degraded_apps_and_tunnel_to_provider(self):
        with tempfile.TemporaryDirectory() as scratch:
            job_dir = Path(scratch) / "job"
            job_dir.mkdir()
            outputs = iter([
                ("hub Ready", False), ("app Ready", False), ("", False),
                ("", False),
                ("ubuntu-k3s-broken Synced Degraded\nubuntu-hostinger-broken Synced Degraded", False),
                ("", False),
            ])
            with mock.patch.object(status, "JOB_DIR", Path(scratch)), \
                    mock.patch.object(status, "_posix_spawn_capture", side_effect=lambda *a, **k: next(outputs)), \
                    mock.patch.object(status, "_post_status_report", return_value=True), \
                    mock.patch.object(status, "_notify_job"), \
                    mock.patch.object(status, "_smoke_test_services", return_value=[]), \
                    mock.patch("socket.create_connection") as connect:
                connect.return_value.__enter__.return_value = object()
                status._run_cluster_status("job", "", provider="k3s-aws")
            report = (job_dir / "output").read_text()
        self.assertIn("ubuntu-k3s-broken", report)
        self.assertNotIn("ubuntu-hostinger-broken", report)
        self.assertIn("*SSH tunnel (16443):* UP ✅", report)
        self.assertEqual(connect.call_args.args[0], ("localhost", 16443))

    def test_aws_status_never_probes_hostinger_port_or_reports_other_provider_apps(self):
        with tempfile.TemporaryDirectory() as scratch:
            job_dir = Path(scratch) / "job"
            job_dir.mkdir()
            outputs = iter([
                ("hub Ready", False), ("app Ready", False), ("", False),
                ("", False), ("ubuntu-k3s-good Synced Healthy\nubuntu-hostinger-bad Synced Degraded", False),
                ("", False),
            ])
            with mock.patch.object(status, "JOB_DIR", Path(scratch)), \
                    mock.patch.object(status, "_posix_spawn_capture", side_effect=lambda *a, **k: next(outputs)), \
                    mock.patch.object(status, "_post_status_report", return_value=True), \
                    mock.patch.object(status, "_notify_job"), \
                    mock.patch.object(status, "_smoke_test_services", return_value=[]), \
                    mock.patch("socket.create_connection") as connect:
                connect.return_value.__enter__.return_value = object()
                status._run_cluster_status("job", "", provider="k3s-aws")
            report = (job_dir / "output").read_text()
        self.assertEqual(connect.call_args.args[0], ("localhost", 16443))
        self.assertNotIn("DOWN ❌", report.split("SSH tunnel", 1)[1].splitlines()[0])
        self.assertNotIn("ubuntu-hostinger-bad", report)

    def test_post_provision_aws_never_triages_other_provider_apps(self):
        output = []
        webhook._POST_PROVISION_DELAY_SECS = 0
        with tempfile.TemporaryDirectory(), \
                mock.patch.object(webhook, "_notify_job", side_effect=lambda _job, text: output.append(text)), \
                mock.patch.object(webhook, "_smoke_test_services", return_value=[]), \
                mock.patch.object(webhook, "_posix_spawn_capture", return_value=(
                    "ubuntu-k3s-good Healthy\nubuntu-hostinger-bad Degraded", False)), \
                mock.patch.object(webhook, "_call_gemini", return_value="triaged") as triage, \
                mock.patch("socket.create_connection") as connect:
            def sandbox_port_only(address, timeout):
                if address == ("localhost", 6443):
                    raise OSError("Hostinger port intentionally down")
                return mock.MagicMock()
            connect.side_effect = sandbox_port_only
            webhook._run_post_provision_check("scratch-job", "k3s-aws")
        self.assertEqual(connect.call_args.args[0], ("localhost", 16443))
        self.assertNotIn("ubuntu-hostinger-bad", "\n".join(output))
        self.assertFalse(triage.called)
        self.assertNotIn("SSH tunnel down — ACG cluster API unreachable", "\n".join(output))


if __name__ == "__main__":
    unittest.main()
