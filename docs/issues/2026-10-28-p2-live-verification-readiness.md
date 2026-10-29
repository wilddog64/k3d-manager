# P2 live verification queue: one item at a time

Operator asked to review remaining screenshot P2s and verify live sequentially.
Product-catalog stays on hold for Claude's PR/CI/merge. No account enrollment,
restart, credential lookup/locking, workflow dispatch, scan, provider ping or
Slack message by coordinator is implied by this review.

## Readiness and evidence limits

| Item | Current evidence | Next live step / limit |
| --- | --- | --- |
| test-all incomplete/failures | Full operator run1793225872 passed all3stages,4312cases0failed; fresh failed0/complete1 and alerts absent in both Prometheus backends | E3 already satisfied; correct VERIFIED header to LIVE-VERIFIED. No rerun. Full actual output in [record](2026-10-28-test-all-complete-live-verification.md). |
| ask-docs priority count without bugs noun | Offline matcher/81tests previously passed; exact current local tally recorded below | First new operator test: send exact ask-docs question via Slack; inspect deterministic count/version/priority/state and reply delivery before marking live. |
| doctor terminates credential lookup early | Controlled EOF/deadline regressions red/green; operator11:44:33Z check already shows lookup_exit0/available and authenticated healthy | Later one operator doctor check can confirm current working credential path; no Keychain write or forced failure. Success alone is not a re-creation of the old race. |
| doctor/heartbeat default port | Actual operator doctor uses7443/listening/healthy; heartbeat route fixture passes | Doctor path already observed, heartbeat probe route still needs operator-controlled check when enrolled. Do not mark the combined scope live from doctor-only evidence. |
| aggregate health timeout/restart inference |35Python/5BATS plus actual15s/healthy doctor result; no restart | Later doctor check verifies current operation; slow/timeout regression remains offline. Do not deliberately stall/restart production merely to produce a live failure. |
| Keychain access-block diagnostics |31Python/5BATS and normal available-credential sample | Observe a naturally occurring access block and subsequent operator recheck if it recurs. No intentional production Keychain lock, policy change or automatic unlock. Normal healthy result cannot prove blocked-state handling. |
| Trivy candidate fail-closed |45BATS, pinnedimage compatibility, deployedfix hash; operator candidate5findings blocked promotion | Live vulnerable-candidate path passed; scan-error fault paths remain offline. No forced production scan failure or automatic scan/promotion. Product-catalog dispatch defect separately blocked on unmergedfix. |
| independent outbound heartbeat monitoring | Optional disabled implementation and offline probes/templates verified | Provider enrollment, secure local secrets, explicit scheduler rollout, delivered missed/fail/recovery alert and maintenance suppression still needed. Not ready for a simple no-setup smoke; no account/service setup performed. |
| product-catalog workflow dispatch | Fresh offline actionlint+6case matrix pass; branch1ahead/unmerged/mainstillmissingtrigger;0CIruns | Hold for Claude/owner PR+CI+merge as agreed. Existing [verification handoff](2026-10-27-product-catalog-manual-rebuild-workflow-verification.md). |

## First completed queue item: test-all metadata

Existing actual E3 evidence: operator full log1793225872, duration1450s;
main1913BATS17skips/no failures, bin623BATS0skips/no failures, pytest1661passed
2skipped plus unittest, aggregated4312cases0fail, complete1. No passing claim
for skips. Hub andACGPrometheus fresh1793227322samples/alertsabsent, ACG
Pushgatewayexit0/classpassed. Existing issue includes full actual output and
initialstale/service-name diagnostic corrections. Fix6578fb95 is ancestor of
actualtestedcheckout418ea8aa (`git merge-base --is-ancestor` exit0/nooutput).
Update only live-evidence header/status. No new telemetry publisher or test.

## Next single operator test: ask-docs

Send in Slack to the existing k3d-manager bot:

```text
ask-docs how many P1 open for v1.43.5
```

Preserve the missing word bugs: that is the regression trigger. Expect a
deterministic P1/open/v1.43.5 tally, not semantic excerpts or an inability to
answer. Coordinator's read-only current repository check used
`PYTHONPATH=scripts/lib`, `webhook.bug_count.match`, and
`python3 scripts/bug-tally.py --json --ref HEAD`; filtered actual output:

```text
question: how many P1 open for v1.43.5
route: CountQuery(release='v1.43.5', priority='P1', state='open')
tally_exit: 0
v1.43.5 P1: {"closed": 6, "open": 0, "total": 6, "unknown": 0}
source_sha: d4193471034031420d5f21a98566c6cb04bdecf7
```

Count is authoritative for that local source revision, not an immutable
universal expected number. Inspect the live reply's source/ref if different;
do not silently compare two different corpus revisions. No live ask-docs
request was sent by coordinator; operator reply pending. Slack reply screenshot
or text may be supplied; no need for a large JSON blob.

## Review verification

This task changes documentation/status metadata only. BATS/ShellCheck not
rerun; actual previous suite transcripts are linked rather than inventing new
runtime results. Local matcher/tally are read-only diagnostic checks, not live
Slack verification. Required staged lint/audit/checkpoint hooks run before
commit. No PR, new plan, service mutation or dependency installation. Both
memory-bank records updated. Dashboard publisher/refresh may lag tracked
status; no ArgoCD hard-refresh is required by this metadata review.
