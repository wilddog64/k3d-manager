# Dispatch spec: classify failed Hostinger diagnostics by command exit status

**Implementation:** landed as `6be25c92` on `k3d-manager-v1.43.5`; independently verified offline. The Hostinger outage remains OPEN and unrelated to this classification result.

Fix the confirmed webhook diagnostic-result classification defect recorded in [the Hostinger incident](../bugs/2026-10-20-hostinger-multi-service-502-kubernetes-api-timeouts.md). The 2026-10-20 API-path fault domain remains unknown and is not part of this implementation task.

## Source finding

`scripts/lib/webhook/status.py::_posix_spawn_capture` currently discards the subprocess return code and returns only output and timeout state. `_run_cluster_diagnostics` marks a prompt, non-timeout command successful regardless of whether `kubectl` exited nonzero. The incident's approved diagnostic displayed an API timeout in its output while the wrapper reported `success`.

## Required behavior

- A diagnostic command exiting 0 and not timing out remains `success`.
- A diagnostic command exiting nonzero is `failed`, even if it produced output.
- A diagnostic timeout remains `failed` and retains its distinct timeout message.
- Preserve bounded output, redaction, read-only command allowlists, response/thread routing, and existing status behavior for unrelated status probes.
- Do not make a `success` job status imply all checks in a multi-check status report passed; this change is only about the explicit `/api/v1/diagnostics` command's process result.

## Files

- `scripts/lib/webhook/status.py`
- `scripts/tests/bin/test_webhook_cluster_status_thread.py`

The canonical incident and this spec are context only; do not edit them in the implementation dispatch unless test findings require a factual correction, in which case report it without broadening the code change.

## Acceptance

1. A deterministic unit test stubs a prompt `kubectl` nonzero exit with error output and asserts the persisted job status is `failed`, while the output remains useful and safely redacted.
2. A deterministic unit test asserts exit code 0 remains `success`.
3. A timeout test confirms existing timeout classification/message is preserved.
4. Existing diagnostics routing/thread tests and the focused webhook BATS suite pass.
5. No AWS, Kubernetes, Hostinger, Argo CD authentication, Slack live calls, or infrastructure operations are performed by the task.

## Verification

Run the focused pytest module `scripts/tests/bin/test_webhook_cluster_status_thread.py`, `bats scripts/tests/lib/webhook.bats`, Python AST/syntax validation, `git diff --check`, `_agent_lint`, and `_agent_audit`. This is an offline software fix only; no live verification of the historical incident cause is implied.
