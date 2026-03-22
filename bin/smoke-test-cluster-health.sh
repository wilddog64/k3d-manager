#!/usr/bin/env bash
# bin/smoke-test-cluster-health.sh
# Baseline cluster health gate — run after every cluster task before reporting done.
#
# Checks:
#   1. ghcr-pull-secret exists in all 3 shopping-cart namespaces (ubuntu-k3s context)
#   2. All 5 ArgoCD apps are Synced (infra cluster context)
#   3. At least 4 pods Running on ubuntu-k3s (basket CrashLoopBackOff is expected)
#
# Usage:
#   bin/smoke-test-cluster-health.sh
#
# Environment:
#   INFRA_CONTEXT      kubectl context for infra cluster (default: k3d-k3d-cluster)
#   APP_CONTEXT        kubectl context for app cluster   (default: ubuntu-k3s)
#   ARGOCD_NAMESPACE   namespace ArgoCD runs in          (default: cicd)

set -euo pipefail

INFRA_CONTEXT="${INFRA_CONTEXT:-k3d-k3d-cluster}"
APP_CONTEXT="${APP_CONTEXT:-ubuntu-k3s}"
ARGOCD_NAMESPACE="${ARGOCD_NAMESPACE:-cicd}"
SHOPPING_CART_NS="shopping-cart"

PASS=0
FAIL=0

_pass() { echo "[PASS] $*"; (( PASS++ )) || true; }
_fail() { echo "[FAIL] $*" >&2; (( FAIL++ )) || true; }

echo "=== Cluster Health Smoke Test ==="
echo "  infra: ${INFRA_CONTEXT}"
echo "  app:   ${APP_CONTEXT}"
echo ""

# --- 1. ghcr-pull-secret in all 3 namespaces (app cluster) ---
echo "-- ghcr-pull-secret --"
for ns in shopping-cart-apps shopping-cart-data shopping-cart-payment; do
  if kubectl --context="${APP_CONTEXT}" get secret ghcr-pull-secret -n "${ns}" >/dev/null 2>&1; then
    _pass "ghcr-pull-secret present in ${ns}"
  else
    _fail "ghcr-pull-secret MISSING in ${ns}"
  fi
done

echo ""

# --- 2. ArgoCD apps Synced (infra cluster) ---
echo "-- ArgoCD sync status --"
for app in shopping-cart-basket shopping-cart-order shopping-cart-payment \
           shopping-cart-product-catalog shopping-cart-frontend; do
  sync_status=$(kubectl --context="${INFRA_CONTEXT}" get application "${app}" \
    -n "${ARGOCD_NAMESPACE}" \
    -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "NotFound")
  if [[ "${sync_status}" == "Synced" ]]; then
    _pass "${app}: Synced"
  else
    _fail "${app}: ${sync_status} (expected Synced)"
  fi
done

echo ""

# --- 3. Pod status on app cluster ---
echo "-- Pod status (${APP_CONTEXT}) --"
running=$(kubectl --context="${APP_CONTEXT}" get pods -n "${SHOPPING_CART_NS}" \
  --no-headers 2>/dev/null | grep -c "Running" || true)
crashloop=$(kubectl --context="${APP_CONTEXT}" get pods -n "${SHOPPING_CART_NS}" \
  --no-headers 2>/dev/null | grep -c "CrashLoopBackOff" || true)

echo "  Running:            ${running}"
echo "  CrashLoopBackOff:   ${crashloop}"

if (( running >= 5 )); then
  _pass "${running}/5 pods Running"
elif (( running >= 4 )); then
  _pass "${running}/5 pods Running (1 pod exempt — see docs/issues/)"
else
  _fail "only ${running}/5 pods Running — expected at least 4"
fi

echo ""

# --- Summary ---
echo "=== Result: ${PASS} passed, ${FAIL} failed ==="
if (( FAIL > 0 )); then
  exit 1
fi
exit 0
