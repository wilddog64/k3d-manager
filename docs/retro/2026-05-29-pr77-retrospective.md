# Retrospective — shopping-cart-infra PR #77

**Date:** 2026-05-29
**PR:** #77 — merged to main
**Branch:** fix/remove-legacy-argocd-apps
**Participants:** Claude, Copilot

## What Went Well
- Three focused fixes landed cleanly in a single PR
- Copilot caught three real issues: stale namespace doc ref, RBAC app name mismatch, and ApplicationSet lifecycle bug in argocd-delete
- Rebase correctly dropped 3 commits already squash-merged via PR #76 — clean 2-commit result

## What Went Wrong
- Branch had merge conflict (dirty state) because first 3 commits were squash-merged in PR #76 but left on the feature branch — required rebase before merge
- networking.yaml fix was on a stale docs/next-improvements accumulator branch — should have been put on fix/remove-legacy-argocd-apps directly

## Copilot Findings (PR #77)
| Finding | File | Fix |
|---------|------|-----|
| Stale "namespace" in architecture.md | docs/architecture.md:141 | Removed namespace from platform-level apps list |
| order-admin RBAC referenced old app name `order-service` | argocd/config/argocd-rbac-cm.yaml | Updated to `shopping-cart-order` |
| argocd-delete would be undone by ApplicationSet controller | Makefile:238 | Added ApplicationSet deletion before child app deletion |

## Decisions Made
- networking.yaml fix cherry-picked onto fix/remove-legacy-argocd-apps instead of opening separate PR from docs/next-improvements — avoids stale accumulator branch PR
- docs/next-improvements recreated fresh from merge SHA — old accumulator branch retired

## Theme
Cleanup sprint closing out stale ArgoCD app definitions and a perpetual OutOfSync bug left over from the ApplicationSet migration in v1.4.11. Copilot caught an RBAC stale reference that would have silently broken order-admin access after the ApplicationSet rename.
