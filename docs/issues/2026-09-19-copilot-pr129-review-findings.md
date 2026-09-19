# Copilot review findings — PR #129

**PR:** [#129](https://github.com/wilddog64/k3d-manager/pull/129) — `fix(tests): narrow 42 whole-line grep -F source assertions across 8 BATS suites`
**Date:** 2026-09-19
**Fix commit:** `5bf07f2c`
**Findings:** 3 raised by Copilot (2 Medium, 1 Low), all valid; **1 further instance found by Claude** while checking the rest of the diff for the same shape.

The headline: this PR's entire purpose was to replace assertions that gate *formatting* with
assertions that gate *requirements*. Copilot found that three of the 42 conversions had gone
one step too far and stopped gating a requirement as well — the exact failure the spec's own
"narrowing, not weakening" rule forbids. They were invisible to the suite: each still matched a
distinctive token, so each stayed green.

---

## Finding 1 (Medium) — `namespace`, `payload` and `meta` dropped from the worker assertions

`scripts/tests/plugins/slack_slash_commands.bats:146`, test
`"slack relay parses cluster-diagnose payloads"`.

Copilot: *"The narrowed regexes no longer assert two semantics that were present in the original
whole-line checks: (1) that the `get-pods` payload includes `namespace`, and (2) that the
diagnostics relay call passes both `payload` and `meta`. As written, the test would still pass if
`namespace` were dropped or if `meta` stopped being forwarded to `relay()`."*

Before:
```bash
run grep -Eq "provider: target, action: 'get-pods'" "${WORKER}"
run grep -Eq "relay\('/api/v1/diagnostics'" "${WORKER}"
```

After:
```bash
run grep -Eq "provider: target.*action: 'get-pods'.*namespace" "${WORKER}"
run grep -Eq "relay\('/api/v1/diagnostics',\s*payload,\s*meta" "${WORKER}"
```

**Root cause.** The conversion kept the token that made the line *identifiable* and dropped the
tokens that made it *correct*. Those are different jobs, and one regex was doing only the first.
Picking a distinctive substring is how you locate the statement; it is not how you decide what to
assert about it.

---

## Finding 2 (Medium) — `_attempt<=30` was still layout-dependent

`scripts/tests/lib/provider_contract.bats:961`.

Copilot: *"This assertion is still sensitive to formatting (`_attempt<=30` with no whitespace)…
consider allowing optional whitespace around the comparison."*

```bash
-  run grep -Eq '_attempt<=30' "${_ACG_STATE_DIR}/bin/argocd-port-forward.sh"
+  run grep -Eq '_attempt\s*<=\s*30' "${_ACG_STATE_DIR}/bin/argocd-port-forward.sh"
```

**Root cause.** A narrowing measured against the *current* spelling rather than the range of
spellings that satisfy the requirement. `_attempt <= 30` is the same retry budget and would have
reddened the gate — a smaller version of the defect the whole PR exists to remove.

---

## Finding 3 (Low) — CHANGELOG said "shell source" for a change spanning four languages

`CHANGELOG.md:7`. Reworded to "a whole line of source code", now naming Bash,
Python (`bin/k3dm-webhook`, `scripts/lib/webhook/config.py`), JavaScript
(`workers/slack-relay/index.js`) and rendered `*.sh.tmpl` wrappers.

**Root cause.** The entry was written from the suites' own idiom (BATS, therefore shell) rather
than from the diff's grep *targets*, half of which are not shell.

---

## Finding 4 (found by Claude, not Copilot) — `delete=False` dropped from the ask-transcript test

`scripts/tests/lib/webhook.bats:601`, test
`"webhook ask subprocess captures transcripts in the k3d-manager run dir"`.

```bash
-    run grep -Eq 'prefix="k3dm-ask-".*dir=str\(RUN_DIR\)' …
+    run grep -Eq 'prefix="k3dm-ask-".*delete=False.*dir=str\(RUN_DIR\)' …
```

Because two instances of the same shape appeared in one file, the remaining 40 conversions were
re-read looking for it rather than trusting that Copilot had found them all. `delete=False` is
load-bearing: with `delete=True` the `NamedTemporaryFile` is destroyed on close, so the test would
still pass while the transcript it claims to capture no longer exists.

### Three further candidates deliberately left narrowed

The judgement is whether the dropped token is part of what the `@test` name claims:

| Site | Dropped | Test name | Verdict |
|---|---|---|---|
| `argocd.bats:239` | `-n "${NAMESPACE}"` | *"…falls back when the requested context is missing"* | keep narrowed — the claim is context fallback |
| `webhook.bats:318` | `"thread_ts": thread_ts` | *"…accepts provider dispatch"* | keep narrowed — the claim is provider dispatch |
| `webhook.bats:547` | `.local` / `share` | *"…defines policy and audit log"* | keep narrowed — the claim is that it is defined, not where |

Same diff, opposite verdicts — which is why this cannot be swept by pattern.

---

## Verification

Every restored token was mutation-verified rather than assumed: the assertion must pass against
the real file **and fail** against a scratch copy with that token removed.

| Restored token | Real file | Token stripped | Gates? |
|---|---|---|---|
| `namespace` in payload | PASS | FAIL | ✅ |
| `payload, meta` in relay | PASS | FAIL | ✅ |
| `delete=False` | PASS | FAIL | ✅ |
| `_attempt <= 30` | PASS | FAIL (budget → 99) | ✅ |

Plus the tolerance Copilot asked for: the reformatted `_attempt <= 30` still matches.

`make test` 947 ok / 0 not ok; `make test-bin` 108 ok / 0 not ok — unchanged from `main`.

---

## Process notes

1. **Add to the audit spec's rule set:** when narrowing an assertion, check each dropped token
   against the `@test` name. A token the name claims must survive the narrowing; a token it does
   not claim may go. "It still matches something distinctive" is not the test.
2. **A green suite cannot detect a weakening** — by construction it passes. Only mutation can.
   The audit already knew this for the conversions it mutation-tested; the three defects were in
   sites where the conversion looked obviously safe and was therefore not mutated. *Obviously
   safe* is the category that needs the check.
3. **One finding of this class implies a sweep, not a patch.** Fixing only Copilot's two would
   have shipped the third. Recorded in
   `docs/bugs/2026-09-18-bats-whole-line-grep-assertion-audit.md`.
