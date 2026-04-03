# P2: Jenkins PV Template Has Hardcoded `namespace: jenkins`

**Date:** 2026-03-01
**Reported:** Observed during infra cluster rebuild (post v0.3.0 merge)
**Status:** FIXED — template now uses `$JENKINS_NAMESPACE` and `_create_jenkins_pv_pvc` exports it before `envsubst`
**Severity:** P2
**Type:** Bug — hardcoded namespace breaks `--namespace` override

---

## What Happened

When running `deploy_jenkins --namespace cicd`, the PV/PVC step fails:

```
error: the namespace from the provided object "jenkins" does not match the namespace "cicd".
You must pass '--namespace=jenkins' to perform this operation.
kubectl command failed (1): kubectl apply -f /tmp/jenkins-home-pv.GYjwSM.yaml -n cicd
ERROR: failed to execute kubectl apply -f /tmp/jenkins-home-pv.GYjwSM.yaml -n cicd: 1
```

The PVC template (`scripts/etc/jenkins/jenkins-home-pv.yaml.tmpl`) has `namespace: jenkins` hardcoded:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: jenkins-home
  namespace: jenkins   # ← hardcoded; ignores $JENKINS_NAMESPACE
```

`_create_jenkins_pv_pvc` calls `envsubst < "$jenkins_pv_template"` but the template never references `$JENKINS_NAMESPACE`, so substitution has no effect.

---

## Root Cause

**File:** `scripts/etc/jenkins/jenkins-home-pv.yaml.tmpl` line 13

The namespace field is a string literal `jenkins`, not `$JENKINS_NAMESPACE`.

`_create_jenkins_pv_pvc` in `scripts/plugins/jenkins.sh` (line ~458) calls:

```bash
envsubst < "$jenkins_pv_template" > "$jenkinsyamfile"
_kubectl apply -f "$jenkinsyamfile" -n "$jenkins_namespace"
```

When `jenkins_namespace=cicd`, kubectl sees a metadata namespace of `jenkins` but the `-n cicd` flag and rejects it.

---

## Related Issue

`JENKINS_NAMESPACE` env var also not respected — `deploy_jenkins` defaults to `jenkins` at line 1281:
```bash
jenkins_namespace="${jenkins_namespace:-jenkins}"  # never falls back to $JENKINS_NAMESPACE env var
```
This is a separate (related) bug — see companion issue.

---

## Fix

**File:** `scripts/etc/jenkins/jenkins-home-pv.yaml.tmpl`

```yaml
# Before:
  namespace: jenkins

# After:
  namespace: $JENKINS_NAMESPACE
```

**File:** `scripts/plugins/jenkins.sh` (`_create_jenkins_pv_pvc`)

```bash
  export JENKINS_NAMESPACE="$jenkins_namespace"
  envsubst < "$jenkins_pv_template" > "$jenkinsyamfile"
```

By exporting the namespace before `envsubst`, the template substitution now picks up the namespace selected via flag/env var.

---

## Resolution & Verification (2026-03-02)

- Updated the PV template and `_create_jenkins_pv_pvc` export as described above so the rendered YAML always matches the target namespace.
- Ran `PATH="/opt/homebrew/bin:$PATH" bats scripts/tests/lib/test_auth_cleanup.bats` ✅ to ensure Jenkins helper behavior remains intact.
- Attempted `PATH="/opt/homebrew/bin:$PATH" bats scripts/tests/plugins/jenkins.bats`, but the test file does not exist in `scripts/tests/plugins/`; no plugin-specific suite was run.
- `shellcheck scripts/plugins/jenkins.sh` ✅

---

## Impact

- Jenkins cannot be deployed to `cicd` namespace (or any non-default namespace) without manual workaround
- v0.3.0 namespace rename to `cicd` is blocked for Jenkins
- Workaround: manually create the PVC in the target namespace, but deploy still fails at apply step

---

## Workaround (Operational)

Jenkins skipped in current infra rebuild. Deploy to default `jenkins` namespace if Jenkins is needed immediately:

```bash
VAULT_NS=secrets ./scripts/k3d-manager deploy_jenkins --enable-ldap --enable-vault
```

---

## Triage

| Factor | Assessment |
|---|---|
| Operational impact | High — Jenkins cannot move to `cicd` ns without fix |
| Fix urgency | P2 — blocks v0.3.0 namespace rename goal for Jenkins |
| Fix risk | Low — template one-liner + export in function |
| Severity | P2 — core v0.3.0 feature blocked |
