# Bug: `/cluster-diagnose logs` publishes pod log lines with only registry-based redaction

**Branch:** `k3d-manager-v1.40.0`
**Filed:** 2026-09-28 by Claude (cloud session), at the operator's request while adding
`/cluster-diagnose` to the cloud bridge (`v1.40.0-cloud-bridge-test-targets.md` M4b)
**Status:** OPEN
**Severity:** Medium — no known live leak; a real exposure path to Slack today, and a
permanent one to git once the bridge exposes it.
**Component:** `scripts/lib/webhook/status.py` (`_run_cluster_diagnostics`, `action == "logs"`),
`bin/k3dm-webhook` (`_redact_secrets`)
**Related:** `2026-09-17-webhook-register-secret-coverage-audit.md` — its "Not in scope — the
fetch-scoped registry limit" section describes this exact limit and says it is "tracked
separately as a v1.35.0 item". No such item exists in `docs/` or `memory-bank/` (searched
2026-09-28). This doc is that item, for the `logs` verb.
**Sibling:** `2026-09-28-diagnostics-describe-pod-prints-literal-env-values.md`

## The defect

`logs` runs `kubectl logs pod/<name> -n <ns> --context <ctx> --tail=<n>` and writes the result
through `_redact_secrets` before posting it. `_redact_secrets` replaces only values in
`_REDACT_VALUES` — secrets the webhook process itself fetched and registered. A pod's log is
produced by the application; any credential the application prints (a connection string with a
password, a bearer token in a request dump, a Vault token in a startup banner) was never
registered, so it passes through untouched.

The namespace allowlist (`_DIAGNOSTIC_NAMESPACES`) does not help: it includes `identity`
(Keycloak), `secrets`, `cicd` (ArgoCD) and `shopping-cart-apps` — the namespaces most likely to
log credentials.

## Where it goes

| Path | Today | Retention |
|---|---|---|
| Slack thread (`/cluster-diagnose ... logs`) | **reachable now** | Slack history |
| `cloud-requests` branch via `job-status` | once M4b's `diagnose-logs` lands | **permanent git history**, readable by anyone who can read the repo |

The second is why M4b holds `diagnose-logs` until this is fixed.

## Fix

A shape-based scrubber applied to diagnostics output **in addition to** `_redact_secrets`, in
`_run_cluster_diagnostics`, so both Slack and the bridge get it from one place:

- Patterns, each replaced with `***REDACTED***`, keeping the prefix so the line stays readable:
  `Bearer <token>`; JWTs (`eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+`); URL userinfo
  (`scheme://user:<pw>@`); `key=value` / `key: value` where the key matches
  `(?i)(password|passwd|secret|token|api[_-]?key|credential)`; Vault tokens (`hvs\.`/`s\.` +
  24+ chars); `sk_live_`/`sk_test_`; `ghp_`/`github_pat_`.
- Reuse the vocabulary `_args_have_sensitive_flag` (`scripts/lib/system.sh`) already names, so
  the lists cannot drift; one Python module the cloud-request artifacts filter
  (`v1.40.0-cloud-request-artifacts.md` M2) imports rather than redefines.
- Scrub the whole output after `_redact_secrets`, never per line before it.

The 2026-09-17 doc warns that an improvised matcher inside this file is worse than the honest
limit. That is the reason for the gates below: every pattern is a named, tested case, and the
false-positive cases are tested as hard as the positive ones.

## Tests

1. Each pattern above, embedded in a synthetic log line, comes out redacted with its prefix
   intact. Synthetic values only.
2. False-positive guards: a line mentioning the word `password` with no value, a `token_count=42`
   metric, a 40-hex git SHA and an image digest `sha256:<64 hex>` are **unchanged**.
3. `_run_cluster_diagnostics` with a stubbed `kubectl logs` returning a synthetic bearer token:
   the written output and the Slack payload both lack the token.
4. A registered secret is still redacted (the registry path is not replaced).

### Mutations

- Drop the scrubber call → test 3 red.
- Widen the key pattern to `(?i)token` alone → test 2's `token_count` guard red.
- Drop the JWT pattern → its test 1 case red.

## Out of scope

- `describe-pod` — the sibling doc; different leak shape.
- Whether diagnostics should be posted to Slack at all.
- `_register_secret` coverage (the 2026-09-17 doc).
