# `_vcluster_ensure_exists` proves nothing and exits the shell out of teardown

**Filed:** 2026-09-23
**Status:** FIXED 2026-09-23 — Changes 1-2 implemented, unit-verified and mutation-proven.
**Not yet exercised against the live runner.**
**Found while:** tracing the vCluster leak fixed in `7338a238`.

## Summary

`_vcluster_ensure_exists` (`scripts/plugins/vcluster.sh:290`) has two defects that
compound each other:

1. **The predicate lies.** It returns success as soon as a kubeconfig *file* exists
   on the host. A file is not a virtual cluster. Six stale kubeconfigs currently sit
   in `~/.kube/vclusters/` on the m2 runner — residue of the teardowns that never ran
   before `7338a238` — and every one of them makes this function claim a vCluster
   exists that does not.

2. **Its failure path exits the shell, and its only caller cannot catch that.**
   When the shortcut does *not* fire, "not found" ends in `_err`, which is `exit 1`.

Defect 2 is the same class of failure as `7338a238`: an `exit` where the caller
expects a return code.

## Why defect 2 is live, not theoretical

The call chain:

```
_e2e_exit_trap            e2e.sh:396   _e2e_teardown "..." || true
_e2e_teardown             e2e.sh:405   vcluster_destroy "$name" || _warn "e2e: teardown of ... failed"
vcluster_destroy      vcluster.sh:88   _vcluster_ensure_exists "$name"
_vcluster_ensure_exists vcluster.sh:303/317   _err "vCluster '$name' not found ..."   -> exit 1
```

Neither `|| _warn` nor `|| true` can catch an `exit`. So when the existence check
fails, the shell terminates and **`_e2e_teardown` never reaches lines 411-426** —
the proxy removal, the stale-kubeconfig removal and the per-run log cleanup are all
skipped. Inside the EXIT trap it is worse: the trap dies mid-way, exactly as it did
before `7338a238`.

The kubeconfig shortcut is what usually hides this. It fires whenever the run got
far enough to export a kubeconfig. The uncovered window is a run that fails **during**
`vcluster create`: no kubeconfig was written, the vCluster is absent or half-created,
`vcluster list` does not name it, and teardown exits the shell instead of cleaning up.
`docs/bugs/2026-09-23-e2e-harness-creating-vcluster.md` records failures in precisely
that phase.

## Why no test catches it

`vcluster_destroy: uses the contract-returned CLI path` (`vcluster.bats:131`) passes
**only because of the shortcut**. It touches `${VCLUSTER_KUBECONFIG_DIR}/demo.yaml`
and leaves `VCLUSTER_LIST_OUTPUT` empty, so `_vcluster_ensure_exists` returns at the
`-f` check and the real existence logic is never entered. The one test that does reach
it (`vcluster.bats:113`, `fails on unknown cluster name`) asserts only
`[ "$status" -ne 0 ]`, which an `exit 1` satisfies just as well as a `return 1` — so it
cannot distinguish the defect from correct behaviour.

## Fix plan

### Change 1 — the kubeconfig shortcut goes

`vcluster list` becomes the single source of truth. Delete the `-f "$kubeconfig"`
early return and the now-unused `kubeconfig` local.

### Change 2 — `_err` becomes `_warn` + `return 1`

Both "not found" exits become a warning and a non-zero return. The empty-name guard
stays `_err`: that is a programming error at the call site, not a runtime state, and
no caller is expected to recover from it.

This preserves the public contract (`vcluster_destroy` on a missing cluster still
fails, still says "not found") while letting `_e2e_teardown`'s `|| _warn` do its job,
so the best-effort cleanup at `e2e.sh:411-426` runs.

### Testing requirements

- A test that `vcluster_destroy` **returns** rather than exits on a missing vCluster —
  it must distinguish the two, which `vcluster.bats:113` does not. Assert that a
  statement after the call still executes.
- A test that a stale kubeconfig with no matching vCluster is **not** accepted as proof
  of existence.
- `vcluster.bats:131` must be reseeded via `VCLUSTER_LIST_OUTPUT` rather than relying on
  the shortcut, so it keeps testing what its name claims.
- Mutation-prove each new guard: restore the defect, confirm the test goes red. A new
  test passing is not evidence it can fail.

### Implemented

Changes 1 and 2 landed as written. One consequence surfaced during testing and needed a
third edit: with the shortcut gone, `vcluster_destroy`'s existence check ran *before* the
`DRY_RUN` early return, so a dry run queried `vcluster list` and broke its own
"executes nothing" guarantee (`vcluster.bats:102` caught it). The check now sits after the
dry-run return, matching where `_vcluster_reconcile_namespace` was placed in `vcluster_create`.

Verification: shellcheck clean; 183 BATS pass / 0 fail across `vcluster`, `e2e`,
`e2e_remote`, `e2e_observability`, `e2e_image_prune`. Both new guards mutation-proven —
restoring the kubeconfig shortcut reds exactly the stale-kubeconfig test, restoring `_err`
reds exactly the returns-instead-of-exiting test. `vcluster.sh` restored byte-identical
(`cmp -s`) after each mutation.

### Not in this change

- The six stale kubeconfigs on the runner. Harmless files; once Change 1 lands they no
  longer lie. Sweeping them is a live-host mutation and needs the operator's go.
- `_vcluster_ensure_exists` is not made to distinguish "absent" from "list command
  failed". Both are non-recoverable for a destroy and both now return 1.
