#!/usr/bin/env bats

DASHBOARD="${BATS_TEST_DIRNAME}/../../etc/grafana/dashboards/k3dm-deployments-configmap.yaml"
HARNESS="${BATS_TEST_DIRNAME}/../lib/webhook.bats"

@test "every deployment panel aggregates job_id away" {
  run python3 - "${DASHBOARD}" <<'PY'
import re, sys
text = open(sys.argv[1]).read()
exprs = re.findall(r'"expr": "(.*?)",?\n', text)
exprs = [e for e in exprs if "k3dm_deployment" in e]
assert len(exprs) == 5, f"expected 5 deployment exprs, found {len(exprs)}"
for expr in exprs:
    assert expr.startswith("max by ("), f"not aggregated: {expr}"
    assert "job_id" not in expr, f"job_id leaked into grouping: {expr}"
print("OK", len(exprs))
PY
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"OK 5"* ]]
}

@test "the webhook harness neutralizes the Pushgateway" {
  run grep -F -- 'export K3DM_PUSHGATEWAY_URL=""' "${HARNESS}"
  [ "${status}" -eq 0 ]
}
