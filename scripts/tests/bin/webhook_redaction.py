#!/usr/bin/env python3
"""Regression tests for k3dm-webhook secret redaction registration."""
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


class RedactionTests(unittest.TestCase):
    def setUp(self):
        wh._REDACT_VALUES.clear()
        wh._REDACT_SKIPPED.clear()
        wh._REDACT_PATTERN = None

    def test_registers_and_redacts_secret(self):
        self.assertEqual(wh._register_secret("supersecret"), "supersecret")
        redacted = wh._redact_secrets("prefix supersecret suffix")
        self.assertIn("***REDACTED***", redacted)
        self.assertNotIn("supersecret", redacted)

    def test_counts_none(self):
        self.assertIsNone(wh._register_secret(None))
        self.assertEqual(wh._REDACT_SKIPPED["none"], 1)

    def test_counts_non_string(self):
        value = b"bytes"
        self.assertEqual(wh._register_secret(value), value)
        self.assertEqual(wh._REDACT_SKIPPED["not-str"], 1)

    def test_counts_short_value_without_registering(self):
        self.assertEqual(wh._register_secret("ab"), "ab")
        self.assertEqual(wh._REDACT_SKIPPED["too-short"], 1)
        self.assertEqual(wh._redact_secrets("cab"), "cab")

    def test_second_secret_invalidates_compiled_pattern(self):
        wh._register_secret("first-secret")
        wh._redact_secrets("first-secret")
        wh._register_secret("second-secret")
        redacted = wh._redact_secrets("first-secret second-secret")
        self.assertNotIn("first-secret", redacted)
        self.assertNotIn("second-secret", redacted)
        self.assertEqual(redacted, "***REDACTED*** ***REDACTED***")

    def test_empty_and_none_are_unchanged(self):
        self.assertEqual(wh._redact_secrets(""), "")
        self.assertIsNone(wh._redact_secrets(None))


if __name__ == "__main__":
    unittest.main()
