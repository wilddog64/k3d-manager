# Cloud bridge round trip takes up to ~90 s for a request the webhook answers in seconds

**Status:** FIXED — `6fc0bc47` + `819e636a` (MAX_PER_TICK refetch); operator restarted the bridge 2026-10-03 06:18. Live: request→response commit 14 s and 9 s (was 7–31 s), client round trip ~20 s (was up to ~90 s)
**Branch:** `k3d-manager-v1.41.0`
**Filed:** 2026-10-03, Claude (operator asked "how can we improve claude-bridge performance?")

## Symptom

A cloud session's `bin/k3dm-cloud-request --wait <action>` takes 30–90 s for actions the webhook
answers in under a second. The last two requests on `cloud-requests` (bridge repo
`~/.k3d-manager/cloud-bridge/repo.git`):

| Request | Request commit | Response commit | Bridge-side gap |
|---|---|---|---|
| `cluster-status` | 2026-10-01 11:42:30 | 11:42:37 | 7 s |
| `job-status` | 2026-10-01 11:43:15 | 11:43:46 | 31 s |

The gap is pickup wait, not work: a `git fetch` of the branch measured 1.15 s on 2026-10-03, and
the webhook call returns immediately for status actions. The client then adds its own wait.

## Root cause

Three fixed delays, all in code:

1. **Bridge tick is a fixed 60 s sleep** — `bin/k3dm-cloud-bridge` `main()`: `time.sleep(60)`.
   A request waits 30 s on average, 60 s worst case, before it is seen. Each tick also does a full
   `git fetch` even when nothing changed.
2. **Client poll is a fixed 30 s sleep** — `bin/k3dm-cloud-request` `main()`, `--wait` loop:
   `time.sleep(30)`, and it sleeps *before* its first re-fetch. A response that has already landed
   sits unread for up to 30 s. Worst case 1 + 2 ≈ 90 s per round trip.
3. **A redundant re-fetch after every response** — `process_tick()` calls `_fetch(repo)` after each
   `_write_commit()`, although `_write_commit()` has just pushed a known commit. That is an extra
   network round trip per request (commit + push + fetch = three per request).

Out of scope here, and recorded in `docs/plans/v1.41.0-cloud-bridge-e2e-dispatch.md` instead
(they matter mostly for e2e runs): slow actions (`health`) blocking the serial loop for up to
`HTTP_TIMEOUT`, and following a long make job by repeated `job-status` round trips.

## Spec (for Codex)

Target files only:

- `bin/k3dm-cloud-bridge`
- `bin/k3dm-cloud-request`
- `scripts/tests/bin/test_cloud_bridge.py`
- `docs/howto/cloud-session-requests.md`
- `CHANGELOG.md` (`[Unreleased]` → `### Changed`)

### Change 1 — adaptive bridge tick with a cheap change check

In `bin/k3dm-cloud-bridge`:

- Add module constants, overridable by env, validated as positive numbers (fall back to the default
  on a bad value, never crash):
  - `ACTIVE_POLL_SECONDS = 5` (`K3DM_CLOUD_BRIDGE_ACTIVE_POLL`)
  - `IDLE_POLL_SECONDS = 60` (`K3DM_CLOUD_BRIDGE_IDLE_POLL`)
  - `IDLE_AFTER_SECONDS = 600` (`K3DM_CLOUD_BRIDGE_IDLE_AFTER`)
- Add `_remote_tip(repo)`: runs `git ls-remote origin refs/heads/cloud-requests` via `_git(...,
  timeout=30)` and returns the SHA (first field), or `None` when the output is empty.
- `process_tick(repo, root)` gains an optional `last_tip=None` parameter and returns
  `(tip, processed_count)`:
  - call `_remote_tip(repo)` first; if it equals `last_tip` **and** `last_tip` is not `None`,
    return `(last_tip, 0)` without fetching;
  - otherwise do the existing fetch-and-process work, and return the tip that was processed
    (the ref after the last write, see Change 2) and the number of requests processed.
- `main()` keeps `last_tip` and `last_activity = time.monotonic()` across iterations; when a tick
  processes ≥1 request it updates `last_activity`. Sleep `ACTIVE_POLL_SECONDS` while
  `time.monotonic() - last_activity < IDLE_AFTER_SECONDS`, else `IDLE_POLL_SECONDS`. On the
  existing exception path set `last_tip = None` (force a full fetch next tick) and keep sleeping
  per the same rule.
- A remote tip that changed because the bridge itself pushed is fine: the next tick fetches once,
  finds nothing unprocessed, and records the tip.

### Change 2 — no re-fetch after the bridge's own push

`_write_commit()` returns the new `commit` SHA it pushed. In `process_tick()`, replace
`ref = _fetch(repo)` after `_write_commit(...)` with `ref = <returned commit>`. If a cloud session
pushed in between, the next `_write_commit` push fails its `--force-with-lease` check, raises
`RuntimeError`, the tick ends, and the next tick (≤5 s later) refetches — the existing safety
mechanism, unchanged. Keep the per-tick `MAX_PER_TICK` cap.

### Change 3 — client polls fast and checks before sleeping

In `bin/k3dm-cloud-request`:

- Add `--poll-interval SECONDS` (float, default `5`, must be > 0 — reject `<= 0` with
  `parser.error`, same style as `--timeout`).
- In the `--wait` loop, fetch first then read, then sleep `min(poll_interval, remaining)`:
  never sleep past the deadline, and still make one final fetch-and-read at the deadline before
  returning 5.

### Change 4 — docs and changelog

- `docs/howto/cloud-session-requests.md`: replace "every 60 seconds" with the adaptive rule
  (5 s while active, 60 s after 10 idle minutes); replace "poll interval 30s" with the
  `--poll-interval` flag and its 5 s default; update "10 requests per 60-second tick" to
  "10 requests per tick". State that the first request after a long idle period can still wait up
  to 60 s.
- `CHANGELOG.md` `[Unreleased]` → `### Changed`: one prose bullet with the before/after latency.

## Tests (offline — stub `_git` / `_spawn_capture_text`; no network, no real repo)

Add to `scripts/tests/bin/test_cloud_bridge.py`:

1. `process_tick` with `last_tip` equal to the `ls-remote` SHA makes **no** `fetch` call and
   returns `(last_tip, 0)`.
2. `process_tick` with a changed tip fetches exactly once when there is one unprocessed request
   (i.e. no re-fetch after the write) and returns the pushed commit SHA.
3. The sleep-selection helper (factor it out as a pure function, e.g.
   `_next_sleep(now, last_activity)`) returns 5 inside the idle window and 60 after it.
4. Env overrides: a non-numeric or non-positive `K3DM_CLOUD_BRIDGE_ACTIVE_POLL` falls back to 5.
5. Client: `--poll-interval 0` and `--poll-interval -1` are rejected; the `--wait` loop fetches
   before its first sleep and never sleeps past the deadline (stub `time.sleep` and
   `time.monotonic`, assert the recorded sleep durations).

## Gates (paste actual output)

1. `pytest scripts/tests/bin/test_cloud_bridge.py scripts/tests/bin/test_cloud_artifacts.py scripts/tests/bin/test_restart_cloud_bridge.py -q`
   (bare `pytest` — `python3 -m pytest` has no pytest on this machine)
2. `make test-pytest`
3. `python3 scripts/check-doc-links.py`
4. Mutation: restore `ref = _fetch(repo)` after the write → test 2 fails; make `_next_sleep`
   always return 60 → test 3 fails. Restore, show `git diff --stat` lists only the target files.

## Definition of Done

- [ ] Changes 1–4 implemented in the target files only.
- [ ] Gates 1–4 pass, output pasted.
- [ ] Commit message, exactly:

  ```
  perf(cloud-bridge): poll every 5s while active and skip redundant fetches

  Co-Authored-By: Codex <noreply@openai.com>
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  ```
- [ ] `git push origin k3d-manager-v1.41.0`; report `git rev-parse origin/k3d-manager-v1.41.0`.
- [ ] Operator rollout after Claude verifies: `make restart-cloud-bridge` (the bridge loads its code
  once at start).

## What NOT to Do

- Do NOT create a PR, merge, or commit to `main`; do NOT use `--no-verify`.
- Do NOT modify files outside the target list; do NOT edit `memory-bank/` (Claude records it).
- Do NOT change the request schema, the action allowlist, `MAX_PER_TICK`, `REQUEST_TTL_SECONDS`,
  the reader-token handling, or the `--force-with-lease` push.
- Do NOT add threading or async job-following — those are in the cloud-bridge e2e dispatch spec.
- Do NOT poll faster than 5 s by default, and do NOT use the GitHub REST API for the change check
  (it is rate-limited; `git ls-remote` over SSH is not).
- Do NOT restart the running bridge or touch the live `cloud-requests` branch.
