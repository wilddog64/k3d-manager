# P3 — Slack k3dm find-similar-docs rejects natural-language Q arguments containing spaces

**Filed:** 2026-10-15
**Branch:** `k3d-manager-v1.43.2`
**Priority:** P3 — Slack command usability / argument parsing
**Status:** OPEN — observed in Slack and parser confirmed; implementation not started
**Approval:** operator explicitly requested P3 bug filing; no implementation authorized

## Observed failure

In the Slack `#acg-automation` channel/thread, the operator entered:

```text
k3dm find-similar-docs Q=what's recent e2e-remote issues
```

The k3d-manager app returned:

```text
Usage: k3dm <target> [KEY=value ...] [confirm]
```

The intended question was not submitted to `find-similar-docs`. This is a parsing rejection, **not evidence of any vector-store retrieval problem**.

## Confirmed implementation path / cause

`bin/k3dm-webhook` in `_handle_thread_command`, under `elif cmd == "k3dm":`, uses `command.strip().lstrip("/").split()` and iterates individual `parts[2:]`. The first `Q=what's` token is accepted as a KEY=value assignment, but `recent`, `e2e-remote`, and `issues` have no `=`, triggering the generic usage response.

The `find-similar-docs` target is explicitly permitted in `scripts/lib/webhook/make_targets.py` and declares required `Q` with optional `K`. The failure occurs before the target executes.

**Important:** Simply adding quotation marks to a Slack message does not solve the current whitespace splitting, since `str.split()` is not quote-aware.

## Expected behavior

The Slack command interface should accept a natural-language `Q` value, including spaces, punctuation, apostrophes and hyphens, without accidentally treating its words as separate positional arguments.

For example, after the fix:

```text
k3dm find-similar-docs Q="what's recent e2e-remote issues"
```

should pass the full string as a single `Q` value to the existing validated execution path. Prefer a documented, consistent quoting/escaping convention for free-text `KEY=value` arguments; avoid inventing ad hoc parser rules that silently concatenate unrelated parameters. A user-friendly parse error should identify malformed or unterminated quoted values rather than only showing the generic usage line.

## Investigation and requirements

1. Review all Slack `k3dm` command entry points (thread replies, top-level events, slash command/API, if applicable) for inconsistent argument tokenization and validation; preserve existing role checks, target allowlists, required/optional keys and `confirm` semantics.
2. Implement a quote-aware or equivalent bounded parser appropriate for Slack plaintext; explicitly define supported quote, apostrophe and escape behavior, and ensure an apostrophe within `what's` in a properly double-quoted value remains intact.
3. Ensure `Q` text is passed as one argument through `parse_make_request` to the Make target without bypassing its allowlist/regex validation. Inspect the existing `Q` validation regex for compatibility with ordinary English questions; report/fix any second-stage rejection in the same scope.
4. Reject unknown keys, extra standalone arguments, malformed quotes, and unexpected confirm tokens rather than broadening the remote execution surface.
5. Update the Slack help/example for `find-similar-docs` to illustrate accepted natural-language query syntax. Preserve existing single-token invocations.
6. Consider other text-bearing arguments only where an explicit free-text contract exists; do not allow arbitrary multiword inputs for unrelated targets.

## Acceptance / regression tests

- A quoted multiword query with apostrophe/hyphen reaches `find-similar-docs` as the exact full `Q` string: `Q="what's recent e2e-remote issues"`.
- A simple `Q=recent-e2e-remote-issues` still works.
- Optional `K=5` alongside quoted `Q` is parsed as a separate argument.
- Unknown keys, stray positional tokens, mismatched quotes, and invalid target/role combinations remain rejected with clear feedback.
- Parsing does not enable shell-command expansion or bypass the existing `parse_make_request` validation.
- Regression tests cover actual Slack routing and ensure the bot does not respond with generic usage for valid quoted questions.

## Related

- `bin/k3dm-webhook` — Slack thread-command parser (`_handle_thread_command`).
- `scripts/lib/webhook/make_targets.py` — `find-similar-docs` `Q` contract.
- Intent-driven / natural-language command goals of k3d-manager.

**Implementation:** not started. Filing this report does not change application code or live infrastructure.
