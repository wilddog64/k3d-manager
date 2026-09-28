# Bug: `bin/k3dm-cloud-request` fails on a fresh clone and can file only 4 of the bridge's 13 actions

**Branch:** `k3d-manager-v1.40.0`
**Filed:** 2026-09-28 by Claude (cloud session), found while verifying the bridge end to end
**Status:** FIXED
**Component:** `bin/k3dm-cloud-request` (the cloud-side helper). The bridge itself is not at fault.

Two independent defects in the same file. Both make the helper fail for a cloud session, which is
the helper's only audience.

## Codex brief

**Goal:** a fresh cloud clone can file every bridge action through `bin/k3dm-cloud-request`, with no
manual `git fetch` first, and the helper's action list can never drift from the bridge's again.

**Runs where:** Codex web is fine. Pure code and offline tests; nothing needs the M4, a cluster, the
webhook, or the real `cloud-requests` branch. Test 1 uses a local bare repo in `tmp_path`, never
`origin` on GitHub.

**Decision already made (shape 1):** create `scripts/lib/webhook/cloud_actions.py` holding
`JOB_ID_RE`, `NS_RE`, `Q_RE` and `ACTION_ALLOWLIST`, moved verbatim from `bin/k3dm-cloud-bridge`.
It imports only `re` (`scripts/lib/webhook/__init__.py` is empty, so importing it pulls in no
`webhook.auth`). The bridge imports those four names from it so `bridge.ACTION_ALLOWLIST` and the
regexes still resolve for existing tests. The helper derives its argparse `choices` and per-action
arg names from `ACTION_ALLOWLIST` and validates each value with that action's regex; delete
`ACTION_ARGS` and the helper's own `JOB_ID_RE`.

**Files to touch (only these):**
- `scripts/lib/webhook/cloud_actions.py` (new)
- `bin/k3dm-cloud-bridge` (import the table instead of defining it)
- `bin/k3dm-cloud-request` (fetch in `_commit_request`; table-driven args)
- `scripts/tests/bin/test_cloud_bridge.py` (tests 1 to 3 below)
- `docs/howto/cloud-session-requests.md`, `CLAUDE.md` (the "Docs" section below)
- `CHANGELOG.md` (one `### Fixed` bullet under `## [Unreleased]`)
- `memory-bank/activeContext.md`, `memory-bank/progress.md` (SHA and status)
- this bug doc (set **Status** to FIXED with the SHA)

**Defect 1 detail:** in `_commit_request`, first `_git(["fetch", "origin", FETCH_REFSPEC], timeout=120)`,
then resolve the parent with `git rev-parse --verify --quiet refs/remotes/origin/cloud-requests`.
The fetch of a missing remote branch fails, so treat "remote has no `cloud-requests`" (check with
the existing `ls-remote` call, done before the fetch) as the empty-tree path, exactly as today.
Keep `--force-with-lease` against that parent.

**Gates (paste the output of each):**
- `python3 -m py_compile bin/k3dm-cloud-request bin/k3dm-cloud-bridge scripts/lib/webhook/cloud_actions.py`
- `make test-pytest` green (summary pasted). Invoke via make, not bare pytest.
- `command grep -c 'ACTION_ARGS' bin/k3dm-cloud-request` → `0`
- `command grep -c '^ACTION_ALLOWLIST = ' bin/k3dm-cloud-bridge` → `0`
- `python3 -c "import sys; sys.path.insert(0,'scripts/lib'); import webhook.cloud_actions; print('webhook.auth' in sys.modules)"` → `False`
- The three mutations in "Mutations" below, each shown red, then the tree restored and green again.
- `git diff --stat` lists only the files above.

**Do not change:**
- The bridge's validation logic, its `FETCH_REFSPEC`, or any regex's pattern text (the existing
  `test_make_action_argument_patterns_match_webhook_patterns` pins them to `make_targets`).
- The helper's exit codes (2 bad args, 3 rejected, 4 error, 5 timeout) or the request JSON schema.
- `.claude/settings.json`, `scripts/lib/foundation/`, `scripts/lib/acg/`.
- Do not add the four actions from `v1.40.0-cloud-bridge-test-targets.md` M4. That spec adds them
  to the bridge table later, and after this fix the helper picks them up for free.
- Do not run `kubectl`, the bridge's poll loop, `make install-cloud-bridge`, or `make down`, and do
  not push to the real `cloud-requests` branch.

**Commit and hand back:** one commit on `k3d-manager-v1.40.0`, message
`fix(cloud-request): fetch before filing and derive actions from the bridge allowlist`.
No PR, no merge, no force-push, no `--no-verify`.

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
