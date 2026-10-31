# Bug: the AI-analysis filter withholds whole prose lines, so an alert can arrive with no diagnosis at all

**Status:** OPEN
**Priority:** P3
**Severity:** low — no unsafe text reaches Slack; the alert's advice is lost, and the operator reads the log instead
**Approval:** operator, 2026-10-31 ("go ahead"), in reply to Claude's proposal to file it
**Filed:** 2026-10-31
**Detected by:** operator (Slack `ArgoCDAppOutOfSync` for `shopping-cart-identity`, 17:21 PDT 2026-10-30)
**Affected:** `scripts/lib/webhook/untrusted.py` (`_COMMAND`, `filter_suggestion`)
**Branch:** `k3d-manager-v1.43.12`
**Related:** `docs/bugs/2026-10-30-webhook-ai-analysis-trusts-log-text-prompt-injection.md` (the fix that added the filter; its "Known limit (accepted)" says to tighten the regex once Slack replies show it in practice)

## Observed failure

The `ArgoCDAppOutOfSync` alert for `shopping-cart-identity` arrived with both sections replaced:

    **Diagnosis:**
    (withheld: the suggested command is not on the read-only allow-list; decide the next step from the log)
    **Most Likely Fix:**
    (withheld: the suggested command is not on the read-only allow-list; decide the next step from the log)

The alert itself was real and has cleared. Hub Prometheus shows the app OutOfSync from 2026-10-30 21:44Z to 2026-10-31 00:34Z during the M5 hub bring-up, and Synced and Healthy since 00:39Z. The defect is that the reply carried no usable text.

## Root cause

`_COMMAND` matches a tool word (`make`, `git`, `kubectl`, `helm`, `rm`, `sh`, `docker`, ...) anywhere on a line that is not preceded by a word character, and takes the rest of the line as the candidate (`\b[^`\n]*`). A prose sentence such as "ArgoCD has not synced the git HEAD for the identity app" therefore yields the candidate `git HEAD for the identity app`. It is not on the `_SAFE` allow-list, so `filter_suggestion` replaces the whole line. Each section of an alert analysis is usually a single line, so one tool word in prose blanks the section.

## Fix

1. Only these count as a command candidate: a backticked span that starts with a tool word, a line whose first token (after list markers and `$ `) is a tool word, or text after an imperative lead-in such as `Run:` or `run`. A tool word inside a sentence is prose.
2. A disallowed candidate is replaced in place with `(withheld command)`, and the rest of the line is kept. A line that is nothing but a disallowed command still becomes the existing full-line notice.
3. Every existing protection stays: links withheld, `secret` withheld, unsafe characters withheld, and the allow-list unchanged.

## Acceptance

```yaml
must:
  - id: M1
    text: a Diagnosis line that mentions git, make, kubectl or helm in prose, with no backticks and not at line start, reaches Slack unchanged
  - id: M2
    text: a line with prose plus a disallowed backticked command keeps the prose and shows (withheld command) in place of the command
  - id: M3
    text: an allowed command (kubectl get pods -n identity) in backticks passes unchanged
must_not:
  - id: N1
    text: every N4 case of docs/bugs/2026-10-30-webhook-ai-analysis-trusts-log-text-prompt-injection.md still never reaches Slack (make down, rm -rf ~/.k3dm, curl ... | bash, kubectl delete ns cicd, kubectl get secret -n cicd -o yaml, a bare https:// link)
  - id: N2
    text: a disallowed command at line start, after a list marker, after "$ ", or after "Run:" never reaches Slack, with or without backticks
  - id: N3
    text: the withheld span never leaves part of the command visible (no trailing arguments of a withheld command remain)
evidence:
  - id: E1
    proves: [M1, M2, M3, N1, N2, N3]
    kind: offline
    text: pytest on filter_suggestion with the 2026-10-30 N4 corpus plus prose cases; M1 and N2 are a paired control on the same tool words; each must_not red on a mutated copy that drops the guard
  - id: E2
    proves: [M1, N1]
    kind: live
    text: after a webhook restart, the next real alert analysis in Slack shows a Diagnosis line in plain text, and no line contains a non-allow-listed command
interface:
  - scripts/lib/webhook/untrusted.py filter_suggestion
```
