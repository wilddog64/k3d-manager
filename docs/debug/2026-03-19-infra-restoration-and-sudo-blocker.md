# Debugging Session: Infrastructure Restoration and Sudo Blocker

**Date:** 2026-03-19
**Host:** `m4-air.local`
**Target:** Infra Cluster (k3d), App Cluster (Ubuntu k3s on M2 Air)

## Summary

This session focused on bringing the infrastructure back online after an unexpected restart of the `m4-air` host and the `ubuntu` VM. While the infra cluster was successfully restored, the app cluster redeployment was blocked by a privilege escalation issue.

## Timeline & Actions

### 1. Infra Cluster Restoration (k3d)
- **Status:** All components except Jenkins were redeployed successfully.
- **Components:** Vault (unsealed via cached keys), ESO, OpenLDAP, Keycloak, ArgoCD.
- **Jenkins:** Explicitly skipped per user request to maintain optionality.

### 2. SSH Tunnel & Network Isolation
- **Issue:** SSH tunnel on port 6443 was reported as "Address already in use" on the host. 
- **Confusion:** Attempted to use port 6445 as a workaround.
- **Discovery:** ArgoCD pods inside the cluster could not reach the host's `localhost:6443` tunnel due to network namespace isolation.
- **Fix Attempted:** Bound the tunnel to `0.0.0.0` and used `host.k3d.internal` (mapping to the bridge gateway IP).
- **Default Reversion:** Per user instruction, reverted all configurations to the default port **6443**.

### 3. Ubuntu VM Hang & Hard-Reset
- **Issue:** Direct SSH to `ubuntu` and the tunnel itself were failing or dropping immediately.
- **Diagnosis:** The Ubuntu VM (running on Parallels on an M2 Air) was found to be hung.
- **Action:** Accessed the M2 Air via SSH and issued a hard-reset:
  ```bash
  ssh m2-air.local "prlctl reset 'Ubuntu 24.04 ARM64'"
  ```
- **Result:** VM rebooted successfully and SSH connectivity was restored.

### 4. App Cluster (k3s) Rebuild Attempt
- **Action:** User requested a clean rebuild of the app cluster to resolve TLS trust issues resulting from the reset.
- **Execution:**
  - uninstalled existing k3s on Ubuntu.
  - Attempted `deploy_cluster --force-k3s automation`.
- **Blocker:** The deployment failed at the `mkdir -p /etc/rancher/k3s` step.
- **Root Cause:** The `_run_command` function defaults to `sudo -n` (non-interactive). After a VM reboot, the `sudo` timestamp is cold and requires a password. `sudo -n` rejects the command immediately rather than prompting.

## Lessons Learned

1.  **Defaults are Sacred:** Stick to default ports (6443) to avoid configuration drift and "cleaning up" multiple IP/port mappings.
2.  **Sandbox Reality:** Remember that `localhost` inside an OrbStack/k3d pod is NOT the same as the Mac host `localhost`. Host-bound tunnels MUST bind to an interface reachable by the cluster gateway (e.g., `0.0.0.0`).
3.  **Sudo Warmup:** When performing remote rebuilds after a reboot, the `sudo` timestamp must be "warmed up" manually (`ssh -t ubuntu "sudo true"`) because the agent cannot handle interactive prompts through the current `_run_command` logic.

## Status at Session End
- **Infra Cluster:** Fully Functional (Vault unsealed).
- **App Cluster:** **Uninstalled**.
- **Blocker:** Non-interactive `sudo` failure documented in `docs/issues/2026-03-19-run-command-non-interactive-sudo-failure.md`.
- **Plan:** Fix `_run_command` logic on 2026-03-20.
