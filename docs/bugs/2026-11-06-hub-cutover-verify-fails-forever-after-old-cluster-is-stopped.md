# Bug: `make hub-cutover-forwards` can never pass once the old hub's cluster is stopped

**Status:** LANDED `03f40c0a`, VERIFIED: offline verification recorded 2026-11-06 (independent 20/20; 7 red pre-fix) and live E2 passed on the M5 2026-11-06.
**Priority:** P2
**Severity:** medium. The tunnel fix `8e5f8831` cannot be rolled out, so the M4's dispatch and test metrics and shipped logs stay off the M5. Worse, after three minutes the failure tells the operator to run `make hub-cutover-rollback` against a healthy hub.
**Approval:** Filing: Claude, 2026-11-06, told the operator when reporting the failed rollout. Dispatch: operator, 2026-11-06 ("please dispatch P2 and P3 to Luna").
**Filed:** 2026-11-06
**Detected by:** Operator, running the tunnel fix rollout on the M5, 2026-11-06
**Affected:** `bin/hub-cutover` (`verify_cutover`)
**Branch:** `k3d-manager-v1.43.14`
**Related:** `docs/bugs/2026-11-06-hub-forward-tunnels-lose-auth-after-old-hub-reboot.md` (the rollout this blocks); `docs/bugs/2026-11-06-hub-cutover-verify-ignores-old-host-in-report.md`

## Observed failure

On the M5, 2026-11-06 06:04 PST, `make hub-cutover-forwards HUB_OLD_HOST=m4-air.local`:

- `The connection to the server 127.0.0.1:55730 was refused`, then `hub-cutover: verify attempt 1/18 failed; retrying in 10s`.
- The M5's own API is `127.0.0.1:53245` and healthy: nodes Ready, `argocd.3ai-talk.org` and `frontend.3ai-talk.org` return 200.

## Root cause

`verify_cutover` requires the old hub's controller to read 0 replicas, through `remote_kubectl`:

`[[ "$(remote_kubectl get "$CONTROLLER" -o 'jsonpath={.spec.replicas}')" == 0 ]] || return 1`

That needs the old cluster's API. Captured over ssh from the M5 to `m4-air.local`, 2026-11-06 06:05 PST:

- `kubectl --context k3d-k3d-cluster -n cicd get deploy` rc 1; the context's server is `https://127.0.0.1:55730`, with no listener.
- `docker ps -q --filter name=k3d-k3d-cluster-server --filter status=running` prints nothing, rc 0.
- `docker ps -a --format '{{.Names}} {{.State}}' --filter name=k3d-k3d-cluster-server` prints `k3d-k3d-cluster-serverlb exited` and `k3d-k3d-cluster-server-0 exited`.

The check exists to prove the old controller cannot act. A stopped cluster proves that more strongly, and it is the normal state after a cutover, but the check reads it as failure. `make hub-cutover-forwards` depends on `hub-cutover-verify`, and the report guard refuses `verify-failed`, so the forwards step is unreachable. The earlier `forwards-pass` on 2026-10-31 ran while that cluster was still up.

## Fix

In `bin/hub-cutover`, replace that one line with a helper used by `verify_cutover`:

1. If `remote_kubectl get "$CONTROLLER"` succeeds, its value must be 0, as today. A non-zero replica count fails, whatever the containers report.
2. If it fails, ask the old host through `old_ssh`, with the same PATH prefix `remote_kubectl` uses: `docker ps -a` and `docker ps` with `--filter "name=^${CONTEXT}-"` and `--filter status=running`. Pass only when both docker commands succeed, at least one container of that cluster exists, and none is running. Print `hub-cutover: old cluster on <host> is stopped; old controller cannot act`.
3. Every other case fails: ssh fails, docker fails or is absent, no such container exists, or a container is running while the API refuses. Fail closed: a running cluster with an unreachable API is not proof of anything.

`--rollback`, the cutover path and the `forwards` guard are unchanged. Do not start the old cluster, and do not edit the report by hand.

## Files

- `bin/hub-cutover`
- `scripts/tests/bin/hub_cutover.bats`

## Acceptance

```yaml
must:
  - id: M1
    text: "With the old API refusing connections and every old cluster container exited, make hub-cutover-verify's check passes and bin/hub-cutover --verify records pass."
  - id: M2
    text: "With the old API reachable and 0 replicas, verify still passes (no container check needed)."
  - id: M3
    text: "After M1, bin/hub-cutover --forwards is allowed to run."
must_not:
  - id: N1
    text: "With the old API reachable and replicas above 0, verify does not pass, even if the container check would say stopped."
  - id: N2
    text: "With the old API refusing and any old cluster container running, verify does not pass."
  - id: N3
    text: "With the old API refusing and no container of that cluster found, verify does not pass (a wrong context name cannot read as stopped)."
  - id: N4
    text: "With the old API refusing and docker failing or absent on the old host, verify does not pass."
  - id: N5
    text: "Verify starts, stops or scales nothing on the old host: no docker start, k3d or kubectl scale call."
evidence:
  - {id: E1, proves: [M1, M2, M3, N1, N2, N3, N4, N5], kind: offline, text: "BATS with HOME in BATS_TEST_TMPDIR (asserted first) and ssh, kubectl and docker stubs logging every call. Stub output taken from the captures above, with host and date in a comment. M1 red on the pre-fix commit; each must_not red by a mutant."}
  - {id: E2, proves: [M1, M3], kind: live, text: "Operator on the M5: make hub-cutover-forwards HUB_OLD_HOST=m4-air.local passes; then the tunnel fix's live E3 runs."}
interface:
  - "bin/hub-cutover [--verify|--forwards]"
  - "env: HOME, HUB_OLD_HOST, HUB_CUTOVER_STATE_DIR, HUB_CUTOVER_CONTEXT, PATH (ssh, kubectl, docker, make, curl, cloudflared, launchctl, jq stubs)"
```

## Live E2, 2026-11-06, M5

`make hub-cutover-forwards` run by the operator with the M4 cluster stopped. Printed `old cluster on m4-air.local is stopped; old controller cannot act`. Report rows: `pass` 14:54:12Z, `forwards-pass` 14:54:26Z. The same run printed `unknown` from Hermes and an untested webhook health, which it should not have accepted; filed as `docs/bugs/2026-11-06-hub-cutover-verify-accepts-hermes-unknown.md`.
