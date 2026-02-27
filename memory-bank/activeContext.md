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

## Next Step for Gemini — Capture Jenkins agent evidence, then tackle SMB CSI

**Now that Codex has the agents green locally, please re-run the flow on m4-air and paste the transcripts so we can close the loop.** Once evidence is landed, pivot to SMB CSI Phase 2.

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

If all pass: add an "Evidence" subsection here + in `progress.md` and mark Jenkins agents ✅.
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
