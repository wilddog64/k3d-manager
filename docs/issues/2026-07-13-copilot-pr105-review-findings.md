# Copilot PR #105 review findings — v1.15.0

**PR:** [#105](https://github.com/wilddog64/k3d-manager/pull/105) — `feat: v1.15.0 — security & multi-cluster provider hardening`
**Fix commit:** `<fill after commit>`
**Date:** 2026-07-13

---

## Finding 1 — new trivy plugin test not run by CI (`scripts/tests/plugins/trivy_operator_observability.bats:48`)

**Copilot:** the added ClientServer-mode assertions live under `scripts/tests/plugins`, but
CI only runs `bats scripts/tests/lib` (`.github/workflows/ci.yml:71-80`). The new regression
check therefore never runs in CI and would not catch a future regression of the built-in
Trivy server migration.

## Finding 2 — new per-context CSS test not run by CI (`scripts/tests/etc/hub_vault_profile.bats:102`)

**Copilot:** the new per-context hub-Vault CSS override tests are under `scripts/tests/etc`,
also outside the CI-scanned `scripts/tests/lib`, so the new per-context override behavior in
`scripts/etc/vault/vars.sh` is untested in CI despite the added tests.

---

## Fix applied — wire the covered suites into CI

`.github/workflows/ci.yml` — expanded the unit-BATS step from `bats scripts/tests/lib` to also
run the fully-green `scripts/tests/etc` directory and the specific new trivy plugin file.

**Before:**

```yaml
      - name: Run lib unit BATS
        ...
          bats scripts/tests/lib
```

**After:**

```yaml
      - name: Run unit BATS (lib + etc + trivy plugin)
        ...
          bats \
            scripts/tests/lib \
            scripts/tests/etc \
            scripts/tests/plugins/trivy_operator_observability.bats
```

**Why scoped, not the whole `plugins` dir:** `scripts/tests/etc` passes fully headless (18/18),
so the entire directory is added. `scripts/tests/plugins` (260 tests) has **pre-existing**
non-CI-safe cases — e.g. `argocd_deploy_keys.bats` `--dry-run makes no kubectl calls` and
`slack_relay_ack.bats` assert a stubbed `kubectl`/relay is not invoked, but a real `kubectl` on
`PATH` (the stub inherits `PATH=$PATH`) defeats the stub and the assertion fails. Adding the whole
`plugins` dir would turn CI red on suites unrelated to this PR. So only the file this PR touches
(`trivy_operator_observability.bats`, green) is wired in.

**Verification:** `yamllint .github/workflows/ci.yml` clean; the three added targets pass headless
(`bats scripts/tests/etc scripts/tests/plugins/trivy_operator_observability.bats` → 24 tests, all
`ok`).

---

## Root cause

CI's BATS step was scoped to `scripts/tests/lib` when the plugin/etc suites were added later, and
new specs kept landing in `plugins`/`etc` without a corresponding CI-scope update — so tests were
authored but never enforced.

---

## Process note

- When a spec adds BATS tests, confirm the target directory is actually in the CI `bats` invocation
  (`.github/workflows/ci.yml`). A test outside the scanned path is documentation, not a gate.
- Follow-up (tracked, out of scope here): make the full `scripts/tests/plugins` suite CI-safe
  (isolate the `kubectl`/relay stubs from a real binary on `PATH`) so the whole directory can be
  added to CI. Until then, wire in individual green files as their code lands.
