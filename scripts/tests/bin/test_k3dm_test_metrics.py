import importlib.machinery
import importlib.util
import os
import plistlib
import re
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path




ROOT = Path(__file__).resolve().parents[3]
SOURCE = ROOT / "bin" / "k3dm-test-metrics"
SPEC = importlib.util.spec_from_loader(
    "k3dm_test_metrics", importlib.machinery.SourceFileLoader("k3dm_test_metrics", str(SOURCE))
)
METRICS = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(METRICS)
FIXTURE = ROOT / "scripts" / "tests" / "fixtures" / "k3dm-test-metrics.log"


def fixture_text():
    return FIXTURE.read_text()


def test_bats_tap_counts_match_the_fixture():
    parsed = METRICS.parse_log(fixture_text())
    assert parsed["suites"]["webhook.bats"] == {"ok": 2, "not_ok": 0}
    assert parsed["suites"]["policy.bats"] == {"ok": 1, "not_ok": 1}


def test_a_red_case_is_attributed_to_the_right_suite():
    parsed = METRICS.parse_log(fixture_text())
    assert parsed["suites"]["policy.bats"]["not_ok"] == 1
    assert parsed["suites"]["webhook.bats"]["not_ok"] == 0


def test_real_combined_bats_output_aggregates_and_counts_its_red():
    parsed = METRICS.parse_log(
        "./scripts/k3d-manager test all\n1..3\nok 1 alpha\nnot ok 2 beta\nok 3 gamma\n"
    )
    assert parsed["suites"]["bats"] == {"ok": 2, "not_ok": 1}
    assert parsed["failed"] == 1
    payload = METRICS.build_payload(parsed, "test-all", 0)
    assert 'k3dm_test_cases_failed{target="test-all"} 1' in payload
    assert "k3dm_test_last_success_timestamp_seconds" not in payload


def test_failed_bats_cases_publish_bounded_name_and_reason_labels():
    parsed = METRICS.parse_log(
        "# file: observability.bats\n1..2\nok 1 good\nnot ok 2 deploy fallback\n"
        "#   expected generated config\n"
    )
    payload = METRICS.build_payload(parsed, "test-all", 2)
    assert 'k3dm_test_failure{target="test-all",suite="observability.bats",case="2",name="deploy fallback",reason="expected generated config"} 1' in payload


def test_unittest_and_pytest_blocks_are_parsed():
    parsed = METRICS.parse_log(fixture_text())
    assert parsed["suites"]["webhook_policy.py"] == {"ok": 12, "not_ok": 2}
    assert parsed["suites"]["pytest"] == {"ok": 189, "not_ok": 2}
    assert parsed["total"] == 209
    assert parsed["failed"] == 5


def test_total_equals_sum_of_suites():
    parsed = METRICS.parse_log(fixture_text())
    assert parsed["total"] == sum(sum(values.values()) for values in parsed["suites"].values())


def test_success_timestamp_is_omitted_when_any_case_failed():
    parsed = METRICS.parse_log(fixture_text())
    payload = METRICS.build_payload(parsed, "test-all", 0, now=123)
    assert "k3dm_test_last_success_timestamp_seconds" not in payload


def test_exit_code_0_with_zero_failures_is_a_success():
    parsed = METRICS.parse_log("# file: clean.bats\n1..1\nok 1 works\n")
    payload = METRICS.build_payload(parsed, "test-all", 0, now=123)
    assert 'k3dm_test_cases_failed{target="test-all"} 0' in payload
    assert "k3dm_test_last_success_timestamp_seconds 123" in payload


def test_nonzero_exit_code_does_not_update_last_success_timestamp():
    parsed = METRICS.parse_log("# file: clean.bats\n1..1\nok 1 works\n")
    payload = METRICS.build_payload(parsed, "test-all", 2, now=123)
    assert 'k3dm_test_run_classification{target="test-all",classification="failed_untriaged"} 1' in payload
    assert "k3dm_test_last_success_timestamp_seconds" not in payload


def test_run_classification_follows_terminal_exit_code():
    parsed = METRICS.parse_log("# file: clean.bats\n1..1\nok 1 works\n")
    passed = METRICS.build_payload(parsed, "test-all", 0)
    failed = METRICS.build_payload(parsed, "test-all", 2)
    assert 'k3dm_test_run_classification{target="test-all",classification="passed"} 1' in passed
    assert 'k3dm_test_run_classification{target="test-all",classification="failed_untriaged"} 1' in failed


def test_success_marker_is_separate_and_bounded_to_the_success_group():
    marker = METRICS.build_success_marker(now=123)
    assert marker == (
        "# HELP k3dm_test_last_success_timestamp_seconds Unix timestamp of the last run with zero failures and exit code 0\n"
        "# TYPE k3dm_test_last_success_timestamp_seconds gauge\n"
        "k3dm_test_last_success_timestamp_seconds 123\n"
    )


def test_main_publishes_success_marker_only_after_a_success(monkeypatch, tmp_path):
    monkeypatch.setenv("K3DM_PUSHGATEWAY_URL", "http://127.0.0.1:9")
    log = tmp_path / "run.log"
    log.write_text("# file: clean.bats\n1..1\nok 1 works\n")
    calls = []
    monkeypatch.setattr(METRICS, "push_metrics", lambda payload, *args, **kwargs: calls.append((payload, args, kwargs)))
    METRICS.main([str(log), "--target", "test-all", "--exit-code", "0"])
    assert len(calls) == 2
    assert calls[1][2]["group_suffix"] == "-last-success"


def test_main_does_not_publish_success_marker_after_a_failure(monkeypatch, tmp_path):
    monkeypatch.setenv("K3DM_PUSHGATEWAY_URL", "http://127.0.0.1:9")
    log = tmp_path / "run.log"
    log.write_text("# file: clean.bats\n1..1\nok 1 works\n")
    calls = []
    monkeypatch.setattr(METRICS, "push_metrics", lambda payload, *args, **kwargs: calls.append((payload, args, kwargs)))
    METRICS.main([str(log), "--target", "test-all", "--exit-code", "2"])
    assert len(calls) == 1


def test_origin_is_in_the_grouping_url_not_only_a_label():
    def healthy_opener(request, timeout):
        class Response:
            status = 200

            def __enter__(self):
                return self

            def __exit__(self, *args):
                return False

        return Response()

    assert METRICS.push_metrics("payload", "test-all", "ci", endpoint="http://example.test", opener=healthy_opener).endswith(
        "/metrics/job/k3dm-tests/instance/test-all-ci"
    )


def test_no_metric_is_labelled_by_test_name():
    parsed = METRICS.parse_log(fixture_text())
    payload = METRICS.build_payload(parsed, "test-all", 0)
    for line in payload.splitlines():
        if "{" in line:
            if line.startswith("k3dm_test_failure{"):
                continue
            labels = line.split("}", 1)[0]
            assert all(" " not in value and len(value) <= 80 for value in re.findall(r'="([^"]*)"', labels))


def test_failure_labels_are_bounded_and_escaped():
    parsed = METRICS.parse_log(
        '# file: clean.bats\n1..1\nnot ok 1 bad "case"\n# reason\n'
    )
    payload = METRICS.build_payload(parsed, "test-all", 1)
    assert 'name="bad \\"case\\""' in payload
    failure_line = next(line for line in payload.splitlines() if line.startswith("k3dm_test_failure"))
    assert all(len(value) <= METRICS.MAX_LABEL_LENGTH for value in re.findall(r'="((?:\\.|[^"\\])*)"', failure_line))


def test_push_failure_is_non_fatal(monkeypatch, capsys):
    monkeypatch.setattr(METRICS, "PUSH_SLEEP_SECONDS", 0)

    def broken_opener(*args, **kwargs):
        raise OSError("offline")

    result = METRICS.push_metrics("payload", "test", "local", endpoint="http://offline", opener=broken_opener)
    assert result.endswith("/metrics/job/k3dm-tests/instance/test-local")
    assert "non-fatal" in capsys.readouterr().out


def test_push_to_local_throwaway_server_receives_payload(monkeypatch):
    received = []

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            self.send_response(200)
            self.end_headers()

        def do_PUT(self):
            received.append(self.rfile.read(int(self.headers["Content-Length"])).decode())
            self.send_response(200)
            self.end_headers()

        def log_message(self, *_args):
            pass

    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    monkeypatch.setattr(METRICS, "PUSH_RETRIES", 1)
    try:
        payload = "# HELP local metric\n# TYPE local gauge\nlocal 1\n"
        METRICS.push_metrics(payload, "test", "local", endpoint=f"http://127.0.0.1:{server.server_port}")
    finally:
        server.shutdown()
        thread.join()
        server.server_close()
    assert received == [payload]


def test_payload_is_valid_prometheus_text_format():
    parsed = METRICS.parse_log(fixture_text())
    payload = METRICS.build_payload(parsed, "test-all", 0)
    types = {line.split()[2] for line in payload.splitlines() if line.startswith("# TYPE")}
    assert types
    for line in payload.splitlines():
        if line.startswith("#"):
            continue
        assert re.match(r"^[a-zA-Z_:][a-zA-Z0-9_:]*(\{[^}]*\})? -?[0-9]+(?:\.[0-9]+)?$", line)
        assert "NaN" not in line and "inf" not in line.lower()


def test_pytest_summary_duration_is_parsed():
    parsed = METRICS.parse_log(fixture_text())
    assert parsed["durations"]["pytest"] == 4.0


def test_suite_without_a_reported_duration_is_omitted_not_zero():
    parsed = METRICS.parse_log("# file: clean.bats\n1..1\nok 1 works\n")
    payload = METRICS.build_payload(parsed, "test-all", 0, now=123)
    assert 'k3dm_test_suite_duration_seconds{suite="clean.bats"}' not in payload


def test_run_duration_is_published_when_measured():
    parsed = METRICS.parse_log(fixture_text())
    payload = METRICS.build_payload(parsed, "test-all", 0, now=123, run_duration=917)
    assert 'k3dm_test_run_duration_seconds{target="test-all"} 917' in payload
    assert "k3dm_test_run_duration_seconds 0" not in payload


def test_run_duration_is_omitted_when_not_measured():
    parsed = METRICS.parse_log(fixture_text())
    payload = METRICS.build_payload(parsed, "test-all", 0, now=123)
    assert "k3dm_test_run_duration_seconds" not in payload


def test_complete_expected_stages_publish_run_complete_one():
    parsed = METRICS.parse_log(
        "[test-all] stage-complete test\n"
        "[test-all] stage-complete test-bin\n"
        "[test-all] stage-complete test-python\n"
    )
    payload = METRICS.build_payload(
        parsed, "test-all", 0, expected_stages=["test", "test-bin", "test-python"]
    )
    assert 'k3dm_test_run_complete{target="test-all"} 1' in payload


def test_failing_stage_that_prints_marker_publishes_run_complete_one():
    parsed = METRICS.parse_log(
        "[test-all] stage-complete test\n"
        "[test-all] stage-complete test-bin\n"
        "[test-all] stage-complete test-python\n"
    )
    payload = METRICS.build_payload(
        parsed, "test-all", 1, expected_stages=["test", "test-bin", "test-python"]
    )
    assert 'k3dm_test_run_complete{target="test-all"} 1' in payload
    assert 'k3dm_test_run_classification{target="test-all",classification="failed_untriaged"} 1' in payload


def test_parallel_log_with_stage_complete_is_accepted_by_test_metrics():
    # Captured from real output on host m4-air.local, 2026-11-13, Bats 1.12.0, pytest 9.1.1
    # Command: make --no-print-directory test-all PARALLEL=1 STAGE_TEST_FILES="scripts/tests/plugins/argocd_platform_ops_message.bats /tmp/failing_test.bats" STAGE_TEST_BIN_FILES="scripts/tests/bin/k3dm_slack_notify.bats" STAGE_TEST_PYTHON_FILES="scripts/tests/bin/test_cni_ipam_rules.py"
    log_text = (
        "FAIL /tmp/failing_test.bats 1s (rc 1)\n"
        "PASS scripts/tests/plugins/argocd_platform_ops_message.bats 1s\n"
        "SLOWEST /tmp/failing_test.bats 1s\n"
        "TOTAL 1s\n"
        "1..1\n"
        "not ok 1 deliberate failure for capture\n"
        "# (in test file /tmp/failing_test.bats, line 2)\n"
        "#   `false' failed\n"
        "1..1\n"
        "ok 1 platform-ops: closing message reports current schedules\n"
        "[test-all] stage-complete test\n"
        "PASS scripts/tests/bin/k3dm_slack_notify.bats 1s\n"
        "SLOWEST scripts/tests/bin/k3dm_slack_notify.bats 1s\n"
        "TOTAL 1s\n"
        "1..2\n"
        "ok 1 slack notify: empty stdin exits 2\n"
        "ok 2 slack notify: failed relay exits 1 without exposing URL\n"
        "[test-all] stage-complete test-bin\n"
        "Agent docs check passed\n"
        "PASS scripts/tests/bin/test_cni_ipam_rules.py 1s\n"
        "SLOWEST scripts/tests/bin/test_cni_ipam_rules.py 1s\n"
        "TOTAL 1s\n"
        "============================= test session starts ==============================\n"
        "platform darwin -- Python 3.13.6, pytest-9.1.1, pluggy-1.6.0\n"
        "rootdir: /Users/cliang/.local/share/k3d-manager/worktrees/v1.44.0/parallel-offline-tests-b\n"
        "collected 2 items\n"
        "\n"
        "scripts/tests/bin/test_cni_ipam_rules.py ..                              [100%]\n"
        "\n"
        "============================== 2 passed in 0.03s ===============================\n"
        "[test-all] stage-complete test-python\n"
        "[test-all] failed:\n"
        "FAIL /tmp/failing_test.bats 1s (rc 1)\n"
    )
    parsed = METRICS.parse_log(log_text)
    assert parsed["completed_stages"] == {"test", "test-bin", "test-python"}
    payload = METRICS.build_payload(
        parsed, "test-all", 1, expected_stages=["test", "test-bin", "test-python"]
    )
    assert 'k3dm_test_run_complete{target="test-all"} 1' in payload
    assert 'k3dm_test_cases_total{target="test-all"} 6' in payload
    assert 'k3dm_test_cases_failed{target="test-all"} 1' in payload


def test_partial_expected_stages_publish_run_complete_zero():
    parsed = METRICS.parse_log("[test-all] stage-complete test\n")
    payload = METRICS.build_payload(
        parsed, "test-all", 2, expected_stages=["test", "test-bin", "test-python"]
    )
    assert 'k3dm_test_run_complete{target="test-all"} 0' in payload


def test_run_complete_is_not_published_without_expected_stages():
    parsed = METRICS.parse_log("[test-all] stage-complete test\n")
    payload = METRICS.build_payload(parsed, "test-all", 0)
    assert "k3dm_test_run_complete" not in payload


def test_main_publishes_run_complete_from_expected_stages_flag(monkeypatch, tmp_path):
    monkeypatch.setenv("K3DM_PUSHGATEWAY_URL", "http://127.0.0.1:9")
    log = tmp_path / "run.log"
    log.write_text(
        "[test-all] stage-complete test\n"
        "[test-all] stage-complete test-bin\n"
        "[test-all] stage-complete test-python\n"
    )
    pushed = []
    monkeypatch.setattr(METRICS, "push_metrics", lambda payload, *args, **kwargs: pushed.append(payload))
    METRICS.main([
        str(log), "--target", "test-all", "--expected-stages", "test,test-bin,test-python",
    ])
    assert 'k3dm_test_run_complete{target="test-all"} 1' in pushed[0]


def test_main_forwards_run_duration(monkeypatch, tmp_path):
    monkeypatch.setenv("K3DM_PUSHGATEWAY_URL", "http://127.0.0.1:9")
    log = tmp_path / "run.log"
    log.write_text("# file: clean.bats\n1..1\nok 1 works\n")
    pushed = []
    monkeypatch.setattr(METRICS, "push_metrics", lambda payload, *args, **kwargs: pushed.append(payload))
    METRICS.main([str(log), "--target", "test-all", "--run-duration", "42"])
    assert 'k3dm_test_run_duration_seconds{target="test-all"} 42' in pushed[0]


def test_main_without_pushgateway_url_publishes_nothing(capsys, monkeypatch, tmp_path):
    monkeypatch.delenv("K3DM_PUSHGATEWAY_URL", raising=False)
    assert "K3DM_PUSHGATEWAY_URL" not in os.environ
    urlopen_calls = []
    push_calls = []
    monkeypatch.setattr(METRICS.urllib.request, "urlopen", lambda *args, **kwargs: urlopen_calls.append((args, kwargs)))
    monkeypatch.setattr(METRICS, "push_metrics", lambda *args, **kwargs: push_calls.append((args, kwargs)))
    log = tmp_path / "run.log"
    log.write_text("# file: clean.bats\n1..1\nok 1 works\n")
    rc = METRICS.main([str(log), "--target", "test-all", "--exit-code", "0"])
    assert rc == 0
    assert len(urlopen_calls) == 0
    assert len(push_calls) == 0
    captured = capsys.readouterr()
    assert "[k3dm-test-metrics] metrics not published (K3DM_PUSHGATEWAY_URL unset)" in captured.out


def test_main_with_blank_pushgateway_url_publishes_nothing(capsys, monkeypatch, tmp_path):
    monkeypatch.setenv("K3DM_PUSHGATEWAY_URL", "  ")
    urlopen_calls = []
    push_calls = []
    monkeypatch.setattr(METRICS.urllib.request, "urlopen", lambda *args, **kwargs: urlopen_calls.append((args, kwargs)))
    monkeypatch.setattr(METRICS, "push_metrics", lambda *args, **kwargs: push_calls.append((args, kwargs)))
    log = tmp_path / "run.log"
    log.write_text("# file: clean.bats\n1..1\nok 1 works\n")
    rc = METRICS.main([str(log), "--target", "test-all", "--exit-code", "0"])
    assert rc == 0
    assert len(urlopen_calls) == 0
    assert len(push_calls) == 0
    captured = capsys.readouterr()
    assert "[k3dm-test-metrics] metrics not published (K3DM_PUSHGATEWAY_URL unset)" in captured.out


def test_main_with_explicit_pushgateway_url_publishes(capsys, monkeypatch, tmp_path):
    monkeypatch.setenv("K3DM_PUSHGATEWAY_URL", "http://127.0.0.1:9")
    push_calls = []
    monkeypatch.setattr(METRICS, "push_metrics", lambda payload, *args, **kwargs: push_calls.append((payload, args, kwargs)))
    log = tmp_path / "run.log"
    log.write_text("# file: clean.bats\n1..1\nok 1 works\n")
    rc = METRICS.main([str(log), "--target", "test-all", "--exit-code", "0"])
    assert rc == 0
    assert len(push_calls) == 2
    assert push_calls[1][2].get("group_suffix") == "-last-success"
    captured = capsys.readouterr()
    assert "metrics not published (K3DM_PUSHGATEWAY_URL unset)" not in captured.out


def test_nightly_plist_sets_pushgateway_url():
    template_path = ROOT / "scripts" / "etc" / "launchd" / "com.k3d-manager.test-metrics.plist.tmpl"
    raw_content = template_path.read_text()
    substituted = re.sub(r"\{\{[^}]+\}\}", "/test/path", raw_content)
    parsed = plistlib.loads(substituted.encode("utf-8"))
    assert parsed.get("EnvironmentVariables", {}).get("K3DM_PUSHGATEWAY_URL") == "http://localhost:9091"
