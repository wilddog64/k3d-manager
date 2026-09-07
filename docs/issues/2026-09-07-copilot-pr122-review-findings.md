# Copilot + CodeQL review findings — PR #122 (v1.31.0 Hermes preflight + token-expiry advisory)

**Date:** 2026-09-07
**PR:** [#122](https://github.com/wilddog64/k3d-manager/pull/122)
**Reviewers:** Copilot (2 findings, both fixed), github-advanced-security / CodeQL (1 finding, false positive)

---

## Finding 1 — preflight only inspects the single latest run (Copilot)

**Where:** `scripts/lib/hermes/preflight.py:28` — `actions/runs?per_page=1`

**Flagged:** `run_preflight` requested only the most recent run and then required
`conclusion == "success"` to pick a run to probe write scope against. If the latest run was
still in progress or had failed, `next(...)` raised `StopIteration` (caught) and preflight
returned exit 1 — reporting a scope failure that was really just "the latest run wasn't a
success", a false negative unrelated to the PAT.

**Fix:** widen the sample so a recent success is reliably found.

```python
# before
["gh", "api", f"/repos/{REPOSITORY}/actions/runs?per_page=1"]
# after
["gh", "api", f"/repos/{REPOSITORY}/actions/runs?per_page=30"]
```

**Root cause:** the write probe needs *a* successful run to POST `rerun-failed-jobs` against;
limiting the fetch to one run coupled preflight's verdict to the state of the newest run.

---

## Finding 2 — write-scope probe misreads empty/transport-error output as success (Copilot)

**Where:** `scripts/lib/hermes/preflight.py:41`

**Flagged:** `report["actions_write"] = "resource not accessible" not in write_output.lower()`
treated *any* output without that phrase as write-capable. On an empty output (network/auth
failure, `write_output == ""`), the substring test is trivially true, so preflight would
falsely report `actions_write: true`.

Note the probe deliberately does **not** key on the runner return code: a write-capable PAT
still gets a non-zero rc here because `rerun-failed-jobs` on a *successful* run returns a
business-logic error (`"This workflow run cannot be retried"`), not a scope error. So the fix
guards on output presence, not rc.

**Fix:**

```python
# before
report["actions_write"] = "resource not accessible" not in write_output.lower()
# after
report["actions_write"] = bool(write_output) and "resource not accessible" not in write_output.lower()
```

**Root cause:** the classifier assumed the probe always produced a GitHub response body;
an empty body from a transport failure fell through to the "not a scope error" branch.

**Coverage added:** `test_preflight_write_probe_empty_output_is_not_success` (empty output → false)
and `test_preflight_finds_success_beyond_latest_run` (a success beyond run[0] is used). Suite: 33 passed.

---

## Finding 3 — clear-text logging of sensitive information (CodeQL) — FALSE POSITIVE

**Where:** `bin/k3dm-hermes:128` — `print(json.dumps(report, sort_keys=True))` in the
`preflight` branch. Rule `py/clear-text-logging-sensitive-data` (severity high), alert #21.

**Analysis:** the printed `report` contains only booleans and the literal string `"pat"`.
`_secrets` stores `bool(keychain(<service>))` — a presence flag, never the secret value —
and the actual PAT flows only into `env = {"GH_TOKEN": keychain(GITHUB_SERVICE)}` passed to
the subprocess runner, which is never serialized into `report`. No secret value reaches the
`print`.

CodeQL's clear-text query is value-insensitive and does not model `bool(<secret>)` as a
taint barrier, so it follows the presence-flag derivation from the secret read into the logged
dict — the same family of taint-model false positives documented for this repo
(`str.replace` redaction tripping the same rule). CodeQL is **not** a required status check on
`main` (`required_status_checks: []`), so this does not block merge.

**Disposition:** surfaced to the maintainer for the accept-vs-dismiss decision — no code change
applied, since the printed output demonstrably carries no secret. If a green dashboard is
preferred over a documented false positive, the presence flags can be rederived through a
comparison CodeQL treats as a barrier (candidate: `len(keychain(<service>) or "") > 0`),
verified against a re-scan.

## Process note

Preflight probes that classify a remote capability from command output must (a) sample enough
history to find the run/state they need rather than binding to the newest item, and (b) treat
empty output as "unknown / not confirmed", never as the success branch. Add both to the
preflight/probe spec template.
