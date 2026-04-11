# Spec: shopping-cart-order PR #24 — Copilot findings fixes

## Context

Copilot reviewed PR #24 (`fix/rabbitmq-client-1.0.1`) and raised 3 findings.
All are valid. Fix them in a single follow-up commit on the same branch.

---

## Before You Start

```
Branch: fix/rabbitmq-client-1.0.1 (already exists on origin)

git -C ~/src/gitrepo/personal/shopping-carts/shopping-cart-order \
  fetch origin && git checkout fix/rabbitmq-client-1.0.1
```

Read these files in full before touching anything:
- `k8s/base/kustomization.yaml`
- `CHANGELOG.md`

---

## Findings and Fixes

### Finding 1 — `k8s/base/kustomization.yaml` line 30: stale image tag

Copilot: `newTag` was changed from `latest` to `2026-04-11-rabbit-health` (a manually-pushed
tag that has the NPE bug). If merged as-is, ArgoCD would try to run the broken image in the
window before CI publishes the fixed `sha-<merge-sha>` tag. The post-merge `publish` job is
the only thing that should mutate `newTag`.

**Old:**
```yaml
    newTag: 2026-04-11-rabbit-health
```

**New:**
```yaml
    newTag: latest
```

---

### Finding 2 — `CHANGELOG.md` line 10: stale `### Fixed` entry

Copilot: The first bullet under `### Fixed` describes the `RabbitHealthConfig` guarded health
indicator — code that was deleted in this PR. The entry is now inaccurate and should be removed.

**Old (remove this line entirely):**
```
- Replace Spring Boot's default RabbitMQ health indicator with a guarded version so /actuator/health stays UP while the rabbitmq-client cache is empty (prevents CrashLoopBackOff until the patched library is released)
```

**New:** *(line deleted — leave the other `### Fixed` bullets in place)*

---

### Finding 3 — `CHANGELOG.md` line 17: dangling word in `### Changed` bullet

Copilot: The new `### Changed` bullet breaks awkwardly — "remove" is left dangling at end of
line 1 with no object. Add "the" so the line reads as a complete phrase.

**Old:**
```
- Bump `rabbitmq-client` dependency from `1.0.0-SNAPSHOT` to `1.0.1`; remove
  `RabbitHealthConfig` workaround — NPE in `ConnectionManager.getStats()` is fixed
  at source in `1.0.1`, eliminating the `CrashLoopBackOff` on pod startup
```

**New:**
```
- Bump `rabbitmq-client` dependency from `1.0.0-SNAPSHOT` to `1.0.1`; remove the
  `RabbitHealthConfig` workaround — NPE in `ConnectionManager.getStats()` is fixed
  at source in `1.0.1`, eliminating the `CrashLoopBackOff` on pod startup
```

---

### Finding 4 — Issue doc (required by process)

Create `docs/issues/2026-04-11-copilot-pr24-review-findings.md` with this exact content:

```markdown
# Copilot PR #24 Review Findings

**Date:** 2026-04-11
**PR:** #24 — fix(deps): bump rabbitmq-client to 1.0.1; remove RabbitHealthConfig workaround
**Reviewer:** Copilot

## Finding 1 — Stale image tag in kustomization.yaml

**File:** `k8s/base/kustomization.yaml` line 30
**Flagged:** `newTag: 2026-04-11-rabbit-health` — a manually-pushed tag containing the NPE bug.
Merging with this tag would cause ArgoCD to deploy the broken image in the window before CI
publishes the fixed sha tag.
**Fix:** Reverted to `newTag: latest` so the post-merge publish CI job is the sole mutator.
**Root cause:** The workaround commit (`c813340`) changed this tag manually; the spec omitted
it from the "do not touch" list.
**Process note:** Spec template should explicitly list `k8s/base/kustomization.yaml` in
"What NOT to Do" for any PR where CI auto-updates it.

## Finding 2 — Stale CHANGELOG Fixed entry

**File:** `CHANGELOG.md` line 10
**Flagged:** Bullet describing `RabbitHealthConfig` guarded indicator — code deleted in this PR.
**Fix:** Removed the stale bullet.
**Root cause:** Entry was written when the workaround was added; not updated when workaround was removed.

## Finding 3 — Dangling word in CHANGELOG Changed bullet

**File:** `CHANGELOG.md` line 17
**Flagged:** "remove" left dangling at end of line with no grammatical object.
**Fix:** Changed to "remove the" so the sentence reads as a complete phrase.
**Root cause:** Line wrap introduced during spec writing.
```

---

## Files Changed

| File | Action |
|------|--------|
| `k8s/base/kustomization.yaml` | Edit — revert `newTag` to `latest` |
| `CHANGELOG.md` | Edit — remove stale Fixed entry, reflow Changed bullet |
| `docs/issues/2026-04-11-copilot-pr24-review-findings.md` | Create |

---

## Rules

- Work on `fix/rabbitmq-client-1.0.1` only — do NOT commit to `main`
- Do NOT create a PR (one already exists: #24)
- Do NOT skip pre-commit hooks (`--no-verify`)
- No other files modified

---

## Definition of Done

- [ ] `k8s/base/kustomization.yaml` has `newTag: latest`
- [ ] Stale `### Fixed` CHANGELOG bullet removed
- [ ] `### Changed` bullet reads "remove the `RabbitHealthConfig` workaround..."
- [ ] `docs/issues/2026-04-11-copilot-pr24-review-findings.md` created
- [ ] Commit message (exact):
  ```
  fix(pr24): address 3 Copilot review findings — kustomization tag, stale changelog entry, reflow
  ```
- [ ] Branch pushed: `git push origin fix/rabbitmq-client-1.0.1`
- [ ] SHA reported back

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify files outside the three listed above
- Do NOT commit to `main`
