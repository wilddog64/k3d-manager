# Bug: `/cluster-diagnose logs` publishes pod log lines with only registry-based redaction

**Branch:** `k3d-manager-v1.40.0`
**Filed:** 2026-09-28 by Claude (cloud session), at the operator's request while adding
`/cluster-diagnose` to the cloud bridge (`v1.40.0-cloud-bridge-test-targets.md` M4b)
**Status:** FIXED — follow-up commit `89214fc0`
**Severity:** Medium — no known live leak; a real exposure path to Slack today, and a
permanent one to git once the bridge exposes it.
**Component:** `scripts/lib/webhook/status.py` (`_run_cluster_diagnostics`, `action == "logs"`),
`bin/k3dm-webhook` (`_redact_secrets`)
**Related:** `2026-09-17-webhook-register-secret-coverage-audit.md` — its "Not in scope — the
fetch-scoped registry limit" section describes this exact limit and says it is "tracked
separately as a v1.35.0 item". No such item exists in `docs/` or `memory-bank/` (searched
2026-09-28). This doc is that item, for the `logs` verb.
**Sibling:** `2026-09-28-diagnostics-describe-pod-prints-literal-env-values.md`

## Codex brief

**Goal:** diagnostics output (Slack and `job-status`) never carries a credential-shaped value,
whether or not the webhook registered it. One shared scrubber module that the describe-pod
sibling, the artifacts spec's M2 filter and the v1.41.0 logging spec's M4 all import.

**Runs where:** Codex web is fine. Pure code and offline tests with a stubbed `kubectl`; nothing
needs the M4, a cluster, Slack, or the webhook process.

**Decisions already made:**
- New module `scripts/lib/webhook/redact.py`, stdlib `re` only, exposing
  `scrub_credentials(text) -> str`. The marker is `***REDACTED***`, the one `_redact_secrets`
  already uses, so every redaction reads the same.
- Call it in exactly one place: `_finish` inside `_run_cluster_diagnostics`
  (`scripts/lib/webhook/status.py:372`), as
  `output = scrub_credentials(_redact_secrets("".join(lines)))`. That covers every diagnostics
  action (logs, describe-pod, describe-app, ...) for both the Slack post and the `output` file.
- Key/value rule: match only when the **key ends in** the sensitive word, so `DB_PASSWORD=`,
  `client_secret:` and `api-key=` are caught but `token_count=42` and `secretName: app-tls` are
  not. A starting point:
  `(?i)\b([\w.-]*(?:password|passwd|secret|token|api[_-]?key|credential)s?)(\s*[:=]\s*)(\S+)`,
  replacing group 3.
- Vault tokens need a word boundary: `\b(?:hvs|s)\.[A-Za-z0-9]{24,}`, so `items.<long id>`
  does not match.
- `_args_have_sensitive_flag` (`scripts/lib/system.sh:196`) names `password`, `token` and
  `username`. `username` is not a secret and stays out. Add a test asserting `password` and
  `token` are both in the module's key vocabulary, so the two cannot drift.

**Files to touch (only these):**
- `scripts/lib/webhook/redact.py` (new)
- `scripts/lib/webhook/status.py` (import and the one call in `_finish`)
- `scripts/tests/bin/test_redact.py` (new; tests 1 to 4 below, plus the vocabulary test and
  the extra guard `secretName: app-tls` unchanged)
- `CHANGELOG.md` (one `### Fixed` bullet under `## [Unreleased]`)
- `memory-bank/activeContext.md`, `memory-bank/progress.md` (SHA and status)
- this bug doc (set **Status** to FIXED with the SHA)

**Test 3 detail:** monkeypatch `status.JOB_DIR` to `tmp_path`, `status._spawn_capture_text` to
return `(0, "<synthetic log with Bearer token>", False)`, and `status._slack_post` /
`status._notify_job` to capture their text. Call `_run_cluster_diagnostics` with
`{"action": "logs", "context": "k3d-k3d-cluster", "namespace": "identity", "name": "keycloak-0"}`
and a `response_url`, then assert neither `tmp_path/<job>/output` nor the captured payload
contains the token.

**Gates (paste the output of each):**
- `python3 -m py_compile scripts/lib/webhook/redact.py scripts/lib/webhook/status.py`
- `make test-pytest` green (summary pasted).
- `python3 scripts/tests/bin/webhook_redaction.py` green (the registry path still works).
- `command grep -c 'scrub_credentials' scripts/lib/webhook/status.py` → `2` (import + call)
- The three mutations below, each shown red, then the tree restored and green again.
- `git diff --stat` lists only the files above.

**Do not change:**
- `_redact_secrets`, `_register_secret` or `_REDACT_VALUES` in `bin/k3dm-webhook`.
- `_args_have_sensitive_flag` or anything in `scripts/lib/system.sh`, `scripts/lib/foundation/`
  or `scripts/lib/acg/`.
- The describe-pod env-block masking. That is the sibling doc's job and it will import this
  module.
- `bin/k3dm-cloud-bridge`. The artifacts spec wires the scrubber in there.
- Do not run `kubectl`, restart the webhook, post to Slack, or run `make down`.

**Commit and hand back:** one commit on `k3d-manager-v1.40.0`, message
`fix(diagnostics): scrub credential-shaped values from diagnostics output`.
No PR, no merge, no force-push, no `--no-verify`.

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

## Verification (2026-09-28, Claude cloud session)

`7208c043` passes every gate in the brief: compile OK, `make test-pytest` 334 passed,
`webhook_redaction.py` OK, grep count `2`, diff limited to the listed files. The three brief
mutations each go red. Authored as `t <t@t>`, like the previous Codex commit.

Gaps found, each reproduced against `scrub_credentials` directly:

| Input | Output | Why |
|---|---|---|
| `{"password":"hunter2"}` | unchanged | a quote sits between the key and `:`; JSON logs (zap, structlog) leak |
| `{"access_token": "abc"}` | unchanged | same |
| `token: Bearer abc123` | `token: ***REDACTED*** abc123` | key/value rule eats `Bearer` first, so the Bearer rule never sees the token |
| `redis://:pw@redis:6379` | unchanged | userinfo rule needs a non-empty user |
| `Authorization: Basic dXNl...` | unchanged | no Basic rule |
| `password = "two words"` | `password = ***REDACTED*** words"` | quoted value cut at the first space |

Surviving mutations (tests stay green):
- Drop `_redact_secrets(` from `_finish`: 20/20 and 334/334 green. Test 3 stubs
  `_redact_secrets` to identity and test 4 uses a local lambda, so no test proves the registry
  path still runs in diagnostics.
- Drop `\b` from `_VAULT_RE`: green. No test guards `items.<long id>`.

### Codex brief (follow-up)

Same branch, same files: `scripts/lib/webhook/redact.py`, `scripts/tests/bin/test_redact.py`,
`CHANGELOG.md`, `memory-bank/*`, this doc. Do not touch `status.py` beyond what test 4 needs
(nothing expected).

- Key/value rule allows an optional closing quote after the key (`"password":"x"`) and redacts a
  whole quoted value (`"..."` or `'...'`), else `\S+` as now.
- Run the Bearer rule before the key/value rule, or make the key/value value skip a leading
  `Bearer `, so `token: Bearer x` redacts `x`.
- Userinfo user may be empty (`[^/\s:@]*`).
- Add `Basic <base64>` (keep the `Basic ` prefix).
- Tests: one case per row in the table above; a guard that `items.abcdefghijklmnopqrstuvwxyz0123`
  is unchanged; rewrite test 4 to call `_run_cluster_diagnostics` with a real registry-style
  `_redact_secrets` (via `status.configure_runtime` or monkeypatch to a function that replaces a
  registered value) and assert the registered value is gone from `output`.
- Mutations to show red: drop `_redact_secrets(` from `_finish`; drop `\b` from `_VAULT_RE`;
  revert the JSON quote handling.
- Commit message: `fix(diagnostics): scrub JSON, quoted and Basic credentials in diagnostics output`.

### Live check

Not possible from the cloud bridge yet: it has no diagnostics action (M4b holds `diagnose-logs`
on this bug), and `job-status` for make jobs returns empty output
(`2026-09-28-make-jobs-never-write-output-file.md`), so a bridged `make-test-pytest` (job
`ece42f1c`, status success) cannot show which tests ran on the M4.
