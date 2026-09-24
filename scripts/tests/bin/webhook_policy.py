#!/usr/bin/env python3
"""Structural and equality guards for webhook authorization policy."""
import importlib.util
import io
import json
from importlib.machinery import SourceFileLoader
import unittest
from unittest.mock import patch
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

    def test_effective_policy_matches_the_measured_table(self):
        expected_floors = {
            "/api/v1/argocd-upgrade": "admin",
            "/api/v1/cve-remediate": "operator",
            "/api/v1/cluster": "reader",
            "/api/v1/cluster-status": "reader",
            "/api/v1/diagnostics": "reader",
            "/api/v1/hostinger-status": "reader",
            "/api/v1/cluster-refresh": "operator",
            "/api/v1/cluster-resume": "admin",
            "/api/v1/cleanup-stale-sandbox": "admin",
            "/api/v1/make": "reader",
            "/api/v1/analyze": "operator",
            "/api/v1/ask": "reader",
            "/api/v1/health": "reader",
            "/api/v1/status/": "reader",
        }
        expected = [
            (("/api/v1/argocd-upgrade", {}), {"name": "argocd-upgrade", "min_role": "admin"}),
            (("/api/v1/cve-remediate", {}), {"name": "cve-remediate", "min_role": "operator"}),
            (("/api/v1/cluster", {"action": "up"}), {"name": "cluster-up", "min_role": "admin"}),
            (("/api/v1/cluster", {"action": "down"}), {"name": "cluster-down", "min_role": "admin"}),
            (("/api/v1/cluster", {"action": "kill"}), {"name": "cluster-kill", "min_role": "operator"}),
            (("/api/v1/cluster", {"action": "other"}), {"name": "cluster", "min_role": "reader"}),
            (("/api/v1/cluster-status", {}), {"name": "cluster-status", "min_role": "reader"}),
            (("/api/v1/diagnostics", {}), {"name": "diagnostics", "min_role": "reader"}),
            (("/api/v1/hostinger-status", {}), {"name": "hostinger-status", "min_role": "reader"}),
            (("/api/v1/cluster-refresh", {}), {"name": "cluster-refresh", "min_role": "operator"}),
            (("/api/v1/cluster-resume", {}), {"name": "cluster-resume", "min_role": "admin"}),
            (("/api/v1/cleanup-stale-sandbox", {}), {"name": "cleanup-stale-sandbox", "min_role": "admin"}),
            (("/api/v1/make", {"target": "fix-list"}), {"name": "make:fix-list", "min_role": "reader"}),
            (("/api/v1/make", {"target": "unknown"}), {"name": "make:unknown", "min_role": "reader"}),
            (("/api/v1/analyze", {}), {"name": "analyze", "min_role": "operator"}),
            (("/api/v1/ask", {}), {"name": "ask", "min_role": "reader"}),
            (("/api/v1/health", {}), {"name": "health", "min_role": "reader"}),
            (("/api/v1/status/", {}), {"name": "status", "min_role": "reader"}),
        ]
        for (path, body), expected_policy in expected:
            with self.subTest(path=path, body=body):
                route = {**wh._POST_ROUTES, **wh._GET_ROUTES}[path]
                self.assertEqual(route["min_role"], expected_floors[path])
                self.assertEqual(wh.effective_policy(route, path, body), expected_policy)

    def test_a_route_with_no_dynamic_policy_still_has_a_floor(self):
        routes = dict(wh._POST_ROUTES)
        routes["/api/v1/synthetic"] = {
            "handler": "synthetic", "min_role": "operator", "action_name": "synthetic"
        }
        self.assertEqual(
            wh.effective_policy(routes["/api/v1/synthetic"], "/api/v1/synthetic", {}),
            {"name": "synthetic", "min_role": "operator"},
        )

    def test_strictest_role_picks_the_highest_and_defaults_closed(self):
        self.assertEqual(wh.strictest_role("reader", "admin"), "admin")
        self.assertEqual(wh.strictest_role("operator", None), "operator")
        self.assertEqual(wh.strictest_role(None, None), "admin")
        self.assertEqual(wh.strictest_role("nonsense"), "admin")

    def test_every_route_declares_a_floor_and_dynamic_routes_say_so(self):
        valid_roles = {"reader", "operator", "admin"}
        routes = {**wh._POST_ROUTES, **wh._GET_ROUTES}
        dynamic_paths = {"/api/v1/cluster", "/api/v1/make"}
        for path, route in routes.items():
            with self.subTest(path=path):
                self.assertIn("min_role", route)
                self.assertIn(route["min_role"], valid_roles)
                if path in dynamic_paths:
                    self.assertIsInstance(route.get("dynamic"), str)
                    self.assertTrue(route["dynamic"])

    def test_audit_is_written_exactly_once_per_request(self):
        class Request:
            def __init__(self, body, role=None):
                self.path = "/api/v1/cluster"
                self.headers = {"Content-Length": str(len(body))}
                if role is not None:
                    self.headers["X-K3DM-Role"] = role
                self.rfile = io.BytesIO(body)
                self.responses = []

            def _auth(self):
                return True

            def _json(self, code, response):
                self.responses.append((code, response))

        def drive(body, role=None):
            request = Request(json.dumps(body).encode(), role)
            with patch.object(wh._Handler, "_auth", Request._auth), patch.object(wh._Handler, "_json", Request._json), patch.object(wh, "_audit_remote_action") as audit:
                wh._Handler.do_POST(request)
            return request, audit

        allowed, allowed_audit = drive({"action": "other"}, "reader")
        self.assertEqual(len(allowed_audit.call_args_list), 1)
        self.assertTrue(allowed_audit.call_args.args[4])
        self.assertEqual(allowed.responses[0][0], 400)

        denied, denied_audit = drive({"action": "kill"}, "reader")
        self.assertEqual(len(denied_audit.call_args_list), 1)
        self.assertFalse(denied_audit.call_args.args[4])
        self.assertEqual(denied.responses[0][0], 403)

        no_dynamic, no_dynamic_audit = drive({"action": "other"}, "reader")
        self.assertEqual(len(no_dynamic_audit.call_args_list), 1)
        self.assertTrue(no_dynamic_audit.call_args.args[4])
        self.assertEqual(no_dynamic.responses[0][0], 400)


if __name__ == "__main__":
    unittest.main()
