# Active Context — lib-acg

## Current Branch: `main`

**Repo created:** 2026-04-25
**Status:** Skeleton committed — awaiting Phase 3 file migration from k3d-manager.

## Phase Status

- [x] **Phase 2** — COMPLETE. Repo skeleton created; lib-foundation subtree pending.
- [ ] **Phase 3** — PLANNED. Migrate acg.sh, gcp.sh, playwright scripts, vars.sh, and
      extract _browser_launch + _cdp_ensure_acg_session into scripts/lib/cdp.sh.
      Spec: `k3d-manager/docs/plans/v1.2.0-lib-acg-extraction.md` Phase 3 section.

## Consumed By

- `k3d-manager` — will pull via git subtree at `scripts/lib/acg/` (Phase 4)
