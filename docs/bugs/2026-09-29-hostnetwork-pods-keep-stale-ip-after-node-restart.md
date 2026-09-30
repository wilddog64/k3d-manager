# Bug: after a hub node restart, host-network pods keep stale node IPs, and nothing detects or fixes it

**Branch:** `k3d-manager-v1.40.0`
**Filed:** 2026-09-29 by Claude (cloud session), from a `PrometheusDuplicateTimestamps` alert on the hub
**Status:** FIXED — implemented 2026-09-29; commit SHA recorded in the completion handoff. Recovered live by the operator.
**Related:** `docs/bugs/2026-09-13-hub-orbstack-restart-serverlb-empty-config.md` Defect 4 (first
occurrence, `istio-cni-node`, fixed by hand, never given a durable fix)

## Evidence (2026-09-29)

- Alert `PrometheusDuplicateTimestamps` (hub, `warning`), ongoing for at least 24 h. The Prometheus log:
  `Error on ingesting samples with different value but same timestamp`
  `scrape_pool=serviceMonitor/monitoring/kube-prometheus-stack-kube-state-metrics/0 num_dropped=1`, every minute.
- The duplicate series was
  `kube_endpoint_address{endpoint="kube-prometheus-stack-prometheus-node-exporter",ip="192.168.97.5",port_number="9100"}`.
- The node-exporter pods, all `RESTARTS 1 (2d4h ago)`:

  | Node | Node InternalIP | Pod IP (hostNetwork) |
  |---|---|---|
  | server-0 | .5 | .5 |
  | agent-0 | .4 | .3 |
  | agent-1 | .3 | .5 |
  | agent-2 | .2 | .4 |

- Consequences: the Service listed `.5` twice (the duplicate) and `.2` not at all, so **agent-2 was
  not scraped**. Every other per-node series carried the wrong node's data.
- Live fix: `kubectl -n monitoring delete pod -l app.kubernetes.io/name=prometheus-node-exporter`. The
  DaemonSet recreated each pod with the correct IP. A cluster-wide check (host-network pods with
  `status.hostIP` ≠ the node's InternalIP) then came back empty.

## Root cause

When OrbStack or `k3dm-node-health-watch` restarts the k3d node containers, OrbStack can assign the
nodes different IPs. Pods restart in place, and for `hostNetwork` pods the recorded
`status.podIP`/`status.hostIP` keep the pre-restart address, so Services and EndpointSlices route by
the old addresses. Nothing in the repo compares a host-network pod's IP to its node's current IP.
The first occurrence (2026-09-13) hit `istio-cni-node`, whose readiness probe then failed. This one
hit node-exporter, which failed silently except for the duplicate-sample warning.

## Codex brief

**Goal:** detect host-network pods whose recorded IP no longer matches their node, fix them after a
node restart without a human, and let Hermes propose the same fix at any other time.

**Runs where:** Codex web is fine. Offline only: stub `kubectl`; never touch a live cluster.

**Decisions already made:** one shared script used in three places. The fix deletes **only**
DaemonSet-owned pods (their controller recreates them immediately), never bare pods and never
Deployment/StatefulSet pods. The Hermes repair is approval-gated (Phase 2), like R1–R4 and R7.

**Files to touch (only these):**
- `bin/k3dm-hostnet-drift` (new, `set -euo pipefail`): `--context CTX` (default `k3d-k3d-cluster`),
  `--json` (report), `--fix`. Reads `kubectl get nodes -o json` and `get pods -A -o json` once each.
  A pod has drifted when `spec.hostNetwork == true`, it is `Running`, and `status.hostIP` differs from
  its node's `InternalIP`. `--json` prints `{"drifted": [{"namespace","pod","node","pod_ip","node_ip","owner_kind"}]}`
  and exits 0. `--fix` deletes drifted pods whose `ownerReferences[0].kind == "DaemonSet"`, logs each
  one, logs and skips others, and exits 0 unless a delete fails.
- `scripts/plugins/hub_recovery.sh`: new step `"Host-network IP drift"` in `hub_recovery_reconcile`,
  run after `k3d serverlb upstreams`; it calls `bin/k3dm-hostnet-drift --context "$hub_context" --fix`.
  Warn on failure and continue.
- `bin/k3dm-node-health-watch`: after it restarts an agent container **and** the node is `Ready`
  again, run `bin/k3dm-hostnet-drift --context <ctx> --fix` once. Advisory paths (no restart) do not call it.
- `scripts/lib/hermes/sensors.py`: new sensor `hostnet_drift(run, state, threshold=2)` that runs
  `bin/k3dm-hostnet-drift --json` through the injected runner (as `kine` does). Healthy when
  `drifted` is empty; degraded (debounced) with evidence `"N host-network pods on stale IPs: ns/pod, …"`
  (first 3) and `data.drifted`; unknown when the probe fails. Register it in `bin/k3dm-hermes`, and
  add `"hostnet_drift": "node"` to the exporter's `target_scopes`.
- `scripts/lib/hermes/repairs.py`: `r8` "Recycle drifted host-network DaemonSet pods". Precondition:
  `hostnet_drift` degraded and at least one drifted pod has `owner_kind == "DaemonSet"`. Command
  `["bin/k3dm-hostnet-drift", "--fix"]`, `cwd: ROOT`. Blast radius: "DaemonSet pods on stale node IPs
  are recreated". `reversible: True`. `needs_scope: "local hub kubeconfig"`. Add `"r8": ("hostnet_drift",)` to `_evidence`.
- `docs/architecture/hermes-phase2-repair-scope.md` (R8 row); tests (below); `CHANGELOG.md`;
  `memory-bank/activeContext.md`, `memory-bank/progress.md`; this doc (Status → FIXED with the SHA).

**Tests (offline, stubbed `kubectl` JSON based on the 2026-09-29 table above):**
1. `bin/k3dm-hostnet-drift --json` reports exactly the three mismatched node-exporter pods, and not
   server-0's pod.
2. `--fix` deletes those three and nothing else. A drifted Deployment-owned hostNetwork pod and a bare
   pod are reported but not deleted.
3. No drift → `--fix` makes no delete calls.
4. `hub_recovery_reconcile --confirm` calls the script with `--fix` after the serverlb step, and a
   failure there does not stop recovery.
5. `node-health-watch`: a restart path calls the script once after Ready; the advisory path does not.
6. `hostnet_drift` sensor: healthy, degraded after 2 cycles, unknown on probe failure.
7. R8 is proposed only when a DaemonSet-owned pod has drifted, and its command is exactly as specified.

**Mutations:** compare `podIP` from the wrong side (or skip the comparison) → test 1 red; drop the
DaemonSet-owner check → test 2 red; make a drift-fix failure fatal in recovery → test 4 red.

**Gates (paste output):** `shellcheck -S warning bin/k3dm-hostnet-drift bin/k3dm-node-health-watch scripts/plugins/hub_recovery.sh`;
the new and touched BATS suites; `make test-pytest`; `git diff --stat` lists only the files above.

**Lessons from the previous brief (2026-09-29 review of `2dfa00ef`):** do not use `trap … RETURN`
with nested quoting; clean up temp files explicitly on every return path. Every early-return path
needs its own test. Cover each numbered test above; say explicitly if you skip one.

**Do not change:** R1–R7, `approve()`, `scripts/lib/foundation/`, `scripts/lib/acg/`. No live cluster commands.

**Commit and hand back:** one commit on `k3d-manager-v1.40.0`, message
`fix(hub): detect and recycle host-network pods stranded on stale node IPs`.
No PR, no merge, no force-push, no `--no-verify`.
