# P3: `deploy_jenkins` Ignores `JENKINS_NAMESPACE` Env Var

**Date:** 2026-03-01
**Reported:** Observed during infra cluster rebuild (post v0.3.0 merge)
**Status:** OPEN
**Severity:** P3
**Type:** Bug — env var override silently ignored

---

## What Happened

When running:

```bash
JENKINS_NAMESPACE=cicd ./scripts/k3d-manager deploy_jenkins --enable-ldap --enable-vault
```

Jenkins deployed to the `jenkins` namespace instead of `cicd`. The `JENKINS_NAMESPACE=cicd` env var was silently ignored.

---

## Root Cause

**File:** `scripts/plugins/jenkins.sh` line 1281

```bash
jenkins_namespace="${jenkins_namespace:-jenkins}"   # ← defaults to "jenkins" literal, ignores $JENKINS_NAMESPACE env var
```

The local variable `jenkins_namespace` is initialized from the `--namespace` CLI flag (or positional arg). If neither is provided, it falls back to the literal string `jenkins` instead of `${JENKINS_NAMESPACE:-jenkins}`.

---

## Fix

**File:** `scripts/plugins/jenkins.sh` line 1281

```bash
# Before:
jenkins_namespace="${jenkins_namespace:-jenkins}"

# After:
jenkins_namespace="${jenkins_namespace:-${JENKINS_NAMESPACE:-jenkins}}"
```

---

## Impact

- `JENKINS_NAMESPACE=cicd deploy_jenkins` deploys to `jenkins` instead of `cicd`
- v0.3.0 namespace rename to `cicd` requires `--namespace cicd` CLI flag to work
- Related to companion bug: PV template hardcoded `namespace: jenkins` (separate issue)

---

## Triage

| Factor | Assessment |
|---|---|
| Operational impact | Medium — `--namespace cicd` flag workaround exists |
| Fix urgency | P3 — workaround available |
| Fix risk | Low — one-line change with consistent env var pattern |
| Severity | P3 — inconsistent with other plugins that do check env vars |
