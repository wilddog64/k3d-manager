# Copilot Review Findings — PR #104 (v1.14.0)

**PR:** [#104](https://github.com/wilddog64/k3d-manager/pull/104) — feat: v1.14.0 — observability & multi-cluster reliability hardening
**Date:** 2026-07-12
**Reviewer:** GitHub Copilot
**Outcome:** all findings verified genuine and fixed; CI was green before and after.

Copilot raised 4 threads. Three are the same metric-name typo across code/test/doc; the fourth is a
context-vs-cluster-name bug in the freshly-shipped Workstream 3 Phase 1 code.

---

## Finding 1 — Trivy ClusterRole metric name typo (code)

**File:** `scripts/plugins/observability.sh:655`
**Flagged:** the infra-security report queried `trivy_clusterrole_clusterrbacassments` — missing the
`esse` — so the ClusterRole RBAC portion of the report silently returned empty. Every other file in
the repo (`grafana-dashboard-argocd.yaml`, `argocd_metrics_servicemonitor.bats`, and the mock at
`observability.bats:443`) uses the correct `trivy_clusterrole_clusterrbacassessments`.

**Before:**
```
sum by (name,resource_kind,severity) (trivy_clusterrole_clusterrbacassments{severity=~"High|Critical"}) > 0
```
**After:**
```
sum by (name,resource_kind,severity) (trivy_clusterrole_clusterrbacassessments{severity=~"High|Critical"}) > 0
```

## Finding 2 — auth mount derived from cluster entry, not context (code)

**File:** `scripts/plugins/vault.sh:1850`
**Flagged:** `configure_vault_app_auth_for_context` passed `${cluster_name}` (the kubeconfig
`context.cluster` entry) to `_vault_app_auth_mount`, but the helper is context-keyed and the intent
(design doc `2026-07-07-app-cluster-vault-portability.md`) is `kubernetes-<sanitized-context>`. On
providers where the kube-context name differs from the cluster entry (EKS/AKS/GKE), Vault would write
a mount name the ESO ClusterSecretStore never reads — the SecretStore side (`eso.sh`) and the
shopping-cart CSS auth block (`shopping_cart.sh`) both derive from the **context**, so `vault.sh` was
the odd one out, breaking the three-site parity and the per-context isolation guarantee. On the
current k3d/hostinger fleet context == cluster so it happened to work, masking the bug.

**Before:** `app_mount="$(_vault_app_auth_mount "${cluster_name}")"`
**After:**  `app_mount="$(_vault_app_auth_mount "${app_context}")"`

`cluster_name` is still used for the server/CA-data lookups (lines 1804–1809), which legitimately key
on the cluster entry — only the mount argument was wrong.

## Finding 3 — same metric typo in the alert-automation spec (doc)

**File:** `docs/bugs/2026-07-08-trivy-findings-should-trigger-actionable-alerts.md:21`
Referenced the misspelled metric, which would mislead the follow-up alert-rule work. Corrected to
`trivy_clusterrole_clusterrbacassessments`.

## Finding 4 — test asserts the typo, locking it in (test)

**File:** `scripts/tests/lib/observability.bats:466`
The grep assertion matched the misspelled query, so the suite passed against the broken code. Because
the mock at `:443` already emitted results under the *correct* metric name, the test was internally
inconsistent. Corrected the assertion to the right spelling; after the `observability.sh:655` fix the
emitted query and the assertion now agree.

---

## Verification

- `grep -rn clusterrbacassments` → 0 occurrences repo-wide.
- `shellcheck -S warning scripts/plugins/vault.sh scripts/plugins/observability.sh` → clean.
- `env -i HOME=… PATH=… bats scripts/tests/lib/observability.bats` → `1..12` all pass.
- `env -i … bats scripts/tests/plugins/vault_app_auth.bats` → `1..15` all pass (the `app_context`
  change disturbed no test).
- `env -i … bats scripts/tests/plugins/shopping_cart_css_auth_block.bats` → `1..5` all pass.
- `./scripts/k3d-manager _agent_audit` → exit 0.

## Root cause & process note

- The metric typo predates this PR (it lives in v1.12-era observability code) but rode along because
  the guarding BATS assertion greps the **same** literal string as the code — a test that asserts a
  string the code emits cannot catch a typo shared by both. **Process rule:** when a test pins a
  Prometheus/PromQL query string, the mock's `case` arm and the assertion must be derived from the
  metric's canonical name, not copy-pasted from the code under test, so a shared typo desyncs them.
- The vault finding is a spec-level miss: the Phase 1 spec's exact code block itself said
  `${cluster_name}`, so Codex implemented it faithfully. **Process rule:** when a helper is documented
  as context-keyed and sibling call sites (eso, shopping_cart) key on context, the spec's example must
  pass the context too — cross-check the argument against the other mount sites before handoff.
