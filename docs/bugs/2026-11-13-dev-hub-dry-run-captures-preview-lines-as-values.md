# dev-hub: DRY_RUN=1 captures `[dry-run]` preview lines as command output

**Status:** OPEN
**Priority:** P3 (Claude proposal: only the dev-hub dry run, which fails safe; no real command runs)
**Classified:** pending (Argon, from this doc alone)
**Waiting on:** operator decision — since 2026-11-13
**Introduced by:** b2067ad3 (dev-hub Part A); the preemption read in 3e0ee4ac adds a second instance
**Should have been caught by:** offline test (the bats `_run_command` stub ignores `DRY_RUN`, so the dry-run test never exercises the real override)
**Prior art:** exact-slug glob, no match; `make find-similar-docs` not run (vector store context missing); related: docs/bugs/2026-11-13-dev-hub-b-dry-run-and-untested-probe-paths.md (read first at triage)
**Approval:** pending

## Symptom

Found by the Fable review of 3e0ee4ac, 2026-11-13, by simulating the real wrapper (no cluster). Under `DRY_RUN=1`, `scripts/lib/system_overrides.sh:36-62` prints `[dry-run] <command>` to stdout and returns 0. dev-hub code that captures command output with `$(_run_command ...)` gets the preview line back:
- `_dev_hub_require_host_context` (`scripts/plugins/dev_hub.sh:38-44`) reads `[dry-run] kubectl config current-context` as the context name and errors, so a real `DRY_RUN=1 dev_hub_up` stops there.
- `_dev_hub_apply_host_objects` would read the preview line as the PriorityClass policy and preview a `delete priorityclass` even when the class is absent or already correct.

Same review, test-only gaps: M2 (`dev_hub.bats:270-278`) greps for the delete without the `--context k3d-k3d-cluster` prefix; `[ -n a ] && [ -n b ]` at :275 should be two lines.
