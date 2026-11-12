# Bug: a Hermes approval runs whatever the repair builds at click time, not what the card showed

**Status:** LANDED 2026-11-11 `a985ac90` (Luna, resume 3; Claude review + one fix: per-cycle kine counters `state_db_bytes`/`slow_sql_count` excluded from the records digest, else every r5 approval is refused; new test red on the worker's code)
**Priority:** P2
**Waiting on:** live check — since 2026-11-11 (independent verifier owed; live after hub-promote)
**Introduced by:** `4b6ce874` (v1.33.0, Hermes Slack approvals); `edfc9a5c` (v1.43.0) added the one exception, r10
**Should have been caught by:** spec
**Prior art:** exact-slug glob: none. `make find-similar-docs` not run (vector store unreachable, 2026-11-10). Read
`docs/bugs/2026-11-09-hermes-reauth-lasts-24h-and-is-reusable.md` (same handler, different defect: how long an
authorization lasts, not what it authorizes) and
`docs/bugs/2026-11-08-hermes-values-branch-flags-deploy-hub-and-r9-retargets-release-branch.md` (the incident that
showed a card can outlive the rule it was built under)
**Severity:** an approved repair can execute a different command, against different targets or under different repair
code, than the one the operator read on the card. r9 and r10 are irreversible. The precondition re-check and the
one-attempt-per-incident rule still apply, which is why this is P2 and not P1.
**Approval:** operator, 2026-11-10: "yes" (file it, after a LinkedIn reader suggested binding approvals to the
**Dispatch go:** operator, 2026-11-10: "go as you recommeded for those two"
**Intent approved:** operator, 2026-11-10
**Intent approval words:** ("approve P2")
evaluated revision and policy version)
**Filed:** 2026-11-10
**Detected by:** external reader comment on the operator's LinkedIn post about the 2026-11-08 wrong-branch incident;
verified by Claude in code, 2026-11-10
**Branch:** `k3d-manager-v1.43.15`

## Evidence (Claude, 2026-11-10, `k3d-manager-v1.43.15`)

- `scripts/lib/hermes/repairs.py:280-287` (`propose`): stores `command`, `evidence` and `proposed_at`; the
  `action_id` is `key` plus 8 hex of `sha1(key + command)`.
- `scripts/lib/hermes/repairs.py:301-325` (`approve`): re-checks the precondition against `records_now`, then
  **rebuilds** the command from `records_now` (`:319`) and runs it. Only r10 compares the rebuilt command to the stored
  one (`:320-321`, "target set changed since proposal"). r2 and r4 build their argv from current records, so the
  targets can change between card and click without a refusal.
- `proposed_at` is never read after it is written (grep across `scripts/lib/hermes` and `bin/k3dm-hermes`): a pending
  proposal has no expiry.
- `bin/k3dm-hermes:272`: the button nonce is the **incident** nonce (`:231`, `:247`), so it ties a click to the
  incident, not to the evaluated state.
- Nothing records the Hermes code revision or the deploy ref the proposal was evaluated against. A card proposed
  before a Hermes upgrade executes under the new `REPAIRS` entry for the same key, which is how the 2026-11-08 r9 card
  came to offer a retarget the new deploy rule forbids.

## Fix

At `propose`, store a binding with the proposal: the exact command, a digest of the sensor records the precondition
read, the Hermes code revision (`git rev-parse HEAD` of the running checkout) and the evaluated `deploy/hub` commit
for repairs that act on deployments (r9), plus `expires_at` (proposed_at + a short TTL, e.g. 30 min). At `approve`,
refuse with a distinct outcome when any of them differs or the proposal has expired: generalise r10's command
comparison to every repair, and post the refusal to the thread so the operator sees why. Keep the button value
(`action_id|nonce`) and the `action_id` format unchanged, so the relay worker contract does not move.

### Clarification (Claude, 2026-11-11, answering the worker's question)

- **Source of the r9 `deploy/hub` commit:** `git rev-parse --verify --quiet 'refs/remotes/origin/deploy/hub^{commit}'`
  run in the Hermes checkout. On the hub that ref is kept current by checkout-auto-sync's 5-minute fetch. Do not fetch
  at `propose` or `approve` (no network calls from the approval path).
- **Repo root:** resolve it from the module's own path (`Path(__file__)`), never from the current directory. Use one
  helper for both the code revision (`HEAD`) and the deploy ref.
- **Fail closed:** if the ref cannot be resolved at `propose`, store an empty value. At `approve`, refuse an r9
  proposal whose stored or current deploy commit is empty (`refused: deploy-ref-unknown`), or when they differ
  (`refused: deploy-ref-moved`). Other repairs do not read the deploy ref.
- **Tests:** point the helper at a scratch git repo (monkeypatch its root). Create `refs/remotes/origin/deploy/hub` with
  `git update-ref`; move it between `propose` and `approve` for the refusal case. First assert the root is the scratch
  repo and not this checkout.

## Files

| File | Change |
|---|---|
| `scripts/lib/hermes/repairs.py` | binding stored at `propose`; checks and expiry at `approve` |
| `bin/k3dm-hermes` | post the refusal reason to the thread |
| `scripts/tests/hermes/test_repairs.py` | E1 tests |
| `scripts/tests/hermes/test_approvals.py` | button value and outcome tests |

## Contract readers

- `state["pending_repairs"]` (Hermes state file): writer `scripts/lib/hermes/repairs.py:287` (`propose`; gains the
  binding fields); readers `repairs.py:303` (`approve`, gains the checks), `:347`, `bin/k3dm-hermes:271` (drain loop,
  unchanged), `:1012` (prints pending as JSON, new fields appear, additive), `:1037` (reads one proposal, unchanged).
- Slack button value `action_id|nonce` and `ACTION_ID_RE` (`scripts/lib/hermes/approvals.py:14`): writer
  `approvals.py:61`; readers `workers/slack-relay/index.js`, `approvals.py:38`. Unchanged by this fix.
- Approval outcomes (`refused: ...` strings): readers the Hermes Slack thread replies and
  `scripts/tests/hermes/test_approvals.py`; new refusal reasons are additive.

## Acceptance

```yaml
must:
  M1: an approval executes only if the command it would run equals the command stored when the card was proposed, for every repair key
  M2: an approval of a proposal older than its expiry is refused with a reason naming expiry
  M3: an approval of a proposal made under a different Hermes code revision, or (for deployment repairs) a different evaluated deploy/hub commit, is refused with a reason naming what changed
  M4: each refusal is posted to the incident thread
must_not:
  N1: no repair command runs when the sensor records changed between proposal and approval so that the rebuilt command differs (r2 and r4 today run the rebuilt command)
  N2: an unchanged, unexpired proposal is never refused (paired positive control for N1 and M2-M3)
  N3: the Slack button value and action_id format do not change
evidence:
  - {id: E1, proves: [M1, N1], kind: offline, intent: "You will see a test propose r2 and r4, change the records so the targets differ, approve, and get a refusal with nothing run; against today's code the same test runs the new targets."}
  - {id: E2, proves: [M2, M3, N2], kind: offline, intent: "You will see one proposal refused after its expiry, one refused after the recorded Hermes revision changes, and an identical untouched proposal still executed."}
  - {id: E3, proves: [N3], kind: offline, intent: "You will see the existing approvals tests pass unchanged, showing the button and action-id contract did not move."}
  - {id: E4, proves: [M1, M4], kind: live, intent: "On the hub, the operator approves a test card after its target changed and sees the refusal reason in the Slack thread; Claude confirms from the Hermes audit that nothing ran."}
interface:
  - "scripts/lib/hermes/repairs.py: propose(records, state), approve(action_id, state, records_now, runner)"
  - "bin/k3dm-hermes approval drain (pending_repairs state, Slack thread replies)"
```

## Worker definition of done

- Change only `scripts/lib/hermes/repairs.py`, `bin/k3dm-hermes` (refusal posting) and tests under
  `scripts/tests/hermes/`. Show E1 red against today's code, then green. Paste command, rc and proving lines. Leave
  changes uncommitted; Claude reviews and lands.
