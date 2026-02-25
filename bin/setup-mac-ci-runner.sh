#!/usr/bin/env bash
set -euo pipefail

# setup-mac-ci-runner.sh — Pre-build the persistent Stage 2 CI cluster on a macOS runner.
#
# Platform: macOS only (uses OrbStack as the container runtime).
# For a Linux runner (Ubuntu + k3s), a separate setup-linux-ci-runner.sh will be needed.
#
# Run this once on the self-hosted Mac runner (m2-air) before Stage 2 CI jobs can execute.
# The script installs OrbStack (if needed), creates the k3d cluster, and deploys the core
# stack (Istio, Vault HA, ESO). The cluster is left running as a persistent fixture for CI.
#
# Usage:
#   ./bin/setup-mac-ci-runner.sh               # full setup (safe to re-run)
#   ./bin/setup-mac-ci-runner.sh --health-only # just run the health check, no setup
#
# Environment variables:
#   CLUSTER_PROVIDER  — cluster backend (default: orbstack)
#   SKIP_CREATE       — set to 1 to skip cluster creation (if cluster already exists)
#   SKIP_VAULT        — set to 1 to skip Vault deploy (if already deployed)
#   SKIP_UNSEAL       — set to 1 to skip Vault unseal (if freshly deployed / auto-unsealed)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
K3D_MANAGER="${SCRIPT_DIR}/scripts/k3d-manager"
HEALTH_CHECK="${SCRIPT_DIR}/scripts/ci/check_cluster_health.sh"

export CLUSTER_PROVIDER="${CLUSTER_PROVIDER:-orbstack}"

_info() { printf '\n[setup-mac-ci-runner] %s\n' "$*"; }
_err()  { printf '\n[setup-mac-ci-runner] ERROR: %s\n' "$*" >&2; exit 1; }
_ok()   { printf '[setup-mac-ci-runner] OK: %s\n' "$*"; }

# ── Platform guard ─────────────────────────────────────────────────────────────

if [[ "$(uname -s)" != "Darwin" ]]; then
  _err "This script is macOS-only (OrbStack is not available on Linux)."
  _err "For a Linux runner, use a separate setup-linux-ci-runner.sh with k3s or k3d+Docker."
fi

# ── Preflight ──────────────────────────────────────────────────────────────────

[[ -x "$K3D_MANAGER" ]] || _err "k3d-manager not found at $K3D_MANAGER"
[[ -f "$HEALTH_CHECK" ]] || _err "check_cluster_health.sh not found at $HEALTH_CHECK"

if [[ "${1:-}" == "--health-only" ]]; then
  _info "Running health check only..."
  bash "$HEALTH_CHECK"
  _ok "Cluster is healthy."
  exit 0
fi

# ── OrbStack check ─────────────────────────────────────────────────────────────

_info "Checking OrbStack..."
if ! command -v orb >/dev/null 2>&1; then
  _info "OrbStack not found — k3d-manager will install it via Homebrew."
  _info "If OrbStack.app opens, complete the GUI onboarding, then the script will continue automatically."
else
  if ! orb status >/dev/null 2>&1; then
    _info "OrbStack is installed but not running — launching OrbStack.app..."
    open -g -a OrbStack 2>/dev/null || true
    _info "Waiting for OrbStack to start (complete GUI onboarding if prompted)..."
    attempts=20
    while (( attempts-- > 0 )); do
      if orb status >/dev/null 2>&1; then break; fi
      sleep 3
    done
    orb status >/dev/null 2>&1 || _err "OrbStack did not start. Open OrbStack.app manually and rerun."
  fi
  _ok "OrbStack is running."
fi

# ── Cluster creation ───────────────────────────────────────────────────────────

if [[ "${SKIP_CREATE:-0}" == "1" ]]; then
  _info "SKIP_CREATE=1 — skipping cluster creation."
else
  _info "Creating cluster (CLUSTER_PROVIDER=$CLUSTER_PROVIDER)..."
  _info "If OrbStack.app opens during this step, complete onboarding before continuing."
  CLUSTER_PROVIDER="$CLUSTER_PROVIDER" "$K3D_MANAGER" create_cluster
  _ok "Cluster created."
fi

# ── Core stack deployment ──────────────────────────────────────────────────────

_info "Deploying Istio..."
CLUSTER_PROVIDER="$CLUSTER_PROVIDER" "$K3D_MANAGER" deploy_istio
_ok "Istio deployed."

if [[ "${SKIP_VAULT:-0}" == "1" ]]; then
  _info "SKIP_VAULT=1 — skipping Vault deploy."
else
  _info "Deploying Vault (HA mode)..."
  CLUSTER_PROVIDER="$CLUSTER_PROVIDER" "$K3D_MANAGER" deploy_vault ha
  _ok "Vault deployed."
fi

_info "Deploying External Secrets Operator..."
CLUSTER_PROVIDER="$CLUSTER_PROVIDER" "$K3D_MANAGER" deploy_eso
_ok "ESO deployed."

if [[ "${SKIP_UNSEAL:-0}" == "1" ]]; then
  _info "SKIP_UNSEAL=1 — skipping Vault unseal."
else
  _info "Unsealing Vault..."
  CLUSTER_PROVIDER="$CLUSTER_PROVIDER" "$K3D_MANAGER" reunseal_vault
  _ok "Vault unsealed."
fi

# ── Final health check ─────────────────────────────────────────────────────────

_info "Running cluster health check..."
bash "$HEALTH_CHECK"
_ok "All checks passed. macOS CI runner is ready for Stage 2 jobs."

cat <<'EOF'

────────────────────────────────────────────────────────
  Stage 2 CI runner setup complete (macOS / OrbStack).

  Keep this cluster running between CI jobs.

  After a host reboot, unseal Vault before the next run:
    CLUSTER_PROVIDER=orbstack ./scripts/k3d-manager reunseal_vault

  To verify cluster health at any time:
    ./bin/setup-mac-ci-runner.sh --health-only
────────────────────────────────────────────────────────
EOF
