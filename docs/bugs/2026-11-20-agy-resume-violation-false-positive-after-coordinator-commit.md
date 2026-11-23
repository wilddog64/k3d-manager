# Bug: agy resume reports "agent committed" after the coordinator commits between rounds

**Status:** OPEN — captured 2026-11-20, not triaged
**Priority:** P3 (proposed; process/tooling, workaround exists)
**Introduced by:** unknown
**Should have been caught by:** spec
**Introducing change reviewed:** unknown
**Classified:** P2 by gemini-4-argon-medium, 2026-11-22 (Coordinator commits between rounds trigger a false `VIOLATION: agent committed` on agy resume and block `land`, requiring manual git log inspection and PR landing.)
**Waiting on:** operator decision — since 2026-11-20
**Prior art:** none above threshold — `make find-similar-docs` unavailable (vector store context missing), exact-slug glob and `grep -il "agent committed" docs/bugs docs/issues` found nothing

## Symptom

`bin/k3dm-codex-dispatch status dirused-m9b-stop-delete-start` showed `state: VIOLATION: agent committed` after
correction round 3 (agy, gemini-3.8-flash-medium) exited 0 on 2026-11-20. The agent had committed nothing: its changes
were uncommitted in the worktree. HEAD was `283eb4e`, a commit Claude made in the worktree after round 2, on top of
Claude's round-1 commit `a9edf98`.

## Cause

`bin/k3dm-codex-dispatch:342-345` (agy branch of the worker) compares `git rev-parse HEAD` with `$run/base`, which is
written once at start (`:1085`) and never moved when the coordinator commits between rounds. Any Claude commit in the
worktree before a resume makes every later agy exit a "violation". `land` then refuses (`:1386`).

## Workaround

Read `git log <base>..HEAD` and check the authors and times of the commits. Claude's commits carry the
`Claude-Session` trailer and come before the resume's start time. In this case the work went to a PR
(wilddog64/dirused#39) instead of `land`.

## Fix direction (for triage)

Record HEAD at each resume start (for example `$run/base-<n>`), and compare the agent's exit against the HEAD at the
start of that round, not the HEAD at dispatch.
