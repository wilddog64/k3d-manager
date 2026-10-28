# Webhook incident closeout evidence review

**Date:** 2026-10-28
**Scope:** Review of retained operator evidence and evidence/status parsing. No code, bug spec, or memory-bank changes; no live actions.

## Finding and recommendation

The operator's local doctor check at `2026-10-28T11:44:33.867109Z` reported authenticated `healthy_http`, `all_ok=true`, loaded launchd job PID `4295`, listener on port `7443`, available reader credential, fresh log with no error categories, and `recovery_recommended=false`. The operator then reloaded cloud-bridge separately. Filtered read-only state showed a recently started bridge process (PID `65583`); no exit code was supplied, so none is claimed. The completed request `20261028T114826Z-health` returned at `2026-10-28T11:49:51.677857Z` with HTTP 200, status `ok`, `all_ok=true`, and 21 successful checks. Earlier Slack `/k3dm fix-list` job `a13d5831` also completed and delivered a reply.

These records establish current local webhook functionality and current cloud-bridge request/reply delivery. No webhook restart was indicated or performed. They do not show that the historical October 26 outage was reproduced, that a webhook repair occurred, or what caused the offsite unresponsiveness. The separate cloud-bridge SSH fallback fix is verified for its bounded current path; it is not evidence that it caused or fixed the historical incident.

**Recommendation:** the coordinator can close the active operational incident as recovered, while carrying the unknown October 26 cause in a linked historical-investigation issue. Do not describe the historical cause as fixed or mark the bridge fallback as the webhook incident's fix. This avoids keeping an active P2 outage after current local and external operation have both been demonstrated, while preserving the unresolved causal question. The coordinator owns the status change; this review does not edit the bug record.

## Acceptance mapping

| Item | Evidence and disposition |
| --- | --- |
| M1 / E1 | The 11:44 local doctor snapshot independently reports launchd, PID, listener, log freshness/categories, credential availability, and authenticated functional health before the later bridge reload. It is not a contemporaneous snapshot from the October 26 failure and cannot establish the original pre-recovery state. Historical E1 is unavailable. |
| M2 | Not applicable to the observed current state: the doctor reported healthy local HTTP and recommended no recovery. No `make restart-webhook` invocation was warranted or performed. |
| M3 / E2 | Current local health plus the completed 11:49 cloud health request demonstrate local functionality and delivered cloud-bridge response. There was no webhook recovery event, so E2's post-webhook-restart sequence is not met literally; the operational outcome it was intended to verify is now demonstrated without a needless restart. |
| M4 | The October 26 cause remains explicitly unknown. The incident links to the independent-heartbeat monitoring follow-up. Keep a separate historical investigation record if causal analysis remains useful. |
| N1 | Compliant: no host outage, process crash, tunnel failure, or specific historical cause is inferred from offsite unresponsiveness. |
| N2 | Compliant in retained evidence: the doctor JSON is redacted/structured; no token or secret-bearing launchd output is recorded here. |
| N3 | Compliant: no repeated or destructive recovery occurred. No webhook restart was performed. |
| N4 | Compliant: current function is evidenced, while historical cause/fix is not claimed. |
| Definition of Done | Current local and external operation are independently verified. A repair attempt was not indicated. Historical E1 and historical cause cannot be reconstructed; preserve that limitation in the linked issue rather than retaining a currently active outage state. |

## Suggested truthful bug metadata

If the coordinator accepts operational closure, use a status that scopes closure to current recovery, for example:

```markdown
**Status:** LIVE-VERIFIED — current local webhook and cloud-bridge delivery recovered; October 26 cause remains unknown
**Verification type:** investigation
**Live investigation evidence:** 2026-10-28 · source operator · reference docs/issues/2026-10-28-three-bug-luna-batch-verification.md · env m4-webhook-and-cloud-bridge · scenario current-local-and-delivered-health-check · proves m1,m3,m4
```

Do not add a `Fix commit` line to the webhook incident: there is no demonstrated code fix for its historical cause. The cited evidence supports the current operational state, not causal attribution. `scripts/check-bug-evidence.py` accepts typed investigation evidence for a newly `LIVE-VERIFIED` bug only when `Verification type: investigation` is present and there is no `Fix commit`; this is the appropriate evidence form if the status is changed. Its validation checks line shape and metadata, not whether the referenced record proves the claims. Keep the `proves` list narrow and retain the linked operator record as the evidence source.

The prior-art parser recognizes status prefixes such as `LIVE-VERIFIED`, `CLOSED`, and `RESOLVED`. Its ordinary `Live evidence` parser requires a commit SHA; its typed investigation parser is local to `check-bug-evidence.py`, not a general prior-art evidence parser. Therefore do not use a fake code commit or ordinary `Live evidence` line to represent an operational investigation. A status edit should be checked against the existing dashboard/status consumers by the coordinator.

## Historical follow-up and bounded recurrence checklist

Retain the October 26 cause as unconfirmed and link the incident to `docs/bugs/2026-10-26-independent-heartbeat-healthchecks-monitoring.md`. On recurrence, use this sequence once, recording UTC timestamps and sanitized results:

1. On m4, run `bin/k3dm-webhook-doctor --check`; review its JSON. Do not share tokens, raw environment, raw process arguments, unfiltered launchd output, or raw logs.
2. If the reader credential is unavailable, or a health request times out while a listener exists, treat the result as inconclusive and stop for credential-context or bounded local diagnosis. Do not infer a dead handler or restart from those results alone.
3. If local health is good, do not restart the webhook. Investigate the external path; consider one separate `make restart-cloud-bridge` only when bridge-specific evidence justifies it. Then issue one benign read-only health request and confirm its completed response was delivered.
4. If local evidence instead confirms the webhook job is absent or its handler is nonresponsive, an operator may make at most one `make restart-webhook` attempt. Record the command result and refreshed local and delivered-request evidence. Remember it also restarts cloud-bridge. Stop after bootstrap failure, repeated process exit, or a still-hung handler; no restart loop or additional remediation.
5. If m4 is unavailable, this local recovery path cannot act. Preserve evidence and use the independently maintained heartbeat/host path; do not infer the cause from remote unresponsiveness alone.

## Rules gates

Documentation-link check:

```text
$ make check-doc-links
check-doc-links: 2473 file(s) OK
```

Diff whitespace check:

```text
$ git diff --check
[no output; exit 0]
$ git diff --no-index --check /dev/null docs/issues/2026-10-28-webhook-incident-closeout-review.md
[no output; exit 1 because the untracked report differs from /dev/null]
```

The new report was the only file changed. No unit tests, live doctor check, service action, credential access, provider request, or network probe was run for this docs-only closeout review.

## Independent coordinator acceptance and consumer check

Coordinator reviewed supplied operator JSON/HTTP200 response and original
conditional recovery requirements. Accept operational closure, not causalfix.
Uses CLOSED rather than proposed LIVE-VERIFIED because actual publisher does
not understand typed investigation proof, despite the hook accepting it.
Read-only in-memory consumer check (outputfiltered to status/evidencefields):
```text
proposed-live-investigation {"fix_sha": "-", "live_evidence": "missing", "live_verified": "true", "status": "fixed", "verified": "true"}
selected-operational-closure {"fix_sha": "-", "live_evidence": "-", "live_verified": "false", "status": "fixed", "verified": "false"}
PASS: incident closed without a fabricated causal fix or code-fix verification claim.

```
Initial exploratory fixture without release tally emitted unassigned/n/a and
was inconclusive; corrected fixture supplies actualv1.43.9tally as above.
This source-consumer gap is recorded for future investigation-only evidence
support, not fixed silently in a documentation closeout. No fake Fixcommit.

Report adopted into release documentation by the coordinator after independent
review/link/parser/whitespace/stagedchecks. This is a review-only result, not a
new implementation land: existing native land guard accepts only one prior
same-spec slug, while both webhook-incident-doctor-luna and
webhook-incident-evidence-review-luna have already landed this spec. No duplicate
code integration, guard/history rewrite or prior landed-marker removal performed.
The review runner's exit succeeds; native implementation landing is not claimed.
Existing task record remains intact. A future multi-superseding/review-only
tracking enhancement is outside this task. No code changed to bypass the guard.

Minor CLI discovery output: `bin/k3dm-codex-dispatch verify --help` returned
`[codex-dispatch] ERROR: unknown verify option: --help` (exit2); source inspected
instead, no verify record fabricated because that command requires landedtask.
No unittest/shellcheck rerun for documentation-only changes. Relevant existing
142Python/5restartBATS remain in the earlier batch evidence, not claimed fresh.

## Accepted closeout commit and gates

Commit7ea1032f (coordinator documentation adoption and operational closure).
Actual staged gate output, all exited0:
```text
$ ./scripts/k3d-manager _agent_lint
running under bash version 5.3.20(1)-release
$ ./scripts/k3d-manager _agent_audit
running under bash version 5.3.20(1)-release
check-doc-links: 5 file(s) OK
[k3d-manager-v1.43.9 7ea1032f] checkpoint: before docs: close recovered webhook incident and retain cause investigation
```
No BATS/ShellCheck rerun applicable to this docs-only closeout; prior actual
implementation results remain in linked batch evidence. No PR created.
