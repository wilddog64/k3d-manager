# Bug: `_secret_store_data` puts the secret value in `security`'s argv

**Branch:** `k3d-manager-v1.43.0`
**Filed:** 2026-10-09
**Status:** OPEN — spec ready (v1.43.2 batch 1). Fix upstream in lib-foundation (branch `fix/secret-store-data-stdin` from `origin/main`, v0.5.1 still affected), then subtree-pull. One agent fixes this and `2026-10-10-secret-store-data-reports-success-on-failed-keychain-write.md` in one change
**Priority:** P2
**Severity:** Medium — every Keychain write through the shared helper exposes the value in the process list for the life of the `security` call
**Files:** `scripts/lib/foundation/scripts/lib/system.sh` (upstream: lib-foundation `scripts/lib/system.sh`)

## Symptom

On macOS, `_secret_store_data` stores a value with:

```bash
_no_trace bash -c 'security add-generic-password -s "$1" -a "$2" -w "$3" >/dev/null' _ "$service" "$key" "$data"
```

`_no_trace` stops the value reaching an xtrace log, but `"$3"` is still an argument of both the
`bash -c` child and the `security` process. Any process of the same user can read it with `ps` while
the call runs.

Found while verifying the v1.43.0 DR drill. Its plan (D1) requires the Vault unseal shards to travel
"through the existing helpers' stdin path only; they never appear in argv". The helper has no stdin
path, so `vault_dr_shards_save`, `vault_dr_shards_import` and the existing transient unseal cache
(`_vault_cache_unseal_keys`) all put unseal shards on argv. The shards are the highest-value secret
stored this way.

## Prior art

The same exposure was fixed at individual call sites, each working around the helper rather than
fixing it:

- `docs/bugs/2026-10-01-cloudflared-credentials-exposed-in-process-argv.md`: feeds
  `add-generic-password ... -w <value>` to `security -i` on **stdin**, so the value is never an
  argument.
- `docs/bugs/2026-09-15-update-webhook-slack-secret-argv-fail-open.md`: same class, in a Makefile
  target.

## Fix

In lib-foundation, change the macOS branch of `_secret_store_data` to the `security -i` stdin form
already proven in the cloudflared fix. Quote the value for `security -i`'s own parser, or hex-encode
it as that fix does. Keep `_no_trace`. The Linux `secret-tool store` branch already reads the value
from stdin; leave it.

Then subtree-pull into k3d-manager. Do not edit `scripts/lib/foundation/` here.

## Tests (lib-foundation BATS)

- A stub `security` logs its argv and its stdin. After `_secret_store_data svc key SENTINEL`, the
  sentinel appears in the stdin log only, never in any argv log.
- A value containing a space, a quote and a backslash round-trips through `_secret_load_data`.
- Mutation: put `-w "$3"` back on argv; the first test goes red.

## Dispatch

- Work repo `~/src/gitrepo/personal/lib-foundation`, branch `fix/secret-store-data-stdin` from
  `origin/main`. Run `codex exec` from that repo; `make codex-dispatch` only handles k3d-manager.
- One commit covers both bugs:
  `fix(system): _secret_store_data writes over stdin, keeps the old item on failure, returns the real status`.
- After the lib-foundation PR merges and is released, subtree-pull into k3d-manager on
  `k3d-manager-v1.43.2`.
