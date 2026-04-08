# Issue: False Dependency on Antigravity IDE for ACG Extensions

## Status
**Identified** (Architectural Debt)

## Description
The ACG Sandbox extension logic (specifically `antigravity_acg_extend` and `acg_watch`) currently resides within the `antigravity.sh` plugin and uses the "Antigravity" naming convention. However, investigation has confirmed that this logic **does not depend on the Antigravity IDE**.

The script `scripts/playwright/acg_extend.js` only requires:
1. Node.js
2. Playwright
3. Google Chrome (controlled via CDP port 9222)

The current structure creates unnecessary complexity and confusion, as the `acg.sh` plugin must source `antigravity.sh`, and background watcher scripts (`acg-watch-run.sh`) must call functions named after an IDE they do not use.

## Root Cause
The ACG extension automation was built using the browser automation "infrastructure" (CDP connection logic, Chrome startup flags, and shared profiles) that was originally developed for Antigravity IDE experiments (such as the now-abandoned GitHub Copilot agent trigger).

## Impact
- **Confusion:** New users or maintainers may believe the Antigravity IDE is required for sandbox lifecycle management.
- **Tightly Coupled Plugins:** `acg.sh` is forced to depend on `antigravity.sh`.
- **Misleading Naming:** Function names do not accurately reflect their dependencies or purpose.

## Recommended Follow-up
1. **Refactor Browser Helpers:** Move general browser automation helpers (`_browser_launch`, `_antigravity_browser_ready`) from `antigravity.sh` to a more appropriate location (e.g., `acg.sh` or a new `browser.sh` plugin).
2. **Rename Functions:** Rename `antigravity_acg_extend` to something more accurate, such as `acg_extend_browser`.
3. **Decouple Plugins:** Remove the `source "${SCRIPT_DIR}/plugins/antigravity.sh"` line from `acg.sh`.
4. **Update Watcher:** Update `acg_watch_start` to generate a wrapper script that calls the renamed, decoupled function.
