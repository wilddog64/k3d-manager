# Verification reports

Use this format for every live or offline verification reported to the operator, including a review of a dispatched agent's fix. Put the approved intent first and answer it directly.

## Required fields

1. **Intent:** quote the approved intent sentence, then answer in plain words: **seen** or **not seen**.
2. **Verdict:** **PASS**, **FAIL**, or **PASS WITH NOTES**.
3. **Proof:** name the command or make target, its exit code, and the single output line that shows the result.
4. **Errors seen:** list every error, warning, and non-zero exit in the output, with a plain reason each does or does not change the verdict. Write `none` when there were no errors. An unexplained error means the verdict cannot be PASS.

A bug or plan with live verification links the report using a `**Live evidence:**` line.

## Example

**Intent:** You will see the summary report say `3 checks passed`. It failed if the report says fewer than three. **Seen.**

**Verdict:** PASS

**Proof:** `make verify-summary` — exit 0 — `3 checks passed`

**Errors seen:** none.
