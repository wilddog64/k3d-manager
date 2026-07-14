# Trivy Standalone → ClientServer migration (fix multi-container scan cache-lock)

**Branch:** `k3d-manager-v1.15.0`
**Files:** `scripts/etc/helm/observability/trivy-operator-values.yaml`, `scripts/etc/helm/observability/trivy-operator-acg-values.yaml`, `scripts/tests/plugins/trivy_operator_observability.bats`

---

## Problem

`trivy-operator` runs in **Standalone** scan mode: every scan job pod initializes its own
Trivy vulnerability DB into its own `/home/scanner/.cache`. When the operator fans out
concurrent scan jobs against a **multi-container** target (e.g. the Grafana pod, plus the
2 other scanners running at the same time), the jobs contend on the Trivy cache lock and
time out, surfacing as **`exit=1`** scan-job failures.

The related OOMKill symptom was already fixed in `d434e289` (raised scan-job memory
`512Mi→1Gi`), which eliminated the `exit-137` OOMKills. The **residual, documented
secondary symptom** is the `exit=1` cache-lock timeout on multi-container targets — its
real fix is migrating off Standalone mode.

**Root cause:** Standalone mode gives each concurrent scan job its own DB init + cache
lock. Three scanners hitting a multi-container pod serialize on that lock and time out.

---

## Fix

Enable the trivy-operator chart's **built-in Trivy server** (`operator.builtInTrivyServer:
true`). The chart then:

1. Deploys a single shared `trivy-server` StatefulSet that holds one vulnerability DB.
2. Automatically sets `trivy.mode: "ClientServer"` and
   `trivy.serverURL: "http://trivy-service.trivy-system:4954"` in the operator ConfigMap
   (this branch overrides the `trivy.mode` value — no `serverURL` needs to be supplied).

Scan jobs become lightweight **clients** that offload DB download and analysis to the
shared server, so there is no per-job cache to lock and the concurrent multi-container
contention disappears.

Server resources stay at the chart default (requests `200m`/`512Mi`, limits `1`/`1Gi`) and
the server cache uses the chart-default 5Gi PVC on the cluster's default storage class —
adequate for both the laptop k3d hub and the ACG/Hostinger app cluster. The client
`trivy.resources` block is left unchanged: in ClientServer mode it applies to the now-
lightweight client jobs, so it is over-provisioned but safe, and leaving it keeps the diff
minimal.

### Change 1 — `scripts/etc/helm/observability/trivy-operator-values.yaml`: enable built-in server

**Exact old block:**

```yaml
operator:
  scanJobTTL: 1h
  vulnerabilityReportsPlugin: Trivy
```

**Exact new block:**

```yaml
operator:
  scanJobTTL: 1h
  builtInTrivyServer: true
  vulnerabilityReportsPlugin: Trivy
```

### Change 2 — `scripts/etc/helm/observability/trivy-operator-acg-values.yaml`: enable built-in server

**Exact old block:**

```yaml
operator:
  scanJobTTL: 1h
  vulnerabilityReportsPlugin: Trivy
```

**Exact new block:**

```yaml
operator:
  scanJobTTL: 1h
  builtInTrivyServer: true
  vulnerabilityReportsPlugin: Trivy
```

> Both files are identical except for the `serviceMonitor.labels.release` line
> (`kube-prometheus-stack` vs `acg-kube-prometheus-stack`) — do **not** touch that line in
> either file. Only add the one `builtInTrivyServer: true` line under `operator:`.

### Change 3 — `scripts/tests/plugins/trivy_operator_observability.bats`: lock the migration

Insert immediately **before** the existing test
`@test "trivy observability: acg trivy application set uses the acg-specific values file" {`:

```bash
@test "trivy observability: both values files enable the built-in trivy server (ClientServer mode)" {
  run grep -F -- 'builtInTrivyServer: true' "${SETTINGS}"
  [ "${status}" -eq 0 ]

  run grep -F -- 'builtInTrivyServer: true' "${ACG_SETTINGS}"
  [ "${status}" -eq 0 ]
}
```

---

## Files Changed

| File | Change |
|------|--------|
| `scripts/etc/helm/observability/trivy-operator-values.yaml` | Add `operator.builtInTrivyServer: true` |
| `scripts/etc/helm/observability/trivy-operator-acg-values.yaml` | Add `operator.builtInTrivyServer: true` |
| `scripts/tests/plugins/trivy_operator_observability.bats` | +1 test locking the built-in-server contract |

**Do NOT touch:** the `serviceMonitor.labels.release` line in either values file, the
`image`/`trivy.resources` blocks, the ApplicationSet files, or any other test.

---

## Before You Start

1. `git pull origin k3d-manager-v1.15.0`
2. Read `memory-bank/activeContext.md` and `memory-bank/progress.md` — confirm this Trivy
   ClientServer migration matches the recorded v1.15.0 next step.
3. Read this spec in full, then read both values files and the bats file before editing.
4. Add the aquasec helm repo if not present (needed for the render gate):
   `helm repo add aquasec https://aquasecurity.github.io/helm-charts && helm repo update aquasec`

---

## Rules

- **Render gate (both files):** each must template cleanly in built-in-server mode. Run:
  ```
  helm template t aquasec/trivy-operator --version 0.33.2 -n trivy-system \
    -f scripts/etc/helm/observability/trivy-operator-values.yaml
  helm template t aquasec/trivy-operator --version 0.33.2 -n trivy-system \
    -f scripts/etc/helm/observability/trivy-operator-acg-values.yaml
  ```
  Each render must (a) succeed, (b) contain `trivy.mode: "ClientServer"`, (c) contain
  `trivy.serverURL: "http://trivy-service.trivy-system:4954"`, (d) contain a
  `kind: StatefulSet` (the trivy-server), and (e) still carry the correct
  `release:` label (`kube-prometheus-stack` for the hub file,
  `acg-kube-prometheus-stack` for the acg file).
- **Test gate:** `env -i HOME="$HOME" PATH="$PATH" bats scripts/tests/plugins/trivy_operator_observability.bats`
  must report `1..6` with all passing (5 existing + 1 new).
- No files touched other than the three listed targets. No unsolicited refactors.

---

## Definition of Done

- [ ] `operator.builtInTrivyServer: true` added to BOTH values files (nothing else changed
      in them).
- [ ] Both `helm template` renders succeed and show `ClientServer` mode + the trivy-server
      StatefulSet + the correct `release:` labels.
- [ ] 1 BATS test added; `bats scripts/tests/plugins/trivy_operator_observability.bats` →
      `1..6` all pass.
- [ ] Committed and pushed to `origin/k3d-manager-v1.15.0`.
- [ ] `memory-bank/activeContext.md` and `memory-bank/progress.md` updated with the commit
      SHA and task status (as a **separate** commit from the implementation).

**Commit message (exact — full subject, body, and both trailers):**
```
fix(observability): migrate trivy to ClientServer via built-in server

Enable operator.builtInTrivyServer in both trivy-operator values files so the
chart deploys one shared trivy-server StatefulSet and switches scan jobs to
ClientServer mode. Standalone mode gave each concurrent scan job its own DB
cache, so 3 scanners hitting a multi-container pod contended on the cache lock
and failed with exit=1; a single shared server DB removes that contention.
Client scan-job resources and the serviceMonitor release labels are unchanged.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01WDPY5ZzfbrUihTsRB4v3np
```

---

## What NOT to Do

- Do NOT create a PR.
- Do NOT skip pre-commit hooks (`--no-verify`).
- Do NOT modify any file other than the three listed targets.
- Do NOT commit to `main` — work on `k3d-manager-v1.15.0`.
- Do NOT change the `serviceMonitor.labels.release` line, the `trivy.resources` block, the
  `image` block, or the ApplicationSet files.
- Do NOT set `trivy.mode` or `trivy.serverURL` by hand — `builtInTrivyServer: true` wires
  both automatically; setting them manually is redundant and can break the render.

---

## Follow-up (Claude, after merge — NOT part of this handoff)

The `trivy-operator` ArgoCD Application auto-syncs (`selfHeal`), so this commit will reach
both clusters via git — unlike the imperatively-applied Grafana dashboard ConfigMap. After
Codex ships, Claude verifies live: `trivy-server-0` pod `Running`, operator ConfigMap shows
`trivy.mode: ClientServer`, and recent scan jobs complete without `exit=1` on
multi-container targets (the Grafana pod is the canonical repro).
