# Reviewer trial: Fable vs Argon

**Started:** 2026-11-15 (operator: "then we can compare Fable and Argon to see how they perform")
**Why:** Fable reviews were the largest extra Claude-quota cost in the week of 2026-11-12 (33% of weekly_all in 31% of
the window). Argon (`gemini-4-argon-medium` via agy) draws on a separate Gemini quota. Reviews now default to Argon, and
Fable is kept for high-risk land calls. This log measures what that trade costs in review quality.

## Method

- **Same input, blind.** Each pair reviews the same artifact (design, spec or diff) with the same brief. Neither sees the
  other's findings or Claude's conclusions. Reviews are read-only and every finding needs file:line or a command.
- **Pairs come from three sources:** (1) Argon re-running a review Fable already did (no new Claude quota); (2) high-risk
  land calls, where Fable runs anyway, get an Argon run too; (3) at most one fresh pair per week by choice.
- **Claude scores each finding** against the code: `confirmed` (real, verified), `refuted` (checked and wrong),
  `unverified` (not yet checked), `style` (true but no behaviour impact). Overlap means both reviewers found the same
  defect.
- **Per pair record:** artifact, minutes, tokens (Fable from the subagent result; Argon from the agy conversation db),
  quota cost, counts per score and severity, unique confirmed findings per reviewer, and verdict.
- **Judge after about 6 pairs or at v1.45.0 grooming.** Key questions: does Argon miss confirmed BLOCKER/MAJOR findings
  that Fable catches? How often is each refuted? What does each confirmed finding cost in quota?

## Log

| # | Date | Artifact | Reviewer | Verdict | Findings (B/M/m) | Confirmed | Refuted | Unique confirmed | Cost |
|---|---|---|---|---|---|---|---|---|---|
| 1 | 2026-11-14 | Part B M2 stage-runner design (scratchpad draft) | Fable | APPROVE WITH CHANGES | 2 / 3+ / – | 4 spot-checked, 0 refuted | 0 | see below | Claude quota (Fable) |
| 1 | 2026-11-15 | same, same brief | Argon | APPROVE WITH CHANGES | 2 / 5 / 2 | 6 | 1 partial | 4 (see below) | Gemini quota, 334 s |

### Pair 1 baseline: Fable findings on the M2 design (recorded before Argon's run)

- BLOCKER: exit code cannot separate fail from abort for bats/unittest/dispatcher (bats `abort()` exits 1); use output
  evidence (TAP plan vs counts, "Ran N tests"). Confirmed (bats 1.14.0).
- BLOCKER: "pure refactor" is false: `scripts/tests/bin/test_test_tripwire.py:30-47` pins recipe text and the
  `test-all:` prerequisite line; `test-python-unit` set -e vs continue; pytest 3/4/5. Confirmed.
- MAJOR: log-line contract with `bin/k3dm-test-metrics` (5→3 stage mapping); MAKEFLAGS exported to every recipe, so the
  script must unset it; `--file` must not redo stage-level work (`K3DM_RESOLVED_PYTEST`).
- MAJOR: missing contract readers: `test_test_tripwire.py`, `suite_discovery.bats:25-26`, `scripts/ci/fast_gate.sh:39-48`,
  webhook `make_targets.py`/`cloud_actions.py`/`lifecycle.py:215`, `Makefile` test-metrics, `AGENTS.md:22`,
  `GEMINI.md:43`, `.clinerules:248`, `README.md:60`. Draft errors: the plist runs `test-metrics` (not test-all)
  (confirmed), and the land test is caller-supplied.
- Open questions: bin/ script OK; exit 3 only for pytest; keep the dispatcher as the stage-1 runner; land a fact-based
  pinning test with Part B (adopted as correction 8 item 11).

### Pair 1 Argon findings, scored by Claude (2026-11-15)

- BLOCKER-1 (standalone one-liners break `test_test_tripwire.py:21-47`): **confirmed, overlaps** Fable BLOCKER 2.
- BLOCKER-2 (parallel completion predicate `rc<126 && rc!=2` would count an exit-3 abort as complete; preflight
  before `_run_parallel`, because `--retry-failed` at `Makefile:1745` reruns every file of a stage that is missing a
  tool): **confirmed**. It partly overlaps Fable BLOCKER 1, but Argon calls exit 3 "safe" once a preflight runs, and
  misses that bats `abort()` mid-run exits 1. Fable's sharper point stands.
- MAJOR-1/2 (per-runner exit table; keep `test-python` as the composite stage): confirmed, but these restate the
  design's open questions.
- MAJOR-3 (`FAKE_REPO` needs `bin/k3dm-test-stage` symlinked): **confirmed, unique**.
- MAJOR-4 (latent divergences): **partly refuted**. The CLUSTER_ROLE "bug" is wrong because the dispatcher resets an
  unsupported role to infra (`scripts/k3d-manager:334-344`). The conftest.py skip divergence between standalone
  `test-python-unit` (`Makefile:1485-1486`) and test-all is real but latent (there is no `scripts/tests/bin/conftest.py`).
- MAJOR-5 (log-line contract: `bin/k3dm-test-metrics:55-73`, `[make] python3 <f>`): **confirmed, overlaps** Fable
  MAJOR, with more line detail.
- MINOR-1 contract readers: overlaps Fable on `test_test_tripwire.py`, `suite_discovery.bats`, `make_targets.py` and
  `cloud_actions.py`. **Unique, confirmed:** the `K3DM_JUNIT_XML` writer (`scripts/lib/webhook/lifecycle.py:193`) and the
  tripwire `TMPDIR` coupling with `conftest.py`.
- Q3 note: the dispatcher's `test` calls `_ensure_bats`, which can run `brew install bats-core`
  (`system.sh:1662-1663`); the stage script must check `command -v bats` first. **Confirmed, unique.**
- Missed compared with Fable: MAKEFLAGS exported to every recipe; the plist runs `test-metrics`, not test-all; the land
  test is caller-supplied; bats `abort()` exits 1.

**Pair 1 read:** both reviewers gave the same verdict and agreed on both blockers in substance. Fable was sharper on the
exit-code blocker and caught MAKEFLAGS. Argon found more contract readers and three concrete unique issues
(`_ensure_bats` network install, `FAKE_REPO` symlink, retry amplification). Argon had one partly refuted claim; Fable
had none. Argon's quality is close enough on this pair to keep Argon-first; one pair is not a verdict.

### Pair 2: hub-promote containment diff (Sol run 2, uncommitted), 2026-11-15

High-risk land call (`bin/k3dm-hub-promote` moves the ref the production hub deploys from). Both reviewers got the same
staged diff and spec, blind to each other and to Claude's gate, pre-fix and verifier results. Argon:
`gemini-4-argon-medium` via agy, read-only. Fable: background agent, read-only, scratch mirrors only.

**Verdicts:** Argon APPROVE WITH CHANGES; Fable LAND WITH CHANGES, keep the bug OPEN.

Scored by Claude against the code and real history:

- Fable MAJOR-1 (the squash check does not fire on the incident: `git merge-tree --write-tree` of deploy/hub 9f5f0d89
  into the target conflicts): **confirmed, unique, decisive**. Claude reproduced it in a scratch repo borrowing the
  main object store: rc 1 with 73 conflicts against 34707659, 24 against the squash aa1196ed, 95 against c4d647bf.
  deploy/hub was promoted mid-release; PR #160 gained commits before the squash. Every toy-repo test, the independent
  verifier and Argon missed it because none replayed the real SHAs.
- Fable MAJOR-2 (`hub-promote.md` overstates the squash case): confirmed, follows from MAJOR-1.
- Fable minor-3 (`.github/copilot-instructions.md:42,138` still describe BREAK_GLASS as skipping checks): confirmed,
  unique; a missed contract reader.
- Fable minor-4 (make expands `$` in `SKIP_CHECK_RUNS_REASON` passed as a make variable): unique; not reproduced by Claude.
- Fable minor-5 (reason allows control characters; no injection): unique, accepted as low risk.
- Fable minor-6 / Argon MAJOR-1 (the "before fetching" `!= *"From "*` clause cannot fail): **overlap, confirmed by
  both**; Argon rated it MAJOR with a concrete mutation, Fable minor (die text and unchanged hub carry the test).
- Argon minor-2 (E10 make test passes with the `Makefile:478` change reverted, because `:299` falls back to
  `$SKIP_CHECK_RUNS`): **confirmed, unique** (Claude read `:299`).
- Argon minor-3 (E9 M5 loop reads only the newest tag and one static reason): unique, plausible, not reproduced.
- Fable minor-7 (an exported flag skips checks on every promote): by design; noted.
- Mutants: Fable ran seven (m1 to m7), all red. Argon ran the suites only.

**Pair 2 read:** opposite of pair 1's closeness. Both found the test-strength issues, but only Fable tested the change
against the incident it claimed to fix, and that finding reverses the land decision. On a high-risk land call that is
the case for escalating to Fable; Argon-first stays the default for low-risk work. Cost: Fable 128K tokens, 22 tool
calls, about 10 minutes.

## Pair 3 — 2026-11-15, spec review: ESO 403 after vault-0 restart (`token_reviewer_jwt`)

Medium-risk spec review (hub Vault auth config). Both got the spec and the code, blind to each other and to Claude's
upstream proof. Argon: `gemini-4-argon-medium` via agy, read-only. Fable: background agent, read-only.

**Verdicts:** both CHANGES, no blocker.

- Main finding, **overlap, confirmed by both**: the spec's `test_vault` scope listed two root-token-in-argv sites;
  there are five (`test.sh:723`, `:731`, `:739`, and `_cleanup_vault_test` `:816`, `:820` via the trap at `:705`), so
  E2 would have stayed red. Both cited the same lines.
- Overlap, confirmed: `vault_role_policy_merge.bats:102-110` missing from the test list; `_vault_set_eso_reader`'s early
  return means `deploy_vault` never heals an existing cluster; remaining argv tokens at `test.sh:661`, `:792-796`.
- Fable unique, confirmed: no mutant on two of the four writers (added m4-m6); stub needs for `test_vault`
  (`:702-703`, `:770-783`); suggested the TokenReview `can-i` check (Claude ran it live: `yes`, two bindings); E5's
  two-minute bound unproven; `bin/get-ldap-password:132-143`.
- Argon unique, confirmed: non-ESO `auth/kubernetes/login` readers (`hub_data.sh:191`, three credential rotators,
  Jenkins) and the production caller `bin/k3dm-orbstack-upgrade:131`; A03 positional args for the converted `sh -c`.
- Argon unique, **refuted**: "`<<<"$root_token"` on a `_no_trace` call traces the token". Claude tested bash 5.3.20 and
  3.2.57 under `set -x`: the here-string never appears; the pipe and process-substitution forms do. The refutation went
  into the spec as a requirement.

**Pair 3 read:** like pair 1, same verdict and same main finding; each added different contract readers. Argon's one
wrong claim was a testable shell-behaviour claim, caught by running it. Cost: Fable 85K tokens, 9 tool calls, about
2 minutes; Argon one agy call (about 9 minutes wall clock).

## Pair 4 — 2026-11-17, spec review: Hermes vault-sealed sensor + r7 gating (combined plan)

Medium-risk spec review (Hermes repair gating, Slack card text, webhook diagnosis). Both got the plan, the two bug docs
and the repo, blind to each other. Argon: `gemini-4-argon-medium` via agy, read-only. Fable: background agent,
read-only.

**Verdicts:** both CHANGES.

- **Overlap, confirmed by both:** the existing r7 test (`test_repairs.py:330`) breaks once r7 needs `vault_seal`, and
  the file was not in Files; the two r7 mutations could not turn test 1 red (both guards false at once) and nothing
  caught `N <= 20`; existing `_run_cycle` tests (`test_hermes.py:287,311,333,385`, `test_app_health.py:164`) would call
  a real `kubectl`; resolve clears `pending_repairs` and then `propose()` re-adds it, and the approve re-sample would
  turn "precondition no longer holds" into "unknown action-id"; `approve_when` source undefined against
  `test_approvals.py` dicts with no `key`; "no `secret` in argv" breaks on `-n secrets` and `clustersecretstore`;
  `-k` filters need fixed test names.
- **Fable unique, confirmed:** gate r7 on raw `data.pods[].sealed` (the debounced status is still healthy on the first
  sealed cycle); the text fallback card also needs the Recommended line; N3 was false as written (Hermes already reads
  a Secret at `bin/k3dm-hermes:180`); count-regex details; a lone seal posts nothing (two contributors needed);
  production passes no `llm`; `pager.py` is a contract reader.
- **Argon unique, confirmed:** `test_approvals.py:199` runs `git diff --quiet -- repairs.py` and fails in any
  uncommitted worktree; the 7-poll unknown test pages "vault_seal check unknown 30+ min"; the `vault-initialized`
  mutation survives test 2 on a realistic fixture; the guide's "five read-only sensors" row is already gone;
  `_enrich` takes no `records`; Contract readers mislabelled `:1096` as deny; `analyze_env` returns non-JSON for
  every call, so the new reads must fail open.
- **Refuted:** none.

**Pair 4 read:** the same verdict and the same main findings, with about half of each list unique and all of it real.
Argon was stronger on tests that would break in the worker's tree; Fable was stronger on behaviour (debounce gap, card
fallback, a false must_not). Cost: Fable about 130K tokens, 18 tool calls, about 4 minutes; Argon one agy call.
After review the plan was split for the operator's Flash/Luna instruction: Hermes (Luna) and webhook Fix 5 (Flash,
`docs/plans/webhook-analyze-vault-context.md`).

## Post-land diff reviews — 2026-11-17, Fable only (no Argon pair)

The two vault-sealed landings went in without a diff review. With Fable quota spare (operator, 2026-11-17), each diff got a
blind Fable review after land; Claude re-read every finding against the code.

- webhook bea02b84: about 67K tokens. 2 medium (stderr merged into the JSON capture fails the sealed check open; tests record
  argv but never assert it) and 4 minor, all confirmed; 0 refuted.
- Hermes fadf8438: about 97K tokens. 3 correctness (odd label value reads unsealed; r7 precondition vacuous on empty pods;
  resolved-text timestamp and fixed "without a repair") and 1 doc gap, confirmed; lower test-hygiene items not adjudicated.
- Filed as `docs/bugs/2026-11-17-vault-sealed-landed-review-findings.md`.

**Read:** a diff review found a real fail-open (W1) that two blind spec reviews could not see, since it lives in an existing
helper the spec told the worker to reuse. Evidence for keeping a diff review on medium-risk landings.

## Pair 5 — 2026-11-18, release diff review: PR #163 (v1.44.2), Argon then Fable, both blind

Same diff (`main...k3d-manager-v1.44.2`, code only). Argon: one agy run, 9 findings. Fable: three parallel area reviews
(hub_data, dispatch, webhook/Hermes), about 321K tokens total (91K + 120K + 111K), most findings checked by running probes.

- **Argon:** 9 findings. 8 confirmed (1 medium: shards under xtrace, fixed in PR; 7 low), 1 duplicate of an open bug, 0 refuted.
- **Fable:** about 25 findings. All checked items confirmed, 0 refuted, 1 not a finding (bash 3.2 on a bash-4 script), 3 by design.
  Unique medium: recovery exits silently on a missing `vault-unseal` (fixed in PR; the tests were vacuous because the stub
  returned where `_kubectl` exits), Hermes approve re-propose voids digest/expiry, r7 two-cluster parsing, klog lines.
  Unique low/latent: project dir above the release, non-semver tag, root token in `jq` argv (pre-existing).
- **Overlap:** dispatch stall scan, slug collision, `scheme=branch`, status `unknown`, resample withdraw, unlabelled pod (6).
  Fable confirmed the xtrace fix as clean.

**Pair 5 read:** Argon found the one secret-exposure bug; Fable found the one functional break in the DR path that Argon and
CI both missed, plus more behaviour defects, at about 6% of the Fable weekly allowance. Fable's edge again came from running
probes (real `_kubectl`, scratch dispatch roots) instead of reading. Supports Argon-first plus Fable on high-risk release diffs.

## Pair 6 — 2026-11-18, release diff review: lib-foundation PR #89 (v0.5.7), Argon, Astra and Fable, all blind

Same brief (`docs/plans/release-lib-foundation-pr89-v0.5.7-review.md`) and diff (`f8025a2..5492724 -- scripts`). Argon: agy
`gemini-4-argon-medium`. Astra: codex `gpt-6.2-astra`, first trial (253,880 input of which 226,816 cached, 1,291 output).
Fable: Agent subagent, 67,675 tokens, 102 s. Claude checked every finding against the code.

| Reviewer | Findings | New in diff and real | New, not reproduced | Pre-existing real | Already accepted |
|---|---|---|---|---|---|
| Argon | 2 | 0 | 0 | 1 (RETURN-only trap) | 1 (old dir lock) |
| Astra | 7 | 1 (noclobber accepts symlink->/dev/null; rated high, really low) | 0 | 6 | 0 |
| Fable | 5 | 1 (same bug, both lock sites, rated low) | 1 (test `sort` locale; same order in C, C.UTF-8, en_US on macOS and ubuntu:26.04) | 3 (incl. unbounded claim loop, reproduced) | 0 |

Claude reproduced the symlink bug (two claims rc 0 on bash 3.2 and 5; old `mkdir` rc 1). Pre-existing findings captured as
two P3s (`docs/bugs/2026-11-18-lib-foundation-*`).

**Pair 6 read:** Fable most accurate (correct severity, stated what it did not run); Astra matched Fable on the one new bug and
read widest, but inflated severity and did not state its limits; Argon found nothing new. Operator verdict: "Fable is still
the best of among three but Astra is also worth a try for second eye. Google's Gemini 4 is the weakest one." Medium/high-risk
spec review switched to Fable + Astra (operator go 2026-11-18). Low-risk specs and routine diff review stay on Argon.

## Pair 7 — 2026-11-18, spec review: multi-project M2 bug metrics, Argon and Fable, blind

Operator picked Argon + Fable for this one. Same brief, same spec (`docs/plans/v1.45.0-multi-project-m2-bug-metrics.md` at
`cb192a0a`). Fable: Agent subagent, 135,091 tokens, 336 s, 12 findings. Argon: agy `gemini-4-argon-medium`, 7 findings (first
run lost to an agy flag-order error, re-run). Both "ready with changes".

| Reviewer | Findings | Real, unique | Real, shared | Refuted / not adopted |
|---|---|---|---|---|
| Argon | 7 | 2 (fetch misses late tags, reproduced; empty `local path` → k3d-manager root) | 4 | 1 design choice (call site inside `publish_bug_metrics`) |
| Fable | 12 | 7 (120 s Hermes kill, entry point/interface, must_not reds need mutants, verified/live_verified gap, `evidence_check=` reuse, branch label, naming) | 4 | 0 |

Shared: FETCH_HEAD mtime advances on a failed fetch (both reproduced), legacy open-history counts k3d-manager docs, shared
fixture must blank `K3DM_PROJECTS_LIST`, two dirused live-evidence lines unparseable.

**Pair 7 read:** Fable again broader and better at testability and process gaps; Argon's two unique finds were both real
and one (missing `--tags`) also exposed a pre-existing P3 in the lib-foundation pass. Argon's proofs were concrete
reproducers this time. Argon worth keeping as the cheap second eye on specs.
