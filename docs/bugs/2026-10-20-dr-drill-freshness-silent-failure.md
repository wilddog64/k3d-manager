# Bug: DR drill freshness workflow fails silently when last successful result is stale

**Filed:** 2026-10-20 (operator GitHub failure notification; investigated with GitHub Actions logs and results branch)
**Status:** OPEN
**Priority:** P2 — repeated scheduled freshness failures lack actionable diagnostics and the DR evidence is past its eight-day assurance window
**Severity:** moderate — DR readiness evidence is stale and the automated workflow cannot distinguish its failure mode; no evidence that an actual recovery drill failed
**Approval:** operator requested investigation and bug filing if necessary on 2026-10-20; no authorization for live DR operations
**Component:** `scripts/etc/dr/drill-freshness.sh`, `scripts/tests/plugins/dr_drill_freshness.bats`, installed copy `wilddog64/k3dm-hub-data:main/drill-freshness.sh`
**Related:** `docs/plans/v1.46.0-scheduled-dr-drill.md` (weekly unattended drill is already queued; do not duplicate); `docs/howto/hub-dr-drill.md`; `docs/bugs/2026-10-11-hub-data-export-fails-under-launchd-and-dr-alerts-never-deployed.md`

## Symptom / verified evidence

GitHub's `Hub DR drill freshness` workflow failed on 2026-10-19 (run [39231660994](https://github.com/wilddog64/k3dm-hub-data/actions/runs/39231660994)) and 2026-10-20 (run [39401291165](https://github.com/wilddog64/k3dm-hub-data/actions/runs/39401291165)); it passed through 2026-10-18. Both failing jobs completed checkouts and exited 1 immediately at `bash k3dm-manager/drill-freshness.sh results` without any explanation, making the GitHub notification look like a failed DR drill.

The `results` branch currently contains only `results/20261010T182508Z.json` (plus `.gitkeep`). That result has `success: true`, V0–V7 all true, `rto_seconds: 499`, and `rpo_seconds: 459`. The script enforces `age <= 8 * 86400`: on October 19 and 20 that last result was older than eight days. **This is a legitimate stale-freshness failure, not evidence that an actual restore drill failed.**

The workflow's `actions/checkout@v4.2.2` Node.js deprecation warning is unrelated to the exit 1.

## Follow-up evidence (2026-10-21)

- Scheduled run [39577636232](https://github.com/wilddog64/k3dm-hub-data/actions/runs/39577636232) failed again at 09:31 UTC (02:31 PDT), on data-repo `main` commit `7c88cbf8`.
- Both checkouts completed successfully, including the `results` branch. The `freshness` job's `bash k3dm-manager/drill-freshness.sh results` step exited 1 immediately with no diagnostic; all other job steps completed.
- As inspected on October 21, the `results` branch still contains only `results/20261010T182508Z.json` plus `.gitkeep`. The October 10 JSON says `success: true`, V0–V7 true, RTO 499 seconds, RPO 459 seconds. At the October 21 run it is approximately 10 days 15 hours old, exceeding the eight-day gate.
- This confirms repeated **stale evidence**, not a new failed DR execution. Investigate why subsequent runs were not executed and/or published separately under the existing `docs/plans/v1.46.0-scheduled-dr-drill.md` work; preserve the existing eight-day threshold.
- The operator requested P2 bug tracking on October 21 and authorized a direct documentation update to `k3d-manager-v1.43.5` without a PR. No DR operation or data-repo update is authorized by that request.

## Root cause

The freshness script deliberately exits 1 without diagnostics for all three failure classes:

```bash
[[ -n "$latest" ]] || exit 1
jq -e '.success == true' "$latest" >/dev/null || exit 1
(( age <= 8 * 86400 ))
```

Consequently, an operator cannot distinguish missing drill results, latest drill failure, and stale successful drills from the Actions log. There is no discrepancy in the threshold itself; the unattended weekly scheduling/publishing gap belongs to the existing v1.46.0 plan.

## Fix (direction)

Retain nonzero exit semantics and the eight-day policy. Emit concise, actionable diagnostics to stderr/GitHub Actions annotations, distinguishing: no readable/valid results, most recent result failed, and most recent successful result older than the configured freshness threshold. Include last timestamp, computed age (days/hours), cutoff, and the steps `make dr-drill` on M2 and `make dr-drill-publish` on M4 until v1.46.0 scheduled agents are installed. Never print secrets, encrypted contents, or other result payloads.

Update the authoritative `scripts/etc/dr/drill-freshness.sh` and tests; document how the installed script in the data repo is synchronized after review. Do not silently modify the data repo or claim a successful drill was run.

## Acceptance

```yaml
must:
  - id: M1
    text: A stale but successful latest result causes exit 1 with a readable diagnostic naming the latest run timestamp, age and eight-day threshold.
  - id: M2
    text: No valid result and latest-result-success-false cases each cause exit 1 with distinct diagnostics.
  - id: M3
    text: A fresh successful result exits 0, preserving the existing threshold and timestamp comparison behavior.
  - id: M4
    text: The workflow log provides a clear operator action to run and publish the next DR drill; the installed data-repo copy remains aligned with its authoritative template after deployment.
must_not:
  - id: N1
    text: The fix must not extend or disable the eight-day freshness gate merely to make GitHub Actions green.
  - id: N2
    text: A stale successful result must not be reported as an actual recovery-drill failure.
  - id: N3
    text: Error logs must not expose secret values or encrypted snapshot contents.
evidence:
  - id: E1
    proves: [M1, M2, M3, N1, N2, N3]
    kind: offline
    text: BATS fixtures for stale-success, fresh-success, failed-latest, missing/invalid results and exact threshold boundary; assert exit codes and distinct stderr diagnostics. Show the pre-fix stale case has no useful diagnostic.
  - id: E2
    proves: [M1, M4]
    kind: live
    text: After operator-approved deployment to the data repo, run the GitHub freshness workflow against an intentionally stale result and verify the Actions log states the cause; later, after a real new published successful drill, verify it passes.
interface:
  - scripts/etc/dr/drill-freshness.sh results
  - wilddog64/k3dm-hub-data main/drill-freshness.sh
  - wilddog64/k3dm-hub-data results/*.json
```

## Definition of Done

- [ ] Offline cases pass, including previously silent stale-result path.
- [ ] Code review and PR merge through the normal branch workflow.
- [ ] Operator-approved sync to data-repo `main` and E2 checked.
- [ ] The unattended drill itself remains tracked by the existing v1.46.0 plan.

## What NOT to Do

- Do NOT run a destructive DR drill, touch the production hub, or publish synthetic green results.
- Do NOT change the success/age contract to hide failures.
- Do NOT commit directly to `main` or bypass the normal review process.
