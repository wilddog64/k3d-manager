# Bug: `acg-up` on the M4 dev node restarts the retired local hub instead of refusing

**Status:** OPEN
**Priority:** P2
**Severity:** medium — running `bin/acg-up` / `make up` from the M4 (where Claude and dispatches run) would start a second hub: a second ArgoCD that registers the sandbox, port-forward plists and CronJobs that push to the same Pushgateway names; the workaround is to run it on the M5
**Approval:** operator, 2026-11-01 (asked "does it matter from m4 or m5?" while scheduling acg-up; hub-migration gaps are filed as found)
**Filed:** 2026-11-01
**Detected by:** Claude, reading `bin/cluster-up` before the session's acg-up
**Affected:** `bin/cluster-up` (hub bootstrap, lines ~528-545: `k3d cluster list` → `deploy_cluster --provider k3d` or `k3d cluster start`)
**Branch:** `k3d-manager-v1.43.14`
**Related:** `docs/plans/v1.43.14-control-node-role.md` (machine roles); `docs/plans/v1.43.12-m5-new-hub-one-command.md` (cutover); `memory: project_m5_air_new_hub`

## Observed state

On the M4, 2026-11-01 06:48 PST (read-only):

- `docker ps -a`: `k3d-k3d-cluster-server-0`, `-agent-0..2`, `-serverlb` all `Exited` ~25 hours (the pre-cutover hub).
- `kubectl --context k3d-k3d-cluster get ...`: `dial tcp 127.0.0.1:55730: connect: connection refused`.

## Root cause

`bin/cluster-up` treats "a k3d cluster named `k3d-cluster` exists locally" as "this machine is the hub". If the cluster
exists but the API is unreachable, it runs `k3d cluster start`; if none exists, it creates one. Since the 2026-10-31
cutover the hub is the M5, and the M4 still holds the stopped containers, so an `acg-up` from the M4 revives the
retired hub. Nothing records which machine is the hub, so the script cannot tell.

## Fix

1. Record the role: `bin/k3dm-machine-setup` writes the role it ran with to
   `${XDG_CONFIG_HOME:-$HOME/.config}/k3d-manager/machine-role` (one word: `hub`, `worker`, `console`, `control`).
2. `bin/cluster-up` (and `make up CLUSTER_PROVIDER=k3d` / `hub-up` through it) refuses to create or start the local
   hub unless that file says `hub`, or `K3DM_ALLOW_LOCAL_HUB=1` is set. The error names the file, the role found
   (or "missing"), and says to run acg-up on the hub machine. It exits non-zero before any `k3d`, `kubectl` or AWS call.
3. A missing file on the real hub must not strand the operator: the message gives the one-line fix
   (`make machine-setup ROLE=hub` or the override).
4. Docs: `docs/howto/machine-setup.md` names the file; the acg how-to says acg-up runs on the hub.

## Files

- `bin/cluster-up`
- `bin/k3dm-machine-setup`
- `scripts/tests/bin/` (new or existing cluster-up / machine-setup BATS)
- `docs/howto/machine-setup.md`
- `CHANGELOG.md`

## What NOT to do

- Do not delete or stop anyone's k3d containers in the fix or its tests.
- Do not gate on hostname or hardware model.
- Tests use a scratch HOME / XDG_CONFIG_HOME (asserted not to be the real one) and stub `k3d`, `kubectl`, `docker`;
  the stub `k3d cluster list` output is captured from a real read-only run (host and date in a comment).

## Acceptance

```yaml
must:
  M1: make machine-setup / bin/k3dm-machine-setup --role R writes R to $XDG_CONFIG_HOME/k3d-manager/machine-role
  M2: with machine-role = hub, cluster-up proceeds to the existing hub start/create path (paired positive control for N1)
  M3: with K3DM_ALLOW_LOCAL_HUB=1 and no role file, cluster-up proceeds to the hub path
must_not:
  N1: with machine-role = control/worker/console, or missing, cluster-up never runs k3d cluster start or k3d cluster create (deploy_cluster --provider k3d) and exits non-zero with a message naming the role file and "run acg-up on the hub"
  N2: the refusal happens before any AWS, SSH tunnel or kubectl mutation call
evidence:
  E1:
    proves: [M1, M2, M3, N1, N2]
    kind: offline
    intent: >-
      You will see BATS with a scratch XDG_CONFIG_HOME and stub k3d/kubectl/aws recording their argv: role control
      and a missing file give a non-zero exit, the message, and no k3d start/create or aws call in the log (red on
      the pre-fix script); role hub and the override reach the stub k3d start.
    what: bats on the new/updated cluster-up and machine-setup suites
  E2:
    proves: [N1]
    kind: live
    intent: >-
      You will see on the M4 (role control or no file) that bin/acg-up --no-login-prompt exits at once with the
      refusal, and docker ps -a still shows the k3d-k3d-cluster containers Exited.
    what: operator on the M4
  E3:
    proves: [M1, M2]
    kind: live
    intent: You will see on the M5, after make machine-setup ROLE=hub, the role file reads hub and acg-up gets past the hub step.
    what: operator on the M5
interface:
  - bin/cluster-up (via bin/acg-up, make up)
  - bin/k3dm-machine-setup --role R
  - $XDG_CONFIG_HOME/k3d-manager/machine-role
  - env K3DM_ALLOW_LOCAL_HUB
```
