# Bug: promote mover: any pushed branch or tag can block promotes; all-skipped checks count as green

**Status:** OPEN — captured 2026-11-23
**Priority:** P3
**Triage:** next-minor → v1.47.0 candidate at the next /release-groom (operator, 2026-11-25); Argon blind classification, Claude verified
**Introduced by:** v1.45.0 plan 2d (deploy-ref mover)
**Should have been caught by:** review
**Introducing change reviewed:** unknown
**Waiting on:** operator decision
**Prior art:** exact-slug glob: none; `make find-similar-docs` not run (vector store unavailable: cluster context missing); grep of docs/bugs for the key terms found no match
**Detected by:** v1.45.0 red-team gate, 2026-11-22, on `7dfb7238` — see [docs/issues/2026-11-23-v1.45.0-red-team.md](../issues/2026-11-23-v1.45.0-red-team.md)
**Severity:** denial of service on promotion and audit gaps; no unapproved move of `deploy/hub` found.
**Findings:** Astra 4, Astra 6, Fable 4, Fable 5, Fable 6. Claude: 4 and 6 confirmed, 5 plausible, P3.

## What is wrong (`scripts/lib/promote_mover.py`)

- `:122-155` fetches `+refs/heads/*` into the root daemon's mirror; `:13,301`: a pushed `k3d-manager-v999.0.0` becomes "newest",
  so every legitimate promote refuses `not_newest_branch`.
- `:178` treats `neutral` and `skipped` as success: an all-skipped check set is "green" (an approval is still required).
- `:182-208`: any annotated `hub-promote/*` tag with `approval: <id>` counts as a witness; the tagger is not checked, so a pushed tag
  burns the approval (`already_spent`) or causes `witness_conflict`.
- `:335` push then `:345` marker: a crash between them leaves `deploy/hub` moved with no witness tag and the approval unspent.

## Fix direction

Ruleset on `k3d-manager-v*` and `hub-promote/*`; narrow the refspec; all-skipped = `none`; match the daemon's own tag object or
authority tagger; pending marker before the push; `errors="replace"` in `subprocess.run`.
