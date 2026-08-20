# E2E run exited after teardown without a result artifact

## Observed output

```text
04:37:59 info Waiting for virtual cluster to be deleted...
04:38:26 done Virtual Cluster is deleted
INFO: Deleted vCluster 'e2e-1787138459-450'
make: *** [e2e] Error 1
```

The vCluster teardown completed, but `${HOME}/.k3dm/e2e/` contained no run
log or JSON summary and the hub had no `k3dm.k3d.io/e2e-result=true` ConfigMap.
Therefore the Playwright/job failure reason cannot be recovered from this run.

## Follow-up

Make the E2E wrapper persist a local run-start marker and a failure summary in
an EXIT trap before vCluster teardown, and publish a failure event whenever the
job or substrate setup exits non-zero. Then rerun with the normal job timeout
and retain the Playwright log for diagnosis. This is separate from the
agent-0 kubelet outage; `make status` was healthy after the agent restart.
