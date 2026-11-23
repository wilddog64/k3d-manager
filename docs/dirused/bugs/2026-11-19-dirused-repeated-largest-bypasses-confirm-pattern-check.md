# dirused `/purge /confirm` with a repeated `/largest` deletes from the whole default list

**Status:** LANDED — 1f0779f on branch m8b-purge-dry-run, PR wilddog64/dirused#32
**Priority:** P2 — deletes files nobody named, but only with an unusual command line (`/largest` twice, the last without patterns) plus `/confirm`; workaround: give `/largest` once
**Introduced by:** M8 (wilddog64/dirused fa3a07c, released v0.0.18)
**Should have been caught by:** review
**Introducing change reviewed:** yes (both)
**Waiting on:** live check — since 2026-11-19 (released v0.0.19, merge b708b63; operator E2 on work laptop)
**Tracked:** dirused (OOB repo), not a k3d-manager release.
**Prior art:** `docs/dirused/bugs/2026-11-19-dirused-purge-dry-run-refuses-without-pattern.md` (same parser lines, different root cause); find-similar-docs not run
**Fix commit:** 1f0779f (wilddog64/dirused PR #32)
**Filed:** 2026-11-19

## Symptom

Found by the blind Argon review of PR #32 and reproduced by Claude on both fa3a07c and f79ba4c (probe calling `ArgParser.Parse`):
`dirused C:\ /largest *.log /largest /purge /confirm` parses with no error, and `Largest` is the 25-pattern default list
(`*.bak`, `*.dmp`, `*.tmp`, `*.old` and others). With `/confirm`, that run deletes those files.

## Cause

`largestExplicit` was set to true by the first `/largest` that had a pattern and never cleared. The second `/largest`
replaced the pattern list with the defaults.

## Fix

Each `/largest` resets `largestExplicit` before reading its own argument, so the last `/largest` decides.
Red/green: the new ArgParserTests assertions fail on f79ba4c (1 failed) and pass with the fix (121/121). Positive control:
`/largest /largest *.log /purge /confirm` still parses.
