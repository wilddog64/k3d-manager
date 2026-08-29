# Keep Grafana up while `monitoring-pause` scales the rest to zero

**Filed:** 2026-08-29
**Area:** `scripts/plugins/observability.sh` — `observability_pause` / `observability_resume`
**Type:** enhancement (behavior change to an existing feature)
**Related:** `docs/bugs/2026-08-28-monitoring-pause-resume-toggle.md` (the toggle itself),
`docs/bugs/2026-08-28-status-monitoring-paused-false-fail.md`

## Problem

`observability_pause` (`make monitoring-pause`) scales **every** Deployment and
StatefulSet in the `monitoring` and `trivy-system` namespaces to `replicas=0` via a
namespace-wide sweep (`observability.sh:696-708`). Grafana
(`deployment/kube-prometheus-stack-grafana`, namespace `monitoring`) is swept in with
everything else, so **the Grafana UI is unreachable while paused** — you cannot log in
to look at anything until you resume the whole stack.

The user wants Grafana to stay **loginable** during a pause. Layer-1/Layer-2 model:
- **Layer 1 (default):** full stack running.
- **Layer 2 (paused):** heavy scrape/store components down to reclaim CPU, **but Grafana
  stays up** so the dashboard UI is reachable on demand.

## Desired behavior

`monitoring-pause` scales down prometheus, alertmanager, loki, kube-state-metrics,
kube-prometheus-stack-operator, and trivy-operator (unchanged), **but leaves Grafana at
`replicas=1`**. `monitoring-resume` is unchanged (its scale-to-1 sweep already covers
Grafana; scaling an already-running Grafana to 1 is a no-op).

### Accepted caveat (document, do not fix)
With prometheus/loki scaled to 0, Grafana panels show **"No data" / datasource errors** —
Grafana itself runs fine, but there is nothing to query. "Keep Grafana up" means the UI
is **reachable and loginable**, not that panels render live data. This is the intended
trade-off (reach the UI without resuming the whole stack), and is noted here so it is not
later mistaken for a bug.

## Design

### 1. Config seam (overridable, safe default)
Add a keep-list variable, defaulted in-function like the existing `OBSERVABILITY_*` vars:

```bash
local _keep="${OBSERVABILITY_PAUSE_KEEP:-kube-prometheus-stack-grafana}"
```

Space-separated workload **names** (no `deployment/` prefix — matches the `sed 's#.*/##'`
names the sweep already iterates). Default keeps only Grafana. Setting
`OBSERVABILITY_PAUSE_KEEP=""` restores the old all-or-nothing behavior.

### 2. Pure predicate helper (BATS-testable seam)
Extract the match as a small pure-logic function so it can be unit-tested per repo
convention (`scripts/tests/` is pure logic only — no cluster mocks):

```bash
function _observability_workload_in_keep_list() {
  local _name="$1" _keep="$2"
  case " ${_keep} " in
    *" ${_name} "*) return 0 ;;
    *) return 1 ;;
  esac
}
```

Space-padding on both sides gives **whole-word** matching — `grafana` must NOT match
`kube-prometheus-stack-grafana`, and vice-versa.

### 3. Skip keep-listed workloads in the pause sweep
In `observability_pause`, inside the `deployment statefulset` sweep
(`observability.sh:700-705`), skip any workload on the keep-list:

```bash
while read -r _name; do
  [[ -z "${_name}" ]] && continue
  if _observability_workload_in_keep_list "${_name}" "${_keep}"; then
    _info "[observability]   ${_ns}/${_name}: kept up (keep-list)"
    continue
  fi
  _kubectl scale "${_type}/${_name}" -n "${_ns}" --context "${_ctx}" \
    --replicas=0 >/dev/null 2>&1 || true
done < <(...)
```

Declare `local _keep=...` alongside the other `local` declarations at the top of
`observability_pause`. **`observability_resume` is not modified** (minimal patch).

### 4. Makefile help text
`Makefile:706` — update the one-line help so the behavior is discoverable:

```
make monitoring-pause    Scale hub monitoring to zero, keep Grafana up (~1 core back)
```

(Reclaimed CPU is marginally less than the current "~1.1 cores" because idle Grafana
stays running — a few tens of millicores. Keep the number honest but do not over-fuss.)

## Constraints (repo rules)
- Minimal patch — no unsolicited refactor of the rest of `observability_pause/resume`.
- Maintain existing indentation, quoting, naming (`_`-prefixed privates, `${var}` quoting).
- `set -euo pipefail` already in effect in the plugin — do not weaken.
- LF endings, no inline comments beyond the one `_info` breadcrumb.
- Do NOT change the ArgoCD `automated=null` / appset-pause logic — Grafana staying at 1
  makes the kube-prometheus-stack Application *less* OutOfSync, not more (see
  `reference_argocd_pause_appset_managed_workload`).

## BATS coverage (Codex — new test file `scripts/tests/observability_keep_list.bats`)
Source the plugin (or the function) and assert on `_observability_workload_in_keep_list`:

1. name **in** list → returns 0
   (`_observability_workload_in_keep_list kube-prometheus-stack-grafana "kube-prometheus-stack-grafana"`).
2. name **not in** list → returns 1
   (`... prometheus-kube-prometheus-stack-prometheus-0 "kube-prometheus-stack-grafana"`).
3. **empty** keep-list → returns 1 (old behavior: nothing exempted).
4. **whole-word** guard: `grafana` against keep-list `kube-prometheus-stack-grafana`
   → returns 1 (no substring false-match); and the reverse.
5. **multi-entry** keep-list: `loki-0` in `"kube-prometheus-stack-grafana loki-0"` → 0.

Gates Codex must pass locally and report (with command output, not a "done"):
- `bats scripts/tests/observability_keep_list.bats` — all pass.
- `shellcheck scripts/plugins/observability.sh` — no **new** findings vs. baseline.
- `bash -n scripts/plugins/observability.sh` — clean.
- Disappearance/idempotence sanity: `grep -n 'OBSERVABILITY_PAUSE_KEEP' scripts/plugins/observability.sh`
  returns the new default line; keep-list skip present in the pause sweep only.

## Live verification — CLAUDE ONLY (not Codex)
Codex must **not** touch the live hub cluster (serialize-live-sandbox rule). After Codex
pushes, Claude runs on the real hub (`k3d-k3d-cluster`):
1. `make monitoring-pause` → assert `deployment/kube-prometheus-stack-grafana` stays
   `1/1`; prometheus/alertmanager/loki/ksm/operator/trivy-operator → 0.
2. Grafana reachable while paused: `make status` shows `Grafana login: HTTP 200`
   (or `curl -sk https://grafana.shopping-cart.local/api/health` = 200).
3. Node `top` confirms CPU still meaningfully reclaimed.
4. `make monitoring-resume` → all back to 1; `make status` → **HEALTHY**.

## Out of scope
- A true "light tier" where a trimmed prometheus keeps feeding Grafana. This spec only
  keeps the **UI reachable**; live data during pause is explicitly out of scope.
