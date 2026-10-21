# Bug: Slack smoke command cannot specify an ArgoCD target

**Status:** VERIFIED — explicit Slack target selector is allowlisted and validated; operator live verification pending
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

## Offline verification

- Landed on `k3d-manager-v1.43.5` as `611bc1f8` (`fix(slack): allow explicit smoke target prefix`).
- `python3 -m unittest scripts.tests.bin.webhook_make_targets`: **39 tests passed**.
- `python3 -m pytest -p no:cacheprovider scripts/tests/bin/test_cloud_bridge.py`: **83 passed**.
- The dispatcher's land gate reran both commands successfully; commit hook `_agent_audit` passed.
- No live Slack/webhook verification was performed. After deploying/restarting the webhook, run
  `/k3dm smoke ARGOCD_APP_PREFIX=<chosen-target-prefix>` (for example,
  `ARGOCD_APP_PREFIX=ubuntu-hostinger-` or `ubuntu-k3s-`) and confirm the intended single target is
  checked. Without an explicit selector, the existing fail-closed behavior must remain.
