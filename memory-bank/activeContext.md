# Active Context – k3d-manager

## Current Branch: `k3d-manager-v0.6.4` (as of 2026-03-07)

**v0.6.3 SHIPPED** — tag `v0.6.3` pushed, PR #21 merged. See CHANGE.md.
**v0.6.4 active** — branch cut from `main`.

---

## Current Focus

**v0.6.4: Linux k3s Validation + lib-foundation Extraction**

| # | Task | Who | Status |
|---|---|---|---|
| 1 | Linux k3s validation — 5-phase teardown/rebuild on Ubuntu VM (`CLUSTER_PROVIDER=k3s`) | Gemini | ⚠️ Phase 5 blocked |
| 1a | Fix `_install_bats_from_source` default version `1.10.0` → `1.11.0` | Codex | ⏳ active |
| 1b | Re-run Phase 5 BATS suite on Ubuntu after fix | Gemini | pending |
| 2 | `_agent_audit` hardening — bare sudo detection + credential pattern check | Codex | pending |
| 3 | Pre-commit hook — wire `_agent_audit` to run on every commit | Codex | pending |
| 4 | Contract BATS tests — provider interface enforcement | Gemini | pending |
| 5 | Create `lib-foundation` repository | Owner | pending |
| 6 | Extract `core.sh` + `system.sh` via git subtree | Codex | pending |

## Codex Next Task — Fix BATS Default Version

Task spec: `docs/plans/v0.6.4-codex-bats-version-fix.md`

**Goal:** Update hardcoded default BATS version from `1.10.0` (invalid tag, 404) to `1.11.0`
in `scripts/lib/system.sh` — two lines only (`_install_bats_from_source:1209` and `_ensure_bats:1295`).

**Claude review of Gemini Phase 1-5 report — VERIFIED:**
- Phase 1 destroy_cluster: PASS
- Phase 2 create_cluster: PASS — `_detect_platform` returns `debian` confirmed
- Phase 3 deploy_cluster: PASS — full stack deployed
- Phase 4 smoke tests: PASS — Vault, ESO, Istio
- Phase 5 BATS: BLOCKED — `_install_bats_from_source` defaults to `1.10.0` (non-existent tag, 404)
- Gemini report accurate. Fix routed to Codex.

**Protocol note to Gemini:** Self-commit rule applies to issue docs and memory-bank updates too.
The issue doc (`docs/issues/2026-03-07-bats-source-install-404.md`) and this memory-bank update
were left unstaged. Commit your own work — every artifact you create.

**After Codex fix is merged:** Gemini re-runs Phase 5 only (`CLUSTER_PROVIDER=k3s ./scripts/k3d-manager test all`) on Ubuntu to confirm BATS installs cleanly and suite passes.

---

## Engineering Protocol

1. **Spec-First**: No code without a structured, approved implementation spec.
2. **Checkpointing**: Git commit before every surgical operation.
3. **Audit Phase**: Verify no tests weakened after every fix cycle.
4. **Simplification**: Refactor for minimal logic before final verification.
5. **Memory-bank compression**: Compress memory-bank at the *start* of the new branch, before the first agent task. Completed release details → single line in "Released" section + CHANGE.md. Reason: end of release the context is still live and needed; start of new branch it is history — compress before any agent loads stale data.

---

## Agent Workflow

```
Claude
  -- reviews all agent memory-bank writes before writing next task
  -- opens PR on owner go-ahead; routes PR issues back to agents by scope
  -- writes corrective/instructional content to memory-bank

Gemini  (SDET + Red Team)
  -- authors BATS unit tests and test_* integration tests
  -- cluster verification: full teardown/rebuild, smoke tests
  -- red team: adversarially tests existing security controls (bounded scope)
  -- commits own work; updates memory-bank to report completion

Codex  (Production Code)
  -- pure logic fixes and feature implementation, no cluster dependency
  -- commits own work; updates memory-bank to report completion
  -- fixes security vulnerabilities found by Gemini red team

Owner
  -- approves and merges PRs
```

**Agent rules:**
- Commit your own work — self-commit is your sign-off.
- Update memory-bank to report completion — this is how you communicate back to Claude.
- No credentials in task specs or reports — reference env var names only (`$VAULT_ADDR`).
- Run `shellcheck` on every touched `.sh` file and report output.

**Red Team scope (Gemini):**
- Test existing controls only: `_copilot_prompt_guard`, `_safe_path`, stdin injection, trace isolation.
- Report findings to memory-bank — Claude routes fixes to Codex.
- Do NOT modify production code.

**Memory-bank flow:**
```
Agent  → memory-bank   (report: task complete, what changed, what was unexpected)
Claude reads           (review: detect gaps, inaccuracies, overclaiming)
Claude → memory-bank   (instruct: corrections + next task spec)
Agent reads + acts
```

**Lessons learned:**
- Gemini may write stale memory-bank content — Claude reviews every update before writing next task.
- PR sub-branches from Copilot agent (e.g. `copilot/sub-pr-*`) may conflict — evaluate and close if our implementation is superior.

---

## Cluster State (as of 2026-03-07)

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
| ESO | Pending | Deploy after infra work stabilizes |
| shopping-cart-data | Pending | PostgreSQL, Redis, RabbitMQ |
| shopping-cart-apps | Pending | basket, order, payment, catalog, frontend |

**SSH note:** `ForwardAgent yes` in `~/.ssh/config`. Stale socket fix: `ssh -O exit ubuntu`.

---

## Version Roadmap

| Version | Status | Notes |
|---|---|---|
| v0.1.0–v0.6.3 | released | See CHANGE.md |
| v0.6.4 | **active** | Linux k3s validation gate + lib-foundation extraction |
| v0.7.0 | planned | Keycloak provider + App Cluster deployment |
| v0.8.0 | planned | Lean MCP server (`k3dm-mcp`) |
| v1.0.0 | vision | Reassess after v0.7.0 |

---

## Open Items

- [ ] ESO deploy on Ubuntu app cluster
- [ ] shopping-cart-data / apps deployment on Ubuntu
- [ ] GitGuardian: mark 2026-02-28 incident as false positive (owner action)
- [ ] `CLUSTER_NAME` env var not respected during `deploy_cluster` — see `docs/issues/2026-03-01-cluster-name-env-var-not-respected.md`
- [ ] `scripts/tests/plugins/jenkins.bats` — backlog
- [ ] v0.7.0: Keycloak provider interface + App Cluster deployment
- [ ] v0.8.0: `k3dm-mcp` lean MCP server

---

## Operational Notes

- **Always run `reunseal_vault`** after any cluster restart before other deployments
- **ESO SecretStore**: `mountPath` must be `kubernetes` (not `auth/kubernetes`)
- **New namespace defaults**: `secrets`, `identity`, `cicd`
- **Branch protection**: `enforce_admins` permanently disabled — owner can self-merge
- **Istio + Jobs**: `sidecar.istio.io/inject: "false"` required on Helm pre-install job pods
- **Bitnami images**: use `docker.io/bitnamilegacy/*` for ARM64

### Keycloak Known Failure Patterns

1. **Istio sidecar blocks `keycloak-config-cli` job** — mitigated via `sidecar.istio.io/inject: "false"` in `values.yaml.tmpl`.
2. **ARM64 image pull failures** — use `docker.io/bitnamilegacy/*`.
3. **Stale PVCs block retry** — delete `data-keycloak-postgresql-0` PVC in `identity` ns before retrying.
