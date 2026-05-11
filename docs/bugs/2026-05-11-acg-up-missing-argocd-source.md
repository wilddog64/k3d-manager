# Bug: `bin/acg-up` calls Argo CD readiness helper without sourcing the plugin

**Status:** Fixed

## What happened
`bin/acg-up` now calls `_argocd_wait_for_local_port_forward` in Step 4b, but the script did not source `scripts/plugins/argocd.sh` before that call. A fresh `make up` failed immediately with:

```text
INFO: [acg-up] Step 4b/12 — Installing ArgoCD port-forward launchd agent (localhost:8080, auto-restart)...
bin/acg-up: line 194: _argocd_wait_for_local_port_forward: command not found
make: *** [up] Error 1
```

## Root cause
The readiness helper exists in `scripts/plugins/argocd.sh`, but `bin/acg-up` only sourced:

- `scripts/plugins/gemini.sh`
- `scripts/plugins/acg.sh`
- `scripts/plugins/tunnel.sh`
- `scripts/plugins/shopping_cart.sh`

So the helper was never in scope when Step 4b executed.

## Fix
Source `scripts/plugins/argocd.sh` from `bin/acg-up` before the first `_argocd_*` call.

## Follow-up
- Keep the Argo CD plugin sourcing explicit in `bin/acg-up`.
- Add a regression test that guards the import chain.
