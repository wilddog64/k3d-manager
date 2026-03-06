# Active Context – k3d-manager

## Current Branch: `k3d-manager-v0.6.2` (as of 2026-03-06)

**v0.6.1 merged** — infra rebuild bug fixes integrated.
**v0.6.2 in progress** — Copilot CLI integration + security hardening.

---

## Current Focus

**v0.6.2: Codex Fix Cycle → Gemini Phase 2 + 3**

Codex implementation complete (2026-03-06). Gemini Phase 1 audit complete with 4 findings.
Codex fix cycle complete (2026-03-06). Gemini Phase 2 and Phase 3 are the active gate.

**Active sequence:**
1. ✅ Codex implementation (Batches 1–4)
2. ✅ Gemini Phase 1 — audit findings filed: `docs/issues/2026-03-06-v0.6.2-sdet-audit-findings.md`
3. ✅ **Codex fix cycle** — 4 Gemini findings resolved (task: `docs/plans/v0.6.2-codex-fix-task.md`)
4. ✅ **Gemini Phase 2** — BATS 115/115 pass, shellcheck warning at system.sh:149 (pre-existing SC2145)
5. ✅ **Gemini Phase 3** — RT-1/3/5/6 PASS, RT-3 PARTIAL; RT-2 FAIL (vault stdin), RT-4 FAIL (deny-tool)
6. ✅ **Codex RT fix cycle** — RT-2 + RT-4 resolved (`docs/plans/v0.6.2-codex-rt-fix-task.md`)
7. ⏳ **Claude** — review, commit, open PR
8. ✅ **Codex P1 fix cycle** — Copilot review issues (rc capture, PATH guard, sticky bit) per `docs/plans/v0.6.2-codex-copilot-review-task.md`

**Phase 2 definition:** Run `shellcheck scripts/lib/system.sh scripts/etc/ldap/ldap-password-rotator.sh`
and `./scripts/k3d-manager test all`. Report total/pass/fail counts. Confirm no regressions.
**Codex status:** local shellcheck + targeted BATS suites completed; Gemini full `test all` already run.

**Phase 3 definition:** Structured security audit — one PASS/FAIL/N/A with justification per check:
- RT-1: PATH poisoning (`_safe_path` with world-writable + relative path + sticky bit)
- RT-2: Secret exposure in process listing (`ldap-password-rotator.sh` stdin fix)
- RT-3: Trace isolation for copilot CLI (`_run_command` + `_args_have_sensitive_flag`)
- RT-4: Deny-tool guardrails completeness + placement
- RT-5: AI gating bypass (`K3DM_ENABLE_AI` check + no direct copilot calls)
- RT-6: Prompt injection surface (no credentials passed to copilot)

---

## Engineering Protocol (Activated)

1. **Spec-First**: No code without a structured, approved implementation spec.
2. **Checkpointing**: Git commit before every surgical operation.
3. **AI-Powered Linting**: Use `copilot-cli` to verify architectural intent (e.g., "Prove the test ran," "Check for price injection") before allowing a commit.
4. **Audit Phase**: Explicitly verify that no tests were weakened.
5. **Simplification**: Refactor for minimal logic before final verification.

---

## Cluster State (as of 2026-03-02)

### Infra Cluster — k3d on OrbStack (context: `k3d-k3d-cluster`)

| Component | Status | Notes |
|---|---|---|
| Vault | Running | `secrets` ns, initialized + unsealed |
| ESO | Running | `secrets` ns |
| OpenLDAP | Running | `identity` ns |
| Istio | Running | `istio-system` |
| Jenkins | Running | `cicd` ns |
| ArgoCD | Running | `cicd` ns |
| Keycloak | Running | `identity` ns |

### App Cluster — Ubuntu k3s (SSH: `ssh ubuntu`)

| Component | Status | Notes |
|---|---|---|
| k3s node | Ready | v1.34.4+k3s1 |
| Istio | Running | IngressGateway + istiod |
| ESO | Pending | Deploy after PR merges |
| shopping-cart-data | Pending | PostgreSQL, Redis, RabbitMQ |
| shopping-cart-apps | Pending | basket, order, payment, catalog, frontend |

**SSH note:** `ForwardAgent yes` in `~/.ssh/config`. Stale socket fix: `ssh -O exit ubuntu`.

---

| Version | Status | Notes |
|---|---|---|
| v0.1.0–v0.5.0 | released | See CHANGE.md |
| v0.6.0–v0.6.1 | released | PR #17 merged; infra rebuild verified |
| v0.6.2 | active | AI Tooling (`copilot-cli`) + Checkpointing Protocol |
| v0.6.3 | planned | Refactoring (De-bloat) + `rigor-cli` Integration |
| v0.6.4 | planned | lib-foundation extraction via git subtree |
| v0.7.0 | planned | Keycloak provider + App Cluster deployment |
| v0.8.0 | planned | Lean MCP server (`k3dm-mcp`) for Claude Desktop / Codex / Atlas / Comet |
| v1.0.0 | vision | Reassess after v0.7.0; see `docs/plans/roadmap-v1.md` |

---

## Open Items

- [x] `configure_vault_app_auth` — implemented + Copilot review resolved (PR #16, CI green, awaiting merge)
- [ ] ESO deploy on Ubuntu app cluster (Gemini — SSH, after PR merges)
- [ ] shopping-cart-data / apps deployment on Ubuntu (Gemini — SSH)
- [ ] GitGuardian: mark 2026-02-28 incident as false positive (owner action)
- [ ] `scripts/tests/plugins/jenkins.bats` — backlog
- [x] v0.6.2: `_ensure_node` + `_ensure_copilot_cli` — implemented by Codex (2026-03-06)
- [x] v0.6.2: SDET/Red-Team audit findings (RT-1, RT-2, RT-3) — see `docs/issues/2026-03-06-v0.6.2-sdet-audit-findings.md`
- [x] v0.6.2: Gemini Phase 2 & 3 (Verification + Red-Team Audit) — Results: BATS 115/115 Pass, RT-2/RT-4 FAIL
- [x] v0.6.2: Codex RT fix cycle — RT-2 + RT-4 (task: `docs/plans/v0.6.2-codex-rt-fix-task.md`)
- [ ] v0.6.2: Codex Copilot fix cycle — per `docs/plans/v0.6.2-codex-copilot-review-task.md`
- [ ] v0.6.2: Claude review and merge (PR)
- [ ] v0.7.0: Keycloak provider interface + App Cluster deployment (ESO, shopping-cart stack)
- [ ] v0.7.0: rename cluster to `infra` + fix `CLUSTER_NAME` env var
- [ ] v0.8.0: `k3dm-mcp` — lean MCP server for Claude Desktop, Codex, Atlas, Comet

---

## Operational Notes

- **Pipe all command output to `scratch/logs/<cmd>-<timestamp>.log`** — always print log path before starting
- **Always run `reunseal_vault`** after any cluster restart before other deployments
- **ESO SecretStore**: `mountPath` must be `kubernetes` (not `auth/kubernetes`)
- **Vault reboot unseal**: dual-path — macOS Keychain + Linux libsecret; k8s `vault-unseal` secret is fallback
- **New namespace defaults**: `secrets`, `identity`, `cicd` — old names still work via env var override
- **Branch protection**: `enforce_admins` permanently disabled — owner can self-merge
- **Istio + Jobs**: `sidecar.istio.io/inject: "false"` required on Helm pre-install job pods
- **Bitnami images**: use `docker.io/bitnamilegacy/*` for ARM64 — `docker.io/bitnami/*` and `public.ecr.aws/bitnami/*` are broken/amd64-only

### Keycloak Known Failure Patterns (deploy_keycloak)

1. **Istio sidecar blocks `keycloak-config-cli` job** — job hangs indefinitely; look for `keycloak-keycloak-config-cli` pod stuck in Running. Already mitigated in `values.yaml.tmpl` via `sidecar.istio.io/inject: "false"` — verify the annotation is present if job hangs again.
2. **ARM64 image pull failures** — `docker.io/bitnami/*` and `public.ecr.aws/bitnami/*` are amd64-only; `values.yaml.tmpl` must use `docker.io/bitnamilegacy/*` for Keycloak, PostgreSQL, and Keycloak Config CLI.
3. **Stale PVCs block retry** — a failed deploy leaves `data-keycloak-postgresql-0` PVC in the `identity` namespace; Helm reinstall will hang waiting for PostgreSQL. Delete the PVC before retrying: `kubectl -n identity delete pvc data-keycloak-postgresql-0`.

---

## Agent Workflow (canonical)

```
Claude
  -- monitors CI / reviews agent reports for accuracy
  -- opens PR on owner go-ahead
  -- when CI fails: identifies root cause → writes bug report → hands to Gemini

Gemini
  -- investigates, fixes code, verifies live (shellcheck + bats + cluster)
  -- handles Ubuntu SSH deployment (interactive)
  -- may write back stale memory bank — always verify after

Codex
  -- pure logic fixes with no cluster dependency
  -- STOP at each verification gate; do not rationalize partial fixes

Owner
  -- approves and merges PRs
```

**Lessons learned:**
- Gemini ignores hold instructions — accept it, use review as the gate
- Gemini may write back stale memory bank content — verify file state after every update
- Codex commit-on-failure is a known failure mode — write explicit STOP guardrails
