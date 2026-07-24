# Bug: `observability-acg` ApplicationSet names its Loki app bare `loki` — inconsistent and collision-prone

**Branch:** `k3d-manager-v1.18.0`
**Files (edit ONLY these two):**
- `scripts/etc/argocd/applicationsets/observability-acg.yaml`
- `scripts/tests/plugins/observability_acg_loki_naming.bats` (new)

**Classification:** Bugfix in `docs/bugs/` (exempt from the max-5-plan limit).

---

## Before You Start

- `git pull origin k3d-manager-v1.18.0`
- Read `memory-bank/activeContext.md` and `memory-bank/progress.md` — this is the
  "`loki` Application inconsistently named" flag item.
- Read IN FULL before editing:
  - `scripts/etc/argocd/applicationsets/observability-acg.yaml` — the whole file
  - `scripts/etc/argocd/applicationsets/observability.yaml` — the **hub** set, which
    already models the exact end-state this change copies (`hub-loki` + a `releaseName`
    conditional that pins the Helm release to `loki`). You are making the ACG set match
    that shape.
- Branch: `k3d-manager-v1.18.0` — do NOT commit to `main`.
- **This is a text-only change. You do NOT apply it to any cluster.** See
  `## What NOT to Do` and `## Live rollout — Claude only`.

---

## Problem

The `observability-acg` ApplicationSet generates three Applications. Two are prefixed,
one is not:

| generator element `name` | live Application |
|---|---|
| `acg-kube-prometheus-stack` | `acg-kube-prometheus-stack` |
| `acg-trivy-operator` | `acg-trivy-operator` |
| **`loki`** | **`loki`** |

The bare `loki` sits in the same ArgoCD namespace (`cicd`) next to the **hub's** Loki
Application, which is named `hub-loki`. So the hub's Loki and the app-cluster's Loki are
`hub-loki` and `loki` — the app-cluster one is the odd member of its own set *and* is
indistinguishable by name from a hub Application. Renaming it to `acg-loki` makes it
consistent with its two siblings and unambiguous against `hub-loki`.

**Why the hub is the template:** the hub set already went through this exact rename. It
names the element `hub-loki` but keeps the Helm **release** name `loki` via a conditional
in the chart source's `helm` block:

```yaml
# scripts/etc/argocd/applicationsets/observability.yaml, chart source helm block
          helm:
            releaseName: '{{if eq .name "hub-loki"}}loki{{else}}{{.name}}{{end}}'
            valueFiles:
              - '$values/{{.valuesFile}}'
```

Pinning the release name is what makes the rename safe from Helm's side: the Application is
renamed but the in-cluster Helm release keeps the name `loki`, so its resources
(StatefulSet, Service, ConfigMaps) are **adopted**, not recreated under a new release name.

The ACG set has **no** `releaseName` at all today, so its Loki release currently defaults
to the Application name `loki`. You will add the same conditional so that after the rename
the release name is still `loki`.

---

## Reproduction

```
$ kubectl --context k3d-k3d-cluster -n cicd get applications \
    -o custom-columns=NAME:.metadata.name | grep -i loki
hub-loki
loki
```

`loki` should read `acg-loki`, matching `acg-kube-prometheus-stack` / `acg-trivy-operator`.

---

## Fix

Two edits, both in `scripts/etc/argocd/applicationsets/observability-acg.yaml`.

### Change 1 — rename the generator element `loki` → `acg-loki`

**Exact old block:**

```yaml
          - name: loki
            namespace: monitoring
            chart: loki
            repoURL: https://grafana-community.github.io/helm-charts
            targetRevision: 18.2.0
            valuesFile: scripts/etc/helm/observability/loki-values.yaml
```

**Exact new block** (only the first line changes):

```yaml
          - name: acg-loki
            namespace: monitoring
            chart: loki
            repoURL: https://grafana-community.github.io/helm-charts
            targetRevision: 18.2.0
            valuesFile: scripts/etc/helm/observability/loki-values.yaml
```

### Change 2 — pin the Helm release name so the rename adopts the existing release

**Exact old block:**

```yaml
          helm:
            valueFiles:
              - '$values/{{.valuesFile}}'
            parameters:
              - name: prometheus.prometheusSpec.externalLabels.cluster
                value: '{{.clusterLabel}}'
```

**Exact new block** (add exactly one `releaseName:` line as the first key under `helm:`):

```yaml
          helm:
            releaseName: '{{if eq .name "acg-loki"}}loki{{else}}{{.name}}{{end}}'
            valueFiles:
              - '$values/{{.valuesFile}}'
            parameters:
              - name: prometheus.prometheusSpec.externalLabels.cluster
                value: '{{.clusterLabel}}'
```

**Why the conditional, and why it must NOT be `releaseName: loki` unconditionally — do
NOT "simplify":** the `template` block applies to **all three** generator elements. An
unconditional `releaseName: loki` would rename the Helm releases of
`acg-kube-prometheus-stack` and `acg-trivy-operator` to `loki` too — three different charts
fighting over one release name in three namespaces, an immediate outage. The conditional
gives `acg-loki` the release `loki` and leaves the other two at their own name
(`{{.name}}`), which is byte-identical to their current implicit release name. This is the
exact structure the hub set uses; mirror it.

---

## Change 3 — new test: `scripts/tests/plugins/observability_acg_loki_naming.bats`

**Exact new file contents:**

```bash
#!/usr/bin/env bats

APPSET="scripts/etc/argocd/applicationsets/observability-acg.yaml"

@test "observability-acg names the Loki element acg-loki, consistent with its siblings" {
  run grep -F 'name: acg-loki' "${APPSET}"
  [ "${status}" -eq 0 ]
}

@test "observability-acg no longer generates a bare 'loki' element" {
  run grep -Ec '^[[:space:]]*-[[:space:]]*name:[[:space:]]*loki[[:space:]]*$' "${APPSET}"
  [ "${output}" -eq 0 ]
}

@test "observability-acg pins the Helm release name to loki via the acg-loki conditional" {
  run grep -F "releaseName: '{{if eq .name \"acg-loki\"}}loki{{else}}{{.name}}{{end}}'" "${APPSET}"
  [ "${status}" -eq 0 ]
}

@test "observability-acg still parses as YAML after the rename" {
  run python3 -c "import yaml; list(yaml.safe_load_all(open('${APPSET}')))"
  [ "${status}" -eq 0 ]
}
```

The second test is a **disappearance gate**: it proves the bare `loki` element is gone,
not merely that `acg-loki` was added.

---

## Files Changed

| File | Change |
|------|--------|
| `scripts/etc/argocd/applicationsets/observability-acg.yaml` | Rename element `loki` → `acg-loki`; add `releaseName` conditional pinning the release to `loki` |
| `scripts/tests/plugins/observability_acg_loki_naming.bats` | New 4-test suite (present + disappearance + release-name + YAML-parse gates) |

---

## Rules

- `bats scripts/tests/plugins/observability_acg_loki_naming.bats` — prints `1..4`, all
  pass. **Paste the `1..4` line.**
- YAML still parses:
  `python3 -c "import yaml; list(yaml.safe_load_all(open('scripts/etc/argocd/applicationsets/observability-acg.yaml')))"`
- `shellcheck -S warning scripts/tests/plugins/observability_acg_loki_naming.bats` — zero
  warnings
- **`_agent_audit` — you MUST `git add` the two target files BEFORE running it.** Every
  check inside `_agent_audit` (`scripts/lib/agent_rigor.sh`) reads
  `git diff --cached` / `git show :<file>` — **staged content only**. Run on an unstaged
  tree it audits nothing, prints only the dispatcher banner, and returns 0 — a false green,
  not a pass. Correct order:

  ```
  git add scripts/etc/argocd/applicationsets/observability-acg.yaml \
          scripts/tests/plugins/observability_acg_loki_naming.bats
  git diff --cached --name-only
  ./scripts/k3d-manager _agent_audit
  rc=$?
  echo "rc=$rc"
  ```

  Capture the exit code on its **own line** — never after `; echo`, never through a pipe.
  **Report it as `rc=<n>`, not as its stdout.** `running under bash version …` is the
  dispatcher's startup banner, not audit output. Paste the
  `git diff --cached --name-only` list too — it must show exactly the two files.
- No other files touched.

---

## Definition of Done

- [ ] Element renamed `loki` → `acg-loki` (Change 1)
- [ ] `releaseName` conditional added as the first key under `helm:` (Change 2)
- [ ] `grep -Ec '^[[:space:]]*-[[:space:]]*name:[[:space:]]*loki[[:space:]]*$' scripts/etc/argocd/applicationsets/observability-acg.yaml` → **0**
- [ ] `grep -cF 'name: acg-loki' scripts/etc/argocd/applicationsets/observability-acg.yaml` → **1**
- [ ] New BATS suite passes → `1..4`
- [ ] YAML parses
- [ ] `_agent_audit` **`rc=0`** (staged first)
- [ ] Committed and pushed to `k3d-manager-v1.18.0`
- [ ] memory-bank updated with the commit SHA and task status, in a **separate commit**,
      then pushed — do NOT report done until BOTH commits are on
      `origin/k3d-manager-v1.18.0`

**Commit message — use the ENTIRE block below, subject AND body:**

```
fix(observability): name the ACG Loki app acg-loki for consistency

The observability-acg ApplicationSet named its two other elements
acg-kube-prometheus-stack and acg-trivy-operator but the third just
loki, which is inconsistent with its siblings and indistinguishable by
name from the hub's hub-loki Application in the same cicd namespace.
Rename the element to acg-loki and pin the Helm release name to loki via
the same conditional the hub set uses, so the live release is adopted
rather than recreated when the set is reapplied.
```

---

## Live rollout — Claude only (NOT part of this task)

Committing this YAML changes **nothing** on any cluster: the ApplicationSet on the hub is
frozen at whatever branch it was last applied from (that is the whole values-branch-drift
lesson), so your committed rename is inert until someone reapplies the set. That someone is
**Claude, not you.**

The reapply is dangerous and must be staged, which is exactly why it is not yours: the live
`loki` Application carries `resources-finalizer.argocd.argoproj.io` and predates any
`preserveResourcesOnDeletion` flag, so a naive reapply makes the ApplicationSet controller
delete the old `loki` app and its finalizer **cascade-deletes the live Loki workload** — the
same failure mode that deleted the `shopping-cart-apps` namespace on 2026-07-19
(`docs/bugs/2026-07-19-services-git-appset-duplicate-application-names.md`). Claude will
strip the finalizer from the live `loki` app first, then apply the renamed set so `acg-loki`
adopts the existing `loki` release. This paragraph is documentation of Claude's follow-up,
not an instruction to you.

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than the two listed targets
- Do NOT commit to `main` — work on `k3d-manager-v1.18.0`
- Do NOT run ANY cluster command: no `kubectl apply`, no `kubectl patch`, no
  `argocd app sync`, no reapplying the ApplicationSet, no `deploy_observability_acg`, no
  smoke. **Claude does all live-cluster work.** The BATS + grep + YAML-parse gates are your
  entire test surface.
- Do NOT make `releaseName` unconditional (`releaseName: loki`) — it would collide the
  other two charts' releases (see Change 2)
- Do NOT also rename `acg-kube-prometheus-stack` or `acg-trivy-operator` — they are already
  consistent; only the Loki element is in scope
- Do NOT add an `_agent_audit` allowlist entry or raise `AGENT_AUDIT_MAX_IF`

---

## Out of Scope

1. **The live reapply / finalizer strip** — Claude's step (see above).
2. **Wiring `argocd_check_values_branch` into `make status`** — a separate spec
   (`docs/bugs/2026-07-24-make-status-values-branch-drift-wiring.md`).
