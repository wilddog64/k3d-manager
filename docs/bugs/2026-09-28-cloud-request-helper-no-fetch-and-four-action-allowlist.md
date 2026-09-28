# Bug: `bin/k3dm-cloud-request` fails on a fresh clone and can file only 4 of the bridge's 13 actions

**Branch:** `k3d-manager-v1.40.0`
**Filed:** 2026-09-28 by Claude (cloud session), found while verifying the bridge end to end
**Status:** OPEN
**Component:** `bin/k3dm-cloud-request` (the cloud-side helper). The bridge itself is not at fault.

Two independent defects in the same file. Both make the helper fail for a cloud session, which is
the helper's only audience.

## Defect 1 — the helper commits on top of a parent it never fetched

`_commit_request` reads the remote tip with `git ls-remote origin refs/heads/cloud-requests` and then
runs `git read-tree <that sha>`. `ls-remote` returns only the SHA; it downloads no objects. On a
fresh cloud clone the `cloud-requests` commit is not in the object store, so `read-tree` fails:

```
$ bin/k3dm-cloud-request --wait --timeout 240 cluster-status
fatal: failed to unpack tree object 2250750c2a3b9b315d09574d2ac52b5a5b80bb12
exit=4
```

Reproduced 2026-09-28 in a fresh cloud session on `main` (`3a25448`). After
`git fetch origin "+refs/heads/cloud-requests:refs/remotes/origin/cloud-requests"` the same command
filed `20260928T001624Z-cluster-status` and got HTTP 202 back.

The howto does say to fetch first ("`git fetch origin cloud-requests`"), so this is a documented
precondition rather than a hidden one. It is still a bug:

- Exit 4 is the code the helper documents for a **response** with `status: error`. A session reads
  it as "the bridge answered with an error", not "your clone is missing an object".
- The `--wait` path already fetches with the correct explicit refspec (`FETCH_REFSPEC`). Filing is
  the one step that does not.
- Any delay between the session's fetch and the file makes the lease stale anyway, so the helper has
  to own the fetch to be correct, not the caller.

### Fix

At the start of `_commit_request`, run `git fetch origin FETCH_REFSPEC` (the same explicit
`+refs/heads/cloud-requests:refs/remotes/origin/cloud-requests` refspec `--wait` uses, for the reason
the howto gives), then take the parent from `refs/remotes/origin/cloud-requests` rather than from
`ls-remote`. Keep the `--force-with-lease` against that parent. If the branch does not exist
remotely, keep today's empty-tree behaviour.

## Defect 2 — the helper's allowlist is 4 actions; the bridge's is 13

```python
# bin/k3dm-cloud-request
ACTION_ARGS = {"health": set(), "cluster-status": set(), "hostinger-status": set(),
               "job-status": {"job_id"}}
```

`bin/k3dm-cloud-bridge`'s `ACTION_ALLOWLIST` carries thirteen: those four plus `make-fix-list`,
`make-fix-status` (`NS`), `make-status-public`, `make-observability-status`, `make-vuln-scan`,
`make-e2e-runner-health`, `make-test-pytest`, `make-test-python-unit` and `make-find-similar-docs`
(`Q`). The reader-tier make targets were added to the bridge and to the howto's table but not to the
helper, so a cloud session cannot file any of them through the permitted command — `argparse`
rejects the action with exit 2 before anything is written.

The howto contradicts itself on this: its table lists thirteen actions, while its "The helper"
section still says the grant is safe because `argparse` `choices` bound it "to the four actions".
`CLAUDE.md` also still says "Four read-only actions are available".

Filing by hand would work, but `.claude/settings.json` allows only the helper, so in practice a
session is limited to the four.

### Fix

Make the helper's action table follow the bridge's rather than restate it. Two acceptable shapes:

1. Import `ACTION_ALLOWLIST` (and its arg regexes) from the bridge into the helper, so there is one
   list. Loading `bin/k3dm-cloud-bridge` as a module must not import `webhook.auth` side effects on
   the cloud side — factor the table into a small shared module under `scripts/lib/` if needed.
2. Keep two lists, but add a gate that fails when the helper's action set or per-action arg names
   differ from the bridge's.

Either way, validate `NS` and `Q` in the helper with the same regexes the bridge uses, so a bad value
is rejected locally with exit 2 instead of consuming a request id on the bridge.

`v1.40.0-cloud-bridge-test-targets.md` M4 already adds its four new actions to `ACTION_ARGS`; if
shape 1 lands first, that step becomes a no-op.

## Tests

1. Filing from a clone whose object store lacks the `cloud-requests` tip succeeds (stub `git` or use
   a local bare remote with a commit the working clone has not fetched).
2. The helper's accepted action set equals the bridge's `ACTION_ALLOWLIST` keys, and each action's
   accepted `--arg` names equal the bridge's.
3. `make-fix-status --arg NS='bad;ns'` and `make-find-similar-docs --arg Q='$(x)'` exit 2 without
   pushing.

### Mutations

- Remove the new fetch → test 1 red with `failed to unpack tree object`.
- Add an action to the bridge only → test 2 red.
- Drop the `NS` regex check in the helper → test 3 red.

## Docs

Update `docs/howto/cloud-session-requests.md`: drop the "fetch first" instruction (the helper now
does it), and replace "the four actions" in "The helper" section with a reference to the table.
Fix `CLAUDE.md`'s "Four read-only actions are available" the same way. (The artifacts spec, M7, also
asks for the `CLAUDE.md` fix; whichever lands first does it.)

## Out of scope

- Anything in `bin/k3dm-cloud-bridge`'s validation. It rejected nothing it should have accepted.
- The auto-mode classifier note in the howto. This session was in auto mode and the helper ran
  without being refused, so that note may be stale, but one observation is not enough to rewrite it.
