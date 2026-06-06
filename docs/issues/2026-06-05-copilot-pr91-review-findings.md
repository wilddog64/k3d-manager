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

**Status:** DEFERRED — `scripts/lib/acg/` is a subtree from lib-acg. This file cannot be edited directly in k3d-manager; the fix must go to lib-acg upstream first, then a subtree pull brings it here. Tracked as lib-acg upstream debt.

**Process note:**
Add to lib-acg spec template: new providers must log credentials as `[set]`/`[empty]` — never log partial values. Code-review checklist should flag any `slice(0, N)` on credential variables.
