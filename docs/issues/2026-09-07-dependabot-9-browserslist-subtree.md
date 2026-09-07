# Dependabot #9 — browserslist high alert (lib-acg subtree)

**Date:** 2026-09-07
**Alert:** Dependabot #9 (open, severity **high**)
**Advisory:** Browserslist — uncaught crash / prototype write via untrusted `browserslist-stats.json` custom stats (`normalizeStats`)
**Package:** `browserslist` (npm), vulnerable `<= 4.28.6`, first patched `4.28.7`
**Manifest:** `scripts/lib/foundation/scripts/lib/acg/package-lock.json`

## Triage

- **Real-world severity here: LOW** despite the "high" label. The advisory triggers only when
  an attacker-controlled `browserslist-stats.json` custom-stats file is fed to browserslist's
  `normalizeStats`. `browserslist` is a **transitive dev-tool dependency** (jest/babel + playwright
  toolchain) of the `lib-acg` package (`private: true`, dev automation only — see its `package.json`:
  runtime deps are just `playwright`). Nothing in the codebase feeds untrusted stats to browserslist,
  and it is not part of any shipped runtime path. No exploit path in this repo.
- **Legitimately fixable** by bumping the lockfile to `browserslist@4.28.7`.

## Why it cannot be fixed in this repo

The manifest lives under `scripts/lib/foundation/` — a git **subtree** — which itself vendors
`scripts/lib/acg/` — a second subtree. Both are edit-upstream-first; editing either inside
k3d-manager is forbidden (a local lockfile bump would be clobbered on the next subtree pull).

## Fix path (upstream, when scheduled)

1. In the **lib-acg** upstream repo: `npm update browserslist` (or `npm audit fix`) to move the
   lockfile to `>= 4.28.7`; commit + PR upstream.
2. Propagate into **lib-foundation** (which vendors lib-acg).
3. Re-vendor the updated subtree(s) down into k3d-manager via the normal subtree-pull, then confirm
   Dependabot #9 auto-closes.

Not urgent given the low in-context risk; batch it with the next lib-acg / lib-foundation subtree
refresh. This is exactly the class of drift the planned Hermes monthly security-audit
(`docs/plans/v1.32.0-hermes-monthly-security-audit.md`) is designed to keep visible.
