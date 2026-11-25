# Bug: a dispatch worker's partial edit was left in the main checkout

**Status:** OPEN
**Priority:** P3 (proposed: caught by land's dirty-checkout guard; no wrong code landed)
**Introduced by:** unknown
**Should have been caught by:** unknown
**Introducing change reviewed:** unknown
**Waiting on:** operator decision — since 2026-11-24
**Prior art:** Pass 1 exact slug: none; name grep `partial|out-of-scope` found `2026-11-08-dispatch-land-allow-out-of-scope-lands-instruction-file-changes.md` — read, different defect; `make find-similar-docs` not run
**Detected by:** Claude, 2026-11-24, landing `2026-11-23-preflight-services-appset-name-rename-no-longer-matches`

## What happened

The second land attempt refused with "target checkout is dirty". The main checkout
(`k3d-manager-v1.45.1`) had an uncommitted `bin/cluster-preflight` change: the fix's guard block and the
deletion of the old `name: '{{.path.basename}}'` sed line, but **not** the replacement sed line. It was an
incomplete copy of the worker's fix. `_dispatch_scope_verdict` refuses before any apply
(`bin/k3dm-codex-dispatch:1435`), so the earlier refused land did not write it. The most likely writer is the
Codex worker editing the main checkout during its run (compare the known codex exec sandbox-cwd cross-repo
behaviour). Unproven.

The diff was saved before `git restore`, and the land then succeeded as `0d7d1e18`.

## Why it matters

Had the operator committed the main checkout as it stood, a broken preflight render would have shipped:
services Applications keep their production names. `make hub-deploy` and other operator commands also run
from that checkout.

## Possible fix (not decided)

`bin/k3dm-codex-dispatch status` or the exit watcher could compare `git -C <main> status --porcelain` before
start and at exit, and flag new changes to files the task touched.
