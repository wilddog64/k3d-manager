# Bug: the release steps leave the Grafana and LDAP rotators on old scripts

**Status:** FIXED
**Priority:** P2
**Severity:** medium — a merged rotator fix stays inert on the hub after the release steps; the Grafana and LDAP rotators ran their pre-fix scripts on 2026-11-01 after `make platform-ops`; workaround is a full `make observability` or LDAP redeploy
**Approval:** operator, 2026-11-01 ("file as you ranked and dispatch to Luna")
**Filed:** 2026-11-01
**Detected by:** Claude, during the live check of `docs/bugs/2026-10-31-rotator-slack-notice-failure-is-silent.md`
**Affected:** `scripts/plugins/argocd.sh` (`deploy_argocd_platform_ops`), `scripts/plugins/observability.sh`, `scripts/plugins/ldap.sh`, `CLAUDE.md` release rules (read-only reference)
**Branch:** `k3d-manager-v1.43.13`
**Related:** `docs/bugs/2026-10-31-rotator-slack-notice-failure-is-silent.md`; `docs/bugs/2026-10-24-prometheus-rotator-never-posts-slack-notice.md`

## Observed failure

On 2026-11-01 the operator ran `make platform-ops` on the M5 hub from `k3d-manager-v1.43.13`. Afterwards the live
`cicd/argocd-credential-rotator` CronJob carried the `a5ffefb0` fix (4 `WARN slack notice` lines), but
`monitoring/grafana-credential-rotator` and `identity/ldap-password-rotator` still had 0. Both had run their monthly
schedule at 00:00 with the pre-fix script, and a manual Grafana job (`grafana-rotator-manual-1101`) showed the old
behaviour.

## Root cause

The rotator CronJobs are applied by three different entry points:

| Rotator | Applied by | Make target |
|---|---|---|
| ArgoCD | `deploy_argocd_platform_ops` | `make platform-ops` |
| Grafana | `_observability_apply_grafana_rotator` inside `deploy_observability` | `make observability` |
| LDAP | `_ldap_deploy_password_rotator` in `_ldap_run_post_deploy` | LDAP deploy |

The release rules in `CLAUDE.md` run the ApplicationSet reapply and `make platform-ops`. Neither reaches the Grafana
or LDAP rotators, and `make observability` is a full stack redeploy that the release does not run.

## Captured hub state (for test stubs)

Read-only, m5-air.local, 2026-11-01T12:20:58Z, `kubectl --context k3d-k3d-cluster`:

    $ kubectl get namespace
    NAME              STATUS   AGE
    cicd              Active   39h
    default           Active   39h
    identity          Active   39h
    istio-system      Active   39h
    kube-node-lease   Active   39h
    kube-public       Active   39h
    kube-system       Active   39h
    monitoring        Active   39h
    platform-ops      Active   39h
    secrets           Active   39h
    staging           Active   39h
    trivy-system      Active   39h
    vectordb          Active   39h

    $ kubectl get cronjob -A | grep -i rotat
    cicd           argocd-credential-rotator    0 0 1 * *      <none>                False     0        12h             39h
    identity       ldap-password-rotator        0 0 1 * *      <none>                False     0        12h             39h
    monitoring     grafana-credential-rotator   0 0 1 * *      <none>                False     0        12h             38h

## Fix

1. `deploy_argocd_platform_ops` also reapplies the Grafana and LDAP rotator CronJobs (and the Vault roles
   their existing apply functions configure), by calling the existing apply functions, not by copying their bodies.
2. Each rotator is reapplied only when its namespace exists on the target cluster: `monitoring` for Grafana, `identity`
   for LDAP. The LDAP rotator also honours `LDAP_ROTATOR_ENABLED` (default 1 in `scripts/etc/ldap/vars.sh`); when it is
   0, log one INFO line and skip it. When a namespace is absent, log one INFO line naming the rotator as skipped and
   continue.
3. Cross-plugin calls are made with the plugin explicitly loaded. If an apply function is still not defined after
   loading, log an ERROR naming it and make `platform-ops` report a problem. It must never silently do nothing (see
   `reference_dispatcher_lazy_load_cross_plugin_calls` in the operator's notes: lazy-loaded cross-plugin calls no-op).
4. `make platform-ops` prints one summary line per rotator: applied, skipped (namespace absent) or failed.
5. Do not run a rotation. Applying a CronJob must not create a Job.

## Files

- `scripts/plugins/argocd.sh`
- `scripts/plugins/observability.sh`
- `scripts/plugins/ldap.sh`
- `scripts/tests/plugins/argocd_platform_ops_rotators.bats`
- `CHANGELOG.md`

## What NOT to do

- Do not touch the Prometheus rotator. It is a LaunchAgent (`_observability_install_prometheus_rotator`) that runs the
  checkout's `k3d-manager`, so it already runs current code (scope correction, 2026-11-01, raised by Luna).
- Do not redeploy the Grafana or Prometheus Helm releases, or the LDAP server, from `platform-ops`.
- Do not create Jobs from the CronJobs.
- Do not edit `CLAUDE.md`; Claude updates the release rule after the fix lands.
- Do not edit `scripts/lib/foundation/`.

## Acceptance

```yaml
must:
  M1: a platform-ops run against a cluster where the monitoring and LDAP namespaces exist applies the Grafana and LDAP rotator CronJob manifests from the checkout, in addition to the ArgoCD rotator
  M2: a rotator whose namespace is absent is skipped with one INFO line naming it, and the run continues to the remaining rotators (paired with M1)
  M3: platform-ops prints one summary line per rotator stating applied, skipped or failed
must_not:
  N1: platform-ops never silently skips a rotator; if an apply function is undefined after loading its plugin, the run logs an ERROR naming it and reports a problem
  N2: platform-ops never creates a Job, never runs helm install or upgrade for Grafana, Prometheus or LDAP, and never deletes a CronJob
evidence:
  E1:
    proves: [M1, M2, M3, N1, N2]
    kind: offline
    intent: >-
      You will see a bats suite run deploy_argocd_platform_ops against a kubectl stub (the fixture first asserts the
      stub is first on PATH and the kubeconfig points at no real cluster) that records every call. With all namespaces
      present, the log shows apply of each rotator manifest; with monitoring absent, the Grafana rotator is skipped with INFO lines and LDAP is still applied. A mutant that leaves an apply function undefined
      makes the run log an ERROR. The call log has no "create job", no helm install or upgrade, and no delete cronjob.
      Stub kubectl output for "get namespace" comes from a real read-only capture on the M5 hub, with host and date in
      a comment.
    what: bats scripts/tests/plugins/argocd_platform_ops_rotators.bats
  E2:
    proves: [M1]
    kind: live
    intent: >-
      You will see, after make platform-ops on the M5 from the release branch, that the live Grafana and LDAP rotator
      CronJobs carry the "WARN slack notice" lines from a5ffefb0, with no new Jobs created by the run.
    what: Claude reads the CronJobs with kubectl get -o yaml after the operator runs make platform-ops
interface:
  - scripts/plugins/argocd.sh deploy_argocd_platform_ops (make platform-ops)
  - scripts/plugins/observability.sh _observability_apply_grafana_rotator
  - scripts/plugins/ldap.sh _ldap_deploy_password_rotator
```

## Resolution

- `3cc9abcf` (Luna; Claude at land): `deploy_argocd_platform_ops` loads the observability and LDAP plugins and reapplies
  the Grafana and LDAP rotator CronJobs when `monitoring` / `identity` exist, honouring `LDAP_ROTATOR_ENABLED`, with one
  applied/skipped/failed line per rotator and a nonzero return on failure. Each apply function runs in a subshell, so
  an `_err` exit inside one is reported as failed and the run continues.
- Luna's first run stopped and reported that the Prometheus rotator is a LaunchAgent, not a CronJob; the spec was
  corrected (Prometheus out of scope) and the session resumed.
- Claude at land: bare `! grep` assertions became `run` + status checks; added a test that the LDAP CronJob renders
  `VAULT_ADDR=http://vault.secrets.svc:8200` (captured from the live M5 CronJob); `e388c471` stubs the new wrapper in
  `argocd_platform_ops_notifications_slack.bats` (landed `--allow-out-of-scope`).
- E1: new suite 7/7; all 7 fail against the pre-fix plugins in a scratch copy. Related suites (notifications Slack,
  bootstrap, `makefile_platform_ops`, `hub_up`, Grafana seed, LDAP rotator) green.
- E2 pending: operator runs `make platform-ops` on the M5 from the release branch; Claude checks the Grafana and LDAP
  CronJobs carry the `WARN slack notice` lines and that no Job was created.
