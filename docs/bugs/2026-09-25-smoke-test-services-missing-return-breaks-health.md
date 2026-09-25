# `_smoke_test_services` lost its closing `return`, so `/api/v1/health` has 500'd since v1.37.0

**Filed:** 2026-09-25
**Area:** `scripts/lib/webhook/smoke.py` (`_smoke_test_services`); `bin/k3dm-webhook` (`do_GET` health branches, post-provision check)
**Type:** bugfix
**Introduced by:** `925c43e7` — "feat: v1.37.0 — webhook decomposition and gates that prove their claim (#131)"

## Problem

Found while verifying the v1.38.0 credential-bound role work — not by a test, and not by
the suite, which is the point of interest.

An authenticated `GET /api/v1/health` does not return a response at all. The daemon raises
and the connection is dropped, so `curl` reports `http=000`:

```
admin  health: 000
reader health: 000
reader cluster-status: 202
```

`/Users/cliang/Library/Logs/k3dm-webhook.log`:

```
  File "/Users/cliang/src/gitrepo/personal/k3d-manager/bin/k3dm-webhook", line 2187, in do_GET
    result = [{"name": n, "ok": ok, "detail": d} for n, ok, d in services]
                                                                 ^^^^^^^^
TypeError: 'NoneType' object is not iterable
```

The `202` on `cluster-status` is the control: authentication, the credential-bound role
ceiling and the POST path are all fine. Only the health path is broken.

## Root cause

`_smoke_test_services(retries=None, provider=None, quick=False)` has exactly one top-level
`return`, at `scripts/lib/webhook/smoke.py:574`, inside the early-exit branch:

```python
    if quick:
        return results
```

The function then does the full sweep — the paused-monitoring downgrade, pushgateway,
data layer, `_smoke_test_logins` — and **falls off the end**, returning `None`.

This is a decomposition regression. Before `925c43e7` the function lived in
`bin/k3dm-webhook` and ended with `return results` (line 2377 of that file at
`945018ee`). `925c43e7` created `scripts/lib/webhook/smoke.py` and moved the function
into it without the closing return. `scripts/lib/webhook/smoke.py` has exactly one commit
in its history, so there is no later edit to blame.

## Impact

Two callers iterate the result on the non-quick path, and both raise:

- `bin/k3dm-webhook:2186` and `:2196` — **both** `/api/v1/health` branches, the plain path
  and the `?provider=/?quick=` query form. The query form passes `quick` through, so
  `/api/v1/health?quick=1` *works* and the bare `/api/v1/health` does not.
- `bin/k3dm-webhook:1482` — the post-provision check, `for svc_name, ok, detail in smoke`.
  The Slack post-provision health report has been broken for the same reason.

`quick=True` callers were unaffected throughout, which is why this survived a release: the
paths an operator exercises casually still worked.

**It also blocks v1.38.0.** `health` is one of the four actions on the cloud-session
allowlist, so the bridge would have been built and smoke-tested against an endpoint that
cannot answer.

## Fix

One line — restore the closing return:

```python
    results.extend(_smoke_test_logins(provider, app_context))

    return results
```

## Why no test caught it

No test called `_smoke_test_services` on the non-quick path. `webhook_policy.py` patches it
out with `return_value=[]`, and `webhook_hub_eso.bats` does not reach it. A test that only
ever exercises `quick=True` cannot see a missing return on the other branch.

Regression test added: `test_smoke_test_services_returns_results_on_the_non_quick_path` in
`scripts/tests/bin/test_smoke_logins.py`. It asserts the non-quick return is a list and
unpacks each tuple. Mutation-checked — with the `return` removed it fails on the
`result is not None` assertion.

## Verification

- `pytest scripts/tests/bin/test_smoke_logins.py` — 15 passed.
- Mutation check: `return` removed → the new test fails; restored → passes.
- Live: `make restart-webhook`, then an authenticated `GET /api/v1/health` returns 200 with a
  `services` array instead of dropping the connection.

## Follow-up — not in this fix

The release gate did not catch a merged endpoint that returns nothing. A webhook smoke gate
that asserts `/api/v1/health` returns 200 and parses its `services` array would have. That
belongs with the existing webhook smoke-gate work, not here.
