# Bug: Trivy Operator Job Reconcile Errors panel query matches zero lines

**Branch:** `k3d-manager-v1.18.0`
**Files:** `scripts/etc/argocd/platform-ops/grafana-dashboard-argocd.yaml`, `scripts/tests/plugins/trivy_operator_observability.bats`

---

## Before You Start

- `git pull origin k3d-manager-v1.18.0`
- Read `memory-bank/activeContext.md` and `memory-bank/progress.md`
- Read both target files in full before editing
- Branch: `k3d-manager-v1.18.0` — do NOT commit to `main`

---

## Problem

The hub dashboard panel **"Trivy Operator Job Reconcile Errors"** (panel `id 12`, ArgoCD
Apps & Image Updater Hub, uid `argocd-image-updater-hub`) renders **No data** even while
trivy-operator is actively failing to scan images.

This is not an empty-state. It is a **false negative**: the panel's LogQL filters match
zero lines by construction, so real operator errors are invisible on the dashboard.

**Root cause:** the query filters on `controller="job"` AND `msg="Reconciler error"`.
Neither value exists on trivy-operator's error lines.

The operator's scan-job controller logs the failure itself and returns `nil`, so
controller-runtime never emits its generic `"Reconciler error"` wrapper. The error lines
look like this (fields: `level, ts, logger, msg, job, container, status.reason,
status.message, stacktrace` — **no `controller` field at all**):

```json
{"level":"error","ts":"2026-07-24T14:31:52Z","logger":"reconciler.scan job",
 "msg":"Scan job container","job":"trivy-system/scan-vulnerabilityreport-dd796cffd",
 "container":"grafana","status.reason":"Error","status.message":"... FATAL Fatal error ..."}
```

`controller` appears only on the operator's 218 startup lines (`Starting EventSource`,
`Starting Controller`, `Starting workers`) — and those never carry
`msg="Reconciler error"`. The conjunction of the two filters is therefore always empty.

---

## Reproduction

Measured against live Loki on the hub (`k3d-k3d-cluster`, `loki-gateway.monitoring.svc`),
6h window, while `scan-vulnerabilityreport-dd796cffd` was in `Error`:

| LogQL filter on `{namespace="trivy-system",pod=~"trivy-operator.*"}` | Matching lines |
|---|---|
| `\| json \| level="error"` | **13** |
| `\| json \| msg="Reconciler error"` | **0** |
| `\| json \| controller="job"` | **0** |

The underlying failure the panel should have been showing:

```
FATAL run error: image scan error: scan error: scan failed: failed analysis:
analyze error: pipeline error: failed to analyze layer (sha256:bd7eb6dc...):
walk error: failed to process the file: failed to analyze file:
failed to analyze usr/share/grafana/bin/grafana: unable to open
usr/share/grafana/bin/grafana: failed to open the temp file:
open /tmp/trivy-7/cached-file-1161811265: no such file or directory
```

---

## Fix

### Change 1 — `scripts/etc/argocd/platform-ops/grafana-dashboard-argocd.yaml`: correct the panel query

Line 230. Indentation is **14 leading spaces** — preserve it exactly.

**Exact old line:**

```
              "expr": "{namespace=\"trivy-system\",pod=~\"trivy-operator.*\"} | json | controller=\"job\" | msg=\"Reconciler error\" | line_format \"{{.msg}}: {{.namespace}}/{{.name}} controller={{.controller}} error={{.error}}\"",
```

**Exact new line:**

```
              "expr": "{namespace=\"trivy-system\",pod=~\"trivy-operator.*\"} | json | level=\"error\" | line_format \"{{.logger}}: {{.msg}} job={{.job_extracted}} container={{.container_extracted}} reason={{.status_reason}}\"",
```

**Why these exact field names in `line_format` — do NOT "simplify" them:**

LogQL's `json` parser renames two classes of key, and the old `line_format` referenced
fields that never existed (`.namespace`, `.name`, `.controller`, `.error`), which is why
even a matching line would have rendered blank:

| JSON key in the log | Usable in `line_format` as | Why renamed |
|---|---|---|
| `job` | `.job_extracted` | collides with the `job="fluent-bit"` stream label |
| `container` | `.container_extracted` | collides with the `container="trivy-operator"` stream label |
| `status.reason` | `.status_reason` | `.` is not valid in a label name |
| `level`, `logger`, `msg` | unchanged | no collision, no dot |

Using `.job` or `.container` would silently render the *stream label* values
(`fluent-bit` / `trivy-operator`) instead of the scan job and image — wrong, and not
obviously wrong on screen.

Verified live: this exact expression returns rows on the same stream where the old one
returns `[]`, rendering as:

```
reconciler.scan job: Scan job container job=trivy-system/scan-vulnerabilityreport-dd796cffd container=grafana reason=Error
```

Keep the panel `title`, `id`, `gridPos`, `datasource`, and `type` unchanged. Only the
`expr` string changes.

### Change 2 — `scripts/tests/plugins/trivy_operator_observability.bats`: retarget the assertion

`scripts/tests/plugins/trivy_operator_observability.bats:63` pins the **broken**
expression verbatim, so Change 1 fails the suite unless this is updated in the same commit.

**Exact old block (lines 63–64):**

```bash
  run grep -F -- '{namespace=\"trivy-system\",pod=~\"trivy-operator.*\"} | json | controller=\"job\" | msg=\"Reconciler error\"' "${DASH}"
  [ "${status}" -eq 0 ]
```

**Exact new block:**

```bash
  run grep -F -- '{namespace=\"trivy-system\",pod=~\"trivy-operator.*\"} | json | level=\"error\"' "${DASH}"
  [ "${status}" -eq 0 ]

  run grep -F -- 'msg=\"Reconciler error\"' "${DASH}"
  [ "${status}" -ne 0 ]
```

The second assertion is a **disappearance gate** — it proves the broken filter is gone
rather than merely proving the new one is present.

---

## Files Changed

| File | Change |
|------|--------|
| `scripts/etc/argocd/platform-ops/grafana-dashboard-argocd.yaml` | Panel 12 `expr`: filter on `level="error"`; `line_format` uses the parser's real field names |
| `scripts/tests/plugins/trivy_operator_observability.bats` | Retarget the pinned expr assertion + add disappearance gate for the old filter |

---

## Rules

- `shellcheck -S warning scripts/tests/plugins/trivy_operator_observability.bats` — zero new warnings
- Run the BATS suite: `bats scripts/tests/plugins/trivy_operator_observability.bats` — all tests pass
- Confirm the YAML still parses:
  `python3 -c "import yaml,sys; yaml.safe_load(open('scripts/etc/argocd/platform-ops/grafana-dashboard-argocd.yaml'))"`
- Confirm the embedded dashboard JSON still parses (no dangling commas, valid escaping)
- Run `_agent_audit` before reporting done — capture its exit code on its **own line**,
  never after `; echo`, and never through a pipe (`${PIPESTATUS[0]}` comes back empty
  through `| tee` / `| tail`)
- No other files touched

---

## Definition of Done

- [ ] Panel 12 `expr` in the dashboard YAML matches the new line byte-for-byte, at 14-space indent
- [ ] `grep -c 'msg=\\"Reconciler error\\"' scripts/etc/argocd/platform-ops/grafana-dashboard-argocd.yaml` → **0**
- [ ] `grep -c 'controller=\\"job\\"' scripts/etc/argocd/platform-ops/grafana-dashboard-argocd.yaml` → **0**
- [ ] BATS suite passes
- [ ] YAML + embedded JSON both parse
- [ ] `_agent_audit` exit code is 0
- [ ] Committed and pushed to `k3d-manager-v1.18.0`
- [ ] memory-bank updated with the commit SHA and task status, in a **separate commit**

**Commit message (exact):**

```
fix(observability): trivy reconcile panel query matched zero lines

The panel filtered on controller="job" and msg="Reconciler error", neither
of which exists on trivy-operator error lines, so real scan failures were
invisible. Filter on level="error" and use the json parser's actual field
names (job_extracted, container_extracted, status_reason) in line_format.
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than the two listed targets
- Do NOT commit to `main` — work on `k3d-manager-v1.18.0`
- Do NOT rename the panel title, change its `id`/`gridPos`, or touch any other panel
- Do NOT run `make restart-webhook`, apply the dashboard to a cluster, or run any live
  smoke — Claude does all live-cluster verification
- Do NOT "simplify" `.job_extracted` → `.job` or `.container_extracted` → `.container`;
  those resolve to the wrong values (see the table in Change 1)

---

## Out of Scope (do NOT fix here)

Two related findings were surfaced in the same investigation and are deliberately **not**
part of this task:

1. **`platform-ops` namespace does not exist** on either the hub or the app cluster, so
   the "App CVE Scan Decisions" panel is legitimately empty. That needs
   `deploy_argocd_platform_ops` re-run, plus an owner decision on whether it should stay
   a manual one-shot — a separate task.
2. **The Grafana image scan itself is failing** (`cached-file-...: no such file or
   directory`, likely trivy client/server cache or `/tmp` sizing). This spec only makes
   that failure *visible*; fixing it is a separate task.
