# OrbStack Provider Plan

**Date:** 2026-02-24
**Status:** Phase 1 + 2 implemented (2026-02-24); Phase 3 pending
**Branch:** TBD (new feature branch from `main` for Phase 3)

---

## Background

OrbStack is a fast, lightweight Docker Desktop replacement on macOS with native Apple Silicon
support. It is increasingly common among macOS developers as a drop-in replacement for
Docker Desktop. k3d already works on OrbStack's Docker runtime out of the box — k3d-manager
needs to recognize and configure it properly.

OrbStack also ships its own built-in Kubernetes (separate from k3d), which is lighter and
faster than running k3d on top of Docker.

---

## Design Principles

- Follow the existing `CLUSTER_PROVIDER` strategy pattern — no changes to consumers
- Each phase is independently useful and can ship separately
- Phases 1 and 2 share the same provider file; Phase 3 is a new provider file
- Local-first validation on macOS with OrbStack installed before any PR

---

## Phase 1 — OrbStack as k3d Runtime *(status: complete)*

**Effort:** Low (1-2 hours)
**Value:** Covers the majority of OrbStack users who already use k3d

### What it does

Adds OrbStack detection and Docker context configuration so k3d-manager works correctly
when OrbStack is the active Docker runtime. All cluster lifecycle (create, destroy,
kubeconfig) stays identical to the existing k3d provider.

### Implementation

New file: `scripts/lib/providers/orbstack.sh`

Key functions to implement (same interface as `k3d.sh`):

| Function | Notes |
|---|---|
| `_orbstack_detect` | Check `orb` CLI exists and OrbStack is running |
| `_orbstack_set_docker_context` | Set correct `DOCKER_CONTEXT` or `DOCKER_HOST` |
| `_cluster_provider_create` | Set OrbStack context, then delegate to k3d create |
| `_cluster_provider_destroy` | Set OrbStack context, then delegate to k3d destroy |
| `_cluster_provider_get_kubeconfig` | Identical to k3d provider |
| `_cluster_provider_get_nodes` | Identical to k3d provider |

Detection logic:

```bash
function _orbstack_detect() {
  command -v orb &>/dev/null && orb status &>/dev/null
}

function _orbstack_set_docker_context() {
  local ctx
  ctx=$(docker context ls --format '{{.Name}}' | grep -i orbstack | head -1)
  if [[ -n "$ctx" ]]; then
    export DOCKER_CONTEXT="$ctx"
  fi
}
```

### Activation

```bash
CLUSTER_PROVIDER=orbstack ./scripts/k3d-manager create_cluster
```

### Acceptance Criteria

- `CLUSTER_PROVIDER=orbstack create_cluster` creates a k3d cluster on OrbStack
- `CLUSTER_PROVIDER=orbstack destroy_cluster` tears it down cleanly
- kubeconfig is accessible after create
- Existing k3d provider unaffected

---

## Phase 2 — OrbStack Runtime Auto-Detection *(status: complete)*

**Effort:** Low (1 hour)
**Value:** Zero-config experience — no need to set `CLUSTER_PROVIDER` manually

### What it does

Extends the cluster provider abstraction to auto-detect OrbStack as the active Docker
runtime and select the OrbStack provider automatically when `CLUSTER_PROVIDER` is not set.

### Implementation

Update `scripts/lib/cluster_provider.sh` auto-detection logic:

```bash
function _detect_cluster_provider() {
  if [[ -n "${CLUSTER_PROVIDER:-}" ]]; then
    echo "$CLUSTER_PROVIDER"
    return
  fi

  if _orbstack_detect; then
    echo "orbstack"
  elif command -v k3d &>/dev/null; then
    echo "k3d"
  elif command -v k3s &>/dev/null; then
    echo "k3s"
  else
    echo "k3d"  # fallback default
  fi
}
```

### Acceptance Criteria

- On a Mac with OrbStack running and `CLUSTER_PROVIDER` unset, provider auto-selects `orbstack`
- On a Mac with Docker Desktop and `CLUSTER_PROVIDER` unset, provider selects `k3d`
- Explicit `CLUSTER_PROVIDER` always overrides auto-detection

---

## Phase 3 — OrbStack Native Kubernetes Provider

**Effort:** Medium (half day)
**Value:** Lightest possible local Kubernetes — no k3d overhead, truly native

### What it does

Adds a new provider for OrbStack's built-in Kubernetes cluster. This is a fundamentally
different provider — OrbStack manages the cluster lifecycle internally (enable/disable in
settings), so there is no `create_cluster` / `destroy_cluster` in the traditional sense.
Closer in behavior to the k3s provider.

### Key Differences from k3d/OrbStack-k3d

| Aspect | k3d on OrbStack | OrbStack Native k8s |
|---|---|---|
| Cluster lifecycle | `k3d cluster create/delete` | Always running when enabled |
| `create_cluster` | Creates k3d cluster | Verifies OrbStack k8s is enabled |
| `destroy_cluster` | Deletes k3d cluster | No-op (or warn: disable in OrbStack settings) |
| kubeconfig | k3d writes it | OrbStack writes its own context |
| Overhead | k3d + Docker + containerd | Minimal — OrbStack native |

### Implementation

New file: `scripts/lib/providers/orbstack-k8s.sh`

| Function | Behavior |
|---|---|
| `_cluster_provider_create` | Verify OrbStack k8s is enabled; print instructions if not |
| `_cluster_provider_destroy` | Warn that lifecycle is managed by OrbStack settings |
| `_cluster_provider_get_kubeconfig` | Return OrbStack's kubeconfig context |
| `_cluster_provider_get_nodes` | `kubectl get nodes` against OrbStack context |

### Activation

```bash
CLUSTER_PROVIDER=orbstack-k8s ./scripts/k3d-manager deploy_cluster
```

### Acceptance Criteria

- `create_cluster` verifies OrbStack Kubernetes is running; fails gracefully if not enabled
- `deploy_cluster` deploys Vault, Istio, ESO against OrbStack native k8s
- `destroy_cluster` prints a clear message explaining lifecycle is OrbStack-managed
- kubeconfig context is correct and `kubectl get nodes` works

---

## Implementation Sequence

1. [x] Create `scripts/lib/providers/orbstack.sh` — Phase 1 implementation
2. [ ] Validate Phase 1 locally on macOS with OrbStack installed
3. [x] Update `scripts/lib/cluster_provider.sh` — Phase 2 auto-detection
4. [ ] Validate Phase 2 auto-detection with OrbStack running vs. Docker Desktop
5. [x] Update `scripts/etc/cluster_var.sh` — document `orbstack` and `orbstack-k8s` as valid values
6. [x] Update `.clinerules` and `CLAUDE.md` with new provider values
7. [ ] Create `scripts/lib/providers/orbstack-k8s.sh` — Phase 3 implementation
8. [ ] Validate Phase 3 against OrbStack native Kubernetes
9. [x] Update `memory-bank/progress.md` as each phase completes

---

## Reference

- Existing k3d provider: `scripts/lib/providers/k3d.sh`
- Existing k3s provider: `scripts/lib/providers/k3s.sh`
- Provider abstraction: `scripts/lib/cluster_provider.sh`
- OrbStack CLI docs: https://docs.orbstack.dev/
