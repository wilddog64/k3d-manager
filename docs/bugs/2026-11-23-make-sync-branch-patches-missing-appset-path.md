# Bug: `make sync-branch` / `make sync-main` JSON-patch a path that no longer exists in `services-git`

**Status:** OPEN
**Priority:** P3 — hygiene: a dev convenience target fails; the ApplicationSet can still be re-pointed by redeploying it
**Introduced by:** `0c9b2707` (v1.7.1, the services-git generator became a matrix); the patch path dates from `c5949cf4` (v1.4.12)
**Should have been caught by:** offline test (no test exercises either target)
**Introducing change reviewed:** unknown
**Waiting on:** fix running — since 2026-11-24 (R1 landed `5f7ef7be` 2026-11-23, unblocking it)
**Triage:** patch → v1.45.1 (operator, 2026-11-23)
**Intent approved:** operator, 2026-11-23
**Prior art:** Pass 1 `ls docs/bugs/*-make-sync-branch-patches-missing-appset-path.md`: none; `make find-similar-docs` not run (vector store unavailable); found while writing R1, [`2026-11-23-cve-pins-branch-trusted-without-verification.md`](2026-11-23-cve-pins-branch-trusted-without-verification.md) "Not readers" — read, same finding, this doc is its P3 capture
**Filed:** 2026-11-23
**Detected by:** Claude, R1 spec contract-reader grep, 2026-11-23

## What is wrong

- `Makefile:493` (`sync-branch`) and `Makefile:505` (`sync-main`) both send an RFC 6902 `replace` on
  `/spec/generators/0/git/revision`.
- `scripts/etc/argocd/applicationsets/services-git.yaml:11-18` today: `generators[0]` is `matrix` → `matrix` → `git`, so
  `generators/0` has no `git` key. A JSON-patch `replace` on a missing path fails, and the target stops before its refresh
  loop (verified by reading the template, 2026-11-23; not run live).
- The refresh loop (`:495-498`, `:507-510`) annotates bare `shopping-cart-*` Application names. The appset now names them
  `'{{.name}}-{{.path.basename}}'` (`services-git.yaml:41`), so those annotations would miss even if the patch worked
  (`|| true` hides it).
- R1 changes the generator tree again ("After R3 it is `clusters`", R1 spec `:268`), so any fixed index rots.

## Fix

Stop hard-coding the index. Either find the `git` generator whose `directories` include `services/*` in the live object
(`kubectl get applicationset services-git -o json` + `jq` path search) and patch that path, or re-render the template with
`K3D_MANAGER_BRANCH=$(BRANCH)` and apply it through the existing deploy path. Refresh the Applications by label or by the
appset's owner reference instead of a hard-coded name list. Add a test.

## Files

| File | Change |
|---|---|
| `Makefile` | `sync-branch` and `sync-main` only: patch path found by content, refresh by the appset's generated Applications |
| `scripts/tests/bin/make_sync_branch.bats` | new: E1, with a kubectl stub and the rendered-template fixtures (see Clarification) |

Read only: `scripts/etc/argocd/applicationsets/services-git.yaml`.

## Acceptance

```yaml
must:
  - id: M1
    text: the JSON-patch path (or rendered manifest) sync-branch and sync-main send resolves to the services/* git generator's revision in the current services-git.yaml
  - id: M2
    text: the refresh step targets the Applications the appset actually generates (cluster-prefixed names), not a fixed shopping-cart-* list
must_not:
  - id: N1
    text: sync-branch must not send /spec/generators/0/git/revision
    red_on_current: Makefile:493 and :505 send exactly that path
evidence:
  - id: E1
    proves: [M1, M2, N1]
    kind: offline
    command: bats test with a kubectl stub (captured services-git object, host and date in a comment) that records the patch body and applies it with a JSON-patch tool to the rendered template; asserts the patched revision equals BRANCH and the annotate calls name cluster-prefixed Applications
    red_control: on current Makefile the recorded path is /spec/generators/0/git/revision and applying it to the rendered template fails
    intent: Running make sync-branch actually points the shopping-cart apps at the chosen branch and refreshes them, instead of failing silently.
```

## Clarification (Claude, 2026-11-24, before dispatch)

- R1 landed (`5f7ef7be`): `services-git.yaml` is now `matrix` → [`clusters`, `matrix` → [`git`, `git`]]. Line numbers above
  have moved (`sync-branch` is at `Makefile:488`, `sync-main` at `:501`); find the targets by name.
- The hub still runs v1.45.0's ApplicationSet until a promote, so a live capture would show the old tree. E1's stub object
  is therefore the **rendered template from this branch** (`envsubst` over `services-git.yaml` with the variables the
  deploy path sets; record the commit and date in a comment), not a hub capture. Claude captures the live object after the
  promote as a live follow-up.
- Pick the generator by content (the `git` generator whose `directories` include `services/*`), never by index, so the
  test must also pass against a second fixture with the two `git` generators swapped.

## Routing

Luna (Makefile logic + one bats file). **Waits for R1:** the correct path depends on the generator tree R1 leaves in
`scripts/etc/argocd/applicationsets/services-git.yaml`, a file R1's running dispatch owns. Dispatch after R1 lands.
