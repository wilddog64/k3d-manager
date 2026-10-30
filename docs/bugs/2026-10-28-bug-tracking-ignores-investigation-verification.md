# Bug: Bug Tracking ignores valid investigation-only recovery evidence

**Status:** VERIFIED — Luna rework independently tested and landed; operator publication/row check pending
**Fix commit:** c96d0d13
**Priority:** P3
**Filed:** 2026-10-28
**Branch:** k3d-manager-v1.43.9
**Approval:** explicit operator request to dispatch this fix and finish the incident tracking
**Dispatch:** go — gpt-6-luna, investigation-verification-metrics-luna
**Related:** docs/bugs/2026-10-26-webhook-unresponsive-minimal-diagnosis-recovery.md

## Problem and existing evidence

The recovered webhook incident is CLOSED with Verification type investigation
and a well-formed Live investigation evidence line pointing to actual operator
local health and completed cloud health output. Current dashboard shows Fixed
but Verified/Live-verified not yet. check-bug-evidence.py already supports typed
investigation proof without a Fixcommit. Shared prior_art and metrics do not.
A LIVE-VERIFIED typed doc produces live_evidence missing; CLOSED typed doc
produces verifiedfalse/livefalse and an inferred documentation FixSHA. This
misrepresents operational verification and implies a causal codefix. Rootcause
of the historical outage remains unconfirmed; do not manufacture one.
Actual reproducer outputs and retained proof are in:
- docs/issues/2026-10-28-webhook-incident-closeout-review.md
- docs/issues/2026-10-28-three-bug-luna-batch-verification.md

## Required bounded behavior

1. Share the existing typed investigation syntax/parser between hook and
   publisher (prefer hermes.prior_art); preserve ordinary codefix proof rules.
   Validity requires explicit Verificationtype investigation, a well-formed
   typed line with date/source/reference/env/scenario/proves, and no explicit
   Fixcommit. Preserve existing supported opaque reference contract; do not
   introduce network/secret/provider lookups or fetch reference URLs. Shape
   validation is not an automated claim about evidence truth; operator proof
   already reviewed for this incident. Document that limitation clearly.
2. Closed/fixed investigation docs with valid typed proof, including existing
   CLOSED recovered incident, publish verifiedtrue/live_verifiedtrue and
   live_evidenceok. Stop Openfor counting (-2 sentinel) as for verifiedliveproof.
   Open investigations must remain open/unverified even with typed metadata.
3. Missing/malformed typed proof, absent marker or conflicting Fixcommit must
   not bypass ordinary validation or invent investigation verification. An
   explicit marker alone is insufficient. Reject malformed calendar dates if
   shared parser handles validation, consistently in hook/publisher; preserve
   old codefix behavior/ancestry protections and existing hook error contracts.
4. For investigation-only docs do not use fixed_in history's documentation
   status-change commit as a causal FixSHA: show fix_sha '-'. A verified_sha may
   identify the actual investigation-proof recording commit, clearly documented
   as verification record, not causalfix. Date/at labels must be grounded in
   typed evidence date or actual recording commit, never invented timestamps.
5. Preserve current normal codefix metrics, before-v1.43.2/unassigned behavior,
   bounded labels, counts/status/releases, current table layout/columns/links,
   dispatch/cost policies and parent incident CLOSED/recovered semantics.
   No dashboard YAML change/new UI/new panel/newmetric family/ledger rewrite.
   Do not edit parent incident or historical-cause records in worker.
6. Guide explains verification of recovery vs causalcodefix, metadata example,
   safe fields and limitations. Existing tests exercise real helper/hook and
   publisher outputs, CLOSED+LIVE typed cases, negative/mixed/open/legacy cases,
   historical ref behavior and ordinary codefix regression/ancestry protection.
   Demonstrate targeted old-code red before finalgreen. No toy self-assertions.

## Files

- `scripts/lib/hermes/prior_art.py`
- `scripts/check-bug-evidence.py`
- `bin/k3dm-vectordb-metrics`
- `scripts/tests/bin/test_prior_art.py`
- `scripts/tests/bin/test_check_bug_evidence.py`
- `scripts/tests/bin/test_vectordb_bug_metrics.py`
- `scripts/tests/bin/test_live_evidence_acceptance.py`
- `docs/guides/grafana-dashboards/k3dm-bugs.md`
- `CHANGELOG.md`

## Acceptance

Valid existing incident metadata yields Fixed, Verified/Liveverifiedtrue,
correct evidence date/recordcommit, live_evidenceok, no causalFixSHA; invalid or
open investigation cannot gain verified flags. Normal codefix tests unchanged.
Shared accepted syntax is consistent; no live/evidence-source network calls.
No old rows/historical ledger/status edits, new UI or guessed rootcause.
Operator publishes metrics and inspects existing row after offline acceptance.

## Rules and gates

Read repository instructions/memory first. Only Files above may change; no
spec/memory edits, git add/commit/push/PR, main changes, live host/network/log/
Keychain/provider/service access, deployment or screenshots. Work only in
isolated worktree. Preserve DO NOT REMOVE; new/refactored functions<=8ifs;
report legacy conflicts rather than raise budgets or add unjustified allowlist.
Coordinator independently reviews staged audit/lint, commits/lands/pushes and
requests operator live check one at a time. No new plan doc.

Run python3 -m pytest -p no:cacheprovider on the four listed Python suites
(test_prior_art, test_check_bug_evidence, test_vectordb_bug_metrics,
test_live_evidence_acceptance) plus scripts/tests/bin/test_bug_tally.py because
shared status helper is involved. Run existing
bats scripts/tests/plugins/grafana_dashboard_bugs.bats (no layout change).
Ruff: /private/tmp/k3dm-review-tools/bin/ruff check --no-cache on all touched
Python files. Python syntax and git diff --check; relevant doc links.
Report actual outputs, old-code red, any skipped/failed gates and exact files.

## Independent implementation acceptance — 2026-10-28

Luna investigation-verification-metrics-luna run2 landedc96d0d13 after independent
269Python(zero skips/PROMTOOLenabled),38BATS,Ruff,Python syntax,stagedlint/audit,
hooks and repeated post-rebase landing gates. Firstdraftinvalidproof/headerbugs
rejectedandfixed; unrelatedassertionsrestored. RealGit/currentproofline/refcases
coverdatesandrecordSHA, normalcodeproofancestryandlegacybehavior preserved.
Original recovered incident remainsCLOSED and unchanged, nowrenders verifiedtrue/
livetrue/evidenceok/date2026-10-28/verifiedSHA7ea1032f/FixSHA'-' offline.
No dashboardlayout/query/columnchange, no rootcauseclaim, no networkprooflookup.
[Full actual outputs and review](../issues/2026-10-28-investigation-verification-metrics-review.md).
Operator must publishmetrics and inspectexistingrow; notLIVE-VERIFIEDyet.
