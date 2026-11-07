# Bug: a bug doc's Status can be written in a form the dashboard misreads

**Filed:** 2026-11-06
**Branch:** `k3d-manager-v1.43.14`
**Status:** VERIFIED `f832a140`; independent verification recorded (6 mutants red), live E3 passed; rollout to the M5 checkout pending
**Waiting on:** live check — since 2026-11-06
**Priority:** P3 — hygiene; the row is wrong until someone notices, and no service is affected
**Approval:** explicit 2026-11-06 "file as P3 and dispatch when allow" (operator, after four landed bugs showed as Open).
**Severity:** low

## Symptom

2026-11-06: four bugs with landed fixes showed Open in the **Bugs** table. The operator: "otherwise it just confused and not sure the right bug statu". Their Status lines began:

- `OPEN — fix landed 6d42c201`
- `Correction 4 LANDED 632ac235`
- `OPEN — machine-setup half … landed and verified … nothing left to dispatch`
- `FIX IN SUBTREE — both scripts resolve …`

## Root cause

`doc_status` in `scripts/lib/hermes/prior_art.py` reads only the first word of the Status value, and anything it does not recognise is `open`. That rule is deliberate and stays. Nothing tells the writer, so a free-text opening silently reads as Open.

## Fix

Refuse the bad form when it is written. Do not make the parser guess.

### 1. `scripts/check-bug-status.py` (new)

Takes staged paths, as `scripts/check-bug-evidence.py` does, and ignores anything not directly under `docs/bugs/` or not ending `.md`. Import `_status_value`, `_CLOSED_RE` and `_DEFERRED_RE` from `hermes.prior_art`, resolved from the script's own location, never the current directory.

For each doc, compare its Status value with the one at `HEAD`. Do nothing if they are equal, so legacy docs stay untouched until their Status is next edited. A doc with no Status value is not checked. A doc new to `HEAD` is checked.

Refuse, naming the path and quoting the first 60 characters of the value, when either holds:

1. The value matches none of `_CLOSED_RE`, `_DEFERRED_RE`, `^OPEN\b`, `^REOPENED\b` (case-insensitive).
2. The value matches `^OPEN\b` and contains `fix landed` (case-insensitive).

Exit 1 on any refusal, else 0. The refusal message says: a landed fix starts `LANDED`, and `VERIFIED` once independently verified; anything still open starts `OPEN`.

### 2. `.githooks/pre-commit`

Add a guard directly after the `LIVE-VERIFIED` evidence guard, in the same form, over the same staged list, with bypass `K3DM_SKIP_BUG_STATUS=1`. Its message names that bypass.

### 3. `docs/guides/grafana-dashboards/k3dm-bugs.md`

A short section on writing a Status line: the first word decides the row, the accepted words, and the two refusals.

### 4. `CHANGELOG.md`

One bullet at the end of `[Unreleased]`'s existing bullets. Do not add a heading.

## Files

- `scripts/check-bug-status.py`
- `.githooks/pre-commit`
- `scripts/tests/bin/test_check_bug_status.py`
- `docs/guides/grafana-dashboards/k3dm-bugs.md`
- `CHANGELOG.md`

## Tests

`scripts/tests/bin/test_check_bug_status.py`, in a scratch git repo created by the test. First assert the fixture's root is that scratch repo and not the real tree. Gate: `pytest scripts/tests/bin/test_check_bug_status.py scripts/tests/bin/test_check_bug_evidence.py`.

## What NOT to Do

- Do NOT change `doc_status`, `_CLOSED_RE` or any other function in `prior_art.py`.
- Do NOT edit any existing bug doc, or refuse a legacy doc whose Status did not change.
- Do NOT weaken or reorder the existing guards.
- Do NOT commit, push or create a PR. Claude reviews and commits.
- Do NOT modify files outside the Files list.

## Acceptance

```yaml
interface:
  - "scripts/check-bug-status.py <paths>: run with cwd inside a git repo; exit code and stderr"
  - ".githooks/pre-commit: a real git commit in a scratch repo with that hook, the script and scripts/lib/hermes copied in; K3DM_SKIP_BUG_STATUS=1"
must:
  - id: M1
    text: "A staged bug doc whose Status changes to one starting 'Correction 4 LANDED' or 'FIX IN SUBTREE' is refused: exit 1, and stderr names the path."
  - id: M2
    text: "A changed Status starting 'OPEN — fix landed' is refused."
  - id: M3
    text: "A new bug doc with a Status of a refused form is refused."
  - id: M4
    text: "The pre-commit hook blocks the commit for a refused doc, and K3DM_SKIP_BUG_STATUS=1 lets it through."
must_not:
  - id: N1
    text: "A doc with a bad Status that did not change against HEAD, with another line edited, is not refused. Paired control: changing that Status to another bad value is refused."
  - id: N2
    text: "Accepted forms are not refused: OPEN, 'OPEN — machine-setup half landed', REOPENED, LANDED, VERIFIED, LIVE-VERIFIED, FIXED, CLOSED, DEFERRED, each with the first word in any case. Paired control: M1's values are refused in the same fixture."
  - id: N3
    text: "A path outside docs/bugs/, or a doc with no Status value, is not refused. Paired control: the same bad Status under docs/bugs/ is refused."
  - id: N4
    text: "The existing LIVE-VERIFIED evidence guard still refuses a doc with no Live evidence line when K3DM_SKIP_BUG_STATUS=1 is set. Paired control: with evidence added, the commit passes."
evidence:
  - id: E1
    proves: [M1, M2, M3, M4, N1, N2, N3, N4]
    kind: offline
    what: "The Tests gate on the task branch, run by Claude."
  - id: E2
    proves: [M1, M2, M3, M4, N1, N2, N3, N4]
    kind: offline
    what: "Independent verifier's tests, written from this block only, pass on the fix and are red on its parent where new. Mutants, each red: HEAD comparison removed; 'fix landed' rule removed; docs/bugs path limit removed; hook guard removed."
  - id: E3
    proves: [M4]
    kind: live
    what: "Claude: on the real repo, a staged bad Status is refused by the hook, without committing it."
```
