# Slack messages expose the operator's home directory path

**Status:** LANDED — stall-watch notice fixed (d2a72d35); webhook cluster excerpts and both make-job posts now show `~/` and scrub secrets (`ce4c06fa`, Luna); not yet live on the hub
**Priority:** P3
**Introduced by:** pre-existing (stall-watch notice since the dispatch stall detector, v1.44.1)
**Should have been caught by:** review
**Introducing change reviewed:** unknown
**Waiting on:** live check — since 2026-11-18 (needs promote of `ce4c06fa` + webhook restart, then a failed job's Slack post shows `~/`)
**Fix commit:** `ce4c06fa`
**Prior art:** not run (vector store unreachable: context `k3d-k3d-cluster` does not exist; exact-slug glob found none)

## Report

Operator, 2026-11-17 (Slack screenshot, 19:16): "message sent to slack should not expose user info. use ~/ in stead".
The stall notice read `evidence /Users/<user>/.local/share/k3d-manager/worktrees/v1.44.1/e8-toy-stall.run/stall-…`.

## Done

`bin/k3dm-dispatch-stall-watch` `_watch_capture` writes the evidence path with `$HOME` replaced by `~` (bash 3.2 and 5
checked). Test `S1` in `scripts/tests/bin/dispatch_stall_watch.bats` fails on the old code and passes now.

## Open

Other Slack senders were not audited: `bin/k3dm-hermes`, `bin/k3dm-slack-notify`, `bin/k3dm-webhook`, `bin/k3dm-sandbox-reaper`,
`scripts/lib/webhook/render.py` and the rest of `scripts/lib/webhook/`. Option: one filter in the shared send path
(`k3dm-slack-notify` and the webhook's post helper) that replaces `$HOME` with `~` in every message.

## Live observation (2026-11-17)

A real stall notice at 10:21 PST (18:21Z, slug `vault-unseal-secret-follows-keychain-restore`, 48 min after d2a72d35 landed at 09:33 PST) read `evidence ~/.local/share/k3d-manager/worktrees/v1.44.2/vault-unseal-secret-follows-keychain-restore.run/stall-20261117T182150Z`: the stall-watch part works live (operator screenshot, 2026-11-18). The other Slack senders are still unaudited, so the doc stays OPEN.

## Audit of other Slack senders (Claude, 2026-11-18, read-only)

Senders found by grep (`chat.postMessage`, `hooks.slack.com`, `k3dm-slack-notify`, Slack helpers): webhook
(`scripts/lib/webhook/{render,status,agent,lifecycle}.py`), Hermes (`scripts/lib/hermes/slack.py`), `k3dm-slack-notify` callers
(stall-watch, `bin/k3dm-sandbox-reaper`), in-cluster `acg-expiry.sh` and Alertmanager (`scripts/plugins/observability.sh`).

**Leak found — webhook cluster jobs post Python tracebacks.** `scripts/lib/webhook/lifecycle.py:428-429` (cluster up/down) and
`:518` (cluster-resume) write `ERROR: {exc}\n{traceback.format_exc()}` into the job `output`; `_finish("failed")` then posts
`_cluster_output_excerpt` (last 12 lines, `:107-113`) to Slack. The excerpt goes through `_sanitize_cluster_output`
(`:99-104`), which scrubs registered secrets, credential shapes, env values and Slack URLs, but not `$HOME`. Hub evidence
(work:1.0, counts and `~`-substituted lines only): 4 of 18 webhook job dirs hold the home path, all `output` of `up` jobs
(2026-11-10, 2026-11-11); in 3 of them the line is inside the last 12 lines, as
`File "~/src/gitrepo/personal/k3d-manager/scripts/lib/webhook/lifecycle.py", line 415, in _run_cluster`. So it was very likely posted.
`delivery.jsonl` holds metadata only, so it cannot confirm.

**Same class, not scrubbed at all:** `make` job progress (`lifecycle.py:171`) and result (`:205`, posted `:225`) tails skip even
`_sanitize_cluster_output`. No home path in current hub job logs, but any traceback or absolute path in `make` output would pass.

**Clean:** sandbox-reaper (bare `sandbox-reaper.log`, cluster names); `agent.py` filed-bug paths are `relative_to(REPO_ROOT)`;
Hermes card text (home paths only used internally; `{exc}` strings go to stderr/CLI). Indirect: `agent.py:387` puts absolute
`REPO_ROOT` into the agent prompt, so an agent reply could echo it. Borderline: `bin/k3dm-hermes:600` `{exc}` from a failed exec.

**Fix direction (not decided):** one `_tildify_home()` in `scripts/lib/webhook/redact.py`, applied inside
`_sanitize_cluster_output` and to the `make` tails at `:171`/`:205` (which should also go through the sanitizer for secrets).
Test: a traceback line with the real `$HOME` in `output` -> posted excerpt has `~/`, positive control that a non-home path is kept.

## Fix landed (2026-11-18)

`ce4c06fa` (spec `docs/plans/webhook-slack-home-path-scrub.md`, Luna gpt-6-luna). Claude verified: diff matches the
four Fix items; 38/38 in the two suites; in a scratch worktree with the old lib, tests 1–5 all red (test 3 run by
name: the spec's E1 `-k` missed it, fixed in `a13d173c`); mutations re-run by Claude: `:205` unsanitized → test 4 red,
no lookbehind → test 2 red. Land gate (4 webhook suites) green. Live: after promote + webhook restart.
