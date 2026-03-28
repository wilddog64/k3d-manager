# Issue: ACG Domain Redirection — 2026-03-28

## Description
The ACG platform URL `https://learn.acloud.guru` is currently redirecting (301) to `https://acg-notice.pluralsight.com/`, which displays a "This page is no longer accessible" notice. This breaks the `_antigravity_ensure_acg_session` login check as it cannot find the expected login elements or dashboard indicators.

## Environment
- Machine: `m4-air.local`
- Branch: `k3d-manager-v0.9.17`
- Browser: Antigravity (CDP port 9222)

## Verbatim Output (E2E Test finding)
```text
Navigating to https://learn.acloud.guru
Final URL: https://acg-notice.pluralsight.com/
Status: 200
ACG_SESSION_NOT_LOGGED_IN
```

## Root Cause
Pluralsight has fully integrated ACG into their platform and seems to have retired the `learn.acloud.guru` domain or at least the specific landing pages used for automation.

## Recommended Follow-up
1.  **Update URLs:** Investigate the new Pluralsight Skills cloud playground URLs (e.g., `https://app.pluralsight.com/cloud-playground/cloud-sandboxes`).
2.  **Plugin Refactor:** Update `scripts/plugins/acg.sh` and `scripts/plugins/antigravity.sh` to target the new Pluralsight domain.
3.  **Selector Update:** Identify new login indicators on the Pluralsight platform.
