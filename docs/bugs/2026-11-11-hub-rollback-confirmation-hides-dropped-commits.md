# hub-rollback's confirmation lists no commits, and drops promoter commits it never shows

**Status:** OPEN — found 2026-11-11 by the Fable pre-PR review of v1.43.15; confirmed by Claude (scratch repo + reading)
**Priority:** P2
**Waiting on:** operator decision — since 2026-11-11 (keep or drop promoter commits on rollback; then intent approval)
**Introduced by:** `897cfe72` (v1.43.15, deploy/hub with hub-promote and hub-rollback)
**Should have been caught by:** review
**Prior art:** `docs/bugs/2026-11-10-hub-promote-discards-cve-promoter-commits.md` — read, different case (that fix guards commits on top of the stack top; it states a rollback "drops the latest promotion's commits by design"); `docs/bugs/2026-11-08-hub-promote-no-op-promote-tags-and-breaks-rollback.md` — read, different root cause
**Approval:** pending

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

## Decision needed

Should a rollback return to the state live before the last promote (the tag's `old:`, which keeps X), or to the
previous promotion (today)? The confirmation fix (list `new..old` as "will be removed") is needed either way.
