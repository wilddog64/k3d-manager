# Bug: cluster-up reports success while AWS sandbox Prometheus port-forward is unavailable

**Filed:** 2026-10-15
**Branch:** `k3d-manager-v1.43.4` (triage 2026-10-15, operator-approved placement)
**Status:** OPEN — investigation required; root cause not established
**Priority:** P2 — misleading successful provisioning/observability verification, degraded telemetry; reclassify if the sandbox intentionally supports a partial-success state
**Severity:** medium
**Approval:** operator explicitly authorized filing if identified as bug, 2026-10-15; implementation not approved
**Evidence:** Slack post-provision output from AWS ACG `cluster-up` job `5f5cff23` (completed in 18m)

## Observed

Slack reported `✅ cluster-up (aws) — success in 18m`; its post-provision check then showed:

```text
Prometheus: ❌ no listener on localhost:19190 (app-cluster Prometheus port-forward not running)
Grafana: ✅ HTTP 200
```

Other observed checks included ArgoCD 43/43 apps healthy, frontend and Keycloak HTTP 200, Pushgateway HTTP 200 and ESO secrets synced. These prove other checks worked, **not** that the app Prometheus port-forward was healthy. Prometheus itself may be running in Kubernetes; the report only proves no local listener at check time.

## Verified source details

- `bin/cluster-up` Step 14b computes the per-provider port from `19190 + _acg_provider_port_offset`, waits up to 24 × 5s for `monitoring/svc/prometheus-operated`, then launches `kubectl port-forward ... --address 0.0.0.0` as a background process; records its PID, but does **not** verify the listener remains usable before the workflow reports success.
- If the service is absent, Step 14b warns and skips the forward without failing the overall bring-up.
- `scripts/lib/webhook/smoke.py` identifies missing `localhost:19190` listeners during post-provision checks.
- `bin/cluster-refresh` has a `_pf_ensure` repair path for the Prometheus forward, which may be an appropriate explicit recovery action **only after diagnosis**, not an automatically authorized intervention.
- Hub Prometheus and AWS app Prometheus intentionally use separate ports (`19090` versus `19190`); the prior collision was addressed in `docs/bugs/2026-09-14-prometheus-port-19090-hub-acg-collision.md`.
- Prior `docs/bugs/2026-10-03-acg-sandbox-prometheus-crds-missing-from-api-discovery.md` documented a missing Prometheus service/operator issue, now mitigated. Do not assume it recurred without verifying current Kubernetes resources.

## Investigation — non-destructive first

1. Retrieve this job's Step 14/14b output via local webhook job-status (or cloud-bridge reader `job-status` for `5f5cff23`); look for missing-service warning, process PID and port-forward log path. Prefer this over speculative analysis.
2. On the Mac, inspect `lsof -nP -iTCP:19190 -sTCP:LISTEN`, the recorded PID/command, and the actual Step 14b `acg-prom-pf.log` path. Distinguish `bind: address already in use`, `services not found`, upstream connection error and background-process termination. Don't assume the default state directory when overridden.
3. Read-only inspect `kubectl --context ubuntu-k3s -n monitoring get svc prometheus-operated`, StatefulSet/Prometheus CR availability and endpoints, and `kubectl` connectivity. Determine whether only the local forward is down or the underlying service was never created.
4. Check whether `bin/cluster-up` exits with success after port-forward start failure or delayed death; check other port-forward management steps for the same unsafe success semantics. Preserve documented ability to provision sandbox when optional observability is temporarily unavailable, if that is the intended contract, but **report partial success explicitly**.
5. Compare status obtained from existing read-only cloud-bridge `job-status` and `make-observability-status`; the latter reports Kubernetes monitoring state and may not expose host-local listener status. Do not introduce an unrestricted remote-shell endpoint.
6. Decide whether the app Prometheus forward should become a managed/self-restarting LaunchAgent similar to existing forwards, or use a bounded post-start probe/recovery path; assess possible host process ownership/cleanup side effects and the Oct 4 port-forward cleanup regression.
7. Add deterministic tests for service missing, bind conflict, launch success followed by process death, and successful listener; capture remediation guidance and unambiguous terminal state. Avoid invoking real AWS resources in automated tests.

## Expected / acceptance

- Post-provision output clearly identifies app Prometheus **service readiness** separately from **local forwarding health**, including a concrete reason when inaccessible.
- A missing or dead required forwarding path must not be silently reported as a fully healthy `cluster-up`; if provisioning success is separate, show `provisioned with observability warning` and preserve a meaningful verification status.
- A working listener on expected provider-specific port survives the intended lifecycle or has an observable, bounded self-healing mechanism.
- No port-conflict claim or automatic resource mutation without evidence; no unrelated cluster shutdown or destructive action.

## Findings — 2026-10-17 (Claude, read-only)

- Job `5f5cff23` Step 14b **did** start the forward (`PID 20171`); it was not the missing-service skip.
- Step 14b launches a bare background `kubectl port-forward` (`bin/cluster-up` ~1966). Every other
  sandbox forward (Vault 4.1, ArgoCD 4b, frontend 10g.10, Pushgateway 14c) is a launchd agent with
  auto-restart. `kubectl port-forward` exits when its target pod goes away, and nothing restarts it.
- `~/.local/share/k3d-manager/k3s-aws/logs/acg-prom-pf.log` (across runs): 5× `error: lost connection
  to pod`, 2× `unable to forward port because pod is not running. Current status=Pending` — the
  Prometheus pod is rescheduled after Step 14 starts the forward (Step 14 itself deploys/updates it).
- `_acg_up_cleanup` kills the PID only on a non-zero exit, so cleanup is not the cause.
- Likely root cause: an unmanaged forward that dies on the first Prometheus pod restart. Fix shape:
  install it as a launchd agent like Step 14c. Not yet proven for this job (log lines carry no
  timestamps); live proof needs a sandbox.

**Implementation:** not started.
