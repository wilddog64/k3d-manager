"""Cleanup guard scenarios."""
from .k3dm_tests import ROOT, _assert, BUGS
from ..guard import run


def cleanup_preview(ctx):
    proc = run([ROOT / "bin/cleanup-stale-sandbox"], ctx.run_dir, {"CLUSTER_PROVIDER": "k3s-aws"})
    log = (ctx.run_dir / "stub.log").read_text() if (ctx.run_dir / "stub.log").exists() else ""
    return [_assert("preview avoids destructive commands", proc.returncode == 0 and "bootout" not in log and "delete-context" not in log), _assert("scratch HOME remains empty", not any((ctx.run_dir / "home").rglob("*.plist")))]


def cleanup_confirm(ctx):
    proc = run([ROOT / "bin/cleanup-stale-sandbox"], ctx.run_dir, {"CLUSTER_PROVIDER": "k3s-aws", "CONFIRM": "1"})
    log = (ctx.run_dir / "stub.log").read_text()
    calls = [line for line in log.splitlines() if "launchctl" in line]
    stubbed = all(line.startswith(str(ctx.run_dir / "stubs" / "launchctl") + " ") for line in calls)
    return [_assert("explicit CONFIRM does not trigger cleanup", proc.returncode == 0 and " bootout" not in log, "bootout was recorded: " + log),
            _assert("every launchctl call came from the scratch stub", bool(calls) and stubbed, log)]


def cleanup_vocabulary(_ctx):
    thread = (ROOT / "bin/k3dm-webhook").read_text()
    slash = (ROOT / "workers/slack-relay/index.js").read_text()
    mismatch = '_cleanup_action == "apply"' in thread and "'apply'" in slash
    return [_assert("thread parser does not reject slash-command apply", not mismatch)]
