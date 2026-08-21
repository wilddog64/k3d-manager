# Bug: trivy versions are not explicitly pinned everywhere

**Branch:** `k3d-manager-v1.18.0`
**Files:** `scripts/etc/argocd/applicationsets/observability.yaml`,
`scripts/etc/argocd/applicationsets/observability-acg.yaml`,
`scripts/etc/helm/observability/trivy-operator-values.yaml`,
`scripts/etc/helm/observability/trivy-operator-acg-values.yaml`,
`scripts/tests/plugins/trivy_operator_observability.bats`

---

## Before You Start

- `git pull origin k3d-manager-v1.18.0`
- Read `memory-bank/activeContext.md` and `memory-bank/progress.md`
- Read all five target files in full before editing
- Branch: `k3d-manager-v1.18.0` — do NOT commit to `main`

---

## Problem

Three distinct trivy versions are in play. Only two are declared in this repo, and the
third floats with whatever the chart happens to default to:

| What | Where declared | Current value |
|---|---|---|
| Helm **chart** version | both application sets, `targetRevision` | `0.33.2` |
| **Operator** image tag | both values files, `image.tag` | `0.31.2` |
| **Scanner** image tag | *nowhere — chart default* | `0.71.1` (implicit) |

Two problems follow.

**1. The scanner version is invisible.** `trivy.image.tag` is never set in either values
file, so the trivy scanner binary version is whatever the pinned chart defaults to. Bumping
the chart silently changes the scanner. Nothing in the repo records which scanner version
is actually running.

**2. The chart↔operator offset is undocumented and reads as a mismatch.** trivy-operator's
chart version and app version are on different tracks — chart `0.33.2` ships appVersion
`0.31.2`. The pins are correct, but nothing states the relationship, and it has already
been misread once as version drift. The image tag `0.33.2` does not exist at all
(`mirror.gcr.io` returns HTTP 404 for it), so a "make these match" edit produces
`ImagePullBackOff`.

**Goal:** every trivy version used by this project is explicitly pinned in-repo, on the
newest matched set, with the chart↔appVersion relationship stated where it can be seen.

---

## Reproduction

```
$ grep -rn '0.33.2\|0.31.2' scripts/etc/
scripts/etc/argocd/applicationsets/observability.yaml:29:            targetRevision: 0.33.2
scripts/etc/argocd/applicationsets/observability-acg.yaml:30:            targetRevision: 0.33.2
scripts/etc/helm/observability/trivy-operator-values.yaml:4:  tag: "0.31.2"
scripts/etc/helm/observability/trivy-operator-acg-values.yaml:4:  tag: "0.31.2"
```

No `trivy.image.tag` anywhere — the scanner version is undeclared.

Upstream mapping, from `https://aquasecurity.github.io/helm-charts/index.yaml`:

```
chart 0.34.0  ->  appVersion 0.32.0    (newest, published 2026-07-08)
chart 0.33.2  ->  appVersion 0.31.2    (current pin)
```

Registry availability, verified against `mirror.gcr.io`:

```
aquasec/trivy-operator:0.32.0  -> HTTP 200
aquasec/trivy-operator:0.31.2  -> HTTP 200
aquasec/trivy-operator:0.33.2  -> HTTP 404   (chart version, not an image tag)
aquasec/trivy:0.72.0           -> HTTP 200
```

**Upgrade risk assessment — the full chart diff `0.33.2` → `0.34.0` is version labels only:**

```
Chart.yaml          appVersion 0.31.2 -> 0.32.0, version 0.33.2 -> 0.34.0
values.yaml         trivy.image.tag   0.71.1 -> 0.72.0
templates/specs/*   app.kubernetes.io/version label 0.31.2 -> 0.32.0  (6 files)
README.md           badges
crds/               BYTE-IDENTICAL — no CRD changes
```

No template logic changes, no CRD schema changes, no values-schema changes.

---

## Fix

Bump to the newest matched set — chart `0.34.0` / operator `0.32.0` / scanner `0.72.0` —
and pin the scanner explicitly.

Apply the **same** edits to both the hub and the ACG variant of each file. The two values
files are identical except for the Prometheus `release` selector on line 41; do not
disturb that difference.

### Change 1 — `scripts/etc/argocd/applicationsets/observability.yaml`: bump the chart

Line 29. Indentation is **12 leading spaces** — preserve it exactly.

**Exact old line:**

```
            targetRevision: 0.33.2
```

**Exact new line:**

```
            targetRevision: 0.34.0
```

### Change 2 — `scripts/etc/argocd/applicationsets/observability-acg.yaml`: bump the chart

Line 30, same 12-space indent. Same old line, same new line as Change 1.

### Change 3 — `scripts/etc/helm/observability/trivy-operator-values.yaml`: bump the operator, pin the scanner

Two edits in this file.

**3a — operator image tag, line 4, 2 leading spaces.**

**Exact old line:**

```
  tag: "0.31.2"
```

**Exact new line:**

```
  tag: "0.32.0"
```

**3b — pin the scanner image.** Insert the `image:` block as the first key under `trivy:`.

**Exact old block (lines 6–7):**

```yaml
trivy:
  ignoreUnfixed: true
```

**Exact new block:**

```yaml
trivy:
  image:
    registry: mirror.gcr.io
    repository: aquasec/trivy
    tag: "0.72.0"
  ignoreUnfixed: true
```

`registry` and `repository` match the chart defaults and are restated so the scanner image
is fully declared in-repo rather than half-inherited. Do NOT reorder or reindent the
existing `ignoreUnfixed` / `severity` / `resources` keys.

### Change 4 — `scripts/etc/helm/observability/trivy-operator-acg-values.yaml`: same two edits

Identical to Change 3 — same line numbers, same old blocks, same new blocks.

### Change 5 — `scripts/tests/plugins/trivy_operator_observability.bats`: retarget the pins

Three edits.

**5a — test 1, the chart pin.**

**Exact old block (lines 12–18):**

```bash
@test "trivy observability: charts pin trivy-operator 0.33.2 in both application sets" {
  run grep -F -- 'targetRevision: 0.33.2' "${HUB_APPSET}"
  [ "${status}" -eq 0 ]

  run grep -F -- 'targetRevision: 0.33.2' "${ACG_APPSET}"
  [ "${status}" -eq 0 ]
}
```

**Exact new block:**

```bash
@test "trivy observability: charts pin trivy-operator 0.34.0 in both application sets" {
  run grep -F -- 'targetRevision: 0.34.0' "${HUB_APPSET}"
  [ "${status}" -eq 0 ]

  run grep -F -- 'targetRevision: 0.34.0' "${ACG_APPSET}"
  [ "${status}" -eq 0 ]

  run grep -F -- 'targetRevision: 0.33.2' "${HUB_APPSET}"
  [ "${status}" -ne 0 ]

  run grep -F -- 'targetRevision: 0.33.2' "${ACG_APPSET}"
  [ "${status}" -ne 0 ]
}
```

**5b — test 2, the operator image tag.** This assertion currently covers only the hub
values file; the ACG file is unpinned by any test.

**Exact old block:**

```bash
  run grep -F -- 'tag: "0.31.2"' "${SETTINGS}"
  [ "${status}" -eq 0 ]
```

**Exact new block:**

```bash
  run grep -F -- 'tag: "0.32.0"' "${SETTINGS}"
  [ "${status}" -eq 0 ]

  run grep -F -- 'tag: "0.32.0"' "${ACG_SETTINGS}"
  [ "${status}" -eq 0 ]

  run grep -F -- 'tag: "0.31.2"' "${SETTINGS}"
  [ "${status}" -ne 0 ]

  run grep -F -- 'tag: "0.31.2"' "${ACG_SETTINGS}"
  [ "${status}" -ne 0 ]
```

**5c — add a new test for the scanner pin.** Append it immediately after test 2 (the
`chart values enable serviceMonitor scraping` test), before the next `@test`:

```bash
@test "trivy observability: scanner image tag is explicitly pinned in both values files" {
  run grep -F -- 'tag: "0.72.0"' "${SETTINGS}"
  [ "${status}" -eq 0 ]

  run grep -F -- 'tag: "0.72.0"' "${ACG_SETTINGS}"
  [ "${status}" -eq 0 ]
}
```

Do NOT assert on `repository: aquasec/trivy` — it is a substring of
`repository: aquasec/trivy-operator` and `grep -F` would match the operator line, making
the assertion pass for the wrong reason.

The suite goes from **6 tests to 7**.

---

## Files Changed

| File | Change |
|------|--------|
| `scripts/etc/argocd/applicationsets/observability.yaml` | chart `targetRevision` 0.33.2 → 0.34.0 |
| `scripts/etc/argocd/applicationsets/observability-acg.yaml` | chart `targetRevision` 0.33.2 → 0.34.0 |
| `scripts/etc/helm/observability/trivy-operator-values.yaml` | operator `image.tag` 0.31.2 → 0.32.0; pin `trivy.image` 0.72.0 |
| `scripts/etc/helm/observability/trivy-operator-acg-values.yaml` | same two edits |
| `scripts/tests/plugins/trivy_operator_observability.bats` | retarget chart + operator pins, add ACG coverage, add scanner-pin test |

---

## Rules

- `shellcheck -S warning scripts/tests/plugins/trivy_operator_observability.bats` — zero new warnings
- Run the BATS suite: `bats scripts/tests/plugins/trivy_operator_observability.bats` — **7/7 pass**
- All four YAML files still parse:
  `python3 -c "import yaml; [yaml.safe_load(open(p)) for p in ['scripts/etc/argocd/applicationsets/observability.yaml','scripts/etc/argocd/applicationsets/observability-acg.yaml','scripts/etc/helm/observability/trivy-operator-values.yaml','scripts/etc/helm/observability/trivy-operator-acg-values.yaml']]"`
- The two values files must still differ on **exactly one line** — the Prometheus `release`
  selector: `diff scripts/etc/helm/observability/trivy-operator-values.yaml scripts/etc/helm/observability/trivy-operator-acg-values.yaml` reports one hunk, `release: kube-prometheus-stack` vs `release: acg-kube-prometheus-stack`
- Run `_agent_audit` before reporting done — capture its exit code on its **own line**,
  never after `; echo`, and never through a pipe (`${PIPESTATUS[0]}` comes back empty
  through `| tee` / `| tail`)
- No other files touched

---

## Definition of Done

- [ ] `grep -c 'targetRevision: 0.33.2'` → **0** in both application sets
- [ ] `grep -c 'targetRevision: 0.34.0'` → **1** in each application set
- [ ] `grep -c '0.31.2'` → **0** in both values files
- [ ] `grep -c 'tag: "0.32.0"'` → **1** in each values file
- [ ] `grep -c 'tag: "0.72.0"'` → **1** in each values file
- [ ] BATS suite passes **7/7**
- [ ] All four YAML files parse
- [ ] The two values files differ on exactly one line (the `release` selector)
- [ ] `_agent_audit` exit code is 0
- [ ] Committed and pushed to `k3d-manager-v1.18.0`
- [ ] memory-bank updated with the commit SHA and task status, in a **separate commit**,
      then pushed — do NOT report done until BOTH commits are on
      `origin/k3d-manager-v1.18.0`

**Commit message — use the ENTIRE block below, subject AND body:**

```
chore(observability): pin every trivy version explicitly on the newest set

Chart 0.33.2 -> 0.34.0 and operator image 0.31.2 -> 0.32.0 (the chart's
matching appVersion), applied to both the hub and ACG variants. The trivy
scanner image was never declared and floated with the chart default; it is
now pinned to 0.72.0. Chart 0.34.0 differs from 0.33.2 only in version
labels — the CRDs are byte-identical.
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than the five listed targets
- Do NOT commit to `main` — work on `k3d-manager-v1.18.0`
- Do NOT set any image tag to `0.34.0`. That is the **chart** version and does not exist
  as an image tag — `mirror.gcr.io/aquasec/trivy-operator:0.34.0` returns HTTP 404 and
  would produce `ImagePullBackOff`
- Do NOT collapse the chart and app versions to one number, or "correct" one to match the
  other — the offset is upstream's versioning scheme, not a bug
- Do NOT reconcile the two values files into one, or remove the `release` selector
  difference on line 41 — they target different Prometheus stacks
- Do NOT apply anything to a cluster, run `argocd app sync`, reapply the application sets,
  or run any live smoke — Claude does all live-cluster verification

---

## Out of Scope (do NOT fix here)

1. **The hub's values source is pinned to a stale branch.** The live ArgoCD application
   reads its values from `targetRevision: k3d-manager-v1.16.0`, two releases behind. That
   is why a repo-only change does not reach the cluster until the application sets are
   reapplied. Rolling this out is Claude's live step, and the stale-branch pin is a
   separate finding.
2. **The Grafana image scan failure** (`cached-file-...: no such file or directory`) —
   whether 0.32.0 fixes it is unknown and is not a goal of this task.
