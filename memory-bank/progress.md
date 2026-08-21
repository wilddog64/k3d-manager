# Progress — k3d-manager

> Compressed 2026-08-20. Detailed historical entries are preserved in
> `memory-bank/archive/progress-2026-08-19.md` and release notes.

## Releases

| Version | State |
|---|---|
| v1.25.0 | RELEASED — PR #116 `d48e465f`, tag/release published, protection restored |
| v1.24.1 | RELEASED — PR #115, tag and GitHub release published |
| v1.24.0 | RELEASED — PR #113, tag and GitHub release published |
| v1.23.0 and earlier | RELEASED — see `CHANGELOG.md` |

## v1.26.0 queue

- [x] **Fleet node lifecycle Phase B** implemented in `b0fe320a` and pushed to
  `origin/k3d-manager-v1.26.0` on 2026-08-21. The implementation is count-agnostic via
  `ACG_AGENT_COUNT` (default two agents), parallel/idempotent SSH and SSM joins with per-node
  readiness and collected failures, and Makefile fleet render/validate/plan/up rungs. The reference
  `scripts/etc/acg-cluster.yaml` remained unchanged. Offline gates: `bash -n` clean; focused BATS
  `1..39` all passed; shellcheck baseline comparison found no new findings; `_agent_audit` passed.
- [x] **Fleet Phase B live acceptance — GREEN 2026-08-21.** Claude ran live Rungs 1–3 at
  `ACG_AGENT_COUNT=4` on ACG sandbox `851725327555`. First pass surfaced two live-only defects
  (`docs/bugs/2026-08-21-fleet-phaseb-live-verification-findings.md`); **both now FIXED + re-verified
  live**: (1) BLOCKING `_k3s_agent_is_ready` false-negative — fixed in `scripts/plugins/shopping_cart.sh`
  (new `_k3s_agent_private_ip` SSH resolver + exact InternalIP-column match + `STATUS==Ready`; 2 new
  BATS tests, suite 17/17); (2) `fleet-plan` invalid `--no-execute`/missing params — fixed in `Makefile`
  (`create-change-set --change-set-type CREATE` on throwaway `k3d-manager-cluster-plan` stack, full
  params + `CAPABILITY_NAMED_IAM` + EXIT-trap cleanup + `SHELL := /bin/bash`). Re-verify: Rung 2 plans
  4 Agents + 1 Server then trap-cleans; Rung 3 `fleet-up` → `All agent nodes joined and Ready` /
  `FLEET_UP_EXIT=0`. Teardown re-verified clean (0 EC2, stack gone, ArgoCD == baseline). Cosmetic
  `Description` = upstream carry-forward (lib-foundation subtree). **Fixes + docs NOT yet committed** —
  staged pending user go. **Phase B DONE.**

- [x] **Fleet node lifecycle (count-agnostic) — PHASE A released/subtree-pulled and Phase B pushed 2026-08-21.**
  **GATE DONE 2026-08-21:** user squash-merged PR #43 → lib-foundation main (`c4f3211`); Copilot review
  addressed in `32ce9c9` (portable `mktemp -t`, `--help` count-agnostic text, guard regex
  `Agent[12]([^0-9]|$)`); Claude stamped `v0.4.12` (`c1df1be`, direct fast-forward — ruleset blocks only
  force-push/deletion, no PR requirement), tag `v0.4.12` + GitHub release live, lib-foundation next branch
  `feat/v0.4.13` + v0.4.12 retro (`c4ab19dc`). **Subtree-pulled into k3d-manager `scripts/lib/foundation`**
  (`e60dff69`, squash `2c083258` `0b574b13..c1df1bed`) on `k3d-manager-v1.26.0`, pushed + origin-verified.
  **Phase B HANDED TO CODEX 2026-08-21** — GATE-DONE marker stamped into
  `docs/plans/v1.26.0-fleet-node-lifecycle-codex-task.md`; Codex builds B1–B5 (impl + Rung-0 offline
  only, no live sandbox), commits on `k3d-manager-v1.26.0`. Claude runs Rungs 1–3 live serialized.
  Phase A (lib-foundation `feat/v0.4.12` `8148e33`, docs `249a8bd`): generated N-agent CFN via awk emitter
  + dynamic `Agent*PublicIP` discovery + validate-before-AWS + new `scripts/tests/lib/acg.bats`. Claude
  verified independently: only 2 files touched (no vendored), tree clean, 6/6 BATS + shellcheck-default +
  `bash -n` all green run by Claude, render preserves every per-agent property (incl. SSM `!If`) against
  the drifted k3d-manager template. Carry-forwards RESOLVED in the release: numeric agent-IP ordering
  shipped (awk-index `sort -n` + `Agent10` BATS test — no longer lexical); B1 corrected (do NOT regen
  k3d-manager template from upstream — would revert the SSM `!If` fix). Codex Phase B next. Scope decision "both, fleet first" — fleet before the foundation-vcluster-CLI + M2
  remote-runner plans. Design spec `docs/plans/v1.26.0-fleet-node-lifecycle.md` + implementation
  assignment `docs/plans/v1.26.0-fleet-node-lifecycle-codex-task.md` (ONE scope, two files — fleet stays
  plan #4 of 5; file-count in docs/plans is 5, watch the cap for the NEXT new scope). Upstream-first
  (lib-foundation lib-acg `acg.sh`: generated N-agent CFN + dynamic `Agent*PublicIP` discovery), then
  k3d-manager (`k3s-aws.sh` derive hosts/`total_nodes` from `ACG_AGENT_COUNT`; `shopping_cart.sh`
  `deploy_app_cluster()` parallel join + per-node readiness + idempotent). Re-wires `ACG_AGENT_COUNT`
  (removed in v1.0.1 for template/join drift) with a single-source-of-truth design so drift can't recur.
  **Test at the ACG 5-node cap:** `ACG_AGENT_COUNT=4` (server + 4 = 5 nodes = the cap; ACG_AGENT_COUNT=5
  would be 6 instances, over cap). 4-rung verification ladder shipped as `make fleet-render|validate|plan|up`
  targets (render offline; validate/plan zero-instance; `fleet-up`=`deploy_cluster` node-join only, NOT
  `make up`). **Division of labor:** Codex does all impl + Rung-0 offline (render/BATS/shellcheck/audit)
  and must NOT touch the live sandbox; Claude runs Rungs 1–3 serialized. GATE between Part A and B (lib
  release + subtree-pull) is Claude's, not Codex's.
- [x] Lifecycle cleanup foundation — registration metadata plus dry-run/confirm `cleanup-stale-clusters`,
  provider/grace/retain guards, generated-Application-only deletion, and JSONL audit (`f90c8e0d`, pushed on
  `k3d-manager-v1.26.0`). Live expired-sandbox validation remains pending.
- [ ] E2E promotion-gate integration with durable success/failure artifacts.
- [ ] Verify unknown/out-of-sync handling without mutating unrelated live Applications.
- [ ] Keep all new work within the five-plan milestone limit.
- [x] k3s-aws SSM registration fallback — recorded live account `218085830935` Default Host Management
  Role failure in `docs/issues/2026-08-20-k3s-aws-ssm-fallback.md`; provider now falls back to SSH
  (`fef71219`, pushed on `k3d-manager-v1.26.0`). BATS provider suite 11/11 and shellcheck passed.
- [x] Lifecycle cleanup and ArgoCD data-layer DNS recovery — help documents both stale-cleanup targets,
  `make down CLEANUP_STALE=1` runs guarded cleanup, and `make up` repairs Hub CoreDNS before registration
  (`316f26d2`, pushed on `k3d-manager-v1.26.0`). Focused BATS 12/12, `bash -n`, shellcheck, and
  `_agent_audit` passed. Bug evidence is recorded in
  `docs/issues/2026-08-20-make-up-data-layer-argocd-host-dns.md`.
- [x] Added the explicit `make down CLEANUP_STALE=1` example to `make help` (`20a13862`, pushed on
  `k3d-manager-v1.26.0`); Makefile BATS 2/2 passed.
- [x] Added unified `cleanup-stale-resources` dispatch and wired it into confirmed `make down`
  cleanup (`f24c0c96`, pushed on `k3d-manager-v1.26.0`); Makefile BATS 3/3 passed.
- [x] Fixed `make down CLEANUP_STALE=1` Hub/access-layer loss: the target now implies `--keep-hub`,
  and `bin/cluster-down --keep-hub` leaves Hub-dependent ArgoCD/Grafana listeners running. The old
  post-teardown cleanup deleted the Hub before stale cleanup could run, taking down ArgoCD/Grafana.
- [x] Recovered Hostinger-only topology after the Hub teardown: rebuilt local k3d Hub, bootstrapped
  ArgoCD/observability, refreshed `ubuntu-hostinger`, and verified public ArgoCD HTTP 200/Grafana
  HTTP 302 plus local Grafana health 200. Recovery evidence and regenerated-credential note are in
  `docs/issues/2026-08-20-stale-cleanup-deleted-hub-access-layer.md`.
- [x] SSM bootstrap readiness now falls back to SSH and fails only when both transports fail
  (`40f1d19a`, pushed on `k3d-manager-v1.26.0`); provider BATS 13/13 and shellcheck passed.
- [x] Added explicit SSM/SSH transition and success logs (`2424f55f`, pushed on
  `k3d-manager-v1.26.0`); provider BATS 13/13 and `_agent_audit` passed.
- [x] Fixed local k3s-aws kubeconfig TLS SAN mismatch by retaining the loopback API endpoint for
  tunneled kubectl traffic (`3603b60c`, pushed on `k3d-manager-v1.26.0`); shopping-cart BATS 12/12
  and shellcheck passed.

## Verification record

- v1.25.0 release validation: E2E BATS 16/16; webhook BATS 54/54; Python/shell syntax and shellcheck
  gates passed; Copilot findings resolved before merge.
- Node-health watchdog and E2E diagnostics hardening are included in the released branch.
- Prometheus/Grafana recovery, status retry behavior, remediation table cleanup, and Slack status/thread
  fixes are shipped; remaining live follow-ups are listed in `activeContext.md`.

## Process

- Every implementation updates this file and `activeContext.md` with the real commit/PR SHA.
- Unexpected live failures get a dated `docs/issues/YYYY-MM-DD-*.md` record with verbatim evidence.
- Historical specs/issues are archived only when superseded or unreferenced; files are never deleted.

- [x] SSM app-cluster Vault bridge gap fixed: the provider selects SSH whenever the laptop Vault
  reverse bridge is required and overrides explicit SSM safely; SSM remains available for
  non-bridge profiles. Evidence and BATS coverage are in
  `docs/issues/2026-08-20-ssm-vault-bridge-missing.md`.
- Live recovery verified: `vault-backend Ready=True/Valid`, all 13 ExternalSecrets `SecretSynced`;
  unrelated Grafana/frontend/product-image/data-layer health failures remain tracked separately.
- [x] Fixed stale cleanup leaving generated ArgoCD Applications `Unknown` after AWS sandbox teardown
  (`2f4de4fd`): Applications are now matched by managed registration cluster name/label/API server even
  when they lack the managed label. Focused BATS 5/5, shellcheck, syntax, and `_agent_audit` passed;
  full-repository baseline failures (webhook, vcluster, Slack relay, and ArgoCD deploy-key suites) are
  recorded in `docs/issues/2026-08-20-stale-cleanup-unknown-applications.md`.
- [x] Fixed ACG credential extraction after authenticated CDP navigation lands on the Pluralsight
  `s2` 404 route: retry the legacy Cloud Sandboxes URL (`7 suites/22 tests` green; issue record:
  `docs/issues/2026-08-20-acg-credential-s2-404.md`). Live `make credential-test PROVIDER=aws`
  remains unverified because the managed CDP browser exits during startup on port 9222.
- [x] Fixed ACG CDP startup recovery after IPv4 probe failure with stale IPv4/IPv6 listeners
  (`f6bb7bb`, `c7f7b37`, subtree-synced): listener reclaim BATS 5/5, shellcheck, and agent audit pass;
  live `make credential-test PROVIDER=aws` now passes after recovery and sandbox restart; see
  `docs/issues/2026-08-20-acg-credential-live-retry.md`. The test suite now isolates its HOME and
  listener probes; the complete CDP suite passes 5/5.
- [x] Cloudflare tunnel/ArgoCD origin recovery: reloaded the tunnel and pinned ArgoCD ingress to
  IPv4 loopback (`929ebed7`); external Grafana returned 302 and ArgoCD returned 200.

- [x] Subtree sync: pulled lib-foundation v0.4.10 (`bc70cef`) into `scripts/lib/foundation/`
  (`74a29b4f`, changelog-only 24-line stamp). Pushed to `origin/k3d-manager-v1.26.0`.
- [x] Dependabot alert #6 (js-yaml `3.15.0`, CVE-2026-59870, HIGH but dev-only transitive via
  jest->@istanbuljs/load-nyc-config): fixed UPSTREAM as lib-foundation **v0.4.11** (PR #42 merged
  `b92f494`, stamp `0b574b1`, tag/release v0.4.11) — lockfile bump to `3.15.1`, within existing
  `^3.13.1`. Subtree-pulled into `k3d-manager-v1.26.0` (`1bf1d2ce`); vendored lockfile now shows
  `3.15.1`. NOTE: alert #6 still reads `open` because Dependabot evaluates the **default branch**
  (main = v1.25.0); it auto-closes (`fixed_at`) when v1.26.0 merges to main. Remediation is complete
  and staged, closure coupled to the v1.26.0 release. Issue:
  lib-foundation `docs/issues/2026-08-20-js-yaml-omap-cpu-dos-devdep.md`.
