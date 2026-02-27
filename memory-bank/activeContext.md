# Active Context – k3d-manager

## Current Branch: `main` (as of 2026-02-27)

`ldap-develop` merged to `main` via PR #2. **v0.1.0 released.**

## Current Focus (as of 2026-02-27)

**v0.1.0 shipped ✅** — PR #2 merged, tagged, released.

Next task: `test_vault` hard-fail cleanup — ✅ validated via `PATH="/opt/homebrew/bin:$PATH" ./scripts/k3d-manager test_vault` (2026-02-27).
Branch: `fix/vault-auth-delegator` (open — PR pending).

- Stage 2 CI: ✅ fully green (`test_vault`, `test_eso`, `test_istio` on m2-air)
- PR #2 merged to `main` at 2026-02-27T20:09:45Z
- v0.1.0 released: https://github.com/wilddog64/k3d-manager/releases/tag/v0.1.0

### Session Notes (2026-02-27)
- Stage 2 CI complete; `stage2` required status check added to branch protection
- SMB CSI Phase 1 skip guard: Codex implemented, Gemini validated on m4-air
- Jenkins k8s agents: ✅ Gemini validated on m4-air.
- Jenkins agent templates: port `8081`→`8080`, labels `linux-agent`→`linux`, `kaniko-agent`→`kaniko`
- `values.yaml` → `values-default.yaml.tmpl`, envsubst wired in `jenkins.sh` line 1552
- Jenkins k8s agents fully fixed by Codex — SA mismatch, admin credential placeholders, crumb issuer, port alignment
- Jenkins admin password zsh glob issue: always wrap `-u user:pass` in quotes. See `docs/issues/2026-02-27-jenkins-admin-password-zsh-glob.md`
- Smoke test TLS race fixed: retry logic added in `bin/smoke-test-jenkins.sh`
- Vault: `system:auth-delegator` ClusterRoleBinding added to both k8s auth setup paths in `vault.sh` — ✅ Gemini validated on m4-air. `test_vault` now hard-fails immediately if the vault-read pod cannot auth (validated via `PATH="/opt/homebrew/bin:$PATH" ./scripts/k3d-manager test_vault`).

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


### Priority 1: Add `system:auth-delegator` ClusterRoleBinding to `deploy_vault` (VALIDATED ✅)

**Status:** Validated on m4-air. Vault correctly has `system:auth-delegator` via the Helm-managed `vault-server-binding` ClusterRoleBinding.

**What changed on 2026-02-27:**
- `scripts/plugins/vault.sh` updated to include an idempotent `kubectl apply` for `vault-auth-delegator`.
- E2E proof (Gemini m4-air):
  - `kubectl delete clusterrolebinding vault-auth-delegator --ignore-not-found` ✅
  - `deploy_vault` re-run successfully.
  - `kubectl get clusterrolebinding -o json | jq -r '.items[] | select(.subjects[]? | .name=="vault" and .namespace=="vault") | .metadata.name'`
    - Result: `vault-server-binding`
  - `kubectl get clusterrolebinding vault-server-binding -o yaml | grep system:auth-delegator` ✅
  - E2E Vault K8s login: `vault write auth/kubernetes/login role=gemini-test-sa jwt=$JWT`
    - Result: SUCCESS (returned token with `["default" "eso-reader"]` policies).
- Found that the Vault Helm chart manages this binding as `vault-server-binding`. The manual fix previously applied used a different name (`vault-auth-delegator`). The automation in `vault.sh` provides an additional safety net.
- Documented in `docs/issues/2026-02-27-vault-auth-delegator-helm-managed.md`.

### Priority 2: `test_vault` cleanup — revert non-fatal workaround (VALIDATED ✅)

**Status:** Validated on m4-air. `test_vault` now hard-fails if pod auth fails, and the test passes cleanly end-to-end.

**What changed on 2026-02-27:**
- `scripts/lib/test.sh` reverted to `_err` (hard-fail) for the `vault-read` pod authentication check.
- E2E proof (Gemini m4-air):
  - `test_vault` output contains `INFO: Vault test succeeded`.
  - Output does NOT contain the previous workaround warning.
  - See evidence block below.

### Priority 3: LDAP rotator rename — docs cleanup

**Status:** Code already renamed in `scripts/`. Docs/memory-bank cleanup pending.

**What to do:** Update `memory-bank/progress.md`, `memory-bank/activeContext.md`, and
`docs/issues/2026-02-23-gitguardian-false-positive-ldap-rotator-image.md` to reflect
the rename is complete. No code changes needed.

Plan: `docs/plans/ldap-rotator-rename.md`

### Priority 4: AD end-to-end validation
- Deferred to follow-on branch (requires external AD/VPN)

---

## Next Step for Gemini — Validation Complete ✅

**Branch:** `fix/vault-auth-delegator`
**Result:** Success. `test_vault` passed cleanly end-to-end. The `vault-read` pod successfully authenticated using its projected SA token, confirming that the hard-fail logic is now safely active and `system:auth-delegator` is working as expected.

**Evidence:**
```bash
$ hostname
m4-air.local

$ git -C ~/src/gitrepo/personal/k3d-manager log --oneline -1
422ec47 (HEAD -> fix/vault-auth-delegator) memory-bank: add Gemini validation instructions for test_vault hard-fail

$ PATH="/opt/homebrew/bin:$PATH" CLUSTER_PROVIDER=orbstack ./scripts/k3d-manager test_vault
running under bash version 5.3.9(1)-release
INFO: Testing Vault deployment and Kubernetes auth...
INFO: Preparing test namespace 'vault-test-1772230133-31001' and service account 'vault-test-1772230133-31001-sa'...
INFO: Refreshing Vault Kubernetes auth backend (TokenReview mode)...
Success! Data written to: auth/kubernetes/config
INFO: Creating temporary Vault role for service account...
WARNING! The following warnings were returned from Vault:

  * Role vault-test-1772230133-31001-sa does not have an audience. In Vault
  v1.21+, specifying an audience on roles will be required.

INFO: Seeding test secret at secret/eso/vault-secret-1772230133-27424...
================ Secret Path ================
secret/data/eso/vault-secret-1772230133-27424

======= Metadata =======
Key                Value
---                -----
created_time       2026-02-27T22:08:54.417929486Z
custom_metadata    <nil>
deletion_time      n/a
destroyed          false
version            1
pod/vault-read created
pod/vault-read condition met
INFO: Vault test succeeded
Cleaning up Vault test resources...
```

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
- **GitGuardian false positive resolved**: `LDAP_PASSWORD_ROTATOR_IMAGE` already renamed to `LDAP_ROTATOR_IMAGE` in all scripts. Docs/memory-bank cleanup pending — see `docs/plans/ldap-rotator-rename.md`.
- **SMB CSI Phase 1 evidence**: validated on m4-air 2026-02-27. See evidence block in git history (commit `01f9d77`).
