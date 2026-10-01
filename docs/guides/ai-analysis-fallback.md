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
