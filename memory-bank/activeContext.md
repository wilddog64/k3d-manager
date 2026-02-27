# Active Context – k3d-manager

## Current Branch: `main` (as of 2026-02-27)

`ldap-develop` merged to `main` via PR #2. **v0.1.0 released.**

## Current Focus (as of 2026-02-27)

**v0.1.0 shipped ✅** — PR #2 merged, tagged, released.

Next task: add `system:auth-delegator` ClusterRoleBinding to `deploy_vault` so new clusters
get it automatically (currently applied manually to m2-air).

- Stage 2 CI: ✅ fully green (`test_vault`, `test_eso`, `test_istio` on m2-air)
- PR #2 merged to `main` at 2026-02-27T20:09:45Z
- v0.1.0 released: https://github.com/wilddog64/k3d-manager/releases/tag/v0.1.0

### Session Notes (2026-02-27)
- Stage 2 CI complete; `stage2` required status check added to branch protection
- SMB CSI Phase 1 skip guard: Codex implemented, Gemini validated on m4-air
- Jenkins k8s agents: ✅ Gemini validated on m4-air. Evidence added below.
- Jenkins agent templates: port `8081`→`8080`, labels `linux-agent`→`linux`, `kaniko-agent`→`kaniko`
- `values.yaml` → `values-default.yaml.tmpl`, envsubst wired in `jenkins.sh` line 1552
- Jenkins k8s agents fully fixed by Codex — SA mismatch, admin credential placeholders, crumb issuer, port alignment
- Jenkins admin password zsh glob issue: always wrap `-u user:pass` in quotes. See `docs/issues/2026-02-27-jenkins-admin-password-zsh-glob.md`
- Smoke test TLS race fixed: retry logic added in `bin/smoke-test-jenkins.sh`

---

## Current Priorities

### Priority 1: Jenkins Kubernetes agents (VALIDATED ✅)

**Status:** Linux/kaniko agent validation complete on m4-air. All jobs SUCCESS. SMB CSI work continues separately (macOS skip guard still active).

**What changed on 2026-02-27:**
- ServiceAccount mismatch resolved (`docs/issues/2026-02-27-jenkins-k8s-agent-serviceaccount-mismatch.md`).
- JCasC admin placeholders preserved so envsubst runs for all templates (`docs/issues/2026-02-27-jenkins-jcasc-admin-credentials-empty.md`).
- Crumb issuer regression fixed + scripts updated (`docs/issues/2026-02-27-jenkins-crumb-issuer-xpath-forbidden.md`).
- Controller Service/VirtualService ports aligned to 8080 so agents can connect (`docs/issues/2026-02-27-jenkins-service-port-mismatch.md`).
- ConfigMap now renders concrete namespaces (`kubectl get configmap jenkins-jenkins-config-02-kubernetes-agents.yaml | grep jenkinsUrl`).
- E2E proof (Gemini m4-air):
  - `CLUSTER_PROVIDER=orbstack PATH="/opt/homebrew/bin:$PATH" ./scripts/k3d-manager deploy_jenkins --enable-vault` — smoke test 4/4 passes.
  - `PATH="/opt/homebrew/bin:$PATH" JENKINS_URL="http://127.0.0.1:8083" ./bin/run-k8s-agent-tests.sh` — both linux + kaniko jobs trigger and finish.
  - `timeout 120 kubectl -n jenkins get pods -w | grep agent` shows pods progressing Pending → Running → Completed.
  - `curl -sk -u jenkins-admin:*** http://127.0.0.1:8083/job/01-linux-agent-test/lastBuild/api/json | jq '.result'` → `"SUCCESS"` (same for kaniko).

**Next steps:**
- Automate the port-forward workflow (helper script) so Jenkins smoke + agent tests can run outside `deploy_jenkins` without manual tunnels.
- Continue SMB CSI Phase 2 (NFS-based swap) per `docs/plans/smb-csi-macos-workaround.md`.

**Evidence (Gemini — m4-air):**
```bash
# Step 0 — prove you are on m4-air with latest code
$ hostname
m4-air.local
$ git -C ~/src/gitrepo/personal/k3d-manager pull
Already up to date.
$ git -C ~/src/gitrepo/personal/k3d-manager log --oneline -5
f5f3e75 (HEAD -> ldap-develop, origin/ldap-develop) memory-bank: update Gemini validation instructions for Jenkins agents
822fe54 jenkins: fix k8s agents — SA mismatch, envsubst, crumb issuer, port alignment
3731759 docs: add multi-agent workflow screenshot to README
6e866fa memory-bank: compact activeContext.md 532 → 159 lines
056c0f7 clinerules: add memory-bank update rule — no ✅ without evidence

# Step 1 — deploy Jenkins with Vault
$ CLUSTER_PROVIDER=orbstack PATH="/opt/homebrew/bin:$PATH" ./scripts/k3d-manager deploy_jenkins --enable-vault
... (smoke test 4/4 passes) ...
deploy exit: 0

# Step 2 — verify ConfigMap has concrete namespace
$ kubectl -n jenkins get configmap jenkins-jenkins-config-02-kubernetes-agents.yaml -o jsonpath='{.data.*}' | grep jenkinsUrl
        jenkinsUrl: "http://jenkins.jenkins.svc.cluster.local:8080"

# Step 3 — verify RBAC and agent service exist
$ kubectl -n jenkins get role,rolebinding | grep agent
role.rbac.authorization.k8s.io/jenkins-agent-manager     2026-02-25T01:15:34Z
role.rbac.authorization.k8s.io/jenkins-schedule-agents   2026-02-25T01:15:34Z
rolebinding.rbac.authorization.k8s.io/jenkins-agent-manager      Role/jenkins-agent-manager     2d14h
rolebinding.rbac.authorization.k8s.io/jenkins-schedule-agents    Role/jenkins-schedule-agents   2d14h
$ kubectl -n jenkins get svc jenkins-agent
NAME            TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)     AGE
jenkins-agent   ClusterIP   10.43.83.134   <none>        50000/TCP   2d14h

# Step 4 — run the agent test suite
$ PATH="/opt/homebrew/bin:$PATH" JENKINS_URL="http://127.0.0.1:8083" ./bin/run-k8s-agent-tests.sh
=== Triggering Jenkins K8s Agent Tests ===
Getting Jenkins crumb...
Got crumb: Jenkins-Crumb
Triggering job: 01-linux-agent-test
  ✓ Job '01-linux-agent-test' triggered successfully
Triggering job: 02-kaniko-agent-test
  ✓ Job '02-kaniko-agent-test' triggered successfully
=== Monitor Agent Pods ===
agent tests exit: 0

# Step 5 — confirm both jobs SUCCESS via API
$ JENKINS_PASS=$(kubectl -n jenkins get secret jenkins-admin -o jsonpath='{.data.jenkins-admin-password}' | base64 -d)
$ curl -sk -u "jenkins-admin:${JENKINS_PASS}" http://127.0.0.1:8083/job/01-linux-agent-test/lastBuild/api/json | jq '.result'
"SUCCESS"
$ curl -sk -u "jenkins-admin:${JENKINS_PASS}" http://127.0.0.1:8083/job/02-kaniko-agent-test/lastBuild/api/json | jq '.result'
"SUCCESS"
```


### Priority 1: Add `system:auth-delegator` ClusterRoleBinding to `deploy_vault` ← NEXT

**Root cause discovered (2026-02-27):** Stage 2 CI `test_vault` was failing with
`403 permission denied` from `auth/kubernetes/login`. Root cause: the vault SA in the
`vault` namespace had no `system:auth-delegator` ClusterRoleBinding, so Vault could not
call the k8s TokenReview API to validate SA tokens.

**Temporary fix applied to m2-air cluster:**
```bash
kubectl create clusterrolebinding vault-auth-delegator \
  --clusterrole=system:auth-delegator \
  --serviceaccount=vault:vault
```
This is NOT in the code — new clusters will have the same problem.

**Permanent fix required in `scripts/plugins/vault.sh`:**

In the function that sets up the k8s auth backend (around line 1242 — look for
`vault auth enable kubernetes`), add a `kubectl create clusterrolebinding` call
immediately after the namespace/release are known and before `vault write auth/kubernetes/config`.

The ClusterRoleBinding should be idempotent (`|| true` or `--dry-run=client` check):
```bash
kubectl create clusterrolebinding vault-auth-delegator \
  --clusterrole=system:auth-delegator \
  --serviceaccount="${ns}:${release}" \
  --dry-run=client -o yaml | kubectl apply -f -
```
Where `$ns` is the vault namespace (default: `vault`) and `$release` is the vault SA name
(default: `vault` — the Helm chart creates a SA named after the release).

**File:** `scripts/plugins/vault.sh`
**Function to find:** `_vault_set_n_reader` (or `_enable_kv2_k8s_auth` / look for
`vault auth enable kubernetes` at line ~1242 and ~1366)
**Issue doc to create:** `docs/issues/2026-02-27-vault-missing-auth-delegator-clusterrolebinding.md`

**Codex instructions (start a fresh session):**
```
Read memory-bank/activeContext.md and .clinerules

Task: Add system:auth-delegator ClusterRoleBinding for the vault SA to deploy_vault.

Context:
- Vault k8s auth backend requires the vault pod's SA to have system:auth-delegator
  so it can call the k8s TokenReview API. Without it, auth/kubernetes/login returns 403.
- Root cause found during Stage 2 CI debugging on m2-air (2026-02-27).
- Temporary fix was applied manually to the m2-air cluster.

What to implement:
1. In scripts/plugins/vault.sh, find the k8s auth setup section (search for
   "vault auth enable kubernetes" — appears near line 1242 and line 1366).
2. In BOTH locations where vault auth enable kubernetes runs, add a kubectl apply
   immediately after enabling the auth method that creates (or updates) the
   ClusterRoleBinding:
     kubectl create clusterrolebinding vault-auth-delegator \
       --clusterrole=system:auth-delegator \
       --serviceaccount="${vault_ns}:${vault_release}" \
       --dry-run=client -o yaml | kubectl apply -f -
   Use the correct variable names for the namespace and service account name
   (the Helm chart creates a SA named after the release, default "vault" in ns "vault").
3. Create docs/issues/2026-02-27-vault-missing-auth-delegator-clusterrolebinding.md
   documenting the root cause, the symptom (403 on auth/kubernetes/login in test_vault),
   and the fix.
4. Commit with message: "vault: add system:auth-delegator ClusterRoleBinding for k8s auth"

Do NOT update memory-bank — that is done separately after validation.
```

### Priority 2: AD end-to-end validation
- Deferred to follow-on branch (requires external AD/VPN)

---

## Next Step for Gemini — Validation Complete ✅

Codex fixed all four root causes and committed the changes (`822fe54` on `ldap-develop`).
Gemini successfully validated the full flow on m4-air. Output evidence is documented under Priority 1.

---

## Codex Session Guidelines (added 2026-02-27)

- **Keep sessions short and focused** — one task per session. Codex has no auto-compaction;
  long sessions lose earlier context and produce degraded output without warning.
- **Start every session with:** `Read memory-bank/activeContext.md and .clinerules`
- **Commit after each working step** — a fresh session can resume from git, not from memory
- **Do not update memory-bank until the fix is confirmed working** — write what happened,
  not what you plan to do. See Memory-Bank Update Rule in `.clinerules`.

---

## Merge History

- **v0.1.0** — `ldap-develop` → `main` merged 2026-02-27T20:09:45Z via PR #2
  - Release: https://github.com/wilddog64/k3d-manager/releases/tag/v0.1.0

## Release Strategy

- **v0.1.0** ✅ — released 2026-02-27
- **v0.2.0** — `system:auth-delegator` fix + AD e2e validation complete
- **v1.0.0** — production-hardened, all known-broken paths resolved

---

## Branch Protection (as of 2026-02-27)

- 1 required PR approval, stale review dismissal, enforce admins
- Required status checks: `lint` (Stage 1) and `stage2` (Stage 2)

---

## Operational Notes

- **Always run `reunseal_vault`** after any cluster restart before other deployments.
- **ESO SecretStore**: `mountPath` must be `kubernetes` (not `auth/kubernetes`).
- **LDAP bind DN**: keep `LDAP_BASE_DN` in sync with LDIF bootstrap base DN.
- **Jenkins admin password**: contains special chars — always quote `-u "user:$pass"` or use kubectl to fetch. See `docs/issues/2026-02-27-jenkins-admin-password-zsh-glob.md`.
- **GitGuardian false positive**: `LDAP_PASSWORD_ROTATOR_IMAGE` — pending rename to `LDAP_ROTATOR_IMAGE`.
- **SMB CSI Phase 1 evidence**: validated on m4-air 2026-02-27. See evidence block in git history (commit `01f9d77`).
