# Bug: K3dmPromoteWaiting tells the operator to run `make hub-promote` instead of `make hub-deploy`

**Status:** OPEN — captured 2026-11-15
**Priority:** P3 (the named command works but only moves the ref; the follow-up steps then raise `K3dmDeployPending`)
**Introduced by:** v1.44.0 plan `hub-deploy-one-command` (landed without the string change the behind-alert plan assigned to it); alert added in c763e239
**Should have been caught by:** spec
**Introducing change reviewed:** unknown
**Waiting on:** operator decision — since 2026-11-15
**Prior art:** none (exact-slug pass; `make find-similar-docs` unavailable on the M4: vector store needs context `k3d-k3d-cluster`)

## What happens

`scripts/etc/prometheus/rules/repo-sync.yaml:39`: `description: "Run: make hub-promote REF={{ $labels.sha }}"`.
`docs/plans/v1.44.0-deploy-hub-behind-alert.md` (Design 3) says this "becomes `make hub-deploy` when part 1 lands; that
plan updates the string". Part 1 (`make hub-deploy`, `bin/k3dm-hub-deploy`) landed; the string did not change. Found by
the v1.44.0 doc audit (Claude, 2026-11-15).

## Fix

Change the description to `Run: make hub-deploy REF={{ $labels.sha }}` (no test pins the annotation; `git grep` 2026-11-15),
then drop the note in `docs/howto/hub-sync.md`.
