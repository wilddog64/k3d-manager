# Bug: cluster-up reports success while AWS sandbox Prometheus port-forward is unavailable

**Filed:** 2026-10-15
**Branch:** `k3d-manager-v1.43.4` (triage 2026-10-15, operator-approved placement)
**Status:** FIXED — 2026-10-17: `3b3efd9f` (Codex) + behavioural N1/N3/N4 tests `11392935` (Claude); Claude-verified (scope = spec, 8 files; BATS 71/71; N1 red on pre-fix 1707318b, N3/N4 mutation-tested red). Doc status was left at OPEN by mistake until 2026-10-17 20:30 PDT. Independent verifier (Sonnet, Acceptance-only, stubbed launchctl/kubectl, temp HOME) PASSED: 18/18 post-fix covering M1–M6 and N1–N4; N1 red on pre-fix 1707318b (8 pre-fix failures in all); re-run by Claude. Verifier note, not a defect: the missing-service branch's printed recovery hint still suggests a bare `nohup kubectl port-forward` (out of scope here). Live E2 passed (below); awaiting live E3
**Fix commit:** 3b3efd9f
Live E2, 2026-10-17: in the operator's make up (started about 20:00 PDT, tree 68441682), at 20:37:32 `launchctl list` showed `com.k3d-manager.sandbox.prometheus-port-forward` with PID 19772 and LastExitStatus 0, and `curl localhost:19190/-/ready` returned 200. The `make down KEEP_LOCAL=1` that followed removed the agent. Seen again in Claude's 20:44 run (PID 86389, ready 200). E3 not run: the auto-mode permission check blocked Claude's pod delete, so E3 needs the operator.
**Priority:** P2 — misleading successful provisioning/observability verification, degraded telemetry; reclassify if the sandbox intentionally supports a partial-success state
**Severity:** medium
**Approval:** approved — operator, 2026-10-17: "go ahead to do that" (fix as a launchd agent like Step 14c, kept in v1.43.4)
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

**Implementation:** `3b3efd9f` (see Status).

**Live observation — 2026-10-17 19:53–20:08 PDT (not E2/E3):** on `make up CLUSTER_PROVIDER=k3s-aws`
at `a05061c9`, Step 14b logged "ACG Prometheus port-forward agent loaded (launchd:
com.k3d-manager.sandbox.prometheus-port-forward…)", and `acg-prom-pf.log` shows `Forwarding from
0.0.0.0:19190` followed by 58 forwarded connections. After the sandbox went away during the keep-hub
`make down`, launchd kept relaunching kubectl (dial timeouts to the sandbox API) until cluster-down
unloaded the agent and removed it at 20:08:31. No `/-/ready` probe and no pod-delete recovery were
run, so E2 and E3 remain open.

## Fix

Run the sandbox Prometheus forward as a launchd user agent with `KeepAlive`, the same way Step 14c
runs the Pushgateway forward. launchd restarts `kubectl port-forward` each time it exits, so a
Prometheus pod restart costs a few seconds of forward instead of the rest of the sandbox's life.

Label: `com.k3d-manager.sandbox.prometheus-port-forward`. It is **not** the hub's
`com.k3d-manager.prometheus-port-forward` (`scripts/etc/launchd/com.k3d-manager.prometheus-port-forward.plist.tmpl`),
and nothing in this fix may touch that one.

Out of scope: the missing-service branch of Step 14b (its recovery hint is unchanged), the
post-provision report wording in `scripts/lib/webhook/smoke.py`, and `_acg_up_cleanup`. The agent
is not added to `_ACG_UP_OWNED_PIDS`; a failed run after Step 14b leaves it loaded, which is the
same as the Pushgateway agent today, and `cluster-down` / `cleanup-stale-sandbox` remove it.

### 1. `bin/cluster-up` — Step 14b `else` branch

Old:

```bash
else
  if [[ -f "${_acg_prom_pf_pid_file}" ]]; then
    kill "$(cat "${_acg_prom_pf_pid_file}")" 2>/dev/null || true
    rm -f "${_acg_prom_pf_pid_file}"
  fi
  kubectl port-forward svc/prometheus-operated "${_acg_prom_local_port}:9090" \
    -n monitoring --context "${_acg_observability_context}" --address 0.0.0.0 \
    >>"${_ACG_STATE_DIR}/logs/acg-prom-pf.log" 2>&1 &
  _acg_prom_pf_pid=$!
  _ACG_UP_OWNED_PIDS+=" ${_acg_prom_pf_pid}"
  echo "${_acg_prom_pf_pid}" > "${_acg_prom_pf_pid_file}"
  disown "${_acg_prom_pf_pid}"
  _info "[acg-up] ACG Prometheus port-forward PID: ${_acg_prom_pf_pid} (localhost:${_acg_prom_local_port} → ${_acg_observability_context}, log: ${_ACG_STATE_DIR}/logs/acg-prom-pf.log)"
fi
```

New (the `PLIST` terminator must stay in column 0):

```bash
else
  if [[ -f "${_acg_prom_pf_pid_file}" ]]; then
    kill "$(cat "${_acg_prom_pf_pid_file}")" 2>/dev/null || true
    rm -f "${_acg_prom_pf_pid_file}"
  fi
  _acg_prom_pf_label="com.k3d-manager.sandbox.prometheus-port-forward"
  _acg_prom_pf_plist="${HOME}/Library/LaunchAgents/${_acg_prom_pf_label}.plist"
  _acg_prom_pf_log="${_ACG_STATE_DIR}/logs/acg-prom-pf.log"
  _acg_prom_kubectl_bin="$(command -v kubectl)"
  _acg_prom_pf_kubeconfig="${HOME}/.kube/config:${HOME}/.kube/ubuntu-k3s.yaml:${HOME}/.kube/k3s-ubuntu.yaml"
  mkdir -p "$(dirname "${_acg_prom_pf_log}")" "$(dirname "${_acg_prom_pf_plist}")"
  cat > "${_acg_prom_pf_plist}" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${_acg_prom_pf_label}</string>
  <key>ProgramArguments</key>
  <array>
    <string>${_acg_prom_kubectl_bin}</string>
    <string>port-forward</string>
    <string>svc/prometheus-operated</string>
    <string>--namespace</string>
    <string>monitoring</string>
    <string>--context</string>
    <string>${_acg_observability_context}</string>
    <string>--address</string>
    <string>0.0.0.0</string>
    <string>${_acg_prom_local_port}:9090</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>KUBECONFIG</key>
    <string>${_acg_prom_pf_kubeconfig}</string>
  </dict>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>${_acg_prom_pf_log}</string>
  <key>StandardErrorPath</key>
  <string>${_acg_prom_pf_log}</string>
</dict>
</plist>
PLIST
  if launchctl list "${_acg_prom_pf_label}" >/dev/null 2>&1; then
    launchctl unload "${_acg_prom_pf_plist}" 2>/dev/null || true
  fi
  launchctl load "${_acg_prom_pf_plist}"
  _info "[acg-up] ACG Prometheus port-forward agent loaded (launchd: ${_acg_prom_pf_label}, localhost:${_acg_prom_local_port} → ${_acg_observability_context}, log: ${_acg_prom_pf_log})"
fi
```

The pidfile kill stays: it stops a bare forward left by a sandbox brought up before this fix.

### 2. `bin/cluster-down` — unload the agent

Insert directly after the Pushgateway block's
`  _dry_guard "remove Pushgateway port-forward plist" rm -f "${_pgw_pf_plist}"` line (inside the same
`if _is_mac; then` block, before its closing `fi`):

```bash

  _info "[acg-down] Stopping ACG Prometheus port-forward launchd agent..."
  _acg_prom_pf_label="com.k3d-manager.sandbox.prometheus-port-forward"
  _acg_prom_pf_plist="${HOME}/Library/LaunchAgents/${_acg_prom_pf_label}.plist"
  if _dry_run_active; then
    _info "DRY_RUN: would unload ACG Prometheus port-forward LaunchAgent"
  elif launchctl list "${_acg_prom_pf_label}" >/dev/null 2>&1; then
      launchctl unload "${_acg_prom_pf_plist}" 2>/dev/null || true
      _info "[acg-down] ACG Prometheus port-forward launchd agent unloaded"
  fi
  _dry_guard "remove ACG Prometheus port-forward plist" rm -f "${_acg_prom_pf_plist}"
```

Keep the existing `Stopping ACG Prometheus port-forward...` pidfile block unchanged (legacy forwards).

### 3. `bin/cluster-refresh` — repair through launchd when the agent exists

Old:

```bash
_acg_prom_local_port=$((19190 + $(_acg_provider_port_offset "${_cluster_provider}")))
_pf_ensure "ACG Prometheus port-forward" \
  "${_ACG_STATE_DIR}/run/acg-prom-pf.pid" \
  "${_ACG_STATE_DIR}/logs/acg-prom-pf.log" \
  port-forward svc/prometheus-operated "${_acg_prom_local_port}:9090" \
  -n monitoring --context "${_app_context}" --address 0.0.0.0
```

New:

```bash
_acg_prom_local_port=$((19190 + $(_acg_provider_port_offset "${_cluster_provider}")))
_acg_prom_pf_label="com.k3d-manager.sandbox.prometheus-port-forward"
_acg_prom_pf_plist="${HOME}/Library/LaunchAgents/${_acg_prom_pf_label}.plist"
if _is_mac && [[ -f "${_acg_prom_pf_plist}" ]]; then
  _launchd_ensure "${_acg_prom_pf_label}" "${_acg_prom_pf_plist}" user
else
  _pf_ensure "ACG Prometheus port-forward" \
    "${_ACG_STATE_DIR}/run/acg-prom-pf.pid" \
    "${_ACG_STATE_DIR}/logs/acg-prom-pf.log" \
    port-forward svc/prometheus-operated "${_acg_prom_local_port}:9090" \
    -n monitoring --context "${_app_context}" --address 0.0.0.0
fi
```

The `_pf_ensure` fallback keeps a sandbox from before this fix repairable.

### 4. `bin/cleanup-stale-sandbox` — add the label

Old:

```bash
agents=(com.k3d-manager.frontend-port-forward com.k3d-manager.sandbox.pushgateway-port-forward)
```

New:

```bash
agents=(com.k3d-manager.frontend-port-forward com.k3d-manager.sandbox.pushgateway-port-forward com.k3d-manager.sandbox.prometheus-port-forward)
```

### 5. Tests

- `scripts/tests/bin/cluster_up.bats` — test `acg-up records Vault and Prometheus port-forward
  ownership` reads `_acg_prom_pf_pid=\$!`, which this fix removes. Rename it to
  `acg-up records Vault port-forward ownership` and delete its `prom_line` lines; keep the Vault
  assertion as is.
- New `scripts/tests/bin/sandbox_prometheus_port_forward.bats`:
  - extract the Step 14b `else` branch (from `^else$` after `_acg_prom_svc_ready` to the matching
    `^fi$`), run it with `HOME`, `_ACG_STATE_DIR`, `_acg_prom_local_port=19191`,
    `_acg_observability_context=ubuntu-k3s` set and stub `launchctl`/`kubectl` (`kubectl` must log
    and fail if called with `port-forward`). Assert: the plist exists; `plutil -lint` passes when
    `plutil` is available; it has `KeepAlive` true, `--address` `0.0.0.0`, `19191:9090`,
    `--context` `ubuntu-k3s`; `launchctl load <plist>` was called; `kubectl port-forward` was
    **not** run directly; a pre-existing `acg-prom-pf.pid` was removed.
  - `cluster-down --confirm --keep-hub` with the stubs from `cluster_down.bats` and an existing
    `com.k3d-manager.sandbox.prometheus-port-forward.plist`: `launchctl unload <plist>` once, the
    plist is removed, and the hub `com.k3d-manager.prometheus-port-forward.plist` is untouched.
  - `cluster-refresh`: with the agent plist present, the Prometheus repair goes through
    `_launchd_ensure` and starts no bare `kubectl port-forward svc/prometheus-operated`; without it,
    `_pf_ensure` runs as before. (Extract the block by its `_acg_prom_local_port=` line if running the
    whole script is impractical.)
- `scripts/tests/bin/cleanup_stale_sandbox.bats` — add: `--apply` boots out
  `com.k3d-manager.sandbox.prometheus-port-forward` and removes its plist, and never boots out
  `com.k3d-manager.prometheus-port-forward`.

## Acceptance

```yaml
must:
  - id: M1
    text: cluster-up Step 14b (service found) writes ~/Library/LaunchAgents/com.k3d-manager.sandbox.prometheus-port-forward.plist with KeepAlive true, RunAtLoad true, ProgramArguments kubectl port-forward svc/prometheus-operated --namespace monitoring --context <sandbox context> --address 0.0.0.0 <19190+offset>:9090, and loads it with launchctl.
  - id: M2
    text: The plist is a valid property list (plutil -lint passes).
  - id: M3
    text: cluster-down (keep-hub and delete-hub) unloads that agent once and removes its plist; DRY_RUN=1 changes neither.
  - id: M4
    text: cleanup-stale-sandbox --apply boots out that agent and removes its plist.
  - id: M5
    text: cluster-refresh repairs the forward through _launchd_ensure when the plist exists, and falls back to the pidfile forward when it does not.
  - id: M6
    text: A pidfile from an earlier bare forward is killed and removed by Step 14b.
must_not:
  - id: N1
    text: Step 14b (service found) never starts a bare background kubectl port-forward for prometheus-operated (red on pre-fix code, which does exactly that).
  - id: N2
    text: No script in this fix loads, unloads, boots out or removes the hub agent com.k3d-manager.prometheus-port-forward.
  - id: N3
    text: The missing-service branch of Step 14b never writes or loads the agent plist.
  - id: N4
    text: cluster-down never removes the agent when the plist is absent and launchctl does not list it (no error, exit 0).
evidence:
  - id: E1
    proves: [M1, M2, M3, M4, M5, M6, N1, N2, N3, N4]
    kind: offline
    text: BATS with stubbed launchctl/kubectl and a temp HOME; N1 shown red on cluster-up at the commit before the fix.
  - id: E2
    proves: [M1]
    kind: live
    text: Claude, on the next sandbox bring-up — launchctl list com.k3d-manager.sandbox.prometheus-port-forward shows a PID; curl localhost:19190/-/ready returns 200.
  - id: E3
    proves: [M1]
    kind: live
    text: Claude or the operator deletes the sandbox Prometheus pod (kubectl -n monitoring delete pod prometheus-<release>-0 --context ubuntu-k3s); within 2 minutes of the new pod Ready, localhost:19190/-/ready returns 200 again with no manual action.
interface:
  - bin/cluster-up Step 14b (inputs _acg_prom_svc_ready, _acg_prom_local_port, _acg_observability_context, _ACG_STATE_DIR, HOME)
  - bin/cluster-down --confirm [--keep-hub | --delete-hub --discard-hub-data], DRY_RUN
  - bin/cluster-refresh Prometheus repair block
  - bin/cleanup-stale-sandbox [--dry-run|--apply]
  - launchd label com.k3d-manager.sandbox.prometheus-port-forward; plist ~/Library/LaunchAgents/<label>.plist; log ${_ACG_STATE_DIR}/logs/acg-prom-pf.log
```

## Before You Start

- Read `memory-bank/activeContext.md` and `memory-bank/progress.md`.
- `git pull origin k3d-manager-v1.43.4`; work on that branch only.
- Read `bin/cluster-up` Steps 14b–14c, `bin/cluster-down` lines 185–250, `bin/cluster-refresh`
  `_pf_ensure` / `_launchd_ensure` and section 3, `bin/cleanup-stale-sandbox`, and the tests named in §5.

## Definition of Done

- [ ] §1–§4 applied exactly; §5 tests added/updated.
- [ ] `shellcheck bin/cluster-up bin/cluster-down bin/cluster-refresh bin/cleanup-stale-sandbox` — no new warnings.
- [ ] `bats scripts/tests/bin/sandbox_prometheus_port_forward.bats scripts/tests/bin/cluster_up.bats scripts/tests/bin/cluster_down.bats scripts/tests/bin/cleanup_stale_sandbox.bats scripts/tests/bin/sandbox_launchd_scope.bats scripts/tests/plugins/observability_acg_crd_discovery.bats` green; paste the output.
- [ ] N1 shown red: run the new Step 14b test against `git show HEAD~1:bin/cluster-up` (or the pre-fix commit) and paste the failure.
- [ ] `docs/guides/grafana-dashboards.md` triage table (near the `k3dm Deployment panels blank` row): add a row — symptom "sandbox Prometheus panels blank / `federate-acg` TargetDown", cause "the `com.k3d-manager.sandbox.prometheus-port-forward` agent is not loaded", check `launchctl list com.k3d-manager.sandbox.prometheus-port-forward` and `curl -s -o /dev/null -w '%{http_code}' http://localhost:19190/-/ready`.
- [ ] Commit message, verbatim: `fix(cluster-up): run the sandbox Prometheus port-forward as a launchd agent`
- [ ] `git push origin k3d-manager-v1.43.4`; confirm with `git rev-parse origin/k3d-manager-v1.43.4`.
- [ ] Update `memory-bank/activeContext.md` and `memory-bank/progress.md` with the SHA; report the SHA.

## What NOT to Do

- Do NOT create a PR.
- Do NOT skip pre-commit hooks (`--no-verify`).
- Do NOT modify files outside the listed targets (the four `bin/` scripts, the tests in §5, `docs/guides/grafana-dashboards.md`, memory-bank).
- Do NOT commit to `main`.
- Do NOT touch the hub agent `com.k3d-manager.prometheus-port-forward` or its template.
- Do NOT run `cluster-up`, `cluster-down`, `make up/down` or any real `launchctl` — stubs only.
- Do NOT change `_acg_up_cleanup`, `smoke.py` or the missing-service branch of Step 14b.
