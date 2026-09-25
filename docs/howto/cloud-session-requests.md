# Cloud Session Requests — asking the local k3dm webhook for read-only state

**Audience:** a Claude cloud session (or any agent) that has this repo through a GitHub
connection but no network path to the operator's machine. Also the operator, for the
two-token model and revocation.

**Status:** interface contract. This document was written before the implementation and is
what `bin/k3dm-cloud-request` and `bin/k3dm-cloud-bridge` are built to match.

---

## The short version, for a cloud session

You cannot reach the webhook. It listens on `https://127.0.0.1:7443` on a machine that has no
inbound route, and you have no credential for it. Do not look for one, do not try to open a
tunnel, and do not ask the operator to paste a token into your environment — that request is
refused by policy, not by accident.

What you *can* do is **leave a request on a git branch and come back for the answer.** A poller
on the operator's machine reads the branch every 60 seconds, calls the webhook with a read-only
credential you never see, and commits the response back.

```bash
git fetch origin cloud-requests
bin/k3dm-cloud-request cluster-status          # files the request, prints the id
bin/k3dm-cloud-request --wait cluster-status   # files it, then polls until the response lands
```

If nothing comes back within a few minutes, the bridge is not running. That is an operator
problem, not something to work around. Say so and move on.

## What you can ask for

Four actions. This list is a security boundary, not a convenience default — anything not on it
is rejected by the bridge without being executed.

| action | args | what you get back |
|---|---|---|
| `health` | none | per-service smoke results plus `all_ok` |
| `cluster-status` | none | the hub/app cluster status summary |
| `hostinger-status` | none | the hostinger cluster status |
| `job-status` | `job_id` | status and the last 2000 bytes of output for one webhook job |

`job_id` must match `[0-9a-f]{8,64}`. Anything else is rejected.

### What you cannot ask for, and why

`/api/v1/ask` and `/api/v1/analyze` are **excluded even though the webhook rates them
`reader`.** They invoke an AI. Your prompt derives from GitHub content — PR titles, issue
bodies, review comments — which anyone who can open a PR can influence. Routing that into
another AI's prompt chains two injection surfaces together, which is exactly what the webhook's
own `_INJECTION_RE` filter exists to prevent. Adding either one back requires its own spec and
the operator's decision.

Every mutating action — `cluster-up`, `cluster-down`, `cluster-resume`, `cluster-refresh`,
`argocd-upgrade`, `cve-remediate`, `cleanup-stale-sandbox`, any `make` target — is unreachable
through this channel by three independent mechanisms: it is not in the table above, the bridge
presents a reader credential that the webhook will not accept for it, and the branch's content
never becomes a command. If you need one of those, ask the operator to run it.

## Filing a request by hand

The helper is preferred, but the format is plain git so you can do it directly. Branch
`cloud-requests`, never merged to `main`:

```
requests/<id>.json      you write these
responses/<id>.json     the bridge writes these
ledger/processed.txt    append-only, one id per line
```

The id is `<utc-iso-compact>-<slug>`, e.g. `20260925T201403Z-cluster-status`.

```json
{
  "schema": 1,
  "action": "cluster-status",
  "args": {},
  "requested_by": "claude-cloud",
  "requested_at": "2026-09-25T20:14:03Z",
  "expires_at": "2026-09-25T20:44:03Z"
}
```

All six fields are required. `schema` is compared with `==` — an unrecognized value is rejected
rather than coerced, so an old bridge can never silently reinterpret a new format. Give
`expires_at` a short window (the helper uses 30 minutes); a request the bridge picks up after it
expires is rejected, and its id is still consumed.

Commit and push to `cloud-requests` only. Never open a PR from it and never merge it.

## Reading the response

```json
{
  "schema": 1,
  "id": "20260925T201403Z-cluster-status",
  "action": "cluster-status",
  "status": "ok",
  "http_status": 200,
  "completed_at": "2026-09-25T20:14:41Z",
  "body": { }
}
```

`status` is `ok`, `rejected` or `error`. On `rejected`, `reason` says which validation failed and
`body` is absent — the request was never executed. There is **no retry**: an id is consumed
whether it succeeded, was rejected, or expired. To ask again, file a new request with a new id.

## The helper

```
bin/k3dm-cloud-request <action> [--arg key=value ...] [--wait] [--timeout SECONDS]
```

- files a request on `cloud-requests` and prints the id on stdout
- `--wait` polls `responses/<id>.json` (default timeout 300s, poll interval 30s) and prints the
  response JSON on stdout
- exit 0 = response received with `status: ok`; 3 = `rejected`; 4 = `error`; 5 = timed out with
  no response; 2 = bad usage (unknown action, malformed `--arg`)

It needs no credential and no environment variables beyond the git access the session already
has. That is the practical payoff of the pull design.

## Why it is built this way

The alternative was to expose the webhook publicly behind Cloudflare Access with a service token
in the cloud environment. It was rejected on 2026-09-25: the sandbox is outbound-only, so push
requires a public route to a host that also serves mutation-capable paths, and the credential
would have to live in a third-party secret store. Pull reaches the same read-only outcome with no
public route and no exported credential. See
`docs/plans/v1.38.0-cloud-session-endpoint-access.md` for the full threat model.

**Treat the branch as untrusted input in both directions.** Anything that compromises the cloud
session can push arbitrary bytes to it. The bridge's validation order is the control, and it is
the only thing standing between that branch and the webhook.

---

## Operator section

### The two tokens

| credential | source | used by | can do |
|---|---|---|---|
| `k3dm-webhook-token` | env `K3DM_WEBHOOK_TOKEN`, Keychain, then `TOKEN_FILE` | Slack relay, `make` targets, you | everything, including cluster mutation |
| `k3dm-webhook-token-reader` | env `K3DM_WEBHOOK_TOKEN_READER`, Keychain only | the cloud bridge, nothing else | reader-level routes only |

The reader token deliberately has **no `TOKEN_FILE` fallback** — sharing that file would make the
two roles the same secret.

The role now comes from *which credential authenticated*, not from the `X-K3DM-Role` header. A
header can only ever **narrow** a role; the credential sets the ceiling. Before this change the
header was self-asserted and an absent header meant `admin`, which is why a reader-scoped token
was a code change rather than a configuration step. This was audit finding **F4** (LOW, "revisit
if role-scoped tokens are added") in `docs/issues/2026-09-07-webhook-server-security-audit.md`;
adding the reader token is that revisit.

### Creating and rotating the reader token

Generate it on the machine, write it straight to the Keychain, and never let it reach a shell
argument, a log, or a file in the repo. It lives in the login Keychain as service
`k3dm-webhook-token-reader`, account `k3dm` — the same store and account as the admin token.
Write it from a real terminal: a `security add-generic-password -w` with no TTY stores an
*empty* value at exit 0, which would create a credential matching the empty string.

Rotation needs no restart. `_auth()` calls `_get_token()` and `_get_reader_token()` on every
request, so the Keychain is read per authentication and a new value takes effect immediately —
`bin/k3dm-webhook-setup --rotate` says as much for the admin token ("daemon picks up new token
on next request"). Nothing else holds a copy; the bridge reads the Keychain each tick.

Do **not** reuse `bin/k3dm-webhook-setup` for this token. It passes the value as a `-w` argv
argument, and it pushes the result to a GitHub Actions secret — neither is acceptable for a
credential whose whole purpose is that it never leaves this machine.

### Revoking cloud access

One step. Bootout the bridge's launchd agent:

```bash
launchctl bootout gui/$(id -u)/com.k3d-manager.cloud-bridge
```

Requests already on the branch become inert — nothing reads them. The branch can stay; nothing
else needs touching, and the reader token does not need rotating unless you believe it leaked.

### Housekeeping

The branch grows one commit per request plus one per response. Reset it when it gets large:
delete the remote branch and recreate it empty with the three directories. Nothing depends on its
history, and the ledger only needs to contain ids that could still be replayed — but if you
truncate the ledger, any surviving `requests/` entry becomes eligible again, so clear `requests/`
in the same operation.

### Bridge placement

The bridge runs against a **bare clone** at `~/.k3d-manager/cloud-bridge/repo.git`, not against
your working repo. It therefore has no working tree to check out into and cannot disturb
uncommitted work, and repo pre-commit hooks never run on its machine-generated commits. Commits
are built with git plumbing and pushed with `--force-with-lease`.

### Not a Hermes responsibility

This is its own launchd agent on purpose. Hermes' blast radius should not grow, and its plist
already carries template drift (`K3DM_HERMES_AUTO_KINE_GUARD`) that a second consumer would
complicate.
