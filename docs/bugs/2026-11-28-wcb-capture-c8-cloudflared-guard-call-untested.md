# wcb-capture c8: the call to isolation.check_cloudflared is untested (TUNNEL_TOKEN refusal)

**Status:** OPEN — captured 2026-11-28
**Priority:** P3 (test-only gap; proposed, Argon classifies)
**Introduced by:** `7ddd5b52` (capture kit child a2)
**Should have been caught by:** offline test
**Introducing change reviewed:** no
**Waiting on:** operator decision
**Prior art:** not run

## What

`scripts/lib/wcb_capture/c8c9.py` builds the client env as `dict(os.environ)` with `HOME` set to the scratch
`(1)/cfhome`, then calls `isolation.check_cloudflared(argv_client, child_env)` before running
`cloudflared access ssh --hostname <host>`. Claude's mutant during a2 verification (2026-11-28) removed that call:
`test_wcb_capture_browser.py` and `test_wcb_capture_e2e.py` still passed (35 passed).

The argv is a literal, so the guard's argv checks cannot change the outcome. The one live difference is the guard's
refusal when `TUNNEL_TOKEN` is in the environment: without the call, c8 would pass an exported `TUNNEL_TOKEN` to the
client. a1's suite tests `check_cloudflared` itself; nothing tests that c8 calls it.

## Fix (small)

One test in `test_wcb_capture_browser.py`: run c8 with `TUNNEL_TOKEN` in the env and a recording runner; assert c8
refuses and the runner was never called. Red control: the mutant above (call removed) turns it red.
