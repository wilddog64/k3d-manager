# Documentation dispatch: spec self-edit and directory scope findings

**Date:** 2026-10-21
**Area:** Codex dispatch scope / documentation task hygiene
**Tasks:** `grafana-dashboard-guide-split`, `cve-guide-github-render-investigation`

## What was observed

The CVE rendering investigation returned useful read-only findings but appended them to its own
bug spec, which is excluded from the dispatched task's writable scope. The change was removed
from the isolated worktree; no lasting source change remains. The task's last-message and run log
retain the investigation results.

The Grafana guide bug's `## Files` section lists `docs/guides/grafana-dashboards/` as the target
directory. The task generated standalone Markdown pages beneath that directory. The dispatch
status scope checker reports those files outside the literal directory path, even though the bug
spec's proposed design explicitly calls for the per-dashboard pages in that directory.

## Actual status output

```text
task: cve-guide-github-render-investigation
state: exited successfully
network: yes
 M docs/bugs/2026-10-20-cve-remediation-guide-github-render-error.md
out-of-scope: docs/bugs/2026-10-20-cve-remediation-guide-github-render-error.md
scope: out-of-scope (allowed)
```

The CVE task's changed bug-spec section was removed after this report. Its worktree is clean.

During independent landing, the dispatcher initially could not create/acquire its landing lock
from the restricted execution context. The same landing command succeeded after requesting the
required elevated filesystem access; no lock or user data was removed.

```text
[codex-dispatch] ERROR: could not remove stale landing lock
```

After pushing commits `2c32ad31` and `802c21c8`, a live GitHub-page fetch was attempted for the
README, Grafana index, and one standalone dashboard page. The browsing service could not retrieve
any of the pages, so rendered-page verification remains pending; both bugs remain OPEN.

```text
Failed to fetch https://github.com/wilddog64/k3d-manager/blob/k3d-manager-v1.43.5/README.md: Cache miss
Failed to fetch https://github.com/wilddog64/k3d-manager/blob/k3d-manager-v1.43.5/docs/guides/grafana-dashboards.md: Cache miss
Failed to fetch https://github.com/wilddog64/k3d-manager/blob/k3d-manager-v1.43.5/docs/guides/grafana-dashboards/k3dm-bugs.md: Cache miss
```

The operator subsequently supplied GitHub-rendered screenshots of the README and Grafana index.
They confirm both intended layouts; the corresponding bugs were updated to LIVE-VERIFIED. The
earlier cache-miss limitation is resolved by this operator-provided browser evidence.

The Grafana status output included:

```text
out-of-scope: docs/guides/grafana-dashboards/argocd-image-updater.md
out-of-scope: docs/guides/grafana-dashboards/checkout-loadtest.md
out-of-scope: docs/guides/grafana-dashboards/cve-autopatch.md
out-of-scope: docs/guides/grafana-dashboards/e2e-verification.md
out-of-scope: docs/guides/grafana-dashboards/hermes-status.md
out-of-scope: docs/guides/grafana-dashboards/k3dm-agent-dispatch.md
out-of-scope: docs/guides/grafana-dashboards/k3dm-alertmanager-delivery.md
out-of-scope: docs/guides/grafana-dashboards/k3dm-bugs.md
out-of-scope: docs/guides/grafana-dashboards/k3dm-deployments.md
out-of-scope: docs/guides/grafana-dashboards/k3dm-host-cni-ipam.md
out-of-scope: docs/guides/grafana-dashboards/k3dm-host-disk.md
out-of-scope: docs/guides/grafana-dashboards/k3dm-pr-checks.md
out-of-scope: docs/guides/grafana-dashboards/k3dm-tests.md
out-of-scope: docs/guides/grafana-dashboards/k3dm-vectordb.md
out-of-scope: docs/guides/grafana-dashboards/shared-operations.md
out-of-scope: docs/guides/grafana-dashboards/trivy-security.md
scope: out-of-scope (allowed)
```

## Root cause

The task agent treated the bug document as an appropriate place to append investigation evidence,
despite the dispatcher's rule that the spec itself is never writable. Separately, the scope
checker treats the listed directory as a literal path rather than a recursive destination.

## Recommended follow-up

Dispatched agents should report investigation findings in their final message unless an explicit
in-scope evidence file is provided. For a future dashboard-guide split, list an explicit glob or
the planned Markdown destinations in `## Files`; if the current task is landed, review every
generated path first and use the documented out-of-scope allowance only if the directory contents
are all intentional.
