# Jenkins Smoke Test Still Fails on macOS (Istio LB IP Unreachable)

**Date:** 2026-02-25
**Status:** Documented

## Description

After fixing the Jenkins none-auth JCasC flow, `CLUSTER_PROVIDER=orbstack ./scripts/k3d-manager deploy_jenkins --enable-vault` now succeeds end-to-end. However, the built-in smoke test still fails on macOS because it relies on `curl --resolve <host>:443:<IngressIP>` to reach the Istio ingress in the k3d VM.

On OrbStack, `istio-ingressgateway` exposes multiple IPs (e.g., 172.18.0.3–0.6) that are only routable from within the VM. Curl from the macOS host gets `000`/timeouts, so the smoke step always prints `ERROR: Jenkins did not become ready within 60 seconds`, even though the Jenkins pod is Running and accessible via `kubectl port-forward`.

## Impact

- `deploy_jenkins --enable-vault` logs a WARN at the end, making validation noisy even when Jenkins is healthy.
- `./scripts/k3d-manager test_jenkins_smoke` fails in the same way, blocking any attempt to integrate this check into automation on macOS.

## Workaround

- Use `kubectl port-forward -n jenkins svc/jenkins 8443:443` and hit `https://127.0.0.1:8443` for manual smoke validation.
- Alternatively, run the smoke test from inside the k3d node (e.g., `kubectl exec` into the Istio ingress pod) where 172.18.0.x is reachable.

## Chosen Fix Approach (long-term, no tech debt)

**All macOS routing logic lives in `_jenkins_run_smoke_test` (`scripts/plugins/jenkins.sh`), not in the smoke script itself.**

The smoke script (`bin/smoke-test-jenkins.sh`) remains a pure, standalone test tool that accepts a host/port and tests connectivity — it should not need to know about network topology.

### Implementation steps for Codex

1. In `_jenkins_run_smoke_test`, after obtaining the ingress IP, check if it falls in
   any RFC-1918 private range using this bash pattern:
   ```bash
   [[ "$ip" =~ ^(10\.|172\.(1[6-9]|2[0-9]|3[01])\.|192\.168\.) ]]
   ```
   This covers all three RFC-1918 blocks (`10.0.0.0/8`, `172.16.0.0/12`,
   `192.168.0.0/16`). `127.0.0.1` should be treated as "already local" — skip
   port-forward entirely if the IP is loopback.
2. If `_is_mac` **and** the IP is in a private range:
   - Register a `trap` for `EXIT`/`INT`/`TERM` **before** starting the port-forward,
     so the PID is always killed even if the smoke script errors or hangs.
   - Start `kubectl port-forward -n jenkins svc/jenkins 8443:443` in the background;
     record its PID immediately.
   - Wait up to ~5 seconds for the port to become available via
     `nc -z 127.0.0.1 8443` (lightweight; avoids TLS handshake during readiness poll).
   - Call the smoke script with host `127.0.0.1` and port `8443`. Pass
     `--resolve jenkins.dev.local.me:443:127.0.0.1` (or equivalent) so curl sends the
     correct SNI — the TLS cert is issued for `jenkins.dev.local.me`, not `127.0.0.1`.
   - After the smoke script returns, kill the port-forward PID and remove the trap.
3. On Linux/CI the ingress IP is publicly routable, so the existing path is unchanged.
4. Add `JENKINS_SMOKE_URL` as an escape-hatch override only — if set, skip the IP lookup
   entirely and pass the user-supplied URL straight through. This is for CI or unusual
   topologies, not the default path.

### Why this approach avoids tech debt

- The smoke script stays a pure, portable test tool — no platform branches inside it.
- The port-forward lifecycle (start / wait / kill) is owned by the orchestrator
  (`jenkins.sh`), which already knows the namespace, service name, and platform.
- `JENKINS_SMOKE_URL` provides a clean CI override without coupling the script to any
  specific network topology.
- Linux behavior is completely unchanged.

### Risk

- **Medium.** The `trap` must be registered *before* the port-forward starts so the PID
  is always captured. Test specifically: (a) smoke script exits 0, (b) smoke script exits
  non-zero, (c) smoke script hangs and is killed externally. In all three cases the
  port-forward process must not remain in `ps`.
- SNI mismatch: curl hitting `127.0.0.1:8443` will fail TLS verification unless
  `--resolve jenkins.dev.local.me:443:127.0.0.1` is passed so the handshake uses the
  correct hostname. Do not use `-k`/`--insecure` as a shortcut — it masks real cert
  problems.
- RFC-1918 regex must cover all three blocks. The pattern
  `^(10\.|172\.(1[6-9]|2[0-9]|3[01])\.|192\.168\.)` is correct and has been reviewed.

## Verification

- `CLUSTER_PROVIDER=orbstack ./scripts/k3d-manager deploy_jenkins --enable-vault` on m4
  completes without WARN at the end.
- `./scripts/k3d-manager test_jenkins_smoke` passes on macOS.
- Re-run on Linux (or `m2-air`) to confirm no regression in the ingress-IP path.
