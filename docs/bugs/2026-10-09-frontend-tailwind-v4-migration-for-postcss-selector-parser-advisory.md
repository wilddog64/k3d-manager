# Frontend: Tailwind v4 migration to clear the postcss-selector-parser advisory

**Status:** FIXED — Codex `c9d3a95d` + Claude `d6fc1bf1` (codemod renamed a test title); PR shopping-cart-frontend #117 merged 2026-10-09T16:59:49Z (`05ec17e3`); local Chromium E2E 42/42
**Priority:** P3 — medium advisory in a build-time dependency; Dependabot reopens a breaking PR until it is fixed
**Component:** `shopping-cart-frontend` (Tailwind CSS 3.4 → 4.3, PostCSS pipeline)
**Found:** 2026-10-09, E2E failure on Dependabot PR #114 (closed)

## Symptom

Dependabot security PR #114 ("bump postcss-selector-parser and tailwindcss") failed the required E2E
job after 70 minutes. Every page request to the Vite dev server returned 500:

```
[postcss] It looks like you're trying to use `tailwindcss` directly as a PostCSS plugin…
```

## Root cause

- Alert #41, GHSA-rj75-hqrm-r3gf (medium): `postcss-selector-parser` has quadratic parsing.
  The first patched version is 7.1.6.
- `tailwindcss` 3.x depends on `postcss-selector-parser` 6.x, so the only update path Dependabot
  found was `tailwindcss` 3.4.19 → 4.3.3.
- Tailwind 4 moved its PostCSS plugin to `@tailwindcss/postcss`. `postcss.config.js` still loads
  `tailwindcss` directly, so CSS compilation throws on every page.
- `.github/dependabot.yml` ignores npm semver-major bumps, but that rule only covers **version**
  updates. Security updates take whatever version clears the advisory, so the PR opened anyway.
- `dependabot-automerge.yml` auto-merges every security update once required checks pass. The E2E
  job was what stopped this one.

The alert stays open after closing #114, so another breaking PR will open when Tailwind 4 has a
new release. The migration is the lasting fix.

## Implementation spec (Codex)

**Repo:** `shopping-cart-frontend`. **Working copy:** `~/src/gitrepo/personal/shopping-carts/shopping-cart-frontend-tw4`
(a fresh clone; do not use the main `shopping-cart-frontend` checkout, which has unrelated work).
**Branch:** `chore/tailwind-v4-migration`, from `origin/main` (`3623e5b`).
**Files:** `package.json`, `package-lock.json`, `postcss.config.js`, `src/index.css`,
`tailwind.config.js` (kept or removed; see step 2), the `src/**/*.tsx` / `src/**/*.ts` files the
upgrade tool rewrites, `README.md` (Styling row), `docs/architecture/README.md` (Styling row),
`CHANGELOG.md` (`[Unreleased]` → `### Changed`). Nothing else.

### Step 1 — run the official codemod

```bash
npm ci
npx --yes @tailwindcss/upgrade@4.3.3 --force
```

The tool needs Node 20+ and a clean tree. It rewrites `src/index.css`, the PostCSS config,
`package.json`, and the v3 class names that changed in v4. This repo uses `shadow`, `shadow-sm`,
`rounded`, `outline-none`, bare `ring`, and `flex-shrink-0`. Use the tool rather than search and
replace: bare `ring`, `shadow` and `rounded` also appear inside longer class names and plain strings,
and only the tool parses class lists. Paste its full output in your report.

### Step 2 — make the result match these end states

If the tool leaves anything different from the following, fix it by hand:

1. `postcss.config.js`:
   ```js
   export default {
     plugins: {
       '@tailwindcss/postcss': {},
     },
   }
   ```
   Tailwind 4 handles vendor prefixes, so `autoprefixer` is removed from the config **and** from
   `devDependencies`.
2. `src/index.css` starts with `@import "tailwindcss";`, with no `@tailwind` directives. The
   `primary` color scale must still exist, either as an `@theme` block in CSS (the tool's default,
   which deletes `tailwind.config.js`) or through `@config "../tailwind.config.js";`. Both are
   acceptable.
3. `src/index.css` still sets the default border color to gray-200 for every element. Keep the
   existing `* { @apply border-gray-200; }` rule or the tool's equivalent. In v4 the default is
   `currentColor`, and dropping this rule would turn every `border` dark.
4. `package.json` `devDependencies`: `"tailwindcss": "^4.3.3"` and `"@tailwindcss/postcss": "^4.3.3"`.
   No `autoprefixer`. Keep `postcss`. Leave `tailwind-merge` (2.x) unchanged.
5. `npm ls postcss-selector-parser` prints nothing, or only versions ≥ 7.1.6.

### Step 3 — docs and CHANGELOG

- `README.md` and `docs/architecture/README.md`: change the `Styling` row value from `Tailwind CSS 3.x`
  to `Tailwind CSS 4.x`.
- `CHANGELOG.md` `[Unreleased]` → `### Changed` (create the subsection if missing), one bullet:
  `Tailwind CSS 3.4 → 4.3 (PostCSS plugin now \`@tailwindcss/postcss\`; CSS entry \`@import "tailwindcss"\`; v4 utility renames applied by \`@tailwindcss/upgrade\`; \`autoprefixer\` removed). Clears GHSA-rj75-hqrm-r3gf (postcss-selector-parser < 7.1.6). Raises the browser floor to Safari 16.4 / Chrome 111 / Firefox 128.`

### Gates (run all; paste the tail of each)

```bash
npm run lint
npm run build            # tsc -b && vite build
npm test                 # vitest run
npx playwright install chromium && npm run test:e2e
npm audit --audit-level=moderate
! grep -rn '@tailwind ' src/                    # must print nothing and exit 0
grep -c '@tailwindcss/postcss' postcss.config.js  # 1
```

- `npm audit` must not list `postcss-selector-parser`. If it fails only on other, pre-existing
  advisories, list them in your report and do not fix them.
- E2E must pass. If Playwright cannot download its browser inside the sandbox, say so explicitly
  and paste the error. Do not skip silently; CI runs E2E on the PR.
- RED check: before step 1, `grep -c "tailwindcss: {}" postcss.config.js` prints `1`. Afterwards it prints `0`.

### Commit and push

```bash
git push -u origin chore/tailwind-v4-migration
git ls-remote origin chore/tailwind-v4-migration   # must equal git rev-parse HEAD
```

**Commit message (exact):**
```
chore(deps): migrate Tailwind CSS 3.4 to 4.3 to clear postcss-selector-parser advisory

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
```

### What NOT to do

- No PR, no merge, no push to `main`, no `--no-verify`.
- Do not bump React, Vite, `tailwind-merge`, or anything else beyond what Tailwind 4 requires.
- Do not edit `.github/` (workflows, `dependabot.yml`).
- Do not edit `e2e/` specs to make them pass. A failing E2E is a finding to report.
- Do not touch the main `shopping-cart-frontend` checkout.
