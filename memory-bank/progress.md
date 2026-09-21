# Progress — k3d-manager

> Compressed 2026-09-17 (v1.34.0 Grafana/observability block closed → collapsed to pointers).
> Full pre-compression detail: `memory-bank/archive/progress-2026-09-17.md`.
> Settled work lives in `CHANGELOG.md`, `docs/releases.md`, `docs/retro/`, `docs/issues/`,
> `docs/bugs/` and git history. This file tracks what is still open.

## Open items

- [x] **Hub rebuild EXECUTED 2026-09-20 — kine compaction stall CLEARED.** Operator ran the
  teardown; Claude completed and monitored the rebuild. `state.db` 2.72 GiB → 25.8 MB, WAL 678 MB →
  10 MB, `kubectl get nodes` 5.5s → 0.05s, `COMPACT deleted` on a 5-minute cadence (288/day
  baseline) after zero matches beforehand. Runbook corrected against reality:
  `docs/howto/hub-rebuild-from-gitops-vault.md`.

- [x] **Grafana port-forward flapping fixed** — `K3DM_PF_HEALTH_THRESHOLD`/`_TIMEOUT`, spec
  `docs/bugs/2026-09-20-pf-supervisor-kills-healthy-forward-on-single-slow-probe.md`. 0 restarts
  post-fix vs ~1 per 45s before.

- [ ] **Post-rebuild Vault KV is nearly empty — 12 of 14 canonical keys unseeded.**
  `vault kv list secret` returns only `ldap/` and `observability/` (and `observability/` holds only
  `grafana`). The hub-only rebuild sequence does **not** run `deploy_shopping_cart_data`, so
  `redis/*`, `postgres/*`, `payment/*`, `rabbitmq/default`, `minio/credentials`, `keycloak/*` and
  `github/pat` are absent. All 14 are in the Keychain backup, and the `f28a4539` seed fix will
  restore the Stripe key from it, so this is recoverable — it just has not been done. Decide whether
  to run `deploy_shopping_cart_data` (deploys the data tier + ~7 PVCs) or leave the hub lean.

- [ ] **Two platform-ops ExternalSecrets cannot sync** — `app-cluster-kubeconfig` and
  `cosign-public-key`, both `SecretSyncedError: could not get secret data from provider`, which is
  what makes ArgoCD `hub-platform-ops` **Degraded**. Neither key is among the 14 backed-up canonical
  keys, so both were genuinely lost with the Vault PVC. `app-cluster-kubeconfig` is moot until an
  app cluster is registered with the new hub; `cosign-public-key` belongs to the v1.27.0 image
  signing work and needs a recovery path that is **not** `signing_init` (forbidden).
  `monitoring/grafana-admin-credentials` **does** sync, so Grafana login is intact.

- [ ] **`observability/alertmanager` and `observability/prometheus` unseeded** — `make observability`
  warned `Alertmanager Vault secret not found — skipping SMS config`, `Failed to create Alertmanager
  login secret in Vault — using generated local credentials for this run`, and `Prometheus Vault
  credentials unreadable — skipping auth proxy`. The Prometheus auth proxy is therefore **not
  running**, which also means `K3DM_HERMES_STATUS_ENABLED=1` must stay unset. Run
  `make alertmanager-secret`.

- [ ] **`ServiceMonitor monitoring/kube-prometheus-stack-apiserver not found`** — the 45s apiserver
  scrape-timeout patch landed earlier this release had nothing to patch on a fresh cluster, so the
  `KubeAPIDown` flap guard is **not** in place. Re-run once the ServiceMonitor exists.

- [ ] **`cve-remediation-verify` CronJob fails every run: `secrets "cluster-ubuntu-hostinger" not
  found`.** The new hub ArgoCD has no registration Secret for the live `ubuntu-hostinger` cluster,
  so the CVE remediation verifier errors on every schedule. Re-register the hostinger cluster with
  the rebuilt hub — do **not** hand-patch the cluster Secret
  ([[reference_appset_generated_app_cleanup_ordering]] ordering applies). Until then this is a
  recurring red that is *expected*, which is exactly the kind of thing that later gets dismissed as
  noise — fix or pause it, do not learn to ignore it.

- [x] **trivy `scan-vulnerabilityreport-8479d4f9` Error — investigated, benign.** One-off startup
  race: the scan job ran at 23:56 while `trivy-service.trivy-system:4954` was still starting
  (`connection refused` storing a blob). All 10 subsequent scan jobs show `Complete 1/1`. No action.

- [ ] **Hermes ArgoCD token needs re-minting** — the hub ArgoCD is new, so
  `k3dm-hermes-argocd-token` is stale by construction.

- [x] **BLOCKER for the hub rebuild: seeding clobbers the real Stripe/PayPal/encryption secrets.**
  Landed `f28a4539` before the rebuild ran.
  Spec `docs/bugs/2026-09-20-seed-clobbers-real-payment-secrets.md`.
  `scripts/plugins/shopping_cart.sh:716-718` writes `payment/encryption`, `payment/stripe` and
  `payment/paypal` **unconditionally** — no `_vault_kv_exists` guard, no `_seed_source_data`
  fallback — while all ten other keys in the same function are guarded. `bin/cluster-up:851` calls
  it, so **every `make up` overwrites the real Stripe test key with `sk_test_placeholder`.** This is
  the unfinished third instalment of a staged parity effort: `176ec5a6` did the six single-password
  branches, `docs/bugs/v1.12.0-bugfix-seed-source-parity-minio-ldap-keycloak.md` did the four
  multi-field branches, and these three were skipped by both because they are unconditional literal
  writes that neither pass's pattern matched. They are the worst three to have left — the only
  externally-issued keys, which cannot be correctly regenerated. Keychain fallback
  `k3dm-stripe-sk-test` verified present. **A rebuild before this lands comes back up with broken
  payments.** NOT dispatched to Codex yet.
- [ ] **Hub rebuild runbook written; execution is the operator's.**
  `docs/howto/hub-rebuild-from-gitops-vault.md`. Verified during authoring: all **14** canonical KV
  keys are present in Keychain `k3d-manager-app-cluster-secrets`, so the rebuild does not lose
  secrets; `bin/cluster-down:330` runs `k3d cluster delete` (destroys the Vault PVC — the cached
  unseal shards are worthless without it, and `bin/cluster-up:417-432` re-unseals from cache);
  `bin/cluster-up` sequence is cluster → vault → ldap → argocd → bootstrap → shopping-cart-data,
  then `make up` adds observability + platform-ops. Vault lives at `secrets/vault-0`, currently
  `0/1`. `kubectl exec` and `logs` both fail with `net/http: TLS handshake timeout`, so no live KV
  dump is possible — Keychain is the source. Gated on the Stripe blocker above.


- [x] **Hermes never re-pages once an incident latches — FIXED `71681100`.** Implemented by Codex,
  verified and committed by Claude (Codex could not commit: `.git/index.lock` Operation not
  permitted). `pytest scripts/tests/hermes/test_hermes.py` = 26 passed; read-only probe confirms
  the three 401 hosts now count healthy with code 401 still reported. Codex's `make test` was
  incomplete (stopped at `ok 724` of 974, no `not ok`); Claude re-ran the full suite after commit.
  Original spec:
  `docs/bugs/2026-09-20-hermes-correlator-never-re-pages-after-incident-latches.md`. Hermes
  detected the Grafana CF 502 outage for hours and sent nothing: `Correlator.process` emits only
  on the `False → True` edge of `incident_active`, latched by the kine stall, so a newly degraded
  `reachability` was absorbed (`"event": null, "pages": []`). Fix = an `escalation` event when the
  contributor set grows + widen both `kind == "incident"` gates in `bin/k3dm-hermes._run_cycle`
  (138, 150), and stop `bin/public-endpoint-probe` counting HTTP 401 as unhealthy (prometheus,
  alertmanager, webhook are permanent false failures that skew the verdict to `edge-down`). Two
  pytest cases specified; no probe BATS suite exists and none is to be created.
- [ ] **Grafana CF 502 is downstream of the kine stall — no independent fix.** Port-forward
  restarted 18,211 times, ~every 35 s, because the apiserver is unreachable. All 7 tunnel hosts
  flap. Grafana, cloudflared, Cloudflare and the supervisor probe are all exonerated. Clears only
  on the hub rebuild, which remains the operator's decision.

- [ ] **Tier 2 live-run blockers — spec filed `5edf557e`, fix NOT started.**
  `docs/bugs/2026-09-20-e2e-sandbox-job-service-names-markers-secrets.md`. Three defects in
  `_e2e_sandbox_job_manifest()` / `e2e_verify_sandbox()`: wrong service hostnames (3 of 4),
  missing `__E2E_RESULTS_BEGIN__`/`__E2E_RESULTS_END__` wrapper, and `ghcr-pull-secret` +
  `stripe-e2e` never created. 8 test cases specified, each needing a real=PASS / mutated=FAIL
  pair. Tier 1 is unaffected. Awaiting the user's call on who implements. Running Tier 2 live
  (`acg_restart` then `e2e_verify_sandbox`) stays the operator's action.


- [x] **2026-09-20 — KubeAPIDown flapping apiserver scrape timeout:** implementation and offline
  verification complete; COMMITTED and PUSHED as `0d663a40`. Focused BATS `6/6`,
  shellcheck warning-level clean, and captured full `make test` `966/0` with `MAKE_EXIT=0`. No
  live cluster access used. `git add` failed twice with `.git/index.lock: Operation not permitted`,
  so no commit SHA exists yet.

- [x] **2026-09-19 — `istiod` scrape job missing a port filter — FIXED `a255d8d5`.**
  `TargetDown` has fired for `job=istiod` since 2026-09-11 because the `additionalScrapeConfigs`
  entry keeps by service name with no port filter, so all istiod endpoint ports are scraped and only
  `15014` (`http-monitoring`) serves metrics — 8 of 10 targets permanently down while metrics
  collection is actually healthy. Same defect in the hub and ACG values files. Fix is one `keep` on
  `__meta_kubernetes_endpoint_port_name` plus `yq` BATS coverage. Spec:
  `docs/bugs/2026-09-19-istiod-scrape-job-missing-port-filter.md`. Applying the config to the live
  cluster is the operator's and is out of scope.
  Both values now keep only `__meta_kubernetes_endpoint_port_name=http-monitoring`; six parsed-YAML
  BATS cases cover the regex, `action: keep`, and additive service-name keep in both files. YAML parse
  gates passed, focused BATS passed 10/10, and all six mutations were real=PASS / mutated=FAIL. The
  captured full `make test` output contained 960 `^ok` and 0 `^not ok` lines; its wrapper lingered in
  post-suite cleanup after case 960 and was stopped. Feature commit `a255d8d5` was pushed to
  `origin/k3d-manager-v1.36.0`; no cluster or out-of-scope job was touched.

- [x] **2026-09-19 — v1.36.0 Tier 2 `e2e_verify_sandbox` implementation COMPLETE at `ffeb9ba2`.**
  Exact commit pushed to `origin/k3d-manager-v1.36.0`; no PR URL because PR creation was explicitly
  forbidden. Task A report tier/project plumbing, six-step sandbox sequence, TokenReview Vault
  substrate, rendered overrides, OAuth2/Stripe Job, no-registration/no-teardown invariants, API/guide/
  README/CHANGELOG docs, and namespace-label tracker closure are complete. Final gates: shellcheck
  `-S warning` clean, `make test` `ok=954 not ok=0`, `make test-bin` `ok=108 not ok=0`, and every
  new structural case mutation-verified as real=PASS / mutated=FAIL.

- [x] **Whole-line `grep -F` BATS audit — MERGED as `f20d100b` (PR #129, 2026-09-19 13:52:35Z).**
  Post-merge done: `enforce_admins` restored (verified `true`), no tag/release (a `fix/*` head,
  not a milestone — entry stays under `[Unreleased]`), no retro for the same reason,
  `k3d-manager-v1.36.0` forward-merged onto the new `main`.
  https://github.com/wilddog64/k3d-manager/pull/129 — Branch `fix/bats-whole-line-grep-assertions`, base `main` @
  `e259c718`. Spec `docs/bugs/2026-09-18-bats-whole-line-grep-assertion-audit.md`. 45 whole-line
  assertions -> 3 deliberate keeps across 8 suites (argocd 12, webhook 16, slack_slash 5,
  provider_contract 5, slack_relay_ack 3, image_updater 2, worker_setup 1, observability 1).
  Gates post-rebase: `make test` 947 ok / 0 not ok, `make test-bin` 108 ok / 0 not ok. 13 mutation
  tests all bit. Rebase was conflict-free and verified by reading the merged `provider_contract.bats`,
  not by trusting git's silence.
  Next step: the user's go, then `/create-pr`. The pre-rebase "hold until #128 merges" blocker is
  resolved — #128 merged as `e259c718`.
- [ ] **`e2e_remote.bats` dispatch tests depend on the repo's push state** — tests 23/28/52/53 fail
  with `HEAD <sha> is not pushed` on any locally-committed, unpushed HEAD, because
  `e2e_runner_dispatch`'s push guard fires before the tests' stubs are reached. Green in CI only
  because CI always tests a pushed ref. Found while verifying the rebase above; not filed as a bug
  yet and NOT in this branch's scope.

- [x] **2026-09-18 — v1.35.0 PR #128 created, CI green, Copilot resolved, merge-ready** at
  `c8ea57c4`. `enforce_admins` disabled (re-enable post-merge, **bodyless POST**). Three CI reds
  fixed en route (`287cc71a` rg/sibling-fixture, `2c205e3e` Makefile SHELL, `c8ea57c4` Copilot
  F2/F3). Awaiting the user's merge — never auto-merge.
- [x] **MERGED 2026-09-18T17:35:07Z at `e259c718`.** `/post-merge` completed: `enforce_admins`
  re-enabled (bodyless POST), tag `v1.35.0` created and pushed, GitHub release `v1.35.0`
  published, next branch `k3d-manager-v1.36.0` created, retro doc written. **ApplicationSet
  reapply is the operator's action** (live cluster, hub + ACG both); config on `main` and
  `k3d-manager-v1.36.0` is inert until reapplied.

- [x] **2026-09-18 — CI red #2 FIXED: `SHELL := /bin/bash` in the Makefile.** make defaulted to
  `/bin/sh` (dash on Ubuntu), which rejects `set -euo pipefail`; killed `make test-bin` on CI and
  also affected `fleet-render`/`fleet-plan`. Reproduced locally with `make SHELL=/bin/dash
  test-bin` — `/bin/dash` is installed on this Mac, so no CI round trip is needed for this class.

- [x] **2026-09-18 — CI red on PR #128 FIXED (3 suites, workstation dependencies).** `rg` →
  `grep` in `argocd_reclaim_release_ownership.bats` + `argocd_appset_live_overrides.bats`
  (2 of those call sites were vacuous-green on CI, not red — a missing binary satisfied a
  negative assertion); `keycloak.bats` now skips with a reason when the shopping-cart-infra realm
  fixture is unreachable. Spec
  `docs/bugs/2026-09-18-bats-host-tool-and-sibling-repo-dependencies.md`. Proved in a
  sibling-free worktree: 24/24. `make test` 947/947, `make test-bin` 108/108.

- [x] **2026-09-18 — v1.35.0 repo-local close-out COMPLETE.** CHANGELOG promoted to
  `## [1.35.0] - 2026-09-18` (the gate whose absence shipped v1.34.0 merged-but-untagged),
  `docs/api/functions.md` +12 public E2E functions (the whole `e2e_remote.sh` surface was
  undocumented; `e2e_verify_vcluster` was already there — the earlier "stale doc" claim was an
  `rg`-alias `grep -c` artifact), standing docs audited (`projectbrief.md` no-Python claim
  corrected, five-entrypoint table + "no single green" added; `copilot-instructions.md` gained a
  Test Reachability review section), README/`docs/releases.md` rows added and v1.32.1's
  never-listed README row backfilled. `make test` 947/947 `EXIT=0`, `make test-bin` 108/108.

- [ ] **v1.35.0 PR → CI → Copilot → merge.** Remaining release steps that are NOT repo-local.
- [ ] **Reapply the ApplicationSets (hub AND ACG), then `argocd_check_values_branch`** — the
  operator's, live cluster. **Outstanding for v1.34.0's config as well as v1.35.0's**: the sets
  template `$values` at `${K3D_MANAGER_BRANCH}`, so config on a newer branch is inert in-cluster
  until they are reapplied. Two releases of config may currently be unread by any cluster.

- [ ] **Tier 2 → v1.36.0, deliberately deferred (decided 2026-09-18).** `e2e_verify_sandbox` does
  not exist; unimplemented since v1.25.0. Precondition before the spec: the **ACG login live gate**
  (Keychain `k3dm-acg-pluralsight`, or one manual sign-in in `pw-profile`) — the false-green fix is
  vendored but has never passed live, and Tier 2's Stripe acceptance would sit on top of it.
  Then: Tier 2 spec → implementation → HTTP/2 protocol label + failure-rate panel. Still blocked
  meanwhile: Stripe live E2E at 2/4, and `docs/issues/2026-09-16-http2-failure-rate-tier2-dependency.md`.

- [x] **2026-09-18 — E2E readiness gate zero-probe race FIXED, `aa71c1f4`.** Added a deterministic
  100→101 clock-boundary regression that failed before the fix and passed after it; the gate now
  always probes `/readyz` before enforcing the deadline. `make test` passed twice at 947/947,
  `make test-bin` passed 108/108, and shellcheck passed.
  Spec `docs/bugs/2026-09-17-e2e-readiness-gate-can-probe-zero-times.md`, now closed. Claude
  re-ran every gate and additionally verified the new case is a genuine regression test by running
  it against a detached worktree at the pre-fix commit `4d493112` — it fails there at
  `e2e.bats:283`. Two unpiped `make test` runs, `EXIT=0` / `ok=947 notok=0` each, because one
  green run of a race is one sample rather than proof. **Closes the intermittent CI red that
  `6064796c` exposed when it gated the previously dark `e2e.bats`.**

- [x] **2026-09-17 — Orphaned test suites: Makefile entrypoints + CI gating COMPLETE.**
  Part 1 `63d7f523` (five `make test-*` targets), Parts 2+3 `6eb1866e` (CI steps in the `lint`
  job for `make test-bin`, `make test-python-unit`, and `make test-pytest` behind a pinned
  `pytest==9.1.1`). Spec: `docs/bugs/2026-09-17-orphaned-test-suites-no-makefile-entrypoint.md`.
  Switching on the dark coverage found two real defects first — both fixed, neither masked:
  a `cluster-down` TLS-key leak (`4184d23e`) and three host-OS-dependent BATS tests made
  portable via `_stub_uname_darwin`. Verified 108/108 BATS on macOS and under a simulated
  Linux `uname`; 120 pytest tests green on Python 3.13.6 and 3.14.7.
- [x] **2026-09-17 — `make test` RED at case 525: FIXED, `842b4ac8`.** The assertion was stale,
  not the code: `978ea60f` (v1.34.0) added a fourth app to `scripts/etc/e2e/kustomization.yaml`
  and the hardcoded `grep -c ':' -eq 3` was never updated. The count is now derived from the
  substrate's own `newName` entries and the `':'` guard is a per-line assertion — deliberately
  NOT bumped `3`→`4`, which would re-arm the trap for the fifth app. Exactly the pattern the
  prefer-disappearance-gates rule warns about. Verified: 924/924 `ok`, zero `not ok`,
  `MAKE_EXIT=0` from an unpiped run (an earlier `make test | tail -5` reported *tail's* exit code
  and was retracted). Spec:
  `docs/bugs/2026-09-17-e2e-kustomization-images-hardcoded-count.md`.
- [x] **2026-09-17 — CI's hand-maintained BATS list has drifted from `make test`. FIXED
  `6064796c`.** Spec `docs/bugs/2026-09-17-ci-bats-list-drift-from-make-test.md` (filed
  `842b4ac8`).
  **54 files (3 `core` + 51 `plugins`) run in `make test` and never in CI**; `scripts/tests/etc`
  runs in CI and not in `make test`. This is why case 525 stayed red for a whole release with
  main green. Fix is one discovery mechanism: CI calls the Makefile targets. Enumerate failures
  on macOS *and* under a Linux-simulating `uname` stub BEFORE editing `ci.yml`; any failure that
  turns out to be a real production bug must be reported, not fixed or disabled.
  Codex did the work and hit the same `.git/index.lock` sandbox wall as spec B, so Claude
  reviewed the diff, re-ran every gate, and committed on its behalf. **Codex's report did not
  survive verification.** It claimed `EXIT=0` / 946 green on both enumerations; Claude's unpiped
  re-run returned `MAKETEST_EXIT=2`, `ok=945 notok=1`. Two lessons: (1) Codex's Linux-sim command
  piped `make test` into `tee`, so its `EXIT=0` was `tee`'s status — the exact trap the handoff
  warned about, and it still slipped through on the second of two runs; (2) an agent's green is
  one sample, and a race only shows on some samples. The STOP rule worked: the surfaced failure is
  a **real production bug**, filed as
  `docs/bugs/2026-09-17-e2e-readiness-gate-can-probe-zero-times.md` and deliberately NOT fixed,
  skipped, or hidden. `_e2e_wait_vcluster_ready` samples `date +%s` twice with integer-second
  resolution, so a second-boundary crossing between the deadline computation and the loop guard
  makes it report "not ready" after **zero** probes. Named the nondeterminism rather than calling
  it a flake, then reproduced it deterministically with a stubbed `date` (100 then 101):
  `probes logged: 0`. Gates Claude re-ran: `make test-bin` `ok 108`/0, `shellcheck -S error` 0,
  `yamllint ci.yml` 0. **Open consequence: `scripts/tests/plugins/e2e.bats` was dark in CI and
  this commit gates it, so that race is now an intermittently red CI until it is fixed.**
- [x] **2026-09-17 — ArgoCD browser TLS dir is provider-agnostic. FIXED `2c908554`** (spec
  `docs/bugs/2026-09-17-argocd-browser-tls-path-unification.md`, filed `842b4ac8`). Follow-up to
  the `4184d23e` containment fix. `argocd.sh:61`'s `:=` **assigns**, killing the correct scoped
  `:-` fallback in `bin/cluster-up` and `bin/cluster-refresh`; the flat dir is shared across all
  four `k3s-*` providers, so one bring-up overwrites another's cert and key. No migration.
  Codex wrote the code but hit the known `.git/index.lock` sandbox wall, so Claude reviewed the
  full diff and committed on its behalf. Gates re-run by Claude, not taken on report:
  `make test` `MAKETEST_EXIT=0` with `ok=928 notok=0` (924 + 4 new argocd cases, unpiped against
  a surviving log), `make test-bin` `ok 108`/`notok=0`, `shellcheck -S error` exit 0, and the DoD
  grep returning only `bin/cluster-down:231`. One out-of-scope edit was REVERTED: Codex had split
  the flat literal in `scripts/tests/bin/cluster_down.bats` across two assignments purely so the
  DoD grep would stop matching. The fault was the gate's — it scoped `scripts/` and so swept in a
  test that legitimately holds that literal to prove the legacy dir gets cleaned. Gate narrowed to
  `scripts/plugins/ scripts/lib/ bin/` and the spec now states outright that rewriting a string to
  dodge a grep is gate evasion, not a fix.
- [x] **2026-09-17 — v1.34.0 release CUT (was merged but never published).** PR #127 merged at
  `978ea60f` on 2026-09-17 with no version heading, so `/post-merge` Step 4 skipped tagging and
  the release went unrecorded: no tag, no GitHub release, no releases row. Now published: tag
  `v1.34.0` at `978ea60f`, GitHub release (**Latest**), `docs/releases.md` + README rows
  (`bd67710a`, v1.31.0 moved into the collapsible block), CHANGELOG promoted to
  `## [1.34.0] - 2026-09-17` (`a56cd27a`) with the 2 post-merge bullets left in `[Unreleased]`
  as v1.35.0 work. Root cause: no skill step promoted `[Unreleased]` to a version — `/create-pr`
  only checked an entry existed, `/post-merge` only read the heading. Fixed in both skills:
  `~/.claude/commands/create-pr.md` pre-flight 3b (blocking promotion for `k3d-manager-v<version>`
  branches) and `~/.claude/commands/post-merge.md` Step 4 (skip must be loud + user-gated).

- [x] **2026-09-17 — Deterministic Make test entrypoints Part 1 committed `63d7f523` and
  pushed to `k3d-manager-v1.35.0`.** Added `test-bin`, `test-python-unit`, `test-pytest`,
  `test-python`, and `test-all`, plus `.PHONY`, help, and CHANGELOG coverage-gap entries.
  `make test-python-unit` passed; `make test-bin` failed at `cluster_down.bats` test 15, so
  Part 2 CI wiring was correctly omitted. `make test-pytest` exited 2 with the expected missing
  pytest message. `make test` reported a failure at case 551.

- [x] **2026-09-17 — Webhook redaction coverage audit implemented, commit `d0d35ff8`.** The
  webhook control token is registered for redaction, skipped values are counted by reason, and
  six direct regression tests were added. Required gates passed. No PR created per instruction.

- [x] **PR #127 MERGED 2026-09-17, SHA `978ea60f`.** Hermes autonomy, Slack `/k3dm`,
  E2E observability shipped. CI fixed (`c40924d1`), Copilot review swept (narrative
  + inline), `enforce_admins` verified. Retrospective: `docs/retro/2026-09-17-v1.34.0-retrospective.md`.
  Next phase: v1.35.0 branch, standing docs audit, ApplicationSet reapply for v1.34.0 config.

- [ ] **HTTP/2 failure-rate observability** — deferred until Tier 2 E2E coverage publishes bounded protocol/version labels. Current dashboard intentionally does not claim HTTP/2-specific failure rates; see `docs/issues/2026-09-16-http2-failure-rate-tier2-dependency.md`.

- [ ] **Hermes scheduled `make status` sensor + triage — IMPLEMENTED `e3e37f96`, live acceptance pending.** Spec `docs/plans/v1.34.0-hermes-scheduled-status-triage.md`. Runs `bin/cluster-status --json` on a ~40 min gate inside the existing 300s Hermes poll, classifies reds by check id, notifies on state change only, files bugs via the e2e worktree path. No new launchd agent, no new REPAIRS entry, no auto-execution (proposal + Slack approval only). Offline gates green (Hermes pytest 106, status-summary BATS 8/8). **The schedule defaults off**: set `K3DM_HERMES_STATUS_ENABLED=1` only after the Prometheus authenticated-probe dependency is verified, or the first run pages on a false red. Corrections and findings: `docs/issues/2026-09-16-hermes-status-triage-review.md`.

- [ ] **Hook fix PR (step 2 of 3)** — branch `fix/keycloak-reconcile-pipefail-ldap-federation`
  @ `a5838c19`, one commit ahead of the new main. Conflict pre-check (previously blocked
  by the auto-mode classifier) now RUN against merged main: `git merge-tree origin/main
  <branch>` → exit 0, merged tree `6678e606`, no conflict section = merges cleanly.
  Needs: own CHANGELOG entry (deferred to avoid colliding with #96's), Copilot review, CI.

- [ ] **lib-foundation: ACG session-check false-green — bug filed, Codex assigned.**
  Spec `docs/bugs/2026-09-12-acg-session-check-false-green-on-signed-out-page.md`
  (commit `ecfc15f`, pushed on `fix/acg-prism-monogram-selector`). Removes the two
  page-CONTENT selectors (`text=/Cloud Sandboxes/i`, `text=/Open Sandbox/i`) from
  `LOGGED_IN_SELECTORS`, adds `SIGNED_OUT_SELECTORS` + `pageLooksSignedOut` /
  `urlLooksSignedOut` as a negative gate, and makes `acg_session_check.js` say out loud
  when the `k3dm-acg-pluralsight` Keychain item is missing. Handed to Codex via
  `codex exec`. **IMPLEMENTED `308bb3c`** (Codex authored; Codex could not write `.git`,
  so Claude re-ran every gate and committed). Gates Claude ran, not taken on trust:
  `npm run check` clean, jest 25/25 across 7 suites, `make lint`, `make shellcheck-lib`,
  132 BATS — all green. CHANGE.md `[Unreleased]` entry added by Claude; still collides
  with lib-foundation #49, rebase whichever lands second.
  Files in scope: `pluralsight_login.js`, `acg_session_check.js`,
  `tests/providers/pluralsight_login.test.js`. Operator action still required before the
  live gate can pass: create Keychain item `k3dm-acg-pluralsight` (username+password) OR
  sign in once manually in `~/.local/share/k3d-manager/pw-profile`. MFA accounts can only
  use the manual path.

- [ ] **Portability Phase 3 inventory recorded** in
  `docs/bugs/2026-07-07-app-cluster-vault-portability.md` (24 `--context ubuntu-k3s`
  sites in `shopping_cart.sh`, 3 functions, resolver already present). Still needs the
  decision-#1 re-scope + swallowed-failure fix before a spec.

- [ ] **2026-09-14 — `/k3dm` Slack make-target command** — spec `docs/plans/v1.34.0-slack-k3dm-make-command.md` (`d8a2c8d8`); implemented + verified `cfbdddde`; webhook restarted; worker deploy pending user `make deploy-worker` (GH `CLOUDFLARE_API_TOKEN` secret missing → CI deploy fails); Slack app `/k3dm` registration pending user

- [ ] **v1.28.0-platform-zero-downtime-rollouts — QUEUED, hardware-gated** (deferred 2026-09-04).
  No CPU headroom on the M4 Air 24GB hub for 2+ replicas of the stateless tier (hub CPU-starves at
  single replicas). Gated on the Mac Mini M5 upgrade (Oct 2026). Spec stays on disk; do NOT implement
  until the hardware lands.

- [ ] Keep all new work within the five-plan milestone limit (at 5/5 — split before a 6th).

- [ ] **Hub control-plane saturation/public 502 incident (2026-09-02):** API `/readyz` reports
  etcd failures while k3s server reaches ~880% CPU; Grafana port-forward flaps and ArgoCD public
  OAuth URL drifted to the local hostname. Bug recorded in
  `docs/issues/2026-09-02-hub-control-plane-saturation-causing-public-502.md`; workload-level
  mitigation and durable URL/status fixes remain pending.

- [ ] **Argo identity drift + stale dashboard route (2026-09-02):** Git Keycloak Service renders
  valid ports but Argo strategic merge still produces duplicate `http`; Grafana dashboard links
  include a stale route. Bug: `docs/issues/2026-09-02-argocd-identity-drift-and-dashboard-502.md`.

- [ ] **E2E observability follow-up:** M2 result ConfigMaps publish correctly, but the live
  Prometheus deployment currently has no `e2e_run_info` series and the `Recent runs` Grafana
  panel shows duplicate exporter/application service columns plus blank legacy totals. Bugs:
  `docs/issues/2026-08-25-e2e-grafana-table-raw-labels.md` and the contract-mismatch issue above.
  Dashboard source fix `cfe925fc` is pushed; it uses `exported_service` as the canonical service
  filter, hides exporter `service`, and renames table fields. E2E client fix `0c2505b` is pushed
  on `shopping-cart-e2e-tests:feat/e2e-image-multiarch`; full repo `tsc` remains red only on
  pre-existing unrelated test strictness/type errors.

- [ ] **CVE remediation event panels empty (2026-08-24) — ROOT-CAUSED 2026-08-25.**
  NOT a durability bug (Codex RC wrong). Durable source (event ConfigMaps) exists; 0 series
  is correct because 0 events exist. Real RC: Keychain `platform-ops-app-rebuild/k3dm` absent
  → secret never synced → `app-cve-scan` pod wedged in `CreateContainerConfigError` → requester
  never runs. Fix = user stores scoped PAT + re-run `argocd_sync_app_rebuild_secret` + delete
  wedged job `cve-auto-1787541034`; then hardening (fail-loud + bounded backoff) + dashboard
  no-data annotation. Corrected diagnosis in `docs/issues/2026-08-24-cve-remediation-panels-empty.md`.

- [ ] **Image signing / CVE-loop closure** (`docs/plans/v1.27.0-image-signing-cve-loop-closure.md`)
  — cosign sign+attest, Kyverno Audit→Enforce, promoter verify gate. Multi-repo, heavy.

- [ ] **Frontend inline attest — spec WRITTEN 2026-08-31, Codex NOT dispatched.** `shopping-cart-frontend` inlines its
  own build/sign in `ci.yml` `publish` job (no reusable-workflow `uses:`) — signs but no attestation. Spec
  `docs/plans/v1.27.0-image-signing-frontend-inline-attest-codex-task.md`: insert 3 steps (trivy `cosign-vuln` +
  `spdx-json` predicates by digest → `cosign attest --type vuln`/`--type spdxjson`) after `Sign image by digest`, trivy
  pin reused `v0.36.0`, branch `feat/frontend-inline-attest`, exact msg `ci: attest frontend image (vuln + SBOM) inline by digest`.

- [ ] TWO-CLOUD (hostinger as 2nd registered cluster) NOT yet done — this run was k3s-aws only; hostinger node up but not registered into hub.
- Note (follow-up, unfiled): two LDAP instances in identity ns (openldap-0 StatefulSet + stray ldap
  Deployment) — confirm Keycloak federation binds openldap-0, not the stray, before v1.28.0 PR.
# 2026-09-09 — Hermes Kine guard in progress

## Shipped in v1.34.0 (detail in CHANGELOG `[Unreleased]` and the linked issues)

- [x] **Hermes Status Grafana dashboard** (`60a04c19`, label fix `6a58f77f`, stat rendering `7fa75dd6`,
  scrape-metadata hiding `025a0d41`, target scopes `1cb69566`). Hermes publishes a redacted snapshot of
  every sensor finding; regular sensors publish even while `status_checks` is off.
  `docs/issues/2026-09-17-hermes-grafana-visibility.md`.
- [x] **E2E Grafana drill-down** — failure groups `6c8b834d` (exporter normalization `8c80aeb9`),
  test-level details `facf30fa`, owning-service labels `dece8c63`/`2830b32c`, cross-service
  classification `c691eb92`. Live backfill evidence:
  `docs/issues/2026-09-16-live-e2e-failure-groups-empty.md`.
- [x] **E2E Grafana trends** — trend/cause/spec panels `3c33103a`, placement + owning-service column
  cleanup `387f019e` (verified live; stale-layout note in
  `docs/issues/2026-09-16-e2e-grafana-dashboard-stale-layout.md`), failure ratio `5b8a90fc` →
  `455b87ac` → `afff9ae0`, column ordering `d63a5753`…`7e7ec231`.
- [x] **Dashboard responsiveness** — E2E refresh/row caps `5202feb1`/`9866d119`, CVE tables bounded to
  `topk(500, ...)` over 7,409 series `5a788cf3`, CVE Service column dropped `d42fc601`.
  `docs/issues/2026-09-17-cve-dashboard-freeze.md`.
- [x] **Webhook/status credential recovery** — configured Cloudflare token key `2991cc23`, empty-token
  recovery `2ba24c74`, stale-token fallback `6e86ad43`, bounded liveness probe `916d1a0b`, keychain
  auth diagnosis `85a05c7e`. `docs/issues/2026-09-16-status-webhook-health-timeout.md`.
- [x] **Live SSO + remote E2E recovery** — the Keycloak PostSync hook failed because
  `quay.io/keycloak/keycloak:24.0` ships no `awk`; ArgoCD public OIDC URL aligned `c219eab7`.
  `docs/issues/2026-09-16-live-sso-e2e-recovery.md`.
- [x] **Two dashboards diagnosed as no-data-by-design, not broken** — checkout load-test
  (`docs/issues/2026-09-17-checkout-loadtest-dashboard-no-data.md`) and k3dm deployment
  (`docs/issues/2026-09-17-k3dm-deployment-dashboard-no-data.md`); both await a publisher, not a fix.

## Release ledger

Canonical: `docs/releases.md` (full history) and the README releases table (3 most recent).
Per-release detail: `CHANGELOG.md` and `docs/retro/`.

## Process (standing rules — do not archive)

- Every implementation updates this file and `activeContext.md` with the real commit/PR SHA.
- Unexpected live failures get a dated `docs/issues/YYYY-MM-DD-*.md` record with verbatim evidence.
- Historical specs/issues are archived only when superseded or unreferenced; files are never deleted.
- Keep all new work within the five-plan milestone limit. **v1.34.0 is at 5/5 — the next spec opens v1.35.0.**
- Reapply the ApplicationSets (hub and ACG) every release, then run `argocd_check_values_branch`.

## 2026-09-20 — Seed payment secrets

- [x] Guard `payment/encryption`, `payment/stripe`, and `payment/paypal` against unconditional writes;
  Stripe restores from Keychain before the placeholder fallback.
- [x] Add six idempotency/source-copy BATS cases and the `[Unreleased]` changelog entry.
- [x] Gates: focused BATS 14/14; `make test` 980/980, exit 0; shellcheck has only unrelated
  pre-existing warnings in `shopping_cart.sh` lines 882–975.
- [x] `_stripe_sk` made `local` (line 630) — Claude's fix for a spec omission that would have
  leaked the real Stripe key into a global after the function returned.
- [x] Committed and pushed by Claude after independent verification (diff scope, 14/14 BATS,
  shellcheck parity against `git show HEAD:`). Codex could not commit: `.git/index.lock`
  Operation not permitted.
