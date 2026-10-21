# Bug: Slack smoke command cannot specify an ArgoCD target

**Status:** OPEN — Slack smoke fails closed when multiple eligible shopping-cart targets exist, and the Slack Make allowlist cannot pass the supported selector
**Priority:** P2
**Filed:** 2026-10-21
**Detected by:** operator Slack live verification, job `a3d1097b`
**Branch:** `k3d-manager-v1.43.5`
**Component:** Slack `/k3dm` Make target allowlist

## Observed behavior

After the webhook restart, `/k3dm smoke` returned `webhook PASS` and a bounded cluster-health
diagnostic:

```text
[TARGET] expected exactly one shopping-cart target, found 2
  ubuntu-hostinger-shopping-cart-basket -> ubuntu-hostinger
  ubuntu-k3s-shopping-cart-basket -> ubuntu-k3s
```

`bin/smoke-test-cluster-health` intentionally refuses to choose between multiple targets unless
`ARGOCD_APP_PREFIX` is provided. The local Make/script path supports that selector, but
`scripts/lib/webhook/make_targets.py` only allows `SMOKE_ONLY` for Slack `smoke`; therefore an
operator cannot choose the intended target through Slack.

## Expected behavior

- `/k3dm smoke ARGOCD_APP_PREFIX=ubuntu-hostinger-` passes the validated Make variable to the
  smoke command and selects only that exact ArgoCD target.
- Keep selector validation strict and shell-safe; do not accept arbitrary Make variables.
- Do not choose a default target when multiple candidates exist. Without an explicit prefix,
  preserve the current fail-closed `[TARGET]` diagnostic.
- Preserve the existing `SMOKE_ONLY=offline|cluster` behavior and operator role requirement.
- Document the accepted selector and example in Slack command help/docs.

## Files

- `scripts/lib/webhook/make_targets.py`
- `scripts/tests/bin/webhook_make_targets.py`
- `docs/howto/slack-slash-commands.md`

## Verification gates

- `python3 -m unittest scripts.tests.bin.webhook_make_targets`
- `python3 -m pytest -p no:cacheprovider scripts/tests/bin/test_cloud_bridge.py`
- `_agent_audit`

## Scope limits

Do not alter `bin/smoke-test-cluster-health` target resolution or cluster health checks. Do not
contact or mutate a cluster. Keep the task limited to allowlisting a validated explicit selector,
regression tests, and documentation.
