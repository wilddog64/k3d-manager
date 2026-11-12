# Bug: Grafana's error page shows a JavaScript stack trace to anyone who can open the dashboard

**Filed:** 2026-11-07
**Branch:** `k3d-manager-v1.43.14`
**Status:** CLOSED — won't fix: upstream behaviour (Grafana 11.4 always renders the stack, collapsed). Cause fixed `73120c90` and guarded by a test. Re-check during the observability stack upgrade (`docs/ideas.md` row 2026-11-10). Operator, 2026-11-10
**Priority:** P3 — information exposure of low value; nothing secret was shown, but the operator does not want internals on the page
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

## Findings

**2026-11-07, Luna:** stopped without changes; its sandbox could not resolve `raw.githubusercontent.com`, so it could not read the source.

**2026-11-07, Claude** (read at tag v11.4.0 with `gh api`):

- `packages/grafana-ui/src/components/ErrorBoundary/ErrorBoundary.tsx:110-119` — `ErrorBoundaryAlert` with `style="alertbox"` renders `error.toString()` and `errorInfo.componentStack` inside a `<details>` element, with no condition on role, build mode or config.
- `ErrorBoundary.tsx:122` and `ErrorWithStack.tsx:17-21` — `style="page"` renders `ErrorWithStack`, which does the same: title, then a `<details>` holding the error and the component stack, again unconditional.
- `conf/defaults.ini` at v11.4.0 has no key matching `stack`, `error_detail`, `hide_*error` or `show_*error`.
- Not read: Grafana's Go server and any feature toggles beyond the `defaults.ini` search; the dashboard-scenes error views were not traced separately.

**Conclusion:** Grafana 11.4 has no supported setting that hides the stack. It is always rendered, collapsed inside `<details>`. What it exposes is the error text and React component names. Step 2 does not apply, and no config changed. Remaining levers, for the operator: (a) prevention, which is in place, since `73120c90` added a test that rejects unknown field matchers in every platform-ops dashboard; (b) access, since only people who can open Grafana can see the page; (c) close this as won't-fix upstream behaviour, or track a Grafana upgrade that changes it.

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
