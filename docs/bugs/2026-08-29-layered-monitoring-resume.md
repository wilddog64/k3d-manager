# Layered `monitoring-resume` — resume to Layer 1 (lite) or Layer 2 (full)

**Filed:** 2026-08-29
**Area:** `scripts/plugins/observability.sh` — `observability_resume`; `Makefile`
**Type:** enhancement
**Builds on:** `docs/bugs/2026-08-29-pause-keep-grafana-up.md` (keep-list predicate, commit `8506f5fe`)
**Related:** `docs/bugs/2026-08-28-monitoring-pause-resume-toggle.md`,
`reference_argocd_pause_appset_managed_workload` (auto-memory)

## Problem

`observability_resume` (`make monitoring-resume`) always restores the **entire** stack
(Layer 2). There is no way to resume to a lighter posture. The user wants a `LAYER`
parameter so resume can bring the stack up to a named level.

## State ladder (target model)

| State | grafana | prometheus | alertmanager / loki / loki-gateway / ksm / operator / trivy | How |
|-------|:---:|:---:|:---:|---|
| paused | up¹ | 0 | 0 | `make monitoring-pause` |
| **Layer 1 (lite)** | up | up | 0 | `make monitoring-resume LAYER=1` |
| **Layer 2 (full)** | up | up | up | `make monitoring-resume LAYER=2` or no arg |

¹ Grafana stays up in `pause` via the existing keep-list (`8506f5fe`).

**Layer 1 = Grafana + Prometheus.** Prometheus is up, so **dashboards render live data**
(Prometheus datasource). Loki/Alertmanager/Trivy stay at 0.

### Accepted caveats (document, do not fix)
- Prometheus with Alertmanager down logs `Error sending alerts ... context deadline
  exceeded` — harmless.
- Grafana Loki datasource / Explore-logs shows errors while Loki is at 0. Prometheus
  dashboards are unaffected. Layer 1 is "metrics dashboards live", not "everything".

## Design

### 1. Layer arg + up-set config
`observability_resume` takes an optional first positional arg (the layer). Defaults and
overridable up-set:

```bash
local _layer; _layer="$(_observability_normalize_layer "${1:-}")"
local _l1_up="${OBSERVABILITY_LAYER1_UP:-kube-prometheus-stack-grafana prometheus-kube-prometheus-stack-prometheus}"
```

`OBSERVABILITY_LAYER1_UP` = space-separated deployment/statefulset **names** (matching the
`sed 's#.*/##'` names the sweep iterates), reusing the existing
`_observability_workload_in_keep_list` predicate for membership.

### 2. Layer normalizer (pure, BATS-testable)
```bash
function _observability_normalize_layer() {
  case "${1:-2}" in
    1) printf '1\n' ;;
    2|"") printf '2\n' ;;
    *) printf '2\n' ;;   # unknown → full, forgiving
  esac
}
```
An unrecognized value resolves to **2 (full)** — never leave the stack half-up by accident.

### 3. Dispatch in `observability_resume`
Early-branch to a helper for Layer 1; keep the **existing full-resume body unchanged** as
Layer 2:

```bash
if [[ "${_layer}" == "1" ]]; then
  _observability_resume_layer1 "${_ctx}" "${_argons}" "${_apps}" "${_nss}" "${_l1_up}"
  return
fi
# ... existing Layer-2 (full) body, verbatim ...
```

### 4. `_observability_resume_layer1` — partial resume
Key rule (from `reference_argocd_pause_appset_managed_workload`): a partial posture must
**keep ArgoCD auto-sync suspended** (`automated:null`), or selfHeal reconciles the app back
to its git-desired full state and resurrects the components we want at 0. So Layer 1 does
NOT restore `automated`; it drives replicas explicitly and is idempotent from any start
state (pause, L1, or L2).

```bash
function _observability_resume_layer1() {
  local _ctx="$1" _argons="$2" _apps="$3" _nss="$4" _l1_up="$5"
  _info "[observability] Resuming to Layer 1 (lite: Grafana + Prometheus)..."
  local _app
  for _app in ${_apps}; do
    _kubectl get application "${_app}" -n "${_argons}" --context "${_ctx}" >/dev/null 2>&1 || continue
    _kubectl patch application "${_app}" -n "${_argons}" --context "${_ctx}" \
      --type merge -p '{"spec":{"syncPolicy":{"automated":null}}}' >/dev/null 2>&1 || true
  done
  local _ns _type _name _repl
  for _ns in ${_nss}; do
    _kubectl get namespace "${_ns}" --context "${_ctx}" >/dev/null 2>&1 || continue
    for _type in deployment statefulset; do
      while read -r _name; do
        [[ -z "${_name}" ]] && continue
        if _observability_workload_in_keep_list "${_name}" "${_l1_up}"; then
          _repl=1
        else
          _repl=0
        fi
        _kubectl scale "${_type}/${_name}" -n "${_ns}" --context "${_ctx}" \
          --replicas="${_repl}" >/dev/null 2>&1 || true
      done < <(_kubectl get "${_type}" -n "${_ns}" --context "${_ctx}" \
        -o name 2>/dev/null | sed 's#.*/##')
    done
  done
  _kubectl patch prometheus kube-prometheus-stack-prometheus -n monitoring --context "${_ctx}" \
    --type merge -p '{"spec":{"replicas":1}}' >/dev/null 2>&1 || true
  _kubectl patch alertmanager kube-prometheus-stack-alertmanager -n monitoring --context "${_ctx}" \
    --type merge -p '{"spec":{"replicas":0}}' >/dev/null 2>&1 || true
  _info "[observability] Layer 1 up: grafana + prometheus (live dashboards). Alertmanager/Loki/Trivy remain at 0."
}
```

Notes:
- Prometheus runs from its already-rendered config secret; the **operator is not required**
  to keep an existing prometheus StatefulSet serving. Since the operator stays at 0, the
  direct `kubectl scale statefulset` on prometheus is not reverted. The CR patch to
  replicas=1 is for consistency (inert while the operator is down).
- Everything not in `_l1_up` is explicitly scaled to 0, so `resume LAYER=1` is a true
  "set posture to lite" from any starting state (including a currently-full L2).

### 5. Makefile
```
monitoring-resume:
	./scripts/k3d-manager observability_resume $(LAYER)
```
Empty `$(LAYER)` passes nothing → default 2 (full), preserving current behavior. Update the
help text (`Makefile` ~707):
```
make monitoring-resume [LAYER=1|2]  Resume hub monitoring: 1=Grafana+Prometheus, 2=full (default)
```

## Constraints (repo rules)
- Minimal patch: do NOT rewrite the existing Layer-2 body — only add the arg parse, the
  early dispatch, the two new helpers, and the Makefile arg/help.
- Keep indentation, `${var}` quoting, `_`-prefixed private naming, LF endings. No inline
  comments beyond `_info` breadcrumbs. `set -euo pipefail` stays.
- Do NOT touch `scripts/lib/` or `scripts/lib/acg/` subtrees.
- Do NOT modify `observability_pause` (done in `8506f5fe`).

## BATS coverage (Codex — extend `scripts/tests/observability_keep_list.bats`
or add `scripts/tests/observability_resume_layer.bats`)
Test `_observability_normalize_layer` (pure, no cluster):
1. `_observability_normalize_layer 1` → `1`
2. `_observability_normalize_layer 2` → `2`
3. `_observability_normalize_layer ""` (no/empty arg) → `2`
4. `_observability_normalize_layer 9` → `2`
5. `_observability_normalize_layer foo` → `2`

(The up-set membership is already covered by the existing keep-list predicate tests.)

Gates Codex runs locally and pastes real output for:
- `bats scripts/tests/observability_*.bats` — all pass.
- `shellcheck scripts/plugins/observability.sh` — no NEW findings vs. baseline (pre-existing
  SC2016 at ~line 542 is acceptable).
- `bash -n scripts/plugins/observability.sh` — clean.
- `grep -n 'observability_resume\|_observability_resume_layer1\|_observability_normalize_layer\|OBSERVABILITY_LAYER1_UP' scripts/plugins/observability.sh`

## Commit — DO NOT PUSH (Codex)
Stage ONLY `scripts/plugins/observability.sh`, the BATS file, and `Makefile`. `git status`
first — do not sweep unrelated files. Commit on `k3d-manager-v1.27.0`:
`feat(observability): layered monitoring-resume (LAYER=1 lite / LAYER=2 full)`.
Report the local SHA + `git show --stat HEAD` + gate output. Claude pushes after verifying.

## Live verification — CLAUDE ONLY (Codex must not touch the cluster)
On the hub (`k3d-k3d-cluster`), from a paused or full state:
1. `make monitoring-resume LAYER=1` → assert grafana **1/1** AND prometheus STS **1/1**;
   alertmanager/loki/loki-gateway/ksm/operator/trivy-operator → **0/0**.
2. Prove live data: Grafana `/api/health` = ok AND a Prometheus query returns series
   (e.g. `kubectl exec` grafana → query prometheus `up`, or `make status` Prometheus 200 +
   Grafana login 200).
3. `make monitoring-resume LAYER=2` (or no arg) → full stack back; `make status` → HEALTHY.
4. Round-trip: `make monitoring-resume LAYER=1` again from full → drops back to lite
   (idempotent from L2).

## Out of scope
- Reduced scrape-rate / retention tuning for the lite tier (that is the separate
  config-tune lever #1/#2). Layer 1 here changes **which components run**, not their config.
