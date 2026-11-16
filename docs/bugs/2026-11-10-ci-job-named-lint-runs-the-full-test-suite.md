# Bug: the CI job named `lint` runs the full offline test suite

**Status:** OPEN
**Priority:** P2 — raised by the operator 2026-11-16 ("we really need to fix this slow ci. this a big hurdle"); was P3
**Classified:** P3 by gemini-4-argon-medium, 2026-11-12 (CI job hygiene/test-only issue where offline test suites are bundled into the `lint` job, delaying lint feedback without breaking functionality); Claude proposed P3. Agreed.
**Triage:** passed over, 1st — grooming 2026-11-12, operator.
**Waiting on:** dispatch — since 2026-11-16
**Introduced by:** unknown (the test steps accreted into `lint` over several releases)
**Should have been caught by:** review
**Prior art:** exact-slug glob: none. `make find-similar-docs` unavailable (vector store: context `k3d-k3d-cluster` does not exist on the M4, 2026-11-10). Related, not a duplicate: `docs/plans/v1.44.0-parallel-offline-tests.md` (local runner speed; leaves CI unchanged, line 62)
**Severity:** misleading, no breakage. A "lint" result takes 20.8 min and a red `lint` usually means a failing test,
not a lint finding. Lint feedback that could arrive in about a minute waits behind the suite.
**Approval:** operator, 2026-11-10: "so then we should really make the name correctly reflect what it does"
**Intent approved:** operator, 2026-11-10 ("approve P3 intents")
**Filed:** 2026-11-10
**Detected by:** operator, reading the PR-checks dashboard (lint 20.8 min)
**Branch:** `k3d-manager-v1.43.15`

## Evidence (Claude, 2026-11-10, CI run `42908743867` on `k3d-manager-v1.43.15`)

Steps of job `lint` (`.github/workflows/ci.yml:35`), timed from `gh run view --json jobs`:

| Step | Time |
|---|---|
| Run the full offline suite (BATS + Python), `make test` (`:112-120`) | 866 s |
| Run pytest suites (hermes + bin), `make test-pytest` (`:130-134`) | 144 s |
| shellcheck, pyflakes, yamllint, kubeconform, setup | about 35 s |

## Fix

Split job `lint` in `.github/workflows/ci.yml` into two jobs on the same triggers:

- `lint`: checkout, setup the lint needs, shellcheck, pyflakes (`make lint-python`), yamllint, kubeconform. No test step.
- `test`: checkout, the setup the suites need (promtool, pytest, Copilot CLI and its env), `make test`, `make test-pytest`.

Both jobs keep `permissions: contents: read` and pinned action tags. No test is added, removed or skipped; the step
commands stay byte-identical, only their job moves. Parallel sharding is out of scope (an idea row, not this fix).

## Contract readers

- Job name `lint` as a GitHub check name: readers found by grep and the API, 2026-11-10:
  - Branch protection: ruleset `main` (id 12967352) has only `deletion` and `non_fast_forward` rules, no required
    status checks; classic protection has none (`required_status_checks` contexts `[]`). Unchanged.
  - PR-checks exporter and `scripts/etc/argocd/platform-ops/grafana-dashboard-pr-checks.yaml`: group by the `check`
    label, no hard-coded name. Changes in meaning: after the split `lint` durations drop to about 1 min and a new
    `test` series appears; history before the change keeps the suite under `lint`. Note it in the dashboard panel
    description.
  - `scripts/tests/hermes/test_pr_checks.py:15-91` and `scripts/tests/plugins/grafana_dashboard_pr_checks.bats:221-233`:
    use `"lint"` as sample fixture data only. Unchanged.
- Writer: `.github/workflows/ci.yml` is the only writer of the check name.

## Acceptance

```yaml
must:
  - id: M1
    text: "CI has a job named lint that runs only the lint steps (shellcheck, pyflakes, yamllint, kubeconform) and a job named test that runs make test and make test-pytest."
  - id: M2
    text: "Every step command that ran in the old lint job runs in exactly one of the two new jobs, unchanged."
must_not:
  - id: N1
    text: "The lint job never runs make test or make test-pytest."
  - id: N2
    text: "No test step is dropped, skipped or made non-blocking by the split."
evidence:
  - {id: E1, proves: [M1, M2, N1, N2], kind: offline, intent: "You will see a test parse ci.yml and fail if the lint job runs make test or make test-pytest, or if any step command from the old job is missing from both new jobs or marked continue-on-error; it fails on today's ci.yml."}
  - {id: E2, proves: [M1], kind: live, intent: "Claude shows the first CI run after the change on GitHub: a lint check finishing in a few minutes and a separate test check running the suites, both green."}
interface:
  - ".github/workflows/ci.yml"
  - "GitHub check names on a push to the release branch"
```

## Worker definition of done

- Change only `.github/workflows/ci.yml`, a new or existing static test under `scripts/tests/`, and the PR-checks
  dashboard panel description. Show E1 red on today's `ci.yml`, then green. Paste command, rc and proving lines.
  Leave changes uncommitted; Claude reviews and lands.

## Escalation (operator, 2026-11-16): split alone is not enough

PR #161 at `12bd21b7` (runs `43798158706` pull_request, `43798151066` push): job `lint` took 21.9 min, of which
`Run the full offline suite` 1127 s (866 s on 2026-11-10: +30 % in six days) and `make test-pytest` 135 s.

Per-test durations from the job log (`ok N` timestamps): 3381 tests, 18.0 min in total. The slowest 31 tests (over
5 s each) are 4.6 min; the rest is breadth, about 0.3 s a test. Making single tests faster cannot fix this; running
them side by side can.

Each push to a PR branch also runs CI twice (`push` on `k3d-manager-v*` and `pull_request`, `.github/workflows/ci.yml:4-11`),
with the concurrency group keyed on `github.ref`, which differs between the two events, so neither cancels the other. On
2026-11-16 Claude watched only one of the pair and reported green early. The `push` trigger exists for the hub-promote
gate (`docs/bugs/2026-11-07-hub-promote-refuses-release-branch-commits-ci-runs-only-on-prs.md`), so it stays.

### Widened fix (proposed, needs operator approval and new Acceptance)

1. The split above (`lint` about 1 min, its own job).
2. Shard the test job with a `strategy.matrix` (e.g. 4 shards of the BATS files, one for `test-bin` + Python units,
   one for `test-pytest`). The repo is public, so each shard gets its own free 4-vCPU runner. Target wall time
   under 7 min including setup, from about 22. Each shard runs the same commands on a subset; the union of shards
   must equal today's file list (a test that checks this belongs in Acceptance), and a red in any shard fails the run.
3. Not in this fix: `PARALLEL=1` inside one runner (`docs/plans/v1.44.0-parallel-offline-tests.md` keeps CI serial
   until the local runner has a clean month, and `docs/bugs/2026-11-14-lib-foundation-run-parallel-collision-test-flakes-on-linux.md`
   is an open Linux parallel flake). Matrix shards are separate machines, so they avoid that shared-`TMPDIR` class.
4. Optional: drop the double run cost by giving both events one concurrency key (`github.head_ref || github.ref_name`).
   Needs checking first: the cancelled run would leave a cancelled check-run on the head SHA, and the hub-promote gate's
   reading of check-runs must still pass. Prove that before including it.

## Approved fix (operator, 2026-11-16: "go for you recommendation"): option B, lint split + matrix shards, v1.44.1

Supersedes the `## Fix` section above and its Acceptance (the split alone). Option 4 (one concurrency key for both
events) is **rejected**: `bin/k3dm-hub-promote:76` counts any check-run whose conclusion is not success/neutral/skipped
as failed, so a cancelled duplicate run would block every promote; `scripts/lib/hermes/sensors.py:1079` also reports
`cancelled` as a bad check. Both runs stay.

### Change

1. `.github/workflows/ci.yml`: job `lint` keeps checkout, setup, shellcheck, bash -n, yamllint, `make lint-python`
   and `make validate-manifests`, and no test step.
2. New job `test` with `strategy: { fail-fast: false, matrix: { shard: [1, 2, 3, 4] } }`, same `if:` guard, runner
   and permissions as `lint`, the setup the suites need today (setup action, Copilot CLI with the same env, promtool,
   pytest pin), running `make test-shard SHARD=${{ matrix.shard }}/4`.
3. New job `test-python` (one runner): `make test-python-unit` and `make test-pytest`, same env as today.
4. New Makefile target `test-shard SHARD=i/N`: takes the sorted list of every BATS file `make test` and
   `make test-bin` run today (`scripts/tests/{lib,core,plugins,etc}/*.bats` via the dispatcher, `scripts/tests/bin/*.bats`),
   picks its share, and runs each file with the same command, environment and tripwire wrapping as the serial
   recipe for that suite. Assignment is deterministic. The worker may balance by a checked-in weight list (the long
   poles: `scripts/tests/bin/codex_dispatch.bats`, `scripts/tests/bin/makefile_test_all.bats`) or round-robin, as
   long as no shard takes more than about 1.5x the mean on the 2026-11-16 timings.
5. New target `test-shard-list SHARD=i/N` prints the files a shard would run (used by the tests below and by CI
   logs).

Not changed: test files, the serial `make test` / `make test-bin` / `make test-all` recipes, `PARALLEL=1`,
the `alertmanager-behaviour` job, triggers, pinned action tags.

## Contract readers

| Reader / writer | file:line | Change |
|---|---|---|
| hub-promote gate | `bin/k3dm-hub-promote:70-78` | none: counts all check-runs on the SHA, name-agnostic; more check-runs, same rule |
| Hermes PR checks | `scripts/lib/hermes/pr_checks.py:37-52` | none: newest run per name; new names `test (1)`…, `test-python` appear on the dashboard |
| Hermes CI sensor | `scripts/lib/hermes/sensors.py:1074-1095` | none: name-agnostic |
| Grafana PR checks panel (reads pr_checks output) | dashboard | `lint` drops to ~1 min; test time now shows per shard |
| Claude "CI green" check | memory `feedback_ci_green_means_every_check_run_on_head` | none: every check-run on head |
| writer: `.github/workflows/ci.yml` | `:35-150` | job split |
| writer: `Makefile` | new `test-shard`, `test-shard-list` near `test-all` (`:1629`) | added |

## Acceptance

```yaml
must:
  - id: S1
    text: The union of test-shard-list for SHARD=1/4..4/4 equals, as a set and with no duplicates, the BATS files make test and make test-bin run today.
  - id: S2
    text: test-shard runs each file with the same command, environment and tripwire wrapping as the serial recipe for its suite.
  - id: S3
    text: A failing BATS file in any shard makes that shard's make target exit non-zero, and the other shards still run (fail-fast false).
  - id: S4
    text: The lint job has no test step; the test and test-python jobs run every suite the old lint job ran, with the same env (K3DM_ENABLE_AI, K3DM_COPILOT_LIVE_TESTS, COPILOT_GITHUB_TOKEN).
  - id: S5
    text: Wall time from first job start to last job end on the fix's PR CI run is under 9 minutes, and no shard exceeds 1.5x the mean shard time.
must_not:
  - id: N1
    text: A BATS file is left out of every shard (a file added under scripts/tests/bin or scripts/tests/plugins is picked up with no list edit).
  - id: N2
    text: A shard exits 0 when one of its files fails.
  - id: N3
    text: Assignment changes between two runs on the same tree.
evidence:
  - id: E1
    proves: [S1, N1, N3]
    kind: offline
    intent: Every test file still runs in CI after the split, and a newly added test file is picked up automatically, so splitting can never quietly drop a suite.
    check: pytest or BATS test comparing the union of the four shard lists with the serial file lists; mutation - add a fixture .bats file in a fake tree and assert it lands in exactly one shard; mutation - drop one file from the shard selection and assert the test goes red; run the list twice and compare.
  - id: E2
    proves: [S2, S3, N2]
    kind: offline
    intent: A test that fails inside a shard still turns CI red, the same way it does today.
    check: fake tree with one passing and one failing .bats file; test-shard on the failing shard exits non-zero and the other exits 0; positive control - an all-pass tree exits 0; mutation - make test-shard ignore per-file rc and assert the test goes red.
  - id: E3
    proves: [S4]
    kind: offline
    intent: Nothing the old lint job checked is lost, and lint answers on its own in about a minute.
    check: yq over ci.yml - lint has no make test*/test-shard step; the test and test-python jobs together call test-shard 1..4, test-python-unit and test-pytest; env keys match the old step; yamllint passes.
  - id: E4
    proves: [S5]
    kind: live
    intent: A PR's CI result arrives in under 9 minutes instead of about 22.
    check: Claude reads the fix PR's CI run with gh run view --json jobs - per-job start/end, total wall time, per-shard times; both push and pull_request runs green.
interface:
  - make test-shard SHARD=i/N
  - make test-shard-list SHARD=i/N
```

**Intent approved:** operator, 2026-11-16 ("apporve your intents")
