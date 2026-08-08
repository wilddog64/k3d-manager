#!/usr/bin/env python3
"""Regression tests for k3dm-webhook request hardening.

Covers:
  * _content_length: malformed / missing / negative header handling (Finding 2)
  * _rate_limited: fixed-window enforcement still fires (Finding 1 sanity)
  * do_GET: rate limiter runs AFTER auth, so unauthenticated requests do not
    consume the shared bucket (Finding 1 ordering)
"""
import importlib.util
from importlib.machinery import SourceFileLoader
import unittest
from pathlib import Path

_WEBHOOK = Path(__file__).resolve().parents[3] / "bin" / "k3dm-webhook"
_spec = importlib.util.spec_from_file_location(
    "k3dm_webhook", _WEBHOOK, loader=SourceFileLoader("k3dm_webhook", str(_WEBHOOK))
)
wh = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(wh)


class ContentLengthTests(unittest.TestCase):
    def test_valid(self):
        self.assertEqual(wh._content_length({"Content-Length": "42"}), 42)

    def test_missing_defaults_zero(self):
        self.assertEqual(wh._content_length({}), 0)

    def test_non_integer_returns_none(self):
        self.assertIsNone(wh._content_length({"Content-Length": "abc"}))

    def test_negative_returns_none(self):
        self.assertIsNone(wh._content_length({"Content-Length": "-1"}))


class RateLimitTests(unittest.TestCase):
    def setUp(self):
        wh._rate_hits.clear()

    def test_fixed_window_enforced(self):
        for _ in range(wh._RATE_MAX_DEFAULT):
            self.assertFalse(wh._rate_limited("api"))
        self.assertTrue(wh._rate_limited("api"))

    def test_unauthenticated_get_does_not_consume_bucket(self):
        h = wh._Handler.__new__(wh._Handler)
        responses = []
        h._json = lambda code, body: responses.append((code, body))
        h._auth = lambda: False
        h.path = "/api/v1/health"
        h.headers = {}
        for _ in range(wh._RATE_MAX_DEFAULT * 3):
            responses.clear()
            h.do_GET()
            self.assertEqual(responses[0][0], 401)
        self.assertEqual(wh._rate_hits.get("api", (0, 0))[1], 0)


if __name__ == "__main__":
    unittest.main()
