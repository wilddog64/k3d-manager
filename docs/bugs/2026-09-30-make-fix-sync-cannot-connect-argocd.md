# Bug: `make fix-sync` cannot connect to ArgoCD

**Branch:** `k3d-manager-v1.40.0`
**Filed:** 2026-09-30
**Status:** FIXED (`ffe501fa`)
**Severity:** medium — the documented repair target fails with an opaque EOF when the local
ArgoCD port-forward is not already running.

## Evidence

```text
argocd app sync "acg-kube-prometheus-stack" --timeout 120 --server localhost:8080 --insecure
{"level":"fatal","msg":"Failed to establish connection to localhost:8080: error creating connection: EOF"}
make: *** [fix-sync] Error 1
```

## Root cause

The `fix-sync` and `fix-force-sync` recipes assumed that `localhost:8080` was already served by
the ArgoCD port-forward. They also omitted `--grpc-web`, although the repository's ArgoCD login
path uses the port-forward with gRPC-web.

## Fix

The targets now create a short-lived `k3d-k3d-cluster` port-forward when the default local
endpoint is unavailable, wait for `/healthz`, use `--grpc-web`, and clean up the process and log.
`ARGOCD_SERVER=host:port` remains available for an already reachable non-local endpoint.

## Follow-up evidence

After the first fix established the tunnel, ArgoCD returned:

```text
rpc error: code = Unknown desc = Post "https://localhost:8080/application.ApplicationService/Get": EOF
```

The repository's working login path uses `--plaintext` for this local port-forward. The sync
targets now pass that flag as well.

Follow-up commit: `14dab218`.

## Authentication follow-up

After the transport fix, a stale CLI session failed with:

```text
rpc error: code = Unauthenticated desc = invalid session: token signature is invalid: signature is invalid
```

The targets now validate the current CLI session and re-login with the `admin` password from
`argocd-initial-admin-secret` when the cached token is invalid. The password is passed on stdin and
never printed.

Follow-up commit: `a7fb7798`.

## Diagnostics follow-up

When the target still exited with status 1, its cleanup path removed the port-forward log and its
login branch suppressed the useful error. The target now identifies Secret-read and login failures
and preserves the temporary port-forward log when the operation fails.

Follow-up commit: `36653c96`.

## Login compatibility follow-up

The first automatic-login implementation still failed without exposing the CLI diagnostic. It also
did not match the repository's known-good login path, which supplies `--skip-test-tls` and a
newline-terminated password. The target now matches that path and reports the login command's
error output without printing the password.

Follow-up commit: `e853c849`.

## Output-capture follow-up

The login diagnostic was still hidden because stdout was redirected before capture. The target now
captures both stdout and stderr from `argocd login` before reporting the failure.

Follow-up commit: `75952f57`.

## CLI-version compatibility follow-up

The installed CLI rejected the repository's historical `--stdin` flag:

```text
Error: unknown flag: --stdin
```

The fallback now authenticates through ArgoCD's `/api/v1/session` endpoint, reads the password
from stdin without putting it in argv, and exports only the resulting `ARGOCD_AUTH_TOKEN` for the
sync command.

Follow-up commit: `4335a601`.

## Credential-source follow-up

The session API then returned HTTP 401 because the Kubernetes initial-admin Secret was stale. The
target now resolves credentials in this order: `ARGOCD_ADMIN_PASSWORD`, Vault
`secret/argocd/admin`, then the Kubernetes initial-admin Secret.
