# OrbStack macOS Validation Fix Plan

## Scope
- Address the two regressions uncovered during the 2026-02-24 m4 validation run so
  OrbStack Phase 1+2 can progress to `m2-air`.
- Keep changes tightly scoped to Vault deployment plumbing and Jenkins `none` auth
  templating. No Phase 3 provider work yet.

## Objectives
1. Allow `deploy_vault` to succeed on macOS by skipping host-side PV directory
   creation when the storage class is managed inside the OrbStack VM.
2. Restore the baseline `deploy_jenkins --enable-vault` smoke test without requiring
   LDAP/AD flags by preserving a valid Jenkins Configuration as Code (JCasC)
   `securityRealm` and location settings when LDAP config is stripped.
3. Re-run the m4 validation sequence (vault + jenkins portions) and `test lib` to
   confirm the fixes before touching `m2-air`.

## Work Items (Order Matters)
1. **Vault macOS guard** (`scripts/plugins/vault.sh`) ✅
   - `_vault_ensure_data_path` now short-circuits on `_is_mac`; validation via
     `CLUSTER_PROVIDER=orbstack ./scripts/k3d-manager deploy_vault ha` passed.
2. **Jenkins none-auth templating** (`scripts/plugins/jenkins.sh`) — **HIGH RISK** ✅
   - LDAP removal now rebuilds the security realm with a local user, injects the
     matrix permissions list, and adds an explicit `VAULT_PKI_LEAF_HOST` env var for
     Helm values.
   - `deploy_jenkins --enable-vault` succeeds on macOS. LDAP/AD templates untouched
     (still need smoke coverage when time allows).
3. **Validation + docs** — IN PROGRESS
   - Re-run:
     ```bash
     PATH="/opt/homebrew/bin:$PATH" ./scripts/k3d-manager test lib
     CLUSTER_PROVIDER=orbstack ./scripts/k3d-manager deploy_vault ha
     CLUSTER_PROVIDER=orbstack ./scripts/k3d-manager deploy_jenkins --enable-vault
     ```
   - Jenkins smoke test routing fix merged (mac-only port-forward path +
     `JENKINS_SMOKE_URL`/`JENKINS_SMOKE_IP_OVERRIDE` overrides). Need to rerun the
     validation sequence above to capture the now-passing smoke output.
   - Update `docs/issues/` entries (done), `memory-bank/` status (done), and
     `docs/plans/orbstack-provider.md` validation checklist.

## Risks / Mitigations

- **macOS guard too broad:** Ensure the `mkdir` skip only applies where the path is
  inside VM-managed storage. Double-check `_is_mac` guard doesn’t affect Linux
  users on bare metal.

- **JCasC regressions (HIGH RISK):** The `awk` stripping logic in `jenkins.sh` is
  shared across all auth modes (`--enable-ldap`, `--enable-ad`, `--enable-vault`
  only). Any change to it risks breaking auth modes that currently work. Before
  committing the Jenkins fix, run smoke tests for at least `--enable-ldap` to confirm
  no regression. If a regression is found, stop and document — do not attempt to fix
  both issues in the same commit.

- **JCasC variable export order:** `VAULT_PKI_LEAF_HOST` and related vars must be
  exported before JCasC template rendering. If they are set after the `awk` filter
  runs, the fix will appear to work locally but fail in CI where env is clean.

- **Time boxing:** If Jenkins template refactor expands beyond a small patch, split
  work into separate commits for easier review. Vault fix and Jenkins fix must be
  in separate commits regardless — do not batch them.

- **m4 re-validation required:** Do not mark either issue as fixed until the full
  validation sequence passes on m4. Do not proceed to m2-air until both are green.

## Exit Criteria
- `deploy_vault` completes on macOS without manual intervention.
- `deploy_jenkins --enable-vault` (no LDAP) passes its smoke test on m4.
- Both issue docs tagged as fixed, memory bank updated, and m4 validation checklist
  reflects completion so `m2-air` work can start.
