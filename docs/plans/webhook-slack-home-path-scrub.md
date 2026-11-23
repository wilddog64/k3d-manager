# Plan: webhook Slack posts show `~/` instead of the operator's home directory (P3)

**Filed:** 2026-11-18
**Branch:** `k3d-manager-v1.45.0`
**Status:** ready for dispatch
**Covers:** the "Audit of other Slack senders" leak in `docs/bugs/2026-11-17-slack-messages-expose-home-directory-path.md`
(stall-watch part already fixed in d2a72d35).
**Risk:** low (text scrubbing of two webhook Slack posts; one new pure helper; tests)
**Reviewed:** Claude only (low risk, P3; the leak path was confirmed live on the hub, read-only)
**Agent:** Luna (Codex)

## Problem

When a webhook cluster job fails, `scripts/lib/webhook/lifecycle.py:428-429` (cluster up/down) and `:518` (cluster-resume)
append `ERROR: {exc}\n{traceback.format_exc()}` to the job `output`. `_finish("failed")` then posts
`_cluster_output_excerpt` (last 12 lines, `:107-115`) to Slack. That excerpt goes through `_sanitize_cluster_output`
(`:99-104`), which scrubs secrets but not `$HOME`, so traceback frames like
`File "/Users/<operator>/src/gitrepo/personal/k3d-manager/scripts/lib/webhook/lifecycle.py", line 415` reach Slack.
Hub evidence (Claude, 2026-11-18, read-only, pane work:1.0): 3 of 4 `up` job outputs from 2026-11-10/11 had that line
inside the posted 12 lines.

Separately, `_run_make_target` posts two tails with no scrubbing at all: the progress post (`:171-172`) and the result
post (`:205`, posted at `:225`). Neither goes through `_sanitize_cluster_output`, so a secret or a home path in `make`
output is posted as-is.

## Before You Start

1. Read `memory-bank/activeContext.md` and the bug doc above.
2. `git pull` on `k3d-manager-v1.45.0`.
3. Read `scripts/lib/webhook/redact.py` in full, `scripts/lib/webhook/lifecycle.py` lines 1-130 and 150-230, and
   `scripts/tests/bin/test_make_job_output.py` and `scripts/tests/bin/test_redact.py` in full before editing.

## Fix

1. **`scripts/lib/webhook/redact.py`:** add `tildify_home(text)`. It reads `os.environ.get("HOME", "")` **at call time**
   (not at import), strips one trailing `/`, and returns `text` unchanged when `text` is not a non-empty `str` or the
   home value is empty or `/`. Otherwise it replaces every occurrence of the home path with `~` when that occurrence is
   (a) not preceded by a character in `[A-Za-z0-9_./-]` and (b) followed by `/`, end of text, or a character that is not
   in `[A-Za-z0-9_.-]`. Use `re.escape` on the home value. Do not change `scrub_credentials` or `mask_env_values`.
2. **`scripts/lib/webhook/lifecycle.py` `_sanitize_cluster_output`:** apply `tildify_home` as the last step (after the
   Slack URL substitution). Update the import on line 17.
3. **`_run_make_target` progress post (`:171`):** the tail becomes
   `_sanitize_cluster_output("\n".join(_read_job_tail(log_file)), _redact_secrets) or "—"`.
4. **`_run_make_target` result post (`:205`):** sanitize the 40-line tail with `_sanitize_cluster_output(..., _redact_secrets)`
   *before* the `[-3000:]` cut, so the length cap still applies to what is posted. Only the posted text changes: the
   `output` variable (used for the `test-all` metrics check at `:215`) and `make.log` stay raw.

## Files

| File | Change |
|---|---|
| `scripts/lib/webhook/redact.py` | Fix 1 |
| `scripts/lib/webhook/lifecycle.py` | Fix 2-4 |
| `scripts/tests/bin/test_redact.py` | tests 1-2 |
| `scripts/tests/bin/test_make_job_output.py` | tests 3-5 |

## Contract readers

- `_sanitize_cluster_output` — `grep -rn _sanitize_cluster_output bin scripts`: only `scripts/lib/webhook/lifecycle.py:99`
  (definition), `:111` (`_cluster_output_excerpt`) and `:122` (`_cluster_progress_excerpt`). Both callers gain `~/`
  substitution; no other reader.
- `scripts/lib/webhook/redact.py` — readers of `scrub_credentials`: `bin/k3dm-hermes:42,569,972`,
  `bin/k3dm-cloud-bridge:26,456,647`, `scripts/lib/webhook/{ask_docs.py:59,job_output.py:54,status.py:469,failure_notes.py:21,render.py:99,agent.py:475}`.
  None changes: `scrub_credentials` is untouched and `tildify_home` is new (writer: lifecycle.py only).
- `make.log` and job `output` files — unchanged (raw); only the Slack text changes.

## Tests (these names exactly)

Every test that sets `HOME` uses `monkeypatch.setenv("HOME", "/Users/k3dm-fake-home")` and first asserts
`os.environ["HOME"] == "/Users/k3dm-fake-home"` (fixture asserts its target). No test reads the real `$HOME`.

In `scripts/tests/bin/test_redact.py`:

1. `test_tildify_home_replaces_home_prefix` — `File "/Users/k3dm-fake-home/src/x.py", line 4` →
   `File "~/src/x.py", line 4`; `cd /Users/k3dm-fake-home` → `cd ~`; two occurrences on one line are both replaced;
   with `HOME=/Users/k3dm-fake-home/` (trailing slash) the same results.
2. `test_tildify_home_keeps_other_paths` (positive control) — unchanged: `/Users/k3dm-fake-homeother/x`,
   `/tmp/Users/k3dm-fake-home/x`, `/opt/homebrew/bin`, a line with no path; with `HOME` unset, `HOME=""` and `HOME=/`,
   `/Users/k3dm-fake-home/src` is unchanged; `tildify_home(None)` is `None`.

In `scripts/tests/bin/test_make_job_output.py` (reuse the `job` fixture and `_run`; record `_notify_job` texts with a
`monkeypatch.setattr(lifecycle, "_notify_job", ...)` that appends to a list):

3. `test_cluster_output_excerpt_tildifies_traceback` — write an `output` file whose last lines are
   `Traceback (most recent call last):` and `  File "/Users/k3dm-fake-home/src/k3d-manager/scripts/lib/webhook/lifecycle.py", line 415, in _run_cluster`;
   `lifecycle._cluster_output_excerpt(path, lambda t: t)` contains `File "~/src/k3d-manager/` and not
   `/Users/k3dm-fake-home`.
4. `test_make_job_result_post_is_sanitized` — `make.log` output with lines `/Users/k3dm-fake-home/src/x: error` and
   `password=hunter2`, rc 2: the last recorded `_notify_job` text contains `~/src/x: error` and `***REDACTED***`, and
   contains neither `/Users/k3dm-fake-home` nor `hunter2`; `make.log` still holds both raw lines.
5. `test_make_job_progress_post_is_sanitized` — replace `lifecycle.threading.Timer` with a fake whose constructor stores
   the callback and whose `start`/`cancel` do nothing; run `_run` with the same two lines; then call the stored callback.
   The text it posts contains `~/src/x: error` and `***REDACTED***`, and neither `/Users/k3dm-fake-home` nor `hunter2`.

Pre-fix red: 1, 3, 4, 5 fail on the current code (2 also fails today because `tildify_home` does not exist; it is the
positive control). Mutations (each must turn the named test red; apply by hand, run, revert):
read `HOME` once at import time (3, 4); drop the "not preceded by" boundary (2); drop the "followed by" boundary (2);
remove `tildify_home` from `_sanitize_cluster_output` (3, 4, 5); leave the `:205` tail unsanitized (4); leave the `:171`
tail unsanitized (5).

## What NOT to Do

- Do NOT change `scrub_credentials`, `mask_env_values`, `_redact_secrets`, or what is written to `make.log` / `output`.
- Do NOT change the failure-analysis post (`_analyze_failure`), `failure_notes.py`, `agent.py`, Hermes, or
  `bin/k3dm-dispatch-stall-watch`.
- Do NOT change message wording, emoji, job status handling, or the `test-all` metrics check.
- Do NOT touch `docs/`, `CHANGELOG.md` or `memory-bank/`.
- Do NOT commit, push or open a PR. Claude verifies and commits.
- Do NOT skip pre-commit hooks (`--no-verify`).
- Do NOT modify files outside the Files table.

## Rules

- LF line endings only; keep existing indentation, quoting and naming; no unsolicited refactors.
- No test reads the real `$HOME`, calls Slack, or runs a real `make`; stubs only.
- If the spec contradicts the code, stop and say so; do not guess.

## Gates

`pytest scripts/tests/bin/test_redact.py scripts/tests/bin/test_make_job_output.py`, then `make test-pytest`.

## Definition of Done

- [ ] Fix 1-4 implemented; `git status` shows only the four files.
- [ ] Pre-fix red recorded for tests 1, 3, 4, 5.
- [ ] Both gates green.
- [ ] Mutation table: mutation → test → red.
- [ ] Report back to Claude: changed files, test output, mutation table. No commit.

## Acceptance

```yaml
must:
  - id: M1
    text: a failed cluster job's Slack excerpt shows paths under the operator's home as ~/
  - id: M2
    text: both make-job Slack posts (progress and result) go through the same secret and home-path scrubbing as cluster excerpts
  - id: M3
    text: paths outside the home directory, look-alike prefixes, and an unset/empty/root HOME leave text unchanged; make.log and job output stay raw
must_not:
  - id: N1
    text: a traceback line under $HOME is posted to Slack with the full home path — red today
  - id: N2
    text: a make-job Slack post carries a password value or the full home path — red today
evidence:
  - id: E1
    proves: [M1, M2, M3, N1, N2]
    kind: offline
    command: pytest scripts/tests/bin/test_redact.py scripts/tests/bin/test_make_job_output.py -k "tildify or sanitized or tildifies"
    intent: When a cluster or make job fails, the Slack message shows ~/ for your home folder and hides passwords, instead of printing your username and full path.
interface:
  - "scripts/lib/webhook/redact.py: tildify_home(text) -> text"
```

**Intent approved:** operator, 2026-11-18
**Approval words and scope:** "go ahead to open a P3 then dispatch to Luna" (after Claude proposed the `tildify_home`
helper in `redact.py`, applied in `_sanitize_cluster_output` and the two `make` tails, with a test red on today's code).
