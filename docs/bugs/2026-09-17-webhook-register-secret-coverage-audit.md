# Bug — `_register_secret` coverage gaps in `bin/k3dm-webhook`

**Date:** 2026-09-17
**Branch:** `k3d-manager-v1.35.0`
**Severity:** Medium (defence-in-depth gap, no known live leak)
**Related:** `docs/bugs/2026-09-03-webhook-cleartext-secret-storage-codeql.md`
(CodeQL alerts #19/#20 — deliberately left OPEN, not dismissed)

---

## Background

`bin/k3dm-webhook` redacts job output through a runtime denylist:

- `_register_secret(value)` (line 1229) records a value in `_REDACT_VALUES`.
- `_redact_secrets(text)` (line 1242) scrubs every registered value with a
  precompiled `re.sub` alternation.

Five handlers build a `lines` list and write it through `_redact_secrets("".join(lines))`:

| Line | Handler |
|------|---------|
| 2517 | `_run_cluster_status` |
| 2744 | `_run_cluster_refresh` |
| 2831 | `_run_hostinger_status` |
| 2886 | `_run_hostinger_refresh` |
| 2932 | `_run_cluster_diagnostics` |

An audit of every value reaching `lines` found the smoke-login path is clean:
both fetch chokepoints register (`_smoke_secret` at 1813, `_smoke_vault_secret`
at 1853), the nine downstream `_register_secret` calls are belt-and-suspenders,
and `_smoke_code_flow` returns only classified status strings
(`"credentials rejected"`, `"required action pending"`, `"code received"`,
`f"HTTP {code}"`) — never the page body or the `Location` header.

Two concrete gaps remain. A third, structural one is **out of scope for this
spec** (see "Not in scope").

---

## Gap 1 — the webhook's own bearer token is never registered

`bin/k3dm-webhook:56` imports `_get_token` from the foundation lib. It is used
once, at line 3483:

```python
class _Handler(http.server.BaseHTTPRequestHandler):
    def _auth(self):
        token = _get_token()
        if not token:
            return False
        return hmac.compare_digest(
            self.headers.get("Authorization", ""),
            f"Bearer {token}"
        )
```

This is the only secret the process holds that `_redact_secrets` cannot see. It
is the *webhook control token* — the highest-value credential in the process,
since it authorises every `/run`, `/ask` and make-target dispatch. If any
handler ever echoes an environment dump, a reconstructed `curl` command, or a
`launchctl`/plist excerpt into `lines`, the token would pass through redaction
untouched.

There is no known path that echoes it today. This is a defence-in-depth fix:
register it at the one chokepoint that already reads it.

### Fix

Replace lines 3482–3489 exactly:

**Old:**
```python
    def _auth(self):
        token = _get_token()
        if not token:
            return False
        return hmac.compare_digest(
            self.headers.get("Authorization", ""),
            f"Bearer {token}"
        )
```

**New:**
```python
    def _auth(self):
        token = _register_secret(_get_token())
        if not token:
            return False
        return hmac.compare_digest(
            self.headers.get("Authorization", ""),
            f"Bearer {token}"
        )
```

`_register_secret` returns its argument unchanged and ignores non-string and
short values, so a `None` token still short-circuits on the next line exactly as
before. No behaviour change to the auth decision.

---

## Gap 2 — `_register_secret` drops values silently

```python
def _register_secret(value):
    global _REDACT_PATTERN
    if isinstance(value, str) and len(value) >= 4 and value not in _REDACT_VALUES:
        _REDACT_VALUES.add(value)
        _REDACT_PATTERN = None
    return value
```

Both guards are correct in intent — a non-string cannot be `re.escape`d, and a
1–3 character value would redact common substrings across the whole report. But
a caller that wraps a fetch in `_register_secret` and gets back an unregistered
value has **no way to know**. The call site reads as if redaction is guaranteed.

The realistic failure is a Vault key rename: `_smoke_vault_secret(path, key)`
returns `None` when `key` is absent, `_register_secret(None)` registers nothing,
the caller proceeds with `None`, and the handler reports a confusing auth
failure — with no signal that the redaction registration also no-oped. A missing
Vault key is the single most likely cause of a smoke-login regression, and today
it is silent on both axes.

### Fix

Replace the body of `_register_secret` (lines 1229–1239) exactly:

**Old:**
```python
def _register_secret(value):
    """Record a secret value so _redact_secrets can scrub it from any job output.

    Returns the value unchanged so callers can wrap a return in place. Short or
    non-string values are ignored to avoid over-broad redaction of common tokens.
    """
    global _REDACT_PATTERN
    if isinstance(value, str) and len(value) >= 4 and value not in _REDACT_VALUES:
        _REDACT_VALUES.add(value)
        _REDACT_PATTERN = None
    return value
```

**New:**
```python
def _register_secret(value):
    """Record a secret value so _redact_secrets can scrub it from any job output.

    Returns the value unchanged so callers can wrap a return in place. Short or
    non-string values are ignored to avoid over-broad redaction of common tokens;
    that skip is counted in _REDACT_SKIPPED so an unregistered fetch is visible
    without ever logging the value itself.
    """
    global _REDACT_PATTERN
    if isinstance(value, str) and len(value) >= 4:
        if value not in _REDACT_VALUES:
            _REDACT_VALUES.add(value)
            _REDACT_PATTERN = None
    else:
        _REDACT_SKIPPED[_redact_skip_reason(value)] += 1
    return value
```

Add these two definitions immediately **above** `_register_secret` (i.e. right
after the `_REDACT_PATTERN = None` line at 1226):

```python
_REDACT_SKIPPED = collections.Counter()


def _redact_skip_reason(value):
    """Classify why a value was not registered for redaction. Never returns the value."""
    if value is None:
        return "none"
    if not isinstance(value, str):
        return "not-str"
    return "too-short"
```

`collections` is **not** currently imported (verified — the stdlib block runs
`datetime`, `base64`, `hashlib` … at lines 4–21). Add exactly one line,
immediately before `import datetime` at line 4:

```python
import collections
```

Do not reorder or otherwise touch the rest of the import block, and do not add a
third-party dependency.

**The counter must never be rendered into `lines` by this change.** It exists so
a future diagnostics addition and the unit tests can assert on it. Adding it to
handler output is a separate decision, not part of this fix.

---

## Not in scope — the fetch-scoped registry limit

`_redact_secrets` can only scrub values **this process fetched** through
`_smoke_secret` / `_smoke_vault_secret`. Anything arriving from a subprocess —
`kubectl get secret -o yaml`, pod logs, `bin/cluster-status` output — is
invisible to the registry, because the webhook never saw the value to register
it.

This is a structural property of the denylist design, not a bug in any one call
site, and fixing it means either a pattern-based matcher (regex for JWTs, base64
blobs, `password:` YAML keys) or piping subprocess output through a scrubber.
Both are substantial designs with real false-positive risk, inside the most
security-sensitive file in the repo.

**Do not attempt this in this task.** It is tracked separately as a v1.35.0
item. A partial or improvised pattern matcher here would be worse than the
current honest limitation.

---

## Tests

`scripts/tests/bin/webhook_request_hardening.py` already loads `bin/k3dm-webhook`
as a module via `SourceFileLoader` — reuse that exact pattern.

Note: neither file under `scripts/tests/bin/` is wired into the `Makefile` or any
CI workflow today (verified — no references). Run them directly:

```bash
python3 scripts/tests/bin/webhook_request_hardening.py
python3 scripts/tests/bin/webhook_redaction.py
```

Create `scripts/tests/bin/webhook_redaction.py` with the same module-loading
preamble and these cases:

1. `_register_secret("supersecret")` returns `"supersecret"` and a subsequent
   `_redact_secrets("prefix supersecret suffix")` contains `"***REDACTED***"`
   and does **not** contain `"supersecret"`.
2. `_register_secret(None)` returns `None` and increments
   `_REDACT_SKIPPED["none"]` by exactly 1.
3. `_register_secret(b"bytes")` returns the bytes unchanged and increments
   `_REDACT_SKIPPED["not-str"]` by exactly 1.
4. `_register_secret("ab")` returns `"ab"` and increments
   `_REDACT_SKIPPED["too-short"]` by exactly 1; `_redact_secrets("cab")` returns
   `"cab"` unchanged (proves the short value was not registered).
5. Registering a second secret after a first invalidates the compiled pattern and
   both are redacted from one string (guards the `_REDACT_PATTERN = None` reset).
6. `_redact_secrets("")` and `_redact_secrets(None)` return their input unchanged.

Each test must clear shared state in `setUp` — `wh._REDACT_VALUES.clear()`,
`wh._REDACT_SKIPPED.clear()`, `wh._REDACT_PATTERN = None` — following the
`wh._rate_hits.clear()` precedent in the existing suite.

**Do not write a test that asserts on `_auth`.** It needs a live
`BaseHTTPRequestHandler` instance and a real keychain token; that is out of
reach for a unit test and must not be faked by monkey-patching `_get_token` into
returning a literal.

---

## Before You Start

1. Read `memory-bank/activeContext.md` and `memory-bank/progress.md`.
2. `git pull origin k3d-manager-v1.35.0`
3. Read `bin/k3dm-webhook` lines 1–80 (imports), 1220–1270 (registry), and
   3475–3495 (`_auth`) before editing.
4. Read `scripts/tests/bin/webhook_request_hardening.py` in full — match its
   module-loading preamble and test style exactly.

Branch (all work): `k3d-manager-v1.35.0`

---

## Definition of Done

- [ ] `_auth` wraps `_get_token()` in `_register_secret` (Gap 1).
- [ ] `_REDACT_SKIPPED` counter + `_redact_skip_reason` added; `_register_secret`
      counts every skip (Gap 2).
- [ ] `collections` imported if it was not already.
- [ ] `scripts/tests/bin/webhook_redaction.py` created with all 6 cases above.
- [ ] `python3 scripts/tests/bin/webhook_redaction.py` — all green, output pasted
      in the report.
- [ ] `python3 scripts/tests/bin/webhook_request_hardening.py` — still all green,
      output pasted (proves the module still imports).
- [ ] `python3 -c "import ast,sys; ast.parse(open('bin/k3dm-webhook').read())"` clean.
- [ ] CHANGELOG `[Unreleased]` gets a `### Fixed` entry naming both gaps.
- [ ] Commit message, verbatim:
      `fix(webhook): register control token and count unregistered redaction values`
- [ ] `git push origin k3d-manager-v1.35.0` — do NOT report done until the push
      succeeds and `git rev-parse origin/k3d-manager-v1.35.0` matches your commit.
- [ ] `memory-bank/activeContext.md` and `memory-bank/progress.md` updated with the
      commit SHA and status.
- [ ] Report back: commit SHA + both test outputs + the memory-bank lines you wrote.

---

## Rules

- `set -euo pipefail` on any new shell; double-quote every expansion.
- No secret value may be logged, printed, counted by value, or written into any
  handler output. `_redact_skip_reason` returns a fixed classification string and
  must never interpolate `value`.
- Minimal patch — no unsolicited refactors of the redaction path, no reordering
  of existing functions, no changes to the five `_redact_secrets` call sites.
- Do NOT touch `scripts/lib/foundation/` or `scripts/lib/acg/`.

## What NOT to Do

- Do NOT create a PR.
- Do NOT merge, and do NOT commit to `main`.
- Do NOT force-push.
- Do NOT skip pre-commit hooks (`--no-verify`).
- Do NOT modify files outside: `bin/k3dm-webhook`,
  `scripts/tests/bin/webhook_redaction.py`, `CHANGELOG.md`,
  `memory-bank/activeContext.md`, `memory-bank/progress.md`.
- Do NOT implement the subprocess-output scrubber or any pattern-based secret
  matcher (see "Not in scope").
- Do NOT dismiss or otherwise touch CodeQL alerts #19/#20.
- Do NOT render `_REDACT_SKIPPED` into any handler's `lines` output.
