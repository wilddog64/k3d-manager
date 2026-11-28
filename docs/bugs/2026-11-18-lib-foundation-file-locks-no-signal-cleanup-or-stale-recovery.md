# lib-foundation file locks: no signal cleanup, no stale-lock recovery, non-regular lock paths accepted

**Status:** OPEN — captured 2026-11-18 from the PR #89 blind reviews (Argon, Astra 6.2, Fable)
**Priority:** P2 — needs Ctrl-C/SIGTERM mid-download, an interrupted pre-v0.5.7 run, or a planted symlink in a user-owned dir (triage 2026-11-25: was P3; Argon P2, Claude agreed)
**Triage:** upstream → lib-foundation (fix there first, then subtree-pull); backlog until a lib-foundation release takes it (operator, 2026-11-25)
**Introduced by:** items 1-2 pre-existing (lib-foundation `f8025a2`); item 3 lib-foundation `a561b16` (v0.5.7, noclobber claims)
**Should have been caught by:** review
**Introducing change reviewed:** yes (Argon, Fable) for item 3 — found by Astra and Fable in the PR #89 review, accepted as low and deferred
**Classified:** P2 by gemini-4-argon-medium, 2026-11-22 (Interrupted vCluster downloads or pre-v0.5.7 directory locks leave stale lock files that block subsequent runs until manually removed, plus a non-regular file lock hygiene gap.)
**Waiting on:** operator decision — since 2026-11-18 (grooming)
**Prior art:** `docs/bugs/2026-11-14-lib-foundation-run-parallel-collision-test-flakes-on-linux.md` (exact-slug review) — read, different root cause; its plan accepted the old-directory-lock case (item 2). `make find-similar-docs` not run (vector store unreachable, 2026-11-18).
**Filed:** 2026-11-18
**Approval:** operator, 2026-11-18: "we should caputre lder findings in P3 for grooming"

All references are lib-foundation `scripts/lib/system.sh` at `15d5001` (v0.5.7 merge).

## Findings

1. **Only a `RETURN` trap releases the vCluster lock (`:2216`)** — Argon, Astra, Fable. SIGINT/SIGTERM during the download,
   or a `set -e` exit outside the `|| _foundation_vcluster_abort` guards, leaves `<version>.lock`; every later
   `foundation_ensure_vcluster_cli` for that version waits 30 s and fails until the file is deleted by hand.
2. **An old directory lock blocks forever after upgrade (`:2172`, `:2209`)** — Argon, Fable. A `<version>.lock/` directory
   left by an interrupted v0.5.6-or-earlier run makes the noclobber claim fail with EISDIR on every try, and `rm -f`
   cannot remove it. Accepted in the v0.5.7 plan; listed here so a stale-lock recovery covers it.
3. **noclobber accepts an existing non-regular file (`:875`, `:2172`)** — Astra, Fable; reproduced by Claude 2026-11-18
   (macOS bash 3.2.57 and bash 5): with `<lock> -> /dev/null` two consecutive claims both return 0 (the old `mkdir` claim
   returned 1). A directory or dangling symlink is refused. A FIFO blocks the open. Needs something planted in the user's
   own `--out` dir or `XDG_DATA_HOME`.

## Possible fix (for grooming)

Add INT/TERM handlers (release, then re-raise) around the vCluster critical section; stale recovery: record the holder PID
in the lock file and take over when that PID is gone, removing an old directory lock the same way; after a successful
claim, refuse unless the path is a regular file and not a symlink (`[[ -f "$lock" && ! -L "$lock" ]]`).
