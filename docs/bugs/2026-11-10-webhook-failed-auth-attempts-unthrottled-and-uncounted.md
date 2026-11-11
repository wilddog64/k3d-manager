# Bug: webhook failed-auth attempts are neither throttled nor counted

**Status:** OPEN
**Priority:** P3
**Waiting on:** dispatch — since 2026-11-11 (P3 batch)
**Introduced by:** `7253ece4` (v1.23.0, PR #112: the limiter moved after auth, deliberately; see Prior art)
**Should have been caught by:** spec (v1.23.0 fixed the shared-bucket lockout but left failed attempts with no limit and no signal)
**Prior art:** `docs/bugs/v1.23.0-bugfix-webhook-ratelimit-order-and-content-length.md` — read, same code path, different defect: it moved `_rate_limited` after `_auth` because one global pre-auth bucket let an unauthenticated flood 429 the operator; that reason still holds and constrains this fix. `make find-similar-docs` not run (vector store unreachable: `context "k3d-k3d-cluster" does not exist`, 2026-11-10)
**Severity:** detection and hygiene. Tokens are 256-bit random (`bin/rotate-webhook-token:9`, `openssl rand -hex 32`), so guessing is not a practical threat; the gap is that a guessing or flooding source is invisible and unbounded (log growth, CPU). Filed as P3 by Claude after reading the prior art and the token strength; proposed as P2 before that, operator may raise it.
**Approval:** operator, 2026-11-10: "go for those three as you suggested (approved)" (filing)
**Intent approved:** operator, 2026-11-11 ("P2/P3 approved")
**Filed:** 2026-11-10
**Detected by:** Fable review of `docs/plans/v1.54.0-ai-attack-surface-security-boundary-hardening.md` (finding G2); verified by Claude in code, 2026-11-10
**Branch:** `k3d-manager-v1.43.15`
**Related:** `docs/plans/v1.54.0-ai-attack-surface-security-boundary-hardening.md` item 8 (edge detection reads the counter this adds)

## Evidence (Claude, 2026-11-10, `k3d-manager-v1.43.15`)

- `bin/k3dm-webhook:2399-2407` (POST) and `:2796-2800` (GET): `if not self._auth(): 401` returns before
  `_rate_limited("api")`, so failed attempts never touch a limiter.
- `scripts/lib/webhook/policy.py:50-58`: `_rate_limited(bucket)` is one fixed window per bucket name (`api`,
  `slack`), 60/min (`:38-39`), not per source.
- `bin/k3dm-webhook:2882-2894`: the access log already records `status=` and `client=` (from `CF-Connecting-IP`),
  but no metric counts 401s, and no alert reads them.
- The server binds `127.0.0.1` behind cloudflared, so `client_address` is always localhost; the only source
  identity is the `CF-Connecting-IP` header, which a local process can set freely.

## Fix

1. A **separate** pre-auth limiter for failed attempts only, keyed by `CF-Connecting-IP` (fallback key
   `unknown`), counted only when `_auth()` fails. It never shares a bucket with authenticated traffic, so a flood
   from one source cannot 429 the operator (the v1.23.0 reason). Over budget, that source gets 429 without the
   token comparison; a bounded table (LRU or periodic prune) caps memory.
2. A counter of failed auth attempts exported for Prometheus (no token, header value or IP in labels; the IP
   stays in the log line only), so v1.54.0 item 8 can alert on bursts.
3. Prove before spec: that Cloudflare overwrites a client-supplied `CF-Connecting-IP` on requests through the
   tunnel (captured request from outside, host and date), since the per-source key rests on it.

## Contract readers

- `CF-Connecting-IP` header: reader `bin/k3dm-webhook:2882` (log `client=`), unchanged; the new limiter becomes a
  second reader. Writers: Cloudflare edge (external); any local process on the hub (spoof, see Evidence).
- Access log line format (`bin/k3dm-webhook:2894`): readers `scripts/tests/bin/test_webhook_access_log.py:112,137`
  and Loki queries on webhook logs; unchanged (no field removed).
- 401/429 responses: readers Hermes, `bin/k3dm-cloud-bridge`, `bin/smoke-test-webhook`; all present a valid token,
  so they never reach the failed-attempt limiter. Writers: none.

## Acceptance

```yaml
must:
  M1: a source that fails auth more than the budget within the window receives 429 for further attempts from that source in the window
  M2: failed auth attempts increment an exported counter; successful requests do not
must_not:
  N1: failed attempts from one source never cause a valid-token request (from any source) to receive 429
  N2: no metric label or log line added by this fix contains a token or Authorization header value
evidence:
  - {id: E1, proves: [M1, N1], kind: offline, intent: "You will see a test flood 401s from one fake source, get 429 for it, while a valid-token request in the same window still gets 200; the N1 half fails on a design that puts the failed attempts in the shared api bucket."}
  - {id: E2, proves: [M2, N2], kind: offline, intent: "You will see the failed-attempt counter rise by exactly the number of bad requests and not move for good ones, and a scan of the metrics and log output find no token text."}
  - {id: E3, proves: [M1], kind: live, intent: "Claude sends a few bad-token requests through the public webhook hostname and sees the counter rise and, past the budget, 429; the operator's normal calls keep working."}
interface:
  - "HTTP GET/POST to the webhook (127.0.0.1 listener) with and without a valid Bearer token and a CF-Connecting-IP header"
  - "the webhook's Prometheus metrics output"
```

## Worker definition of done

- Change only `bin/k3dm-webhook`, `scripts/lib/webhook/policy.py` and a test under `scripts/tests/bin/`. Show
  N1's test red against a mutant that counts failures in the shared `api` bucket, then green. Paste command, rc
  and proving lines. Leave changes uncommitted; Claude reviews and lands.
