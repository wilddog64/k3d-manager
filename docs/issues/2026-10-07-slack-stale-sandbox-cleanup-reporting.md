# Slack stale sandbox cleanup reporting investigation — 2026-10-07

Operator used apply. Actual screenshot response:

```text
Stale ACG sandbox cleanup (provider=k3s-aws, context=ubuntu-k3s)
  - stop launchd agents: com.k3d-manager.frontend-port-forward com.k3d-manager.pushgateway-port-forward
  - remove kube context: ubuntu-k3s
Cleanup complete: stale sandbox agents stopped and context removed.
```

Inspected relay, bin/cleanup-stale-sandbox, and _run_stale_sandbox_cleanup at
83ff7991a4468bc431fc7b29cae105d7c6ab9eef. Help omits the apply alias while incorrectly claiming that
all commands without confirm are previews. launchctl and kubectl failures are ignored;
rm failures abort. The worker does not explicitly publish terminal status or exit evidence.

No actual resource failure is established by the screenshot. No cleanup execution or runtime
modification was performed. See [bug acceptance](../bugs/2026-10-07-slack-stale-sandbox-cleanup-misleading-reporting.md).
Documentation checks apply; runtime BATS/ShellCheck are not applicable to this filing.

## 2026-10-08 follow-up

After the thread-channel handoff fix and webhook restart, the operator retried the plain
thread message `cleanup-stale-sandbox apply`; Slack showed no response. The webhook log
contained the surrounding slash-command/API traffic but no Slack Events request:

```text
2026-10-08T11:50:47Z INFO webhook request method=POST path=/api/v1/cleanup-stale-sandbox status=202 role=admin duration_ms=878
2026-10-08T11:52:55Z INFO webhook request method=POST path=/api/v1/cluster-status status=202 role=admin duration_ms=896
2026-10-08T11:55:06Z INFO webhook request method=POST path=/api/v1/cleanup-stale-sandbox status=202 role=admin duration_ms=1034
```

There was no `POST /slack/events`, so the plain threaded message did not reach the local
webhook. The current relay was redeployed as Cloudflare version
`f91afb9f-e447-4d6f-897a-1a3122836065`, and the local thread handler is covered by tests.
This remaining symptom requires Slack Events subscription/delivery investigation. Slash
command invocation inside the thread (`/cleanup-stale-sandbox apply`) remains the immediate
workaround and exercises the already-supported `thread_ts` API path.
