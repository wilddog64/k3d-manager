# `_call_gemini` cannot tell failure from output — an agy auth failure is posted to Slack as the AI's answer

**Filed:** 2026-09-23
**Branch:** `k3d-manager-v1.37.0`
**Status:** OPEN — spec only, assigned to Codex.
**Severity:** medium — all 7 webhook AI-analysis consumers return a CLI error string in place of
analysis. `/ask gemini` posted a live Google OAuth URL into Slack while agy was unauthenticated,
and posts a model-drift error now that it is.
**Found while:** the operator reported that the `agy` OAuth URL does not complete while
`gemini-cli` authenticates fine, and asked whether k3d-manager is exposed.

> **Update, 2026-09-23, after filing.** The operator restored agy's login from a real TTY
> (`agy --prompt 'hi'`), so the auth-failure mode is no longer reproducible on this host. It
> changed nothing about this spec: within minutes the *same* defect resurfaced as a **model-drift**
> failure (S0 below), which is the third distinct string to be posted to Slack as analysis. The
> tests here drive fake CLIs, so none of them depend on any live login. If anything the sequence
> is the argument for the fix — the mechanism outlived the symptom by under an hour.

## Summary

`agy` on this host is not logged in. Reproduced directly:

```
$ agy --model gemini-3.5-flash-medium --prompt 'Reply with exactly: PONG'
Authentication required. Please visit the URL to log in:
  https://accounts.google.com/o/oauth2/auth?...&redirect_uri=https%3A%2F%2Fantigravity.google%2Foauth-callback&...
Waiting for authentication (timeout 60s)...
error: authentication failed or timed out
```

`~/.gemini/antigravity-cli/log/cli-20260923_162534.log` confirms the same session from the
operator's own attempt:

```
I0923 16:25:37.000301 auth_manager.go:158] Starting OAuth authentication flow
I0923 16:25:37.000413 browser.go:56]      consumerOAuth: starting OAuth flow
W0923 16:26:35.262187 cache.go:135]       ... error getting token source: You are not logged into Antigravity.
```

The flow starts and never returns; every subsequent minute logs `You are not logged into
Antigravity.` until the process exits at 18:00.

**Why `gemini` works and `agy` does not — they do not share an auth mechanism.**
`~/.gemini/settings.json` has `security.auth.selectedType = gemini-api-key` and
`~/.gemini/google_accounts.json` has `active: null`: gemini-cli is on an **API key** and never
performs a browser OAuth. `agy` has no API-key mode, and its redirect is
`https://antigravity.google/oauth-callback` — a **remote** callback, not a localhost loopback,
so there is no local path to fall back to when that hop fails. Authenticating one CLI proves
nothing about the other. That asymmetry is also what makes a fallback worth building: it
switches credential *type*, not just binary.

## The actual defect is not the auth failure

`_call_gemini` (`bin/k3dm-webhook:1297`) discards the child's exit status:

```python
done_pid, _ = os.waitpid(child_pid, os.WNOHANG)   # :1339 — status thrown away
```

and then returns whatever landed in the output file. Its only guards are a `headless mode` +
`auto-denied` pair, an emptiness check, and a `^Warning:` strip. The string
`Authentication required. Please visit the URL to log in: https://accounts.google.com/...`
passes all three and is returned as the analysis.

Consequences, measured against the live code:

- **`/ask gemini` posts the OAuth URL to Slack.** `:3319` → `:3322`
  `_finish(f"🤖 *gemini:* {answer}")`. The URL carries the PKCE `code_challenge`, `state` and
  `client_id`. These are not long-lived credentials, but a dead auth URL delivered as an AI
  verdict is not an answer, and it should never have reached a channel.
- **The stall detector does the same.** `:732` → `:734` `_notify_job(... *AI:* {analysis})`.
- **Five further consumers** at `:1372`, `:1563`, `:2465`, `:2517`, `:2739`, `:3091` inherit it.

This is the third instance of one structural defect, not a new bug:

| Bug doc | Failure that got posted as analysis |
|---|---|
| `docs/bugs/v1.23.0-bugfix-webhook-agy-model-drift.md` | `model gemini-2.5-flash is not recognized as a known model` |
| `docs/bugs/v1.24.0-bugfix-webhook-gemini-headless-permission.md` | `a tool required the command permission that headless mode cannot prompt for` |
| this doc | `Authentication required. Please visit the URL to log in: …` |

Each of the first two was fixed by hard-coding a rescue for that one string. The common cause —
`_call_gemini` has no notion of "this candidate is unavailable" — was never addressed, so the
next unavailability mode surfaced in Slack again. **Fix the mechanism, and make an unavailable
candidate fall through to another one rather than dead-end.**

## Hermes is not affected, and its LLM knob is inert

`bin/k3dm-hermes:132` constructs `Correlator(..., provider=os.environ.get("K3DM_HERMES_LLM_PROVIDER", "gemini"))`,
but `:138` calls `correlator.process(records, state)` and the signature is
`process(self, records, state, llm=None, today=None)` with enrichment guarded by
`if llm and self.provider != "claude" and ...` (`scripts/lib/hermes/correlator.py:55`). No call
site ever passes `llm`, so enrichment has never run in production. Hermes needs no change here,
and `K3DM_HERMES_LLM_PROVIDER` is a dead knob — recorded so a future reader does not mistake it
for a working seam.

## Two gotchas that would break a naive fallback

Both reproduced on this host, not inferred:

1. **gemini-cli's trust gate.** From an untrusted cwd,
   `gemini --model X --prompt Y` exits **55** with `Gemini CLI is not running in a trusted
   directory` and never reaches the API. A headless call from a job dir needs `--skip-trust`
   (or `GEMINI_CLI_TRUST_WORKSPACE=true`).
2. **Model IDs do not transfer.** `gemini-3.5-flash-medium` is an Antigravity ID. Whether
   gemini-cli accepts it is **unverified** — the probe failed on the API key before model
   validation. Therefore this spec **must not invent a gemini model ID**: omit `--model`
   entirely for the gemini candidate unless `K3DM_ANALYSIS_MODEL_GEMINI` is set, and let
   gemini-cli use its own default.

## What is NOT in scope

- **`scripts/plugins/gemini.sh` / `_agy_prompt`.** It already checks the exit code and fails
  loudly, so it is not silently wrong. More importantly its prompts instruct the agent to write
  and `node`-execute a Playwright script against CDP `localhost:9222`; gemini-cli's
  `defaultApprovalMode` is `plan` (read-only), so a fallback there requires granting it
  `--yolo`. That is an authorization decision for the operator, not a default to ship.
- **The `🤖 *gemini:*` label at `:3322`** is hardcoded and is already wrong when agy serves the
  answer. Correcting it needs the serving binary threaded back to the route; deferred to keep
  this change's blast radius at one function.
- **Stale `gemini-2.5-flash` examples in `docs/howto/gemini.md:74,93`** — that is the
  browser-automation path, covered by the v1.23.0 drift docs.
- **Restoring agy's login.** Operator-only; see "Operator runbook" below.

---

## S0 — the model default is dead again (live break, fix first)

Verified on this host at 2026-09-23, immediately after the login was restored:

```
$ agy --model gemini-3.5-flash-medium --prompt 'Reply with exactly: PONG'
error: invalid model selection (--model "gemini-3.5-flash-medium" --effort ""):
model gemini-3.5-flash-medium is not recognized as a known model or custom model in settings
Available models:
  Gemini 3.8 Flash (High) / (Medium) / (Low)
  Gemini 3.7 Flash (High) / (Medium) / (Low)
  Gemini 3.6 Flash (High) / (Medium) / (Low)
  Gemini 3.1 Pro (High) / (Low)
  Claude Sonnet 4.6 (Thinking) / Claude Opus 4.6 (Thinking) / GPT-OSS 120B (Medium)
exit=1

$ agy --model gemini-3.8-flash-medium --prompt 'Reply with exactly: PONG'
PONG
exit=0
```

`gemini-3.5-flash-medium` — the default set by the v1.23.0 drift fix — has been retired. So
**every webhook AI analysis is broken right now even with a healthy login**, posting the model
error to Slack. This is `docs/bugs/v1.23.0-bugfix-webhook-agy-model-drift.md` recurring, which is
precisely why S1/S2 must classify it as "candidate unavailable" instead of rescuing one more
literal string.

**File:** `bin/k3dm-webhook`

Exact old line (`:224`):

```python
GEMINI_MODEL = os.environ.get("K3DM_ANALYSIS_MODEL", "gemini-3.5-flash-medium")
```

Exact new line:

```python
GEMINI_MODEL = os.environ.get("K3DM_ANALYSIS_MODEL", "gemini-3.8-flash-medium")
```

`gemini-3.8-flash-medium` is verified working above — do not substitute an ID from the display
list without probing it, and do not add `--effort` (agy echoes it in its own error text; the
webhook does not pass it).

> `scripts/plugins/gemini.sh`'s `_GEMINI_MODELS` chain also leads with the retired
> `gemini-3.5-flash-medium`, but `_agy_prompt` already treats `ModelNotFoundError` as
> "try the next model" and its second entry `gemini-3.6-flash-medium` is still valid — so that
> path self-heals at the cost of one wasted attempt. Deliberately left alone; it is not a defect
> and touching it would widen this change.

## S1 — a candidate resolver

**File:** `bin/k3dm-webhook`

Insert immediately **above** `def _call_gemini(prompt):` (currently `:1297`).

```python
_AI_UNAVAILABLE_SIGNATURES = (
    ("not-logged-in", "not logged into Antigravity"),
    ("not-logged-in", "Authentication required. Please visit the URL"),
    ("auth-timeout", "authentication failed or timed out"),
    ("bad-api-key", "API key not valid"),
    ("bad-api-key", "API_KEY_INVALID"),
    ("untrusted-dir", "not running in a trusted directory"),
    ("unknown-model", "is not recognized as a known model"),
    ("headless-tool-denied", "auto-denied"),
)


def _ai_classify_failure(exit_code, raw):
    """Return a short reason string if this candidate is unavailable, else None.

    A nonzero exit is authoritative. The signature table additionally catches CLIs that
    report an unusable state on stdout and still exit 0.
    """
    for reason, needle in _AI_UNAVAILABLE_SIGNATURES:
        if needle in raw:
            return reason
    if exit_code != 0:
        return f"exit {exit_code}"
    return None


def _ai_candidates():
    """Ordered [(name, argv_prefix)] to try. K3DM_GEMINI_BIN pins one and disables fallback."""
    import shutil
    pinned = os.environ.get("K3DM_GEMINI_BIN")
    names = [pinned] if pinned else [
        item.strip() for item in
        os.environ.get("K3DM_AI_BIN_ORDER", "agy,gemini").split(",") if item.strip()
    ]
    out = []
    for name in names:
        resolved = shutil.which(name) or name
        if not os.path.isfile(resolved):
            out.append((name, None))
            continue
        argv = [resolved]
        base = os.path.basename(resolved)
        if base == "gemini":
            argv.append("--skip-trust")
            model = os.environ.get("K3DM_ANALYSIS_MODEL_GEMINI")
            if model:
                argv += ["--model", model]
        else:
            argv += ["--model", GEMINI_MODEL]
        out.append((name, argv))
    return out
```

`K3DM_GEMINI_BIN` keeping its pin-one-binary meaning is **required**, not a nicety:
`bin/smoke-test-webhook:59` sets `K3DM_GEMINI_BIN="/usr/bin/true"` and must keep working
unchanged.

## S2 — make `_call_gemini` iterate candidates and classify failures

Replace the body of `_call_gemini` from `import shutil, tempfile, time` (`:1303`) through
`return f"agy error: {exc}"` (`:1357`) with the block below. Keep the `def` line and rewrite the
docstring as shown. The signature and return type are unchanged: one string, so all 7 call
sites stay untouched.

```python
def _call_gemini(prompt):
    """Run the first available AI CLI candidate and return its answer text.

    Tries each candidate from _ai_candidates() in order. A candidate that cannot serve —
    missing binary, nonzero exit, or a known unavailability signature — is skipped and the
    next is tried. When none can serve, returns a sentinel naming each reason and never the
    candidate's raw output, which may contain an OAuth URL.

    Uses os.posix_spawn (no fork) to avoid macOS NEF atfork SIGSEGV.
    Output is captured via a temp file rather than a pipe.
    """
    import tempfile, time
    env = {**os.environ, "TERM": "xterm-256color"}
    guarded = (
        "You are analyzing pre-collected data in a HEADLESS session with no "
        "interactive approver. Do NOT run any commands or call any tools — a tool "
        "call is auto-denied and yields no answer. Answer ONLY from the text below; "
        "if it is insufficient, say so briefly.\n\n" + prompt
    )
    total_budget = float(os.environ.get("K3DM_AI_TOTAL_BUDGET_S", "180"))
    started = time.monotonic()
    failures = []
    for name, argv in _ai_candidates():
        if argv is None:
            failures.append(f"{name}: not installed")
            continue
        remaining = total_budget - (time.monotonic() - started)
        if remaining < 15:
            failures.append(f"{name}: skipped, time budget exhausted")
            continue
        try:
            with tempfile.NamedTemporaryFile(
                prefix="k3dm-ai-", suffix=".out", delete=False, mode="w"
            ) as tmp:
                tmp_path = tmp.name
            file_actions = [
                (os.POSIX_SPAWN_OPEN, 1, tmp_path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600),
                (os.POSIX_SPAWN_DUP2, 1, 2),
            ]
            child_pid = os.posix_spawn(
                argv[0], argv + ["--prompt", guarded], dict(env),
                file_actions=file_actions, setsid=True,
            )
            deadline = time.monotonic() + remaining
            exit_code = None
            while True:
                if time.monotonic() > deadline:
                    try:
                        os.kill(child_pid, 9)
                        os.waitpid(child_pid, 0)
                    except OSError:
                        pass
                    exit_code = -9
                    break
                try:
                    done_pid, status = os.waitpid(child_pid, os.WNOHANG)
                    if done_pid != 0:
                        exit_code = os.waitstatus_to_exitcode(status)
                        break
                except ChildProcessError:
                    exit_code = 0
                    break
                time.sleep(0.5)
            raw = Path(tmp_path).read_text(errors="replace").strip()
            Path(tmp_path).unlink(missing_ok=True)
        except Exception as exc:
            failures.append(f"{name}: {type(exc).__name__}")
            continue
        if exit_code == -9:
            failures.append(f"{name}: timed out")
            continue
        reason = _ai_classify_failure(exit_code, raw)
        if reason:
            failures.append(f"{name}: {reason}")
            continue
        raw = re.sub(r'(?m)^Warning:.*\n?', '', raw).strip()
        if not raw:
            failures.append(f"{name}: no output")
            continue
        cleaned = re.sub(r'(?:^|\n)\s*\w+\([^)]{0,500}\)\s*', ' ', raw, flags=re.MULTILINE)
        cleaned = re.sub(r'<ctrl[^>]*>', '', cleaned).strip()
        return cleaned or raw
    return "AI analysis unavailable — " + "; ".join(failures)
```

Three properties are load-bearing and each has a test and a mutation below:

1. **The exit status is used.** `done_pid, status = os.waitpid(...)` plus
   `os.waitstatus_to_exitcode`. This is the discarded-`_` bug.
2. **The sentinel carries reasons, never raw output.** The OAuth URL must not be able to reach
   a caller under any path.
3. **`K3DM_GEMINI_BIN` pins exactly one candidate.** Back-compat with `smoke-test-webhook`.

## Tests

New file `scripts/tests/bin/webhook_ai_fallback.py`. Follow the existing idiom in
`scripts/tests/bin/webhook_redaction.py` exactly: `SourceFileLoader` the `bin/k3dm-webhook`
module, `unittest.TestCase`, no network, no cluster. Build fake CLIs as executable shell
scripts in a `tempfile.TemporaryDirectory()` and put that directory first on `PATH`.

A fake that reproduces the live agy failure:

```sh
#!/bin/sh
echo "Authentication required. Please visit the URL to log in:"
echo "  https://accounts.google.com/o/oauth2/auth?client_id=1071006060591-x.apps.googleusercontent.com&state=abc"
echo "error: authentication failed or timed out"
exit 1
```

Required cases:

1. **Fallback happens.** `agy` fake fails as above, `gemini` fake prints `PONG` and exits 0 →
   `_call_gemini` returns `PONG`.
2. **No OAuth URL ever escapes.** Both candidates fail → the result starts with
   `AI analysis unavailable`, contains `not-logged-in`, and `accounts.google.com` is **not**
   in it.
3. **A nonzero exit is a failure even when the output looks like an answer.** `agy` fake prints
   `STALLED — waiting on a pod` and exits 1; `gemini` fake prints `PROGRESSING` → the result is
   `PROGRESSING`. This is the guard for the discarded exit status.
4. **`K3DM_GEMINI_BIN` pins one candidate and disables fallback.** Set it to the failing `agy`
   fake with a healthy `gemini` fake also on `PATH` → the result is the sentinel, and the
   `gemini` fake was never invoked (assert via a marker file it would have written).
5. **Trust-gate classification.** `gemini` fake prints
   `Gemini CLI is not running in a trusted directory` and exits 55 → classified
   `untrusted-dir`, next candidate tried.
6. **Model-drift classification.** A fake printing
   `model gemini-2.5-flash is not recognized as a known model` and exiting 0 → classified
   `unknown-model` and skipped despite the zero exit. This is the v1.23.0 failure, now
   funnelled through one mechanism.
7. **A healthy first candidate never spawns the second.** `agy` fake succeeds; assert the
   `gemini` fake's marker file does not exist.
8. **Candidate argv shape.** The `gemini` candidate receives `--skip-trust` and **no**
   `--model` when `K3DM_ANALYSIS_MODEL_GEMINI` is unset; it receives `--model` when it is set;
   the `agy` candidate receives `--model ${GEMINI_MODEL}`. Assert by having the fake dump
   `"$@"` to a file.

Every test must clear `K3DM_GEMINI_BIN`, `K3DM_AI_BIN_ORDER`, `K3DM_ANALYSIS_MODEL_GEMINI` and
`K3DM_AI_TOTAL_BUDGET_S` in `setUp`/`tearDown` so ordering cannot leak state.

Also confirm the two existing assertions in `scripts/tests/lib/webhook.bats:575-579` still
pass, or update them in the same commit if the literal they grep for moved — they pin
`os.environ.get("K3DM_GEMINI_BIN", "agy")` and
`return "agy CLI not found — skipping AI analysis"`, and **both strings are removed by S1/S2**.
Replace them with assertions on the new behaviour (the default order is `agy,gemini`; the
sentinel prefix is `AI analysis unavailable`). Do not delete the tests.

## Mutations — prove each guard can fail

Reintroduce one at a time, run the suite, paste the red, restore, confirm `git diff --quiet`.

- **M1** — revert `done_pid, status = os.waitpid(...)` / `os.waitstatus_to_exitcode(status)` to
  `done_pid, _ = os.waitpid(...)` with `exit_code = 0` → **test 3 red**.
- **M2** — delete the `("not-logged-in", "Authentication required. Please visit the URL")` and
  `("not-logged-in", "not logged into Antigravity")` rows from `_AI_UNAVAILABLE_SIGNATURES`
  → **test 2 red** (the fake exits 1, so this must red on the *signature*, not the exit code;
  if it stays green the assertion is testing the wrong thing and the test must be fixed).
- **M3** — make `_ai_candidates` ignore the `K3DM_GEMINI_BIN` pin and always use
  `K3DM_AI_BIN_ORDER` → **test 4 red**.

## Docs

New `docs/guides/ai-analysis-fallback.md`:

- the candidate chain, and that `agy` and `gemini-cli` hold **separate credentials** — agy is
  OAuth-only against `antigravity.google/oauth-callback`, gemini-cli here is on an API key, so
  one working says nothing about the other;
- the env vars: `K3DM_AI_BIN_ORDER`, `K3DM_GEMINI_BIN` (pins one, disables fallback),
  `K3DM_ANALYSIS_MODEL`, `K3DM_ANALYSIS_MODEL_GEMINI`, `K3DM_AI_TOTAL_BUDGET_S`;
- the signature table and what each reason means;
- **why there is no invented gemini model ID** — unverified, so `--model` is omitted;
- gemini-cli's trust gate and the `--skip-trust` requirement;
- a triage table: Slack shows `AI analysis unavailable — agy: not-logged-in` → the CLI needs a
  login, the webhook is healthy; `… bad-api-key` → gemini's key; `… unknown-model` → run
  `agy models`;
- that Hermes' `K3DM_HERMES_LLM_PROVIDER` is inert and this guide does not apply to it.

Link it from `README.md` beside the `Alerting` guide line. Add a `### Fixed` entry under
`[Unreleased]` in `CHANGELOG.md`.

## Operator runbook (not Codex)

**Done 2026-09-23** — agy's login was restored by the operator from a real TTY
(`agy --prompt 'hi'`, then paste the authorization code at the
`Or, paste the authorization code here and press Enter:` prompt). Kept here because the
credential is machine-local and unmanaged: it will need repeating, and Claude cannot do it —
Claude's shell has no TTY.

After this change is deployed, confirm end to end:

```
/ask gemini is the hub healthy
```

The answer must be prose, or an `AI analysis unavailable — …` sentinel. If an
`accounts.google.com` URL ever appears in Slack again, this fix has regressed.

## Definition of Done

- [ ] S0 applied — `grep -c 'gemini-3.5-flash-medium' bin/k3dm-webhook` → 0.
- [ ] S1 and S2 applied to `bin/k3dm-webhook`; all 7 call sites unchanged.
- [ ] `grep -c 'accounts.google.com' bin/k3dm-webhook` → 0; no raw candidate output can reach
      the sentinel path.
- [ ] `scripts/tests/bin/webhook_ai_fallback.py` — 8 cases green.
- [ ] `scripts/tests/lib/webhook.bats` green, with the two stale literal assertions replaced.
- [ ] M1, M2, M3 each reproduced, red pasted, file restored.
- [ ] `make test` green, and `pytest` green (`make test` alone is not the CI gate).
- [ ] `docs/guides/ai-analysis-fallback.md` added, linked from `README.md`,
      `make check-doc-links` OK.
- [ ] `CHANGELOG.md` `[Unreleased] → ### Fixed` entry.
- [ ] memory-bank updated with the commit SHA.

Commit message:

```
fix(webhook): fall back between AI CLIs instead of posting auth errors as analysis

_call_gemini discarded the child exit status and returned whatever the CLI
wrote, so an unauthenticated agy made /ask gemini post a live Google OAuth URL
to Slack and made all 7 analysis consumers return an error string as the
answer. Adds an ordered candidate chain (agy then gemini), classifies missing
binaries, nonzero exits and known unavailability signatures as "this candidate
cannot serve", and returns a reason-only sentinel when none can. Folds the
v1.23.0 model-drift and v1.24.0 headless-deny rescues into the same mechanism
so each now falls through instead of dead-ending.
```

## Cross-references

- `docs/bugs/v1.23.0-bugfix-webhook-agy-model-drift.md` — first instance of the same mechanism.
- `docs/bugs/v1.24.0-bugfix-webhook-gemini-headless-permission.md` — second instance.
- `docs/bugs/v1.6.3-bugfix-gemini-cli-warnings-in-slack.md` — origin of the `^Warning:` strip
  this change preserves.
- `docs/howto/gemini.md` — the browser-automation path, deliberately untouched here.
