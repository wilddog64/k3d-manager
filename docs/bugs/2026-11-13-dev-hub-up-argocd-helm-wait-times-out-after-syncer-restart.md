# dev-hub: `dev-hub-up` Argo CD `helm --wait` times out when the vCluster syncer restarts during startup

**Status:** VERIFIED — f1eeeb26 live on the M5 2026-11-13 (operator): stuck pending-install argocd uninstalled, argocd and Grafana installed, no down in between
**Priority:** P1 (Claude proposal, raised 2026-11-13: a rerun cannot recover, and the only way back is down/up, which can hit the same timeout; blocks the plan E2 live check)
**Classified:** pending (Argon, from this doc alone)
**Introduced by:** b2067ad3 or later Part B commit that added the Argo CD install with `--wait` and no `--timeout` (unknown which)
**Should have been caught by:** live check (offline tests cannot see startup timing)
**Prior art:** exact-slug glob, no match; `make find-similar-docs` not run (vector store context missing on m4-air)
**Approval:** operator, 2026-11-13: "go ahead"
**Dispatch go:** operator, 2026-11-13: "go ahead"
**Intent approved:** operator, 2026-11-13

## Symptom

m5-air, 2026-11-13, second `make dev-hub-down` then `make dev-hub-up` (5c253d1b promoted):

    context deadline exceeded
    helm command failed (1): helm --kubeconfig ~/.kube/vclusters/dev-hub.yaml upgrade --install argocd argo/argo-cd -n cicd --create-namespace --version 10.10.5 -f scripts/etc/dev-hub/argocd-values.yaml --wait
    make: *** [dev-hub-up] Error 1

Grafana was never installed, because the run stopped first. About 4 minutes later:
- All 7 host pods in namespace `dev-hub` were Running and 1/1.
- The quota was not near its cap: 2304Mi of 3Gi in memory limits.
- No image pulls happened: every image was "already present on machine".

## What the events show

- `dev-hub-0` failed its `/readyz` readiness probe several times, then restarted its `syncer` container once, about 40 s after its first start.
- During that window, `argocd-server` and `application-controller` probes got connection refused.
- `argocd-applicationset-controller` restarted twice and went into `BackOff`. Its last start came about 4.5 minutes after the pod was created, just about when Helm's 5-minute default timeout ran out.

## Likely cause (not yet proven)

1. The vCluster API restarted while Argo CD was starting.
2. `applicationset-controller` exits when its API is unreachable and lands in CrashLoopBackOff, whose back-off delay doubles each time.
3. `--wait` without `--timeout` gives up after Helm's 5-minute default.

The first run on 2026-11-13 succeeded only because the syncer did not restart that time. To prove it: `kubectl --context k3d-k3d-cluster -n dev-hub logs <applicationset pod> --previous` at the next recurrence.

Separately, after the failure `~/.kube/vclusters/dev-hub.yaml` points to 127.0.0.1:11444 and the connection is refused, because the connect proxy is gone. `dev-hub-up` and its readiness wait refresh the connection (`_vcluster_refresh_connection`), so a rerun recovers it.

## Workaround

**Rerunning does NOT work.** Claude first wrote here that a rerun recovers; that was wrong and was never checked. The operator's rerun on m5-air, 2026-11-13:

    Error: UPGRADE FAILED: another operation (install/upgrade/rollback) is in progress
    helm command failed (1): helm --kubeconfig ~/.kube/vclusters/dev-hub.yaml upgrade --install argocd argo/argo-cd ... --wait

The timed-out install left the `argocd` release in a pending state, and Helm refuses every later operation on it. The only way back is `make dev-hub-down`, which deletes the vCluster together with its Helm release Secrets, followed by `make dev-hub-up`. That can time out again in the same way.

## Fix options (for triage)

The fix needs all three:
1. **Recover a stuck release before installing.** If `helm status` reports `pending-install`, `pending-upgrade` or `pending-rollback`, roll the release back, or uninstall it if it has no deployed revision. Then `dev-hub-up` can be rerun.
2. **Do not leave a pending release behind.** Use the deployed Helm's own failure rollback, `--rollback-on-failure` in Helm 4 (the old `--atomic`), so a timeout cleans up after itself. This has to be proven against the Helm version on the M5 before dispatch.
3. **Give startup time.** Set an explicit `--timeout`, for example 10m, on both chart installs. Optionally, wait for the vCluster to settle first.

Evidence to capture before the spec, read-only on the M5: `helm version --short`; `helm --kubeconfig ~/.kube/vclusters/dev-hub.yaml -n cicd history argocd`; the `applicationset-controller` previous-container log.

## Evidence (m5-air, 2026-11-13, operator, read-only)

- `helm version --short`: `v4.3.1+gc0d08d0`. The m4-air has the same version.
- `helm -n cicd history argocd`: revision 1, `pending-install`, "Initial install underway", 14:52:22 PST. The release was never marked `failed`, so the fix must handle a pending release with no deployed revision, which means uninstalling it.
- `applicationset-controller --previous` log, 22:55:43Z to 22:57:04Z: it repeats `failed to get restmapping: no matches for kind "ApplicationSet" in version "argoproj.io/v1alpha1"` every 10 s, then gets `timed out waiting for cache to be synced`, and the manager exits. **This corrects "Likely cause" above.** The controller did not crash because the API was unreachable. For about 3 to 5 minutes after the install began, the vCluster API was not serving the ApplicationSet CRD that the same Helm release had created. Together with the `dev-hub-0` `/readyz` timeouts and its container restart, this points to a starved control plane: `values-dev-hub.yaml` caps it at 500m CPU and 768Mi memory. Whether the restart was an OOMKill or a failed probe is still to be confirmed.
- Helm v4.3.1 upstream source (`pkg/cmd/install.go:204-206`, `pkg/action/install.go:592-605`): `--rollback-on-failure` exists, and `--atomic` is a deprecated alias for it. On install failure, `failRelease` uninstalls the release without keeping its history, so a timed-out install leaves nothing locked. Read via `gh api repos/helm/helm/contents/...?ref=v4.3.1` on 2026-11-13.

- `syncer --previous` log on `dev-hub-0`, last terminated reason `Error`, exit 1, not OOMKilled: at 22:52:51Z, 29 s after Helm began, `leaderelection lost ... context deadline exceeded`, then `error running controller-manager: error running command /binaries/kube-controller-manager: exit status 1`. **Root cause:** under the Argo CD install load, the embedded kube-controller-manager missed its lease renew deadline. That brought down the whole vCluster process, and the Argo CD controllers started against a control plane that was restarting.

## Proof of external behaviour (vCluster v0.32.1, read 2026-11-13 on m4-air via `gh api repos/loft-sh/vcluster/contents/...?ref=v0.32.1`)

- `pkg/k8s/k8s.go:160` always appends `--leader-elect=true` to kube-controller-manager. At `k8s.go:200-205`, `MergeArgs(args, controllerManager.ExtraArgs)` runs, and if controller-manager exits it calls `osutil.Exit(1)`, taking the whole control plane down.
- `pkg/util/command/command.go:23-34`, `MergeArgs`: a base flag is dropped when ExtraArgs carries the same `--flag` name. So `--leader-elect=false` in ExtraArgs replaces the default.
- `config/config.go:898-906`: `Distro()` returns k8s when no distro is enabled, so `controlPlane.distro.k8s.controllerManager.extraArgs` applies to our deployment even though `k8s.enabled` is false. `chart/values.yaml:236-269` shows that path.
- The control plane runs one replica (`controlPlane.statefulSet.highAvailability.replicas: 1`), so with leader election there is nothing to elect between. All it adds is a lease that can be missed.
- Helm v4.3.1: see the Evidence bullet above for `--rollback-on-failure`.

## Proposed fix

1. **No leader election in the dev hub control plane.** Add `controlPlane.distro.k8s.controllerManager.extraArgs: ["--leader-elect=false"]` to `scripts/etc/vcluster/values-dev-hub.yaml`. Change nothing else in that file. The CPU and memory limits stay as they are; raising them is a separate decision, made only if E2 still shows starvation.
2. **Unlock a stuck release before each chart install.** Before `upgrade --install argocd` and before `upgrade --install dev-hub-grafana`, read the release status in the child cluster.
   - `pending-install`: run `helm uninstall <release> -n <ns>`.
   - `pending-upgrade` or `pending-rollback`: run `helm rollback <release> -n <ns>`.
   - Absent, `deployed` or `failed`: do nothing.
   If the uninstall or rollback fails, `dev_hub_up` fails with a message naming the release.
3. **Fail without leaving a lock.** Both chart installs get `--rollback-on-failure --timeout 10m` in addition to `--wait`, with the timeout set by a `DEV_HUB_HELM_TIMEOUT` variable that defaults to `10m`.

## Acceptance

```yaml
must:
  - id: M1
    text: values-dev-hub.yaml sets controlPlane.distro.k8s.controllerManager.extraArgs to exactly ["--leader-elect=false"]; every other key in the file is unchanged
  - id: M2
    text: both helm upgrade --install calls (argocd, dev-hub-grafana) carry --wait, --rollback-on-failure and --timeout 10m
  - id: M3
    text: when the child release status is pending-install, dev_hub_up runs helm uninstall <release> -n <ns> before that release's upgrade --install (order asserted in the call log)
  - id: M4
    text: when the child release status is pending-upgrade or pending-rollback, dev_hub_up runs helm rollback <release> -n <ns> before that release's upgrade --install
must_not:
  - id: N1
    text: values-dev-hub.yaml leaves kube-controller-manager leader election at the vCluster default (red on pre-fix)
  - id: N2
    text: a chart install runs without --rollback-on-failure or without an explicit --timeout (red on pre-fix)
  - id: N3
    text: dev_hub_up uninstalls or rolls back a release whose status is absent, deployed or failed (paired with M3/M4 as positive controls)
  - id: N4
    text: dev_hub_up continues to upgrade --install after an uninstall or rollback of a pending release fails
evidence:
  - id: E1
    proves: [M1, M2, M3, M4, N1, N2, N3, N4]
    kind: offline
    intent: dev-hub-up turns off the vCluster's leader election that crashed it, gives each chart install ten minutes and a clean undo on failure, and unlocks a release a timed-out run left stuck, while never touching a healthy release.
    command: bats scripts/tests/plugins/dev_hub.bats (new M1/N1, M2/N2, M3, M4 tests red on beda86c1)
  - id: E2
    proves: [M1, M2]
    kind: live
    intent: After a promote, on the M5 the stuck argocd release is cleared by make dev-hub-up without a down, Argo CD and Grafana install in one run, the dev-hub-0 container does not restart during the install, and a following make dev-hub-down and make dev-hub-up also finish in one run.
interface: scripts/etc/vcluster/values-dev-hub.yaml; scripts/plugins/dev_hub.sh _dev_hub_install_charts
```

## Contract readers

- `scripts/etc/vcluster/values-dev-hub.yaml` — reader: `scripts/plugins/dev_hub.sh:25` exports it as `VCLUSTER_VALUES_FILE` for `vcluster_create`; the new key is passed through unchanged. Readers in tests: `scripts/tests/plugins/dev_hub.bats:479-481` and `:505-507` (grep scans, unaffected); `:514-525` M1 CoreDNS (unaffected); `:531-560` root-key allow-list (`controlPlane` is allowed, so unaffected); **`:562+` "N2 values-dev-hub changes only by moving coredns" compares the whole file, so the writer must add the new `distro` key to its expected YAML.**
- Helm install argv — readers in tests: `dev_hub.bats:257` (grep -F, unaffected) and **`:259` and `:930`, which anchor `--wait$`; the writer must update those regexes.** The bats helm stub at `:149-151` keys on the last call-log line; the writer adds `status`/`uninstall`/`rollback` cases.
- Writers: only `dev_hub.sh _dev_hub_install_charts`. No other code writes either contract.

## Files

- `scripts/etc/vcluster/values-dev-hub.yaml`
- `scripts/plugins/dev_hub.sh`
- `scripts/tests/plugins/dev_hub.bats`

## Definition of done (worker)

- `bats scripts/tests/plugins/dev_hub.bats`: all ok, pasted with its summary line.
- Pre-fix control: with `values-dev-hub.yaml` and `dev_hub.sh` restored to beda86c1 and the new tests kept, the M1/N1, M2/N2, M3 and M4 tests are not ok. Paste both runs.
- `shellcheck scripts/plugins/dev_hub.sh`: clean.
- Do not commit; leave changes in the worktree.

## Spec amendment after Fable review (2026-11-13, before landing; supersedes the conflicting lines above)

Fable read the vCluster v0.32.1 and Helm v4.3.1 upstream source; Claude re-checked findings 1 and 3 itself (`dev_hub.sh:207-222`; Helm `pkg/action/uninstall.go:164-212`).

1. **Values reach only a new vCluster.** `dev_hub_up` calls `vcluster_create` only when the cluster is absent (`dev_hub.sh:207-209`), and the existing-cluster branch (`:218-221`) applies no values. Fix 1 therefore takes effect only after `make dev-hub-down` then `make dev-hub-up`. No code change for this; E2 is reworded below.
2. **`--rollback-on-failure` is best-effort.** Its uninstall reads release history first (`uninstall.go:164`). If the vCluster API is unreachable at that moment, the release stays pending. Fix 3 is a mitigation; fix 2, the pre-install unlock, is the guaranteed recovery.
3. **`uninstalling` is also a stuck state.** Uninstall saves `uninstalling` before deleting (`uninstall.go:196,212`). `upgrade --install` neither installs nor upgrades such a release. Fix 2 adds: `uninstalling` → `helm uninstall <release> -n <ns>`.
4. **Status probe, exact command:** use `helm history <release> -n <ns> --max 1 -o json`. It reads only Helm's release storage; `helm status` also fetches the release's resources. Call it through `_run_command --soft --quiet`. Outcomes:
   - "release: not found", or an empty list: treat as absent and do nothing.
   - Any other non-zero exit: fail, naming the release.
   - Otherwise take `.[0].status`.
   The bats stub's output must match `helm history -o json` from Helm v4.3.1 (`pkg/cmd/history.go`, `releaseHistory` fields `revision`, `updated`, `status`, `chart`, `app_version`, `description`). Cite that source in a comment; Claude captures a real M5 sample at live check.
5. **Rollback target:**
   - `pending-upgrade` or `pending-rollback`: roll back to the newest revision whose status is `deployed` or `superseded`, read from `helm history <release> -n <ns> -o json`.
   - If no such revision exists: uninstall instead.
   A bare `helm rollback` targets revision N-1, which may be the failed one (`rollback.go:140-142`).
6. **Any other status not listed** (`absent`, `deployed`, `failed`, `superseded`, `uninstalled`, and the five handled pending/uninstalling cases) fails `dev_hub_up` loudly, naming the release and the status.

### Acceptance changes

- **M3** now also covers `uninstalling` → uninstall.
- **M4** reads "rolls back to the newest deployed or superseded revision (`helm rollback <release> <rev> -n <ns>`), or uninstalls when none exists."
- **New M5:** `DEV_HUB_HELM_TIMEOUT=3m` changes both `--timeout` values to `3m`.
- **New N5:** an unrecognised status, or a non-not-found history error, leads to a chart install anyway.
- **N4 and N5** join the DoD's list of tests that must fail on pre-fix code. N3 is a positive control and cannot fail pre-fix.
- **E2 (live), reworded:**
  1. After the promote, `make dev-hub-up` with no down clears the stuck `argocd` release and installs Argo CD and Grafana (proves M2, M3).
  2. Then `make dev-hub-down` and `make dev-hub-up` finish in one run.
  3. On that second run, the `dev-hub-0` syncer log line `Starting controller-manager` shows `--leader-elect=false`, and the container does not restart during the install (proves M1).
  A failing install can now take about 20 minutes: a 10m wait plus a 10m rollback.

## Live verification (operator, 2026-11-13, m5-air.local)

Hub checkout at ce164bf2 (contains f1eeeb26). The first `make dev-hub-up`, run before the checkout synced, used the old
code and failed with `UPGRADE FAILED: another operation (install/upgrade/rollback) is in progress`. After the sync, with
no `dev-hub-down` in between, `make dev-hub-up` printed `release "argocd" uninstalled`, then installed argocd
(`STATUS: deployed`, 18:06:41) and dev-hub-grafana (`STATUS: deployed`, 18:07:07) with no error. The pending-install
recovery path is proven on the real stuck release. The rollback path (pending-upgrade) is proven offline only.
