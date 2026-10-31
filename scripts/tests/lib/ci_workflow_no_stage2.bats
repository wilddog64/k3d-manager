#!/usr/bin/env bats

@test "CI workflow: retired jobs and self-hosted runners stay absent" {
  run python3 - "${CI_WORKFLOW_PATH:-${BATS_TEST_DIRNAME}/../../../.github/workflows/ci.yml}" <<'PY'
import sys
import yaml

with open(sys.argv[1], encoding="utf-8") as workflow:
    text = workflow.read()
jobs = yaml.safe_load(text)["jobs"]
assert "stage2" not in jobs, "stage2 job must be absent"
assert "detect" not in jobs, "detect job must be absent"
assert "ci:cluster-tests" not in text, "retired label must be absent"
for name, job in jobs.items():
    runner = job.get("runs-on", [])
    if isinstance(runner, str):
        runner = [runner]
    elif isinstance(runner, dict):
        runner = runner.get("labels", [])
        if isinstance(runner, str):
            runner = [runner]
    assert "self-hosted" not in runner, f"{name} uses a self-hosted runner"
    needs = job.get("needs", [])
    if isinstance(needs, str):
        needs = [needs]
    assert all(dependency in jobs for dependency in needs), f"{name} needs a missing job"
PY
  if [ "$status" -ne 0 ]; then
    printf "%s\n" "$output"
    return "$status"
  fi
}
