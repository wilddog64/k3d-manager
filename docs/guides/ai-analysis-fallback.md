# Webhook AI analysis fallback

The webhook tries the configured AI candidates in order. The default order is `agy,gemini`.
`agy` and `gemini-cli` have separate credentials: agy uses OAuth through
`antigravity.google/oauth-callback`, while this host's gemini-cli uses an API key. A working
credential for one does not prove that the other works.

## Configuration

- `K3DM_AI_BIN_ORDER` sets the comma-separated candidate order.
- `K3DM_GEMINI_BIN` pins one candidate and disables fallback, preserving smoke-test behavior.
- `K3DM_ANALYSIS_MODEL` selects the agy model; the default is `gemini-3.8-flash-medium`.
- `K3DM_ANALYSIS_MODEL_GEMINI` optionally selects gemini-cli's model.
- `K3DM_AI_TOTAL_BUDGET_S` bounds the total candidate time.

The webhook does not invent a gemini-cli model ID. When `K3DM_ANALYSIS_MODEL_GEMINI` is unset,
it omits `--model` and lets gemini-cli use its own default. It passes `--skip-trust` because a
headless invocation from an untrusted working directory otherwise exits before reaching the API.

Known unavailable-candidate signatures are classified as `not-logged-in`, `auth-timeout`,
`bad-api-key`, `untrusted-dir`, `unknown-model`, or `headless-tool-denied`. Nonzero exits and
missing binaries are also unavailable. If no candidate serves, the webhook returns only a
reason-bearing sentinel; raw CLI output, including OAuth URLs, is never returned.

| Slack sentinel | Meaning | Triage |
| --- | --- | --- |
| `AI analysis unavailable — agy: not-logged-in` | agy needs login | Authenticate agy from a real TTY |
| `… bad-api-key` | gemini-cli's key is invalid | Repair the gemini-cli API key |
| `… unknown-model` | The requested agy model is retired | Run `agy models` and update the configured model |

Hermes' `K3DM_HERMES_LLM_PROVIDER` is inert because Hermes does not pass an LLM to its
correlator. This guide does not apply to Hermes.

## `agy` prompts for the login password on every run

**Symptom.** Every `agy` run, including the webhook's under launchd, pops up a macOS dialog for your
login password. "Always Allow" does not stop it.

**Cause.** `agy` decrypts its credentials with two keychain items, both with service
`Antigravity Safe Storage` (accounts `Antigravity` and `Antigravity Key`). The Antigravity desktop app
created them, so their trusted-application list holds only `identifier "com.google.antigravity"`. The
CLI at `~/.local/bin/agy` is signed with `Identifier=cli` (team `EQHXZ8M8AV`), so it never matches. The
partition list (`apple-tool:, apple:, teamid:EQHXZ8M8AV`) is already correct and is not the problem.

**Fix (once, in Keychain Access on the M4).** For **each** of the two items: Access Control → keep
"Confirm before allowing access" → **+** → ⌘⇧G → `~/.local/bin/agy` → Add → Save Changes. Do not
choose "Allow all applications".

**Check.** `security dump-keychain -a ~/Library/Keychains/login.keychain-db | grep -A25 '"Antigravity Safe Storage"'`
lists a second requirement (identifier `cli`, team `EQHXZ8M8AV`) on both items. Then run it the way
launchd does:

```bash
launchctl submit -l k3dm.agy-test -o /tmp/agy-test.out -e /tmp/agy-test.err -- \
  ~/.local/bin/agy --model gemini-3.8-flash-medium --prompt 'Reply with exactly: PONG'
sleep 20; cat /tmp/agy-test.out /tmp/agy-test.err; launchctl remove k3dm.agy-test
```

`PONG` with no dialog means it is fixed (verified 2026-10-01). The requirement is tied to the signing
identity, not the build, so it should survive `agy` updates. If the prompt returns, the `cli` entry is
gone; repeat the fix.
