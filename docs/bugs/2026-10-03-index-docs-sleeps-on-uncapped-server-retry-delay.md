# Bug: `make index-docs` sleeps for over an hour on an uncapped server retry delay

**Filed:** 2026-10-03, Claude
**Branch:** `k3d-manager-v1.41.0`
**Status:** FIXED in `7a4bd396`
**Severity:** low. The index stalls silently. Batches already committed are kept, so nothing is lost.

## Observed (2026-10-03)

- The post-rebuild re-index (`make index-docs`, PID 84939) logged `committed 700/1802` at 13:00.
- At 14:08 the log had not moved. The process used 0% CPU, had no open socket and no child process.
- `sample 84939` showed the main thread in `time.sleep` → `nanosleep` for the whole sample.

## Root cause

`scripts/lib/hermes/prior_art.py` `_embed_one`, on a retryable `HTTPError`:

```python
wait = asked if asked is not None else delay
...
time.sleep(wait)
delay = min(delay * 2, EMBED_MAX_BACKOFF)
```

`EMBED_MAX_BACKOFF` (64s) caps only the delay the client guesses. A `retryDelay` the server names
(`asked`) is used as-is, with no limit. A 429 carrying a long delay, such as an exhausted per-day
quota, therefore puts the run to sleep for that long. It never reaches the
`index-docs: paused — ... perday` message that `scripts/index-docs.py` prints for that case.

## Fix

1. In `_embed_one`: `wait = min(asked, EMBED_MAX_BACKOFF) if asked is not None else delay`.
2. If `asked` exceeds `EMBED_MAX_BACKOFF`, do not sleep. Raise `EmbeddingsUnavailable` and include the
   quota id and the asked delay in the message, so `index-docs.py` reports a pause and exits 1. That
   path already says re-running resumes from the last committed batch.

**Gates (offline; stub `urlopen` and `time.sleep`):**
- pytest: a 429 with `"retryDelay": "3600s"` makes no `sleep` call over 64s, and raises
  `EmbeddingsUnavailable` naming the delay.
- pytest: a 429 with `"retryDelay": "31s"` sleeps 31s and then succeeds, so the per-minute path is unchanged.
- Mutation: restoring the uncapped `wait = asked` turns the first test red.
- `git diff --stat` touches only `prior_art.py` and its test file.

## Workaround

Press Ctrl-C in the terminal running `make index-docs`, and re-run it later. Every committed batch of
100 is kept, and the re-run only embeds documents whose hash changed.
