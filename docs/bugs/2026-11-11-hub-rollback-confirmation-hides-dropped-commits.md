# hub-rollback's confirmation lists no commits, and drops promoter commits it never shows

**Status:** OPEN — found 2026-11-11 by the Fable pre-PR review of v1.43.15; confirmed by Claude (scratch repo + reading)
**Priority:** P2
**Waiting on:** operator decision — since 2026-11-11 (intent approval of the Acceptance below)
**Introduced by:** `897cfe72` (v1.43.15, deploy/hub with hub-promote and hub-rollback)
**Should have been caught by:** review
**Prior art:** `docs/bugs/2026-11-10-hub-promote-discards-cve-promoter-commits.md` — read, different case (that fix guards commits on top of the stack top; it states a rollback "drops the latest promotion's commits by design"); `docs/bugs/2026-11-08-hub-promote-no-op-promote-tags-and-breaks-rollback.md` — read, different root cause
**Approval:** operator, 2026-11-11 (semantics: "return to the state live just before last promote"); intent approval pending

## Symptom

1. **Confirmation is always empty.** `show_and_confirm` (`bin/k3dm-hub-promote:86`) prints `git log old..new`. For a
   rollback `new` is an ancestor of `old`, so the list is always empty and it prints `no commits between refs`.
   Scratch repo, 2026-11-11: A, X, B in order; `git log B..A` → `[]`, while the rollback drops `[B X]`.
2. **Promoter commits deployed before the last promote are dropped.** Promote A; the CVE promoter
   (`scripts/etc/argocd/platform-ops/app-cve-scan.sh:544-591`) commits pin X on `deploy/hub`; promote B (contains X).
   `make hub-rollback` targets the previous tag's `new:` (A, `bin/k3dm-hub-promote:197`), so X is dropped. The B tag's
   `old:` records A+X, the state actually live before B.

## Impact

The operator types `promote` to a rollback without seeing what leaves the hub, and an image pin made for a CVE can
silently regress. Workaround: before `make hub-rollback`, run `git log --oneline <previous tag new>..origin/deploy/hub`
on the hub to see what will be dropped.

## Decision (operator, 2026-11-11)

A rollback returns to the state that was live just before the last promote: the top promote tag's `old:`. This keeps
commits that landed on `deploy/hub` between promotions (CVE promoter pins). It supersedes "drops the latest promotion's
commits by design" in `docs/bugs/2026-11-10-hub-promote-discards-cve-promoter-commits.md`.

Live instance (`git ls-remote --tags origin 'refs/tags/hub-promote/*'`, Claude, 2026-11-11): tag
`hub-promote/20261110T115516Z` records `old: 34584e03`, while the previous tag's `new:` is `249c30e6`. Something was
committed on `deploy/hub` between those promotes; today's rollback from `74cd3ca1` would have skipped `34584e03`.

## Fix direction

- `rollback()` (`bin/k3dm-hub-promote:152-201`) keeps each stack entry as the promote tag's (`old`, `new`) pair.
  Promote tags with `old == new` (no-op promotes) push nothing. The target is the top entry's `old`. A rollback tag
  pops the top entry and must carry `new:` equal to that entry's `old`.
- Refuse, without moving anything, when the top entry's `old` is all zeros (bootstrap).
- Keep the existing guard: `deploy/hub` must equal the top entry's `new` or descend from it, otherwise refuse unless
  `BREAK_GLASS=1`.
- `show_and_confirm` for a rollback prints `git log target..old` under "will be removed from deploy/hub" and, if not
  empty, `git log old..target` under "will be added", before asking for `promote`.
- Update `docs/howto/hub-promote.md:66-74` and the `make help` line (`Makefile:1783`) to describe the new target.

## Contract readers

- **Promotion tag message** (`action:`/`old:`/`new:`/`REF:`), writer `record_move` (`bin/k3dm-hub-promote:97-123`):
  format unchanged. Readers: `rollback()` stack replay (`:160-179`, changes: now reads `old:` of promote tags);
  `status()` (`:129`, lists tag names only, unchanged). No reader outside the script (`grep -rn 'hub-promote/' bin
  scripts`, 2026-11-11). Live tags: nine promote tags and no rollback tags, so no rollback tag written under the old
  meaning needs replaying.
- **`deploy/hub` ref**, writers: `hub-promote` promote and rollback (rollback target changes as above); the CVE promoter
  (`scripts/etc/argocd/platform-ops/app-cve-scan.sh:544-591`, writer): its commits made before the last promote now
  survive a rollback; commits made after the last promote are still guarded by the uncontained-commit check. Readers
  (ArgoCD, `make platform-ops`, hub sync) are unchanged; they read whatever the ref holds.
- **Operator docs**: `docs/howto/hub-promote.md:66-74`, `Makefile:1783` help text: change.

## Acceptance

```yaml
must:
  - M1: after promote A, a commit X pushed to deploy/hub, then promote B (containing X), one rollback sets deploy/hub to A+X, the B tag's old
  - M2: before asking for 'promote', the rollback confirmation lists every commit that leaves deploy/hub under a "will be removed" heading
  - M3: with nothing committed between promotions, rollbacks after A, B, C reach B then A, and after a rollback to B and a promote D, a rollback returns to B
  - M4: a rollback writes a tag with action rollback, old the pre-rollback SHA and new the target, and a later rollback replays it
must_not:
  - N1: a rollback removes a commit that was live on deploy/hub immediately before the last promote
  - N2: a rollback when the only promotion is the bootstrap (old all zeros) moves deploy/hub or writes a tag
  - N3: the rollback confirmation prints "no commits between refs" when the rollback removes commits
evidence:
  - E1: {proves: [M1, N1], offline: true, intent: "a rollback keeps CVE image pins that were live before your last promote"}
  - E2: {proves: [M2, N3], offline: true, intent: "before you type promote, you see exactly which commits a rollback removes"}
  - E3: {proves: [M3, M4, N2], offline: true, intent: "rollback still steps back one promotion at a time, and refuses when there is nothing to go back to"}
interface:
  - bin/k3dm-hub-promote rollback (needs a TTY; answers 'promote' on stdin)
  - bin/k3dm-hub-promote promote REF
  - make hub-rollback
  - tags refs/tags/hub-promote/* and branch deploy/hub on a scratch bare origin
```

No live evidence: a live rollback would move the production hub. The behaviour depends only on git, which the fixture
runs for real against a bare origin.

## Files

- `bin/k3dm-hub-promote`
- `scripts/tests/bin/hub_promote.bats`
- `docs/howto/hub-promote.md`
- `Makefile` (help line only)
