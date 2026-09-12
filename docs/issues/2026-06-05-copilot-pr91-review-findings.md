# Copilot PR #91 Review Findings

**PR:** #91 — feat: add /acg-refresh Slack command + acg-up Keycloak retry (v1.6.2)
**Date:** 2026-06-05

---

## Finding 1 — `scripts/lib/acg/playwright/providers/gcp.js:27` — GCP username logged to stderr

**What Copilot flagged:**
```javascript
console.error(`INFO: username="${username.slice(0, 30)}" password="${password ? '[set]' : '[empty]'}" sa_json_len=${serviceAccountJson.length}`);
```
Logging up to 30 characters of the GCP username to stderr is a potential sensitive data leak. Password handling is correct (`[set]`/`[empty]`); the username should follow the same pattern.

**Fix:**
Replace `username.slice(0, 30)` with `username ? '[set]' : '[empty]'` in the log line.

**Before:**
```javascript
console.error(`INFO: username="${username.slice(0, 30)}" password="${password ? '[set]' : '[empty]'}" sa_json_len=${serviceAccountJson.length}`);
```

**After:**
```javascript
console.error(`INFO: username="${username ? '[set]' : '[empty]'}" password="${password ? '[set]' : '[empty]'}" sa_json_len=${serviceAccountJson.length}`);
```

**Root cause:**
`gcp.js` was written before the logging hygiene convention (mask credentials, log only presence) was established in the other providers (`aws.js` already uses `[set]`/`[empty]` for all credentials).

**Status:** FIXED UPSTREAM 2026-09-12 in lib-foundation `fix/acg-prism-monogram-selector` (`3c5e478`) — reaches k3d-manager via the next lib-foundation release + `git subtree pull`.

**Routing correction:** the original deferral pointed at `wilddog64/lib-acg`, which is now archived and was already legacy/diverged well before that. The acg module lives in lib-foundation at `scripts/lib/acg/` (vendored here under `scripts/lib/foundation/`), so that is where acg fixes go. This finding sat stranded for three months because the deferral named a repo nobody was shipping from — when deprecating a repo, re-point every doc that defers work to it.

**Process note:**
Add to lib-acg spec template: new providers must log credentials as `[set]`/`[empty]` — never log partial values. Code-review checklist should flag any `slice(0, N)` on credential variables.
