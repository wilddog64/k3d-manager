# Active Context — k3d-manager

## Current Branch: `k3d-manager-v0.7.1` (as of 2026-03-08)

**v0.7.0 SHIPPED** — squash-merged to main (eb26e43), PR #24. See CHANGE.md.
**v0.7.1 active** — branch cut from main.

---

## Current Focus

**v0.7.1: Drop colima support + BATS teardown + Ubuntu app cluster**

| # | Task | Who | Status |
|---|---|---|---|
| 1 | Drop colima support — remove `_install_colima`, `_install_mac_docker`, update `_install_docker` mac case, clean README | Codex | **active** |
| 2 | Fix BATS teardown — `k3d-test-orbstack-exists` cluster not cleaned up | Gemini | pending |
| 3 | ESO deploy on Ubuntu app cluster | TBD | pending |
| 4 | shopping-cart-data / apps deployment on Ubuntu | TBD | pending |

---

---

## Task 1 — Codex Spec: Drop Colima Support

**Status: active**

### Background

Colima was the original macOS Docker VM runtime. OrbStack is now the primary macOS runtime and bundles Docker natively. Colima has caused operational issues (inotify limit not persistent) and is untested. Removing it reduces complexity and closes the inotify open item.

### Your task

Edit only `scripts/lib/system.sh` and `scripts/lib/core.sh`. Do NOT edit the foundation subtree copies — Claude handles those separately.

Make the same colima removal in both the local copies and the foundation subtree copies — 5 files total.

**`scripts/lib/system.sh` AND `scripts/lib/foundation/scripts/lib/system.sh`:**
1. Delete `_install_colima` (lines 710–717 in local; ~730–736 in foundation) entirely.
2. Delete `_install_mac_docker` (lines 719–745 in local; ~739–765 in foundation) entirely.

**`scripts/lib/core.sh` AND `scripts/lib/foundation/scripts/lib/core.sh`:**
3. In `_install_docker` (line ~416 in local; ~436 in foundation), the `mac)` case currently calls `_install_mac_docker`. Replace the mac case body with:
   ```bash
   mac)
      _info "On macOS, Docker is provided by OrbStack — no installation required."
      ;;
   ```

**`README.md`:**
4. Remove the "Colima resource configuration (macOS)" section (lines 328–334, from the `### Colima resource configuration (macOS)` heading through the last bullet point).
5. On line 289, remove "or Colima" (or equivalent phrasing) from the sentence.
6. On line 316, remove "Colima)" from the parenthetical — leave "Docker Desktop" if relevant or simplify to just mention OrbStack.

### Rules

- Edit only the 5 files listed above — no other files.
- Do NOT edit `scripts/lib/foundation/` files other than the two listed above.
- Do NOT run `git rebase`, `git reset --hard`, or `git push --force`.
- Claude will handle `git subtree push` to sync foundation changes back to lib-foundation after your commit merges.
- Do NOT edit any other files.
- Do NOT run `git rebase`, `git reset --hard`, or `git push --force`.
- `shellcheck scripts/lib/system.sh scripts/lib/core.sh` must exit 0.
- `env -i HOME="$HOME" PATH="/opt/homebrew/bin:$PATH" ./scripts/k3d-manager test all` — must not regress (158/158).
- Commit locally — Claude handles push.

### Required Completion Report

Update `memory-bank/activeContext.md` with:

```
## Task 1 Completion Report (Codex)

Files changed: [list all 5]
Shellcheck: PASS / [issues]
BATS: N/N passing
_install_colima deleted: YES — local system.sh lines N–N; foundation system.sh lines N–N
_install_mac_docker deleted: YES — local system.sh lines N–N; foundation system.sh lines N–N
_install_docker mac case: updated to OrbStack info message — local core.sh line N; foundation core.sh line N
README colima section removed: YES — lines N–N
README inline mentions cleaned: YES / [describe]
Unexpected findings: NONE / [describe]
Status: COMPLETE / BLOCKED
```

---

## Open Items

- [ ] Drop colima support — `_install_colima`, `_install_mac_docker`, README cleanup (Codex — Task 1, active)
- [ ] Fix BATS test teardown: `k3d-test-orbstack-exists` cluster not cleaned up post-test. Issue: `docs/issues/2026-03-07-k3d-rebuild-port-conflict-test-cluster.md`
- [ ] ESO deploy on Ubuntu app cluster
- [ ] shopping-cart-data / apps deployment on Ubuntu
- [ ] lib-foundation: sync deploy_cluster fixes back upstream (CLUSTER_NAME, provider helpers, if-count)
- [ ] lib-foundation: bare sudo in `_install_debian_helm` / `_install_debian_docker`
- [ ] lib-foundation: tag v0.1.1 push to remote (pending next release cycle)
- [ ] v0.7.0 (deferred): Keycloak provider interface + App Cluster deployment
- [ ] v0.8.0: `k3dm-mcp` lean MCP server

---

## lib-foundation Release Protocol (Option A)

lib-foundation is an independent library with its own semver (`v0.1.x`).
k3d-manager embeds it via git subtree and tracks the embedded version explicitly.

**When foundation code changes in k3d-manager:**

1. Codex edits both local copies (`scripts/lib/`) and subtree copies (`scripts/lib/foundation/`) in k3d-manager.
2. PR merges into k3d-manager.
3. Claude runs:
   ```bash
   git subtree push --prefix=scripts/lib/foundation lib-foundation main
   ```
4. Claude updates lib-foundation `CHANGE.md` and cuts a new tag (e.g. `v0.1.2`).
5. k3d-manager `CHANGE.md` records `lib-foundation @ v0.1.2` in the release entry.

**Embedded version tracking:**
- A `scripts/lib/foundation/.version` file (or CHANGE.md note) records the lib-foundation tag embedded in the current k3d-manager release.
- This makes it clear to consumers and auditors exactly which lib-foundation version is in use.

**When lib-foundation releases independently (future consumers):**
- Cut a lib-foundation tag on its own cadence.
- Each consumer does `git subtree pull --prefix=... lib-foundation <tag> --squash` to upgrade.

---

## Version Roadmap

| Version | Status | Notes |
|---|---|---|
| v0.1.0–v0.7.0 | released | See CHANGE.md |
| v0.7.1 | **active** | BATS teardown, inotify, Ubuntu app cluster |
| v0.8.0 | planned | Lean MCP server (`k3dm-mcp`) |
| v1.0.0 | vision | Reassess after v0.8.0 |

---

## Cluster State (as of 2026-03-07)

### Infra Cluster — k3d on OrbStack (context: `k3d-k3d-cluster`)

| Component | Status |
|---|---|
| Vault | Running — `secrets` ns, initialized + unsealed |
| ESO | Running — `secrets` ns |
| OpenLDAP | Running — `identity` ns + `directory` ns |
| Istio | Running — `istio-system` |
| Jenkins | Running — `cicd` ns |
| ArgoCD | Running — `cicd` ns |
| Keycloak | Running — `identity` ns |

**Known issues:**
- Port conflict: BATS test leaves `k3d-test-orbstack-exists` cluster holding ports 8000/8443. Doc: `docs/issues/2026-03-07-k3d-rebuild-port-conflict-test-cluster.md`
- inotify limit in colima VM not persistent across restarts.

### App Cluster — Ubuntu k3s (SSH: `ssh ubuntu`)

| Component | Status |
|---|---|
| k3s node | Ready — v1.34.4+k3s1 |
| Istio | Running |
| ESO | Running |
| Vault | Initialized + Unsealed |
| OpenLDAP | Running — `identity` ns |
| SecretStores | 3/3 Ready |
| shopping-cart-data / apps | Pending |

**SSH note:** `ForwardAgent yes` in `~/.ssh/config`. Stale socket fix: `ssh -O exit ubuntu`.

---

## Engineering Protocol

1. **Spec-First**: No code without a structured, approved implementation spec.
2. **Checkpointing**: Git commit before every surgical operation.
3. **Audit Phase**: Verify no tests weakened after every fix cycle.
4. **Simplification**: Refactor for minimal logic before final verification.
5. **Memory-bank compression**: Compress at the *start* of each new branch.

---

## Agent Workflow

```
Claude
  -- reviews all agent memory-bank writes before writing next task
  -- opens PR on owner go-ahead; routes PR issues back to agents by scope
  -- writes corrective/instructional content to memory-bank
  -- tags Copilot for code review before every PR

Gemini  (SDET + Red Team)
  -- authors BATS unit tests and test_* integration tests
  -- cluster verification: full teardown/rebuild, smoke tests
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
- **NEVER run `git rebase`, `git reset --hard`, or `git push --force` on shared branches.**
- Stay within task spec scope — do not add changes beyond what was specified.

**Push rules by agent location:**
- **Codex (M4 Air, same machine as Claude):** Commit locally + update memory-bank. Claude reviews and handles push + PR.
- **Gemini (Ubuntu VM):** Must push to remote — Claude cannot see Ubuntu-local commits. Always push before updating memory-bank.

**Lessons learned:**
- Gemini skips memory-bank read and acts immediately — paste full task spec inline in the Gemini session prompt; do not rely on Gemini pulling it from memory-bank independently.
- Gemini expands scope beyond task spec — spec must explicitly state what is forbidden.
- Gemini over-reports test success with ambient env vars — always verify with `env -i` clean environment.
- PR sub-branches from Copilot agent may conflict — evaluate and close if our implementation is superior.
- `git subtree add --squash` creates a merge commit that blocks GitHub rebase-merge — use squash-merge with admin override.

---

## Operational Notes

- **Always run `reunseal_vault`** after any cluster restart before other deployments
- **ESO SecretStore**: `mountPath` must be `kubernetes` (not `auth/kubernetes`)
- **Branch protection**: `enforce_admins` permanently disabled — owner can self-merge
- **Istio + Jobs**: `sidecar.istio.io/inject: "false"` required on Helm pre-install job pods
- **Bitnami images**: use `docker.io/bitnamilegacy/*` for ARM64

### Keycloak Known Failure Patterns

1. **Istio sidecar blocks `keycloak-config-cli` job** — mitigated via `sidecar.istio.io/inject: "false"`.
2. **ARM64 image pull failures** — use `docker.io/bitnamilegacy/*`.
3. **Stale PVCs block retry** — delete `data-keycloak-postgresql-0` PVC in `identity` ns before retrying.
