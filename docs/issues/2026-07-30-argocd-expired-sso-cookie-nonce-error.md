# Argo CD shows `data length is less than nonce size` after SSO session expiry

## What was observed

Opening `argocd.3ai-talk.org` rendered a plain error:

```text
data length is less than nonce size
```

The Argo CD server is healthy: one `argocd-server` pod is Ready with no restarts, and
the `argocd-secret` containing `server.secretkey` is stable (created 2026-07-20).
There is no evidence of split replicas or an encryption-key rotation.

## Root cause

Argo CD server logs show the corresponding authentication failure:

```text
Failed to verify session token: failed to verify provider token: oidc: token is expired
rpc error: code = Unauthenticated desc = invalid session: failed to verify the token
```

The browser retained an expired/malformed Argo CD SSO cookie. When Argo CD attempts to
decrypt that stale cookie, it returns the nonce-length error before it can redirect to a
new Keycloak login.

## Resolution

Clear site data/cookies for `argocd.3ai-talk.org` (or use a private window), reload the
site, and sign in again through Keycloak. No cluster-side secret reset or Argo CD restart
is appropriate; either would unnecessarily invalidate every user session.
