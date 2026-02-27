# Active Context – k3d-manager

## Current Branch: `ldap-develop`

Active development branch. **Not yet merged to `main`.**

## Current Focus (as of 2026-02-27)

**Jenkins Kubernetes agents** — last hard requirement before PR to `main`.
- Stage 2 CI: ✅ fully green (`test_vault`, `test_eso`, `test_istio` on m2-air)
- SMB CSI Phase 1 skip guard: ✅ validated on m4-air
- **Current blocker:** `${JENKINS_NAMESPACE}` not expanding in deployed ConfigMap — agents don't launch
- After agents land: open PR `ldap-develop` → `main`, merge, tag `v0.1.0`

### Session Notes (2026-02-27)
- Stage 2 CI complete; `stage2` required status check added to branch protection
- SMB CSI Phase 1 skip guard: Codex implemented, Gemini validated on m4-air
- Jenkins agent templates: port `8081`→`8080`, labels `linux-agent`→`linux`, `kaniko-agent`→`kaniko`
- `values.yaml` → `values-default.yaml.tmpl`, envsubst wired in `jenkins.sh` line 1552
- **Still broken:** `${JENKINS_NAMESPACE}` still literal in ConfigMap after redeploy — envsubst not expanding
- Jenkins admin password zsh glob issue: always wrap `-u user:pass` in quotes. See `docs/issues/2026-02-27-jenkins-admin-password-zsh-glob.md`
- Smoke test TLS race fixed: retry logic added in `bin/smoke-test-jenkins.sh`

---

## Current Priorities

### Priority 1: Jenkins Kubernetes agents (BLOCKED — Codex debugging)

**Symptom:** `${JENKINS_NAMESPACE}` is still literal in the deployed ConfigMap:
```
jenkinsUrl: "http://jenkins.${JENKINS_NAMESPACE}.svc.cluster.local:8080"
```
Agents queue indefinitely with "Jenkins doesn't have label 'linux'".

**Root cause under investigation:**
- `JENKINS_NAMESPACE` exported at `jenkins.sh:1277`
- envsubst runs at `jenkins.sh:1600`
- awk pass reads `$values_file` → `$temp_values` at line 1743; `values_file` reassigned to `$temp_values`
- ConfigMap still shows literal — either JENKINS_NAMESPACE not in env at envsubst call, or awk reintroduces it

**Next task for Codex — 3-step diagnostic (keep session short and focused):**

Step 1 — test envsubst standalone:
```bash
export JENKINS_NAMESPACE=jenkins
envsubst < scripts/etc/jenkins/values-default.yaml.tmpl | grep -A3 "02-kubernetes-agents"
```
- Expanded → envsubst works; bug is in deploy_jenkins call scope
- Still literal → template syntax issue

Step 2 — add debug line before `jenkins.sh:1600`:
```bash
_info "[jenkins] DEBUG JENKINS_NAMESPACE=${JENKINS_NAMESPACE}"
```
Redeploy and check. If empty/missing → export at line 1277 not persisting.

Step 3 — if Step 2 shows JENKINS_NAMESPACE is set but still not expanding, check awk output:
```bash
# Add before line 1743:
_info "[jenkins] DEBUG rendered: $(grep JENKINS_NAMESPACE "$values_file")"
```

**Fix (once root cause confirmed):**
- If not exported at call site: add `JENKINS_NAMESPACE="$ns" envsubst < ...` at line 1600
- If awk reintroduces: pipe `$temp_values` through a second envsubst pass

**Acceptance criteria:**
- `CLUSTER_PROVIDER=orbstack ./scripts/k3d-manager deploy_jenkins --enable-vault` completes
- ConfigMap shows expanded namespace (e.g. `jenkins.jenkins.svc.cluster.local`)
- linux-agent-test job spawns pod and completes

**Memory-bank update rule:** Do NOT mark ✅ until agent pod actually spawns. Paste evidence.

### Priority 2: Open PR and release v0.1.0
- Once Jenkins agents land and CI is green: open PR `ldap-develop` → `main`
- After merge + CI green on `main`: `gh release create v0.1.0 --generate-notes`

### Priority 3: AD end-to-end validation
- Deferred to follow-on branch (requires external AD/VPN)

---

## Next Step for Gemini — Validate Jenkins Kubernetes Agents

**Wait for Codex to fix the envsubst issue first.** Once Codex marks agents ✅ with evidence, run:

**RULES:** Full terminal output required. `hostname` mandatory. No summaries.

```bash
# Step 0 — prove you are on m4-air with latest code
hostname
git -C ~/src/gitrepo/personal/k3d-manager log --oneline -3

# Step 1 — deploy
CLUSTER_PROVIDER=orbstack PATH="/opt/homebrew/bin:$PATH" \
  ./scripts/k3d-manager deploy_jenkins --enable-vault
echo "exit: $?"

# Step 2 — verify ConfigMap has expanded namespace
kubectl -n jenkins get configmap jenkins-jenkins-config-02-kubernetes-agents.yaml \
  -o jsonpath='{.data.*}' | grep jenkinsUrl

# Step 3 — verify RBAC + agent service
kubectl -n jenkins get role,rolebinding | grep agent
kubectl -n jenkins get svc jenkins-agent

# Step 4 — trigger linux-agent-test, watch for pod
kubectl -n jenkins get pods -w --timeout=120s | grep agent
```

If all pass: mark Jenkins agents ✅ in progress.md, commit with evidence.
If any fail: create `docs/issues/YYYY-MM-DD-<slug>.md`, report, do NOT mark complete.

---

## Codex Session Guidelines (added 2026-02-27)

- **Keep sessions short and focused** — one task per session. Codex has no auto-compaction;
  long sessions lose earlier context and produce degraded output without warning.
- **Start every session with:** `Read memory-bank/activeContext.md and .clinerules`
- **Commit after each working step** — a fresh session can resume from git, not from memory
- **Do not update memory-bank until the fix is confirmed working** — write what happened,
  not what you plan to do. See Memory-Bank Update Rule in `.clinerules`.

---

## Merge Criteria for `ldap-develop` → `main`

1. ✅ Stage 2 CI green on PR #2
2. ✅ Pure-logic BATS suites green
3. ✅ No regressions on `deploy_jenkins --enable-vault` baseline
4. ✅ Known-broken paths documented with guardrails
5. **Jenkins Kubernetes agents working** — hard requirement, NOT yet met

## Release Strategy

- **v0.1.0** — trigger: Stage 2 CI green on `main` post-merge
- `gh release create v0.1.0 --generate-notes` — review before publishing
- **v0.2.0** — AD e2e validation complete
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
