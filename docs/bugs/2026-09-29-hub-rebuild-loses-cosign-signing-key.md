# Bug: a hub rebuild loses the cosign signing key, and no bring-up path restores it

**Branch:** `k3d-manager-v1.40.0`
**Filed:** 2026-09-29 by Claude (cloud session), from Hermes `eso` degraded on the hub
**Status:** OPEN — assigned to Codex 2026-09-29 (brief below: Fix 1 + Fix 2). `make signing-restore`
already landed in `19d74587`.
**Related:** `docs/issues/2026-09-05-vault-kv-and-eso-policy-loss-grafana-cosign.md` (first
occurrence and root cause), `docs/bugs/2026-09-13-vault-eso-role-rewrite-drops-cosign-verify.md`
(the grant-only variant, fixed in `b3bc737c`)

## Codex brief

**Goal:** a hub rebuild or recovery restores the cosign key and ESO grant without a human, and
Hermes proposes `make signing-restore` whenever the hub's `cosign-public-key` stops syncing.

**Runs where:** Codex web is fine. Code and offline tests only; nothing needs the M4, a cluster,
Vault, or the Keychain. Stub every `signing_restore`, `kubectl` and `make` call.

**Decisions already made (operator, 2026-09-29):** do both fixes. Prevention calls the existing
`signing_restore` (never `signing_init`, never `signing_rotate_key`). R7 is approval-gated like
R1–R4; do not add it to any auto-execution path.

**Files to touch (only these):**
- `scripts/plugins/hub_recovery.sh`: source `$PLUGINS_DIR/signing.sh` the same way as the other
  plugins at the top of the file. In `hub_recovery_reconcile`, add step `"Cosign signing key"` to
  `steps` right after `"ESO policy"`. After `_hub_recovery_ensure_eso_apps_role`, call
  `_hub_recovery_restore_signing "$hub_context"`: a new function that runs `signing_restore` with the
  hub context pinned (same temporary-kubeconfig pattern as `make signing-restore`). A failure
  **warns and continues** (`_warn`, return 0): an absent Keychain backup must not block recovery.
- `bin/cluster-up`: in the `_hub_newly_created -eq 1` branch of Step 3.6, after `deploy_argocd`, add
  `_dry_guard "restore cosign signing" "${REPO_ROOT}/scripts/k3d-manager" signing_restore || _warn …`
  (warn and continue, as above). Do not touch the `elif` branch.
- `scripts/lib/hermes/repairs.py`: add `r7` to `REPAIRS` using the table in "Fix 2" above;
  `_r7_precondition` = `eso` degraded, its evidence contains `cosign-public-key`, and the same held on
  the previous cycle (use `_sustained` over `history`, as R3 does); `_r7_command` returns
  `(["make", "signing-restore"], {})` with `cwd: ROOT`. Add `"r7": ("eso",)` to `_evidence`.
- `docs/architecture/hermes-phase2-repair-scope.md`: add the R7 row to the §3 allowlist table.
- Tests: `scripts/tests/plugins/hub_recovery.bats`, `scripts/tests/bin/cluster_up.bats`,
  `scripts/tests/hermes/test_repairs.py` (see "Tests" below).
- `CHANGELOG.md` (one `### Fixed` bullet, one `### Added` bullet), `memory-bank/activeContext.md`,
  `memory-bank/progress.md`, and this doc (Status → FIXED with the SHA).

**Tests (all offline):**
1. `hub_recovery_reconcile --confirm` with stubs calls `signing_restore` exactly once, after the ESO
   policy step, with the hub context pinned.
2. `signing_restore` failing → reconcile still returns 0 and logs a warning.
3. The dry list (`hub_recovery_reconcile` without `--confirm`) shows `Cosign signing key`.
4. `cluster_up.bats`: a newly created hub calls `signing_restore` after `deploy_argocd`; an existing
   hub does not.
5. No path in `hub_recovery.sh` or `bin/cluster-up` mentions `signing_init` or `signing_rotate_key`.
6. `test_repairs.py`: R7 proposed only when `eso` is degraded with `cosign-public-key` for 2 cycles;
   not for one cycle; not for other ESO evidence (`1/8 not synced: grafana-admin`); command is exactly
   `make signing-restore`; `reversible` is `True`.

**Mutations (paste each red run, then the restored green run):**
- Remove the `signing_restore` call from `hub_recovery_reconcile` → test 1 red.
- Make the restore failure fatal → test 2 red.
- Drop the `cosign-public-key` evidence check from `_r7_precondition` → test 6 red.

**Gates (paste output):** `shellcheck -S warning scripts/plugins/hub_recovery.sh bin/cluster-up`
unchanged from before; `bats scripts/tests/plugins/hub_recovery.bats scripts/tests/bin/cluster_up.bats`;
`make test-pytest`; `git diff --stat` lists only the files above.

**Do not change:** `scripts/plugins/signing.sh`, the `signing-restore` make target,
`scripts/lib/foundation/`, `scripts/lib/acg/`, R1–R6, or `approve()`. Do not run any command
against a live cluster, Vault or the Keychain.

**Commit and hand back:** one commit on `k3d-manager-v1.40.0`, message
`fix(signing): restore the cosign key on hub bring-up and propose it as Hermes R7`.
No PR, no merge, no force-push, no `--no-verify`.

## Evidence (2026-09-29)

- Hermes `eso`: `1/8 not synced: cosign-public-key` on every poll.
- `platform-ops/cosign-public-key` condition: `could not get secret data from provider`.
- The operator ran `signing_restore` on the hub. Its output:
  `restored cosign signing material from Keychain backup` (Vault `secret/cosign/signing` was
  **empty** — new `version 1`, `created_time 2026-09-29T23:24:54Z`) and
  `granted cosign-verify read to ESO role eso-ldap-directory` (the grant was gone too).
  The ExternalSecret then went `SecretSynced True`.

The hub was rebuilt on 2026-09-20. That rebuild produced a fresh Vault without the key.

## Root cause — known since 2026-09-05, never filed as a bug

The 2026-09-05 post-incident doc found it: the cosign KV data, the `cosign-verify` policy and the
ESO grant are seeded only by the manual `signing_init` / `deploy_image_signing`, never by standard
bring-up. `bin/cluster-up`, `bin/cluster-refresh` and `scripts/plugins/hub_recovery.sh` contain no
call to any `signing_*` function. Every hub rebuild therefore loses the key, and image-signature
verification has no public key until someone notices.

This is the second key loss after a rebuild (2026-09-04, 2026-09-20) and the fourth cosign sync
failure overall (2026-09-05, 2026-09-09, 2026-09-13, 2026-09-29).

`signing_init` must not be the fix: it generates a new key pair, overwrites the Keychain backup and
forces re-signing every image. The safe primitive is `signing_restore`, which restores from the
Keychain backup only when Vault lacks the key and never generates one.

## Landed now: `make signing-restore`

`make signing-restore [CONTEXT=…]` runs `signing_restore` against one cluster through a temporary
single-context kubeconfig (the global current-context is not changed), then force-syncs and waits
for `cosign-public-key`. Default: the hub (`INFRA_CONTEXT`). Hostinger:
`make signing-restore CONTEXT=ubuntu-hostinger SIGNING_ES_NAMESPACE=kyverno SIGNING_ESO_ROLE=eso-app-cluster SIGNING_ESO_AUTH_MOUNT=kubernetes-ubuntu-hostinger`.
Tests: `scripts/tests/bin/makefile_signing_restore.bats` (8). Dropping the kubeconfig pin,
continuing after a failed restore, and ignoring a missing context each went red.

## Fix 1 — prevention (preferred)

Call `signing_restore` from hub bring-up after Vault is initialised and ESO's `vault-backend`
store exists: in `bin/cluster-up` for the hub, and in `hub_recovery.sh` after Vault recovery.
If the Keychain backup is absent (for example, a fresh machine), warn and continue — never fall
back to `signing_init`. Tests: a stubbed bring-up calls `signing_restore` exactly once after the
Vault step, and never calls `signing_init` or `signing_rotate_key`.

## Fix 2 — Hermes repair R7 (approval-gated, Phase 2)

Add to `scripts/lib/hermes/repairs.py`:

| Field | Value |
|---|---|
| name | Restore cosign signing key and ESO grant |
| precondition | `eso` degraded **and** its evidence names `cosign-public-key`, sustained ≥ 2 cycles |
| command | `make signing-restore` (hub). Hostinger stays manual until the sensor distinguishes clusters. |
| blast_radius | Vault `secret/cosign/signing` (written only if empty), the `cosign-verify` policy, one ESO role's policy list (additive), one ExternalSecret resync |
| reversible | True: additive; never generates or rotates a key |
| needs_scope | macOS Keychain (`k3d-manager-signing`), local hub kubeconfig |

This matches the Phase 2 rules in `docs/architecture/hermes-phase2-repair-scope.md`: a structured
precondition (not bare "degraded"), a bounded and additive blast radius, and human approval
through the existing Slack Approve flow. Update §3 of that doc with the new row. Unattended
execution is Phase 3 and out of scope here.

R7 tests: the precondition is true only for `cosign-public-key` evidence sustained for 2 cycles; it
is false for other ESO failures and for a single cycle; the built command is exactly
`make signing-restore`; `approve()` runs it and nothing else.

Fix 1 removes the common trigger, and R7 covers the rest (for example, a grant rewrite).
