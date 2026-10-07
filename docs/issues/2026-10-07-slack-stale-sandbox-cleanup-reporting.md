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
