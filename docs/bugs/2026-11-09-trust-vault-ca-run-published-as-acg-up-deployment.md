# Bug: a `--trust-vault-ca` run is published as a 2-second successful acg-up deployment

**Status:** OPEN — filed 2026-11-09; dispatched to Luna 2026-11-09 (slug `trust-vault-ca-no-deploy-metric`)
**Priority:** P3
**Waiting on:** fix running — since 2026-11-09
**Introduced by:** `401e4eca` (v1.43.5, the EXIT-trap push from
`docs/bugs/2026-10-18-deployment-dashboard-empty-for-cli-lifecycle-runs.md`) combined with the `--trust-vault-ca`
early exit; the webhook route that runs it unattended came in `ecae8a73` (v1.43.14)
**Should have been caught by:** spec (the 2026-10-18 spec listed DRY_RUN and `K3DM_DEPLOYMENT_METRICS=0` as no-push
cases but not the non-deploying `--trust-vault-ca` mode)
**Prior art:** `docs/bugs/2026-10-18-deployment-dashboard-empty-for-cli-lifecycle-runs.md` (grep, not scored) — read,
introduced the push, different defect. `docs/bugs/2026-11-07-webhook-cluster-trust-vault-ca-action-needs-only-reader.md`
— read, its Severity line already notes the action "pushes a deployment metric"; authorization defect, different root
cause. `make find-similar-docs` unavailable (vector store unreachable from the M4, 2026-11-09).
**Severity:** low — no outage. The k3dm Deployment Metrics dashboard reports a CA-trust run as the last AWS deployment
(2 s, SUCCESS), and the run resets `DeploymentMetricsStale`, hiding a real gap in deployments.
**Approval:** operator, 2026-11-09
**Intent approved:** operator, 2026-11-09
**Intent approval words:** "E1, E2, and E3 approved and dispatch if allowed"
**Dispatch:** operator go 2026-11-09, conditional on the WIP limit; started after gate-guard landed freed a slot, `--agent codex --model gpt-6-luna`
**Filed:** 2026-11-09
**Detected by:** operator, 2026-11-09, k3dm Deployment Metrics screenshot ("why AWS (acg-up) Duration is 2s? … it is
weird"); Claude traced it
**Branch:** `k3d-manager-v1.43.15`
**Release:** P3 batch; groom at the next `/release-groom`

## Symptom

Pushgateway (read-only, `curl localhost:19094/metrics`, from the M4, 2026-11-09):

    k3dm_deployment_duration_seconds{action="up",instance="up-aws",job="k3dm-cli",job_id="cli-1794099733-79993",provider="aws",status="success"} 2
    k3dm_deployment_last_timestamp_seconds{action="up",instance="up-aws",job="k3dm-cli",provider="aws",status="success"} 1.794099735e+09
    k3dm_deployment_success{action="up",instance="up-aws",job="k3dm-cli",job_id="cli-1794099733-79993",provider="aws"} 1

`1794099733` is 2026-11-07 17:02:13 PST. The "Last acg-up Duration" stat shows `aws 2 s`; "Deployment Duration Over
Time" is a flat 2 s line, because Pushgateway keeps the last push and Prometheus re-scrapes the same sample. A real
`make up` on k3s-aws takes about 12 minutes (12.3 min on 2026-10-18).

## Root cause

`bin/cluster-up:344` installs `trap _acg_up_cleanup EXIT`. `_acg_up_cleanup` (`bin/cluster-up:288-296`) pushes
`action=up` with the exit status and the elapsed time for **every** exit. Argument parsing runs after the trap:
`--trust-vault-ca` (`bin/cluster-up:459`) runs `_acg_export_and_trust_vault_ca` and exits at `bin/cluster-up:463-466`
after about 2 s, so a CA-trust run is published as a successful `up`. `job="k3dm-cli"` and `job_id="cli-<epoch>-<pid>"`
show the push came from this trap. It is reached from `make trust-vault-ca` (`Makefile:88-89`) and from the webhook
action `trust-vault-ca` (`scripts/lib/webhook/lifecycle.py:361-362`). Which caller ran at 17:02 on 2026-11-07 is
unknown (the M4 webhook log ends 2026-11-06; the hub log was not read). The 2026-11-07 date matches the live work on
the trust-vault-ca action bug.

The webhook also calls `_push_metrics(action, …)` after the job (`scripts/lib/webhook/lifecycle.py:357-358`,
`bin/k3dm-webhook:1765`) with `action="up"` for this action, so the webhook path is a second producer of the same
false sample.

`DRY_RUN` is not a cause: `scripts/lib/deployment_metrics.sh:10` returns before pushing.

### Not a defect: "Last acg-down Duration" shows No data

Pushgateway holds no `down` group. The last recorded `down/aws` was on 2026-10-18; the series did not survive the hub
cutover, and no `make down` has run since. A sandbox that expires on its own runs no `cluster-down`, so nothing is
pushed. Operator's reading (2026-11-09) is correct. No change.

## Fix

1. `bin/cluster-up`: the `--trust-vault-ca` branch publishes no deployment metric (for example
   `K3DM_DEPLOYMENT_METRICS=0` for that branch, or a flag `_acg_up_cleanup` checks). Normal `up` runs, success and
   failure, still push as today.
2. `scripts/lib/webhook/lifecycle.py`: skip `_push_metrics` when `trust_vault_ca` is set.
3. The existing false sample stays in Pushgateway until the next real `make up` overwrites the `up-aws` group, or the
   operator deletes it (`DELETE /metrics/job/k3dm-cli/instance/up-aws`). That delete is a hub mutation: operator
   decision, not part of the dispatch.

## Files

| File | Change |
|---|---|
| `bin/cluster-up` | no push from the `--trust-vault-ca` branch |
| `scripts/lib/webhook/lifecycle.py` | no `_push_metrics` for a trust-vault-ca job |
| `scripts/tests/bin/deployment_metrics.bats` | cases for the trust-only path (no push) and a normal run (push) |
| `scripts/tests/bin/webhook_lifecycle.py` | case: trust-vault-ca job calls no `_push_metrics`; plain up still does |

## Contract readers

| Reader | Changes? |
|---|---|
| `scripts/etc/grafana/dashboards/k3dm-deployments-configmap.yaml:37,61,86,106,127` | No: they stop seeing false `up` samples |
| `scripts/etc/prometheus/rules-acg/k3dm-tests.yaml:67` (`DeploymentMetricsStale`) | No: a CA-trust run no longer resets it |
| `scripts/lib/deployment_metrics.sh` (push helper) | No |
| `bin/cluster-down:82-85` (same pattern for down) | No: has no non-deploying mode |
| `Makefile:88-89` `trust-vault-ca` | No: same command, no metric |

## Acceptance

```yaml
must:
  - id: M1
    text: "A normal cluster-up run still publishes action=up with its status and duration, on success and on failure."
must_not:
  - id: N1
    text: "A cluster-up --trust-vault-ca run never publishes a deployment metric, whether it succeeds or fails."
  - id: N2
    text: "A webhook trust-vault-ca job never calls the webhook's deployment metric push."
evidence:
  - {id: E1, proves: [M1, N1], kind: offline, intent: "With the Pushgateway call stubbed, a trust-only run sends nothing and a normal run still sends its up metric; the trust-only test fails on today's code."}
  - {id: E2, proves: [N2], kind: offline, intent: "The webhook lifecycle test shows a trust-vault-ca job makes no metric push, while a plain up job still does."}
  - {id: E3, proves: [N1], kind: live, intent: "After the fix lands and is promoted, you run make trust-vault-ca on the hub and the Deployment dashboard's acg-up panels do not change."}
interface:
  - "bin/cluster-up --trust-vault-ca (curl/Pushgateway stubbed via K3DM_DEPLOYMENT_PUSHGATEWAY_URL)"
  - "scripts/lib/webhook/lifecycle.py _run_cluster(job_id, 'up', trust_vault_ca=True)"
```
