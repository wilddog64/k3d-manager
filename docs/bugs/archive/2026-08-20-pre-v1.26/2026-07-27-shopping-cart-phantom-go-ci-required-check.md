# Bugfix: shopping-cart repos — phantom `"Go CI"` required status check blocks every merge

**Type:** branch-protection misconfiguration (GitHub settings, not code)
**Affected repos (all `wilddog64`):** `shopping-cart-basket`, `shopping-cart-frontend`,
`shopping-cart-order`, `shopping-cart-payment`, `shopping-cart-product-catalog`
**Executor:** Claude or the maintainer via `!` (the auto-mode safety classifier blocks
automated branch-protection edits — see Notes). **Not a Codex task.**
**Timing:** run **after** the v1.18.0 Dependabot PRs (#15/#30/#35/#25/#36) are merged and
`enforce_admins` has been restored by `/post-merge`.

---

## Problem

All five repos have identical `main` branch protection:

```
required_status_checks: { strict: true, contexts: ["Go CI"] }
required_approving_review_count: 1
enforce_admins: true
```

**No workflow in any of these repos emits a check named `"Go CI"`.** basket's Go workflow
produces `Lint` / `Test` / `Security Scan`; the others are npm / Maven / Python and never
produce anything called "Go CI". So the required context sits **"Expected — Waiting for status
to be reported"** forever.

**Symptom:** every PR is unmergeable through the normal path — the phantom "Go CI" never
reports, and as sole maintainer you cannot supply the 1 required approving review on your own
PR. The only way through is disabling `enforce_admins` for an admin bypass, which is why every
merge (including the Dependabot PRs) needed that step. **Root cause:** a leftover/templated
required-check context (`"Go CI"`) copied across all five repos that no longer matches any
job name.

---

## Fix

Replace the phantom `"Go CI"` context in each repo's `required_status_checks` with the checks
that repo's PR workflows actually produce. This restores real quality gates **and** lets normal
(non-admin) merges succeed once a review is present, so admin-bypass stops being mandatory.

`strict: true` is preserved (require branch up to date before merge). App-level checks
`.github/dependabot.yml` (Dependabot config validation) and `GitGuardian Security Checks` may
optionally be added; they are omitted below to keep the gate to CI jobs — **confirm the set per
repo before applying.**

### Proposed required contexts per repo

| Repo | Proposed `contexts` | Notes |
|------|--------------------|-------|
| `shopping-cart-basket` | `Lint`, `Test`, `Security Scan` | repo also emits a lowercase `test` job — confirm which is canonical before requiring |
| `shopping-cart-frontend` | `Lint`, `Test`, `Type Check`, `Build`, `E2E Tests`, `Security Scan` | deploy jobs (`Docker Build`, `Build, Scan, Push & Deploy`) are skipped on PRs — do NOT require |
| `shopping-cart-order` | `Build & Test`, `Checkstyle` | `Build, Scan & Push` is skipped on PRs — do NOT require |
| `shopping-cart-payment` | `Build and Test`, `Checkstyle & SpotBugs`, `Integration Tests`, `Security Scan` | `Code Quality`, `API Compatibility`, `Validate PR` optional adds; deploy jobs skipped on PRs |
| `shopping-cart-product-catalog` | `Lint & Type Check`, `Lint, Test & Build`, `Integration Test — Schema Self-Heal`, `Security Scan` | note the literal commas/em-dash in the check names |

> Only require checks that **always run on PRs**. Requiring a job that is `skipped` on PRs
> (deploy/push jobs gated to `main`) reintroduces the same permanent-block failure mode.

### Commands (per repo — run with `!` or after granting the classifier)

Each is a `required_status_checks` PATCH with a JSON body. Example for basket:

```bash
gh api repos/wilddog64/shopping-cart-basket/branches/main/protection/required_status_checks \
  -X PATCH --input - <<'JSON'
{"strict": true, "contexts": ["Lint", "Test", "Security Scan"]}
JSON
```

frontend:
```bash
gh api repos/wilddog64/shopping-cart-frontend/branches/main/protection/required_status_checks \
  -X PATCH --input - <<'JSON'
{"strict": true, "contexts": ["Lint", "Test", "Type Check", "Build", "E2E Tests", "Security Scan"]}
JSON
```

order:
```bash
gh api repos/wilddog64/shopping-cart-order/branches/main/protection/required_status_checks \
  -X PATCH --input - <<'JSON'
{"strict": true, "contexts": ["Build & Test", "Checkstyle"]}
JSON
```

payment:
```bash
gh api repos/wilddog64/shopping-cart-payment/branches/main/protection/required_status_checks \
  -X PATCH --input - <<'JSON'
{"strict": true, "contexts": ["Build and Test", "Checkstyle & SpotBugs", "Integration Tests", "Security Scan"]}
JSON
```

product-catalog:
```bash
gh api repos/wilddog64/shopping-cart-product-catalog/branches/main/protection/required_status_checks \
  -X PATCH --input - <<'JSON'
{"strict": true, "contexts": ["Lint & Type Check", "Lint, Test & Build", "Integration Test — Schema Self-Heal", "Security Scan"]}
JSON
```

---

## Change 2 — set `required_approving_review_count: 0` (solo maintainer)

**Decision 2026-07-28:** these repos have a single maintainer who cannot approve their own
PRs, so `required_approving_review_count: 1` guarantees a permanent block (the second half of
why every merge needed an admin bypass — the first is the phantom "Go CI"). Set it to 0. Real
CI checks (Change 1) remain the quality gate; `enforce_admins` can then stay `true` and normal
merges succeed on green CI with no bypass.

```bash
# per repo — run with ! (classifier may block the PATCH; single bare command per repo)
gh api repos/wilddog64/shopping-cart-<repo>/branches/main/protection/required_pull_request_reviews \
  -X PATCH -F required_approving_review_count=0
```

## Change 3 — Dependabot auto-merge (minor/patch + security; majors reviewed)

**Decision 2026-07-28:** after the first scan, Dependabot opens a version-update PR per stale
dep — mostly majors (each its own PR by design). Merging each by hand is untenable. Add an
auto-merge workflow so minor/patch and security PRs merge themselves on green CI, while majors
stay open for review. This is **repo source** → **Codex spec + handoff**, not a settings edit.
**Deferred to v1.19.0** — v1.18.0 is already at the 5-plan-doc limit, so the auto-merge workflow
opens the next release rather than growing this one. Spec: `docs/plans/v1.19.0-shopping-cart-dependabot-automerge.md`
(to be written on the v1.19.0 branch).

> Changes 1 and 2 (branch-protection: real required checks + review-count 0) are settings-only
> and can be applied now, post-merge, independent of the v1.19.0 auto-merge work.

---

## Verification

After each PATCH, confirm the contexts took:

```bash
for r in basket frontend order payment product-catalog; do
  echo "== $r =="
  gh api repos/wilddog64/shopping-cart-$r/branches/main/protection/required_status_checks \
    --jq '{strict, contexts}'
done
```

Expected: no repo lists `"Go CI"`; each lists its real checks. Then open a trivial test PR (or
the next real PR) and confirm the required checks report and merge is possible **without** an
admin bypass once approved.

---

## Definition of Done

- [x] No repo's `required_status_checks.contexts` contains `"Go CI"` — **APPLIED 2026-07-28**
- [x] Each repo requires the confirmed real check contexts from the table — **APPLIED 2026-07-28**
- [x] `required_approving_review_count: 0` on all 5 (Change 2) — **APPLIED 2026-07-28**
- [ ] A subsequent PR shows the required checks reporting (not "expected" forever)
- [x] memory-bank updated with the applied contexts per repo and completion status

### Applied contexts (verified live 2026-07-28, `enforce_admins` kept `true`)

| Repo | `contexts` | review |
|------|-----------|--------|
| basket | `Lint`, `Test`, `Security Scan` | 0 |
| frontend | `Lint`, `Test`, `Type Check`, `Build`, `E2E Tests`, `Security Scan` | 0 |
| order | `Build & Test`, `Checkstyle` | 0 |
| payment | `Build and Test`, `Checkstyle & SpotBugs`, `Integration Tests`, `Security Scan` | 0 |
| product-catalog | `Lint & Type Check`, `Lint, Test & Build`, `Integration Test — Schema Self-Heal`, `Security Scan` | 0 |

All required contexts confirmed **green on `main`** before requiring (every CI failure was a
deploy job — `Publish`, `Build, Scan, Push & Deploy` — correctly excluded). Change 3 (auto-merge)
remains for v1.19.0.

---

## Notes

- The auto-mode safety classifier blocks Claude from running branch-protection edits
  (`enforce_admins` DELETE, `required_status_checks` PATCH) even though `Bash(gh api:*)` is
  allowed — it is a separate guard on security-control-weakening actions. Run these with the
  `!` prefix, or add a specific Bash permission rule if repeated toggling is needed.
- This is **not** a Codex task and touches **no repo source** — it is GitHub settings only.
- Keep `enforce_admins: true` (restored by `/post-merge`). With correct required checks + a
  review, normal merges work; admin bypass remains available for emergencies.
