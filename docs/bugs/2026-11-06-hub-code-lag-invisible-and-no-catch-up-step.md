# Bug: the hub's code falls behind silently, and catching up takes several manual steps

**Filed:** 2026-11-06
**Branch:** `k3d-manager-v1.43.14`
**Status:** OPEN
**Waiting on:** fix running — since 2026-11-06
**Priority:** P2 — fixes look missing or broken while they are simply not deployed; a workaround exists (the manual steps)
**Approval:** explicit 2026-11-06 "go ahead to spec this out, and dispatch in an approperate time" (operator, on the timing of hub changes), and "sounds good" (operator, on Hermes reading the newest release branch from origin rather than fetching from the M4 or M2). Dispatch after P0 S1 lands, because both edit the `Makefile`.
**Severity:** medium
**Related:** `docs/bugs/2026-10-31-ask-docs-bug-count-reads-stale-checkout-head.md` (same lag, for the Slack bug count)

## Symptom

2026-11-06: the `Waiting on` columns did not appear after that fix landed and was pushed. The M5 checkout was 58 commits behind `origin/k3d-manager-v1.43.14`, and `bin/k3dm-vectordb-metrics` there did not yet produce those labels. Nothing on any dashboard said so. Claude also misdiagnosed it, telling the operator that doc text waited on the same pull.

The precedent in `CLAUDE.md`: v1.43.2's e2e abort fix sat undeployed until `make platform-ops`, and a v1.43.13 dashboard fix stayed invisible after it because an ApplicationSet read an older branch.

## Root cause

Changes reach the hub by three routes at three speeds:

| Change | Route | Delay |
|---|---|---|
| Bug and plan doc text | Hermes fetches `origin/<branch>` and reads the ref | about 5 minutes |
| `bin/`, `scripts/` run on the host | The M5 checkout, moved by hand | until someone pulls |
| Dashboards, CronJobs | ArgoCD at the ApplicationSet's branch, or `make platform-ops` | until synced |

1. `_refresh_index` in `bin/k3dm-hermes` already fetches every cycle, but nothing publishes how far `HEAD` is from that ref.
2. Hermes reads docs only from the branch the checkout tracks. After a new release branch is pushed, the hub keeps reading the old one until its checkout is switched, so new docs are missing from the table and the index with nothing saying why.
3. Catching up is a pull, restarts of the webhook and Hermes, `make platform-ops`, `make appsets-check` and sometimes `make machine-setup`. Which of them apply depends on the files changed, and nothing says so.

The checkout must not pull by itself. Agents push to the release branch throughout the day, and Hermes and the webhook hold credentials, so an automatic pull would run unreviewed code on the hub. Deciding when remains the operator's.

## Fix

### 0. Read docs from the newest release: `bin/k3dm-hermes`

In `_refresh_index`, after `fetch_env` is built and before the fetch, when `K3DM_INDEX_REF` is unset, call a new `_newest_release_branch(current, env)`:

- Run `git ls-remote --heads origin 'k3d-manager-v*'`, timeout 60s, with `fetch_env`.
- Keep only names matching `^k3d-manager-v[0-9]+\.[0-9]+\.[0-9]+$`, and compare versions as numbers, so `v1.43.100` beats `v1.43.14`.
- Return the highest if it is newer than `current`. Otherwise, or if `current` does not match that pattern, the command fails, or nothing matches, return `current`. Never go to a lower version.

Use the result as the branch, with ref `origin/<branch>`, and fetch it with the explicit refspec `+refs/heads/<branch>:refs/remotes/origin/<branch>`. Do not touch `HEAD` or the working tree. An explicit `K3DM_INDEX_REF` still wins, as today.

Known limit: pushing a higher release branch while an earlier one is still open moves the table to it. `CLAUDE.md` already cuts a patch branch only after its parent merges, and the tile names the branch being read. `scripts/lib/webhook/bug_count.py` keeps reading `@{upstream}`; do not change it here.

### 1. Publish the lag: `bin/k3dm-hermes`

In `_refresh_index`, directly after the fetch succeeds and before the pause check, call a new `_push_checkout_lag(upstream_ref, upstream_branch, newest_branch)`, which catches its own exceptions and never fails the index refresh. It runs in `ROOT`:

`git rev-list --count HEAD..<upstream_ref> -- . ':!docs' ':!memory-bank' ':!CHANGELOG.md'`

and POSTs to `$K3DM_VECTORDB_PUSHGATEWAY_URL/metrics/job/k3dm-hub-checkout`, the same base URL and default as `_push_index_metrics`:

```
k3dm_hub_checkout_code_commits_behind{branch="<branch>"} <count>
k3dm_hub_checkout_on_newest_release{newest_branch="<newest_branch>"} <1 if upstream_branch equals newest_branch, else 0>
k3dm_hub_checkout_last_check_timestamp_seconds <now>
```

The count is against the checkout's own upstream, not the newest branch: releases are squash-merged, so a count across two release branches means nothing.

Docs are excluded because they do not need a pull, so counting them would raise a false alarm. If git fails, publish nothing: the timestamp ages and the tile below goes to `unknown`.

`<upstream_ref>` and `<upstream_branch>` come from `_index_ref`. Export each branch name only if it matches `^[A-Za-z0-9._/-]{1,100}$`; otherwise publish nothing.

### 2. Show it: `scripts/etc/argocd/platform-ops/grafana-dashboard-bugs.yaml`

Add a stat, **Hub code behind**, to the `Release` row. Make room by setting tiles `Release`, `Bugs filed`, `Bugs open` and `Bugs fixed` to `w: 3` at x 0, 3, 6, 9, `Open, scheduled later` and `Open, untriaged` to `w: 4` at x 12, 16, and the new tile `w: 4` at x 20, y 1, h 4.

- Query: `k3dm_hub_checkout_code_commits_behind and on() (time() - k3dm_hub_checkout_last_check_timestamp_seconds < 900)`
- Legend `{{branch}}`. `noValue`: `unknown`. Thresholds: green at 0, orange at 1.
- Second target, refId B: `k3dm_hub_checkout_on_newest_release and on() (time() - k3dm_hub_checkout_last_check_timestamp_seconds < 900)`, legend `{{newest_branch}}`. A field override for B maps 1 to `current release` and 0 to `older release`, green and orange.
- Description: "Commits with code changes on the hub's branch that the hub's checkout has not pulled. Doc text does not need a pull: it appears within about 5 minutes. If a fix is not showing, run make hub-sync in a shell on the hub. The count is for the branch the hub is on. If the second value says older release, run make hub-sync BRANCH=<the branch it names>."

No alert. No other panel changes.

### 3. Catch up in one step: `bin/k3dm-hub-sync` and `make hub-sync`

New `bash` script, `set -euo pipefail`, resolving the repo from its own location. `make hub-sync` runs it with `BRANCH=` when set. No other arguments. Run from the operator's shell on the hub, because `make platform-ops` reads the login Keychain.

In this order, and a refusal changes nothing:

1. `bin/k3dm-require-role hub`, or exit 1.
2. Refuse, exit 1, if `git status --porcelain` prints anything.
3. Target is `BRANCH`, else the current branch. Refuse, exit 2, unless it matches `^k3d-manager-v[0-9]+\.[0-9]+\.[0-9]+$`.
4. Refuse, exit 1, naming the job id, if any `<job dir>/*/status` holds `queued` or `running` and was modified in the last 3 hours. Job dir: `K3DM_JOB_DIR`, else `~/.local/share/k3d-manager/webhook-jobs`. This is because the restart must not disturb a running cluster job.
5. `git fetch origin "+refs/heads/<target>:refs/remotes/origin/<target>"`. Exit 1 on failure.
6. Switch to the target if it is not current, then `git merge --ff-only origin/<target>`. Refuse, exit 1, when that is not a fast-forward. Never reset, stash or force.
7. Compute the changed files between the old and new `HEAD`. If `HEAD` did not change, skip steps 8 to 10.
8. If any changed file is outside `docs/`, `memory-bank/` and `CHANGELOG.md`: `make restart-webhook`, then `launchctl kickstart -k gui/<uid>/com.k3d-manager.hermes`.
9. If any changed file is under `scripts/etc/argocd/platform-ops/`: `make platform-ops`. Otherwise print that it was skipped and why.
10. If any changed file is under `scripts/etc/launchd/`, or is `bin/k3dm-machine-setup`: print `make machine-setup ROLE=hub` as needed. Do not run it.
11. If `git ls-remote` shows a release branch newer than the target, print `make hub-sync BRANCH=<newest>` as needed. Do not switch to it. A failed lookup prints nothing and does not abort.
12. Always `make appsets-check`. A non-zero result does not abort. Print `make appsets-reapply` as needed, and do not run it: that rollout is staged and soaks.
13. Print a summary: old and new short SHA, commits pulled, each step as `ran`, `skipped` or `needed`, and `previous HEAD <sha>`.

A failing step in 8 or 9 exits non-zero, naming the step. The checkout stays advanced and the summary says so.

### 4. Docs

- `docs/howto/hub-sync.md` (new): the routes table above, what the tile means, when to run it, and that the first run after this lands needs a manual `git pull --ff-only` on the M5, because the script is not there yet.
- `CHANGELOG.md` `[Unreleased]`: one bullet at the end of the existing bullets. Do not add a heading.

Claude, not the worker, updates `CLAUDE.md` afterwards.

## Files

- `bin/k3dm-hermes`
- `bin/k3dm-hub-sync`
- `Makefile`
- `scripts/etc/argocd/platform-ops/grafana-dashboard-bugs.yaml`
- `scripts/tests/bin/hub_sync.bats`
- `scripts/tests/bin/test_hermes_checkout_lag.py`
- `scripts/tests/plugins/grafana_dashboard_bugs.bats`
- `docs/howto/hub-sync.md`
- `CHANGELOG.md`

## Tests

Use a scratch origin and clone, a scratch `HOME` and role file, a scratch `K3DM_JOB_DIR`, and stubs for `launchctl` and `make` that log their arguments. First assert the script under test resolved the scratch repo, not the real tree. For Python, set the Pushgateway to a local stub and assert the target before asserting the body.

The `launchctl` and `make` stubs only log their arguments and exit 0 or as a test sets. They imitate no tool output, so nothing here needs a captured sample.

Gates: `bats scripts/tests/bin/hub_sync.bats scripts/tests/plugins/grafana_dashboard_bugs.bats`, `pytest scripts/tests/bin/test_hermes_checkout_lag.py scripts/tests/bin/test_retrieval_probe.py`.

If an existing test pins a Release-row `gridPos` or width, stop and report it. Do not remove an assertion.

## What NOT to Do

- Do NOT pull automatically from Hermes, the webhook, launchd or a schedule.
- Do NOT reset, stash, force or discard anything in the checkout.
- Do NOT run `make appsets-reapply` or `make machine-setup` from the script.
- Do NOT add an alert or Slack post.
- Do NOT add a git remote or SSH access to any other machine. Hermes reads from `origin` only.
- Do NOT run anything against the real hub, or call the real `launchctl`.
- Do NOT commit, push or create a PR. Claude reviews and commits.
- Do NOT modify files outside the Files list.

## Acceptance

```yaml
interface:
  - "make hub-sync [BRANCH=<branch>], and bin/k3dm-hub-sync, in a git clone of a scratch origin; exit code, stdout, and the arguments reaching stubbed make and launchctl"
  - "K3DM_JOB_DIR and XDG_CONFIG_HOME/k3d-manager/machine-role"
  - "bin/k3dm-hermes: _newest_release_branch(current, env), _push_checkout_lag(upstream_ref, upstream_branch, newest_branch) and _refresh_index(state, now); K3DM_VECTORDB_PUSHGATEWAY_URL"
  - "scripts/etc/argocd/platform-ops/grafana-dashboard-bugs.yaml: panel titled Hub code behind and the Release row"
must:
  - id: M1
    text: "With a clean clone behind origin by a code commit, hub-sync fast-forwards to origin, runs make restart-webhook and kickstarts com.k3d-manager.hermes, and prints the old and new SHA."
  - id: M2
    text: "A range touching scripts/etc/argocd/platform-ops/ runs make platform-ops. A range touching scripts/etc/launchd/ prints make machine-setup ROLE=hub as needed."
  - id: M3
    text: "make appsets-check always runs, including when nothing was pulled, and its failure does not stop the summary."
  - id: M4
    text: "BRANCH= switches to that release branch before the fast-forward."
  - id: M5
    text: "_push_checkout_lag publishes the code-commit count with the branch label and a timestamp. Doc-only commits do not count."
  - id: M6
    text: "_refresh_index publishes the lag on a cycle when indexing is paused."
  - id: M8
    text: "With origin holding v1.43.14, v1.43.9 and v1.43.100 and the checkout on v1.43.14, _newest_release_branch returns v1.43.100, and _refresh_index leaves state index_ref at origin/k3d-manager-v1.43.100 with that ref fetched and a doc only on that branch readable from it."
  - id: M9
    text: "On that fixture k3dm_hub_checkout_on_newest_release is 0 with newest_branch v1.43.100, and hub-sync prints make hub-sync BRANCH=k3d-manager-v1.43.100 as needed. On the newest branch it is 1."
  - id: M7
    text: "The Release row has the seven tiles in the specified positions, none overlapping, and the new query names both series and is guarded by the timestamp."
must_not:
  - id: N1
    text: "A dirty checkout, a non-release target, a wrong role, or a queued or running job younger than 3 hours each exits non-zero and leaves HEAD, the working tree and the stubs' logs unchanged. Paired control: the same fixture with the condition removed syncs."
  - id: N2
    text: "A job in status running older than 3 hours, or in status success, does not refuse. Paired control: a fresh running job does."
  - id: N3
    text: "A diverged checkout is refused, and HEAD and unmerged local commits survive. Paired control: a fast-forwardable one succeeds."
  - id: N4
    text: "A doc-only range restarts nothing and does not run platform-ops. Paired control: a code commit restarts both."
  - id: N5
    text: "hub-sync never runs make appsets-reapply or make machine-setup, in any scenario. Paired control: both are named in the output when needed."
  - id: N6
    text: "A failed git command or an unreachable Pushgateway in _push_checkout_lag does not raise, and _refresh_index's own result and metrics are unchanged; with git failing nothing is published. Paired control: with git working the lag is published."
  - id: N7
    text: "A branch value failing the pattern, such as one containing a quote, never reaches a label. Paired control: a release branch does."
  - id: N8
    text: "Nothing in bin/k3dm-hermes changes HEAD or the working tree: after _refresh_index a behind checkout stays behind, and the count says so."
  - id: N9
    text: "Never a lower or unparseable branch: with only older or non-release names on origin, or ls-remote failing, the current branch stays. Paired control: M8's fixture moves up."
  - id: N10
    text: "An explicit K3DM_INDEX_REF is not overridden and no ls-remote runs. Paired control: with it unset, the newest branch is used."
  - id: N11
    text: "hub-sync with no BRANCH never switches to a newer release by itself. Paired control: with BRANCH set it does."
evidence:
  - id: E1
    proves: [M1, M2, M3, M4, M5, M6, M7, M8, M9, N1, N2, N3, N4, N5, N6, N7, N8, N9, N10, N11]
    kind: offline
    what: "The Tests gates on the task branch, run by Claude."
  - id: E2
    proves: [M1, M2, M3, M4, M5, M6, M8, M9, N1, N2, N3, N4, N5, N6, N7, N8, N9, N10, N11]
    kind: offline
    what: "Independent verifier's tests, written from this block only, pass on the fix and are red on its parent where new. Mutants, each red: --ff-only removed; dirty check removed; job check removed; doc-path exclusion removed from the count; doc-only restart guard removed; lag call moved after the pause check; version compared as text; lower branch allowed."
  - id: E3
    proves: [M5, M7, M8]
    kind: live
    what: "Claude: after the M5 pull and a dashboard sync, Prometheus returns the series, its value equals git rev-list run on the M5 at the same HEAD and ref, and the operator sees the tile. When the next release branch is pushed, its docs reach the table within two cycles with the M5 checkout unmoved."
  - id: E4
    proves: [M1, M3]
    kind: live
    what: "Operator: make hub-sync on the M5 in tmux with a real code commit behind; the webhook and Hermes restart, the summary is right, and the tile returns to 0 within two cycles."
```
