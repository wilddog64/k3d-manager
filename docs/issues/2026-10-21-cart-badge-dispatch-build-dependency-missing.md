# Cart-badge dispatch build validation blocked by local dependency tree

**Date:** 2026-10-21
**Repository:** `shopping-cart-frontend`
**Dispatch:** isolated worktree `/Users/cliang/.codex/worktrees/bdce/shopping-cart-frontend`, Codex session `01a15e8a-082b-71a1-a06f-d2792259984b`

## Attempted validation and actual output

The isolated worktree had no `node_modules`, so the worker's first test/lint/build attempts could not locate `vitest`, `eslint`, or `tsc`. Reused the existing main-checkout dependencies through a temporary symlink (removed after testing); no package installation or network access was attempted.

Focused and full tests then passed:

```text
Test Files  3 passed (3)
Tests       11 passed (11)
Test Files  9 passed (9)
Tests       37 passed (37)
```

`npm run lint` passed. `npm run build` reached Vite but failed at PostCSS config loading:

```text
Build failed with 1 error:
[plugin vite:css] .../src/index.css
Failed to load PostCSS config: Failed to load PostCSS config (searchPath: .../shopping-cart-frontend): [Error] Loading PostCSS Plugin failed: Cannot find module '@tailwindcss/postcss'
Require stack:
- .../shopping-cart-frontend/postcss.config.js
```

`git diff --check` passed. The dispatch candidate is not committed or landed.

## Root cause and follow-up

The local dependency tree is incomplete for the build; this does not establish a source-code build failure. Before landing, restore the declared dependency from the repository lockfile using the normal approved dependency workflow, then rerun build, tests, and lint. Do not add or change dependencies merely to bypass this local validation gap.
