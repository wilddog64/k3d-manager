# Bug: Bug Tracking dashboard links resolve to an empty Git ref and filename (GitHub 404)

**Filed:** 2026-10-19 (operator reported a broken link while reviewing a P1 bug)
**Branch:** `k3d-manager-v1.43.5`
**Status:** LIVE-VERIFIED — 2026-10-20: operator clicked a Bug Tracking dashboard link and confirmed GitHub opened `docs/bugs/2026-10-18-data-layer-app-cascade-deleted-by-registration-label-window.md` instead of returning 404. Offline fix `2036253f`; regression follow-up `7cea0f18`.
**Fix commit:** `2036253f`
**Live evidence:** 2026-10-20 · run operator-screenshot-grafana-bug-link-2026-10-20 · env hub-grafana · scenario bug-tracking-data-layer-row-link · commit 7cea0f18 · proves fix
**Offline regression follow-up:** test-only strengthening landed as `7cea0f18`; dashboard YAML unchanged; operator's live click confirms the deployed link resolves.
**Priority:** P2 — the table displays bug records but clicking a bug cannot open its source document; users can locate documents manually
**Severity:** medium (bug-tracking navigation and traceability are broken; not a cluster/runtime failure)
**Approval:** operator authorized scoped offline implementation dispatch on 2026-10-21: “can you dispatch this bug?” Live Grafana/ArgoCD changes are not authorized by this dispatch.
**Release:** v1.43.5 (bug; exempt from plan cap)
**Component:** `scripts/etc/argocd/platform-ops/grafana-dashboard-bugs.yaml` (Grafana `k3dm-bugs`, "Bugs" table)
**Related:** `docs/bugs/2026-10-11-bug-dashboard-cannot-list-open-bugs.md`; `scripts/tests/plugins/grafana_dashboard_bugs.bats`

## Symptom

From the Grafana k3dm Bug Tracking "Bugs" table, clicking the title
"app-cluster registration exits silently when the role-label lookup fails"
opens GitHub and returns 404. The operator captured the actual URL:

```text
https://github.com/wilddog64/k3d-manager/blob//docs/bugs/.md
```

The same link template is configured for the entire **Bug** column, so other rows
are at risk. This does not prove that every row was clicked or tested. The target
file exists on the release branch:

```text
docs/bugs/2026-10-18-register-app-cluster-role-lookup-exits-silently.md
```

Its metadata was updated by commit `9998c6b9`; the actual fix commit recorded
in the document is `a70e52a4`. The document is **not** the missing resource.

## Root cause / investigation

The dashboard's Bug-column data link is configured as:

```text
https://github.com/wilddog64/k3d-manager/blob/${__data.fields.branch}/docs/bugs/${__data.fields.bug}.md
```

But the same "Bugs" table runs `sortBy` followed by `organize` with:

```json
"excludeByName": {
  "bug": true,
  "branch": true
}
```

The link template references fields removed from the transformed display frame.
The observed resulting URL has both substitutions empty. Confirm the precise
Grafana version's data-link resolution behavior when implementing; the source
configuration and the captured URL are consistent with this field-removal cause.

The existing `grafana_dashboard_bugs.bats` link test checks only that the URL
template **contains** `${__data.fields.branch}` and `${__data.fields.bug}`.
It does not test that these fields are accessible after transformations or that
the resulting link is usable. The test therefore passes for a broken dashboard.

## Live reproduction after offline fix — 2026-10-21

The operator clarified that the reported failure is clicking the CVE-remediation
bug title in the Grafana Bug Tracking table, not opening the CVE architecture guide
itself. The click opens GitHub's 404 page, which reports it cannot find a valid ref
in `docs/bugs/.md`; this matches the empty-ref/empty-stem signature above. The
offline fix `2036253f` preserves `branch` and `bug` through the table transformation,
but this live report shows E2 is not satisfied. Keep the bug OPEN until the live
dashboard's synced ConfigMap revision and exact resolved URL establish whether the
fix has not synced or Grafana still cannot interpolate the transformed fields.

The dashboard source contains one data-link template on the visible `Bug` field,
shared by every row. Therefore this is a table-wide failure mode, not a CVE-row-specific
link. All bug-title clicks may be affected until the live link resolves correctly.

## Live verification — 2026-10-20

The operator reports that clicking a Bug Tracking dashboard row now opens the
GitHub Markdown page for `2026-10-18-data-layer-app-cascade-deleted-by-registration-label-window.md`
without a 404 (screenshot provided in the conversation). This confirms a real
dashboard link resolves to a nonempty ref and file path. The screenshot verifies
one row; a second distinct row was not evidenced in this check, so the broader
two-row acceptance criterion remains unconfirmed.

## Fix requirements

- **F1:** Make every Bug-column data link resolve against the real scanned Git
  ref and the original `docs/bugs/*.md` file stem for its row. Use a
  Grafana-supported approach that preserves the required values for link
  interpolation *without exposing raw metadata columns to users*. Do not merely
  remove the `excludeByName` flags and leave unwanted columns visible.
- **F2:** Keep existing visible columns, sorting, release/repo filters, and
  scan-branch semantics. Do not hardcode `main` or reconstruct the file stem
  from the human-readable bug title.
- **F3:** Add regression coverage exercising the transformed table/link contract
  (not only string presence in a JSON template), with at least two differing
  stems and branch refs; verify that the resolved URL contains no empty
  `/blob//` or `/docs/bugs/.md` components.
- **F4:** Update documentation/changelog only if needed to describe the
  corrected interaction and validation.

## Files

- `scripts/etc/argocd/platform-ops/grafana-dashboard-bugs.yaml`
- `scripts/tests/plugins/grafana_dashboard_bugs.bats` (or an additional focused offline test)
- `docs/guides/grafana-dashboards.md`, `CHANGELOG.md` (only if needed)

## Acceptance

```yaml
must:
  - id: M1
    text: Every Bug-column link resolves to a valid nonempty repository ref and original file stem, retaining the scanned ref rather than assuming main.
  - id: M2
    text: The Bug column still shows the readable title, and branch/stem metadata does not appear as visible columns.
  - id: M3
    text: Existing priority sorting and release/repo/verified filtering are unchanged.
  - id: M4
    text: The Oct 18 app-cluster registration bug opens its actual Markdown document in the k3d-manager repo.
must_not:
  - id: N1
    text: No rendered link may contain /blob// or /docs/bugs/.md; demonstrate regression failure against the pre-fix dashboard.
  - id: N2
    text: Tests must not pass merely because the template contains the two __data.fields placeholders; verify interpolation with post-transformation data.
  - id: N3
    text: No change to bug metric semantics, labels, release accounting or unrelated dashboards.
evidence:
  - id: E1
    proves: [M1, M2, M3, N1, N2, N3]
    kind: offline
    text: Focused regression test for Grafana post-transformation link data and bats scripts/tests/plugins/grafana_dashboard_bugs.bats; show N1/N2 red on the pre-fix dashboard and green on the fix.
  - id: E2
    proves: [M1, M4, N1]
    kind: live
    text: After the updated ConfigMap is synced to the hub Grafana, click at least two distinct rows (including the Oct 18 registration bug) and record the exact resolved URLs and successful GitHub document loads.
interface:
  - scripts/etc/argocd/platform-ops/grafana-dashboard-bugs.yaml (k3dm-bugs JSON, Bugs table data link and transformations)
  - k3dm_bug_info Prometheus metric labels bug and branch
```

## Definition of Done

- [ ] A regression test fails on the original link/transform configuration and passes with the fix.
- [ ] `bats scripts/tests/plugins/grafana_dashboard_bugs.bats` and dashboard JSON validation pass.
- [x] Dashboard link was live-verified by the operator: the data-layer cascade bug opens its GitHub Markdown document without a 404. A second distinct row was not evidenced.
- [ ] Update this bug's Status and verification log with commit SHA and E1/E2 evidence; do not declare LIVE-VERIFIED before E2.

## What NOT to Do

- Do NOT modify `main`, create a PR, or use `--no-verify` as part of this filing.
- Do NOT silently treat missing branch/stem values as `main` or derive paths from display titles.
- Do NOT apply changes to the hub or contact live Grafana/Pushgateway during offline tests.
- Do NOT mark this bug fixed based only on the presence of a GitHub file or a passing template-string test.
