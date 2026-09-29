# Bug: `/cluster-diagnose describe-pod` prints literal container env values unredacted

**Branch:** `k3d-manager-v1.40.0`
**Filed:** 2026-09-28 by Claude (cloud session), at the operator's request while adding
`/cluster-diagnose` to the cloud bridge (`v1.40.0-cloud-bridge-test-targets.md` M4b)
**Status:** FIXED 2026-09-29 by Claude (cloud session) — `mask_env_values` in
`scripts/lib/webhook/redact.py`, called for `describe-pod` only; the whole-output scrubber already ran.
Tests: `scripts/tests/bin/test_describe_pod_env_masking.py`. Test 1 checks the masker directly, because
the shape scrubber alone already hides the three original fixture values and an end-to-end test 1
could not go red; `SENTRY_DSN` (userinfo without a colon) and `WEBHOOK_URL` (secret in the path)
are the cases only layer 1 catches. All three mutations below, plus unwiring the call, went red.
**Severity:** Medium — no known live leak; reachable in Slack today, permanent in git once the
bridge exposes it.
**Component:** `scripts/lib/webhook/status.py` (`_run_cluster_diagnostics`,
`action == "describe-pod"`)
**Related:** `2026-09-17-webhook-register-secret-coverage-audit.md` (fetch-scoped registry limit)
**Sibling:** `2026-09-28-diagnostics-logs-output-unredacted-for-unregistered-secrets.md` — same
root cause, same scrubber; this doc covers the part specific to `describe`.

## The defect

`describe-pod` runs `kubectl describe pod <name> -n <ns> --context <ctx>` and writes the output
through `_redact_secrets`, which scrubs only values the webhook registered itself.

`kubectl describe pod` renders each container's `Environment:` block. A variable sourced from a
Secret prints safely as `<set to the key 'password' in secret 'x'>`. A variable set with a
literal `value:` prints **the value itself**. Anything a manifest or Helm chart inlines —
a `DATABASE_URL` with the password in its userinfo, an API key passed as a plain value, a token
in `Args:` — is printed in full. Annotations (for example `kubectl.kubernetes.io/last-applied-configuration`,
when present on a bare pod) can carry the same literals.

Unlike logs, the leak here is structural and predictable: it is a manifest choice, not an
application's print statement. That makes it cheaper to fix precisely.

## Where it goes

| Path | Today | Retention |
|---|---|---|
| Slack thread (`/cluster-diagnose ... describe-pod`) | **reachable now** | Slack history |
| `cloud-requests` branch via `job-status` | once M4b's `diagnose-describe-pod` lands | **permanent git history** |

## Fix

Two layers, both in `_run_cluster_diagnostics` for `describe-pod`:

1. **Env-block masking (precise).** Within the `Environment:` section, replace the value of any
   variable whose name matches `(?i)(password|passwd|secret|token|api[_-]?key|credential|dsn|_url$)`
   with `***REDACTED***`, keeping the name. Leave `<set to the key ...>` lines untouched — they
   contain no value.
2. **The shape scrubber** from the sibling logs doc, over the whole output, to catch literals in
   `Args:`, `Command:` and annotations.

Implement the scrubber once (sibling doc) and call it here; do not fork a second pattern list.

## Tests

1. A synthetic `describe` fixture with `DB_PASSWORD: hunter2-synthetic`,
   `DATABASE_URL: postgresql://app:synthetic@db:5432/x` and `API_KEY: synthetic-key` yields all
   three masked, names kept.
2. `LOG_LEVEL: info`, `PORT: 8080` and a `<set to the key 'password' in secret 'x'>` line are
   **unchanged**.
3. A synthetic bearer token in `Args:` is redacted by the scrubber layer.
4. End to end with a stubbed `kubectl describe`: neither the written output nor the Slack
   payload contains any fixture secret.

### Mutations

- Drop the env-block masking → test 1 red.
- Match every env name → test 2 red.
- Drop the scrubber call → test 3 red.

## Out of scope

- Moving inline env values into Secrets across the app manifests. Worth doing, but it is a
  manifest change in each service repo, not a webhook fix, and the webhook must not depend on it.
