# A non-semver highest tag resets a project's dispatch version to v0.0.1

**Status:** OPEN — captured 2026-11-18 from Fable's blind diff review of PR #163 (v1.44.2), verified by Claude
**Priority:** P3 — latent; dirused has no pre-release tags
**Introduced by:** 6972d10a (codex-dispatch multi-project M1, k3d-manager-v1.44.2)
**Should have been caught by:** offline test
**Introducing change reviewed:** yes (Argon, missed)
**Waiting on:** operator decision
**Prior art:** none above threshold. Exact slug: no match; keyword grep of docs/bugs: no match. `make find-similar-docs` not run (vector store unreachable from this machine: no k3d-k3d-cluster context).
**Filed:** 2026-11-18

## Symptom

`start --project` (`bin/k3dm-codex-dispatch:1009-1010`) sorts every `v*` tag and regex-tests only the last one. With tags
v0.0.9, v0.0.10 and `v0.1.0-rc1`, the last is the rc, the regex fails, and the version becomes `v0.0.1` (Fable, scratch
repo). The task lands in an old version directory.

## Fix sketch

Filter to `^v[0-9]+\.[0-9]+\.[0-9]+$` before `sort -V`. Test: the three tags above → `v0.0.11`; a single `v0.0.4` → `v0.0.5`
(existing P2 control).
