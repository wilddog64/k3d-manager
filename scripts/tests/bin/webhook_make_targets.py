#!/usr/bin/env python3
"""Regression tests for allowlisted Slack /k3dm Makefile targets."""
import importlib.util
from importlib.machinery import SourceFileLoader
import re
import unittest
from pathlib import Path

_WEBHOOK = Path(__file__).resolve().parents[3] / "bin" / "k3dm-webhook"
_spec = importlib.util.spec_from_file_location(
    "k3dm_webhook", _WEBHOOK, loader=SourceFileLoader("k3dm_webhook", str(_WEBHOOK))
)
wh = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(wh)
from webhook import policy


class MakeTargetTests(unittest.TestCase):
    def test_parse_valid_target(self):
        self.assertEqual(
            wh.parse_make_request("fix-sync", {"APP": "frontend"}, False),
            (["fix-sync", "APP=frontend"], None),
        )

    def test_unknown_target_is_rejected(self):
        _, error = wh.parse_make_request("show-service-passwords", {}, False)
        self.assertIn("unknown target", error)

    def test_required_argument_is_enforced(self):
        _, error = wh.parse_make_request("fix-restart", {"APP": "x"}, False)
        self.assertIn("requires NS", error)

    def test_undeclared_argument_is_rejected(self):
        _, error = wh.parse_make_request("fix-sync", {"APP": "x", "NS": "y"}, False)
        self.assertIn("does not accept NS", error)

    def test_injection_shaped_values_are_rejected(self):
        for value in ("x;rm -rf /", "$(id)", "a b", "X", ""):
            with self.subTest(value=value):
                _, error = wh.parse_make_request("fix-sync", {"APP": value}, False)
                self.assertIn("invalid value for APP", error)
        _, error = wh.parse_make_request("fix-eso-refresh", {"FIX_CONTEXT": "ubuntu-k3s-evil"}, False)
        self.assertIn("invalid value for FIX_CONTEXT", error)

    def test_confirm_gate(self):
        _, error = wh.parse_make_request("fix-force-sync", {"APP": "x"}, False)
        self.assertIn("rerun with", error)
        self.assertEqual(
            wh.parse_make_request("fix-force-sync", {"APP": "x"}, True),
            (["fix-force-sync", "APP=x"], None),
        )

    def test_denylist_is_not_allowlisted(self):
        for target in "e2e test show-service-passwords alertmanager-secret backup restore rotate-webhook-token creds cloudflared-backup restart-webhook install-sudoers provision up down refresh".split():
            with self.subTest(target=target):
                self.assertNotIn(target, wh.MAKE_TARGETS)

    def test_every_allowlisted_target_exists_in_makefile(self):
        makefile = _WEBHOOK.parent.parent / "Makefile"
        targets = set()
        for line in makefile.read_text().splitlines():
            match = re.match(r"^([a-z0-9][a-z0-9 -]*):", line)
            if match:
                targets.update(match.group(1).split())
        for target in wh.MAKE_TARGETS:
            with self.subTest(target=target):
                self.assertIn(target, targets)

    def test_effective_make_role_caps_relay_role(self):
        self.assertEqual(wh._effective_make_role({}, {}), "admin")
        old = policy._slack_user_role
        self.addCleanup(setattr, policy, "_slack_user_role", old)
        policy._slack_user_role = lambda _user_id: "reader"
        self.assertEqual(policy._effective_make_role({"X-K3DM-Role": "admin"}, {"slack_user_id": "unknown"}), "reader")
        policy._slack_user_role = lambda _user_id: "operator"
        self.assertEqual(policy._effective_make_role({"X-K3DM-Role": "admin"}, {}), "operator")
        policy._slack_user_role = lambda _user_id: "admin"
        self.assertEqual(policy._effective_make_role({"X-K3DM-Role": "reader"}, {}), "reader")
        policy._slack_user_role = lambda _user_id: "bogus"
        self.assertEqual(policy._effective_make_role({"X-K3DM-Role": "admin"}, {}), "reader")

    def test_make_action_policy(self):
        self.assertEqual(wh._action_policy("/api/v1/make", {"target": "fix-delete-pod"})["min_role"], "admin")
        self.assertEqual(wh._action_policy("/api/v1/make", {"target": "unknown"})["min_role"], "reader")
        self.assertEqual(wh._action_policy("/api/v1/make", {})["name"], "make:help")

    def test_help_is_role_filtered(self):
        reader_help = wh.make_target_help("reader", wh._role_allows)
        self.assertIn("fix-list", reader_help)
        self.assertNotIn("fix-sync", reader_help)
        self.assertIn("fix-force-sync APP=… confirm", wh.make_target_help("admin", wh._role_allows))

    def test_app_cve_scan_requires_operator(self):
        self.assertEqual(wh.MAKE_TARGETS["app-cve-scan"]["min_role"], "operator")
        self.assertNotIn("app-cve-scan", wh.make_target_help("reader", wh._role_allows))
        self.assertIn("app-cve-scan", wh.make_target_help("operator", wh._role_allows))

    def test_app_cve_scan_cronjob_value_is_enumerated(self):
        self.assertEqual(
            wh.parse_make_request("app-cve-scan", {"CRONJOB": "app-cve-scan"}, None),
            (["app-cve-scan", "CRONJOB=app-cve-scan"], None),
        )
        for value in ("app-cve-scan; rm -rf /", "../../etc/passwd", "app-cve-scan\n", "APP-CVE-SCAN", ""):
            with self.subTest(value=value):
                argv, error = wh.parse_make_request("app-cve-scan", {"CRONJOB": value}, None)
                self.assertIsNone(argv)
                self.assertIsNotNone(error)

    def test_app_cve_scan_needs_no_confirm(self):
        self.assertEqual(
            wh.parse_make_request("app-cve-scan", {}, None),
            (["app-cve-scan"], None),
        )


if __name__ == "__main__":
    unittest.main()
