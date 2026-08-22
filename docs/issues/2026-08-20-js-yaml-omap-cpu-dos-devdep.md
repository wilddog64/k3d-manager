# js-yaml quadratic-CPU DoS (CVE-2026-59870 / GHSA-5p4m-2wfm-xmqj)

**Filed:** 2026-08-20
**Severity:** High (per advisory) — **effective risk: low** (dev-only, no untrusted-YAML surface)
**Status:** Fixed on `feat/v0.4.11` (lockfile bump), pending PR/merge + subtree flow-down

## Alert

Dependabot alert #6 on `wilddog64/k3d-manager` (alerts are disabled on lib-foundation
itself, so the alert surfaces only on the consumer that vendors this lockfile via the
`scripts/lib/foundation/` subtree):

- **Package:** `js-yaml`
- **Manifest (as seen on consumer):** `scripts/lib/foundation/scripts/lib/acg/package-lock.json`
- **Source of truth:** `scripts/lib/acg/package-lock.json` (this repo)
- **Vulnerable range:** `>= 3.0.0, < 3.15.1`
- **Installed (pre-fix):** `3.15.0` — bumped to `3.15.1` by this change (see Fix below).
- **First patched:** `3.15.1`
- **Scope:** `development`
- **Summary:** Quadratic CPU consumption in `!!omap` resolution.

## Why the effective risk is low

`js-yaml` is a **transitive dev-only** dependency, not a runtime or shipped dependency:

```
jest (devDependency)
  └─ @istanbuljs/load-nyc-config  (requires js-yaml ^3.13.1)
       └─ js-yaml
```

It is pulled in solely by istanbul/nyc coverage tooling under `jest`. The only YAML it
parses is trusted local coverage config — never untrusted or attacker-controlled input —
so the `!!omap` CPU-amplification vector is not reachable in this project.

## Fix

The advisory summary text ("fix not backported") is contradicted by the authoritative
`first_patched_version: 3.15.1` field: **3.15.1 patches the 3.x line and satisfies the
existing `^3.13.1` constraint**, so no `overrides` entry or major-version bump is needed.

Applied as a lockfile-only bump on `feat/v0.4.11`:

```bash
cd scripts/lib/acg
npm update js-yaml --package-lock-only   # 3.15.0 -> 3.15.1
```

Diff is 3 lines (version / resolved / integrity) on `node_modules/js-yaml`; `package.json`
is untouched (js-yaml is transitive).

## Flow-down to consumers

Because the alert path is the **vendored subtree copy** in k3d-manager, clearing alert #6
requires this fix to be released here and then pulled down:

1. Merge `feat/v0.4.11` (this fix) to lib-foundation `main` + tag/release.
2. `git subtree pull --prefix=scripts/lib/foundation ... --squash` in k3d-manager.
3. Confirm alert #6 auto-resolves once the consumer lockfile shows `js-yaml 3.15.1`.
