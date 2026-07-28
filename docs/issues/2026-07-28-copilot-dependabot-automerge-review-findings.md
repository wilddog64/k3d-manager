# Copilot review findings — v1.19.0 shopping-cart Dependabot auto-merge

**Date:** 2026-07-28
**PRs:** basket #29, frontend #57, order #49, payment #40, product-catalog #43 (branch `feat/dependabot-automerge`)
**File under review:** `.github/workflows/dependabot-automerge.yml` (byte-identical across all 5 repos)

Copilot re-reviewed after the merge-main commit and raised the findings below. Because the
workflow is byte-identical in all 5 repos, the same findings repeated across PRs. All fixed in one
byte-identical follow-up commit per repo: basket `e59660c`, frontend `ffbddf8`, order `e8e0b30`,
payment `509e14c`, product-catalog `c6e17fa`.

---

## Finding 1 — `alert-state` was dead code (CONFIRMED, fixed)

**Flagged:** `steps.meta.outputs.alert-state == 'OPEN'` in the auto-merge `if`.

`dependabot/fetch-metadata` only populates `alert-state` when invoked with `alert-lookup: true`,
and that lookup needs a token with `security-events: read`. As originally written, `alert-state`
was always empty → the security-update branch of the condition never fired. Security updates would
NOT have auto-merged as the spec/CHANGELOG claimed.

**Related (order #49):** if the branch *had* worked, it would auto-merge major *security* updates,
contradicting "majors stay open for review."

**Decision (maintainer, 2026-07-28):** wire it up properly — security updates auto-merge at **any**
semver (including security-majors), to close CVEs hands-off. Non-security majors still stay open.

**Fix (before → after):**

```yaml
# before
uses: dependabot/fetch-metadata@d7267f6...  # v2.3.0
with:
  github-token: ${{ secrets.GITHUB_TOKEN }}
# (no alert-lookup; no security-events permission)
```

```yaml
# after
permissions:            # job-level
  contents: write
  pull-requests: write
  security-events: read
...
uses: dependabot/fetch-metadata@d7267f6...  # v2.3.0
with:
  github-token: ${{ secrets.GITHUB_TOKEN }}
  alert-lookup: true
```

---

## Finding 2 — fragile `github.actor` gate (CONFIRMED, fixed)

**Flagged:** `if: ${{ github.actor == 'dependabot[bot]' }}` breaks on `reopened`/`edited` events
where the actor becomes the human who reopened, so auto-merge would not re-enable.

**Fix:** gate on the PR author instead:

```yaml
if: ${{ github.event.pull_request.user.login == 'dependabot[bot]' }}
```

---

## Finding 3 — least privilege (CONFIRMED, fixed)

**Flagged:** workflow-wide `permissions:` with write scope under `pull_request_target`; trigger not
scoped.

**Fix:** top-level `permissions: {}`, write scopes moved to the job, and the trigger scoped to the
default branch:

```yaml
on:
  pull_request_target:
    branches: [main]
permissions: {}
jobs:
  automerge:
    permissions:
      contents: write
      pull-requests: write
      security-events: read
```

Aligns with the repo security rule "GitHub Actions workflows must use least privilege" (OWASP A01).

---

## Finding 4 — CHANGELOG grouping wording nit (out of scope, resolved)

**Flagged (basket, payment):** the `[Unreleased]` `.github/dependabot.yml` bullet says minor/patch
updates are "grouped" for all ecosystems, but only the app ecosystem defines a group.

**Disposition:** that bullet is the **pre-existing v1.18.0** Dependabot-config entry, not the
auto-merge workflow this PR adds. Left unchanged (out of scope); thread resolved with an
explanation. Grouping-wording accuracy tracked separately.

---

## Process note (for the spec template)

The v1.19.0 spec *did* flag the security-major behavior as a confirm-point, but shipped the
`alert-state` condition **without** the `alert-lookup: true` + `security-events: read` it requires —
so the feature was inert. **Rule:** when a spec references an action output (`steps.<id>.outputs.*`),
it must also state the exact `with:` inputs and `permissions:` that populate that output, or the
condition is dead code. Add an actionlint gate *plus* a "does every referenced output have its
enabling input/permission?" check to workflow specs.
