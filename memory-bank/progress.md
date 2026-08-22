# Progress — k3d-manager

> Compressed 2026-08-21. Settled fix entries collapsed to pointers; detail is in
> `memory-bank/archive/progress-2026-08-19.md`, `docs/issues/`, release notes, and git.

## Releases

| Version | State |
|---|---|
| v1.26.0 | RELEASED — PR #117 `1bbe5439`, tag v1.26.0 + GitHub release published, branch protection restored (enforce_admins=true, 1 required approval). Shipped 3/5 scopes. |
| v1.25.0 | RELEASED — PR #116 `d48e465f`, tag/release published, protection restored |
| v1.24.1 | RELEASED — PR #115, tag and GitHub release published |
| v1.24.0 | RELEASED — PR #113, tag and GitHub release published |
| v1.23.0 and earlier | RELEASED — see `CHANGELOG.md` |

## v1.26.0 queue

- [x] **Fleet node lifecycle (count-agnostic)** — Phase A shipped as lib-foundation `v0.4.12`
  (PR #43 `c4f3211`, Copilot addressed `32ce9c9`, tag/release live; subtree-pulled into
  `scripts/lib/foundation` `e60dff69`/`2c083258`). Phase B implemented `b0fe320a`
  (`ACG_AGENT_COUNT`-driven hosts/nodes, parallel+idempotent SSH/SSM joins with per-node
  readiness, `make fleet-render|validate|plan|up` rungs; `scripts/etc/acg-cluster.yaml`
  unchanged). **Live-verified** at `ACG_AGENT_COUNT=4` (5 nodes = ACG cap): two live-only
  defects found + fixed + re-verified — `_k3s_agent_is_ready` false-negative (private-IP
  exact-match resolver in `shopping_cart.sh`) and `fleet-plan` invalid `--no-execute`/missing
  params (rewritten to `create-change-set --change-set-type CREATE` on a throwaway stack).
  Suite 17/17; teardown clean (0 EC2, stack gone, ArgoCD == baseline). Commits `46bfdf1c` +
  `35e9ecf2`, pushed + origin-verified. Findings:
  `docs/bugs/2026-08-21-fleet-phaseb-live-verification-findings.md`. **DONE.**
- [x] **E2E promotion-gate integration with durable success/failure artifacts** — live GREEN
  2026-08-21. `e2e_verify_vcluster` on the hub; the Playwright suite failed and the harness
  captured it faithfully: durable artifact `~/.k3dm/e2e/1787338912-32712.json`, result-event
  ConfigMap in `platform-ops`, exporter `e2e_run_info`/`e2e_last_run_pass=0`
  (fires `E2EVerificationFailing`)/`e2e_last_run_timestamp_seconds`. Full chain proven. Minor
  Finding 1a (empty duration metric) filed, not fixed.
  Evidence: `docs/bugs/2026-08-21-lifecycle-e2e-live-acceptance-findings.md`.
- [x] **Verify unknown/out-of-sync cleanup without mutating unrelated live Applications** —
  live GREEN 2026-08-21. Faithful full-ACG run on expired sandbox `604492140645`: 10 appset
  apps + 23 survivors + hostinger baseline; post-cleanup 23 survivors EXACT match, hostinger
  untouched. Found + fixed BLOCKING Finding 2a (`cleanup-stale-clusters` hung — now deletes
  Secret first + non-blocking `--wait=false`; BATS asserts order+wait 2/2; re-verify 3s, 0
  orphans). Commit `0274fdde`, pushed. Medium Finding 2b (dispatcher strips `--confirm`) filed.
- [x] Lifecycle cleanup foundation — registration metadata + dry-run/confirm
  `cleanup-stale-clusters`, provider/grace/retain guards, generated-Application-only deletion,
  JSONL audit (`f90c8e0d`).
- [ ] Keep all new work within the five-plan milestone limit (at 5/5 — split before a 6th).
- [x] 2026-08-20 provisioning/recovery batch (all pushed on `k3d-manager-v1.26.0`, each with a
  `docs/issues/2026-08-20-*.md` record + BATS/shellcheck evidence): k3s-aws SSM→SSH fallback
  (`fef71219`/`40f1d19a`/`2424f55f`), kubeconfig TLS SAN loopback (`3603b60c`), SSM Vault-bridge
  selects SSH, data-layer CoreDNS + guarded `make down CLEANUP_STALE=1` (`316f26d2`/`20a13862`/
  `f24c0c96`, implies `--keep-hub`), hostinger-only hub rebuild, stale unknown-Application match
  fix (`2f4de4fd`), ACG credential s2-404 + CDP-listener recovery (`f6bb7bb`/`c7f7b37`),
  cloudflared IPv4-loopback pin (`929ebed7`).
- [x] Dependabot alert #6 (js-yaml `3.15.0`, CVE-2026-59870, dev-only transitive) — fixed
  upstream as lib-foundation `v0.4.11` (PR #42 `b92f494`), subtree-pulled (`1bf1d2ce`, lockfile
  `3.15.1`). Reads `open` only because Dependabot scans main; auto-closes when v1.26.0 → main.

## v1.27.0 queue

Scope = 4 plan docs (4/5, under cap). Dependency-ordered load-split leads; decision
2026-08-21 "keep all four".

- [ ] **Foundation-managed vCluster CLI** (`docs/plans/v1.27.0-foundation-managed-vcluster-cli.md`)
  — upstream-first in lib-foundation (`foundation_ensure_vcluster_cli <version>`), then
  subtree-pull + rewire `scripts/plugins/vcluster.sh`. **Prerequisite — must land first.**
  - [x] **Part B DELIVERED (Codex) + VERIFIED (Claude) + PUSHED 2026-08-21** — HEAD `142fd06b`
    on `origin/k3d-manager-v1.27.0` (Codex's own note said `6c2dd94d`, but that was amended away and
    is NOT in history — real commit is `142fd06b`). Removes the consumer installer
    (`vcluster_install_cli`/`_vcluster_install_cli`/`VCLUSTER_INSTALL_DIR`), adds module-scoped
    `_VCLUSTER_BIN`, rewires `_vcluster_check_prerequisites` to
    `foundation_ensure_vcluster_cli "$VCLUSTER_VERSION"` (guards both non-zero exit AND empty path),
    routes all 6 lifecycle invocations through `"$_VCLUSTER_BIN"`; updates help/utils.sh,
    functions.md (row removed), howto/vcluster.md, guide; reworks vcluster.bats to stub the contract
    (deleted the 3 installer-era tests, added path-stored + failure-stops + empty-stops + destroy/list
    contract tests); e2e.bats correctly untouched (no installer refs). **Claude re-ran gates
    independently:** BATS 36/36, shellcheck clean, `bash -n` clean, both disappearance greps empty,
    subtree untouched. **Remaining Claude gate:** one live `make e2e` when the hub is healthy
    (ConfigMap → exporter → Grafana). No PR yet — PR is a v1.27.0-release-time step, not per-part.
  - Part A Codex task spec written 2026-08-21:
    `docs/plans/v1.27.0-foundation-managed-vcluster-cli-codex-task.md` — Part A only
    (lib-foundation `feat/v0.4.13`, `scripts/lib/system.sh`, stubbed BATS, STOP at gate).
  - **Part A DELIVERED + VERIFIED 2026-08-21** — Codex `b2adb8f2` on `origin/feat/v0.4.13`
    (independently confirmed on origin). `foundation_ensure_vcluster_cli` + 7 private helpers;
    +253/-0 across the 4 intended files only (system.sh, system.bats, README, functions.md).
    Gates re-run by Claude: BATS 33/33 (7 vcluster cases green), shellcheck clean, `bash -n`
    clean, if-count ≤2/fn (budget 8). Real asset names correct (`checksums.txt`,
    bare `vcluster-<os>-<arch>` via exact awk `$2==asset`). Non-blocking nit: bare `_err` on
    `mktemp` failure after lock acquisition leaks the lockdir (RETURN trap doesn't fire on exit;
    should use `_foundation_vcluster_abort`).
  - **Part A RELEASED as lib-foundation v0.4.13 (2026-08-22).** PR #44 merged (`0a3e4043`);
    Copilot found a REAL bug (`curl -fsSL -- URL -o FILE` put `-o` after `--` → parsed as URLs,
    real download fails; stubbed tests missed it) — fixed `-o` before `--` + tightened the BATS
    curl stub to honor `--` (proven to fail tests 28/32/33 on the buggy order). Nit fix
    (`f154dbe`) folded in. Tag `v0.4.13` + GitHub release published on `0a3e4043`.
    **Subtree-pulled into k3d-manager `scripts/lib/foundation`** — vendored copy verified:
    `foundation_ensure_vcluster_cli` + 7 helpers present, curl fix intact (`-o` before `--`),
    `bash -n` clean.
  - **Part B UNBLOCKED — Codex task spec written 2026-08-21:**
    `docs/plans/v1.27.0-foundation-managed-vcluster-cli-part-b-codex-task.md` (k3d-manager only,
    `k3d-manager-v1.27.0`). Grounded in real anchors: delete `VCLUSTER_INSTALL_DIR` (vcluster.sh:7,13),
    `vcluster_install_cli` (174-176) + `_vcluster_install_cli` (178-218); rewire
    `_vcluster_check_prerequisites` (220-232) to `_VCLUSTER_BIN="$(foundation_ensure_vcluster_cli
    "$VCLUSTER_VERSION")"` (module-scoped, not local — helpers 254/289/325 need it); route all 6
    invocations (49/75/171/263/289/325) through `"$_VCLUSTER_BIN"`; update help/utils.sh, functions.md
    (row 106), howto/vcluster.md, guide; rework vcluster.bats + e2e.bats to stub the contract (delete
    the 3 installer-era tests). Gates + disappearance greps + STOP-at-gate; live `make e2e` is Claude's.
    **Awaiting go to push + hand off to Codex.**
- [ ] **M2 remote E2E runner** (`docs/plans/v1.27.0-m2-remote-e2e-runner.md`) — SSH-dispatch
  ephemeral E2E to m2-air, restricted M4-side publisher → hub ConfigMap → Grafana. The actual
  E2E load-split off the M4 laptop. **Depends on the foundation vCluster CLI.**
- [ ] **Image signing / CVE-loop closure** (`docs/plans/v1.27.0-image-signing-cve-loop-closure.md`)
  — cosign sign+attest, Kyverno Audit→Enforce, promoter verify gate. Multi-repo, heavy.
- [ ] **Adaptive checkout load testing** (`docs/plans/v1.27.0-adaptive-checkout-load-testing.md`)
  — API-level checkout load + Grafana/Prometheus telemetry + small browser cohort.
- Both load-split plans were promoted from v1.26.0-deferred (renamed `v1.26.0-*` →
  `v1.27.0-*`, headers/cross-refs updated) on 2026-08-21.

## Verification record

- v1.25.0 release validation: E2E BATS 16/16; webhook BATS 54/54; syntax/shellcheck gates
  passed; Copilot findings resolved before merge.
- Node-health watchdog and E2E diagnostics hardening shipped in the released branch.
- Prometheus/Grafana recovery, status retry, remediation-table cleanup, and Slack status/thread
  fixes are shipped; remaining live follow-ups are in `activeContext.md`.

## Process

- Every implementation updates this file and `activeContext.md` with the real commit/PR SHA.
- Unexpected live failures get a dated `docs/issues/YYYY-MM-DD-*.md` record with verbatim
  evidence.
- Historical specs/issues are archived only when superseded or unreferenced; files are never
  deleted.
