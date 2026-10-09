#!/usr/bin/env bats

setup() {
  source "${BATS_TEST_DIRNAME}/../test_helpers.bash"
  init_test_env
  dashboard="${BATS_TEST_DIRNAME}/../../etc/argocd/platform-ops/grafana-dashboard-bugs.yaml"
  metrics="${BATS_TEST_DIRNAME}/../../../bin/k3dm-vectordb-metrics"
}

@test "bug dashboard is valid JSON with uid and Prometheus datasource" {
  run python3 -c 'import json,sys; p=sys.argv[1]; s=open(p).read().split("  k3dm-bugs.json: |\n",1)[1]; d=json.loads(s); assert d["uid"] == "k3dm-bugs"; assert "datasource" in d or any("datasource" in panel for panel in d["panels"])' "${dashboard}"
  [ "${status}" -eq 0 ]
}

@test "every bug metric queried by dashboard is emitted" {
  run python3 - "${dashboard}" "${metrics}" <<'PY'
import json, runpy, sys, tempfile
from pathlib import Path
dashboard, metrics_path = sys.argv[1:]
raw = Path(dashboard).read_text().split("  k3dm-bugs.json: |\n", 1)[1]
data = json.loads(raw)
import re
queries = set()
for panel in data["panels"]:
    for target in panel.get("targets", []):
        queries.update(re.findall(r"k3dm_bug_docs(?:_scan_timestamp_seconds)?", target["expr"]))
module = runpy.run_path(metrics_path)
with tempfile.TemporaryDirectory() as tmp:
    bugs = Path(tmp) / "docs/bugs"
    bugs.mkdir(parents=True)
    (bugs / "one.md").write_text("**Priority:** P1\n**Status:** Open\n")
    output = module["_bug_metrics"](Path(tmp))
assert all(name in output for name in queries)
assert "k3dm_bug_docs_scan_timestamp_seconds" in output
PY
  [ "${status}" -eq 0 ]
}
