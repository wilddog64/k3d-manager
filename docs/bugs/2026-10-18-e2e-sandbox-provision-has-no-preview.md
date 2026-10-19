# Bug: e2e-sandbox-provision has no read-only preview

**Filed:** 2026-10-18 (Claude, from the operator's request)
**Status:** FIXED — landed, awaiting webhook restart + E3
**Fix commit:** `2c065963`
**Priority:** P3 — no wrong action today; the operator just cannot see what a 2-hour job will do
**Severity:** low
**Approval:** approved — operator, 2026-10-18: "we should do that, and please file it and may dispatch to codex" (filing + dispatch)
**Release:** v1.43.5 (bug; exempt from the plan cap)
**Component:** `scripts/plugins/e2e.sh`, `Makefile`, `scripts/lib/webhook/make_targets.py`
**Related:** `docs/bugs/2026-10-18-slack-cleanup-accepts-apply-as-confirm-synonym.md` (the same
"no `confirm` = preview, `confirm` = act" rule for `/cleanup-stale-sandbox`);
`docs/bugs/2026-10-13-e2e-sandbox-does-not-provision-missing-acg-cluster.md` (added the target)

## Symptom

`/k3dm e2e-sandbox-provision` without `confirm` is refused (`is destructive — rerun with confirm`).
With `confirm` it runs everything: when `ubuntu-k3s` is down it runs `make up CLUSTER_PROVIDER=k3s-aws`
(30–40 min), then extends the ACG sandbox, writes secrets and Keycloak credentials, enables Stripe and
runs Tier 2, inside a 7200s job. The operator cannot find out beforehand whether the run will build a
sandbox or reuse one, or whether the hub and the ACG login are ready; a down hub or a dead login is
discovered only partway into the job.

## Root cause

`e2e_verify_sandbox` (`scripts/plugins/e2e.sh` ~437) has no read-only mode, and `parse_make_request`
(`scripts/lib/webhook/make_targets.py` ~94) can only refuse a `confirm` target that lacks `confirm`.

## Fix

- **F1.** New public function `e2e_sandbox_preview [DIGEST]` in `scripts/plugins/e2e.sh`. It calls only
  read-only checks, in order, and prints one line each, prefixed `[e2e-preview]`:
  1. `_e2e_sandbox_preflight_auth` → `acg login: ok` or the failure, then stop with rc 1;
  2. `_e2e_sandbox_cluster_ready` → `ubuntu-k3s: ready — would reuse it` or
     `ubuntu-k3s: absent or not ready — would run make up CLUSTER_PROVIDER=k3s-aws`;
  3. `_e2e_sandbox_preflight_hub` → `hub: ok` or the failure, then rc 1;
  4. `digest: <DIGEST>` or `digest: default (none given)`;
  5. last line: `[e2e-preview] no changes made; rerun with confirm to run Tier 2`.
  It returns 0 when every check passes. It must never call `_e2e_sandbox_provision_cluster`,
  `acg_extend_playwright`, `_e2e_sandbox_provision_secrets`,
  `_e2e_sandbox_provision_keycloak_credentials`, `_e2e_sandbox_enable_stripe`, any `make`, or any
  `kubectl` verb other than `get` / `config get-contexts`.
- **F2.** `Makefile`: new target `e2e-sandbox-provision-preview` running
  `./scripts/k3d-manager e2e_sandbox_preview $(DIGEST)`, **not** wrapped in `_e2e_recorded` (a preview
  is not an e2e run and must not appear on the e2e dashboard). Add a `##` help comment.
- **F3.** `scripts/lib/webhook/make_targets.py`:
  - add `"preview": "e2e-sandbox-provision-preview"` to the `e2e-sandbox-provision` entry, and an
    `e2e-sandbox-provision-preview` entry (`min_role: admin`, `optional: ("DIGEST",)`,
    `timeout: 300`, summary `read-only preview of e2e-sandbox-provision`);
  - in `parse_make_request`, when the spec needs `confirm`, `confirm` is not true and the spec has
    `preview`, return `[spec["preview"], *assignments], None` instead of the refusal. Targets without
    `preview` keep the refusal unchanged;
  - `make_target_help` shows `[confirm]` (brackets) for a target that has `preview`.
- **F4.** Tests:
  - `scripts/tests/bin/webhook_make_targets.py`: update
    `test_e2e_sandbox_provision_requires_admin_confirmation` — without `confirm` the argv is
    `["e2e-sandbox-provision-preview"]` (with `DIGEST=` passed through), with `confirm` it is
    `["e2e-sandbox-provision"]`, operator still cannot see either; add a case that
    `fix-delete-pod` without `confirm` is still refused.
  - `scripts/tests/plugins/e2e_sandbox_preflight.bats`: stub `kubectl`, `make`, `acg_extend_playwright`
    and the provision/secret/Stripe functions to record calls; assert the preview prints the
    reuse/provision line for a ready/unready cluster, records no `make` and none of those functions,
    and returns 1 with the auth or hub failure.
- **F5.** Docs: `docs/howto/slack-slash-commands.md` (the `/k3dm e2e-sandbox-provision` row: no
  `confirm` previews, `confirm` runs) and `docs/guides/vcluster-e2e-harness.md` (where it describes
  `e2e-sandbox-provision`, add the preview target).

## Files

- `scripts/plugins/e2e.sh`
- `Makefile`
- `scripts/lib/webhook/make_targets.py`
- `scripts/tests/bin/webhook_make_targets.py`
- `scripts/tests/plugins/e2e_sandbox_preflight.bats`
- `docs/howto/slack-slash-commands.md`
- `docs/guides/vcluster-e2e-harness.md`
- `CHANGELOG.md`

## Acceptance

```yaml
must:
  - id: M1
    text: parse_make_request("e2e-sandbox-provision", {}, None) returns ["e2e-sandbox-provision-preview"] and no error; with DIGEST it passes DIGEST=… through; with confirm=True it returns ["e2e-sandbox-provision", ...].
  - id: M2
    text: e2e_sandbox_preview prints whether it would reuse ubuntu-k3s or run make up CLUSTER_PROVIDER=k3s-aws, the digest, and "no changes made"; rc 0 when auth and hub pass.
  - id: M3
    text: e2e_sandbox_preview returns non-zero and names the failing check when ACG auth or the hub readyz fails.
  - id: M4
    text: make e2e-sandbox-provision-preview exists, is not wrapped in _e2e_recorded, and is an admin-only allowlisted /k3dm target.
must_not:
  - id: N1
    text: The preview must not run make, acg_extend_playwright, the secret/Keycloak provisioning, Stripe enablement, or any kubectl apply/patch/delete (red on pre-fix, where the only no-confirm path is refusal and the confirm path runs them).
  - id: N2
    text: A confirm target without a preview (fix-delete-pod, fix-force-sync, e2e-runner-unlock) must still be refused without confirm.
  - id: N3
    text: An operator-role user must not be able to run the preview or see it in help.
  - id: N4
    text: A preview must not write an e2e run record (no _e2e_recorded entry).
evidence:
  - id: E1
    proves: [M1, M4, N2, N3]
    kind: offline
    text: pytest scripts/tests/bin/webhook_make_targets.py; M1 red on pre-fix (refusal).
  - id: E2
    proves: [M2, M3, N1, N4]
    kind: offline
    text: bats scripts/tests/plugins/e2e_sandbox_preflight.bats with stubs that record calls; N1 shown red by a mutation that calls _e2e_sandbox_provision_cluster from the preview.
  - id: E3
    proves: [M1, M2]
    kind: live
    text: After make restart-webhook, the operator sends /k3dm e2e-sandbox-provision (no confirm) and screenshots the reply; Claude reads it — preview lines, no make up, no e2e dashboard run.
interface:
  - scripts/lib/webhook/make_targets.py parse_make_request(target, args, confirm), make_target_help(role, role_allows), MAKE_TARGETS
  - ./scripts/k3d-manager e2e_sandbox_preview [DIGEST]
  - make e2e-sandbox-provision-preview [DIGEST=…]
```

## Definition of Done

- [ ] F1–F5 on `k3d-manager-v1.43.5`; only the Files above change.
- [ ] M1 and N1 shown red against the pre-fix code (N1 by mutation).
- [ ] `pytest scripts/tests/bin` and `bats scripts/tests/plugins/e2e_sandbox_preflight.bats` green;
      shellcheck clean on `scripts/plugins/e2e.sh`.
- [ ] Commit: `fix(e2e): preview e2e-sandbox-provision without confirm`

## What NOT to Do

- Do NOT create a PR, commit to `main`, or use `--no-verify`.
- Do NOT contact ACG, the hub, AWS or Slack from tests; stub them.
- Do NOT change the confirm path of `e2e_verify_sandbox` or any other `/k3dm` target.
- Do NOT add a preview to `fix-delete-pod`, `fix-force-sync` or `e2e-runner-unlock`.

## Verification log

- 2026-10-18: Codex (dispatcher) fix landed `2c065963`. Claude verified: `webhook_make_targets.py` 35 passed; `e2e_sandbox_preflight.bats` 0 failures; shellcheck clean. Pre-fix `make_targets.py` turns the M1 test red; a mutation calling `_e2e_sandbox_provision_cluster` from the preview turns 2 preview tests red (N1). E3 waits for `make restart-webhook`.
