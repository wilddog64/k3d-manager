# Fix Plan: Jenkins Cannot Deploy to `cicd` Namespace

_Established: 2026-03-01_

---

## Problem Summary

Two related bugs prevent `deploy_jenkins` from deploying to any non-default namespace:

### Bug 1 (P2 — blocking): PV template has `namespace: jenkins` hardcoded

`scripts/etc/jenkins/jenkins-home-pv.yaml.tmpl` contains a literal `namespace: jenkins`
in the PVC metadata. `_create_jenkins_pv_pvc` renders this via `envsubst` but never
references `$JENKINS_NAMESPACE` in the template, so substitution has no effect.
When `deploy_jenkins --namespace cicd` is run, kubectl sees namespace `jenkins` in the
object but `-n cicd` on the command — and rejects it.

**Error observed:**
```
error: the namespace from the provided object "jenkins" does not match the namespace "cicd".
You must pass '--namespace=jenkins' to perform this operation.
ERROR: failed to execute kubectl apply -f /tmp/jenkins-home-pv.GYjwSM.yaml -n cicd: 1
```

### Bug 2 (P3 — related): `JENKINS_NAMESPACE` env var ignored by `deploy_jenkins`

`deploy_jenkins` builds the local `jenkins_namespace` variable from `--namespace` CLI flag or
positional arg. If neither is given, line 1281 defaults to the string `"jenkins"` — it does
not fall back to the `$JENKINS_NAMESPACE` environment variable.

```bash
# Current (line 1281):
jenkins_namespace="${jenkins_namespace:-jenkins}"

# Should be:
jenkins_namespace="${jenkins_namespace:-${JENKINS_NAMESPACE:-jenkins}}"
```

---

## Files to Change

| File | Line | Change |
|---|---|---|
| `scripts/etc/jenkins/jenkins-home-pv.yaml.tmpl` | 13 | `namespace: jenkins` → `namespace: $JENKINS_NAMESPACE` |
| `scripts/plugins/jenkins.sh` | ~451 (`_create_jenkins_pv_pvc`) | export `JENKINS_NAMESPACE` before `envsubst` |
| `scripts/plugins/jenkins.sh` | 1281 (`deploy_jenkins`) | fallback to `${JENKINS_NAMESPACE:-jenkins}` |

---

## Codex Implementation Spec

> **Codex:** implement all three changes on branch `fix/jenkins-cicd-namespace`.
> No other files should need changing. Run the bats tests to confirm no regressions.

### Change 1 — `scripts/etc/jenkins/jenkins-home-pv.yaml.tmpl` line 13

```yaml
# Before:
  namespace: jenkins

# After:
  namespace: $JENKINS_NAMESPACE
```

### Change 2 — `scripts/plugins/jenkins.sh` inside `_create_jenkins_pv_pvc`

The function receives `jenkins_namespace` as `$1` (already resolved by the caller).
Before calling `envsubst`, export it so the template substitution works:

```bash
function _create_jenkins_pv_pvc() {
   local jenkins_namespace=$1
   ...
   # ADD THIS before envsubst call:
   export JENKINS_NAMESPACE="$jenkins_namespace"

   envsubst < "$jenkins_pv_template" > "$jenkinsyamfile"
   _kubectl apply -f "$jenkinsyamfile" -n "$jenkins_namespace"
   ...
}
```

Exact location: after line ~456 (the `mktemp` line), before the `envsubst` call.

### Change 3 — `scripts/plugins/jenkins.sh` line 1281

```bash
# Before:
jenkins_namespace="${jenkins_namespace:-jenkins}"

# After:
jenkins_namespace="${jenkins_namespace:-${JENKINS_NAMESPACE:-jenkins}}"
```

---

## What NOT to Change

- `vault-seed-wrapper.yaml` — `namespace: jenkins` appears 3× but this file is NOT
  applied automatically by `deploy_jenkins`. It is a utility template for manual use.
  Do NOT change it in this PR (separate cleanup task).
- All other Jenkins templates — only `jenkins-home-pv.yaml.tmpl` is affected.
- No changes to bats tests needed — existing tests should still pass. Run them to verify.

---

## Tests

No new tests needed for these fixes. Verify existing suite passes:

```bash
PATH="/opt/homebrew/bin:$PATH" bats scripts/tests/plugins/jenkins.bats
PATH="/opt/homebrew/bin:$PATH" bats scripts/tests/lib/test_auth_cleanup.bats
shellcheck scripts/plugins/jenkins.sh
```

---

## Verification (Claude will do after merge)

```bash
# Deploy Jenkins to cicd namespace — must succeed end-to-end
VAULT_NS=secrets ./scripts/k3d-manager deploy_jenkins --namespace cicd --enable-ldap --enable-vault

# Verify pods in cicd namespace
kubectl get pods -n cicd

# Smoke test
kubectl get externalsecret -n cicd
```

---

## Agent Workflow

```
Codex
  └── implements 3 changes on branch fix/jenkins-cicd-namespace
  └── runs: bats jenkins.bats, test_auth_cleanup.bats, shellcheck
  └── commits, does NOT open PR

Gemini
  └── verifies fixes are correct, bats green, shellcheck clean
  └── posts verification result

Claude
  └── opens PR after Gemini sign-off
  └── deploys Jenkins to cicd ns on infra cluster
  └── verifies pods Running in cicd namespace

Owner
  └── approves PR
```

---

## Status

- [x] Bugs documented (`docs/issues/2026-03-01-jenkins-pv-template-hardcoded-namespace.md`)
- [x] Plan written
- [ ] Codex: implement 3 changes ← **current task**
- [ ] Gemini: verify
- [ ] Claude: PR + deploy Jenkins to `cicd`
