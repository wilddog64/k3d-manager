# Bug: K3dmPromoteWaiting keeps firing for a commit on the squash-merged release branch

**Status:** OPEN
**Priority:** P2 (Argon P2 accepted, grooming 2026-11-22, operator; was: P3 (proposed: a false warning email every cycle after each release merge; no wrong deploy))
**Triage:** carry → v1.46.0 — grooming 2026-11-22, operator
**Branch:** `k3d-manager-v1.46.0`
**Introduced by:** `46ec5b36` (v1.44.0, promotable lookup in `bin/k3dm-repo-sync`)
**Should have been caught by:** spec
**Introducing change reviewed:** unknown
**Classified:** P2 by gemini-4-argon-medium, 2026-11-22 (False `K3dmPromoteWaiting` alert fires continuously after a squash-merged release, with a workaround of switching the hub checkout to the next release branch.)
**Waiting on:** operator decision — since 2026-11-17
**Prior art:** `docs/bugs/2026-11-13-deploy-hub-behind-counts-docs-only-commits.md` (exact-slug pass; `find-similar-docs` not run, vector store needs the hub context) — read, related (docs-only commits counted), different root cause (dead upstream after squash merge). `docs/bugs/2026-11-12-hub-promote-containment-check-blind-to-squash-merges.md` — read, same squash-merge blind spot in a different tool.
**Filed:** 2026-11-17

## Symptom

`[FIRING] K3dmPromoteWaiting on hub` emailed from 2026-11-17 04:45Z, and it was still active at 12:45Z, after
v1.44.1 was promoted (deploy/hub 666b27b7, 12:16Z). Read live on the hub (Alertmanager `127.0.0.1:19093`,
2026-11-17 ~12:45Z): one alert, `sha=1c12925`.

## Cause

- `1c129251` ("dirused M1e: Argon review and vm-live adjudication") is a docs and memory-bank commit on
  `origin/k3d-manager-v1.44.1`. Its content shipped inside squash commit 666b27b7, but the commit itself is not
  an ancestor of `deploy/hub`.
- The hub checkout is still on branch `k3d-manager-v1.44.1` (hub pane prompt, 2026-11-17). `bin/k3dm-repo-sync:450`
  takes the checkout's `@{upstream}` and `find_promotable` (`:83-85`) lists `deploy/hub..<upstream>`.
- After a squash merge that range never empties, so the newest CI-green commit on the dead branch stays
  "promotable" until someone moves the hub checkout to the next release branch.

## Fix direction (not decided)

Either compare by tree or patch content rather than ancestry (`git cherry` or tree equality with deploy/hub), or
treat an upstream already merged into `main` as having no promotable work. Ignoring docs-only commits (the
2026-11-13 bug) would also have hidden this case, but not for a code commit.

Immediate clear: switch the hub checkout to `k3d-manager-v1.44.2` (operator go: it changes the hub).
