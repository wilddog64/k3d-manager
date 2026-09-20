# Active Context — k3d-manager

> Compressed 2026-09-17 (v1.34.0 Grafana/observability block closed → collapsed to pointers).
> Full pre-compression detail: `memory-bank/archive/activeContext-2026-09-17.md`.
> Settled fixes live as pointers; detail in `memory-bank/archive/`, `CHANGELOG.md`,
> `docs/retro/`, `docs/issues/`, `docs/bugs/`, git history, and auto-memory.

## Current focus

- **2026-09-20 — Tier 2 live-run blockers filed as `5edf557e`.** Spec
  `docs/bugs/2026-09-20-e2e-sandbox-job-service-names-markers-secrets.md`. Tier 2
  (`e2e_verify_sandbox`, implemented `ffeb9ba2`) is code-complete and structurally green but has
  never executed live; three defects in the sandbox Job path would fail the first run:
  (1) three of four service hostnames do not exist — `basket`/`order`/`payment` instead of
  `basket-service`/`order-service`/`payment-service`, all four ports already correct, and
  `_e2e_sandbox_render_overrides` (`e2e.sh:149-150`) already uses the right names, so the file
  contradicts itself; (2) the Job command omits the `__E2E_RESULTS_BEGIN__`/`__E2E_RESULTS_END__`
  wrapper the parser at `e2e.sh:636` requires, so `passed`/`total`/`failed` stay `None` and
  pass/fail attribution is dead; (3) neither `ghcr-pull-secret` nor `stripe-e2e` is ever created
  in the sandbox — `stripe-e2e` has exactly one repo-wide reference, the `secretKeyRef` that
  consumes it — so the Job never starts. All three are Tier 2 only; Tier 1 is correct in each
  case, which is why review missed them: the sandbox manifest is a near-copy of the Tier 1 one and
  diverged where Tier 2's substrate differs. The structural BATS suite asserts manifest shape and
  cannot detect any of them. **The ACG login is NOT a blocker** — it is a routine step run many
  times before; `acg_restart` fronts any Tier 2 run. No `ubuntu-k3s` context exists right now, so
  the sandbox is simply not provisioned at the moment.
  Spec commit is local only, NOT pushed — Codex is mid-run on the same branch and pushing first
  would hand it a non-fast-forward. Push after Codex reports.


- **2026-09-20 — KubeAPIDown flapping apiserver scrape timeout implementation complete; commit
  blocked by the session's read-only `.git` metadata.** Added `_observability_ensure_apiserver_scrape_timeout` to patch only the existing
  hub ServiceMonitor endpoint with the default `45s` timeout, preserve idempotency, degrade safely
  when the CRD or ServiceMonitor is unavailable, and wire it immediately after the ArgoCD
  ServiceMonitor ensure. Added six offline BATS cases and the `[Unreleased]` CHANGELOG entry.
  Focused suite passed 6/6; shellcheck `-S warning` passed; captured `make test` finished with
  `966` ok, `0` not ok, `MAKE_EXIT=0`. Mutation evidence is recorded in the task handoff; no
  cluster was touched. Explicit `git add` failed twice with `fatal: Unable to create
  .git/index.lock: Operation not permitted`; no commit or push SHA exists yet.

- **2026-09-19 — `istiod` scrape job missing a port filter: spec filed `96766915`, ASSIGNED to Codex.**
  Operator reported a "Target disappeared from Prometheus target discovery" alert. Nothing
  disappeared — the live rule is kube-prometheus-stack `TargetDown`, and `job=istiod` has been
  firing since 2026-09-11T16:39:47Z. Root cause: the `istiod` `additionalScrapeConfigs` entry in
  `kube-prometheus-stack-values.yaml:29-38` keeps targets by **service name with no port filter**,
  so all istiod endpoint ports are scraped. Only `15014` (`http-monitoring`) serves metrics; 15010
  is gRPC/XDS (its HTTP/2 preface reads as a malformed HTTP/1 response), 15012 is XDS over TLS
  (`EOF`), 15017 is the injection webhook (`400`), and 8080 has no `/metrics` handler (`404`).
  8 of 10 targets down = 80% > the 10% threshold. **Metrics collection is healthy** —
  both `http-monitoring` targets `up`, `count(pilot_xds)` = 4 — so this is pure alert noise that
  trains the operator to ignore `TargetDown`. `kube-prometheus-stack-acg-values.yaml:82-91` carries
  a byte-identical block with the same defect. Fix is one `keep` on
  `__meta_kubernetes_endpoint_port_name` = `http-monitoring` in both files, plus `yq` BATS coverage
  in `observability_federate_self_scrape.bats`. Note the `8080` target arrives with an **empty**
  endpoint port name (the `endpoints` role also emits unmatched pod container ports), so a keep on
  the port *name* drops it while a port-number test would not — keep the good port, do not blacklist
  the bad ones. Spec: `docs/bugs/2026-09-19-istiod-scrape-job-missing-port-filter.md`.
  **Applying the config to the live cluster is the operator's, explicitly out of scope.**
  Two adjacent findings deliberately left out of scope: `job=federate-acg` is also `TargetDown`
  (`host.internal:19190` refused) but is a genuinely dead endpoint, expected with no live ACG
  sandbox; and `kube-prometheus-stack-apiserver/0` is down with `context deadline exceeded` on
  `https://192.168.97.5:6443/metrics`, correlating with the firing `NodeSystemSaturation` and
  `CPUThrottlingHigh` alerts, so it reads as node CPU starvation rather than an apiserver fault.

- **2026-09-19 — `istiod` scrape port filter FIXED and pushed as `a255d8d5`.** Added the literal
  `http-monitoring` endpoint-port `keep` relabel rule to both hub and ACG values, with six parsed-YAML
  BATS cases covering the new regex/action and additive service-name rule. YAML parsing passed; focused
  BATS passed 10/10; mutation evidence was real=PASS / mutated=FAIL for all six assertions. The full
  captured `make test` emitted 960 `^ok` and 0 `^not ok` lines; its wrapper remained in post-suite
  cleanup and was stopped after the final case. No cluster was touched and no out-of-scope jobs/files
  were changed. Exact feature commit `a255d8d5` is on `origin/k3d-manager-v1.36.0`.

- **2026-09-19 — Tier 2 sandbox harness implemented and pushed as `ffeb9ba2`.**
  `e2e_verify_sandbox` now follows the locked v1.25.0 six-step sequence with disposable in-sandbox
  ArgoCD, TokenReview Vault wiring, rendered order/payment overrides, OAuth2/Stripe Job settings,
  shared sandbox reporting, no hub registration, and no teardown. Task A parameterizes tier/project,
  extends 8081/8082 attribution, and makes replay tier-aware. Structural BATS covers all six contract
  points plus public dispatchability. Gates: shellcheck `-S warning` clean; `make test` 954/0;
  `make test-bin` 108/0; six mutation pairs real=PASS/mutated=FAIL. Namespace-label tracker marked
  CLOSED. Pushed to `origin/k3d-manager-v1.36.0`; no PR created (explicitly forbidden).

- **2026-09-19 — whole-line `grep -F` audit MERGED as `f20d100b` (PR #129, merged 13:52:35Z).**
  Post-merge complete: `enforce_admins` re-enabled via bodyless POST (verified `enabled=true`),
  `main` synced locally, `k3d-manager-v1.36.0` forward-merged onto the new `main`. **No tag or
  release** — the head was `fix/bats-whole-line-grep-assertions`, not a milestone branch, so its
  entry correctly stays under `[Unreleased]`; nothing was skipped silently. No retro, for the same
  reason. 42 whole-line source assertions narrowed across 8 suites; `make test` 947/0,
  `make test-bin` 108/0. **Copilot found 3 issues, all valid, and two were real semantic losses in
  my own narrowing** — the `get-pods` payload gate had dropped `namespace` and the diagnostics
  relay gate had dropped `payload` and `meta`, so either could have been removed from the worker
  undetected. Sweeping the other 40 conversions for the same shape found a third Copilot missed:
  the ask-transcript gate had dropped `delete=False`, where deletion destroys the transcript the
  test claims to capture. Three further candidates were left narrowed deliberately, because the
  dropped token is not part of what the `@test` name claims. All four restored tokens were
  mutation-verified. Findings: `docs/issues/2026-09-19-copilot-pr129-review-findings.md`.
  **Lesson: a green suite cannot detect a weakening — only mutation can.**

- **2026-09-19 — `.github/copilot-instructions.md` gained an **Assertion Strength (v1.36.0+)**
  review section.** Closes the gap noted after v1.35.0: the release's most reusable lesson — that
  `run <binary>` plus a non-zero-status assertion is **vacuously green** when the binary is absent,
  because exit 127 satisfies it — was in the CHANGELOG and the retro but in no review instruction,
  so nothing would have caught the next instance. Three rules added, all of which pass CI by
  construction and therefore must be caught by a human or Copilot: (1) `run <binary>` + non-zero
  status, requiring a positive `output` assertion or a `command -v` + `skip` guard; (2) `grep -F`
  of a whole line of source code, with the narrower idioms including `declare -F`; (3) a narrowing
  that dropped a token the `@test` name claims — the PR #129 defect class, where three assertions
  dropped `namespace`, `payload`/`meta` and `delete=False` respectively while staying green.
  Filed on this branch rather than on `fix/bats-whole-line-grep-assertions` per `/post-merge`
  Step 7b (standing-doc updates belong in the first commit on the next feature branch), and to
  avoid re-opening a Copilot-reviewed, merge-ready PR.

- **2026-09-18 — v1.35.0 RELEASED at `e259c718` (merged 17:35:07Z, tag+release pushed).** Post-merge
  complete: `enforce_admins` re-enabled via bodyless POST (verified `enabled=true`); tag `v1.35.0`
  created and pushed to origin; GitHub release published with full CHANGELOG notes;
  `k3d-manager-v1.36.0` branch created on the merge SHA; retrospective doc written at
  `docs/retro/2026-09-18-v1.35.0-retrospective.md`. **ApplicationSet reapply is the operator's
  action** on the live cluster (hub + ACG, both required to pick up v1.35.0 config; deployment
  on main and k3d-manager-v1.36.0 is currently inert until sets are reapplied — the issue was
  first identified and documented in v1.33.0 and remains unfixed operationally).
- **2026-09-18 — PR #128 open and MERGE-READY at `c8ea57c4`.** v1.35.0.
  https://github.com/wilddog64/k3d-manager/pull/128
  All gates green: `lint` pass, `detect` pass, CodeQL (actions/js/python) pass, GitGuardian pass,
  `stage2` skipping (conditional, not a gate). 0 unresolved review threads.
  **`enforce_admins` is DISABLED** — must be re-enabled after merge with a **bodyless POST**
  (`-f enabled=true` returns HTTP 422). `required_approving_review_count` is 1 and Copilot only
  COMMENTED, so `mergeable_state` reads `blocked`; with enforce_admins off the owner can still
  merge. That is the normal shape here, not a problem.
  **Copilot: 3 findings, 0 false positives, all fixed and resolved.** F1 (Makefile pipefail) was
  already fixed in `2c205e3e` before the review landed — Copilot reviewed `404d2139`. F2/F3 are
  the same defect twice: a required dependency treated as optional
  (`docs/issues/2026-09-18-copilot-pr128-review-findings.md`).
  **Three CI reds before green, all one family: "green on the maintainer's macOS box, impossible
  on Linux."** (1) `rg` in 3 BATS suites — and 2 call sites were `run rg …` + `[ status -ne 0 ]`,
  so a missing binary SATISFIED the negative assertion: vacuous-green, not red. (2) `keycloak.bats`
  `cp`'d a fixture from the shopping-cart-infra sibling checkout CI never clones. (3) the Makefile
  declared no `SHELL`, so `set -euo pipefail` recipes ran under dash. Commits `287cc71a`,
  `2c205e3e`, `c8ea57c4`.
  **Most reusable finding: `/bin/dash` IS installed on this Mac.** So the sh-vs-bash class is
  locally reproducible — `make SHELL=/bin/dash <target>` — and never needs a CI round trip again.

- **2026-09-18 — CI red #2 on PR #128: the Makefile had no `SHELL`, so recipes ran under dash. FIXED.**
  All 947 BATS passed on the runner this time; the step died afterwards at `make test-bin` with
  `/bin/sh: 1: set: Illegal option -o pipefail`. Root cause: make defaults to `/bin/sh`, which is
  **dash** on Ubuntu and has no `pipefail`, while macOS `/bin/sh` is bash in sh mode and accepts
  it. Five recipes use `set -euo pipefail`: the three new v1.35.0 test targets **plus
  `fleet-render` and `fleet-plan`** — two live AWS targets that carried the same latent defect and
  would have failed on any Linux host. Fixed with one line, `SHELL := /bin/bash`; bash is already
  a hard dependency of the dispatcher. **Reproduced deterministically before fixing**:
  `make SHELL=/bin/dash test-bin` reproduces the CI error verbatim, and `/bin/dash` turns out to
  be installed on this Mac — so this class of failure is locally reproducible from now on and
  does not need a CI round trip. `SHELL :=` confirmed honored via a probe (`ps -o comm=` in the
  recipe reports `/bin/bash`).
  Pattern worth keeping: **three CI reds in a row on this PR were all "passes on the maintainer's
  macOS box, fails on Linux"** — `rg` vs `grep`, a sibling-repo fixture, and `sh` vs `bash`. The
  release that turned the lights on immediately found three of them in its own tooling.

- **2026-09-18 — CI red on PR #128: three BATS suites depended on the maintainer's laptop. FIXED.**
  Local `make test` was 947/947 green on macOS and CI was red — the exact failure mode this release
  exists to close, reproduced on the release PR itself. Two defects, both pre-existing and both
  dark until `6064796c`:
  (a) `argocd_reclaim_release_ownership.bats` (7 sites) and `argocd_appset_live_overrides.bats`
  (1 site) invoked **`rg`**, which is not a repo dependency and is absent on `ubuntu-latest`.
  Worth noting: two of those sites were `run rg …` + `[ "$status" -ne 0 ]`, so a missing binary
  (127) *satisfied* the negative assertion — those cases were silently **vacuous** on CI, not red.
  That is the more dangerous half: a suite can be green and assert nothing.
  (b) `keycloak.bats:45` `cp`'d a realm fixture from the **sibling repo**
  `shopping-carts/shopping-cart-infra`, which CI never clones. The correct idiom already existed
  at `shopping_cart.bats:86` (a `[[ -d ]]` guard), so keycloak.bats was the outlier, not the
  precedent. Fixture deliberately NOT vendored — it is owned by shopping-cart-infra and a copy
  would drift from the realm actually deployed.
  Spec `docs/bugs/2026-09-18-bats-host-tool-and-sibling-repo-dependencies.md`. Verified the way
  the bug demanded: a detached **worktree in the scratchpad with no sibling repo**, mirroring CI —
  24/24 pass there, the keycloak case skipping with its reason printed and the reclaim case
  passing with real `grep`. Local `make test` 947/947 `EXIT=0`, `make test-bin` 108/108.
  Lesson, now also a Copilot review rule: `rg` is aliased to `grep` on this machine, so a test
  that uses it passes locally and cannot run in CI. Sweep with
  `command grep -rn '\brg\b' scripts/tests/` before trusting a local green.

- **2026-09-18 — v1.35.0 release close-out (repo-local) DONE.** Four items, no cluster touched:
  1. **CHANGELOG promoted** `[Unreleased]` → `## [1.35.0] - 2026-09-18`. This is the gate that
     shipped v1.34.0 merged-but-untagged: `/post-merge` Step 4 skips tagging when it finds no
     version heading, so the promotion must land BEFORE the PR, not after the merge.
  2. **`docs/api/functions.md` +12 public E2E functions.** Correction to an earlier claim in this
     session: `e2e_verify_vcluster` WAS already documented (line 113) — the `grep -c` that said
     otherwise was the `rg` alias, not grep. The real gap was larger: `e2e_prune_images` plus the
     **entire** `scripts/plugins/e2e_remote.sh` public surface (11 functions) had never been
     listed, including `e2e_result_publish`, the SSH forced command that is the sole writer of the
     hub e2e-result ConfigMap. Lesson: `grep -c` under the rg alias is not a trustworthy
     absence proof — confirm an absence with `command grep -n` and read the hit.
  3. **Standing docs audit.** `memory-bank/projectbrief.md`: the "Pure Bash, Zero Framework
     Dependencies" section claimed "no Python ... in the critical path", which has been false
     since Hermes and `bin/k3dm-webhook` (both Python, both stdlib-only) — rewritten as "Bash
     Core, Stdlib-Only Satellites"; "Enforcement at Commit Time" gained the five-entrypoint table
     and the explicit statement that **there is no single green** (`make test` excludes
     `scripts/tests/bin`); `projectBrief.md` case fixed; Repository Structure gained
     `docs/{bugs,issues,guides,retro,api}`. `.github/copilot-instructions.md` gained a
     **Test Reachability (v1.35.0+)** review section: directory discovery not hand-maintained
     lists, the two-root distinction, `bin/` coverage, Python coverage, host-state stubbing, and
     "flag a timeout loop whose deadline is checked before the first attempt" — the generalized
     form of `aa71c1f4`.
  4. **Releases tables.** README top table now v1.35.0/v1.34.0/v1.33.0 (3 most recent), with
     v1.32.0 demoted into `<details>`. Also fixed a pre-existing gap: **v1.32.1 was missing from
     README entirely** — it is in `docs/releases.md` but had never been added to either README
     table; its canonical row was reused verbatim into `<details>`.
  Gates: `make test` `EXIT=0` `ok=947 notok=0`; `make test-bin` `EXIT=0` `ok=108 notok=0`.

- **2026-09-18 — Tier 2 deliberately NOT in v1.35.0.** Recommendation given and accepted: open it
  as the v1.36.0 milestone instead. `e2e_verify_sandbox`, the entrypoint
  `docs/plans/v1.25.0-e2e-harness-tier2-sandbox.md` names, does not exist anywhere in the repo —
  Tier 2 has been unimplemented since v1.25.0, so the `project_e2e_verification_harness`
  "gate DONE v1.26.0" note refers to Tier 1 and the promotion gate only. Reasons to defer, in
  weight order: (a) its substrate prerequisite is **unproven** — Tier 2 runs through the ACG login
  path, whose false-green defect has a fix vendored in `scripts/lib/foundation/` but whose live
  gate has never passed (still needs Keychain `k3dm-acg-pluralsight` or one manual sign-in), and
  building a Stripe acceptance gate on a login layer known to report success on a signed-out page
  would produce a green that means nothing; (b) its DoD is irreducibly live and irreducibly the
  operator's — only the structural BATS is offline-testable, so it is not a Codex task and it
  serializes one-agent-per-sandbox inside a 4h+4h window; (c) 8 DoD items + a new public function
  + a guide section is a milestone, not a release tail; (d) v1.35.0 is coherent as-is.
  Sequencing for v1.36.0: ACG login live-gate → Tier 2 spec → Tier 2 → HTTP/2 label + panel
  (`docs/issues/2026-09-16-http2-failure-rate-tier2-dependency.md`). Blocks until then: Stripe
  live E2E stays 2/4, and the HTTP/2 failure-rate panel stays deferred.

- **2026-09-18 — vCluster readiness zero-probe race FIXED, `aa71c1f4`.** `_e2e_wait_vcluster_ready`
  now probes `/readyz` before checking the integer-second deadline. The deterministic regression
  failed against the old implementation and passed after the fix. `make test` passed twice at
  947/947, `make test-bin` passed 108/108, and shellcheck passed for both touched shell files.
  **Verified independently by Claude, not taken on report.** The claim worth checking was that
  the new case is a real regression test rather than a tautology, so it was run against the
  PRE-FIX tree: a detached worktree at `4d493112` with only `e2e.bats` copied in, where it fails
  at `e2e.bats:283` while `e2e.sh:166` still holds the old pre-test guard. Claude's own gates:
  `make test` twice, unpiped, `EXIT=0` / `ok=947 notok=0` both times (946 + the one new case);
  `make test-bin` `ok=108 notok=0`; `shellcheck -S error` 0; diff scope 3 files; the 600s default
  at `e2e.sh:11` and the `--no-exit` soft-probe contract both untouched; trailers present.
  **Codex committed and pushed unaided this time** — the `.git/index.lock` sandbox wall that
  blocked the two previous tasks is intermittent, not absolute; `reference_codex_exec_cannot_commit_git_lock.md`
  already says "often denied (not always)" and this is the "not always".
  Codex also improved on the spec: the spec's `date` stub used an incrementing shell variable,
  Codex used a sentinel file in `BATS_TEST_TMPDIR`, which is the sounder idiom for a stub called
  across subshell boundaries. Its version was kept.
  **Consequence: the release branch has no known red left.** The intermittent CI red that
  `6064796c` exposed by gating `e2e.bats` is closed.

- **2026-09-17 — Two specs filed and dispatched to Codex, sequentially (never in parallel — both
  target `k3d-manager-v1.35.0`, and the CI spec runs the full suite the TLS spec modifies, so two
  concurrent `codex exec` runs in one worktree would collide on the push and corrupt each other's
  baseline).** Both filed on `842b4ac8`.
  - **B — ArgoCD browser TLS path unification** (dispatched first):
    `docs/bugs/2026-09-17-argocd-browser-tls-path-unification.md`. `argocd.sh:61` uses
    `: "${VAR:=...}"`, which **assigns**, so the correct provider-scoped `${VAR:-...}` fallback in
    every `bin/` script is dead code wherever the plugin is sourced first. The flat dir is shared
    across `k3s-aws`/`k3s-az`/`k3s-gcp`/`k3s-hostinger`, so a second provider's bring-up silently
    overwrites the first's cert and key. **No migration** — the flat dir's contents are
    unattributable, and `bin/cluster-up:582` re-issues unconditionally, so a short-TTL leaf
    (≤720h) is re-minted from the right cluster's Vault PKI on the next bring-up. This reverses an
    earlier session claim that unification would orphan certs.
    **B is DONE at `2c908554`.** Codex produced correct code but could not stage or commit —
    `.git/index.lock` "Operation not permitted", the known sandbox write wall
    (`reference_codex_exec_cannot_commit_git_lock.md`) — so Claude reviewed the diff and committed
    on its behalf. **Lesson: a DoD grep gate scoped wider than the defect induces gate evasion.**
    The gate said `grep -rn '<flat literal>' scripts/ bin/` must return only `bin/cluster-down`
    lines, but `scripts/tests/bin/cluster_down.bats` legitimately holds that literal — proving the
    legacy dir gets cleaned is its whole job. Codex satisfied the gate by splitting the string
    across two assignments. That edit was reverted, the gate narrowed to
    `scripts/plugins/ scripts/lib/ bin/`, and the spec now forbids rewriting a string to dodge a
    grep. Scope the gate to where the literal is actually wrong, and say so explicitly.
  - **A — CI BATS list drift. DONE at `6064796c`.** Same `.git/index.lock` wall; Claude committed
    on Codex's behalf again. **Codex reported 946 green on two enumerations; Claude's unpiped
    re-run found `notok=1`.** Its Linux-sim command piped `make test` into `tee`, so that `EXIT=0`
    was `tee`'s — the trap the handoff explicitly warned about still landed. **Lesson: an agent's
    green is one sample; a race shows on some samples only, so re-run rather than re-read.** The
    spec's STOP rule held — the failure is a real production bug, filed as
    `docs/bugs/2026-09-17-e2e-readiness-gate-can-probe-zero-times.md` and not fixed here:
    `_e2e_wait_vcluster_ready` can report "not ready" after zero probes when the clock crosses a
    second boundary between its two `date +%s` samples. Reproduced deterministically with a
    stubbed `date`, not dismissed as a flake. **`e2e.bats` was dark in CI and is now gated, so
    this race is a live intermittent CI red until fixed — recommend fixing it before the v1.35.0
    PR.**

- **2026-09-17 — Make test entrypoints COMPLETE: Part 1 `63d7f523`, Parts 2+3 `6eb1866e`, plus
  the bug they found `4184d23e`. All pushed.** Part 1 added the deterministic targets. Switching
  the dark suites on surfaced two real defects, both fixed before CI was wired:
  - **A `cluster-down` bug, not a stale test** (`4184d23e`, spec
    `docs/bugs/2026-09-17-cluster-down-argocd-browser-tls-key-not-removed.md`). `cluster-up`/
    `cluster-refresh` source `plugins/argocd.sh`, whose `ARGOCD_BROWSER_TLS_DIR` default is the
    flat path, so they write there; `cluster-down` does not source it and removed the
    provider-scoped path instead. The Vault-PKI `tls.key` survived every teardown. `cluster-down`
    now removes both paths (four named files, no wildcard). `cluster_down.bats` test 15 was
    correct all along — an earlier session note calling it stale was wrong.
  - **`make test-bin` was not portable to `ubuntu-latest`.** Three tests read the host OS instead
    of declaring it (`if _is_mac` launchd block, no `uname` stub), so they passed on macOS and
    would have reddened main. They now call a shared `_stub_uname_darwin` helper. Verified
    108/108 on the macOS host AND with a `uname -s` → `Linux` stub ahead of `PATH`.
  - **CI now gates all three suites** (`6eb1866e`): `make test-bin` + `make test-python-unit` in
    the `lint` job, and `make test-pytest` behind a pinned `pytest==9.1.1` install. 120 pytest
    tests verified on Python 3.13.6 and 3.14.7.
  - **RESOLVED `842b4ac8` — `make test` is GREEN, 924/924, zero `not ok`, `MAKE_EXIT=0`.**
    Case 525 (`_e2e_kustomization_images pairs newName with newTag`) was a stale assertion, not a
    production bug: `978ea60f` (v1.34.0) legitimately added a fourth app
    (`shopping-cart-payment`) to `scripts/etc/e2e/kustomization.yaml`, and the test's hardcoded
    `grep -c ':' -eq 3` was never updated. Deliberately NOT bumped to `4` — that re-arms the same
    trap for the fifth app. The count is now derived from the substrate's own `newName` entries and
    the `':'` guard became a per-line assertion. Spec:
    `docs/bugs/2026-09-17-e2e-kustomization-images-hardcoded-count.md`.
  - **The invisibility is the bigger defect, now spec'd.** CI passes `bats` a hand-maintained file
    list; `make test` globs the directories. Counted: **54 files (3 `core` + 51 `plugins`) run
    locally and never in CI**, while `scripts/tests/etc` runs in CI and not in `make test`. That is
    why a red suite coexisted with a green main for a whole release. Assigned to Codex:
    `docs/bugs/2026-09-17-ci-bats-list-drift-from-make-test.md`.

- **2026-09-17 — Webhook redaction coverage audit implemented, commit `d0d35ff8`.** Registered
  the webhook control token at `_auth`, counted skipped redaction registrations by reason, and
  added six direct regression tests. Required gates passed. No PR created per task instruction.

- **2026-09-17 — PR #127 MERGED, SHA `978ea60f`.** Hermes autonomy, Slack `/k3dm`,
  E2E observability shipped. Pre-merge gates (CI fix `c40924d1`, Copilot review
  narrative + inline comments swept) all green. `enforce_admins: true` verified on
  merge commit. Retrospective: `docs/retro/2026-09-17-v1.34.0-retrospective.md`.
  Next branch: `k3d-manager-v1.35.0` (created 2026-09-17, branched at `978ea60f`).

- **v1.34.0 closed at the 5-plan cap (5/5).** v1.35.0 opens for new specs. Released
  plans: `hermes-scheduled-e2e`, `hermes-sms-pager`, `slack-k3dm-make-command`,
  `hermes-scheduled-status-triage`, `e2e-grafana-trends-and-drilldown`.
  **v1.34.0 IS CUT** (2026-09-17): CHANGELOG `## [1.34.0]` `a56cd27a`, tag `v1.34.0` at
  `978ea60f`, GitHub release marked Latest, `docs/releases.md` + README rows `bd67710a`.
  The earlier "tag SKIPPED" note was the process hole, now closed in `/create-pr`
  pre-flight 3b (promote the heading before the milestone PR) and `/post-merge` Step 4
  (a missing tag on a milestone merge reports loudly instead of skipping silently).

- **2026-09-17 — Grafana/observability block shipped and compressed.** ~40 commits delivered the
  Hermes Status dashboard, E2E failure groups / test-level details / trend panels / failure ratio,
  and dashboard responsiveness bounding. Per-commit detail is in `memory-bank/progress.md`
  ("Shipped in v1.34.0"), `CHANGELOG.md` `[Unreleased]`, and the dated `docs/issues/` records.
  Docs audit done the same day: CHANGELOG had no Grafana coverage, `progress.md` contradicted
  itself on the trends spec, the trends plan had no `**Status:**` header, and the README issue
  table was ten days stale — all four fixed in `5340a2df`.

- **Hermes scheduled `make status` is IMPLEMENTED but DEFAULTS OFF.** `K3DM_HERMES_STATUS_ENABLED=1`
  opts in. Do not enable until the Prometheus authenticated-probe dependency is verified — the
  `✗ Prometheus: HTTP Error 401` red is false (the probe never learned to authenticate after
  `bin/prometheus-auth-proxy` landed), so a live run would page and file a bug on its first pass and
  stay red. Corrections: `docs/issues/2026-09-16-hermes-status-triage-review.md`.

- **Hermes now self-schedules, proven live.** 2026-09-16 02:10 PT it claimed the Wednesday slot,
  dispatched E2E to M2, triaged, filed 5 bugs and pushed `ad4a4a45` with no human involvement.
  Run `1789549631-2079`: 24 passed / 33 failed / 102 total. The 9 payment failures classified as
  `assertion`, not `service-unreachable` — payment is deployed and reachable in the Tier 1
  substrate. Tier 1 runs `OAUTH2_ENABLED=false`, so the run says nothing about SSO.
  **`k3d-manager-v1.34.0` now has a second writer; expect non-fast-forward pushes and rebase.**

- **Live SSO recovery closed the PR #98 question.** The Keycloak PostSync hook was failing because
  `quay.io/keycloak/keycloak:24.0` ships no `awk`; ArgoCD's public OIDC URL was aligned in
  `c219eab7`. Evidence: `docs/issues/2026-09-16-live-sso-e2e-recovery.md`.

- **Operator actions still outstanding:** `make deploy-worker` (GH `CLOUDFLARE_API_TOKEN` secret
  missing) and the Slack `/k3dm` app registration; Keychain items `k3dm-hermes-sms-from` /
  `k3dm-hermes-sms-to`; re-mint the ArgoCD hermes token.

## Merged releases

Archived. Canonical: `docs/releases.md` (full history), the README releases table (3 most recent),
`CHANGELOG.md` per-release sections, and `docs/retro/`. Pre-compression narrative:
`memory-bank/archive/activeContext-2026-09-17.md`.

## 2026-09-11 — Hub rebuild verification

Archived to `memory-bank/archive/activeContext-2026-09-17.md`; the durable findings are in
`docs/issues/2026-09-11-hub-post-rebuild-verification-gaps.md`,
`docs/issues/2026-09-11-hub-recovery-public-origin-and-eso.md`,
`docs/issues/2026-09-11-m2-backup-verification-and-lost-source.md` and
`docs/issues/2026-09-11-status-warnings-hub-vault-eso-breakage.md`.

## Open follow-ups

- **2026-09-01 frontend Keycloak login:** Hostinger frontend bundle uses the `frontend` client in
  realm `shopping-cart`, but the Keycloak realm has no such client (`clientId=frontend` returned
  `[]`), producing the browser's “Client not found” page. Bug recorded in
  `docs/issues/2026-09-01-frontend-keycloak-client-not-found.md`; create/reconcile the public
  client with the production callback before retesting.

- **2026-08-27 hub CPU overcommit — Step 1 IMPLEMENTED + live-applied (`85518a88`→`2a38670c`):**
  `docs/bugs/2026-08-27-hub-cpu-overcommit-resource-governance.md`. Diagnosed the CPU stress the
  federation-scrape tweak (`977d9e11`) could not fix: single 10-CPU/12.6GB hub VM oversubscribed
  (`docker stats` ~1414% vs 1000%; agent-2 426%, load avg 70; `/livez` 1.4–5.3s). Root = zero
  resource governance → unbounded `argocd-application-controller`/`repo-server` (`resources: {}`)
  starve apiserver → 24s status patches → ~4s hot reconcile loop on 25 apps → probe-kill restart
  storm (repo-server 221, svclb 465, coredns 143, keycloak 57). Plus istiod + istio-ingressgateway
  HPAs pinned 5/5 @80%-of-tiny-request (scale-out death spiral). **Both istio HPAs are IstioOperator-
  owned (`scripts/etc/istio-operator.yaml.tmpl` via `_istioctl install` in `k3d.sh`), NOT the ambient
  appset** (that targets remote clusters). **Committed:** requests+limits on all 6 ArgoCD components
  (`values.yaml.tmpl`; controller mem limit 2Gi to avoid OOM — CPU is the constraint) + pilot/ingress
  `hpaSpec:{min=max=1}`+limits (`istio-operator.yaml.tmpl`). **Live-applied** (ArgoCD is Helm-managed,
  no self-Application; no live istio operator reconciler → patches durable): `kubectl patch hpa
  istiod|istio-ingressgateway maxReplicas=1` (5→1 each) + `kubectl patch` controller/repo-server
  resources. **Result:** total CPU ~1414%→~1144% (~2.7 CPU freed); `/livez` 5.3s→~0.4s; agent-2 load
  70→39↓; new repo-server pod 0 restarts; restart storm FROZEN. `kubectl top nodes` UNDERCOUNTS
  (showed agent-2 ~15%); trust `docker stats`. **Istio durable rollout DONE via real tool:**
  `istioctl install -f <rendered istio-operator.yaml.tmpl>` (v1.30.0) reconciled live from committed
  config — HPAs now durably `MINPODS=1 MAXPODS=1` (operator-owned, not just the hand HPA patch),
  istiod limits 500m/1Gi + gateway 500m/512Mi applied, both pods fresh/healthy at ~44% CPU.
  (`istioctl install` foreground-times-out at 2m on the loaded hub — benign, k8s finishes the roll;
  verify with `kubectl get deploy/hpa -n istio-system`.) **ArgoCD formal redeploy DEFERRED** — see
  chart-drift follow-up; fix stays live (patched) + committed. **Step 2 load-shed IMPLEMENTED
  (config committed 2026-08-27; awaiting observability appset reapply for live rollout)**
  (`docs/bugs/2026-08-27-hub-load-shed-observability-footprint.md`): `lokiCanary.enabled: false`
  in `loki-values.yaml` (chart `loki-18.2.0`, canary is a top-level key — no selfMonitoring
  sub-block); `kube-prometheus-stack-values.yaml` `scrapeInterval`+`evaluationInterval` 30s→60s
  (the big CPU lever), `retention` 7d→3d, `retentionSize` 20GB→8GB. Prometheus CPU limit was
  already 1500m and etcd/scheduler/CM/coredns/kube-proxy scrapes already disabled — so those
  parts of the spec were pre-existing. **ROLLOUT PENDING:** reapply the `observability` appset
  with `K3D_MANAGER_BRANCH=k3d-manager-v1.27.0` so `$values` tracks the release branch, then
  ArgoCD selfHeal picks up the new values (loki-canary DaemonSet should disappear; prom CPU drops).
  Monitoring loop still running — hub was oscillating hot (load ~35–50, livez bursting to 20s)
  after Step 1, exactly the demand Step 2 removes.

- **2026-08-27 keycloak-0 restart loop FIXED live + committed + CoreDNS collateral fixed live**
  (`docs/bugs/2026-08-27-keycloak-restart-loop-tight-probes.md`): root cause was the SAME hub
  CPU starvation making Bitnami's **1-second probes** fail. keycloak-0 (67 restarts) was killed
  by liveness `tcpSocket period=1s failureThreshold=3` (SIGTERM 143) — NOT OOM. Fix in
  `scripts/etc/keycloak/values.yaml.tmpl` (previously set no probes/resources): liveness
  `period 1→10s failureThreshold 3→5`, readiness `timeout 1→5s`, **NEW startupProbe** (30s +
  40×10s = 430s grace), resources `750m/768Mi → 1000m/1Gi`. The startupProbe is the critical
  piece — Bitnami `start-dev` re-runs Quarkus augmentation every boot: live logs measured
  `augmentation 172742ms` + `started in 154.023s` = **~326s cold start**, so the old ~170s
  liveness window killed it mid-boot forever. Applied LIVE via `kubectl patch statefulset/keycloak`
  (KEYCLOAK_HELM_CHART_VERSION is empty=latest, so a `helm upgrade`/`deploy_keycloak` would risk a
  chart bump off `keycloak-25.2.0` + Bitnami-deprecation pull failure — patch was the low-risk
  path; template edit makes it durable at next deploy). keycloak-0 now **1/1, 0 restarts**.
  ⚠ **Rolling the pod exposed CoreDNS in CrashLoopBackOff (155 restarts, deploy 0/1)** — same
  1s-probe-under-CPU-starvation disease (`plugin/health … took more than 1s: 1.93s` → liveness
  SIGTERM). DNS was cluster-wide down; only cached-connection pods survived. Live-patched
  `deploy/coredns` liveness `timeout 1→5s failureThreshold 3→5`, readiness `timeout 1→3s` →
  CoreDNS `1/1` stable, DNS restored. **⚠ CoreDNS patch NOT in git — k3s-managed**
  (`k3s.cattle.io` owner, on-node `coredns.yaml`); k3s addon controller may revert. FOLLOW-UP:
  persist via k3s manifest override/HelmChartConfig, or land Step 2 load-shed so 1s probes stop
  failing at the source. This is fresh evidence Step 2 is no longer optional.

- **2026-08-27 hub-wide CPU-starvation cascade INCIDENT (mitigated live).** The keycloak dig
  uncovered that 1s liveness/readiness probes were failing platform-wide under CPU starvation,
  crashlooping EVERY core component into a deadlock: coredns (DNS down), loki-canary (4 pods,
  200+ restarts each), argocd-repo-server (probe-killed 40× → ArgoCD couldn't render manifests →
  couldn't sync the Step 2 relief → deadlock), and **agent-0 node went NotReady** (kubelet
  starved). User ran the Step 2 appset reapply (`applicationset observability configured`, now
  `$values`=k3d-manager-v1.27.0), but ArgoCD sync stayed `Unknown` because repo-server was down
  and then because rendering the big kube-prometheus-stack chart timed out (`DeadlineExceeded`).
  Live mitigations (NOT all in git): (1) `kubectl patch deploy argocd-repo-server` → light
  `/healthz` probes + startupProbe + 10s timeout (broke the deadlock; repo-server 1/1 stable);
  (2) `kubectl delete ds loki-canary` + force-deleted its pods (biggest immediate CPU win);
  (3) `kubectl patch prometheus kube-prometheus-stack-prometheus` → scrape/eval 30s→60s,
  retention 7d→3d, retentionSize 8GB **directly on the CR** (bypasses the timed-out chart
  render; operator regenerates config; ArgoCD sync is stuck so won't revert; and v1.27.0 values
  ALSO say 60s so they AGREE when sync eventually lands). Result: all 4 nodes Ready again
  (agent-0 self-recovered), keycloak/coredns/repo-server/argocd-server stable (restart counters
  frozen), Prometheus cut to 60s + counter frozen, replaying TSDB toward 2/2. ⚠ Live-only debts
  to reconcile: repo-server probe patch (ArgoCD-self-managed → reverts to 1s on next argocd
  self-sync — OK once CPU is free), coredns patch (k3s-managed), metrics-server was briefly
  unavailable. Durable resolution = the committed v1.27.0 Step 2 config syncing once repo-server
  can render the chart under freed CPU. Prometheus prometheusSpec should also carry a startupProbe
  headroom review, but its probes are already sane (not a 1s victim).

- **2026-08-28 node-health-watch was bouncing agent-0 in a restart loop (mitigated live +
  durable fix committed).** Morning regression: agent-0 `NotReady`, coredns `0/1` (DNS
  endpoints empty), prometheus-0 `Pending`/`Unknown`. Root cause was NOT a new probe bug and
  NOT OOM (`RestartCount=0 OOMKilled=false ExitCode=0` = external restarter). The launchd
  watchdog `com.k3d-manager.node-health-watch` (`bin/k3dm-node-health-watch`,
  `K3DM_NODE_RECOVERY_ENABLED=1`) polls `/healthz` with a 5s timeout; under CPU pressure that
  times out on a **slow-but-`Ready`** node, 3 fails (~90s) → `docker restart agent-0`, 300s
  cooldown, repeat ~every 6 min (log: restart 04:11→recover 04:13→fail→restart 04:17 PDT). Each
  bounce takes DNS down (coredns is a single replica pinned to agent-0) and strands Prometheus
  (its local-path PVC is on agent-0) → net-harmful. This is the **node-level instance of the
  1s-probe disease** ([[reference_one_second_probes_cpu_starvation_kill_loop]]). Live mitigation:
  `launchctl bootout gui/$(id -u)/com.k3d-manager.node-health-watch` → restarts stopped, agent-0
  holds Ready on its own (self-recovers), coredns 1/1, DNS restored, Prometheus rescheduled and
  replaying TSDB. Durable fix committed: `bin/k3dm-node-health-watch` now triggers recovery only
  on the authoritative `_ready`=False verdict (a Ready-but-slow `/healthz` is advisory, no
  restart), healthz timeout 5s→15s (`K3DM_NODE_RECOVERY_HEALTHZ_TIMEOUT`), threshold 3→5. Spec
  `docs/bugs/2026-08-28-node-health-watch-restart-loop-slow-node.md`. ⚠ Watchdog is currently
  **unloaded** — reload it (`launchctl bootstrap`) only after the fixed script is the one on
  disk AND the hub CPU has calmed; follow-up fragility: coredns SPOF + prometheus PVC both
  hostage to agent-0.

- **2026-08-28 chronic hub CPU overcommit persists after the watchdog fix — `make status` blocked
  on a pegged control plane.** With the self-inflicted node bounces stopped, all 4 nodes hold Ready,
  but the hub is still CPU-overcommitted at the source. `docker stats --no-stream`: server-0
  **492%**, agent-1 344%, agent-2 270%, agent-0 226% (~1333% total). Inside server-0: `/bin/k3s
  server` (embedded apiserver+etcd+controller-manager+scheduler) at **71%** of the node with **load
  average 60**; co-located discretionary load = `trivy server` (29% VSZ), an istio ingress-gateway
  envoy, kube-state-metrics, access-log-exporter, node_exporter. Consequence: every `kubectl` LIST
  times out (single-namespace `get pods` fails at 30s; `top nodes` times out), and the webhook
  `/api/v1/health` aggregator times out at 90s → `make status` reports `Overall: UNKNOWN / status
  source: webhook unavailable`. The webhook process itself is healthy (listening :7443, 401 without
  a token) — restarting it will NOT help; the blocker is the pegged apiserver, not the webhook.
  Durable fix = the committed Step 1+Step 2 load-shed governance (recent commits on
  `k3d-manager-v1.27.0`), but it is **inert** until ArgoCD reapplies it, and ArgoCD can't
  render/sync while the control plane is drowning (chicken-and-egg). Prior live sheds (prom 60s
  scrape, loki-canary off) are live but insufficient. Decision pending: reduce discretionary
  control-plane churn live (candidate: `trivy-operator` scale-to-0 — reversible, non-user-facing)
  vs. force the committed governance to sync. Same disease family as
  [[reference_one_second_probes_cpu_starvation_kill_loop]].
  - **RESOLVED 2026-08-28 via cluster restart (user-authorized).** Live shed alone did NOT help:
    scaled `trivy-operator` (trivy-system) → 0 and `loki`/`loki-gateway` (monitoring) → 0, but
    server-0 kept *climbing* (492→707→867%, oscillating 540-845% over 90s) because the bottleneck
    is the apiserver's own list/watch/reconcile churn, and pod terminations add to it — shedding
    agent workloads doesn't relieve the control plane. `k3d cluster stop/start k3d-cluster` cleared
    the accumulated churn: server-0 settled 607→**50%**, all 4 nodes Ready throughout, **coredns
    stayed 1/1 on the way up** (looser probes + startupProbe held — no DNS outage). Post-restart:
    apiserver responsive, `make status` completes. Recovery lesson: for a churn-storm on the k3d
    control plane, a cluster restart is the effective lever, NOT workload shedding.
  - **Post-restart Vault was sealed** (expected — raft/shamir, threshold 1). Unsealed via cached
    shards: `./scripts/k3d-manager deploy_vault --re-unseal` (keys in Keychain `k3d-manager-vault-unseal`
    + in-cluster `vault-unseal` Secret, both present). vault-0 → 1/1. ⚠ The `vault_install_unseal_watchdog`
    is NOT deployed, so Vault will need a manual `deploy_vault --re-unseal` after every restart until
    the watchdog is installed.
  - **RESTORED 2026-08-28 (user-authorized):** `trivy-operator`, `loki`, `loki-gateway` back to 1
    (all Running/Ready). ⚠ **CPU tradeoff quantified:** with them shed server-0 sat at **50%**; with
    them restored server-0 settled at **~360%** (a 617% loki cold-start spike that decayed) — 7× the
    shed headroom and much closer to the pressure edge that caused the incident. Still functional
    (apiserver responsive, nodes Ready), but loki is the heavy one; re-shed loki if steady-state
    headroom feels tight on this M4 Air. Also re-enabled the `node-health-watch` watchdog
    (`launchctl bootstrap`, PID confirmed) now running the FIXED script (`2b2d5705`) — validated live:
    logged `agent-0 Ready but /healthz slow/unreachable (advisory, no restart)` and `NotReady (1/5)`
    then stopped (self-recovered before threshold 5) — did NOT bounce the node.
  - **`make status` final: all hub infra GREEN** (ArgoCD/Keycloak/Prometheus/Grafana 200, ESO 18/18,
    data 4/4, Keycloak+ArgoCD+Grafana login OK). Sole remaining red = **`Frontend login: HTTP 401 on
    /api/cart` — a smoke-harness artifact, NOT a hub fault**: `k3dm-smoke-user` Secret absent →
    Keycloak login falls back to the Helm admin Secret (master-realm `admin-cli` token) → that admin
    token correctly can't authenticate to the app frontend, and the graceful 401/403 skip guard
    (`bin/k3dm-webhook` ~1831) only fires for `kc_via_smoke_client`, not the admin-cli fallback, so a
    correct 401 is reported as a hard FAIL. Fix candidate: extend the skip guard to the admin-cli
    fallback, or seed a real `k3dm-smoke-user`. Matches the known status-login false-green limitation.
  - **2026-08-28 Frontend login → TRUE GREEN** (`✓ Frontend login: HTTP 200 on /api/cart`). Root cause
    was 3 factors, all live-fixed on the hub Keycloak: (1) no `shopping-cart` realm existed — created it
    mirroring `home` (LDAP federation) + a public direct-grant client `k3dm-smoke`; (2) issuer mismatch —
    tokens minted locally carried a `localhost`/`.local` `iss`, never basket-service's trusted
    `https://keycloak.3ai-talk.org/realms/shopping-cart`; fixed by pinning the realm
    `attributes.frontendUrl=https://keycloak.3ai-talk.org` so **every** locally-minted token carries the
    public `iss` (no Cloudflare round-trip, verified via `.well-known`); (3) cloned LDAP component bound
    with a **masked** `bindCredential` (`**********` from the admin API) → `LDAP error 49 Invalid
    Credentials` on every federated mint; fixed by PUTting the real `LDAP_ADMIN_PASSWORD` (Secret
    `openldap-admin`, bindDn `cn=ldap-admin,dc=home,dc=org`). Smoke **user** is an LDAP entry
    (`cn=k3dm-smoke,ou=users,dc=home,dc=org`) — READ_ONLY LDAP refuses local Keycloak user creation.
    Seeded Secret `identity/k3dm-smoke-user` (username/password/realm/client; pw via stdin, not argv).
    **Webhook code change:** removed `kc_token_is_stub=True` from the smoke-client branch (a real seeded
    smoke user must green on 200 / red on genuine 401; only admin-cli/master fallback stays a skip) +
    reads optional `realm` key from the Secret. Spec: `docs/bugs/2026-08-28-smoke-frontend-login-stub-token-false-fail.md`
    (durable-follow-up section). ⚠ Live realm/LDAP/client/user/Secret WERE ephemeral — **now codified**:
    **`keycloak_provision_shopping_cart_realm`** (`keycloak.sh`) idempotently creates the realm + pins
    `frontendUrl` (`KEYCLOAK_SMOKE_ISSUER_BASE_URL`, overridable), clones the LDAP provider from `home`
    and repairs the masked `bindCredential` from Secret `openldap-admin`, creates the `k3dm-smoke` client,
    adds the LDAP smoke user (bind pw via stdin→0600 pod file, generated user pw), and writes
    `identity/k3dm-smoke-user`. Live-verified idempotent: re-run → `iss=…/realms/shopping-cart` →
    `/api/cart` **200**. Reach admin API with `KEYCLOAK_BASE_URL=http://localhost:8880` (keycloak PF up).
    Older `keycloak_seed_smoke_user` retained but wrong for this deployment (see spec) — prefer the new fn.
  - **⚠ 2026-08-28 hub CPU crisis recurred mid-session** — while completing the above, `docker stats`
    showed server-0 **454–568%**, agents ~200–330% each (~1170–1550% total on the M4 Air), and
    `/readyz` flapped `etcd failed`/`etcd-readiness failed`. Symptoms: `:8880` keycloak PF dropping to
    `000`, coredns 4× restarts → keycloak `UnknownHostException: keycloak-postgresql`, keycloak DB pool
    500s. Steady hogs (`kubectl top`): argocd-application-controller 733m, prometheus 681m; plus a
    trivy scan burst (10+ scan pods). Same disease family as the chronic overcommit above — the Step 1/2
    governance is committed but **inert until ArgoCD syncs it**.
    - **CPU-reduction pass applied 2026-08-28** (durable in-repo + live): (1) `vault-unseal-watchdog`
      CronJob cadence **`* * * * *` → `*/5 * * * *`** (`scripts/etc/vault/unseal-watchdog.yaml.tmpl`) —
      cuts 1,440 pod-spawns/day of node churn 5×; (2) ArgoCD `timeout.reconciliation` **120s (chart
      default) → 180s** (`scripts/etc/argocd/values.yaml.tmpl` `configs.cm` + live `argocd-cm` patch) —
      relaxes the 727m application-controller's full-resync cadence; takes effect on next controller
      restart (NOT force-restarted — a restart triggers a full re-sync burst). Prometheus already
      conservative (60s scrape / 3d retention) — left as-is. Snapshot at time of pass: prometheus 754m,
      argocd-application-controller 727m, argocd-repo-server 386m, vault-0 368m, keycloak 162m.
    - **Monitoring pause/resume toggle — DONE + live-verified 2026-08-28** (the "biggest optional lever",
      now built): `observability_pause` / `observability_resume` (`scripts/plugins/observability.sh`) +
      `make monitoring-pause` / `make monitoring-resume`. Scales the whole hub observability stack
      (prometheus+grafana+loki+alertmanager+kube-state-metrics+trivy) to zero on demand — reclaims
      **~1.1 cores** (measured: prometheus 730m + grafana 273m + alertmanager 37m + ksm 18m); node-exporter
      DaemonSet (~15m) left running. **Keeps production-grade config fully intact** — pause only scales
      replicas + suspends auto-sync; resume reconciles the identical committed chart values (scrape 60s /
      retention 3d / all rules unchanged). Nothing deleted, PVCs untouched → history survives within 3d.
      **Two-controller mechanism** (both required, learned live): (1) selfHeal defeated by patching each
      app `spec.syncPolicy.automated=null`; (2) that patch made durable by committing
      `ignoreApplicationDifferences: [/spec/syncPolicy/automated]` to the `observability` ApplicationSet
      (the app-level `skip-reconcile` annotation is STRIPPED by appset re-templating within seconds — does
      NOT work); (3) prometheus/alertmanager are operator-reconciled CRs — scale via the CR, not the STS.
      Resume scales workloads back **explicitly** (operator→CRs→deploy/sts to 1), NOT via ArgoCD sync —
      sync goes `Unknown`/slow exactly under the CPU starvation this feature targets. Spec:
      `docs/bugs/2026-08-28-monitoring-pause-resume-toggle.md`. Config-tune levers (#1 scrape, #2 retention)
      confirmed already spent; trivy is event-driven not cron — so the toggle is the remaining real lever.
    - **`make status` made pause-aware (2026-08-28, `bin/k3dm-webhook`)** — with monitoring paused, status
      previously hard-FAILed on Prometheus/Grafana/Grafana-login 502s. Added `_monitoring_paused()` +
      downgrade pass: when the hub `kube-prometheus-stack` ArgoCD app exists AND `spec.syncPolicy.automated`
      is empty (the deliberate-pause signal, distinguishes pause from crash), those three become `⚪` warnings
      (`monitoring paused (make monitoring-resume)`) → `Overall: WARN`, exit 0. **Two gotchas fixed live:**
      (a) query the **hub/INFRA context** `k3d-k3d-cluster`, NOT `_provider_context()` (returns app cluster
      `ubuntu-k3s`, no such app); (b) **NO provider gate** — `make status` resolves to `k3s-hostinger`
      (Makefile `CLUSTER_PROVIDER=k3s-aws` origin=file → recipe forces hostinger), and the `*.3ai-talk.org`
      Prometheus/Grafana URLs front the hub via cloudflared, so paused-hub explains the 502 in every mode.
      Safety verified: apps with `automated` set → not-paused → real outages stay hard errors. `make
      restart-webhook` required after edits. Spec: `docs/bugs/2026-08-28-status-monitoring-paused-false-fail.md`.
    - **Live CPU proof (2026-08-28):** monitoring running → Keycloak `/realms/master` 1.6–6.3s (erratic) →
      login smoke read-timeout FAILs; after `monitoring-pause` → **9–26ms**, server-node CPU recovers from
      `<unknown>`. Concrete evidence the stack starves Keycloak + API server.
    - **RESUMED to Layer 1 2026-08-28** (decision: user wants Layer 1 = reduced-rate stack always on,
      loginable Grafana, `monitoring-pause`/`resume` as the on-demand escape hatch — pause is NOT the
      default). `make monitoring-resume` restored all workloads to 1; `make status` → **HEALTHY** (all
      green incl. Grafana HTTP 200 + Grafana login 200 + Keycloak token minted). Note: pause scales
      **Grafana too** → no login while paused (Grafana without Prometheus shows empty panels anyway);
      "always loginable" = live in Layer 1, don't pause.
    - **⚠️ Resume gotcha — laptop-sleep clock jump (2026-08-28):** during resume the M4 slept; the k3d
      Docker VM clock froze (~20:54Z) then jumped forward ~3h on wake. Forward jump made
      CrashLoopBackOff burst-fire all pending restarts (ksm/operator counters shot to 43/33) + Prometheus
      "out-of-order samples" + operator "context deadline exceeded". NOT a resume bug. Recovery: clocks
      re-sync on their own; **delete the stateless scarred pods** (ksm, operator — no PVC) so they restart
      with `restarts=0`. Verified clean (both came up 0 restarts, stable). See auto-memory
      `reference_laptop_sleep_clock_jump_crashloop`.

- **2026-08-27 ArgoCD chart-version drift (BLOCKS formal deploy_argocd redeploy):** live helm release
  `argocd` is chart **`argo-cd-10.4.0`** (app v3.5.1, revision 1, deployed 2026-08-20) but the repo
  pins `ARGOCD_CHART_VERSION=7.8.1` (`argocd.sh:53`). Running full `deploy_argocd` could unintentionally
  change the chart version → regression risk, so the Step-1 argocd resource limits were NOT applied via
  helm (only live `kubectl patch` on controller+repo-server + committed to `values.yaml.tmpl`). Helm
  release state has no resource values → a non-tmpl `helm upgrade --reuse-values` would strip them
  (normal `deploy_argocd` re-renders the tmpl → keeps them). **Reconcile the pin (7.8.1→10.4.0, or
  downgrade live) BEFORE any formal argocd redeploy.** Surgical durable option if needed sooner:
  `helm upgrade argocd argo/argo-cd --version 10.4.0 -n cicd --reuse-values -f <resources-only overlay>`.

- **2026-08-27 federation scrape tuning:** source commit `977d9e11` changes the hub `federate-acg`
  Prometheus scrape interval from 30s to 60s; the vulnerability exporter remains at 60s. YAML
  parsing passed. Requires the observability values to be reapplied before live effect; monitor
  M4 CPU/API latency afterward.

- **2026-08-27 status credential discovery:** commit `f07adea8` adds fallback to the deployed
  password-only `identity/keycloak-admin-secret` (master realm/admin-cli) for smoke login checks;
  webhook tests pass. Prometheus/public endpoints recovered after OrbStack + edge restart, but the
  aggregate health sweep remains slow under control-plane load.

- **2026-08-27 hub control-plane outage:** restarting agent-0 and the k3s server did not restore
  the API. Kine reported slow SQL/handler timeouts and hub containers saturated CPU; Prometheus
  remained unavailable. Incident recorded in `docs/issues/2026-08-27-hub-control-plane-still-unavailable.md`.

- **E2E transient cleanup (2026-08-27):** commit `6b20cced` pushed on `k3d-manager-v1.27.0`.
  `_e2e_teardown` now best-effort removes orphaned vCluster kubeconfigs/proxies and transient
  per-run logs while retaining JSON audit summaries; regression coverage added. Host remains
  CPU-saturated by OrbStack/browser workloads, so m2 remains the preferred E2E runner.

- **Hostinger access-layer recovery (2026-08-26):** k3d agent-0 exited (143), causing hub workload
  evictions and local ArgoCD/Keycloak/Prometheus 502s; restarting the single stopped container
  restored all hub nodes to Ready and Prometheus replayed its WAL. Commit `44de06f7` fixes the
  Keycloak forward from service port 80 to 8080, pins tunnel/health probes to IPv4, and uses the
  valid `/realms/master` status path. Focused BATS 68/68, shellcheck, and `_agent_audit` passed.
  Repeated direct public probes reached ArgoCD/Keycloak 200; wrapper flapping remains a live
  follow-up when transient port-forward client resets occur. The shared wrapper now tolerates
  three consecutive health failures, retries after 2 seconds, and binds kubectl to IPv4; local
  ArgoCD and Keycloak checks returned 200 after regeneration. Fix commit `a5dc3967` is pushed.
  Incident:
  `docs/issues/2026-08-26-hostinger-keycloak-port-forward-service-port.md`.

- **Hostinger capacity check (2026-08-26):** live node `srv1754834` has 2 vCPU / 7.75 GiB RAM;
  current requests are 1610m CPU (80%) and 4880Mi memory (61%), while observed usage is 404m CPU
  (20%) and 5496Mi node memory (69%). It currently runs 44 pods, including ArgoCD, Vault, ESO,
  Prometheus, Loki, Trivy, and all shopping-cart services. Moving Keycloak+PostgreSQL there would
  fit steady-state usage but leaves inadequate CPU/request and rollout-failure headroom; defer until
  the node is upgraded to at least 4 vCPU/16 GiB or a second worker is added.

- **M2 E2E acceptance blocked (2026-08-25):** bootstrap/preflight passed and the intentional
  invalid-digest run produced a failed artifact, but publisher variables were absent. Replay
  and the passing run are blocked because `m2jump` cannot resolve `m2-air.local`. Evidence:
  `docs/issues/2026-08-25-m2-e2e-acceptance-blocked.md`.

- **CVE remediation panels empty — FINAL root cause (Claude 2026-08-25).** Two prior RCs were
  incomplete: Codex's "in-memory/no durable source" was WRONG (the CM-based durable source
  exists); my own "missing app-rebuild secret" was NECESSARY-BUT-NOT-SUFFICIENT. **Fixed the
  secret half (live):** stored classic PAT (`repo`+`read:packages`) as Keychain
  `platform-ops-app-rebuild/k3dm` → `argocd_sync_app_rebuild_secret` created the Secret →
  deleted 32h-wedged job `cve-auto-1787541034` → manual run `cve-verify-1787657822` completed
  clean, GHCR auth works, `product-catalog`+`payment` PROMOTED for real HIGH/CRIT CVEs.
  **Panels STILL empty → true RC (Bug A):** *nothing in the repo CREATES* the
  `k3dm.k3d.io/cve-remediation-event=true` ConfigMaps — `cve-remediation-verify.sh` only
  reads/transitions them, the exporter only reads them, and `app-cve-scan.sh` `_promote_image()`
  does live-patch+git-persist+notify but emits NO event CM. Consumer+exporter read events the
  producer never writes. **Bug B surfaced:** `_git_persist_promotion()` writes its askpass helper
  into the same dir it `git clone`s into → clone fails 100% ("destination not empty"), promotions
  are live-patch-only (revert on next ArgoCD sync). Token/netpol/git+CA all ruled out.
  **Fixes APPLIED + live-deployed (commit `915d1459`):** (A) `_promote_image()` now emits a
  durable `cve-remediation-event` CM via new `_emit_remediation_event()` — **verified end-to-end**
  (applied one such CM live → exporter emitted `cve_remediation_event_info{current="true"}`, the
  panels' query, cve_ids parsed; test CM deleted). (B) `_git_persist_promotion()` clones into
  `${_p_work}/repo` so the askpass helper no longer poisons the dest — **VERIFIED LIVE
  (deterministic, `7a830dda`+repro):** the failure is CVE-independent, so confirmed with a repro pod
  on real `aquasec/trivy:0.63.0` + live `platform-ops-git-writer/git-token` — OLD path reproduced
  `fatal: destination path '…' already exists and is not an empty directory`, NEW path cloned OK
  with `services/shopping-cart-payment/kustomization.yaml` at HEAD 7a830dd on k3d-manager-v1.27.0
  (no push). A pre-fix `cve-auto` pod on 08-25 had again logged `GITWRITE … clone … failed`,
  confirming the bug was 100% live before the fix. Deployed live by re-creating the
  `argocd-cve-scan-script` CM. **Hardening/UX DONE (`65bf4e31`):** (1) `argocd_sync_app_rebuild_secret`
  `_warn`s loudly when PAT absent + CronJob exists + no Secret (the wedge condition), stays optional
  otherwise; (2) `activeDeadlineSeconds: 1200` on the app-cve-scan CronJob (live) so a
  CreateContainerConfigError pod self-terminates in 20m vs the 32h backoffLimit-never-trips wedge;
  (3) no-data `description` on both remediation panels (live in monitoring CM). Full trail in
  `docs/issues/2026-08-24-cve-remediation-panels-empty.md` +
  `docs/bugs/2026-08-25-git-persist-clone-into-nonempty-dir.md`.

- **✅ CVE panel ② ("Shopping-cart Unique CVEs") — RESOLVED + DURABLE (2026-08-24).** 75 actionable
  `trivy_vulnerability_inventory{image_repository=~"wilddog64/shopping-cart-.*"}` series, native
  operator-generated (self-refreshing 24h TTL), Prometheus-verified. Three durable commits in
  `trivy-operator-acg-values.yaml`: `49477017` (`trivy.slow`+`timeout 15m0s`) + `8bfcbcc9` (scan-job
  CPU request `50m→10m`) + **`aac9cb27` (`operator.privateRegistryScanSecretsNames` +
  `accessGlobalSecretsAndServiceAccount: true`)**. Real root cause: workloads carry NO imagePullSecret
  anywhere (pod spec AND `default` SA empty) → private images pull via node-level containerd cred,
  invisible to the operator → silent skip; operator-upgrade is a dead end. Manual-CR stopgap (352
  all-sev) deleted in favor of native (75 actionable). Hub-side wiring (RBAC/ESO/appset `84817d88`,
  live Vault SA + policy fixes `9c9c8bb8`/`0f7ea0ad`) complete + verified end-to-end.
  Bug: `docs/bugs/2026-08-24-trivy-operator-skips-private-images-sa-imagepullsecret.md`.
  Auto-memory: `reference_trivy_operator_node_cred_private_image_skip`.
  - **Close-out (2026-08-24, both done):** (a) `acg-trivy-operator` **ArgoCD-synced** — the 3
    OutOfSync resources converged via a manual sync (ref `k3d-manager-v1.27.0` contains `aac9cb27`,
    so the private-registry env survived); app Synced/Healthy, panel ② held at 75 (payment 52 / order
    11 / basket 8 / product-catalog 4). (b) `allow-cve-scan-egress` netpol given a durable home —
    **spec'd + pushed** to shopping-cart-payment `docs/plans/durable-trivy-scan-coverage.md` (branch
    `feat/trivy-scan-egress-netpol`, `3ca0dca`, PR gated); flags the kustomize `commonLabels`→selector
    gotcha + optional SA imagePullSecrets hardening. Live netpol stays drift until that merges. The
    originally-planned pod-spec imagePullSecrets / scan-CR CronJob / operator upgrade are
    UNNECESSARY / redundant+harmful / dead — see bug doc "reassessed".
  - ⚠️ The 2026-08-23 "ArgoCD stale-render bug" was a **mis-diagnosis** (I read the hub's own trivy
    configmap, not hostinger's `acg-trivy-operator`, which has no `automated` syncPolicy so manual
    patches stick). Durable git fixes are correct + live.

- **Keycloak hub deploy DONE + dev SSO RESOLVED (2026-08-22).** `keycloak-0` 1/1, VirtualService
  live (`keycloak.3ai-talk.org/realms/master` 200); port-forward remote-port bug fixed (`04cc1e14`,
  →8080). Realm `home` (`dc=home,dc=org`) is the DESIGNED truth; admin/developer/operator synced,
  the only gap was missing LDAP passwords — fixed `bin/cluster-up` step 10d.5 seed loop (`9efb23f7`)
  + live `seed-dev-sso-passwords.sh` (all 3 verified via ldapwhoami, mirrored to
  `secret/keycloak/users/*`). Steps 10d.6/10d.7 realm-federation reconcile are broken+redundant →
  follow-up: delete or retarget `-r home`. **SSO login round-trip to realm `home` still to be
  confirmed by user.** Docs `docs/bugs/2026-08-22-keycloak-*`, `-hub-openldap-wrong-realm-*`.

- **hostinger istiod-scheduling cascade RESOLVED — 3/3 (2026-08-22).** Single 2-CPU node
  `srv1754834` chronically 95–98% CPU requests; istiod Pending 2d → ambient mesh down →
  product-catalog CrashLoop + frontend stuck. Break-glass restored istiod+frontend; product-catalog
  durable via PR #49 `505f758a` (cpu 100m→50m). **ArgoCD source gotcha (keep):** the hub app reads
  `repo=k3d-manager rev=k3d-manager-v1.26.0` whose kustomization pulls REMOTE
  `shopping-cart-product-catalog//k8s/base?ref=main`; a `refresh=hard` annotation re-fetched `ref=main`
  → OutOfSync, user-run `kubectl patch cpu=50m` landed it (durable, selfHeal won't revert).

- **hostinger CPU right-sizing — durable fix committed, ACTIVATION PENDING (2026-08-24).**
  Investigated: node `srv1754834` is **request-bound, not load-bound** — CPU *requests* 98%
  booked (1960m/2000m, 40m free) while *actual* usage ~20% (419m). 0 pending / no FailedScheduling
  at rest; the risk is a future rollout deadlock (surge pod > 40m free → the
  `hostinger_maxsurge_rollout_deadlock` / istiod-cascade class). Durable overlay patches committed
  `6851b5b0` on `k3d-manager-v1.27.0` (`services/shopping-cart-*/kustomization.yaml`): payment
  requests.cpu 200m→50m (+150m); basket/order/frontend maxSurge=1/unavail=0 → maxSurge=0/unavail=1.
  Each `kubectl kustomize` build verified. **INERT until activated:** the `services-git` appset renders
  app `targetRevision` from `${K3D_MANAGER_BRANCH}`, frozen at `k3d-manager-v1.26.0`; `services/` is
  byte-identical v1.26.0↔v1.27.0 so reapplying at `k3d-manager-v1.27.0` pulls ONLY this fix. Live
  patches will NOT stick (all 5 apps `selfHeal=true`). **All three prepped 2026-08-24:**
  (a) `services-git` appset re-rendered at v1.27.0 (server-diff = ONLY the branch ref moves) — apply
  BLOCKED by classifier, handed to user as a `!` command (`kubectl apply -f
  .../services-git-v127.yaml`). (b) rabbitmq 200m→50m committed `1a85dc7a` on branch
  `feat/rabbitmq-cpu-request-trim` in `shopping-cart-infra` → **PR #93 MERGED** `59ed6342` on
  2026-08-24. `enforce_admins` RESTORED (confirmed `true`); `required_reviews` remains 1. Rabbitmq trim
  now live on ref=main (ArgoCD will roll to hostinger via data-layer app read).
  (c) istiod pilot cpu 100m→50m committed `1dbe68dc` on v1.27.0 in
  `scripts/etc/argocd/applicationsets/istio-ambient.yaml` — istiod `maxSurge=100%` is a hardcoded istio
  chart default (NOT helm-overridable in a pure-helm ArgoCD source), so the request trim shrinks the
  surge-pod footprint instead; re-rendered + server-diff = ONLY pilot cpu; apply BLOCKED by classifier,
  handed to user (`kubectl apply -f .../istio-ambient-v127.yaml`).
  **✅ ALL THREE LIVE + VERIFIED 2026-08-24:** both appsets reapplied at v1.27.0 (services-git
  `targetRevision` v1.26.0→v1.27.0; istiod appset pilot cpu 50m). basket/frontend/order Synced+Healthy,
  payment rolled (50m), istiod Synced/Healthy (surge pod scheduled), rabbitmq rolled via data-layer.
  Hostinger node `srv1754834` CPU requests **1960m (98%) → 1610m (80%)** = ~350m reclaimed (~40m→~390m
  free); zero Pending pods. Rollout-deadlock class eliminated. hostinger CPU right-sizing CLOSED.

- **Other live/tracked follow-ups:**
  - Replace the interim in-cluster CVE promoter git-writer token with a fine-grained
    contents-write-only PAT.
  - Reconcile stale port-forward/LaunchAgent state on public Grafana/status probe failures
    (`reference_single_service_502_zombie_port_forward` in auto-memory).
  - Re-seed display-only Vault paths wiped in rebuild (Prometheus basic-auth, ArgoCD/Grafana
    mirrors) — display-only, not ESO-managed; `make show-service-passwords` triage in
    `reference_show_service_passwords_na_root_causes`. Hub Prometheus is UNAUTHENTICATED (rotate fn
    targets ACG, not hub).
  - Keep ArgoCD smoke credential-drift + k3s-aws SSM registration issues visible in `docs/issues/`
    until their live follow-ups close. Account-level SSM Default Host Management Role optional.
  - Dependabot alert #6 (js-yaml) remediated as lib-foundation `v0.4.11` (subtree `1bf1d2ce`,
    lockfile `3.15.1`); reads `open` only because Dependabot scans main → auto-closes when
    v1.26.0 → main. Dev-only transitive, low risk.

- **k3d agent watchdog hardening (2026-08-26):** existing bounded `node-health-watch` previously
  skipped exited containers; commit `15c7d072` now uses `docker start` for `created`/`exited`/`paused`
  states and `docker restart` only for running containers. Focused BATS 2/2, ShellCheck, and
  `_agent_audit` passed. Watchdog reinstalled live with the existing 3-failure/300-second cooldown.

## Operating decisions

- **2026-08-26 hub outage:** an exited k3d agent caused node-affine Prometheus/Loki pods to hang and
  Kine/SQLite readiness to fail, producing edge 502s. Agent/server restart plus stale pod cleanup
  restored the workloads; public forwards still require live verification. See
  `docs/issues/2026-08-26-hub-control-plane-and-edge-forward-outage.md`.

- **Edge forward hardening:** `ea91431d` increases wrapper probe timeout/hysteresis (5s/6 failures)
  to avoid restarting ArgoCD/Keycloak on transient control-plane latency. Public ArgoCD/Keycloak
  checks still need re-verification once the k3s API settles.

- `make status` follows the active provider (concise/full/JSON); Slack reuses the same summary contract.
- CVE remediation current-state excludes terminal `superseded`/`deployment_advanced` events; history
  keeps the audit trail. Verifier cadence/bounds stay conservative under hub load.
- E2E runs use a throwaway vCluster, pinned service images, runtime-generated datastore credentials,
  and an EXIT-trap result artifact written before teardown.
- **2026-08-27 M2 E2E migration:** corrected the remote dispatcher to forward an explicit immutable
  `E2E_IMAGE_TAG` to the M2 runner (`0f16f0de` on `k3d-manager-v1.27.0`). The corrected image build
  (`shopping-cart-e2e-tests` run `33073207387`, source `0c2505bb`) passed; live M2 acceptance remains
  the next verification step. M4 storage is healthy (58% root, 196 GB free; OrbStack 26%, 184 GB free).
  The 2026-08-27 M2 run used the immutable tag but failed 31/102 (26 passed, 45 skipped), with
  basket/order response-shape failures and payment-suite failures; see
  `docs/issues/2026-08-27-m2-e2e-acceptance-after-immutable-image.md`.
- **2026-08-27 Keycloak smoke fallback:** committed `931839ab` on `k3d-manager-v1.27.0` to support
  deployed password-only Keycloak admin Secrets while preserving the existing username/password path.
  Focused Keycloak BATS passed 12/12 and ShellCheck was clean.
- Do not deploy source-only changes until their release-branch/PR gates + live verification are explicit.
- When the laptop Vault reverse bridge is required (`HUB_VAULT_USE_BRIDGE=1`, default), k3s-aws selects
  SSH and overrides explicit SSM with a warning; SSM stays available for non-bridge Vault profiles.

- **2026-08-28 hub last-mile close-out** (`k3d-manager-v1.27.0`): four follow-ups from the CPU-crisis
  resolution actioned.
  - **Governance already durable (verified, no-op):** `argocd_check_values_branch` → all 6 Applications
    track `k3d-manager-v1.27.0` (no drift); live `monitoring` ns confirms Step 2 governance is applied —
    loki-canary=0, prom scrapeInterval/eval=60s, retention=3d, retentionSize=8GB. ApplicationSets were
    already reapplied; nothing inert.
  - **Vault auto-unseal watchdog deployed + fixed:** installed `vault_install_unseal_watchdog` (CronJob
    `vault-unseal-watchdog`, ns `secrets`, `* * * * *`, Forbid). Found + fixed two bugs — (1) stale
    pinned image `1.18.3` vs live `1.20.1`, and vars.sh unconditionally exporting the stale default,
    defeating derivation; now `vault.sh` derives the image from the running Vault StatefulSet and vars.sh
    leaves `VAULT_UNSEAL_IMAGE` empty; (2) per-node k3d image cache + `activeDeadlineSeconds:50` killed a
    cold pull → raised to 150. Validated: manual job SUCCEEDED ~12s, logs `vault already unsealed`. Note:
    a real restart preserves node image caches, so the cold-pull only bites first-deploy. Spec:
    `docs/bugs/2026-08-28-vault-unseal-watchdog-stale-image.md`.
  - **Frontend-login false-red fixed:** `bin/k3dm-webhook` skip guard extended from `kc_via_smoke_client`
    to a new `kc_token_is_stub` flag (True on both smoke-client AND admin-cli fallback paths), so an
    expected 401 on `/api/cart` from a stand-in admin token is a SKIP not a hard FAIL. `make status` now
    `WARN (1 warning)` — the lone warning is the honest "no real smoke user seeded" skip; everything else
    green. Real outages still FAIL (guard is 401/403-only). Spec:
    `docs/bugs/2026-08-28-smoke-frontend-login-stub-token-false-fail.md`. Durable follow-up (out of scope):
    seed a real `k3dm-smoke-user` in the shopping-cart realm to make this a true PASS.
  - **loki re-shed declined (data-driven):** offered when server-0 was ~360% cold-start; it has since
    settled to **95–130%** with canary already gone. A manual `loki=0` would be reverted by ArgoCD
    selfHeal (git declares 1) and would remove log aggregation for CPU that is no longer pressured — left
    loki at 1/1. One-command shed remains available if headroom is ever needed.
- **2026-08-28 optional durable follow-ups:**
  - **deploy_vault now auto-installs the unseal watchdog** (`vault.sh`, after `_vault_setup_pki`, guarded
    `|| _warn`) so auto-unseal survives a hub rebuild without a second command — same pattern as
    platform-ops in the ArgoCD bootstrap. Decision folded into
    `docs/bugs/2026-08-28-vault-unseal-watchdog-stale-image.md`.
  - **Real smoke-user seed NOT applicable on the hub — architecture finding.** `keycloak_seed_smoke_user`
    targets a `shopping-cart` realm, but the hub Keycloak (identity ns, reached at
    `keycloak.shopping-cart.local`) has only `home` + `master` realms — no `shopping-cart` realm and no
    frontend/app client (`home` has only default clients). The shopping-cart frontend + its realm live on
    the **app-cluster (ACG)**, not the hub. So seeding a hub user cannot produce a true Frontend-login PASS
    without first provisioning the shopping-cart realm + frontend client on the hub Keycloak (a real setup
    task, not a last-mile seed). The honest SKIP from the `kc_token_is_stub` fix is the correct state. Seed
    aborted at the realm-existence check — created nothing (verified: no `k3dm-smoke-user` secret, no
    `k3dm-smoke` client). Also noted: codebase default realm `shopping-cart` is stale vs live hub `home`.

- **2026-08-29 monitoring-pause Grafana keep-list — LIVE-VERIFIED (8506f5fe, pushed):** pure
  whole-word `_observability_workload_in_keep_list` + default
  `OBSERVABILITY_PAUSE_KEEP=kube-prometheus-stack-grafana` pause-sweep exemption; resume unchanged.
  Five pure BATS cases + Makefile help. Spec `docs/bugs/2026-08-29-pause-keep-grafana-up.md`. Coded by
  Codex, Claude-verified (BATS 5/5, `bash -n` clean, SC2016 pre-existing only). Live hub:
  `make monitoring-pause` keeps grafana 1/1 (loginable, `database:ok`) while everything else → 0/0;
  resume → HEALTHY. By design panels show "No data" while paused (UI reachable, not live data). To
  restore the old all-or-nothing sweep set `OBSERVABILITY_PAUSE_KEEP=""`.

- **2026-08-29 layered `monitoring-resume` — LIVE-VERIFIED (1bdbe3c6, pushed):** `make
  monitoring-resume LAYER=1` brings up **Grafana + Prometheus only** (live dashboards), all else 0;
  `LAYER=2` or no arg = full stack (existing body, verbatim). Added `_observability_normalize_layer`
  (1→1, 2/empty/unknown→2 — forgiving) + `_observability_resume_layer1` (keeps ArgoCD `automated:null`
  so selfHeal can't resurrect the 0-set; explicit replica drive; idempotent from pause/L1/L2), reusing
  the keep-list predicate with `OBSERVABILITY_LAYER1_UP=kube-prometheus-stack-grafana
  prometheus-kube-prometheus-stack-prometheus`. Makefile `$(LAYER)` passthrough + help. 5 pure BATS
  normalize cases. Spec `docs/bugs/2026-08-29-layered-monitoring-resume.md`. Coded by Codex,
  Claude-verified (BATS 10/10, `bash -n` clean, SC2016 pre-existing only, diff==spec, scope==3 files).
  **Live hub:** L2→`LAYER=1` dropped to grafana 1/1 + prometheus 1/1 (rest 0/0), Prometheus `up` query
  returned series + Grafana `database:ok`; `LAYER=2` restored all 7 workloads 1/1, `make status`
  HEALTHY. One manual touch during the L2 ramp: deleted a stale `Unknown` prometheus pod from the known
  CPU-starvation cascade (full stack starting at once) — not a feature defect.

- **2026-08-29 Tier-1 E2E orders.spec ROOT-CAUSED + FIXED (aa2f2190, pushed) — gate rerun
  confirming:** the orders.spec wholesale failure (42 ✘) was NOT a client-contract bug. Ground
  truth (captured Playwright `results.json` from the live pod before teardown + direct
  port-forward replay): the deployed order image `sha-56033880` is the **Go** rewrite (commit
  `5603388`), not Java (earlier Dockerfile read was wrong), and it ships **no runtime migration** —
  the substrate created the `orders` DATABASE but never the `orders`/`order_items` TABLES →
  every order DB op HTTP 500 (`relation "orders" does not exist`, 42P01). Fix: added
  `20-orders-schema.sql` to `scripts/etc/e2e/postgres.yaml` initdb (`\connect orders` + DDL).
  Critical nuance: DDL must match the **deployed** commit `5603388` — its `order_items` has **no
  `total_price`** column; copying repo-HEAD/testdata DDL (which added `total_price NOT NULL`) 500s on
  insert (23502) since that binary never writes it. **Live-validated** against the running substrate:
  `POST /api/orders → 201` with full contract (id, status PENDING, items[].subtotal, totalAmount,
  shippingAddress, currency USD), `GET …?customerId=X` (X-User-ID header) → 200 with the order. List
  filters by `X-User-ID` (MockAuthMiddleware), not the query param — e2e client sends it consistently,
  no change needed. Payments.spec (27) + payment cross-service stay Tier-1-out-of-scope (no payment
  manifest = Tier-2/ACG's job). Spec `docs/bugs/2026-08-29-e2e-order-schema-missing.md`; durable
  service-side self-migrate follow-up `docs/issues/2026-08-29-order-service-no-startup-migration.md`.
  Confirming rerun DONE (`~/.k3dm/e2e/1788051374-25838.json`, commit 86298144): **passed 26→45,
  failed 31→12, skipped 45**. Cross-service fully greened (21→0), orders 42→2. **Residual 12 =
  ZERO substrate bugs**: (a) 9 payments `ECONNREFUSED :8084` — no payment svc in Tier-1
  (Tier-2/ACG's job); (b) 2 order status-update — e2e test sends status `CONFIRMED` which is NOT
  in the deployed `OrderStatus` enum (PENDING/PAID/PROCESSING/SHIPPED/COMPLETED/CANCELLED) + illegal
  transitions (PENDING→only PAID/CANCELLED) → PATCH 400 → status undefined = **e2e-test contract bug**
  (shopping-cart-e2e-tests, spec-not-direct); (c) 1 cart remove-qty-0 — `cart.items` undefined,
  pre-existing basket/e2e mismatch. Substrate fix is COMPLETE for its scope. To green the gate:
  cross-repo — fix the 3 test-contract bugs in the e2e repo (+ rebuild image) and decide payment
  (Tier-1 manifest vs scope-to-non-payment + Tier-2). User chose (2026-08-29): **fix e2e tests,
  payment→Tier-2.**

- **2026-08-29 e2e residual triage — CART RECLASSIFIED as a basket-service bug (specs written,
  Codex handoff pending):** on grounding the 3 residuals, only 2 are e2e-test bugs; the cart one is
  a service bug:
  - **Order status (2, e2e-test bug):** tests send status `CONFIRMED`, absent from the deployed
    `OrderStatus` enum (PENDING/PAID/PROCESSING/SHIPPED/COMPLETED/CANCELLED) + illegal transitions
    (PENDING→only PAID/CANCELLED). Fix = use real enum + legal chain (PENDING→PAID; history
    PENDING→PAID→PROCESSING→SHIPPED). Spec `docs/bugs/2026-08-29-e2e-order-status-enum-mismatch.md`
    (repo `shopping-cart-e2e-tests`).
  - **Cart qty-0 (1, BASKET-service bug, NOT a test bug):** basket `UpdateItemRequest.Quantity`
    is `binding:"required,min=0"`; gin treats int 0 as "missing" so `{quantity:0}` → 400 before the
    handler's `quantity<=0` remove path runs. Test is CORRECT. Fix = drop `required` (use `min=0`).
    Issue `docs/issues/2026-08-29-basket-update-quantity-zero-required.md` (repo `shopping-cart-basket`).
  Both are shopping-cart repos → spec+Codex, branch+PR, rebuild image (spec-not-direct). Codex handoff
  + image rebuild + Tier-1 re-verify still to do; PR/merge gated.

## Canonical pointers

### 2026-09-01 — live frontend Keycloak client hotfix
- Created missing public OIDC client `frontend` in hub `shopping-cart` realm (Keycloak admin API returned HTTP 201); verified by an in-pod admin query.
- Configured callback `https://frontend.3ai-talk.org/callback` and web origin `https://frontend.3ai-talk.org`, matching the deployed frontend bundle.
- Public `keycloak.3ai-talk.org` DNS currently fails to resolve from the workstation, so browser verification remains blocked by the edge/tunnel path, not Keycloak client configuration.

- Roadmap: `docs/roadmap.md`
- v1.27.0 plans: `docs/plans/v1.27.0-*`
- Active bugs/incidents: `docs/bugs/` and `docs/issues/`
- Release history: `CHANGELOG.md` and `docs/retro/`

### 2026-09-02 — ArgoCD identity sync recovery and secure credential handling
- ArgoCD password was handled only in process memory via a Kubernetes-secret-to-API
  pipeline; no password file, shell argument, log, or output was created.
- Recreated the stuck `argocd-application-controller-0` pod and cleared its stale
  operation. Identity sync now reaches the immutable `postgres-keycloak-pvc` blocker.
- Added `Replace=true` to the identity Application template in `bin/cluster-up`.
- Follow-up issue: `docs/issues/2026-09-02-secure-argocd-sync-and-pvc-blocker.md`.

### 2026-09-03 — Grafana CVE panels empty
- Prometheus retained 6,066 vulnerability series and 6 remediation events, but the
  vulnerability exporter target was down on scrape timeout because `/metrics`
  synchronously refreshed both clusters.
- Exporter now refreshes in a 60-second daemon loop and serves the cached snapshot
  immediately. Manifest applied; post-rollout scrape confirmation is pending.
- Issue: `docs/issues/2026-09-03-grafana-cve-tables-empty-exporter-timeout.md`.
### 2026-09-01 — status blind spot documented
- Filed `docs/issues/2026-09-01-status-blind-spot-on-exited-hub-agent.md`: when a hub agent exits, webhook-backed `make status` reports only `UNKNOWN` and omits node evidence. Recommended bounded local Docker/node fallback; no automatic restart.
### 2026-09-01 — status fallback and Keycloak credential lookup fixed
- `make show-service-passwords` now reads `identity/keycloak-admin-secret` key `password`; verified it reports admin present without exposing the value.
- `bin/cluster-status-summary` now adds local `k3d-k3d-cluster-agent-0` Docker state to webhook-unavailable output. Syntax and all 8 BATS tests pass.
### 2026-09-01 — Hermes automation roadmap
- Added an unversioned forward theme for optional Hermes event-driven operations automation: read-only monitoring first, then approval-gated repairs, cooldowns/budgets, audit, and verification. k3d-manager webhook remains authoritative.

### 2026-09-03 — keycloak-secrets ES root cause = Vault FIELD SCHISM (not missing data)
- Live `keycloak-0` is DECOUPLED from `keycloak-secrets`/`postgres-keycloak`: it connects to
  `jdbc:postgresql://keycloak-postgresql:5432/bitnami_keycloak` (legacy Bitnami PG, user `bn_keycloak`)
  with a FILE-based password (`KC_DB_PASSWORD_FILE`) from configmap `keycloak-env-vars`. SSO is safe to
  touch these secrets — nothing live reads them.
- The failing ExternalSecrets (`keycloak-secrets`, `keycloak-client-secrets`, `ldap-secrets`) all use
  store `vault-kv-store`; the WORKING ones (`keycloak-admin-secret`, `keycloak-ldap-secret`, `openldap-admin`)
  use `keycloak-vault-store`. Error is `cannot find secret data for key: "admin_password"` at
  `secret/data/keycloak/admin` — the secret is READABLE but the FIELD is misnamed.
- `secret/keycloak/admin` holds only `password` (keycloak.sh convention); the infra ES wants `admin_password`
  + `db_password` (shopping_cart.sh convention). `secret/ldap/admin` does not exist; canonical ldap admin pw
  is `secret/ldap/openldap-admin#LDAP_ADMIN_PASSWORD`.
- FIX (operational seed, NOT a manifest change): patch `secret/keycloak/admin` to ADD
  `admin_password`(=existing `password`) + fresh `db_password`; create `secret/ldap/admin#admin_password`
  (=openldap-admin LDAP_ADMIN_PASSWORD). Auto-mode classifier blocked the read-into-var+write script twice;
  handed the exact command to the user to run via `!`.
- Live identity app syncOptions = ["CreateNamespace=true","Replace=true"] (Codex 0bca3e21 IS live) with
  automated=null (Stage A suspension holds). DO NOT resume auto-sync until Replace=true is scoped to the
  Keycloak Service only (Stage B) — resuming with blanket Replace=true would force-replace Keycloak STS/PVC.
- Sequence once seeded: ES reconciles (15m or forced) → keycloak-secrets syncs → postgres-keycloak leaves
  CreateContainerConfigError → identity app heals to Healthy while auto-sync STAYS suspended (safe hold).

### 2026-09-04 — v1.28.0 two-cloud bring-up: fresh-hub `make up` aborted on unguarded PrometheusRule apply
- Live two-cloud validation (AWS EC2 k3s + hostinger): both clouds' nodes + hub came up
  (`ubuntu-k3s` 3 nodes Ready, `ubuntu-hostinger` 1 node Ready, hub k3d Up), but ArgoCD stayed BARE
  (0 registered clusters, 0 ApplicationSets, 0 Applications). `make up` had errored, not completed.
- Root cause: `scripts/plugins/argocd.sh` applied `PrometheusRule` (1540), `AlertmanagerConfig` (1546),
  and `vulnerability-inventory-exporter` (1549, bundles a ServiceMonitor) WITHOUT a CRD guard — on a
  fresh hub the Prometheus-Operator CRDs aren't installed yet, so `PrometheusRule` hard-failed
  (`no matches for kind "PrometheusRule" in version "monitoring.coreos.com/v1"`) and aborted the deploy
  BEFORE `register_app_cluster` (bin/cluster-up:758) ever ran. The ServiceMonitor ensure (argocd.sh:512)
  already had the correct guard; these three missed it.
- FIX (this branch): added a single `prometheusrules.monitoring.coreos.com` CRD-presence guard
  (`_prom_operator_present`) mirroring line 512; gated all three applies, left the Grafana ConfigMap
  unconditional. shellcheck clean. Spec: `docs/bugs/argocd-prometheus-operator-unguarded-crd-apply.md`.
- Next: re-run idempotent `make up CLUSTER_PROVIDER=k3s-aws` → confirm it clears platform-ops and reaches
  `register_app_cluster`, then reapply ApplicationSets (hub + ACG) + `argocd_check_values_branch`, then
  inspect the v1.28.0 multi-cloud internals (scoped state dirs, active-providers, port offsets, hub-lock).

### 2026-09-04 (cont.) — argocd guard SHIPPED + verified; next blocker LDAP verify newline FIXED
- argocd guard FINAL scope = ALL SIX monitoring-stack-dependent applies behind one
  `prometheusrules.monitoring.coreos.com` CRD guard: PrometheusRule, AlertmanagerConfig,
  vulnerability-inventory-exporter(+rollout restart), and the argocd/cve-autopatch/e2e Grafana dashboard
  ConfigMaps (all target `namespace: monitoring`, also absent on fresh hub). The earlier "leave the
  ConfigMap unconditional" note was WRONG — corrected before commit. Committed `5f4526fd` (pushed).
- LIVE-VERIFIED: guard fired ("Prometheus-Operator CRDs / monitoring namespace absent; skipping..."),
  platform-ops cleared, `ubuntu-k3s` registered into hub ArgoCD, app stack built through the identity phase.
- NEXT blocker hit at Step 10d.5/14 (LDAP password seed): ldappasswd -S set OK but ldapwhoami verify failed
  Invalid credentials(49) for admin/developer/operator → checkpoint not written → `make up` Error 1.
- Root cause: verify pipe `printf '%s\n'` wrote `<password>\n` to the `-y` file; ldapwhoami -y uses the whole
  file incl. newline as bind password. PROVEN live on openldap-0: -y w/newline → invalid creds(49);
  w/o newline → bind OK. FIX: `printf '%s\n'` → `printf '%s'` at bin/cluster-up:1045 (verify only; the
  ldappasswd -S set step's newlines are prompt delimiters, left as-is). shellcheck clean, bats 8/8.
  Committed `41389804` (pushed). Spec: docs/bugs/2026-09-04-ldap-verify-ldapwhoami-trailing-newline.md.
- Observation (separate, NOT fixed): two LDAP instances in `identity` on hub — openldap-0 (Helm
  openldap-stack-ha StatefulSet, the seed target, holds all real users) + a stray `ldap` Deployment
  (name=ldap, component=directory). Immaterial to the newline bug; matters for Keycloak federation (10d.6).
- IN FLIGHT: `make up CLUSTER_PROVIDER=k3s-aws` re-run (task bsqm1ma34) to confirm 10d.5 clears.
- STILL PENDING after make up completes: reapply ApplicationSets pinned to release branch (hub + ACG) →
  argocd_check_values_branch → inspect v1.28.0 multi-cloud internals across both clouds. No PR yet (gated).

### 2026-09-04 (cont.) — TWO-CLOUD validation COMPLETE (AWS + hostinger, both fixes verified)
- Brought up hostinger as 2nd cloud (`make up CLUSTER_PROVIDER=k3s-hostinger`, task bzqq4i5i6, exit 0).
  Path = deploy_cluster (NOT bin/cluster-up): k3sup install ran idempotently ("Skipping...already exists",
  workloads persist — never touches the VM), merged ubuntu-hostinger kubeconfig, registered into hub
  (ubuntu-hostinger -> https://2.25.146.252:6443), recorded active-providers/k3s-hostinger marker.
- VERIFIED two-cloud state: BOTH cluster secrets in hub cicd (cluster-ubuntu-k3s + cluster-ubuntu-hostinger);
  BOTH active-providers markers coexist; ArgoCD generating ubuntu-hostinger-* apps (data-layer/eso/
  shopping-cart-* Synced+Healthy); both node contexts reachable (k3s=3, hostinger=1); argocd_check_values_branch
  green on k3d-manager-v1.28.0 after BOTH runs; k3s-aws scoped state intact (not clobbered).
- OBSERVATION 1 (consistency, not a bug): k3s-hostinger/ has NO scoped state subtree — deploy_cluster path
  isn't checkpoint-scoped like bin/cluster-up. hostinger uses Cloudflare edge + in-cluster Vault (HUB_VAULT_PROFILE
  =hostinger), so no local port-forward footprint to scope/offset. Port-offset table (aws=0/hostinger=10/...) applies
  to the cluster-up local-PF path only. Candidate v1.28.0 follow-up: scope deploy_cluster state too, or document why not.
- OBSERVATION 2: ubuntu-hostinger-platform app HEALTH=Unknown (others Synced+Healthy) — likely reconciling; recheck.
- MILESTONE STATUS: v1.28.0 two-cloud multi-provider is LIVE-VALIDATED. Remaining before PR (gated): resolve/close
  the two observations, lib-foundation acg-robust-click PR (credential-test first), two-LDAP-instance federation check.

### 2026-09-04 (cont.) — Two v1.28.0 follow-ups CLOSED
- FOLLOW-UP 1 (deploy_cluster scoped-state asymmetry): NO CODE CHANGE — rationale already in
  docs/plans/v1.28.0-parallel-multi-cloud-provisioning.md (~L420: hostinger deliberately flat, "collides
  with nothing", full scoping = tracked future work). Added a dated Live-validation note confirming it:
  hostinger's deploy_cluster path created NO scoped subtree AND no local PF footprint (edge + in-cluster
  Vault), did not disturb k3s-aws state. Sequential two-cloud coexistence PROVEN; literal simultaneity
  (Phase 3/4 ports+flock) still untested.
- FOLLOW-UP 2 (two-LDAP federation check): RESOLVED the question, found a REAL high-sev bug (needs a
  decision, NOT blind-fixed). Keycloak shopping-cart realm federates the osixia `ldap` Deployment
  (ArgoCD-managed by shopping-cart-identity, dc=shopping-cart,dc=local, connectionUrl
  ldap.identity.svc:389), NOT openldap-0. The cluster-up Step 10d.5 seed writes openldap-0
  (dc=home,dc=org) + Vault → DECOUPLED from SSO. PROVEN: Vault dev password fails to bind osixia ldap
  (Invalid credentials 49). So get-keycloak-password returns a non-working-for-SSO password.
  Filed docs/issues/2026-09-04-keycloak-federates-osixia-ldap-not-seeded-openldap.md with 3 decision
  options (A osixia canonical / B openldap canonical / C two-dirs-by-design) + verification steps.
  Supersedes the pre-osixia 2026-08-22 doc. ESCALATED to user — awaiting canonical-directory decision.

### 2026-09-04 (cont.) — Tidy-up: pruned unconditional Jenkins fixtures from LDAP bootstrap seed
- User asked why jenkins-admin appears in openldap-0 though Jenkins was never deployed. Answer: static
  seed fixture in bootstrap-basic-schema.ldif (Jenkins is deprecated/never deployed; 0 jenkins pods on
  hub/aws/hostinger). The ldap.sh generator already GATES jenkins entries behind enable_jenkins; only the
  static bootstrap seeded them unconditionally.
- Pruned (dc=home,dc=org tidy surface, self-consistent): deleted dead jenkins-users-groups.ldif (unloaded);
  removed jenkins-admin user + jenkins-admins group + it-devops dangling jenkins-admin member from
  bootstrap-basic-schema.ldif (kept it-devops w/ chengkai.liang); dropped jenkins-admin from
  test-directory-auto-load user+group loops; dropped jenkins-admin from rotation defaults (vars.sh
  LDAP_USERS_TO_ROTATE + ldap-password-rotator.sh + .yaml.tmpl). shellcheck clean; group blocks keep >=1 member.
- Deliberately KEPT (deprecated-but-gated / separate scope): ldap.sh gated generator, vars.sh LDAP_JENKINS_*
  config block, bootstrap-ad-schema.ldif (separate AD dc=corp,... testing dir), dirservices RBAC,
  jenkins values tmpls, smoke-test-jenkins, ad/vars.sh jenkins-admin path. Source-only cleanup — live
  openldap-0 keeps jenkins-admin until a fresh bootstrap; SSO (osixia ldap) unaffected.
- Spec: docs/bugs/2026-09-04-prune-unconditional-jenkins-ldap-fixtures.md.

### 2026-09-04 (cont.) — DECISION: leave bootstrap-ad-schema.ldif Jenkins fixtures as-is
- After pruning the default-directory Jenkins clutter (d9ee756b), checked the AD-testing schema
  scripts/etc/ldap/bootstrap-ad-schema.ldif (dc=corp,dc=example,dc=com; "Jenkins Service"/"Jenkins Admins").
- FINDING (non-obvious): its Jenkins entries are LOAD-BEARING for a live CI suite —
  scripts/tests/lib/dirservices_activedirectory.bats:227 asserts "CN=Jenkins Admins,OU=Groups,DC=corp,...".
  The whole `activedirectory` directory-service provider is a Jenkins-AD integration feature
  (_dirservice_activedirectory_generate_jcasc/authz, deploy_ad → _ldap_run_ad_smoke_test, AD_BIND_DN=svc-jenkins).
  It loads ONLY under explicit AD testing (ldap.sh:1207 deploy_ad), NOT in the default openldap-0 directory.
- USER DECISION 2026-09-04: LEAVE IT. Removing Jenkins here isn't a fixture tidy — it's "remove the whole
  Jenkins-AD provider + its BATS suite", a separate larger task that conflicts with keep-deprecated-Jenkins.
  Do NOT re-open as "tidy" work. See [[project_jenkins_deprecation]].

### 2026-09-04 (cont.) — lib-foundation PR #45 created (acg robust-click), gates green, AWAITING MERGE GO
- Sequence (user-directed 2026-09-04): (1) lib-foundation PR → (2) subtree-pull into k3d-manager → (3) v1.28.0 PR.
- STEP 1 DONE (prepared, gated): PR https://github.com/wilddog64/lib-foundation/pull/45
  (fix/acg-sandbox-robust-click, commit 91f0f12: _robustClick dispatched MouseEvent for sandbox reveal/provision).
  Gates: make credential-test PASS (extracted + sts-validated AWS creds); CI acg/bats/shellcheck all green;
  scope clean. Copilot NOT attached (appears disabled on lib-foundation; not a payment PR). k3dm overlay
  (scripts/lib/foundation/.../acg/playwright/{sandbox.js,acg_restart.js}) is IDENTICAL to 91f0f12 — no un-upstreamed drift.
- HOLD: never-auto-merge. Awaiting user go to merge #45.
- STEP 2 (after merge): tag lib-foundation v0.4.14 → git subtree pull into k3d-manager (replaces the uncommitted
  overlay). STEP 3: create v1.28.0 k3d-manager PR (branch k3d-manager-v1.28.0, all this session's commits).

### 2026-09-04 (cont.) — STEP 1+2 DONE: lib-foundation v0.4.14 merged + subtree-synced into k3d-manager
- #45 merged (squash dddc18cb); tagged+released lib-foundation v0.4.14; git subtree pull --prefix=scripts/lib/foundation
  lib-foundation v0.4.14 --squash → commits 05c5e952 (squash) + 09dab403 (merge). Overlay now formalized; tree clean.
  Verified: pulled subtree JS identical to v0.4.14, _robustClick present. Pushed origin/k3d-manager-v1.28.0.
- STEP 3 NEXT: create v1.28.0 k3d-manager PR (base main). Pre-PR gates to run: CI green on branch, scope check,
  live smoke. Never-auto-merge holds for the v1.28.0 merge.

### 2026-09-04 (cont.) — STEP 3 DONE: v1.28.0 PR #119 created, CI GREEN, AWAITING MERGE GO
- PR https://github.com/wilddog64/k3d-manager/pull/119 (base main ← k3d-manager-v1.28.0, 24 commits, merge-base 62c9ff27).
- Gates: CI all green (CodeQL actions/js-ts/python, lint, detect, GitGuardian; stage2 skipped-conditional);
  local lib bats 323 exit 0; shellcheck clean; live two-cloud smoke done; scope clean.
- Copilot: NOT attached (requested_reviewers empty on both #45 and #119 via raw-JSON POST — appears Copilot code
  review not enabled on these repos right now). Flagged to user; not a payment PR.
- HOLD: never-auto-merge. Awaiting user go to merge #119. On merge: /post-merge (restore protection, tag v1.28.0,
  release, next branch, retro, standing-docs audit, memory-bank).
- Sequence COMPLETE up to the gate: lib-foundation #45 merged+v0.4.14+subtree-synced → v1.28.0 PR #119 up & green.
