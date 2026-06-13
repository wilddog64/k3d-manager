# Copilot PR #94 Review Findings — v1.6.5

**PR:** [#94](https://github.com/wilddog64/k3d-manager/pull/94) — `feat: v1.6.5 — k3s-az Azure provider + provisioning hardening`
**Reviewer:** `copilot-pull-request-reviewer[bot]` (state: COMMENTED)
**Date:** 2026-06-13

---

## Finding 1 + 2 — `workers/slack-relay/index.js`: provider alias normalization is case-sensitive

**Flagged (lines 91, 123):** `/acg-up Azure` and `/acg-resume Azure` (or `AZ`) fell back to
`aws` because `text` was not lowercased before the `PROVIDER_ALIASES` lookup / `VALID_PROVIDERS`
membership test. The alias map (`{ azure: 'az' }`) and valid set (`aws`, `gcp`, `az`) use
lowercase keys, so any mixed-case Slack argument missed.

**Fix (commit `eb0dfca2`):** lowercase the token before normalization.

```javascript
// before
const _p = PROVIDER_ALIASES[text] || text
const provider = VALID_PROVIDERS.has(_p) ? _p : 'aws'
// after
const _t = text.toLowerCase()
const _p = PROVIDER_ALIASES[_t] || _t
const provider = VALID_PROVIDERS.has(_p) ? _p : 'aws'
```

Verified: `node --check` OK; normalization probe — `Azure`/`AZ`/`Az` → `az`, `AWS` → `aws`,
`GCP` → `gcp`, garbage/empty → `aws`.

**Root cause:** trim without case-fold; alias/valid keys assumed already-lowercase input.

---

## Finding 3 — `scripts/lib/acg/playwright/acg_restart.js`: `others` exclusion is case-sensitive

**Flagged (line 113):** the card-match keeps a case-insensitive label test
(`new RegExp(label, 'i')`) but excludes sibling providers with case-sensitive `t.includes(p)`,
so differently-cased card text could let another provider's label through.

**Disposition: deferred upstream — NOT fixed in this PR.** This file is part of the
`scripts/lib/acg/` **git subtree** (lib-acg). Per subtree discipline the k3d-manager copy must
never be edited directly; the fix lands in lib-acg and reaches k3d-manager via `git subtree pull`.

Tracked upstream: `lib-acg/docs/bugs/2026-06-13-acg-restart-others-exclusion-case-sensitive.md`
(branch `feat/v0.1.8`). It is a pre-existing robustness issue in synced code, not introduced by
v1.6.5, and does not block this release.

---

## Process Note

- Provider-token normalization (Slack args, CLI args, UI label matching) should case-fold at the
  boundary before any alias/membership test. Add to spec review checklist for any new provider
  alias path.
- Copilot findings in subtree paths (`scripts/lib/acg/`, `scripts/lib/foundation/`) are filed
  upstream, never patched in the consuming repo.
