# Retrospective — PR #11 (fix/acg-credentials-extend-dialog)

**Date:** 2026-05-17
**PR:** #11 — fix: AWS sandbox credential extraction and dialog handling
**Merged to:** main
**Participants:** Claude, Copilot

## What Went Well
- AWS credential extraction fully functional: `bin/acg-credential-test` writes to `~/.aws/credentials [default]`, validates with `sts:GetCallerIdentity`
- Credential values suppressed from terminal output (tee → redirect fix)
- Copilot caught 3 real issues: missing subtree guard, missing `--diff-filter=ACM`, stale memory-bank description — all fixed before merge
- CI shellcheck + node --check gates in place

## What Went Wrong
- 10 dialog dismiss attempts before settling on WARN fallback:
  - CDP keyboard events silently drop without active tab
  - bringToFront() dismisses iTerm2 visor mode
  - Cancel button unfindable (custom React component, no ARIA role)
  - AppleScript approach was platform-specific and failed with execSync error
  - Settled on bringToFront+Enter with WARN fallback (credentials populate via Extend regardless)
- Codex committed docs to wrong repo (k3d-manager instead of lib-acg code change) — fixed by explicit constraint in handoff block
- Memory-bank had stale "DOM clicks" description not updated as implementation changed

## Process Rules Added
- When redirecting `core.hooksPath`, diff existing hook against new one and port all guards
- Every `git diff --cached --name-only` feeding a file-existence check needs `--diff-filter=ACM`
- For CDP-attached sessions: bringToFront() + keyboard events are unreliable without OS focus; native OS clicks (AppleScript) are platform-specific; WARN fallback is acceptable when credentials populate regardless

## Decisions Made
- WARN fallback for dialog dismiss: acceptable because credentials populate via Extend path whether dialog is dismissed or not
- No AppleScript / platform-specific code: lib-acg must remain cross-platform
- `bin/acg-credential-test` captures stdout (credentials) privately; all status goes to stderr

## Theme
Ten attempts to dismiss a React dialog exposed the limits of CDP-attached browser automation: keyboard events need active tab, mouse events get blocked by React's isTrusted check, and OS-level clicks are platform-specific. The WARN fallback — accepting that the dialog persists but credentials flow regardless — was the right call. The credential write and validation story is clean; the dialog is cosmetic noise.
