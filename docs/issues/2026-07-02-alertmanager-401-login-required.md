# Alertmanager status check returned `401` because the auth proxy cached stale credentials

## What I tested

I observed `make status` reporting:

```text
❌ Alertmanager: HTTP 401 (login required) (https://alertmanager.3ai-talk.org/api/v2/status)
```

I also inspected the local Alertmanager login proxy and the on-disk credential file used by the status probe.

## Root cause

`bin/alertmanager-auth-proxy` only loaded `~/.local/share/k3d-manager/alertmanager-basic-auth.env` once at startup. If the credential file was regenerated or rotated later, `make status` would read the new password from disk while the running proxy still authenticated against the old in-memory snapshot.

That split view produced the `401` even though the proxy path itself was up.

## Fix

`bin/alertmanager-auth-proxy` now rereads the credentials file on every request instead of caching the first read forever. That keeps the proxy and `make status` aligned across credential regeneration and rotation.

`docs/howto/launchd-daemons.md` now documents the behavior so the proxy’s reload semantics are explicit.

## Verification

The proxy regression test now proves the file is reread without a restart:

```text
bats scripts/tests/bin/alertmanager_auth_proxy.bats
1..2
ok 1 alertmanager auth proxy requires basic auth and forwards headers
ok 2 alertmanager auth proxy rereads rotated credentials without restart
```

`python3 -m py_compile bin/alertmanager-auth-proxy` also passes with `PYTHONPYCACHEPREFIX=/tmp`.
