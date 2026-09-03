# Webhook clear-text secret storage — CodeQL HIGH x2 (defensive redaction barrier)

**Filed:** 2026-09-03
**PR:** #118 (v1.27.0)
**CodeQL:** 2 HIGH `py/clear-text-storage-sensitive-data` — `bin/k3dm-webhook:2286` and `:2601`, both `(job_dir / "output").write_text(output)`.

## Analysis

- Both flagged sinks are pre-existing `_finish()` writes in the status handlers `_run_cluster_status` (2286) and `_run_hostinger_status` (2601); **this PR did not modify those lines**. CodeQL re-ran dataflow because `bin/k3dm-webhook` changed (+60 lines) and self-noted the alerts "might not be introduced by this pull request."
- The cited taint source is the smoke-test password (`_smoke_secret(...)` → `kc_pass`/`seeded_pass`, added by this PR's Keycloak admin-secret fallback in `_smoke_test_logins`).
- **The secret value does not actually reach `output`:** `kc_pass` is only urlencoded into the login POST body (`{"grant_type":"password","password":kc_pass}`); the smoke results appended to `lines` are status strings (`"token minted"`, `"HTTP {code}"`, `"skipped (stand-in token rejected …)"`), and the `except … str(exc)[:200]` paths surface urllib URL+code, never the POST body. => value-insensitive taint over-approximation (likely false positive).

## Decision: harden defensively (do not merely dismiss)

Even as an FP, `_run_cluster_status`/`_run_hostinger_status` post **kubectl diagnostics to Slack and to `job_dir/output`** — a real vector for accidental secret exposure (e.g. `kubectl` output, pod logs). Add a redaction barrier so any known secret value the webhook has read is scrubbed from job output before it is written or posted.

## Change (bin/k3dm-webhook only — test/utility surface, no security-relevant behavior change)

1. Module-level registry + helpers near the other top-level helpers:
   - `_REDACT_VALUES = set()`
   - `_register_secret(value)` — add non-empty str values of length ≥ 4; returns the value (pass-through so it can wrap returns).
   - `_redact_secrets(text)` — replace every registered value in `text` with `***REDACTED***`; no-op on empty.
2. Register at the secret-read helpers so values enter the registry as they are fetched:
   - `_smoke_secret(...)` — wrap the successful decoded return.
   - nested `_vault_secret(path, key)` inside `_smoke_test_logins` — wrap its return.
   - the direct env password reads used by the smoke path (`K3DM_SMOKE_KC_PASS`, `K3DM_SMOKE_ARGOCD_PASS`, Grafana) — register when non-empty.
3. Apply the barrier on the full joined output **before** truncation and before `write_text`/`_slack_post`/`_notify_job`. Broadened beyond the two CodeQL-flagged blocks to **all five status `_finish` handlers** that post kubectl diagnostics (same sink pattern, `output`/`report = _redact_secrets("".join(lines))`) — consistent defense, avoids the other three being flagged later.

## Caveats (report honestly)

- CodeQL's GitHub check may **not** flip to green from a `str.replace` sanitizer — code scanning does not treat `.replace()` as a taint barrier and does not honor inline suppressions by default. The value of this change is the genuine defense-in-depth; if the check stays red it is confirmation of the FP with the barrier in place, and closing it then needs a UI/API dismiss (needs `security_events` scope). CodeQL is **not** a required check on `main` (`required_status_checks: []`), so it does not block merge either way.
- After landing, the live webhook must be restarted to pick up the change: `make restart-webhook`.

## Definition of Done

- [ ] `_redact_secrets`/`_register_secret`/`_REDACT_VALUES` added; secrets registered at the read helpers.
- [ ] Barrier applied in both flagged `_finish` blocks before write/post.
- [ ] `python3 -c "import ast; ast.parse(open('bin/k3dm-webhook').read())"` parses; webhook BATS (`scripts/tests/lib/webhook.bats`) green.
- [ ] Pushed; CodeQL re-checked and result reported (green, or FP-confirmed with barrier in place).
- [ ] memory-bank updated.

## What NOT to Do

- Do NOT weaken or remove the login smoke checks.
- Do NOT edit the external `webhook.render` module in this fix (keep scope to the flagged file).
- Do NOT log or print any registered secret value.
