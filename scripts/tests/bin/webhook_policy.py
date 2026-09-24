#!/usr/bin/env python3
"""Structural and equality guards for webhook authorization policy."""
import importlib.util
from importlib.machinery import SourceFileLoader
import unittest
from pathlib import Path

_ROOT = Path(__file__).resolve().parents[3]
_WEBHOOK = _ROOT / "bin" / "k3dm-webhook"
_spec = importlib.util.spec_from_file_location(
    "k3dm_webhook", _WEBHOOK, loader=SourceFileLoader("k3dm_webhook", str(_WEBHOOK))
)
wh = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(wh)


class WebhookPolicyTests(unittest.TestCase):
    def test_route_table_every_entry_declares_valid_min_role(self):
        valid_roles = {"reader", "operator", "admin"}
        routes = {**wh._POST_ROUTES, **wh._GET_ROUTES}
        self.assertTrue(routes)
        for path, route in routes.items():
            with self.subTest(path=path):
                self.assertIn("min_role", route)
                self.assertIn(route["min_role"], valid_roles)

    def test_effective_authorization_pairs_match_baseline(self):
        expected_static = {
            "/api/v1/argocd-upgrade": "admin",
            "/api/v1/cve-remediate": "operator",
            "/api/v1/cluster-status": "reader",
            "/api/v1/diagnostics": "reader",
            "/api/v1/hostinger-status": "reader",
            "/api/v1/cluster-refresh": "operator",
            "/api/v1/cluster-resume": "admin",
            "/api/v1/cleanup-stale-sandbox": "admin",
            "/api/v1/analyze": "operator",
            "/api/v1/ask": "reader",
        }
        for path, expected_role in expected_static.items():
            with self.subTest(path=path):
                self.assertEqual(wh._action_policy(path, {}), {"name": path.rsplit("/", 1)[-1], "min_role": expected_role})

        dynamic = (
            ("/api/v1/cluster", {"action": "kill"}, "operator"),
            ("/api/v1/cluster", {"action": "up"}, "admin"),
            ("/api/v1/cluster", {"action": "down"}, "admin"),
            ("/api/v1/make", {"target": "unknown"}, "reader"),
        )
        for path, body, expected_role in dynamic:
            with self.subTest(path=path, body=body):
                self.assertEqual(wh._action_policy(path, body)["min_role"], expected_role)


if __name__ == "__main__":
    unittest.main()
