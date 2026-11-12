# GCP provider 4/4 — status, refresh, restart and teardown for k3s-gcp; remove the dead GCP code

**Status:** PLANNED — ordered backlog (unnumbered); fourth of the four GCP provider plans
**Approval:** operator, 2026-11-12 ("let's get GCP provider plans into roadmap")
**Intent approved:** pending
**Branch:** unassigned (release chosen at grooming)
**Depends on:** `docs/plans/gcp-cluster-up-full-pipeline.md`
**Related:** Fable and Argon GCP reviews 2026-11-12

## Goal

Once a GCP cluster is up, `make status`, `make refresh`, ACG restart and `make down` treat it the way they treat
k3s-aws, and nothing GCP-shaped is left behind after teardown.

## Gaps today

- `bin/cluster-status:94-103,106,419` checks `localhost:16443` and skips cloud probes for k3s-gcp.
- `acg_restart` accepts `gcp` but then calls the AWS `acg_get_credentials` and `_acg_check_credentials`
  (`acg.sh:679-680`); `acg_watch` checks an AWS instance id (`acg.sh:775`); `acg-credential-test` has no GCP block.
- `_provider_k3s_gcp_destroy_cluster` (`k3s-gcp.sh:244-312`) does not stop the tunnel, deregister the ArgoCD cluster,
  delete `~/.kube/k3s-gcp.yaml` or verify the VM is gone; `bin/cleanup-stale-sandbox` ignores GCP.
- Dead code: `scripts/playwright/gcp_login.js` (pre-subtree copy; `gcp.bats:209` syntax-checks it instead of the
  live one), `_gcp_capture_auth_url` (`gcp.sh:145-165`), `scripts/etc/playwright/vars.sh` (duplicate of the
  foundation file). `gcp_revoke` (`gcp.sh:247-271`) is unused: with plan 1's per-process auth there may be nothing to
  revoke; delete it or wire it into teardown, decided at spec time.

## Files

lib-foundation first (`scripts/lib/acg/acg.sh`, `gcp.sh`, `bin/acg-credential-test`), then a subtree pull;
k3d-manager `bin/cluster-status`, `bin/cluster-down`, `bin/cleanup-stale-sandbox`, `scripts/lib/providers/k3s-gcp.sh`,
the dead files above, `scripts/tests/plugins/gcp.bats`.

## Live evidence (when specced)

`make status`, `make refresh` and `make down CLUSTER_PROVIDER=k3s-gcp` leaving 0 GCE VMs in the project, no tunnel
process, and no `ubuntu-gcp` cluster in ArgoCD.
