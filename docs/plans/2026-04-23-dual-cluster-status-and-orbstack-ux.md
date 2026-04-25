# Plan: Dual-cluster status reporting and optional OrbStack startup UX

## Objective

Make `make up` and related operator commands report the state of both the local Hub and remote app cluster clearly, while optionally helping the operator start OrbStack when the local runtime is unavailable.

## Why this is needed

The current workflow spans two clusters and several local access layers:

- local Hub / infra cluster (`k3d-k3d-cluster`)
- remote app cluster (`ubuntu-k3s`)
- SSH tunnel / forwarded endpoints
- local Vault port-forward path
- ArgoCD in-cluster health vs local access setup

Today these concerns are reported separately and sometimes misleadingly. Operators can end up with a healthy remote cluster, a healthy ArgoCD install, and still lack a clear answer to "what is actually up?"

## Scope

- Improve reporting and operator UX only.
- Do not redesign the underlying cluster topology.
- Keep OrbStack auto-start optional, never implicit/destructive.

## Proposed Outcome

At the end of `make up` (or via a shared status helper), print a concise readiness summary with two sections:

### 1. Local Hub

- Runtime: OrbStack running / not running
- Infra cluster: `k3d-k3d-cluster` reachable / unreachable
- Vault: healthy / sealed / unreachable
- ArgoCD: installed / bootstrapped / local access required
- Tunnel: forward endpoint healthy / reverse Vault endpoint healthy / degraded

### 2. Remote App Cluster

- App cluster: `ubuntu-k3s` reachable / unreachable
- ESO webhook: ready / waiting / failed
- ClusterSecretStore: ready / waiting / failed
- App-cluster registration: present / missing

## Implementation Plan

### Phase 1 — Define status semantics

- Standardize the meaning of:
  - process running
  - endpoint reachable
  - service healthy
  - access not configured
- Separate local-access problems from in-cluster deployment problems.

### Phase 2 — Build dual-cluster status helpers

- Add helper(s) that evaluate the local Hub state.
- Add helper(s) that evaluate the remote app cluster state.
- Reuse the same status model in `make status` and the end of `bin/acg-up`.

### Phase 3 — Fix misleading tunnel reporting

- Replace the current simplistic tunnel check with endpoint-aware checks.
- Report forward and reverse legs separately.
- Avoid declaring the tunnel "down" when the process is running but one endpoint is degraded or the probe is using the wrong protocol.

### Phase 4 — ArgoCD access UX

- Distinguish clearly between:
  - ArgoCD installed and healthy in `cicd`
  - ArgoCD bootstrapped with applications/projects
  - local operator access not yet established
- Print the exact `kubectl port-forward` and `argocd login` commands when access is the only remaining gap.

### Phase 5 — Optional OrbStack startup

- Detect whether OrbStack is running before local Hub operations.
- If it is not running:
  - report that state clearly, and
  - optionally start it behind an explicit opt-in flag or environment variable.
- Never start OrbStack implicitly without operator intent.

## Risks / Questions

- Which OrbStack invocation should be treated as canonical on macOS?
- Should the optional runtime-start behavior live in `make up`, `bin/acg-up`, or a lower-level local-runtime helper?
- How much status output is useful before it becomes noisy for routine happy-path runs?

## Success Criteria

- `make up` ends with an operator-readable summary of both cluster states.
- `make status` distinguishes local Hub issues from remote app-cluster issues.
- Tunnel reporting no longer marks healthy forwarded endpoints as simply "down."
- ArgoCD health and ArgoCD local-access setup are reported separately.
- OrbStack startup remains optional and explicit.
