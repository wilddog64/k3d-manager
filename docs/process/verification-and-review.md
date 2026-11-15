# Verification and review: how a change earns "done"

An AI worker's "done" is a claim, not evidence. In this repo a change moves through separate stages, each run by a
different party that cannot see the conclusions of the stage before it. This page explains the ladder end to end. The
binding rule text is in [`rules.md`](rules.md) (Acceptance block, test controls, verify before trust). The ledger
commands are in [`../howto/codex-dispatch.md`](../howto/codex-dispatch.md).

## The ladder

| # | Stage | Who | Sees | Produces | Catches |
|---|---|---|---|---|---|
| 1 | Spec with `## Acceptance` | Claude writes; operator approves intent | the bug, the code | `must` / `must_not` / `evidence` / `interface`, mutants | vague "fixed" criteria |
| 2 | Spec review | Argon (low risk); Argon **and** Fable blind (medium/high risk) | spec + code, not each other | findings with file:line | contradictions, missing contract readers |
| 3 | Implementation | dispatched worker (Codex, Sol, agy) in a worktree | spec + code | uncommitted diff + full gate output | — (stops on a spec contradiction) |
| 4 | Gate rerun | Claude, outside the worker sandbox | the diff | `make test`, `make test-pytest`, targeted suites | sandbox-only reds and sandbox-only greens |
| 5 | Pre-fix red | Claude | new tests + old code | which tests fail before the fix | tests that cannot fail |
| 6 | Independent verifier | a separate agent | **Acceptance block only** — never the diff or the worker's report | its own tests, mutant results, every error | a fix that passes its own tests but not the contract |
| 7 | Diff review / land call | Argon by default; Fable too for hub, security or shared-contract changes | diff + spec, blind to each other and to Claude | verdict + findings with file:line | design and safety defects tests do not cover |
| 8 | Land | Claude (coordinator) | all of the above | commit with `Coordinator:` trailer; `verify` ledger event | — |
| 9 | Live evidence | operator or Claude, **never Gemini** | the deployed system | `**Live evidence:**` line; Status `LIVE-VERIFIED` | anything only a real system shows |

## Why each separation exists

- **The worker never commits and never verifies.** A worker that verifies its own work has once "fixed" instead of
  verified, passed a test that could not fail, and written a memory-bank entry for work it never did. Workers hand back
  a diff and gate output; Claude checks both (`git log`, `gh run view`, rerun) before trusting either.
- **Gates rerun outside the sandbox.** The worker's sandbox lacks parts of the real environment. On 2026-11-15 a worker
  reported 83 bats and 25 pytest failures. Claude reran the same diff on the M4: both suites green. The reverse also
  happens: sandboxed runs have reported greens that a real run turned red.
- **`must_not` items must be red on pre-fix code.** A new test that passes before the fix proves nothing. Paired with
  mutants (deliberate one-line breakages named in the spec), this measures whether the tests can fail for the right reason.
- **The verifier reads only the Acceptance block.** If it saw the diff or the worker's tests it would inherit their blind
  spots. It writes its own probes in scratch repos, applies the spec's mutants itself, and reports every error it hit.
- **Reviewers are blind to each other and to Claude.** A reviewer handed a conclusion tends to confirm it. Each finding
  needs a file:line or a command, and Claude verifies every finding against the code before acting; a finding is
  rejected only when the code proves it wrong.
- **Live evidence is never Gemini's.** It is recorded by the operator or by Claude, on the real system, with host, date,
  commit and scenario.

## Model tiering

| Role | Default | Escalate to |
|---|---|---|
| Implementation | Codex / Sol via `make codex-dispatch` | — |
| Spec and diff review | Argon (`gemini-4-argon-medium` via agy, read-only) | Fable, for high-risk land calls or a blocker Claude and Argon disagree on |
| Independent verifier | Sonnet | Opus when mutant hunting matters |
| Live check | operator or Claude | — |

Argon draws on a separate Gemini quota; Fable reviews were the largest extra Claude-quota cost in the week of
2026-11-12. Whether Argon-first loses review quality is being measured, not assumed:
[`../reviews/reviewer-trial-fable-vs-argon.md`](../reviews/reviewer-trial-fable-vs-argon.md) logs every blind pair and
scores each finding as confirmed, refuted, unverified or style. Judgement after about six pairs or at v1.45.0 grooming.

## Worked example: hub-promote containment (2026-11-15)

Spec: [`../bugs/2026-11-12-hub-promote-containment-check-blind-to-squash-merges.md`](../bugs/2026-11-12-hub-promote-containment-check-blind-to-squash-merges.md).
`bin/k3dm-hub-promote` moves the ref the production hub deploys from, so this is a high-risk change.

1. **Worker run 1 stopped instead of coding.** The spec required mutant m2 (ignore merge-tree's exit code) to turn
   test E6a red. The worker (gpt-6.1-sol) probed a scratch repo and showed the conflicted tree never equals the target
   tree, so E6a stays green under m2: the specified test could not catch the mutant. It stopped, as instructed on a
   contradiction. Claude added fixture E6c (exit 1 *and* the target tree), and run 2 implemented the full spec.
2. **Gate rerun.** The worker's broad gates were red in its sandbox (83 bats, 10 + 15 pytest). The byte-identical diff
   on the M4: `make test` and `make test-pytest` both exit 0.
3. **Pre-fix red.** On the old promoter, exactly the 7 new behaviour tests fail; the 4 refusal controls pass on both.
4. **Independent verifier (Opus, Acceptance only).** Every offline item PASS, E8 not verifiable offline; all four
   mutants killed, m2 only by E6c. 111K tokens, 32 tool calls, about 12 minutes.
5. **Blind review pair** (Argon diff review + Fable land call; pair 2 in the trial). Argon approved with test-strength
   changes. Fable replayed the incident's real SHAs and found the squash check still refuses: merging deploy/hub into
   the target conflicts (24 to 95 conflicts) because deploy/hub was promoted mid-release, before the PR gained more
   commits. Claude reproduced it. Every earlier stage used toy repos, so every earlier stage passed.
6. **Not landed.** Stages 1 to 6 were green and the change was still wrong for its purpose. The fix goes back to the
   spec: deploy/hub 9f5f0d89 is an ancestor of PR #160's head (`refs/pull/160/head`, kept by GitHub after the squash),
   which suggests a containment rule based on the merged PR's head rather than on tree content.

The lesson for the ladder: an acceptance test must include the real case that motivated the bug, not only a model of it.
