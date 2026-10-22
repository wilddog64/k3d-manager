# ACG live verification stopped before app-cluster registration

**Date:** 2026-10-21
**Result:** Inconclusive for the registration fix; ACG bring-up failed before registration was reached.
**Related:** `docs/bugs/2026-10-20-acg-expiry-leaves-observability-appset-degraded.md`

## Attempt and output

The operator ran `make up CLUSTER_PROVIDER=k3s-aws; make down CLUSTER_PROVIDER=k3s-aws KEEP_LOCAL=1` in the adjacent tmux pane. Because the commands are separated by `;`, the teardown ran after `make up` failed. The captured terminal output was:

```text
INFO: [k3s-aws] Installing k3s server + joining agents...
INFO: [shopping_cart] Installing k3s on ubuntu@ubuntu via k3sup...
WARN: [shopping_cart] ssh-keyscan ubuntu not ready after 120s — k3sup may prompt
ERROR: [shopping_cart] ubuntu@ubuntu did not answer SSH within 180s — node unresponsive; not starting k3sup
WARN: [acg-up] failed (exit 1) — cleaning up local processes...
INFO: [acg-up] leaving the cloudflare tunnel up — it is the hub's public ingress and predates this run
make: *** [up] Error 1
INFO: [acg-down] keep-hub=1 hub-cluster=k3d-cluster
INFO: [acg-down] Stopping sandbox tunnel agents...
[tunnel] stopped
INFO: [acg-down] Tearing down CloudFormation stack (AWS)...
INFO: [acg] Checking AWS credentials...
INFO: [acg] Credentials OK (arn:aws:iam::591706807878:user/cloud_user)
INFO: [acg] Deleting CloudFormation stack k3d-manager-cluster...
```

At last read-only inspection, the pane was still running `make` and the stack deletion had not yet printed completion. No Argo CD cluster-registration or ApplicationSet health output was reached, so this run neither confirms nor refutes the registration fix.

## Follow-up

Once the failed bring-up/teardown has completed, diagnose why the AWS node at `ubuntu` did not answer SSH, then retry bring-up alone. Do not chain teardown with `;` when the intent is to preserve a successful cluster for verification. After bring-up succeeds, inspect the registration verification log and `observability-acg` destination/health.
