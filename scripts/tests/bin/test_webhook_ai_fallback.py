"""Offline tests for the webhook AI candidate fallback."""

import os
import stat
import tempfile
import unittest
from pathlib import Path

import sys

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "scripts" / "lib"))

from webhook import agent  # noqa: E402


class WebhookAIFallbackTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.bin_dir = Path(self.tmp.name)
        self.old_env = os.environ.copy()
        for key in (
            "K3DM_GEMINI_BIN", "K3DM_AI_BIN_ORDER", "K3DM_ANALYSIS_MODEL_GEMINI",
            "K3DM_AI_TOTAL_BUDGET_S",
        ):
            os.environ.pop(key, None)
        os.environ["PATH"] = f"{self.bin_dir}:{self.old_env.get('PATH', '')}"
        os.environ["K3DM_AI_TOTAL_BUDGET_S"] = "30"
        agent.GEMINI_MODEL = "gemini-3.8-flash-medium"

    def tearDown(self):
        os.environ.clear()
        os.environ.update(self.old_env)
        self.tmp.cleanup()

    def fake(self, name, body):
        path = self.bin_dir / name
        path.write_text("#!/bin/sh\n" + body + "\n")
        path.chmod(path.stat().st_mode | stat.S_IXUSR)
        return path

    def call(self, prompt="synthetic prompt"):
        return agent._call_gemini(prompt)

    def test_fallback_happens(self):
        self.fake("agy", 'echo "Authentication required. Please visit the URL to log in:"; echo "https://accounts.google.com/o/oauth2/auth?state=abc"; exit 1')
        self.fake("gemini", 'echo PONG; exit 0')
        self.assertEqual(self.call(), "PONG")

    def test_no_oauth_url_escapes(self):
        self.fake("agy", 'echo "Authentication required. Please visit the URL to log in:"; echo "https://accounts.google.com/o/oauth2/auth?state=abc"; exit 1')
        self.fake("gemini", 'echo "not logged into Antigravity"; exit 1')
        result = self.call()
        self.assertTrue(result.startswith("AI analysis unavailable"))
        self.assertIn("not-logged-in", result)
        self.assertNotIn("accounts.google.com", result)

    def test_unavailable_result_carries_safe_failure_metadata(self):
        self.fake("agy", 'echo "Authentication required. Please visit the URL"; exit 1')
        self.fake("gemini", 'echo "not logged into Antigravity"; exit 1')
        result = self.call()
        self.assertEqual(result.metadata["status"], "failed")
        self.assertEqual(result.metadata["failure_class"], "summary_model_unavailable")
        self.assertIn("agy: not-logged-in", result.metadata["failures"])
        self.assertIn("gemini: not-logged-in", result.metadata["failures"])
        first = result.metadata["failure_details"][0]
        self.assertEqual(first["candidate"], "agy")
        self.assertEqual(first["exit_code"], 1)
        self.assertIsInstance(first["elapsed_s"], float)
        self.assertFalse(first["timed_out"])

    def test_nonzero_exit_is_failure_even_with_answer_like_output(self):
        self.fake("agy", 'echo "STALLED — waiting on a pod"; exit 1')
        self.fake("gemini", 'echo PROGRESSING; exit 0')
        self.assertEqual(self.call(), "PROGRESSING")

    def test_pinned_candidate_disables_fallback(self):
        agy = self.fake("agy", 'echo "Authentication required. Please visit the URL"; exit 1')
        marker = self.bin_dir / "gemini-called"
        self.fake("gemini", f'touch "{marker}"; echo PROGRESSING; exit 0')
        os.environ["K3DM_GEMINI_BIN"] = str(agy)
        result = self.call()
        self.assertTrue(result.startswith("AI analysis unavailable"))
        self.assertFalse(marker.exists())

    def test_trust_gate_is_classified_and_falls_back(self):
        self.fake("agy", 'echo "Gemini CLI is not running in a trusted directory"; exit 55')
        self.fake("gemini", 'echo TRUSTED; exit 0')
        self.assertEqual(self.call(), "TRUSTED")

    def test_model_drift_is_classified_even_with_zero_exit(self):
        self.fake("agy", 'echo "model gemini-2.5-flash is not recognized as a known model"; exit 0')
        self.fake("gemini", 'echo RECOVERED; exit 0')
        self.assertEqual(self.call(), "RECOVERED")

    def test_healthy_first_candidate_does_not_spawn_second(self):
        marker = self.bin_dir / "gemini-called"
        self.fake("agy", 'echo HEALTHY; exit 0')
        self.fake("gemini", f'touch "{marker}"; echo SECOND; exit 0')
        self.assertEqual(self.call(), "HEALTHY")
        self.assertFalse(marker.exists())

    def test_candidate_argv_shape(self):
        agy_args = self.bin_dir / "agy.args"
        gemini_args = self.bin_dir / "gemini.args"
        self.fake("agy", f'printf "%s\\n" "$@" > "{agy_args}"; exit 1')
        self.fake("gemini", f'printf "%s\\n" "$@" > "{gemini_args}"; echo OK; exit 0')
        self.assertEqual(self.call(), "OK")
        self.assertIn("--model\ngemini-3.8-flash-medium", agy_args.read_text())
        self.assertIn("--skip-trust", gemini_args.read_text())
        self.assertNotIn("--model", gemini_args.read_text())

        os.environ["K3DM_ANALYSIS_MODEL_GEMINI"] = "gemini-custom"
        gemini_args.unlink()
        self.assertEqual(self.call(), "OK")
        self.assertIn("--model\ngemini-custom", gemini_args.read_text())


if __name__ == "__main__":
    unittest.main()
