# Bug: ACG interaction surface keeps `k3d-manager` coupled to Gemini/browser automation

**Branch:** `k3d-manager-v1.1.0`
**Files Implicated:** `scripts/plugins/acg.sh`, `scripts/plugins/antigravity.sh`, `bin/acg-up`, `bin/acg-refresh`

---

## Summary

`k3d-manager` currently carries an implicit Gemini/browser-automation dependency through the ACG interaction layer. The dependency is not universal across the whole repo, but it is part of the normal ACG-assisted workflow surface.

That makes the ACG subsystem the correct extraction boundary: the `acg_*` commands and browser/session automation should move out together, instead of leaving `k3d-manager` responsible for Gemini-backed ACG interaction.

---

## Why this is a problem

- Cluster orchestration and ACG browser automation are different domains.
- The ACG layer depends on:
  - browser/CDP lifecycle,
  - session/profile handling,
  - interactive sandbox navigation,
  - Gemini-backed prompt execution.
- Those dependencies are not generally required for cluster/provider orchestration.
- As long as they remain inside `k3d-manager`, the repo keeps absorbing ACG-specific failures, testing complexity, and toolchain assumptions.

---

## Current Code Reality

- `scripts/plugins/antigravity.sh` owns `_antigravity_gemini_prompt` and the Gemini-driven browser automation helpers.
- `scripts/plugins/acg.sh` calls into the shared browser launch/session path.
- `bin/acg-up` and `bin/acg-refresh` source `scripts/plugins/antigravity.sh` as part of the current ACG-assisted flow.
- This means Gemini is effectively part of the ACG workflow contract even though it should not be part of core cluster orchestration.

---

## Proposed Fix

1. Treat the full ACG interaction surface as the extraction boundary:
   - `acg_*` commands/functions
   - browser/CDP/session helpers
   - credential extraction / sandbox interaction helpers
   - Gemini-backed automation prompts
2. Keep provider/orchestration logic in `k3d-manager`.
3. Move the Gemini dependency out together with the ACG subsystem so `k3d-manager` no longer needs to own it.

---

## Impact

Medium. This coupling increases maintenance cost, broadens the dependency surface of `k3d-manager`, and makes the repo harder to reason about as an orchestration tool.
