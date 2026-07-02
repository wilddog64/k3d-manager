#!/usr/bin/env bats

SCRIPT="${BATS_TEST_DIRNAME}/../../../bin/k3dm-worker-setup"
MAKEFILE="${BATS_TEST_DIRNAME}/../../../Makefile"

@test "k3dm-worker-setup deploys the worker" {
  run grep -F -- 'npx --yes wrangler deploy' "${SCRIPT}"
  [ "${status}" -eq 0 ]
}

@test "k3dm-worker-setup smoke-tests signed cluster-status after deploy" {
  run grep -F -- '_worker_smoke_test()' "${SCRIPT}"
  [ "${status}" -eq 0 ]

  run grep -F -- 'command=%2Fcluster-status&text=&response_url=https%3A%2F%2Fexample.com' "${SCRIPT}"
  [ "${status}" -eq 0 ]

  run grep -F -- 'X-Slack-Request-Timestamp' "${SCRIPT}"
  [ "${status}" -eq 0 ]

  run grep -F -- 'X-Slack-Signature' "${SCRIPT}"
  [ "${status}" -eq 0 ]
}

@test "k3dm-worker-setup reports a hard failure when the smoke test is not accepted" {
  run grep -F -- '_error "Worker smoke test failed (HTTP ${_code:-000})' "${SCRIPT}"
  [ "${status}" -eq 0 ]
}

@test "make deploy-worker also smoke-tests the live Worker" {
  run grep -F -- 'python3 -c '\''import hmac,hashlib,os; body=os.environ["BODY"]; secret=os.environ["SECRET"].encode(); ts=os.environ["TS"]; msg=f"v0:{ts}:{body}".encode(); print("v0="+hmac.new(secret, msg, hashlib.sha256).hexdigest())'\''' "${MAKEFILE}"
  [ "${status}" -eq 0 ]

  run grep -F -- 'X-Slack-Signature: $$_sig' "${MAKEFILE}"
  [ "${status}" -eq 0 ]

  run grep -F -- '_code=$$(curl -sS -o /dev/null -w '\''%{http_code}'\''' "${MAKEFILE}"
  [ "${status}" -eq 0 ]
}
