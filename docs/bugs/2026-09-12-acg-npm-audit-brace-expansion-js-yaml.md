# acg module: 2 high-severity npm advisories (`brace-expansion`, `js-yaml`)

**Date:** 2026-09-12
**Module:** `scripts/lib/acg/`
**Severity:** high (per advisory) — but both are **dev-only transitive deps of `jest`**, not runtime
**Branch (all work):** `fix/acg-npm-audit-brace-expansion-js-yaml`

## Symptom

`npm audit` in `scripts/lib/acg/` reports 2 high-severity vulnerabilities:

```
brace-expansion  <=1.1.17   (installed 1.1.16)
  GHSA-mh99-v99m-4gvg  DoS via unbounded expansion length causing an OOM process crash
  GHSA-rgw5-rvv9-x895  DoS via unbounded intermediate arrays, bypassing the CVE-2026-14257 mitigation

js-yaml  3.0.0 - 3.15.1     (installed 3.15.1)
  GHSA-2883-xcg3-v3hh  maxTotalMergeKeys does not limit CPU use for empty merge sources
```

## Exposure — read this before deciding the fix is urgent

Both are **transitive `devDependencies` of `jest@29.7.0`** and are marked `"dev": true` in the
lockfile. Neither is reachable from any runtime code path in this module (the runtime dependency is
`playwright`). Measured paths:

```
lib-foundation-acg@0.4.0
└─┬ jest@29.7.0 → @jest/core → @jest/reporters → glob@7.2.3 → minimatch@3.1.5 → brace-expansion@1.1.16
└─┬ jest@29.7.0 → @jest/core → @jest/transform → babel-plugin-istanbul@6.1.1
                → @istanbuljs/load-nyc-config@1.1.0 → js-yaml@3.15.1
```

So the practical impact is a DoS surface in the **test toolchain only**. This is worth clearing to
keep `npm audit` at zero (and to stop GitHub echoing the advisories), not an incident.

## Root cause

Both are deep transitive pins carried by `jest@29.7.0`'s own dependency tree. Patched releases exist
**inside the semver ranges jest already requests**, so nothing was blocking the upgrade — the
lockfile simply had not been refreshed since those patches shipped:

- `brace-expansion` 1.1.18 satisfies the requested `^1.1.7`
- `js-yaml` 3.15.2 satisfies the requested `^3.13.1`

No `overrides` block, no jest major bump, and no `package.json` change are required.

## Fix — exact commands

Run in `scripts/lib/acg/`:

```bash
npm update brace-expansion js-yaml --package-lock-only --ignore-scripts
```

`--package-lock-only` keeps this a lockfile-only change; `--ignore-scripts` avoids the
`fsevents` install-script warning. Do **not** run bare `npm audit fix` — it is free to touch
unrelated entries; the targeted `npm update` is what was measured.

## Expected diff — EXACTLY this, nothing else

`scripts/lib/acg/package-lock.json`, two entries, 6 changed lines total. `scripts/lib/acg/package.json`
must be **byte-identical** afterwards.

```diff
     "node_modules/brace-expansion": {
-      "version": "1.1.16",
-      "resolved": "https://registry.npmjs.org/brace-expansion/-/brace-expansion-1.1.16.tgz",
-      "integrity": "sha512-IDw48K2/2kRkg9LdJxurvq3lV3aBgq0REY89duEqFRthjlPdXHKMj7EnQOXVckxzgisinf3nHfrcE2FufFLXMw==",
+      "version": "1.1.18",
+      "resolved": "https://registry.npmjs.org/brace-expansion/-/brace-expansion-1.1.18.tgz",
+      "integrity": "sha512-Edep/X9fGqVNmzKBVsDYIOtD+z1tuezV70LBjdCst9Tqu76lsnvRiZ6oTic1n+/BIwX6QDGAO94PN4N2SADvtw==",
       "dev": true,
```

```diff
     "node_modules/js-yaml": {
-      "version": "3.15.1",
-      "resolved": "https://registry.npmjs.org/js-yaml/-/js-yaml-3.15.1.tgz",
-      "integrity": "sha512-S99WuO3HlhO3XN41EtYUNl9zzXjoJx7QvmipxsJVxtCBT0YHEFy+iOJhjSvrmV12nYhWpZaM8lPHkJm0yUMbag==",
+      "version": "3.15.2",
+      "resolved": "https://registry.npmjs.org/js-yaml/-/js-yaml-3.15.2.tgz",
+      "integrity": "sha512-6EuL879VkRA+1Cz578mKMiKvjPNEuk6+r1JaFzoSWejZmtf7xWbIyw1e3KkxlkzTIt9Taw6JBhEppG7utc1P+w==",
       "dev": true,
```

Do **not** hand-edit these values. Regenerate them with the `npm update` command above so the
`integrity` hashes come from the registry. If your regenerated hashes differ from the ones quoted
here, STOP and report it — that is a supply-chain signal, not a formatting difference.

## CHANGE.md

Add under `## [Unreleased]`, in a `### Security` subsection (create it if absent — leave any
existing `### Changed` subsection there alone; `fix/acg-package-name-identity` also writes to
`[Unreleased]` and both entries must survive):

```markdown
### Security
- `scripts/lib/acg/package-lock.json`: bump `brace-expansion` 1.1.16 → 1.1.18
  (GHSA-mh99-v99m-4gvg, GHSA-rgw5-rvv9-x895) and `js-yaml` 3.15.1 → 3.15.2
  (GHSA-2883-xcg3-v3hh), clearing both high-severity `npm audit` findings. Both are dev-only
  transitive dependencies of `jest@29.7.0` and are not reachable from any runtime path; the
  patched releases already satisfy the semver ranges jest requests, so this is a lockfile
  refresh only — no `overrides`, no `package.json` change, no jest bump. Spec:
  `docs/bugs/2026-09-12-acg-npm-audit-brace-expansion-js-yaml.md`.
```

## Rules

- Lockfile-only. `scripts/lib/acg/package.json` must not change.
- Do not add an `overrides` block.
- Do not bump `jest`, `playwright`, or any other direct dependency.
- Do not commit `node_modules/`.
- Do not reformat `package-lock.json` — only the 6 lines above may differ.

## Definition of Done

- [ ] `npm update brace-expansion js-yaml --package-lock-only --ignore-scripts` run in `scripts/lib/acg/`
- [ ] `git -C <repo> diff --stat` shows **exactly** `docs/bugs/...` (new), `CHANGE.md`, and
      `scripts/lib/acg/package-lock.json` — nothing else
- [ ] `npm audit` in `scripts/lib/acg/` prints `found 0 vulnerabilities` — paste the output
- [ ] `npm ci` in `scripts/lib/acg/` succeeds against the new lockfile — paste the tail
- [ ] `npm test` in `scripts/lib/acg/` → **7 suites / 28 tests passed** — paste the summary lines
- [ ] `node -e 'require("./package-lock.json")'` parses
- [ ] CHANGE.md `### Security` entry added under `[Unreleased]` without deleting anything already there
- [ ] Committed on `fix/acg-npm-audit-brace-expansion-js-yaml` with this exact message:

```
fix(acg): bump brace-expansion 1.1.18 and js-yaml 3.15.2 (2 high advisories)
```

- [ ] Report the commit SHA

## What NOT to Do

- Do NOT create a PR.
- Do NOT merge anything.
- Do NOT commit to `main`.
- Do NOT skip pre-commit hooks (`--no-verify`).
- Do NOT modify any file outside the three listed above.
- Do NOT touch `fix/acg-package-name-identity` or PR #52.
- Do NOT run `git push --force` anything.
- If `git commit` fails with `Unable to create '.../.git/index.lock': Operation not permitted`,
  that is the known sandbox limit — **stop and report it**, leave the working tree as-is, and do
  not retry or work around it. Claude will commit.
