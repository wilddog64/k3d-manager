# acg module package name still claims the retired `lib-acg` repo

**Date:** 2026-09-12
**Module:** `scripts/lib/acg/`
**Severity:** low (metadata only — no runtime behaviour)

## Symptom

`scripts/lib/acg/package.json` and `scripts/lib/acg/package-lock.json` both declare
`"name": "lib-acg"`. The standalone `wilddog64/lib-acg` repo was absorbed into lib-foundation
in v0.4.0 and archived on 2026-09-12, so the package identity names a repo that no longer
exists as a source of truth.

## Scope — what is and is NOT stale

Only the live package metadata is wrong. A repo-wide grep finds 89 other `lib-acg` references,
and **they are all historically accurate and must not be rewritten**:

- `CHANGE.md` entries describing the absorption and the imported commits
- `docs/plans/v0.4.0-absorb-lib-acg.md` — the absorption plan
- `docs/bugs/`, `docs/issues/` — specs and findings that cite `lib-acg` SHAs as provenance
- `README.md`, `docs/api/acg.md` — "imported from lib-acg", which is true

Rewriting those would falsify the record of where this code came from. They stay.

`scripts/lib/acg/tests/providers/output.test.js:36` uses a `lib-acg-output-` temp-dir prefix.
That is a local string, not the package identity, and is left alone (minimal-patch rule).

## Root cause

The v0.4.0 absorption was a deliberate **verbatim clean tree-copy** from lib-acg `7708ae31` —
byte-for-byte fidelity was load-bearing for reviewability. `package.json` came across unchanged
along with everything else, and the identity field was never revisited afterwards.

## Fix

Rename the package to `lib-foundation-acg` in both files:

`scripts/lib/acg/package.json`:
```json
  "name": "lib-acg",
```
becomes
```json
  "name": "lib-foundation-acg",
```

`scripts/lib/acg/package-lock.json` — both the top-level `name` and the root-package
(`packages.""`) `name`, which npm requires to match `package.json`.

Safe because:
- the package is `"private": true` and has never been published to a registry
- nothing imports or resolves it by name (grep over `*.sh`, `*.js`, `*.json`, `Makefile`)
- `version` stays `0.4.0`; no dependency graph changes, so no `npm install` is required

## Verification

- `node -e` parse of both JSON files succeeds
- `scripts/lib/acg/package.json` and `scripts/lib/acg/package-lock.json` are the only files
  carrying a code or metadata change; the branch also touches `CHANGE.md` and adds this spec
  doc, which are documentation only and affect nothing at runtime
- `npm ci` in `scripts/lib/acg/` still resolves, and `npm test` (28 jest) stays green

## Process note

A verbatim import is the right call for reviewability, but it carries the source repo's
identity with it. An absorption checklist should include an explicit "re-home the package
metadata" step so identity fields are not silently inherited from the retired repo.
