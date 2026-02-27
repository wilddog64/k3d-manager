# Active Context – k3d-manager

## Current Branch: `ldap-develop`

Active development branch. **Not yet merged to `main`.**

## Current Focus (as of 2026-02-27)

**Jenkins Kubernetes agents** — Codex fix committed (`822fe54`). Waiting for Gemini validation on m4-air.
- Stage 2 CI: ✅ fully green (`test_vault`, `test_eso`, `test_istio` on m2-air)
- SMB CSI Phase 1 skip guard: ✅ validated on m4-air
- Jenkins k8s agents: ✅ fixed by Codex (local evidence) — **pending Gemini validation on m4-air**
- After Gemini evidence landed: open PR `ldap-develop` → `main`, merge, tag `v0.1.0`

### Session Notes (2026-02-27)
- Stage 2 CI complete; `stage2` required status check added to branch protection
- SMB CSI Phase 1 skip guard: Codex implemented, Gemini validated on m4-air
- Jenkins agent templates: port `8081`→`8080`, labels `linux-agent`→`linux`, `kaniko-agent`→`kaniko`
- `values.yaml` → `values-default.yaml.tmpl`, envsubst wired in `jenkins.sh` line 1552
- Jenkins k8s agents fully fixed by Codex — SA mismatch, admin credential placeholders, crumb issuer, port alignment
- Jenkins admin password zsh glob issue: always wrap `-u user:pass` in quotes. See `docs/issues/2026-02-27-jenkins-admin-password-zsh-glob.md`
- Smoke test TLS race fixed: retry logic added in `bin/smoke-test-jenkins.sh`

---

## Current Priorities

### Priority 1: Jenkins Kubernetes agents (VALIDATED — SMB CSI still pending)

**Status:** Linux/kaniko agent validation complete. SMB CSI work continues separately (macOS skip guard still active).

**What changed on 2026-02-27:**
- ServiceAccount mismatch resolved (`docs/issues/2026-02-27-jenkins-k8s-agent-serviceaccount-mismatch.md`).
- JCasC admin placeholders preserved so envsubst runs for all templates (`docs/issues/2026-02-27-jenkins-jcasc-admin-credentials-empty.md`).
- Crumb issuer regression fixed + scripts updated (`docs/issues/2026-02-27-jenkins-crumb-issuer-xpath-forbidden.md`).
- Controller Service/VirtualService ports aligned to 8080 so agents can connect (`docs/issues/2026-02-27-jenkins-service-port-mismatch.md`).
- ConfigMap now renders concrete namespaces (`kubectl get configmap jenkins-jenkins-config-02-kubernetes-agents.yaml | grep jenkinsUrl`).
- E2E proof:
  - `CLUSTER_PROVIDER=orbstack PATH="/opt/homebrew/bin:$PATH" ./scripts/k3d-manager deploy_jenkins --enable-vault` — smoke test 4/4 passes.
  - `PATH="/opt/homebrew/bin:$PATH" JENKINS_URL="http://127.0.0.1:8083" ./bin/run-k8s-agent-tests.sh` — both linux + kaniko jobs trigger and finish.
  - `timeout 120 kubectl -n jenkins get pods -w | grep agent` shows pods progressing Pending → Running → Completed.
  - `curl -sk -u jenkins-admin:*** http://127.0.0.1:8083/job/01-linux-agent-test/lastBuild/api/json | jq '.result'` → `"SUCCESS"` (same for kaniko).

**Next steps:**
- Automate the port-forward workflow (helper script) so Jenkins smoke + agent tests can run outside `deploy_jenkins` without manual tunnels.
- Continue SMB CSI Phase 2 (NFS-based swap) per `docs/plans/smb-csi-macos-workaround.md`.


### Priority 2: Open PR and release v0.1.0
- Once Jenkins agents land and CI is green: open PR `ldap-develop` → `main`
- After merge + CI green on `main`: `gh release create v0.1.0 --generate-notes`

### Priority 3: AD end-to-end validation
- Deferred to follow-on branch (requires external AD/VPN)

---

## Next Step for Gemini — Validate Jenkins agents on m4-air

Codex fixed all four root causes and committed the changes (`822fe54` on `ldap-develop`).
Your job: pull latest, run the full flow on m4-air, paste **complete terminal output**.

**RULES (non-negotiable):**
- `hostname` must appear in your output — proves you are on the right machine
- Full terminal output only — no summaries, no paraphrasing
- Do not mark anything ✅ until you have run it and have the output in front of you
- If any step fails: create `docs/issues/YYYY-MM-DD-<slug>.md`, report, stop

```bash
# Step 0 — prove you are on m4-air with latest code
hostname
git -C ~/src/gitrepo/personal/k3d-manager pull
git -C ~/src/gitrepo/personal/k3d-manager log --oneline -5

# Step 1 — deploy Jenkins with Vault
cd ~/src/gitrepo/personal/k3d-manager
CLUSTER_PROVIDER=orbstack PATH="/opt/homebrew/bin:$PATH" \
  ./scripts/k3d-manager deploy_jenkins --enable-vault
echo "deploy exit: $?"

# Step 2 — verify ConfigMap has concrete namespace (not literal ${JENKINS_NAMESPACE})
kubectl -n jenkins get configmap jenkins-jenkins-config-02-kubernetes-agents.yaml \
  -o jsonpath='{.data.*}' | grep jenkinsUrl

# Step 3 — verify RBAC and agent service exist
kubectl -n jenkins get role,rolebinding | grep agent
kubectl -n jenkins get svc jenkins-agent

# Step 4 — run the agent test suite
PATH="/opt/homebrew/bin:$PATH" JENKINS_URL="http://127.0.0.1:8083" \
  ./bin/run-k8s-agent-tests.sh
echo "agent tests exit: $?"

# Step 5 — confirm both jobs SUCCESS via API
JENKINS_PASS=$(kubectl -n jenkins get secret jenkins -o jsonpath='{.data.jenkins-admin-password}' | base64 -d)
curl -sk -u "jenkins-admin:${JENKINS_PASS}" \
  http://127.0.0.1:8083/job/01-linux-agent-test/lastBuild/api/json | jq '.result'
curl -sk -u "jenkins-admin:${JENKINS_PASS}" \
  http://127.0.0.1:8083/job/02-kaniko-agent-test/lastBuild/api/json | jq '.result'
```

**If all pass:** add an "Evidence (Gemini — m4-air)" subsection under Priority 1 here
and in `progress.md`, then mark Jenkins agents ✅. Open PR `ldap-develop` → `main`.

**If any step fails:** create `docs/issues/YYYY-MM-DD-<slug>.md` with full output,
report back, do NOT mark complete.

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
5. ✅ Jenkins Kubernetes agents working — linux/kaniko validation succeeded (2026-02-27); SMB CSI still pending separately

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
