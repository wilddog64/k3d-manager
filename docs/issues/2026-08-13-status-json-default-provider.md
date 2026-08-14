# `make status-json` ignored the active provider

## Symptom

With the active provider set to `k3s-hostinger`, `make status` was healthy but
`make status-json` emitted an unknown result for the default `k3s-aws` provider:

```text
{"overall":"unknown","provider":"k3s-aws","context":"","errors":[],"warnings":[{"id":"status_source","status":"unknown","reason":"webhook unavailable"}],"checks":[],"counts":{}}
make: *** [status-json] Error 2
```

## Root cause

The JSON summary helper defaulted directly to `k3s-aws`. The Makefile only
passes `CLUSTER_PROVIDER` when the user explicitly supplies it, while the
summary path bypassed `bin/cluster-status`'s active-provider resolution.

## Fix and verification

`bin/cluster-status-summary` now reads
`~/.local/share/k3d-manager/active-provider` when no provider is explicit (or
when the Makefile's file default is still `k3s-aws`). A regression test covers
this behavior. Live verification now returns:

```text
{"overall": "healthy", "provider": "k3s-hostinger", ...}
```
