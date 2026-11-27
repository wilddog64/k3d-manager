"""Metrics and dashboard acceptance scenarios."""
import importlib.util
import json
import os
import re
import shutil
import sys
import urllib.request
from pathlib import Path
from importlib.machinery import SourceFileLoader

from ..fake_pushgateway import FakePushgateway
from ..guard import run, validate_url

ROOT = Path(__file__).resolve().parents[4]
BUGS = {
    "metrics-publication-failure": "docs/bugs/2026-11-26-test-metrics-exporter-exits-zero-when-push-fails.md",
    "panels-multi-target": "docs/bugs/2026-11-26-k3dm-tests-summary-panels-max-across-targets-hide-stale-test-all.md",
    "cleanup-ambient-confirm": "docs/bugs/2026-11-26-stale-sandbox-cleanup-inherits-ambient-confirm.md",
    "cleanup-vocabulary": "docs/bugs/2026-11-26-cleanup-stale-sandbox-apply-accepted-by-slash-command-refused-in-thread.md",
}


def _assert(name, passed, detail=""):
    return {"name": name, "passed": bool(passed), "detail": detail}


def _fixture(name):
    return ROOT / "scripts/tests/fixtures/operator-acceptance" / name


def _export(ctx, fake, fixture, exit_code=0):
    return run([sys.executable, ROOT / "bin/k3dm-test-metrics", fixture, "--target", "test-all", "--exit-code", str(exit_code)], ctx.run_dir,
               {"K3DM_PUSHGATEWAY_URL": validate_url(fake.url)})


def metrics_totals(ctx):
    with FakePushgateway() as fake:
        proc = _export(ctx, fake, _fixture("totals.log"))
        payload = next(iter(fake.groups.values()), "")
        from ..runner import redact
        (ctx.run_dir / "transport.log").write_text(redact(json.dumps(fake.requests, sort_keys=True)))
        return [_assert("exporter exited successfully", proc.returncode == 0, proc.stdout + proc.stderr),
                _assert("declared totals published", "k3dm_test_cases_total{target=\"test-all\"} 4" in payload and "k3dm_test_cases_failed{target=\"test-all\"} 1" in payload),
                _assert("fake Pushgateway recorded exporter PUT", any(method == "PUT" for method, _path, _body in fake.requests))]


def metrics_sequence(ctx):
    with FakePushgateway() as fake:
        t = [100, 200, 300, 400]
        metrics = importlib.util.spec_from_loader("metrics", SourceFileLoader("metrics", str(ROOT / "bin/k3dm-test-metrics")))
        module = importlib.util.module_from_spec(metrics)
        metrics.loader.exec_module(module)
        observed = []
        for index, code in enumerate((0, 1, 2, 0)):
            parsed = module.parse_log(_fixture("fail.log" if code else "pass.log").read_text())
            payload = module.build_payload(parsed, "test-all", code, now=t[index])
            endpoint = validate_url(fake.url)
            opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
            module.push_metrics(payload, "test-all", "local", endpoint=endpoint, opener=opener.open)
            if code == 0:
                module.push_metrics(module.build_success_marker(now=t[index]), "test-all", "local", endpoint=endpoint, group_suffix="-last-success", opener=opener.open)
            observed.append((payload, dict(fake.groups)))
        p0, p1, p2, p3 = (v[0] for v in observed)
        final_failure_group = observed[3][1].get("/metrics/job/k3dm-tests/instance/test-all-local", "")
        return [_assert("last run advances four times", [int(re.search(r"k3dm_test_last_timestamp_seconds (\d+)", p).group(1)) for p in (p0,p1,p2,p3)] == t),
                _assert("last success holds across failures and advances at recovery", "k3dm_test_last_success_timestamp_seconds 100" in observed[1][1].get("/metrics/job/k3dm-tests/instance/test-all-local-last-success", "") and "k3dm_test_last_success_timestamp_seconds 400" in observed[3][1].get("/metrics/job/k3dm-tests/instance/test-all-local-last-success", "")),
                _assert("recovery clears failure group", "k3dm_test_failure" not in p3 and "k3dm_test_failure" not in final_failure_group)]


def publication_failure(ctx):
    with FakePushgateway(fail_put=True) as fake:
        proc = _export(ctx, fake, _fixture("pass.log"))
        return [_assert("stdout reports skipped publication", "metrics push skipped" in proc.stdout.lower(), proc.stdout), _assert("publication failure exits nonzero", proc.returncode != 0, f"observed rc={proc.returncode}")]


def panel_queries(ctx):
    promtool = os.environ.get("PROMTOOL") if os.environ.get("PROMTOOL") and Path(os.environ["PROMTOOL"]).is_file() else shutil.which("promtool")
    if not promtool:
        return [{"name": "promtool available", "passed": False, "detail": "promtool not found", "inconclusive": True}]
    raw = (ROOT / "scripts/etc/grafana/dashboards/k3dm-tests-configmap.yaml").read_text()
    data = raw.split('  k3dm-tests.json: |', 1)[1]
    doc = json.loads("\n".join(line[4:] for line in data.splitlines() if line.startswith("    ")))
    exprs = [t["expr"].replace("$__range", "6h") for panel in doc["panels"] for t in panel.get("targets", [])]
    rules_dir = ctx.run_dir / "promtool"
    rules_dir.mkdir()
    rule_file, test_file = rules_dir / "rules.yml", rules_dir / "tests.yml"
    groups = [{"name": "panel-expressions", "rules": [{"record": f"acceptance_panel_{i}", "expr": expr} for i, expr in enumerate(exprs)]}]
    rule_file.write_text(json.dumps({"groups": groups}))
    # promtool evaluates every dashboard expression against a deterministic, failed-then-recovered fixture series.
    series = [
        {"series": 'k3dm_test_last_timestamp_seconds{target="test",instance="test-local"}', "values": "100 200 300 400"},
        {"series": 'k3dm_test_last_timestamp_seconds{target="test-all",instance="test-all-local"}', "values": "100 100 100 400"},
        {"series": 'k3dm_test_last_success_timestamp_seconds{target="test-all"}', "values": "100 100 100 400"},
        {"series": 'k3dm_test_cases_failed{target="test-all"}', "values": "0 1 1 0"},
        {"series": 'k3dm_test_failure{target="test-all",suite="clean.bats",case="2",name="fail",reason="fixture"}', "values": "_ 1 1 stale"},
        {"series": 'k3dm_test_run_classification{target="test-all",classification="failed_untriaged"}', "values": "_ 1 1 stale"},
        {"series": 'k3dm_test_run_classification{target="test-all",classification="passed"}', "values": "_ _ _ 1"},
        {"series": 'k3dm_test_run_complete{target="test-all"}', "values": "1 1 1 1"},
        {"series": 'k3dm_test_run_duration_seconds{target="test-all"}', "values": "1 1 1 1"},
        {"series": 'k3dm_test_cases_total{target="test-all"}', "values": "4 4 4 4"},
    ]
    expected = {
        "max(k3dm_test_last_timestamp_seconds) * 1000": [{"labels": "{}", "value": 400000}],
        "time() - max(k3dm_test_last_success_timestamp_seconds)": [{"labels": "{}", "value": -220}],
        "k3dm_test_cases_failed": [{"labels": '{__name__="k3dm_test_cases_failed", target="test-all"}', "value": 0}],
        "k3dm_test_failure": [],
        "k3dm_test_run_duration_seconds": [{"labels": '{__name__="k3dm_test_run_duration_seconds", target="test-all"}', "value": 1}],
        "k3dm_test_suite_duration_seconds": [],
        "k3dm_test_cases_total": [{"labels": '{__name__="k3dm_test_cases_total", target="test-all"}', "value": 4}],
        "k3dm_test_run_complete{target=" + '"test-all"' + "}": [{"labels": '{__name__="k3dm_test_run_complete", target="test-all"}', "value": 1}],
        "k3dm_test_run_classification": [{"labels": '{__name__="k3dm_test_run_classification", classification="passed", target="test-all"}', "value": 1}],
        "max_over_time(k3dm_test_failure[6h])": [{"labels": '{case="2", name="fail", reason="fixture", suite="clean.bats", target="test-all"}', "value": 1}],
    }
    query_tests = [{"expr": expr, "eval_time": "3m", "exp_samples": expected[expr]} for expr in exprs]
    (test_file).write_text(json.dumps({"rule_files": [str(rule_file)], "evaluation_interval": "1m", "tests": [{"interval": "1m", "input_series": series, "promql_expr_test": query_tests}]}))
    proc = run([promtool, "test", "rules", str(test_file)], ctx.run_dir)
    shutil.rmtree(rules_dir)
    return [_assert("promtool evaluates every panel expression", proc.returncode == 0 and len(exprs) >= 9, proc.stdout + proc.stderr)]


def multi_target(_ctx):
    return [_assert("summary reports the stale test-all target", "max(k3dm_test_last_timestamp_seconds)" not in (ROOT / "scripts/etc/grafana/dashboards/k3dm-tests-configmap.yaml").read_text(), "panel 1 currently uses max across targets")]


SCENARIOS = [
    ("metrics-totals", [], metrics_totals),
    ("metrics-pass-fail-fail-pass", [], metrics_sequence),
    ("metrics-publication-failure", [], publication_failure),
    ("panels-promql", ["promtool"], panel_queries),
    ("panels-multi-target", ["promtool"], multi_target),
]
