# BATS red on `k3d-manager-v1.27.0` — stale guard tests + vcluster harness gaps

**Filed:** 2026-09-03
**Branch:** `k3d-manager-v1.27.0` (HEAD `83cbdbe1`)
**Trigger:** pre-PR local BATS scope check for the v1.27.0 milestone PR found the branch RED.
**Scope:** test-only. No production code changes. The milestone code is correct; the tests lag intentional infra changes or have harness bugs.

## Summary

A single-threaded local run of `bats scripts/tests/ --recursive` reports **13 failures**. Bucketed:

- **9 branch-related failures** — must fix (they fail deterministically and would fail in CI too).
- **4 pre-existing local-macOS-env failures** — fail identically on `main` (which is CI-green), so they pass in CI and are **out of scope** for this milestone. Tracked separately in `docs/issues/`.

Verification method: ran the affected test files on `main` (CI-green baseline) and on the branch, in isolation, to separate branch regressions from environment/ordering artifacts.

## Group B — stale guard tests (code is intentional, assertions lag)

1. **`scripts/tests/bin/cluster_up.bats` — "acg-up verifies every LDAP password before checkpointing the seed"**
   Branch migrated LDAP to the `openldap-stack-ha` chart (`bin/cluster-up`): `ldap://localhost:389` → `ldap://localhost:1389`, `dc=shopping-cart,dc=local` → `dc=home,dc=org`, `cn=admin` → `cn=ldap-admin`, label `app.kubernetes.io/name=ldap` → `openldap-stack-ha`.
   - Line 185: `ldapwhoami -x -H ldap://localhost:389` → `ldapwhoami -x -H ldap://localhost:1389`

2. **`scripts/tests/bin/cluster_up.bats` — "acg-up keeps LDAP user passwords out of command arguments"**
   Same migration. Security property (password via `-y "${_ldap_password_file}"`, never `-s`/`-w` in argv) is unchanged and still holds.
   - Line 200: `ldappasswd -x -H ldap://localhost:389` → `ldappasswd -x -H ldap://localhost:1389`
   - Line 203: `-S "uid=$1,ou=users,dc=shopping-cart,dc=local"` → `-S "uid=$1,ou=users,dc=home,dc=org"`
   - Lines 206/209/212 (positive `-y file`, negative `-s`/`-w`) unchanged — still pass.

3. **`scripts/tests/plugins/shopping_cart_namespace.bats` — "shopping-cart-frontend deployment uses ghcr pull secret"**
   Branch moved the pull secret from an inline `imagePullSecrets:` in `services/shopping-cart-frontend/kustomization.yaml` to a dedicated `frontend` ServiceAccount (`services/shopping-cart-frontend/serviceaccount.yaml` carries `imagePullSecrets: - name: ghcr-pull-secret`; the deployment patch sets `serviceAccountName: frontend`). Also added `maxSurge: 0` (hostinger rollout-deadlock lesson).
   - Replace the two `kustomization.yaml` greps with assertions that (a) `serviceaccount.yaml` exists and contains `imagePullSecrets:` + `- name: ghcr-pull-secret`, and (b) `kustomization.yaml` references `serviceaccount.yaml` and sets `serviceAccountName: frontend`.

4. **`scripts/tests/bin/node_health_watch.bats` — "node health watchdog preserves bounded recovery controls"**
   Branch intentionally bumped the recovery failure threshold `3 → 5` in `bin/k3dm-node-health-watch` (wait for NotReady longer before bouncing a slow-but-alive node; CPU-starvation restart-loop lesson).
   - `threshold="${K3DM_NODE_RECOVERY_FAILURE_THRESHOLD:-3}"` → `:-5`

5. **`scripts/tests/lib/provider_contract.bats` — "_hostinger_refresh_access_layer restarts argocd port-forward before cloudflared"**
   Branch reworked `scripts/etc/argocd/port-forward-wrapper.sh.tmpl` into a consecutive-failure self-healer; the coarse `sleep 30` restart delay is now `sleep "${RESTART_DELAY}"` with `RESTART_DELAY=2`. All other assertions in this test already pass against the new generated wrapper.
   - Line 902 assertion `sleep 30` → `RESTART_DELAY=2` (literal survives the envsubst allowlist).

6. **`scripts/tests/plugins/argocd.bats` — "_argocd_write_port_forward_wrapper includes a self-healing loop"**
   Same template rework: `HEALTH_FAILURE_THRESHOLD` default is now `6` (was `3`), `--max-time 1` → `5`.
   - `HEALTH_FAILURE_THRESHOLD=3` → `HEALTH_FAILURE_THRESHOLD=6`

## Group C — vcluster test-harness bugs (`scripts/tests/plugins/vcluster.bats`)

Introduced by commit `142fd06b` (branch-only, never CI-green). Tests: 850 "vcluster_create: uses foundation-managed CLI path", 851 "_vcluster_check_prerequisites: stores the contract path", 854 "vcluster_create: honors VCLUSTER_VALUES_FILE override".

7. **850 / 854** — `vcluster_create` calls `_vcluster_wait_ready` (`scripts/plugins/vcluster.sh:186`), a real `until _kubectl get pod … | grep -q . ; sleep 2` loop (60s timeout). The `stub_kubectl` helper returns exit 0 but **empty stdout** for `get pod`, so the loop never satisfies `grep -q .` → 60s timeout → `_err` → `vcluster_create` returns 1 → tests asserting `status -eq 0` fail (and make the suite slow).
   - Fix: stub `_vcluster_wait_ready() { :; }` in `setup()`. No `@test` exercises `_vcluster_wait_ready` directly, so a global no-op is safe. Do **not** globally stub `_vcluster_export_kubeconfig` — tests 160/168 exercise it directly.

8. **851** — the test does `run _vcluster_check_prerequisites` then asserts `[ "$_VCLUSTER_BIN" = "$managed_path" ]`. `run` executes in a subshell, so the `_VCLUSTER_BIN` assignment made inside `_vcluster_check_prerequisites` does not propagate to the test shell; `_VCLUSTER_BIN` stays at the `setup()` value.
   - Fix: call `_vcluster_check_prerequisites` directly (no `run`) so the side-effect assignment persists, then assert `_VCLUSTER_BIN`.

9. **854** (surfaces only after the wait_ready timeout is removed) — commit `142fd06b` updated tests 43/destroy/list to expect the foundation-managed path `$VCLUSTER_STUB create …`, but left this test asserting bare `vcluster create demo … -f ${override_values}`. The code correctly logs `$_VCLUSTER_BIN` (= `$VCLUSTER_STUB`).
   - Fix: line 82 expected string `vcluster create demo …` → `$VCLUSTER_STUB create demo …`.

## Group A — pre-existing local-macOS-env failures (OUT OF SCOPE — file in docs/issues/)

These fail identically on `main` (CI-green), so they pass in CI and do not block the v1.27.0 PR. Not introduced by this milestone.

- `scripts/tests/plugins/argocd_deploy_keys.bats` — "configure_vault_argocd_repos --dry-run makes no kubectl calls" (455) and "…--seed-vault prints actions only" (457): `[ ! -s "$KUBECTL_LOG_PATH" ]` — kubectl log non-empty under dry-run locally.
- `scripts/tests/plugins/slack_relay_ack.bats` — "slack relay cluster-status acks before webhook completes" (767): relay returns non-zero locally.
- `scripts/tests/plugins/slack_slash_commands.bats` — "slack relay allowlist includes cluster-status and hostinger-status" (773).

## Definition of Done

- [ ] Groups B and C fixed (test files only; no production `.sh`/`.tmpl`/manifest edits).
- [ ] `bats scripts/tests/plugins/vcluster.bats scripts/tests/bin/cluster_up.bats scripts/tests/bin/node_health_watch.bats scripts/tests/lib/provider_contract.bats scripts/tests/plugins/argocd.bats scripts/tests/plugins/shopping_cart_namespace.bats` → all green.
- [ ] Full-suite run failures drop from 13 to 4 (the Group A local-env set only).
- [ ] Group A documented in `docs/issues/`.
- [ ] memory-bank updated.

## What NOT to Do

- Do NOT change any production code (`bin/cluster-up`, `bin/k3dm-node-health-watch`, `scripts/plugins/*.sh`, `scripts/etc/argocd/*.tmpl`, `services/**`) — the code is correct and intentional.
- Do NOT "fix" Group A by weakening its assertions — it is a separate pre-existing issue.
- Do NOT globally stub `_vcluster_export_kubeconfig`.
