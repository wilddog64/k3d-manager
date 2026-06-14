# Bugfix: v1.7.1 — `bin/hostinger-status` missing Service Health (endpoints + ESO)

**Branch:** `k3d-manager-v1.7.1`
**Files:** `bin/hostinger-status`

---

## Problem

`make status CLUSTER_PROVIDER=k3s-hostinger` (which runs `bin/hostinger-status`) reports nodes,
pods, API health, ArgoCD registration, apps, and ApplicationSets — but **does not report
per-service endpoint health and does not check ESO** (External Secrets Operator). Its ACG
counterpart `bin/cluster-status` has a `Service Health` section that surfaces both.

**Root cause:** `bin/hostinger-status` never calls the webhook `/api/v1/health` endpoint.
That endpoint already returns the full report — per-endpoint HTTP checks **plus**
`ESO ClusterSecretStore` and `ESO ExternalSecrets` readiness (verified live: `Ready=True`,
`5/5 synced`). The script simply omits the section.

---

## Reproduction

```bash
make status CLUSTER_PROVIDER=k3s-hostinger
```

**Actual:** ends at `=== ArgoCD ApplicationSets ===`. No endpoint statuses, no ESO.
**Expected:** a trailing `=== Service Health (endpoints + ESO) ===` section listing each
service with ✅/❌ and detail, including `ESO ClusterSecretStore` and `ESO ExternalSecrets`.

---

## Fix

### Change 1 — `bin/hostinger-status`: append a Service Health section

Mirror `bin/cluster-status:73–93` exactly (same webhook call, same renderer). The webhook is the
single source of truth for endpoint + ESO health, so reuse it rather than re-implementing checks.

**Exact old block (end of file, lines 57–61):**

```bash
echo ""
echo "=== ArgoCD ApplicationSets (${INFRA_CONTEXT}) ==="
kubectl get applicationsets.argoproj.io -A --context "${INFRA_CONTEXT}" 2>/dev/null \
  || echo "Cannot reach hub cluster or ArgoCD CRDs not installed"
```

**Exact new block:**

```bash
echo ""
echo "=== ArgoCD ApplicationSets (${INFRA_CONTEXT}) ==="
kubectl get applicationsets.argoproj.io -A --context "${INFRA_CONTEXT}" 2>/dev/null \
  || echo "Cannot reach hub cluster or ArgoCD CRDs not installed"

echo ""
echo "=== Service Health (endpoints + ESO) ==="
_WEBHOOK_TOKEN="${K3DM_WEBHOOK_TOKEN:-$(security find-generic-password -s k3dm-webhook-token -w 2>/dev/null || true)}"
_WEBHOOK_PORT="${K3DM_WEBHOOK_PORT:-7443}"
if [[ -n "${_WEBHOOK_TOKEN}" ]]; then
  _health_json=$(curl -sf --max-time 90 \
    -H "Authorization: Bearer ${_WEBHOOK_TOKEN}" \
    "http://localhost:${_WEBHOOK_PORT}/api/v1/health" 2>/dev/null || true)
  if [[ -n "${_health_json}" ]]; then
    echo "${_health_json}" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for s in data.get('services', []):
    icon = '✅' if s['ok'] else '❌'
    print(f'  {icon} {s[\"name\"]}: {s[\"detail\"]}')
"
  else
    echo "  (webhook unreachable at localhost:${_WEBHOOK_PORT} — run: make restart-webhook)"
  fi
else
  echo "  (webhook token not in Keychain — set K3DM_WEBHOOK_TOKEN or run: make install-webhook)"
fi
```

---

## Files Changed

| File | Change |
|------|--------|
| `bin/hostinger-status` | append `Service Health (endpoints + ESO)` section calling webhook `/api/v1/health` |

---

## Rules

- `shellcheck -S warning bin/hostinger-status` — zero new warnings
- `bash -n bin/hostinger-status` — clean
- No other files touched
- Do NOT touch `scripts/lib/acg/` or `scripts/lib/foundation/` (subtrees)

---

## Definition of Done

- [ ] `bin/hostinger-status` ends with a `=== Service Health (endpoints + ESO) ===` section
- [ ] Section renders each `/api/v1/health` service with ✅/❌ + detail, incl. both ESO rows
- [ ] Graceful fallbacks for missing token / unreachable webhook (kept verbatim from cluster-status)
- [ ] `shellcheck -S warning bin/hostinger-status` + `bash -n bin/hostinger-status` clean
- [ ] Committed and pushed to `k3d-manager-v1.7.1`
- [ ] memory-bank updated with commit SHA and task status

**Commit message (exact):**
```
fix(status): add Service Health (endpoints + ESO) to bin/hostinger-status
```

---

## What NOT to Do

- Do NOT re-implement endpoint/ESO checks in the shell script — reuse the webhook `/api/v1/health`
- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `bin/hostinger-status`
- Do NOT commit to `main` — work on `k3d-manager-v1.7.1`

---

## Known limitation (NOT part of this fix — separate task)

The webhook's `_SMOKE_ENDPOINTS` and the data-layer readiness check are still pointed at the
ACG/hub-local surface (`localhost:8080` ArgoCD, `frontend.shopping-cart.local`, data-layer on
context `ubuntu-k3s`). The **ESO** rows are hub-based and correct for Hostinger; the **HTTP
endpoint** rows and **Data layer** row will show stale ACG targets until those are re-pointed at
the Hostinger app cluster. Re-pointing `_SMOKE_ENDPOINTS` + data-layer context is a larger,
separate change and out of scope here — this fix only makes the section *appear*.
