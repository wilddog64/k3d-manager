# Bug: Grafana's error page shows a JavaScript stack trace to anyone who can open the dashboard

**Filed:** 2026-11-07
**Branch:** `k3d-manager-v1.43.14`
**Status:** OPEN
**Priority:** P3 — information exposure of low value; nothing secret was shown, but the operator does not want internals on the page
**Waiting on:** investigation — since 2026-11-07
**Approval:** explicit 2026-11-07 "can you file grafana error page showing a stack trace bug, and dispatch it" (operator); concern first raised 2026-11-07: "the exception should not explore on the page ... that's security concern"
**Severity:** low
**Related:** `docs/bugs/2026-11-07-hub-code-behind-tile-unknown-matcher-crashes-bugs-dashboard.md`

## Symptom

When the Bugs dashboard crashed on an unknown field matcher (2026-11-07, Grafana 11.4.0 at grafana.3ai-talk.org), the page showed Grafana's error boundary with the error message and a full component and JavaScript stack: bundle file URLs, function names, and the matcher id.

## What is known

- The page is rendered in the browser by Grafana's React error boundary, not by the server. The stack holds public bundle URLs and code names, no secrets, tokens or data.
- The crash cause is fixed (`73120c90`), and a test now rejects unknown field matchers in every platform-ops dashboard, so this page should not appear again from that cause.
- Not known: whether Grafana 11.4 has any supported setting that hides the stack from viewers.

## Task (investigation first)

1. In the Grafana v11.4.0 source, find the component that renders the dashboard and panel error boundaries (start from `ErrorBoundaryAlert` and `ErrorWithStack` in `packages/grafana-ui`). Report whether it shows the stack unconditionally, behind a details toggle, or only for some roles, and whether any `grafana.ini` setting, feature toggle or environment variable changes that. Cite file paths and line numbers at tag v11.4.0.
2. Only if a supported setting exists: set it in `scripts/etc/helm/observability/kube-prometheus-stack-values.yaml` and `scripts/etc/helm/observability/kube-prometheus-stack-acg-values.yaml` under the Grafana chart's `grafana.ini` key, and add a test for it per the Acceptance block.
3. If no supported setting exists: change no code. Write the findings into a new `## Findings` section at the end of this doc, with the citations, and say so in your final message. Claude decides next steps with the operator.
4. `CHANGELOG.md`: one bullet at the end of `[Unreleased]` only if step 2 changed config.
5. If you cannot read the Grafana v11.4.0 source (no network in your sandbox), write that into `## Findings` and stop. Do not answer from memory.

## Files

- `scripts/etc/helm/observability/kube-prometheus-stack-values.yaml` (step 2 only)
- `scripts/etc/helm/observability/kube-prometheus-stack-acg-values.yaml` (step 2 only)
- `scripts/tests/bin/test_grafana_error_details.py` (new; step 2 only)
- `docs/bugs/2026-11-07-grafana-error-page-shows-stack-trace.md` (the `## Findings` section only)
- `CHANGELOG.md` (step 2 only)

## Gates

Step 2 only: `pytest scripts/tests/bin/test_grafana_error_details.py`, with `PATH` including a Python that has PyYAML. Paste the output.

## What NOT to Do

- Do NOT patch, fork or proxy Grafana, inject CSS or JavaScript, or add a sidecar. Supported settings only.
- Do NOT change Grafana's version, auth or any other `grafana.ini` key.
- Do NOT guess at a setting name; every setting you use must be cited from the v11.4.0 source or docs.
- Do NOT commit, push or create a PR. Claude reviews and commits.
- Do NOT touch `memory-bank/`, the header of this doc, or any file outside the Files list.

## Acceptance

```yaml
interface:
  - "scripts/etc/helm/observability/kube-prometheus-stack-values.yaml and kube-prometheus-stack-acg-values.yaml: grafana.grafana.ini"
  - "docs/bugs/2026-11-07-grafana-error-page-shows-stack-trace.md: ## Findings"
must:
  - id: M1
    text: "The Findings section states, with v11.4.0 file and line citations, how the error boundary decides to show the stack and which settings, if any, change it."
  - id: M2
    text: "If a supported setting exists, both values files set it to hide the stack, and a test asserts it in both files. Paired control: the test fails when the key is removed from either file."
must_not:
  - id: N1
    text: "No grafana.ini key other than the cited one changes, and no file outside the Files list changes."
evidence:
  - id: E1
    proves: [M1, M2, N1]
    kind: offline
    what: "Claude reads the cited source lines at tag v11.4.0 and confirms each citation; if config changed, an independent verifier runs tests from this block."
  - id: E2
    proves: [M2]
    kind: live
    what: "Operator: a deliberately broken scratch panel shows no stack after the change. Only if config changed."
```
