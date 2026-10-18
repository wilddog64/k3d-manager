# Bug: k3dm Deployment Metrics dashboard is empty: hub datasource uid missing, CLI runs never publish

**Filed:** 2026-10-18 (Claude, from the operator's screenshot after four `make up` / `make down` runs)
**Status:** LIVE-VERIFIED 2026-10-18 — the operator's real `make up` and `make down` (k3s-aws, KEEP_LOCAL=1) show on the hub dashboard as `up/aws` SUCCESS 12.3 min and `down/aws` SUCCESS 2.12 min; fixed in `47b4903a`, test-leak guard `e37bd31a`
**Fix commit:** `47b4903a`
**Priority:** P2 — lifecycle runs are invisible on the dashboard; the workaround is to read the run logs
**Severity:** medium
**Approval:** approved — operator, 2026-10-18: "go ahead" (to "file it as a bug for v1.43.5 and dispatch it to Codex")
**Branch:** `k3d-manager-v1.43.5`
**Release:** v1.43.5
**Component:** `scripts/etc/grafana/dashboards/k3dm-deployments-configmap.yaml`, `bin/cluster-up`,
`bin/cluster-down`, new `scripts/lib/deployment_metrics.sh`, new `scripts/tests/bin/deployment_metrics.bats`,
`docs/guides/grafana-dashboards.md`
**Related:** `docs/issues/2026-09-17-k3dm-deployment-dashboard-no-data.md` (same "no publisher" finding,
never fixed); `docs/issues/2026-10-08-checkout-and-deployment-dashboard-no-data-triage.md` (suspected the
datasource uid, not confirmed live)

## Symptom

On the hub Grafana, every panel of **k3dm Deployment Metrics** (Last acg-up Duration, Last acg-down
Duration, Last Deployment Success, Last Deployment Time, Deployment Duration Over Time) shows a red
error triangle and "No data". This was after four sandbox `make up` / `make down` runs on 2026-10-17 and
2026-10-18.

## Root cause (two independent defects)

1. **The datasource uid doesn't exist on the hub.** Every target uses
   `"uid": "P5A1115AEDF367D43"`. Claude read the provisioned datasource ConfigMaps on 2026-10-18:
   - **Hostinger** (`monitoring/acg-kube-prometheus-stack-grafana-datasource`) defines `prometheus-acg`
     with that uid.
   - **Hub** (`monitoring/kube-prometheus-stack-grafana-datasource`) defines uids `prometheus`,
     `alertmanager` and `loki`, plus `acg-prometheus` with no pinned uid.

   The same dashboard ConfigMap (`monitoring/k3dm-deployment-metrics`) is on both clusters, so on the
   hub every query errors out. Both clusters do define uid `prometheus`.
2. **CLI lifecycle runs publish nothing.** The only producer of `k3dm_deployment_*` is
   `_push_metrics` in `bin/k3dm-webhook`, which runs only for jobs started through the webhook. Its
   target is `K3DM_PUSHGATEWAY_URL`, default `http://localhost:9091`. A `make up` / `make down` in a
   terminal runs `bin/cluster-up` / `bin/cluster-down` directly, and neither pushes anything. So even
   with the uid fixed, the operator's normal runs leave the dashboard empty.

## Fix

### F1. Dashboard datasource

In `scripts/etc/grafana/dashboards/k3dm-deployments-configmap.yaml`, replace every
`"uid": "P5A1115AEDF367D43"` with `"uid": "prometheus"`. Change nothing else in the dashboard.

### F2. Publisher for CLI runs

New `scripts/lib/deployment_metrics.sh` (k3d-manager-owned; not under `scripts/lib/foundation/`).
It defines `function _k3dm_push_deployment_metrics()` with arguments
`<action> <provider> <status> <duration_secs> <run_id>`. It:

- Builds the same three series, with the same names and label sets, that `_push_metrics` in
  `bin/k3dm-webhook` emits:
  - `k3dm_deployment_duration_seconds{action,provider,status,job_id}`
  - `k3dm_deployment_last_timestamp_seconds{action,provider,status}`
  - `k3dm_deployment_success{action,provider,job_id}`
- PUTs them with `curl --silent --show-error --max-time 5 --data-binary @-` to
  `${K3DM_DEPLOYMENT_PUSHGATEWAY_URL:-http://localhost:19094}/metrics/job/k3dm-cli/instance/<action>-<provider>`.
  This is the hub Pushgateway that `bin/k3dm-disk-metrics` and `bin/dr-drill-publish` already use, so
  the record survives sandbox teardown.
- Is skipped entirely when `K3DM_DEPLOYMENT_METRICS=0` or in dry-run mode (`_dry_guard` semantics,
  `DRY_RUN=1`).
- Always returns 0. On failure it logs one `_warn` line naming the URL and never prints the
  payload.

`<provider>` is the short name the webhook emits (`k3s-aws` → `aws`, `k3s-gcp` → `gcp`, `k3s-azure` →
`azure`; otherwise the value unchanged). `<run_id>` is `cli-<epoch>-<pid>`.

Wire it in:

- **`bin/cluster-up`:** record the start epoch at startup. Add an EXIT hook that runs before the
  existing `_acg_up_cleanup` logic, whatever the exit code. It calls the push with `action=up`, the
  provider, `status` `success` for exit 0 or `failed` otherwise, and the elapsed seconds. It must
  keep the original exit code.
- **`bin/cluster-down`:** the same, with `action=down`.
- A run that exits before the provider is known, such as a usage error, pushes nothing.

Only the CLUSTER_PROVIDER values `bin/cluster-up` / `bin/cluster-down` already handle are in scope.
The webhook path is unchanged.

### F3. Guide

In `docs/guides/grafana-dashboards.md`, under the k3dm Deployment Metrics entry, state:

- CLI runs publish to the hub Pushgateway under `job="k3dm-cli"`.
- Webhook runs keep `job="k3dm-webhook"`.
- `K3DM_DEPLOYMENT_METRICS=0` disables the push.
- The panels query uid `prometheus`.

## Acceptance

```yaml
must:
  - id: M1
    text: Every datasource uid in k3dm-deployments-configmap.yaml is "prometheus"; no target references P5A1115AEDF367D43.
  - id: M2
    text: bin/cluster-up and bin/cluster-down, on exit (success or failure), PUT k3dm_deployment_duration_seconds, k3dm_deployment_last_timestamp_seconds and k3dm_deployment_success with the webhook's label sets to <K3DM_DEPLOYMENT_PUSHGATEWAY_URL>/metrics/job/k3dm-cli/instance/<action>-<provider>.
  - id: M3
    text: status is success and k3dm_deployment_success is 1 when the script exits 0; status is failed and the value is 0 otherwise; duration is the elapsed whole seconds of the run.
  - id: M4
    text: provider is the short name (k3s-aws -> aws, k3s-gcp -> gcp, k3s-azure -> azure).
  - id: M5
    text: The guide paragraph in F3 exists.
must_not:
  - id: N1
    text: A make up / make down run must not finish without pushing deployment metrics (red on pre-fix, which pushes nothing).
  - id: N2
    text: An unreachable or failing Pushgateway must not change the script's exit code or hang longer than about 5 seconds.
  - id: N3
    text: No push happens when K3DM_DEPLOYMENT_METRICS=0 or under DRY_RUN=1.
  - id: N4
    text: The push must not print the metric payload, and the webhook's _push_metrics and its series must not change.
  - id: N5
    text: Tests must not reach the live hub Pushgateway at localhost:19094.
evidence:
  - id: E1
    proves: [M2, M3, M4, N1, N2, N3, N4, N5]
    kind: offline
    text: bats scripts/tests/bin/deployment_metrics.bats with curl stubbed to record its URL, args and stdin; cases for exit 0, exit 1, each provider mapping, an unreachable URL (127.0.0.1:9, exit code preserved, bounded time), K3DM_DEPLOYMENT_METRICS=0 and DRY_RUN=1; N1 red against pre-fix bin/cluster-up / bin/cluster-down (no curl call recorded).
  - id: E2
    proves: [M1, M5]
    kind: offline
    text: a test asserting the dashboard JSON has no P5A1115AEDF367D43 and every target uid is prometheus; make validate-manifests; shellcheck on the touched scripts with no new warnings.
  - id: E3
    proves: [M1, M2, N1]
    kind: live
    text: Claude or the operator runs make up then make down (KEEP_LOCAL=1); on the hub Grafana the k3dm Deployment Metrics panels show the up and down durations of that run with no error triangle.
interface:
  - bin/cluster-up, bin/cluster-down (exit hook)
  - function _k3dm_push_deployment_metrics <action> <provider> <status> <duration_secs> <run_id> in scripts/lib/deployment_metrics.sh
  - env K3DM_DEPLOYMENT_PUSHGATEWAY_URL, K3DM_DEPLOYMENT_METRICS, DRY_RUN
  - dashboard scripts/etc/grafana/dashboards/k3dm-deployments-configmap.yaml
```

## Definition of Done

- [ ] F1–F3 implemented on `k3d-manager-v1.43.5`; only the Component files changed.
- [ ] E1 and E2 pass; N1 shown red against the pre-fix scripts.
- [ ] Commit message: `fix(deployment-metrics): publish CLI lifecycle runs and fix hub datasource uid`
- [ ] Pushed to `origin/k3d-manager-v1.43.5`; report the SHA.

## What NOT to Do

- Do NOT create a PR.
- Do NOT skip pre-commit hooks (`--no-verify`).
- Do NOT modify files outside the Component list, including `bin/k3dm-webhook` and `scripts/lib/foundation/`.
- Do NOT commit to `main`.
- Do NOT push to the live hub Pushgateway from tests.

## Verification (Claude, 2026-10-18)

- `bats scripts/tests/bin/deployment_metrics.bats`: 5/5. `cluster_down_acceptance.bats` 11/11, `cluster_up.bats` 66/66.
- N1 red: Codex ran the N1 case against the pre-fix scripts and recorded no curl call. Claude confirmed independently: `git show 47b4903a^:bin/cluster-{up,down}` contains no push code (0 matches for `deployment_metrics`, `metrics/job` or `k3dm_deployment`).
- Scope: only the six Component files changed; `bin/k3dm-webhook` untouched.
- Deviation, accepted: the push uses POST, not the PUT the Fix text names. `_push_metrics` in
  `bin/k3dm-webhook` also POSTs, and the spec asks for parity with it. POST replaces only the pushed
  series within the `k3dm-cli/<action>-<provider>` group, which is all the dashboard reads.
- Remaining: E3 live, on the operator's next `make up` then `make down KEEP_LOCAL=1`.

## N5 gap and fix (Claude, 2026-10-18)

N5 held only inside `deployment_metrics.bats`. Other suites run the real `bin/cluster-down` or
`bin/cluster-up` with no URL override, and when `curl` resolves to the real binary
(`cluster_down_acceptance.bats` puts `/usr/bin` on PATH) the push reached the live hub. Claude's run
of that suite pushed `down/aws (failed)` and `down/somethingelse (success)`; the operator deleted both
groups.

Fix: `_k3dm_push_deployment_metrics` returns before pushing when `BATS_TEST_FILENAME` is set and
`K3DM_DEPLOYMENT_PUSHGATEWAY_URL` is not, so every suite is covered, including future ones. Suites that
test the push set the URL explicitly and still reach their curl stub.

- New test `N5: under BATS with no explicit URL the publisher never calls curl`: green on the fix, red
  on a pre-fix copy of the library.
- `cluster_down_acceptance.bats` with a recording `curl` stub: 10 `k3dm-cli` push attempts on the
  pre-fix tree, 0 on the fix.
- `cluster_down_acceptance`, `cluster_down`, `cluster_up`, `deployment_metrics`, `hub_pushgateway`:
  123 ok, 0 failures.

## E3 progress (2026-10-18)

The operator's `make up` and `make down CLUSTER_PROVIDER=k3s-aws KEEP_LOCAL=1` (`cloud teardown:
verified`) both reached the hub: the "Deployment Duration Over Time" graph shows `up/aws (success)`
at 12.3 min and `down/aws (success)` at about 2.1 min, with no datasource error. The stat tiles also
showed the leaked test series; that display is fixed separately in
`docs/bugs/2026-10-18-deployment-stat-tiles-cramped-and-show-stale-runs.md`. Marking LIVE-VERIFIED
waits for the tiles after `make platform-ops`.

## Live verification (Claude, from the operator's screenshot, 2026-10-18 ~14:10 PDT)

After `make platform-ops`, the hub's **k3dm Deployment Metrics** tiles read `up/aws` 12.3 mins and
SUCCESS, `down/aws` 2.12 mins and SUCCESS, with no datasource error. Both runs came from the
operator's working tree on `k3d-manager-v1.43.5` after `47b4903a`. The evidence line cites the fix
commit, because the exact HEAD each run used was not recorded.

**Live evidence:** 2026-10-18 · run operator-make-up-then-make-down · env k3d-k3d-cluster · scenario cli-up-down-k3s-aws-keep-local · commit 47b4903a · proves E3
