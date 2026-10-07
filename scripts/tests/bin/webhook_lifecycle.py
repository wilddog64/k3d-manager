import importlib.util
import os
import tempfile
import threading
import time
import unittest
from importlib.machinery import SourceFileLoader
from pathlib import Path

import sys

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "scripts" / "lib"))
SOURCE = ROOT / "scripts" / "lib" / "webhook" / "lifecycle.py"
SPEC = importlib.util.spec_from_file_location(
    "webhook_lifecycle_test_module", SOURCE,
    loader=SourceFileLoader("webhook_lifecycle_test_module", str(SOURCE)),
)
lifecycle = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(lifecycle)


class WebhookLifecycleTests(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        lifecycle.JOB_DIR = Path(self.temp_dir.name)
        self.notifications = []
        self.spawned = []
        self.published_metrics = []
        self.lock = threading.Lock()
        self.lock.acquire()
        lifecycle.configure_runtime(
            lambda message: None,
            lambda job_id, text: self.notifications.append((job_id, text)),
            lambda *args: None,
            lambda lines: "stall",
            lambda lines: "failure",
            lambda text: text,
            self._spawn_job,
            {
                "current_label": lambda env: "",
                "cluster_name": lambda env: "cluster",
                "patch_label": lambda name, version: None,
                "running_procs": {},
                "running_procs_lock": threading.Lock(),
                "record_acg_state": lambda provider: None,
                "run_post_provision_check": lambda job_id, provider: None,
                "running_cluster_job": lambda: None,
                "make_job_lock": self.lock,
                "publish_test_metrics": lambda *args: self.published_metrics.append(args),
            },
        )
        lifecycle._run_cleanup = lambda *args: None

    def tearDown(self):
        if self.lock.locked():
            self.lock.release()
        self.temp_dir.cleanup()

    def _spawn_job(self, cmd, output_path, cwd=None, env=None):
        self.spawned.append((cmd, output_path, cwd, env))
        Path(output_path).write_text("")
        return lifecycle.os.posix_spawn("/usr/bin/true", ["true"], dict(env or {}))

    def test_make_target_passes_validated_argv_as_a_list(self):
        job_id = "a1b2c3d4"
        (lifecycle.JOB_DIR / job_id).mkdir()
        lifecycle._run_make_target(job_id, ["app-cve-scan", "CRONJOB=app-cve-scan"], 731, "actor-1")
        self.assertEqual(self.spawned[0][0], ["make", "--no-print-directory", "app-cve-scan", "CRONJOB=app-cve-scan"])
        self.assertEqual(self.spawned[0][2], lifecycle.REPO_ROOT)
        self.assertTrue(any("actor-1" in text for _, text in self.notifications))

    def test_make_target_never_uses_shell_or_concatenated_command(self):
        job_id = "a1b2c3d5"
        (lifecycle.JOB_DIR / job_id).mkdir()
        lifecycle._run_make_target(job_id, ["fix-list"], 12, "actor")
        self.assertEqual(self.spawned[0][0], ["make", "--no-print-directory", "fix-list"])
        self.assertEqual(self.published_metrics, [])

    def test_test_all_publishes_captured_log_once_after_completion(self):
        job_id = "a1b2c3d6"
        (lifecycle.JOB_DIR / job_id).mkdir()

        lifecycle._run_make_target(job_id, ["test-all"], 731, "cloud-bridge")

        self.assertEqual(len(self.published_metrics), 1)
        published_job, log_path, exit_code, duration = self.published_metrics[0]
        self.assertEqual(published_job, job_id)
        self.assertEqual(log_path, lifecycle.JOB_DIR / job_id / "make.log")
        self.assertEqual(exit_code, 0)
        self.assertGreaterEqual(duration, 0)
        self.assertEqual((lifecycle.JOB_DIR / job_id / "status").read_text(), "success")

    def test_make_target_times_out_and_kills_the_job(self):
        job_id = "a1b2c3d8"
        job_dir = lifecycle.JOB_DIR / job_id
        job_dir.mkdir()
        child = {}

        def spawn_long_running_job(cmd, output_path, cwd=None, env=None):
            Path(output_path).write_text("")
            child["pid"] = lifecycle.os.posix_spawn(
                "/bin/sleep", ["sleep", "30"], dict(env or {}), setsid=True
            )
            return child["pid"]

        lifecycle._spawn_job = spawn_long_running_job
        started = time.monotonic()
        lifecycle._run_make_target(job_id, ["fix-list"], 0.3, "actor")
        elapsed = time.monotonic() - started

        self.assertEqual((job_dir / "status").read_text(), "failed")
        self.assertTrue(any("timed out after" in text for _, text in self.notifications))
        self.assertLess(elapsed, 5)
        with self.assertRaises(ProcessLookupError):
            os.kill(child["pid"], 0)

    def test_make_target_includes_actor_in_audit_notification(self):
        lifecycle._spawn_capture_text = lambda cmd, **kwargs: (0, "", False)
        job_id = "a1b2c3d9"
        (lifecycle.JOB_DIR / job_id).mkdir()
        lifecycle._run_make_target(job_id, ["fix-list"], 12, "audited-actor")
        self.assertTrue(any("audited-actor" in text for _, text in self.notifications))

    def test_cluster_provider_defaults_to_aws_for_unknown_value(self):
        (lifecycle.JOB_DIR / "a1b2c3d6").mkdir()
        original_waitpid = lifecycle.os.waitpid
        original_wifexited = lifecycle.os.WIFEXITED
        original_wexitstatus = lifecycle.os.WEXITSTATUS
        original_killpg = lifecycle.os.killpg
        try:
            lifecycle.os.waitpid = lambda pid, options: (pid, 0)
            lifecycle.os.WIFEXITED = lambda status: True
            lifecycle.os.WEXITSTATUS = lambda status: 0
            lifecycle.os.killpg = lambda pid, signal: None
            lifecycle._run_cluster("a1b2c3d6", "up", provider="not-a-provider", dry_run=True)
            self.assertEqual(self.spawned[0][0], ["make", "up", "CLUSTER_PROVIDER=k3s-aws"])
        finally:
            lifecycle.os.waitpid = original_waitpid
            lifecycle.os.WIFEXITED = original_wifexited
            lifecycle.os.WEXITSTATUS = original_wexitstatus
            lifecycle.os.killpg = original_killpg

    def test_cluster_refuses_a_concurrent_job(self):
        calls = []
        lifecycle._helpers["running_cluster_job"] = lambda: ("other123", "up")
        lifecycle._helpers["running_procs"] = {}
        lifecycle._spawn_job = lambda *args, **kwargs: calls.append(args)
        lifecycle._run_cluster("a1b2c3d7", "up", provider="aws", dry_run=True)
        self.assertEqual(calls, [])
        self.assertTrue(any("already running" in text for _, text in self.notifications))

    def test_cluster_timeout_kills_sleep_and_marks_failed(self):
        job_id = "a1b2c3e0"
        job_dir = lifecycle.JOB_DIR / job_id
        job_dir.mkdir()
        child = {}

        def spawn_long_running_job(cmd, output_path, cwd=None, env=None):
            Path(output_path).write_text("")
            child["pid"] = lifecycle.os.posix_spawn(
                "/bin/sleep", ["sleep", "60"], dict(env or {}), setsid=True
            )
            return child["pid"]

        lifecycle._spawn_job = spawn_long_running_job
        lifecycle._posix_spawn_job = spawn_long_running_job
        old_timeout = os.environ.get("K3DM_CLUSTER_UP_TIMEOUT")
        os.environ["K3DM_CLUSTER_UP_TIMEOUT"] = "1"
        try:
            started = time.monotonic()
            lifecycle._run_cluster(job_id, "up")
            elapsed = time.monotonic() - started
        finally:
            if old_timeout is None:
                os.environ.pop("K3DM_CLUSTER_UP_TIMEOUT", None)
            else:
                os.environ["K3DM_CLUSTER_UP_TIMEOUT"] = old_timeout

        self.assertLess(elapsed, 40)
        self.assertEqual((job_dir / "status").read_text(), "failed")
        self.assertIn("timed out after 1s", (job_dir / "output").read_text())
        with self.assertRaises(ProcessLookupError):
            os.kill(child["pid"], 0)

    def test_cluster_normal_exit_is_success(self):
        job_id = "a1b2c3e1"
        job_dir = lifecycle.JOB_DIR / job_id
        job_dir.mkdir()

        def spawn_quick_job(cmd, output_path, cwd=None, env=None):
            Path(output_path).write_text("")
            return lifecycle.os.posix_spawn("/usr/bin/true", ["true"], dict(env or {}), setsid=True)

        lifecycle._spawn_job = spawn_quick_job
        lifecycle._posix_spawn_job = spawn_quick_job
        lifecycle._run_cluster(job_id, "up", dry_run=True)
        self.assertEqual((job_dir / "status").read_text(), "success")

    def test_cluster_timeout_escalates_to_sigkill(self):
        job_id = "a1b2c3e2"
        job_dir = lifecycle.JOB_DIR / job_id
        job_dir.mkdir()
        child = {}

        def spawn_term_resistant_job(cmd, output_path, cwd=None, env=None):
            Path(output_path).write_text("")
            child["pid"] = lifecycle.os.posix_spawn(
                "/bin/sh", ["sh", "-c", "trap '' TERM; exec sleep 60"],
                dict(env or {}), setsid=True
            )
            return child["pid"]

        lifecycle._spawn_job = spawn_term_resistant_job
        lifecycle._posix_spawn_job = spawn_term_resistant_job
        old_timeout = os.environ.get("K3DM_CLUSTER_UP_TIMEOUT")
        os.environ["K3DM_CLUSTER_UP_TIMEOUT"] = "1"
        try:
            started = time.monotonic()
            lifecycle._run_cluster(job_id, "up")
            elapsed = time.monotonic() - started
        finally:
            if old_timeout is None:
                os.environ.pop("K3DM_CLUSTER_UP_TIMEOUT", None)
            else:
                os.environ["K3DM_CLUSTER_UP_TIMEOUT"] = old_timeout

        self.assertLess(elapsed, 40)
        self.assertEqual((job_dir / "status").read_text(), "failed")
        with self.assertRaises(ProcessLookupError):
            os.kill(child["pid"], 0)

    def test_cluster_timeout_defaults_and_bridge_bounds(self):
        bridge_spec = importlib.util.spec_from_loader(
            "k3dm_cloud_bridge",
            SourceFileLoader("k3dm_cloud_bridge", str(ROOT / "bin" / "k3dm-cloud-bridge")),
        )
        bridge = importlib.util.module_from_spec(bridge_spec)
        bridge_spec.loader.exec_module(bridge)
        old_up = os.environ.get("K3DM_CLUSTER_UP_TIMEOUT")
        old_down = os.environ.get("K3DM_CLUSTER_DOWN_TIMEOUT")
        try:
            os.environ.pop("K3DM_CLUSTER_UP_TIMEOUT", None)
            os.environ.pop("K3DM_CLUSTER_DOWN_TIMEOUT", None)
            self.assertEqual(lifecycle._cluster_job_timeout("up"), 3300)
            self.assertEqual(lifecycle._cluster_job_timeout("down"), 1500)
            os.environ["K3DM_CLUSTER_UP_TIMEOUT"] = "17"
            os.environ["K3DM_CLUSTER_DOWN_TIMEOUT"] = "19"
            self.assertEqual(lifecycle._cluster_job_timeout("up"), 17)
            self.assertEqual(lifecycle._cluster_job_timeout("down"), 19)
            os.environ["K3DM_CLUSTER_UP_TIMEOUT"] = "not-an-int"
            os.environ["K3DM_CLUSTER_DOWN_TIMEOUT"] = "not-an-int"
            self.assertEqual(lifecycle._cluster_job_timeout("up"), 3300)
            self.assertEqual(lifecycle._cluster_job_timeout("down"), 1500)
            self.assertLess(3300, bridge.LIFECYCLE_TIMEOUTS["sandbox-up"])
            self.assertLess(1500, bridge.LIFECYCLE_TIMEOUTS["sandbox-down"])
        finally:
            for name, value in (("K3DM_CLUSTER_UP_TIMEOUT", old_up), ("K3DM_CLUSTER_DOWN_TIMEOUT", old_down)):
                if value is None:
                    os.environ.pop(name, None)
                else:
                    os.environ[name] = value


if __name__ == "__main__":
    unittest.main()
