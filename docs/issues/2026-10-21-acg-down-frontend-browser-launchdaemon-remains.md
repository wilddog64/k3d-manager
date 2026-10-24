# ACG teardown leaves frontend-browser HTTP system LaunchDaemon installed

**Date:** 2026-10-21  
**Type:** Unexpected live teardown behavior  
**Status:** Open — ACG cluster teardown succeeded, local system daemon remains

## What was tested

Operator ran `make down CLUSTER_PROVIDER=k3s-aws KEEP_LOCAL=1`. AWS stack deletion
and hub deregistration completed, and the command reported overall teardown
success. The frontend-browser HTTP system LaunchDaemon was not unloaded. No
cleanup command was run by Codex.

## Actual terminal output

Visible `make down` output; the AWS account number is redacted:

```text
INFO: [acg-down] keep-hub=1 hub-cluster=k3d-cluster
INFO: [acg-down] Stopping sandbox tunnel agents...
[tunnel] stopped
INFO: [acg-down] Tearing down CloudFormation stack (AWS)...
INFO: [acg] Checking AWS credentials...
INFO: [acg] Credentials OK (arn:aws:iam::[REDACTED-AWS-ACCOUNT]:user/cloud_user)
INFO: [acg] Deleting CloudFormation stack k3d-manager-cluster...
INFO: [acg] Stack deleted
INFO: [acg] Removing ubuntu-k3s context from kubeconfig...
INFO: [acg] Context ubuntu-k3s removed
INFO: [acg] Teardown complete
INFO: [acg-down] AWS stack deletion confirmed; deregistering sandbox from hub ArgoCD...
INFO: [k3s-aws] Deregistered cluster-ubuntu-k3s + generated Applications and retired ApplicationSet/observability-acg from hub ArgoCD (cicd)
INFO: [acg-down] Stopping Vault port-forward...
INFO: [acg-down] Vault port-forward stopped
INFO: [acg-down] Stopping frontend browser HTTP listener launchd daemon...
WARN: [acg-down] com.k3d-manager.sandbox.frontend-browser-http is still installed (see /Users/cliang/.local/share/k3d-manager/k3s-aws/logs/frontend-browser-http-launchctl.log); remove it with: sudo launchctl bootout system /Library/LaunchDaemons/com.k3d-manager.sandbox.frontend-browser-http.plist; sudo rm -f /Library/LaunchDaemons/com.k3d-manager.sandbox.frontend-browser-http.plist
INFO: [acg-down] Stopping Pushgateway port-forward launchd agent...
INFO: [acg-down] Pushgateway port-forward launchd agent unloaded
INFO: [acg-down] Stopping ACG Prometheus port-forward launchd agent...
INFO: [acg-down] ACG Prometheus port-forward launchd agent unloaded
INFO: [acg-down] Stopping frontend port-forward...
INFO: [acg-down] Frontend port-forward LaunchAgent unloaded
INFO: [acg-down] Stopping ACG Prometheus port-forward...
INFO: [acg-down] --keep-hub set — local Hub cluster preserved
INFO: [acg-down] Pruning Docker build cache and unused images...
INFO: [acg-down] Docker prune complete
INFO: [acg-down] Cleaning up stale /tmp files...
INFO: [acg-down] /tmp cleanup complete
INFO: [acg-down] Done. Remote cluster deleted; local Hub preserved.
INFO: [acg-down] cloud teardown: verified (stack k3d-manager-cluster deleted or absent in us-west-2)
```

## Root cause and follow-up

Unknown. The down script detects the installed system LaunchDaemon but does not
remove it automatically. Inspect the launchctl service and its log to determine
whether it is still serving traffic; if removal is intended, use the explicit
`launchctl bootout` and plist cleanup shown by the warning. Do not treat this
local daemon warning as a failure of the AWS stack deletion or ArgoCD
ApplicationSet cleanup.
