# Bugfix: v1.14.0 — Loki logs panels render empty templates and raw JSON

**Branch:** `k3d-manager-v1.14.0`
**Files:** `scripts/etc/argocd/platform-ops/grafana-dashboard-argocd.yaml`, `scripts/tests/plugins/argocd_metrics_servicemonitor.bats`

---

## Problem

Panels `6` (`Image Updater Processing Results`) and `12` (`Trivy Operator Job Reconcile Errors`)
render as visually identical walls of promtail `kubernetes_*` labels, because in each panel the
actual message content is destroyed before it reaches the screen.

**Root cause — three independent defects:**

1. **Panel 6 has no line filter.** The stream selector is followed directly by `| json`, so *every*
   `argocd-image-updater` log line is fed to the `regexp` stage. Non-matching lines produce empty
   capture groups, and the trailing `line_format` emits the template anyway.

2. **Panel 12 has no `line_format`.** The query filters correctly but never reformats, so Grafana
   displays the raw fluent-bit envelope (`{"time":"…","_p":"F","level":"error",…}`) instead of the
   message.

3. **All three logs panels set `showLabels: true`.** Combined with `| json`, this renders the full
   promtail label set inline on every row. The label set is identical across panels because it comes
   from promtail, not the application — which is why the panels look interchangeable.
   `enableLogDetails: true` already exposes these on expand.

**Not a regression from `ae088b34`.** Panels 6 and 12 predate it and were outside that spec's scope.
The drilldown dedupe merely removed the clutter that was hiding this.

**Explicitly NOT a bug:** the `\\d` escaping in panel 6's `regexp` is correct. The ConfigMap stores
`\\d`, LogQL unquotes it to `\d`, and it matches. Do not "fix" it.

---

## Reproduction

Against the live infra cluster (`k3d-k3d-cluster`), port-forward Loki and run panel 6's query
exactly as deployed over a 6h window:

```
rows: 200
  applications=0 images_considered=0 images_skipped=0 images_updated=0 errors=0   x96
  applications= images_considered= images_skipped= images_updated= errors=        x104
```

**104 of 200 rows (52%) render every value blank.** Adding `|= "Processing results"` yields
`180/180` populated, zero blank.

Panel 12's query as deployed returns the raw JSON envelope:

```
{"time":"2026-07-04T13:26:28.158771137Z","_p":"F","level":"error","ts":"…","msg":"Reconciler error","controller":"job",…}
```

Both replacement queries in this spec were validated against live Loki before it was written.

---

## Fix

### Change 1 — `grafana-dashboard-argocd.yaml`: add a line filter to panel 6 (line 129)

**Exact old block:**

```
              "expr": "{namespace=\"cicd\",pod=~\"argocd-image-updater.*\"} | json | line_format \"{{.log}}\" | regexp \"Processing results: applications=(?P<applications>\\\\d+) images_considered=(?P<images_considered>\\\\d+) images_skipped=(?P<images_skipped>\\\\d+) images_updated=(?P<images_updated>\\\\d+) errors=(?P<errors>\\\\d+)\" | line_format \"applications={{.applications}} images_considered={{.images_considered}} images_skipped={{.images_skipped}} images_updated={{.images_updated}} errors={{.errors}}\"",
```

**Exact new block:**

```
              "expr": "{namespace=\"cicd\",pod=~\"argocd-image-updater.*\"} |= \"Processing results\" | json | line_format \"{{.log}}\" | regexp \"Processing results: applications=(?P<applications>\\\\d+) images_considered=(?P<images_considered>\\\\d+) images_skipped=(?P<images_skipped>\\\\d+) images_updated=(?P<images_updated>\\\\d+) errors=(?P<errors>\\\\d+)\" | line_format \"applications={{.applications}} images_considered={{.images_considered}} images_skipped={{.images_skipped}} images_updated={{.images_updated}} errors={{.errors}}\"",
```

The only change is inserting `|= \"Processing results\" ` between `.*\"}` and `| json`. Everything
after `| json` is byte-identical — copy it, do not retype it.

---

### Change 2 — `grafana-dashboard-argocd.yaml`: add a `line_format` to panel 12 (line 256)

**Exact old block:**

```
              "expr": "{namespace=\"trivy-system\",pod=~\"trivy-operator.*\"} | json | controller=\"job\" | msg=\"Reconciler error\"",
```

**Exact new block:**

```
              "expr": "{namespace=\"trivy-system\",pod=~\"trivy-operator.*\"} | json | controller=\"job\" | msg=\"Reconciler error\" | line_format \"{{.msg}}: {{.namespace}}/{{.name}} controller={{.controller}} error={{.error}}\"",
```

---

### Change 3 — `grafana-dashboard-argocd.yaml`: turn off inline labels on all three logs panels

There are exactly **three** occurrences of this line (lines `122`, `200`, `249`), each with 12
leading spaces. Replace **all three**.

**Exact old block:**

```
            "showLabels": true,
```

**Exact new block:**

```
            "showLabels": false,
```

---

### Change 4 — `argocd_metrics_servicemonitor.bats`: drop the tautology (lines 173–174)

`grep -F 'description'` matches the word anywhere in the file, including `"description"` keys. It
asserts nothing.

**Exact old block:**

```bash
  run grep -F -- 'description' "${DASH}"
  [ "${status}" -eq 0 ]

  run grep -F -- 'Trivy Infra Findings Drilldown' "${DASH}"
```

**Exact new block:**

```bash
  run grep -F -- 'Trivy Infra Findings Drilldown' "${DASH}"
```

---

### Change 5 — `argocd_metrics_servicemonitor.bats`: append three new tests

These were required by `docs/bugs/2026-07-10-trivy-drilldown-panels-redundant-and-banner-newlines-literal.md`
(Change 2) but were never shipped in `ae088b34`. They are the negative assertions that prevent
reintroduction of panels `10`/`16`/`17` and the `\\n` escape. The third test guards this spec's fix.

**Append verbatim to the end of the file** (after the closing `}` of the last test):

```bash

@test "metrics: dashboard has exactly one trivy drilldown table and banner" {
  run grep -cF -- '### Trivy drilldown' "${DASH}"
  [ "${status}" -eq 0 ]
  [ "${output}" -eq 1 ]

  run grep -F -- '"title": "Trivy Drilldown",' "${DASH}"
  [ "${status}" -ne 0 ]

  run grep -F -- 'Trivy Infra RBAC Drilldown' "${DASH}"
  [ "${status}" -ne 0 ]

  run grep -F -- 'Trivy ClusterRole Drilldown' "${DASH}"
  [ "${status}" -ne 0 ]

  run grep -F -- '"url": "?viewPanel=16"' "${DASH}"
  [ "${status}" -ne 0 ]
}

@test "metrics: dashboard banner uses real newlines not literal backslash-n" {
  run grep -F -- '\\n' "${DASH}"
  [ "${status}" -ne 0 ]
}

@test "metrics: loki logs panels filter their streams and format their lines" {
  run grep -F -- '{namespace=\"cicd\",pod=~\"argocd-image-updater.*\"} |= \"Processing results\" | json' "${DASH}"
  [ "${status}" -eq 0 ]

  run grep -F -- '| line_format \"{{.msg}}: {{.namespace}}/{{.name}} controller={{.controller}} error={{.error}}\"' "${DASH}"
  [ "${status}" -eq 0 ]

  run grep -F -- '"showLabels": true' "${DASH}"
  [ "${status}" -ne 0 ]

  run grep -cF -- '"showLabels": false' "${DASH}"
  [ "${status}" -eq 0 ]
  [ "${output}" -eq 3 ]
}
```

---

## Before You Start

1. Read `memory-bank/activeContext.md` and `memory-bank/progress.md`.
2. `git checkout k3d-manager-v1.14.0 && git branch --show-current` — must print `k3d-manager-v1.14.0`.
   If it prints anything else, **STOP**.
3. `git pull origin k3d-manager-v1.14.0`
4. Read both target files in full.

**Stop-gates — run these before editing. If any value differs, STOP and report:**

```bash
grep -cF '"showLabels": true' scripts/etc/argocd/platform-ops/grafana-dashboard-argocd.yaml   # must be 3
grep -cF '|= \"Processing results\"' scripts/etc/argocd/platform-ops/grafana-dashboard-argocd.yaml  # must be 0
grep -cF '### Trivy drilldown' scripts/etc/argocd/platform-ops/grafana-dashboard-argocd.yaml  # must be 1
grep -c '@test' scripts/tests/plugins/argocd_metrics_servicemonitor.bats                      # must be 12
```

---

## Files Changed

| File | Change |
|------|--------|
| `scripts/etc/argocd/platform-ops/grafana-dashboard-argocd.yaml` | panel 6 line filter; panel 12 `line_format`; `showLabels: false` ×3 |
| `scripts/tests/plugins/argocd_metrics_servicemonitor.bats` | drop `description` tautology; append 3 tests |

---

## Rules

- The embedded dashboard JSON must still parse:
  `yq -r '.data."argocd-image-updater-hub.json"' scripts/etc/argocd/platform-ops/grafana-dashboard-argocd.yaml | jq -e . >/dev/null`
- `env -i HOME="$HOME" PATH="$PATH" bats scripts/tests/plugins/argocd_metrics_servicemonitor.bats` — must report `1..15`, all pass
- `./scripts/k3d-manager _agent_audit` — must exit 0
- No other files touched

---

## Definition of Done

- [ ] Panel 6 expr contains `|= \"Processing results\"` immediately after the stream selector
- [ ] Panel 12 expr ends with the `line_format` from Change 2
- [ ] `grep -cF '"showLabels": true'` returns 0; `grep -cF '"showLabels": false'` returns 3
- [ ] Embedded dashboard JSON parses under `jq -e .`
- [ ] `bats scripts/tests/plugins/argocd_metrics_servicemonitor.bats` reports `1..15`, all pass
- [ ] `./scripts/k3d-manager _agent_audit` exits 0
- [ ] Committed and pushed to `k3d-manager-v1.14.0`
- [ ] memory-bank updated with the commit SHA and task status, **as a separate commit after the push**

**Commit message (exact):**
```
fix(observability): filter and format loki logs panels
```

**Memory-bank commit message (exact):**
```
docs(memory-bank): record loki logs panel fix
```

---

## Commit sequence — not a judgment call

The two target files may **not** be committed together with the memory-bank files: `## What NOT to Do`
forbids touching files outside the listed targets, and memory-bank is not a target. But the Definition
of Done requires memory-bank to record the commit SHA — and a commit cannot contain its own SHA.
Therefore, unconditionally:

1. `git add` **only** the two target files → commit with the exact message above
2. `git push origin k3d-manager-v1.14.0`
3. `git log origin/k3d-manager-v1.14.0 --oneline -1` → this is the SHA to record
   (`git push` updates the local `refs/remotes/origin/…` ref; no `git fetch` needed)
4. Edit `memory-bank/activeContext.md` + `memory-bank/progress.md` with that SHA
5. `git add` **only** the two memory-bank files → commit with the memory-bank message above
6. `git push origin k3d-manager-v1.14.0`

Do not report done until step 6 succeeds.

---

## Deferred — do NOT do in this task

- Do NOT change the `\\d` escaping in panel 6's `regexp`. It is correct.
- Do NOT renumber panel ids.
- Do NOT add a line filter to panel 9 (`App CVE Scan Decisions`) — it already has `|= \"[app-cve-scan]\"`.
- Do NOT deploy the ConfigMap to any cluster. Claude applies it.

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than the four listed above (two targets + two memory-bank)
- Do NOT commit to `main` — work on `k3d-manager-v1.14.0`
- Do NOT stage `docs/bugs/2026-07-08-refresh-output-is-healthy.md` (untracked, unrelated)
