# Bug: the fast gate lets commits authored with a fixture identity through when the identity was already set

**Status:** OPEN — dispatched to Luna 2026-11-09
**Priority:** P2
**Waiting on:** fix running — since 2026-11-09
**Introduced by:** `9942c413` (the repo-state guard compares before and after only)
**Should have been caught by:** spec
**Prior art:** `docs/bugs/2026-10-31-pre-push-gate-from-linked-worktree-writes-into-real-repo.md` (found by grep, not
scored) — read, different root cause: it covers fixtures writing into the real repo during the gate; this covers the
guard not noticing a section that was already there. `make find-similar-docs` not run (vector store unreachable from
the M4, 2026-11-09).
**Severity:** medium — every local commit from 2026-10-31 15:03 to 2026-11-09 was authored `Test
<test@example.invalid>` and pushed without a warning; no data loss, `main` unaffected (GitHub squash merges)
**Approval:** operator, 2026-11-09 ("go ahead lower P1 to P2 and dispach it to Luna if allows")
**Intent approved:** operator, 2026-11-09
**Filed:** 2026-11-09
**Detected by:** Claude, 2026-11-09, checking commit authorship for the operator
**Affected:** `scripts/ci/fast_gate.sh`
**Branch:** `k3d-manager-v1.43.15`

## Symptom

The main checkout's `.git/config` held `[user] name = Test, email = test@example.invalid` from 2026-10-31 15:03 (the
commit that filed the 2026-10-31 P1) until Claude removed it on 2026-11-09. Every pre-push gate in that window passed,
and the commits reached `origin` authored as `Test`.

## Root cause

1. The 2026-10-31 repair restored `core.bare = false` but left the `[user]` section, which that doc had recorded.
2. `scripts/ci/fast_gate.sh:110-116` snapshots `core.bare`, local `user.*`, branches and worktrees before the suites
   and compares after (`:198-202`). A value that was already wrong before the gate is in both snapshots, so the guard
   passes it.

Found by reading the reflog author of every local commit since 2026-10-01 (`git reflog` plus `git log -1 --format=%an`):
the switch to `Test` is at 2026-10-31 15:03:14; every later non-`Test` commit came from GitHub (squash merges), the CVE
promoter, or a pull. No tracked suite rewrote the section on 2026-11-09: each of the 11 files that use
`test@example.invalid` was run from the main checkout with `.git/config` compared before and after, all unchanged.

## Fix

In `scripts/ci/fast_gate.sh`, before any suite runs, fail with a message (and run no suite) when either holds:

1. `git config --local --get core.bare` prints `true`.
2. A commit in `<base>..HEAD` (the range the gate already computes) has an author or committer email ending in
   `@example.invalid` or `@example.com`, the fixture domains used under `scripts/tests` (`git grep -h -o
   '@example\.[a-z]*' scripts/tests | sort -u`). The message names each such commit (short SHA and subject) and says how
   to repair: remove the `[user]` section with `git config --local --remove-section user`, then re-author the unpushed
   commits.

Keep the existing before/after guard as it is.

`scripts/tests/lib/fast_gate.bats` builds its fixture repo with `Test <test@example.com>` (`:13-14`). Change that
fixture identity to an address outside the two domains, for example `gate-fixture@localhost`, so the existing tests
keep passing.

## Files

- `scripts/ci/fast_gate.sh`
- `scripts/tests/lib/fast_gate.bats`

## Do not

- Do not remove or weaken the before/after guard, or the `unset` of git variables at `:98`.
- Do not refuse every repo-local `[user]` section: fixture repos and other clones may set one legitimately.
- Do not add an environment variable that skips the check.
- Do not rewrite history or touch the real `.git/config` from the gate; it reports, the operator repairs.

## Contract readers

`scripts/ci/fast_gate.sh` exit status and output, found by `git grep fast_gate.sh`:

- `.githooks/pre-push:24,26`: no change; a nonzero exit refuses the push, as today.
- `Makefile:1525` (`make fast-gate`): no change.
- `bin/k3dm-codex-dispatch:1151-1153` (`land` runs the gate in the task worktree against `origin/<target>`): no
  change; worker commits authored with a fixture domain would now be refused at land, which is intended.
- `scripts/tests/bin/codex_dispatch.bats:48,1270-1376,1805-1824`: replace the gate with a stub; unaffected.
- `scripts/tests/lib/fast_gate.bats`: fixture identity changes (Fix).

## Proof of external behaviour

git 2.56.0, M4, 2026-11-09, scratch repo: `git config --local --get-regexp '^user\.'` exits 1 with no output when no
local identity is set and 0 with `user.name Test` / `user.email test@example.invalid` lines when it is;
`git config --local --get core.bare` prints `false` with rc 0 in a fresh `git init` repo.

## Acceptance

```yaml
must:
  - id: M1
    text: "in a scratch repo whose commits in base..HEAD use an address outside example.invalid and example.com, and core.bare false, the gate runs the selected suites and exits 0"
  - id: M2
    text: "when the gate refuses a fixture-domain commit, its output names that commit's short SHA and the git config --local --remove-section user repair"
must_not:
  - id: N1
    text: "a commit in base..HEAD authored with an @example.invalid address passes the gate, when that identity was already in the repo's local config before the gate started (red on pre-fix code; paired with M1)"
  - id: N2
    text: "a commit in base..HEAD whose committer (not author) email is @example.com passes the gate"
  - id: N3
    text: "the gate passes, or runs any suite, when the repo's local core.bare is true"
  - id: N4
    text: "a fixture-domain commit that is already on the base (before base..HEAD) makes the gate fail"
evidence:
  - id: E1
    proves: [M1, M2, N1, N2, N3, N4]
    kind: offline
    intent: "tests run the real fast gate on scratch repos: a repo whose new commits carry the test identity is refused before any suite runs, with the commit named and the one-line repair shown; a normal repo still passes; old commits below the push range do not trip it"
interface:
  - "scripts/ci/fast_gate.sh [BASE], run from the root of a git repository, exit status and stdout/stderr"
```

## Definition of done (worker)

Before your last message, do all of these and paste the evidence:
1. Run `bats scripts/tests/lib/fast_gate.bats`. Give the command, the exit code and every error line. Do not run
   `make test`.
2. For each `must_not`: break the check that enforces it, show its test red, restore it, show it green. List any that
   stayed green with the check broken.
3. No read-only real-data run: the real repo's `.git/config` is clean now, and the gate must not be pointed at it from
   a test. Say so.
4. List every place where you chose something the spec did not decide.
5. Fixtures assert first that they point at a scratch repo, not the real tree.

## Notes

The 2026-10-31 P1's Recurrence section is corrected to say this was a missed repair, not a new write.
